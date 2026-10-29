-- ============================================================================
--  biashara_yangu — MODULE 23 bis : CORRECTIFS & MODE SIMPLE
--
--  1) `rpc_entreprise_creer_simple` — CRÉATION DIRECTE EN MODE SIMPLE :
--     le nouveau commerçant obtient son entreprise ET son abonnement d'essai
--     (7 jours, actif immédiatement), sans passer par la double validation
--     gestionnaire → finance. C'est une exception VOLONTAIRE réservée au
--     mode simple : elle évite qu'un débutant attende plusieurs heures avant
--     de pouvoir vendre.
--
--  2) `rpc_ma_tournee` — l'agent ne voit QUE ses consignes (les autres
--     agents ne doivent pas apparaître dans son écran).
--
--  3) `rpc_consigne_enregistrer` / `rpc_bonus_enregistrer` — un client
--     d'une AUTRE entreprise est refusé (lecture du propriétaire via
--     `to_jsonb`, donc compatible avec les anciennes bases).
--
--  4) `rpc_accueil_stats` — ajoute le NOMBRE TOTAL de ventes : le tableau
--     de bord ne mélange plus un total serveur (montants) et un total local
--     (nombre de ventes) qui pouvaient se contredire.
--
--  PRÉ-REQUIS : migrations 0080 (module 23), 0038 (rpc_entreprise_creer v6).
--  ⚠️ IDEMPOTENT.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);

-- Contrôle préalable ---------------------------------------------------------
do $$
begin
  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where p.proname = 'rpc_entreprise_creer' and n.nspname = 'public'
  ) then
    raise exception 'Migration 0038 absente : rpc_entreprise_creer v6 requise.';
  end if;
  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where p.proname = 'rpc_tournee_creer' and n.nspname = 'public'
  ) then
    raise exception 'Migration 0080 absente : exécutez le module 23 avant ce correctif.';
  end if;
end $$;


-- ============================================================================
--  1. CRÉATION SIMPLE : ENTREPRISE + ABONNEMENT D'ESSAI ACTIF
-- ============================================================================

