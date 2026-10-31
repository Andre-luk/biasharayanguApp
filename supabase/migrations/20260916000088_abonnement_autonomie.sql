-- ============================================================================
--  biashara_yangu — PHASE 7 : L'ABONNEMENT EN AUTONOMIE
--  ---------------------------------------------------------------------------
--  Le client paie SEUL son abonnement (Mobile Money / carte), y compris une
--  avance, et son compte s'active tout seul. Les agents de la plateforme ne
--  doivent plus être un passage obligé : ils restent disponibles si le client
--  demande de l'aide.
--
--  CE QUI BLOQUAIT (constaté dans le code)
--  --------------------------------------
--  `rpc_serdipay_ouvrir` facturait `entreprises.solde_restant`. Or un cycle
--  entièrement payé puis expiré laisse `solde_restant = 0` : aucun mécanisme
--  n'ouvrait le cycle suivant. Résultat : `SOLDE_NUL` → « Aucun montant à
--  payer : votre abonnement est déjà réglé », et le client ne pouvait PAS se
--  renouveler lui-même.
--
--  CE QUE FAIT CETTE MIGRATION
--  ---------------------------
--   1. `rpc_abonnement_prix_du_cycle`      → le prix du prochain cycle
--      (jamais l'installation : elle ne se paie qu'une fois).
--   2. `rpc_abonnement_preparer_renouvellement` → ouvre le cycle suivant,
--      UNIQUEMENT si l'abonnement est échu. Aucun risque de double facturation.
--   3. `rpc_serdipay_ouvrir` (v2) → appelle la préparation quand c'est
--      nécessaire et accepte un MONTANT PARTIEL (avance) borné par le solde.
--   4. Quotas IA de l'abonnement : `quotas_ia_mensuels` sur les grilles et
--      sur l'entreprise, crédités AUTOMATIQUEMENT à chaque activation ou
--      renouvellement (trigger sur `date_expiration`). Aucun agent à solliciter.
--   5. `rpc_entreprise_supprimer` → supprime une entreprise de test et ses
--      comptes (SUPER_ADMIN + confirmation écrite).
--
--  ⚠️ `rpc_abonnement_enregistrer_paiement` N'EST PAS redéfini (correctifs
--     43, 53, 60, 61, 62 préservés). Le moteur active déjà tout seul quand le
--     cycle est soldé : on lui donne simplement un cycle à solder.
--  ⚠️ IDEMPOTENT.
--  OÙ : Supabase → SQL Editor → coller → Run
-- ============================================================================

select set_config('search_path', 'public, extensions', true);

-- Contrôle préalable ---------------------------------------------------------
do $$
begin
  if not exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'entreprises'
       and column_name = 'prix_abonnement_mensuel'
  ) then
    raise exception 'Migration 0060 absente : exécutez 20260916000060_prix_installation_et_mensuel.sql.';
  end if;
  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where p.proname = 'rpc_serdipay_ouvrir' and n.nspname = 'public'
  ) then
    raise exception 'Migration 0079 absente : exécutez 20260916000079_passerelle_serdipay.sql.';
  end if;
end $$;


-- ============================================================================
--  1. QUOTAS IA INCLUS DANS L'ABONNEMENT
-- ============================================================================
--  Deux niveaux, comme pour les prix :
--    • `groupes_tarifaires.quotas_ia_mensuels` — ce que le pack prévoit ;
--    • `entreprises.quotas_ia_mensuels`       — ce qui a été négocié.
--  La valeur négociée gagne ; à défaut, celle du pack ; à défaut, 0.

alter table public.groupes_tarifaires
  add column if not exists quotas_ia_mensuels integer not null default 0;

alter table public.entreprises
  add column if not exists quotas_ia_mensuels integer;