create or replace function public.rpc_entreprise_creer_simple(
  p_nom       text default null,
  p_telephone text default null,
  p_type      text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user  uuid := auth.uid();
  v_res   jsonb;
  v_id    uuid;
  v_deja  boolean;
  v_fin   timestamptz := now() + interval '7 days';
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour créer votre entreprise.';
  end if;

  -- Création standard (nom, type validé, espace, rattachement, rôle).
  v_res := public.rpc_entreprise_creer(
    p_nom,
    p_telephone,
    coalesce(nullif(btrim(coalesce(p_type, '')), ''), 'boutique')
  );

  v_id := nullif(v_res->>'entreprise_id', '')::uuid;
  v_deja := coalesce((v_res->>'deja')::boolean, false);

  if v_id is null then
    raise exception 'CREATION_IMPOSSIBLE|L''entreprise n''a pas pu être créée.';
  end if;

  -- Déjà rattaché : on ne modifie pas un dossier existant (il garde son
  -- état d'activation et son abonnement en cours).
  if v_deja then
    return v_res || jsonb_build_object('mode', 'simple', 'essai', false);
  end if;

  -- MODE SIMPLE : l'essai de 7 jours est ACTIF tout de suite. Le compte peut
  -- vendre, encaisser et créer ses produits immédiatement. Aucun montant
  -- n'est réclamé pendant l'essai.
  update public.entreprises
     set activation_etape = 'actif',
         statut = 'ESSAI_7J'::public.statut_abonnement_enum,
         date_activation = now(),
         date_expiration = v_fin,
         montant_total_du = 0,
         montant_deja_paye = 0,
         updated_at = now()
   where id = v_id;

  -- Traçabilité du dossier : la soumission reste, l'activation automatique
  -- est ajoutée en clair (un auditeur doit pouvoir expliquer l'exception).
  begin
    insert into public.activations_entreprise (
      entreprise_id, etape, acteur_id, acteur_role, note
    ) values (
      v_id, 'paiement_finance', v_user, public.mon_role(),
      'Activation AUTOMATIQUE — mode simple (essai 7 jours)'
    );
  exception when others then
    -- Une table d'historique absente ne doit pas priver le commerçant de
    -- son entreprise : l'état de `entreprises` fait foi.
    null;
  end;

  begin
    insert into public.journal_audit (entreprise_id, action, utilisateur_id, details)
    values (
      null, 'ACTIVATION_AUTO_ESSAI', v_user,
      jsonb_build_object(
        'entreprise_id', v_id,
        'mode', 'simple',
        'essai_jours', 7,
        'date_expiration', v_fin
      )
    );
  exception when others then null;
  end;

  return v_res || jsonb_build_object(
    'mode', 'simple',
    'essai', true,
    'essai_jours', 7,
    'date_expiration', v_fin,
    'activation_etape', 'actif'
  );
end;
$$;

comment on function public.rpc_entreprise_creer_simple(text, text, text) is
  'Mode simple : crée l''entreprise et ACTIVE immédiatement un essai de 7 jours (sans double validation).';

revoke all on function public.rpc_entreprise_creer_simple(text, text, text) from public;
revoke all on function public.rpc_entreprise_creer_simple(text, text, text) from anon;
grant execute on function public.rpc_entreprise_creer_simple(text, text, text) to authenticated;


-- ============================================================================
--  2. « MA TOURNÉE » — LES CONSIGNES DE L'AGENT UNIQUEMENT
-- ============================================================================

create or replace function public.rpc_ma_tournee()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user  uuid := auth.uid();
  v_t     public.tournees%rowtype;
  v_debut timestamptz :=
    (date_trunc('day', now() at time zone 'Africa/Lubumbashi'))
      at time zone 'Africa/Lubumbashi';
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour voir votre tournée.';
  end if;

  select * into v_t
    from public.tournees
   where agent_id = v_user
     and statut in ('preparee', 'en_cours')
   order by date_tournee desc, cree_le desc
   limit 1;

  if not found then
    return jsonb_build_object('ok', false, 'motif', 'AUCUNE_TOURNEE');
  end if;

  return jsonb_build_object(
    'ok', true,
    'tournee', jsonb_build_object(
      'id', v_t.id,
      'reference', v_t.reference,
      'date_tournee', v_t.date_tournee,
      'zone', v_t.zone,
      'statut', v_t.statut,
      'note', v_t.note
    ),
    'lignes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'produit_id', l.produit_id,
        'nom', l.nom_produit,
        'unite', l.unite,
        'attribuee', l.quantite_attribuee,
        'vendue', l.quantite_vendue,
        'retournee', l.quantite_retournee,
        'restante', l.quantite_attribuee - l.quantite_vendue - l.quantite_retournee,
        'prix_vente', l.prix_vente
      ) order by l.nom_produit)
      from public.tournee_lignes l
      where l.tournee_id = v_t.id
    ), '[]'::jsonb),
    -- COHÉRENCE : seules les consignes de CET agent (ou de sa tournée)
    -- s'affichent. Voir celles d'un collègue n'a aucun sens pour lui.
    'consignes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', c.id,
        'client_id', c.client_id,
        'client_nom', c.client_nom,
        'zone', c.zone,
        'libelle', c.libelle_contenant,
        'quantite', c.quantite,
        'recuperee', c.quantite_recuperee,
        'restante', c.quantite - c.quantite_recuperee,
        'statut', c.statut,
        'date', c.date_consigne
      ) order by c.date_consigne desc)
      from public.consignes c
      where c.owner_id = v_t.owner_id
        and (c.agent_id = v_user or c.tournee_id = v_t.id)
        and c.statut in ('chez_client', 'partielle')
    ), '[]'::jsonb),
    -- « Aujourd'hui » = jour LOCAL (Lubumbashi), pas le jour UTC du serveur.
    'bonus', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', b.id,
        'client_nom', b.client_nom,
        'nature', b.nature,
        'montant', b.montant,
        'description', b.description,
        'date', b.date_bonus
      ) order by b.date_bonus desc)
      from public.bonus_clients b
      where b.agent_id = v_user
        and b.date_bonus >= v_debut
    ), '[]'::jsonb)
  );
end;
$$;