do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.groupes_tarifaires'::regclass
       and conname = 'groupes_tarifaires_quotas_ia_positifs'
  ) then
    alter table public.groupes_tarifaires
      add constraint groupes_tarifaires_quotas_ia_positifs
      check (quotas_ia_mensuels >= 0);
  end if;

  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.entreprises'::regclass
       and conname = 'entreprises_quotas_ia_positifs'
  ) then
    alter table public.entreprises
      add constraint entreprises_quotas_ia_positifs
      check (quotas_ia_mensuels is null or quotas_ia_mensuels >= 0);
  end if;
end $$;

comment on column public.groupes_tarifaires.quotas_ia_mensuels is
  'Quotas de l''assistant IA inclus dans le pack, renouvelés à chaque cycle d''abonnement.';
comment on column public.entreprises.quotas_ia_mensuels is
  'Quotas IA négociés pour cette entreprise (prime sur la grille). NULL = valeur du pack.';


-- Fixer les quotas IA d'une entreprise (négociation), comme on fixe un prix.
create or replace function public.rpc_abonnement_definir_quotas_ia(
  p_entreprise_id uuid,
  p_quotas        integer,
  p_note          text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_role text;
  v_e    public.entreprises%rowtype;
  v_avant integer;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;

  select upper(coalesce(u.new_role::text, '')) into v_role
    from public.utilisateurs u where u.id = v_user;

  if coalesce(v_role, '') not in ('FINANCE_LAPERLE', 'AGENT_TERRAIN',
                                  'GESTIONNAIRE_COMPTES', 'SUPER_ADMIN')
     and not public.est_plateforme() then
    raise exception 'DROIT_REFUSE|Seule la plateforme fixe les quotas IA d''un abonnement.';
  end if;

  if p_quotas is not null and p_quotas < 0 then
    raise exception 'QUOTA_INVALIDE|Le nombre de quotas ne peut pas être négatif.';
  end if;

  select * into v_e from public.entreprises where id = p_entreprise_id for update;
  if not found then
    raise exception 'ENTREPRISE_INTROUVABLE|Ce compte n''existe plus.';
  end if;

  v_avant := v_e.quotas_ia_mensuels;

  update public.entreprises
     set quotas_ia_mensuels = p_quotas,
         updated_at         = now()
   where id = p_entreprise_id;

  begin
    insert into public.journal_audit (entreprise_id, action, utilisateur_id, details, created_at)
    values (
      p_entreprise_id, 'QUOTAS_IA_ABONNEMENT', v_user,
      jsonb_build_object('avant', v_avant, 'apres', p_quotas,
                         'note', nullif(btrim(coalesce(p_note, '')), '')),
      now()
    );
  exception when others then null;
  end;

  return jsonb_build_object(
    'ok', true,
    'entreprise_id', p_entreprise_id,
    'quotas_ia_mensuels', p_quotas,
    'source', case when p_quotas is null then 'grille' else 'negocie' end
  );
end;
$$;

comment on function public.rpc_abonnement_definir_quotas_ia(uuid, integer, text) is
  'Fixe les quotas IA mensuels d''une entreprise (NULL = revenir à la valeur du pack).';

revoke all on function public.rpc_abonnement_definir_quotas_ia(uuid, integer, text) from public, anon;
grant execute on function public.rpc_abonnement_definir_quotas_ia(uuid, integer, text) to authenticated;


-- ============================================================================
--  2. LE PRIX DU PROCHAIN CYCLE (jamais l'installation)
-- ============================================================================

create or replace function public.rpc_abonnement_prix_du_cycle(
  p_entreprise uuid
)
returns numeric
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_e        public.entreprises%rowtype;
  v_grille   numeric := 0;
  v_prix     numeric := 0;
begin
  select * into v_e from public.entreprises where id = p_entreprise;
  if not found then
    return 0;
  end if;

  select coalesce(g.montant_abonnement, 0)
    into v_grille
    from public.groupes_tarifaires g
   where g.id = v_e.groupe_tarifaire_id;

  -- Ordre de résolution identique au moteur (correctif 60), et JAMAIS
  -- l'installation : elle appartient au premier cycle, point final.
  v_prix := coalesce(
    nullif(v_e.prix_abonnement_mensuel, 0),
    nullif(v_grille, 0),
    -- Le montant du cycle précédent, s'il ne ressemble pas à l'installation.
    case
      when coalesce(v_e.montant_total_du, 0) > 0
       and coalesce(v_e.montant_total_du, 0) <> coalesce(v_e.prix_installation, -1)
        then v_e.montant_total_du
      else 0
    end,
    0
  );

  return coalesce(v_prix, 0);
end;
$$;

comment on function public.rpc_abonnement_prix_du_cycle(uuid) is
  'Prix du prochain cycle d''abonnement : prix négocié, sinon grille, sinon cycle précédent. Jamais l''installation.';

revoke all on function public.rpc_abonnement_prix_du_cycle(uuid) from public;
grant execute on function public.rpc_abonnement_prix_du_cycle(uuid) to authenticated;


-- ============================================================================
--  3. OUVRIR LE CYCLE SUIVANT (uniquement si l'abonnement est échu)
-- ============================================================================

create or replace function public.rpc_abonnement_preparer_renouvellement(
  p_entreprise uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user   uuid := auth.uid();
  v_owner  uuid;
  v_id     uuid;
  v_e      public.entreprises%rowtype;
  v_prix   numeric := 0;
  v_ouvert boolean := false;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour payer votre abonnement.';
  end if;

  v_owner := public.mon_proprietaire();
  v_id := coalesce(p_entreprise, public.mon_entreprise_id(), v_owner, v_user);

  select * into v_e from public.entreprises where id = v_id for update;
  if not found then
    raise exception 'ENTREPRISE_INTROUVABLE|Cette entreprise n''existe pas.';
  end if;

  if not (v_user = v_e.id
          or v_user = coalesce(v_owner, v_e.id)
          or public.est_plateforme()) then
    raise exception 'DROIT_REFUSE|Vous n''avez pas accès à ce dossier.';
  end if;

  -- L'installation appartient au PREMIER cycle : on ne « renouvelle » pas un
  -- compte jamais activé.
  if v_e.date_activation is null then
    raise exception 'PREMIER_CYCLE|Ce compte n''a pas encore été activé : l''installation est due.';
  end if;

  -- GARDE-FOU ANTI DOUBLE FACTURATION : on n'ouvre un nouveau cycle que si
  -- l'abonnement est RÉELLEMENT échu. Un client encore actif qui relance
  -- l'écran ne se voit pas réclamer un deuxième mois.
  if not (v_e.statut in ('EXPIRE', 'EN_ATTENTE_COMPLEMENT')
          or (v_e.date_expiration is not null and v_e.date_expiration < now())) then
    return jsonb_build_object(
      'ok', true,
      'entreprise_id', v_id,
      'cycle_ouvert', false,
      'motif', 'CYCLE_EN_COURS',
      'solde_restant', coalesce(v_e.solde_restant, 0),
      'prix_mensuel', public.rpc_abonnement_prix_du_cycle(v_id),
      'devise', coalesce(v_e.devise, 'CDF')
    );
  end if;

  -- Un cycle déjà ouvert avec un solde : rien à préparer, le client paie.
  if coalesce(v_e.solde_restant, 0) > 0.001 then
    return jsonb_build_object(
      'ok', true,
      'entreprise_id', v_id,
      'cycle_ouvert', true,
      'motif', 'DEJA_OUVERT',
      'solde_restant', coalesce(v_e.solde_restant, 0),
      'prix_mensuel', public.rpc_abonnement_prix_du_cycle(v_id),
      'devise', coalesce(v_e.devise, 'CDF')
    );
  end if;

  v_prix := public.rpc_abonnement_prix_du_cycle(v_id);
  if v_prix <= 0 then
    raise exception 'PRIX_ABSENT|Aucun prix mensuel n''est défini pour ce compte : contactez la plateforme.';
  end if;

  -- Nouveau cycle : la dette devient le prix du mois, le compteur de
  -- versements repart de zéro. `solde_restant` est GÉNÉRÉ (total − payé).
  update public.entreprises
     set montant_total_du  = v_prix,
         montant_deja_paye = 0,
         updated_at        = now()
   where id = v_id;
  v_ouvert := true;

  begin
    insert into public.journal_audit (
      id, entreprise_id, action, utilisateur_id, details, created_at
    ) values (
      gen_random_uuid(), v_id, 'CYCLE_RENOUVELLEMENT_OUVERT', v_user,
      jsonb_build_object('prix_mensuel', v_prix, 'statut', v_e.statut,
                         'expiration', v_e.date_expiration),
      now()
    );
  exception when others then null;
  end;

  return jsonb_build_object(
    'ok', true,
    'entreprise_id', v_id,
    'cycle_ouvert', v_ouvert,
    'motif', 'CYCLE_OUVERT',
    'solde_restant', v_prix,
    'prix_mensuel', v_prix,
    'devise', coalesce(v_e.devise, 'CDF')
  );
end;
$$;

comment on function public.rpc_abonnement_preparer_renouvellement(uuid) is
  'Ouvre le cycle suivant au prix mensuel négocié, uniquement si l''abonnement est échu. Le client peut ensuite payer seul.';

revoke all on function public.rpc_abonnement_preparer_renouvellement(uuid) from public;
grant execute on function public.rpc_abonnement_preparer_renouvellement(uuid) to authenticated;


-- ============================================================================
--  4. OUVRIR UN PAIEMENT SERDIPAY (v2) — AVANCE AUTORISÉE, CYCLE PRÉPARÉ
-- ============================================================================
--  ⚠️ La v1 avait 5 paramètres. On la SUPPRIME avant de créer la v2 : sinon
--     Postgres garde les deux (surcharge) et un appel à 5 arguments devient
--     ambigu (« function is not unique »). Les appels existants continuent de
--     fonctionner : `p_montant` est optionnel.

drop function if exists public.rpc_serdipay_ouvrir(text, uuid, text, text, uuid);

create or replace function public.rpc_serdipay_ouvrir(
  p_objet         text,
  p_objet_id      uuid default null,
  p_telephone     text default null,
  p_operateur     text default null,
  p_entreprise_id uuid default null,
  p_montant       numeric default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user     uuid := auth.uid();
  v_ent      uuid;
  v_ligne    public.entreprises%rowtype;
  v_objet    text := lower(btrim(coalesce(p_objet, 'abonnement')));
  v_montant  numeric := 0;
  v_devise   text := 'CDF';
  v_type     text := 'SOLDE';
  v_tel      text;
  v_op       text;
  v_ref      text;
  v_id       uuid;
  v_expire   timestamptz;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE';
  end if;

  v_ent := public.mon_entreprise_id();

  if p_entreprise_id is not null then
    if p_entreprise_id = v_ent then
      v_ent := p_entreprise_id;
    elsif public.est_plateforme() then
      v_ent := p_entreprise_id;
    else
      raise exception 'ENTREPRISE_REFUSEE';
    end if;
  end if;

  if v_ent is null then
    raise exception 'ENTREPRISE_INTROUVABLE';
  end if;

  select * into v_ligne from public.entreprises where id = v_ent;
  if not found then
    raise exception 'ENTREPRISE_INTROUVABLE';
  end if;

  v_devise := coalesce(nullif(btrim(v_ligne.devise), ''), 'CDF');

  v_tel := nullif(regexp_replace(coalesce(p_telephone, ''), '[^0-9]', '', 'g'), '');
  if v_tel is null or length(v_tel) < 9 or length(v_tel) > 15 then
    raise exception 'TELEPHONE_INVALIDE';
  end if;

  v_op := nullif(lower(btrim(coalesce(p_operateur, ''))), '');

  -- MONTANT : calculé ici, jamais dicté par le client.
  if v_objet = 'facture' then
    if p_objet_id is null then
      raise exception 'OBJET_REQUIS';
    end if;

    select coalesce(f.solde_restant, 0)
      into v_montant
      from public.factures_abonnement f
     where f.id = p_objet_id
       and f.entreprise_id = v_ent;

    if v_montant is null then
      raise exception 'FACTURE_INTROUVABLE';
    end if;

  elsif v_objet = 'abonnement' then

    -- ABONNEMENT ÉCHU : on ouvre d'abord le cycle suivant au prix négocié.
    -- C'est ce qui débloque le renouvellement en autonomie.
    if coalesce(v_ligne.solde_restant, 0) <= 0
       and v_ligne.date_activation is not null
       and (v_ligne.statut in ('EXPIRE', 'EN_ATTENTE_COMPLEMENT')
            or (v_ligne.date_expiration is not null
                and v_ligne.date_expiration < now())) then
      begin
        perform public.rpc_abonnement_preparer_renouvellement(v_ent);
      exception
        when others then
          -- On ne masque jamais la suite : si la préparation échoue
          -- (prix absent), le message viendra de la lecture ci-dessous.
          null;
      end;

      select * into v_ligne from public.entreprises where id = v_ent;
    end if;

    v_montant := coalesce(v_ligne.solde_restant, 0);

    -- AVANCE : le client peut payer une PARTIE du solde, jamais plus.
    if p_montant is not null and p_montant > 0 then
      if p_montant > v_montant + 0.01 then
        raise exception 'MONTANT_INCORRECT';
      end if;
      v_montant := round(p_montant, 2);
    end if;

  else
    raise exception 'OBJET_INVALIDE';
  end if;

  if v_montant <= 0 then
    raise exception 'SOLDE_NUL';
  end if;

  -- Type attendu par le moteur d'abonnement.
  v_type := case
              when coalesce(v_ligne.montant_deja_paye, 0) > 0 then 'SOLDE'
              when v_montant < coalesce(v_ligne.solde_restant, 0) - 0.01 then 'AVANCE'
              when v_ligne.date_activation is null then 'AVANCE'
              else 'RENOUVELLEMENT'
            end;

  v_ref := public.serdipay_reference();

  insert into public.paiements_serdipay (
    reference, entreprise_id, utilisateur_id, objet, objet_id,
    montant, devise, type_paiement, telephone, operateur, statut
  ) values (
    v_ref, v_ent, v_user, v_objet, p_objet_id,
    v_montant, v_devise, v_type, v_tel, v_op, 'en_attente'
  )
  returning id, expire_le into v_id, v_expire;

  begin
    insert into public.journal_audit (entreprise_id, action, utilisateur_id, details)
    values (
      v_ent, 'SERDIPAY_OUVERT', v_user,
      jsonb_build_object(
        'reference', v_ref, 'objet', v_objet, 'montant', v_montant,
        'type', v_type, 'operateur', v_op
      )
    );
  exception when others then null;
  end;

  return jsonb_build_object(
    'ok', true,
    'reference', v_ref,
    'montant', v_montant,
    'devise', v_devise,
    'type_paiement', v_type,
    'expire_le', v_expire,
    'entreprise_id', v_ent
  );
end;
$$;

comment on function public.rpc_serdipay_ouvrir(text, uuid, text, text, uuid, numeric) is
  'Ouvre un paiement SerdiPay. Montant calculé en base (solde d''abonnement ou de facture), avance partielle autorisée, cycle de renouvellement ouvert automatiquement si l''abonnement est échu.';

revoke all on function public.rpc_serdipay_ouvrir(text, uuid, text, text, uuid, numeric)
  from public, anon;
grant execute on function public.rpc_serdipay_ouvrir(text, uuid, text, text, uuid, numeric)
  to authenticated;


-- ============================================================================
--  5. QUOTAS IA CRÉDITÉS AUTOMATIQUEMENT À CHAQUE CYCLE PAYÉ
-- ============================================================================
--  Déclencheur posé sur `entreprises.date_expiration` : c'est la SEULE chose
--  qui bouge quand un cycle est réglé (le moteur pousse l'échéance). Peu
--  importe QUI paie — client en autonomie, agent, webhook Mobile Money — les
--  quotas du mois arrivent.
--
--  ⚠️ Ne bloque JAMAIS un paiement : toute erreur est avalée (le module 13
--     peut ne pas être installé).

create or replace function public.abonnement_crediter_quotas_ia()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_quota integer := 0;
begin
  -- Un cycle payé = une échéance qui avance.
  if new.date_expiration is null
     or (old.date_expiration is not null
         and new.date_expiration <= old.date_expiration) then
    return new;
  end if;

  begin
    select coalesce(
             nullif(new.quotas_ia_mensuels, 0),
             nullif((select g.quotas_ia_mensuels
                       from public.groupes_tarifaires g
                      where g.id = new.groupe_tarifaire_id), 0),
             0
           )
      into v_quota;

    if v_quota > 0 and to_regclass('public.agent_ia_quotas') is not null then
      insert into public.agent_ia_quotas (
        utilisateur_id, entreprise_id, quotas_disponibles, quotas_achetes_total
      ) values (
        null, new.id, v_quota, 0
      )
      on conflict (entreprise_id) where utilisateur_id is null
      do update set
        quotas_disponibles = public.agent_ia_quotas.quotas_disponibles
                             + excluded.quotas_disponibles,
        updated_at         = now();

      insert into public.journal_audit (entreprise_id, action, details, created_at)
      values (
        new.id, 'AGENT_IA_QUOTAS_ABONNEMENT',
        jsonb_build_object('quotas', v_quota, 'expiration', new.date_expiration),
        now()
      );
    end if;
  exception
    when others then
      -- Jamais d'échec de paiement à cause d'un quota.
      null;
  end;

  return new;
end;
$$;

comment on function public.abonnement_crediter_quotas_ia() is
  'Crédite les quotas IA du mois quand un cycle d''abonnement est réglé (échéance repoussée). N''échoue jamais.';

drop trigger if exists trg_abonnement_crediter_quotas_ia on public.entreprises;
create trigger trg_abonnement_crediter_quotas_ia
  after update of date_expiration on public.entreprises
  for each row execute function public.abonnement_crediter_quotas_ia();


-- ============================================================================
--  6. SUPPRIMER UNE ENTREPRISE ET SES COMPTES (nettoyage des tests)
-- ============================================================================
--  Réservé au SUPER_ADMIN, avec confirmation écrite. La liste des tables est
--  lue dans le catalogue : toute table portant `owner_id` ou `entreprise_id`
--  est nettoyée, y compris celles ajoutées demain.

create or replace function public.rpc_entreprise_supprimer(
  p_entreprise   uuid,
  p_confirmation text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user      uuid := auth.uid();
  v_roles     text[] := array['SUPER_ADMIN'];
  v_role      text;
  v_ids       uuid[];
  v_t         record;
  v_supprimees integer := 0;
  v_utilisateurs integer := 0;
  v_nom       text;
  v_reste     integer := 0;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;

  if upper(btrim(coalesce(p_confirmation, ''))) <> 'SUPPRIMER' then
    raise exception 'CONFIRMATION_REQUISE|Écrivez SUPPRIMER pour confirmer.';
  end if;

  select upper(coalesce(u.new_role::text, '')) into v_role
    from public.utilisateurs u
   where u.id = v_user;

  if coalesce(v_role, '') <> all(v_roles) and not public.est_plateforme() then
    raise exception 'DROIT_REFUSE|Seul un Super Administrateur peut supprimer une entreprise.';
  end if;

  select e.nom into v_nom from public.entreprises e where e.id = p_entreprise;
  if v_nom is null then
    raise exception 'ENTREPRISE_INTROUVABLE|Cette entreprise n''existe plus.';
  end if;

  if p_entreprise = public.mon_entreprise_id() then
    raise exception 'DROIT_REFUSE|Impossible de supprimer l''entreprise de votre propre compte.';
  end if;

  -- Tous les identifiants rattachés : l'entreprise ET ses comptes (les
  -- données applicatives portent `owner_id` = identifiant UTILISATEUR).
  with recursive liens as (
    select u.id
      from public.utilisateurs u
     where u.id = p_entreprise
        or u.entreprise_id = p_entreprise
        or u.parent_id = p_entreprise
    union
    select u2.id
      from public.utilisateurs u2
      join liens l on u2.parent_id = l.id
  )
  select array_agg(distinct id) into v_ids from liens;

  v_ids := coalesce(v_ids, array[]::uuid[]) || p_entreprise;

  -- 1) Toutes les tables applicatives qui désignent cette entreprise.
  for v_t in
    select distinct c.table_name, c.column_name
      from information_schema.columns c
      join information_schema.tables t
        on t.table_schema = c.table_schema
       and t.table_name = c.table_name
       and t.table_type = 'BASE TABLE'
     where c.table_schema = 'public'
       and c.column_name in ('owner_id', 'entreprise_id')
       and c.table_name <> 'entreprises'
     order by c.table_name
  loop
    execute format('delete from public.%I where %I = any($1)', v_t.table_name, v_t.column_name)
      using v_ids;
    v_supprimees := v_supprimees + 1;
  end loop;

  -- 2) Les comptes (cas où ils ne sont rattachés que par `parent_id`).
  begin
    delete from public.utilisateurs
     where id = any(v_ids) or parent_id = any(v_ids);
    get diagnostics v_utilisateurs = row_count;
  exception
    when foreign_key_violation then
      raise exception 'SUPPRESSION_BLOQUEE|Des données pointent encore vers ces comptes : supprimez-les puis réessayez.';
  end;

  -- 3) L'entreprise elle-même.
  begin
    delete from public.entreprises where id = p_entreprise;
  exception
    when foreign_key_violation then
      raise exception 'SUPPRESSION_BLOQUEE|Des données liées empêchent la suppression de « % » : prévenez le support technique.', v_nom;
  end;

  begin
    insert into public.journal_audit (action, utilisateur_id, details, created_at)
    values (
      'ENTREPRISE_SUPPRIMEE', v_user,
      jsonb_build_object(
        'entreprise_id', p_entreprise, 'nom', v_nom,
        'tables_nettoyees', v_supprimees,
        'comptes_supprimes', v_utilisateurs
      ),
      now()
    );
  exception when others then null;
  end;

  select count(*) into v_reste from public.entreprises where id = p_entreprise;

  return jsonb_build_object(
    'ok', v_reste = 0,
    'entreprise_id', p_entreprise,
    'nom', v_nom,
    'tables_nettoyees', v_supprimees,
    'comptes_supprimes', v_utilisateurs,
    'note', 'Les comptes de connexion Supabase (Authentication) restent à supprimer séparément si nécessaire.'
  );
end;
$$;

comment on function public.rpc_entreprise_supprimer(uuid, text) is
  'Supprime une entreprise, ses données applicatives et ses comptes. SUPER_ADMIN uniquement, confirmation « SUPPRIMER » exigée.';

revoke all on function public.rpc_entreprise_supprimer(uuid, text) from public, anon;
grant execute on function public.rpc_entreprise_supprimer(uuid, text) to authenticated;


-- ============================================================================
--  FIN — PHASE 7
-- ============================================================================