-- ============================================================================
--  3. CONSIGNES / BONUS — LE CLIENT DOIT APPARTENIR À L'ENTREPRISE
-- ============================================================================
--  `to_jsonb(c)->>'owner_id'` évite de dépendre de l'existence de la colonne
--  (les anciennes bases n'ont pas toutes `clients.owner_id`). Absence de
--  propriétaire = client hérité, accepté ; propriétaire différent = refusé.

create or replace function public.rpc_consigne_enregistrer(
  p_client_id  bigint default null,
  p_client_nom text default null,
  p_zone       text default null,
  p_libelle    text default 'Récipient',
  p_quantite   integer default 1,
  p_note       text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user    uuid := auth.uid();
  v_owner   uuid;
  v_id      uuid := gen_random_uuid();
  v_nom     text;
  v_zone    text;
  v_tournee uuid;
  v_prop    text;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour enregistrer une consigne.';
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  if not (v_user = v_owner
          or exists (select 1 from public.utilisateurs u
                      where u.id = v_user and u.parent_id = v_owner)
          or public.est_plateforme()) then
    raise exception 'DROIT_REFUSE|Vous n''appartenez pas à cette entreprise.';
  end if;

  if coalesce(p_quantite, 0) <= 0 then
    raise exception 'QUANTITE_INVALIDE|Indiquez au moins un récipient.';
  end if;

  select nullif(btrim(coalesce(p_client_nom, '')), '') into v_nom;
  select nullif(btrim(coalesce(p_zone, '')), '') into v_zone;

  if p_client_id is not null then
    select c.nom,
           nullif(btrim(coalesce(p_zone, c.zone, '')), ''),
           to_jsonb(c)->>'owner_id'
      into v_nom, v_zone, v_prop
      from public.clients c
     where c.id = p_client_id;

    if not found then
      raise exception 'CLIENT_INTROUVABLE|Ce client n''existe plus.';
    end if;

    if v_prop is not null and v_prop <> v_owner::text and not public.est_plateforme() then
      raise exception 'HORS_BOUTIQUE|Ce client appartient à une autre entreprise.';
    end if;

    if v_zone is not null then
      update public.clients set zone = v_zone where id = p_client_id;
    end if;
  end if;

  select t.id into v_tournee
    from public.tournees t
   where t.agent_id = v_user and t.statut = 'en_cours'
   order by t.date_tournee desc
   limit 1;

  insert into public.consignes (
    id, owner_id, agent_id, client_id, client_nom, zone, tournee_id,
    libelle_contenant, quantite, note
  ) values (
    v_id, v_owner, v_user, p_client_id, v_nom, v_zone, v_tournee,
    coalesce(nullif(btrim(coalesce(p_libelle, '')), ''), 'Récipient'),
    p_quantite, nullif(btrim(coalesce(p_note, '')), '')
  );

  begin
    insert into public.journal_audit (
      id, entreprise_id, action, utilisateur_id, details, created_at
    ) values (
      gen_random_uuid(), null, 'CONSIGNE_AJOUTEE', v_user,
      jsonb_build_object('consigne', v_id, 'client', v_nom,
                         'quantite', p_quantite, 'zone', v_zone),
      now()
    );
  exception when others then null;
  end;

  return jsonb_build_object('ok', true, 'id', v_id, 'quantite', p_quantite);
end;
$$;


create or replace function public.rpc_bonus_enregistrer(
  p_client_id    bigint default null,
  p_client_nom   text default null,
  p_nature       text default 'remise',
  p_montant      numeric default 0,
  p_description  text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user    uuid := auth.uid();
  v_owner   uuid;
  v_id      uuid := gen_random_uuid();
  v_nom     text;
  v_nature  text := lower(btrim(coalesce(p_nature, 'remise')));
  v_tournee uuid;
  v_prop    text;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour enregistrer un bonus.';
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  if not (v_user = v_owner
          or exists (select 1 from public.utilisateurs u
                      where u.id = v_user and u.parent_id = v_owner)
          or public.est_plateforme()) then
    raise exception 'DROIT_REFUSE|Vous n''appartenez pas à cette entreprise.';
  end if;

  if v_nature not in ('remise', 'cadeau', 'fidelite', 'autre') then
    raise exception 'NATURE_INVALIDE|Type de bonus inconnu.';
  end if;

  if coalesce(p_montant, 0) < 0 then
    raise exception 'MONTANT_INVALIDE|Le montant du bonus ne peut pas être négatif.';
  end if;

  select nullif(btrim(coalesce(p_client_nom, '')), '') into v_nom;

  if p_client_id is not null then
    select c.nom, to_jsonb(c)->>'owner_id'
      into v_nom, v_prop
      from public.clients c
     where c.id = p_client_id;

    if not found then
      raise exception 'CLIENT_INTROUVABLE|Ce client n''existe plus.';
    end if;

    if v_prop is not null and v_prop <> v_owner::text and not public.est_plateforme() then
      raise exception 'HORS_BOUTIQUE|Ce client appartient à une autre entreprise.';
    end if;
  end if;

  select t.id into v_tournee
    from public.tournees t
   where t.agent_id = v_user and t.statut = 'en_cours'
   order by t.date_tournee desc
   limit 1;

  insert into public.bonus_clients (
    id, owner_id, agent_id, client_id, client_nom, tournee_id,
    nature, montant, description
  ) values (
    v_id, v_owner, v_user, p_client_id, v_nom, v_tournee,
    v_nature, coalesce(p_montant, 0),
    nullif(btrim(coalesce(p_description, '')), '')
  );

  begin
    insert into public.journal_audit (
      id, entreprise_id, action, utilisateur_id, details, created_at
    ) values (
      gen_random_uuid(), null, 'BONUS_CLIENT', v_user,
      jsonb_build_object('bonus', v_id, 'client', v_nom,
                         'nature', v_nature, 'montant', p_montant),
      now()
    );
  exception when others then null;
  end;

  return jsonb_build_object('ok', true, 'id', v_id);
end;
$$;


-- ============================================================================
--  4. ACCUEIL — NOMBRE TOTAL DE VENTES + UNE SEULE LECTURE PAR TABLE
-- ============================================================================
--  Performance : l'ancienne version lançait cinq sous-requêtes séparées sur
--  `ventes` (un balayage par sous-requête). Ici, UN seul agrégat par table.
--  Les index ci-dessous couvrent les filtres utilisés.

create index if not exists idx_produits_owner
  on public.produits (owner_id);
create index if not exists idx_ventes_owner
  on public.ventes (owner_id);

create or replace function public.rpc_accueil_stats()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user         uuid := auth.uid();
  v_owner        uuid;
  v_debut        timestamptz :=
    (date_trunc('day', now() at time zone 'Africa/Lubumbashi'))
      at time zone 'Africa/Lubumbashi';
  v_produits     bigint := 0;
  v_alertes      bigint := 0;
  v_ventes_jour  bigint := 0;
  v_ventes_total bigint := 0;
  v_ca_jour      numeric := 0;
  v_ca_total     numeric := 0;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  -- Une seule lecture des produits.
  select count(*),
         count(*) filter (
           where not coalesce(p.stock_illimite, false)
             and coalesce(p.quantite, 0) <= coalesce(p.seuil_alerte, 5)
         )
    into v_produits, v_alertes
    from public.produits p
   where p.owner_id = v_owner;

  -- Une seule lecture des ventes : jour, total, CA jour, CA total.
  select count(*) filter (where v.date >= v_debut),
         count(*),
         coalesce(sum(v.prix) filter (where v.date >= v_debut), 0),
         coalesce(sum(v.prix), 0)
    into v_ventes_jour, v_ventes_total, v_ca_jour, v_ca_total
    from public.ventes v
   where v.owner_id = v_owner;

  return jsonb_build_object(
    'ok', true,
    'produits', v_produits,
    'stock_alertes', v_alertes,
    'ventes_jour', v_ventes_jour,
    'ventes_total', v_ventes_total,
    'ca_jour', v_ca_jour,
    'ca_total', v_ca_total
  );
end;
$$;

revoke all on function public.rpc_accueil_stats() from public;
grant execute on function public.rpc_accueil_stats() to authenticated;


-- ============================================================================
--  5. VÉRIFICATIONS
-- ============================================================================

select proname
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and proname in ('rpc_entreprise_creer_simple', 'rpc_ma_tournee',
                   'rpc_consigne_enregistrer', 'rpc_bonus_enregistrer',
                   'rpc_accueil_stats')
 order by proname;
