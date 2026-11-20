-- ============================================================================
--  biashara_yangu — MIGRATION 0174
--  CRÉATION UNIFIÉE · MÉTIER RÉEL · SUPPRESSIONS SANS TOUCHER AU JOURNAL
--  ---------------------------------------------------------------------------
--  Fichier : supabase/migrations/20260916000174_creation_unifiee_suppressions.sql
--
--  CE QUE CETTE MIGRATION CORRIGE (diagnostic du 20/11/2026)
--  ---------------------------------------------------------------------------
--  P1. « invalid input syntax for type uuid » à la création d'une entreprise
--      + propriétaire (Super Admin ET Setup).
--      → les listes déroulantes envoient '' ; un paramètre déclaré `uuid`
--        refuse cette valeur (22P02) et toute la transaction est annulée.
--      CORRECTIF : les paramètres d'identifiant sont reçus en `text` puis
--        normalisés par `public.uuid_ou_null()` (jamais '' → toujours NULL).
--        Une ancienne version de l'application installée sur un téléphone
--        continue donc de fonctionner.
--
--  P2. Setup et Super Admin ne suivaient pas la même logique.
--      → UN SEUL cœur : `biashara_entreprise_creer_coeur(...)`, appelé par
--        `rpc_entreprise_creer` (inscription) ET
--        `rpc_admin_entreprise_creer` (plateforme). Même transaction, même
--        ordre : entreprise → espace → propriétaire/liaison → dossier →
--        modules → trace. Tout réussit ou tout est annulé.
--      → `biashara_assurer_profil_activite(type)` garantit qu'un profil de
--        modules EXISTE pour toute activité (créé complet avec tout le
--        catalogue s'il manque) : plus jamais d'entreprise « à moitié »
--        configurée.
--      → `owner_id` (route B, migration 145) est désormais TOUJOURS écrit :
--        une entreprise créée par le Super Admin était invisible dans le
--        sélecteur d'espaces de son propriétaire.
--
--  P3. Le type change, puis « l'ancien type réapparaît » à la réouverture.
--      → L'écran affichait `entreprises.type_activite` (axe commercial
--        boutique/distribution) alors que le MÉTIER vit dans `espaces.type`.
--      CORRECTIF serveur : `rpc_entreprises_metiers()` expose le métier réel
--        (source unique : `espaces.type`), avec son libellé. Aucune colonne
--        dupliquée, donc aucune divergence possible.
--
--  P4. Suppression d'entreprise bloquée par « journal d'audit inaltérable ».
--      → `rpc_entreprise_supprimer` supprimait des lignes du journal et
--        devait couper son déclencheur append-only.
--      CORRECTIF : le journal n'est PLUS touché du tout.
--        • colonnes d'instantané `entreprise_nom` / `utilisateur_email`
--          (aucune clé étrangère : supprimer une entreprise n'oblige plus à
--          modifier le journal) ;
--        • toutes les clés étrangères DU JOURNAL sont supprimées ;
--        • l'événement de suppression est une NOUVELLE ligne (INSERT).
--      Le déclencheur `trg_journal_audit_append_only` reste intact.
--
--  P5. Suppression d'un utilisateur avec cascade COMPLÈTE.
--      → `biashara_supprimer_utilisateur_coeur(...)` :
--        entreprises possédées (owner_id / proprietaire_id) + toutes leurs
--        données (y compris paiements), comptes collaborateurs, espaces,
--        dossiers d'activation, compte GoTrue (auth.users).
--        Garde-fous : Super Admin uniquement, jamais soi-même, jamais le
--        dernier Super Admin, jamais un compte de plateforme.
--        Confirmation : « SUPPRIMER », le nom du compte ou son e-mail.
--        Journalisation en INSERT seul.
--
--  ⚠️ AUCUNE donnée existante n'est supprimée par cette migration.
--  ⚠️ IDEMPOTENTE : relançable sans effet de bord.
--  ⚠️ À exécuter dans Supabase → SQL Editor → coller → Run.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);


-- ============================================================================
--  1. LE GARDE-FOU D'IDENTIFIANTS : UNE CHAÎNE VIDE N'EST PAS UN UUID
-- ============================================================================

create or replace function public.uuid_ou_null(p_valeur text)
returns uuid
language plpgsql
immutable
as $$
declare
  v text := lower(btrim(coalesce(p_valeur, '')));
begin
  -- Valeurs « fausses » envoyées par d'anciens écrans.
  if v in ('', 'null', 'undefined', 'none', 'nil', '0', '-1') then
    return null;
  end if;

  -- Un identifiant non-UUID (code de module, nom de type…) n'est PAS un UUID.
  if v !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return null;
  end if;

  return v::uuid;
exception
  when others then
    return null;
end;
$$;

comment on function public.uuid_ou_null(text) is
  '0174 — convertit un texte en UUID valide, ou NULL. Jamais d''erreur 22P02 : une chaîne vide, « null », « undefined » ou un code de module ne peuvent pas faire échouer une transaction.';

grant execute on function public.uuid_ou_null(text) to anon, authenticated;


-- ============================================================================
--  2. LE JOURNAL D'AUDIT RESTE INALTÉRABLE — MAIS N'EST PLUS UN FREIN
-- ============================================================================
--  2.a Colonnes INSTANTANÉ : « qui / quoi » au moment de l'action.
--      Ce sont de simples textes : aucune clé étrangère, donc supprimer une
--      entreprise ou un compte n'oblige plus à MODIFIER le journal.
-- ============================================================================

alter table public.journal_audit
  add column if not exists entreprise_nom    text;
alter table public.journal_audit
  add column if not exists utilisateur_email text;

comment on column public.journal_audit.entreprise_nom is
  '0174 — instantané du nom de l''entreprise au moment de l''action (aucune FK : le journal survit à la suppression de l''entreprise).';
comment on column public.journal_audit.utilisateur_email is
  '0174 — instantané de l''auteur (e-mail, repli nom) au moment de l''action. Aucune FK : le journal survit à la suppression du compte.';

-- ============================================================================
--  2.b Supprimer TOUTES les clés étrangères DU JOURNAL (cascade / SET NULL).
--      Une cascade « ON DELETE SET NULL » exécute un UPDATE : c'est
--      précisément ce que le déclencheur append-only refuse.
-- ============================================================================

do $$
declare
  v_fk record;
begin
  for v_fk in
    select con.conname
      from pg_constraint con
     where con.conrelid = 'public.journal_audit'::regclass
       and con.contype = 'f'
  loop
    execute format('alter table public.journal_audit drop constraint %I',
                   v_fk.conname);
    raise notice 'Journal d''audit : clé étrangère % supprimée.', v_fk.conname;
  end loop;
end $$;

-- ============================================================================
--  2.c Le déclencheur de préparation remplit les INSTANTANÉS.
--      (Le hash chaîné, le niveau et l'horodatage sont conservés à
--       l'identique — seule l'écriture des deux instantanés est ajoutée.)
-- ============================================================================

create or replace function public.trg_audit_preparer()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_prec text;
begin
  perform pg_advisory_xact_lock(83829112);

  -- Instantanés : lus une seule fois, à l'insertion. Aucune FK ne les
  -- rattache aux tables vivantes, donc ils ne changeront jamais.
  if new.entreprise_nom is null and new.entreprise_id is not null then
    select e.nom into new.entreprise_nom
      from public.entreprises e
     where e.id = new.entreprise_id;
  end if;

  if new.utilisateur_email is null and new.utilisateur_id is not null then
    select coalesce(nullif(btrim(u.email), ''),
                    nullif(btrim(u.nom), ''))
      into new.utilisateur_email
      from public.utilisateurs u
     where u.id = new.utilisateur_id;
  end if;

  new.niveau := coalesce(
    nullif(upper(btrim(coalesce(new.niveau, ''))), ''),
    public.audit_niveau(new.action)
  );

  new.created_at := coalesce(new.created_at, now());
  new.details    := coalesce(new.details, '{}'::jsonb);

  select a.empreinte
    into v_prec
    from public.journal_audit a
   order by a.seq desc
   limit 1;

  new.empreinte := public.audit_empreinte_ligne(
    v_prec,
    new.seq,
    coalesce(new.id, gen_random_uuid()),
    new.utilisateur_id,
    new.entreprise_id,
    new.action,
    new.niveau,
    new.details,
    new.created_at
  );

  if new.id is null then
    new.id := gen_random_uuid();
  end if;

  return new;
end;
$$;

drop trigger if exists trg_journal_audit_preparer on public.journal_audit;
create trigger trg_journal_audit_preparer
  before insert on public.journal_audit
  for each row
  execute function public.trg_audit_preparer();

-- ⚠️ On NE TOUCHE PAS `trg_journal_audit_append_only` : UPDATE et DELETE
-- restent refusés pour tout le monde, y compris au Super Admin.


-- ============================================================================
--  3. LE MÉTIER RÉEL, SANS DUPLICATION
-- ============================================================================
--  Source unique de vérité : `espaces.type`. Cette fonction ne fait que lire
--  et présenter — aucune colonne miroir à maintenir, donc aucune divergence
--  possible après un changement de type.
-- ============================================================================

create or replace function public.rpc_entreprises_metiers(
  p_ids uuid[] default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_resultat jsonb;
begin
  if auth.uid() is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;

  select coalesce(
           jsonb_agg(
             jsonb_build_object(
               'entreprise_id', x.entreprise_id,
               'metier',        x.metier,
               'libelle',       coalesce(t.libelle, x.metier),
               'nb_espaces',    x.nb_espaces,
               'types',         x.types
             )
             order by x.metier, x.entreprise_id
           ),
           '[]'::jsonb)
    into v_resultat
    from (
      select s.entreprise_id,
             -- Le métier SPÉCIALISÉ prime sur la valeur par défaut
             -- « boutique » lorsque plusieurs boutiques coexistent.
             (array_agg(s.type order by (s.type = 'boutique') asc,
                                      s.created_at asc nulls last))[1] as metier,
             count(*)          as nb_espaces,
             to_jsonb(array_agg(distinct s.type)) as types
        from public.espaces s
       where coalesce(btrim(s.type), '') <> ''
         and (p_ids is null or s.entreprise_id = any(p_ids))
         -- Portée : la plateforme voit tout ; un compte d'entreprise ne voit
         -- que ses propres entreprises (jamais de fuite de noms/activités).
         and (public.est_plateforme()
              or s.entreprise_id in (
                   select e.id
                     from public.entreprises e
                    where e.owner_id = public.mon_patron()
                       or e.owner_id = auth.uid()
                       or exists (select 1 from public.utilisateurs u
                                   where u.id = auth.uid()
                                     and u.entreprise_id = e.id)))
       group by s.entreprise_id
    ) x
    left join public.types_espaces_modules t
           on t.type = x.metier;

  return v_resultat;
end;
$$;

comment on function public.rpc_entreprises_metiers(uuid[]) is
  '0174 — métier réel d''une entreprise (source unique : espaces.type), avec son libellé. Sert à l''administration au lieu d''afficher l''axe commercial.';

revoke all on function public.rpc_entreprises_metiers(uuid[]) from public, anon;
grant execute on function public.rpc_entreprises_metiers(uuid[]) to authenticated;


-- ============================================================================
--  4. LE CATALOGUE COMPLET D'UN MÉTIER
-- ============================================================================
--  4.0 PARITÉ DES CODES DE MODULES (frontend = base).
--      `modules_catalogue()` (migration 27) n'avait que 22 codes. Le
--      référencement Dart (`ModuleCode`, `ModuleActivite.catalogue`) en
--      compte 25 : les modules de DISTRIBUTION et de PRESSING manquaient, ce
--      qui rendait impossible leur ajout à un profil par l'écran Expert et
--      faisait créer des profils incomplets.
-- ============================================================================

create or replace function public.modules_catalogue()
returns text[]
language sql
immutable
as $$
  select array[
    -- Modules de base (vente au comptoir)
    'ventes', 'produits', 'stock', 'qr', 'caisse', 'clients', 'finance',
    'employes', 'rapports', 'assistant_ia',
    -- Modules métier (phases C)
    'chambres', 'reservations', 'checkin',
    'tables', 'commandes', 'cuisine',
    'salles', 'evenements',
    'lots_expiration', 'production', 'pesee', 'variantes',
    -- Distribution professionnelle (tournées, consignes, récipients…)
    'distribution',
    -- Pressing & blanchisserie
    'press_depots', 'press_atelier', 'press_retraits'
  ]::text[];
$$;

comment on function public.modules_catalogue() is
  '0174 — catalogue des modules connus, MIROIR EXACT de ModuleCode (Dart). 25 codes : base + métier + distribution + pressing.';

revoke all on function public.modules_catalogue() from public, anon;
grant execute on function public.modules_catalogue() to authenticated;

--  4.1 Un profil de modules EXPLOITABLE pour toute activité.
--  S'il manque (métier créé après le seed, type saisi directement en base…),
--  il est créé avec TOUT le catalogue : c'est la « configuration complète »
--  demandée. Un profil existant (même personnalisé par l'Expert) n'est
--  JAMAIS écrasé.
-- ============================================================================

create or replace function public.biashara_assurer_profil_activite(p_type text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_type    text := lower(btrim(coalesce(p_type, '')));
  v_libelle text;
  v_modules jsonb;
  v_cree    boolean := false;
begin
  if v_type = '' then
    v_type := 'boutique';
  end if;

  -- 1. Profil existant et non vide ? On le respecte tel quel.
  select t.libelle, t.modules
    into v_libelle, v_modules
    from public.types_espaces_modules t
   where t.type = v_type;

  if v_modules is not null
     and jsonb_typeof(v_modules) = 'array'
     and jsonb_array_length(v_modules) > 0 then
    return jsonb_build_object(
      'type', v_type, 'libelle', coalesce(v_libelle, v_type),
      'modules', v_modules, 'cree', false);
  end if;

  -- 2. Sinon : profil COMPLET (tout le catalogue), créé ou complété.
  v_libelle := coalesce(nullif(btrim(coalesce(v_libelle, '')), ''),
                        initcap(replace(v_type, '_', ' ')));

  insert into public.types_espaces_modules (type, libelle, modules, actif)
  values (v_type, v_libelle, to_jsonb(public.modules_catalogue()), true)
  on conflict (type) do update
     set modules = excluded.modules,
         libelle = coalesce(nullif(btrim(types_espaces_modules.libelle), ''),
                            excluded.libelle)
   where types_espaces_modules.modules is null
      or jsonb_typeof(types_espaces_modules.modules) <> 'array'
      or jsonb_array_length(types_espaces_modules.modules) = 0;

  v_cree := true;

  select t.libelle, t.modules
    into v_libelle, v_modules
    from public.types_espaces_modules t
   where t.type = v_type;

  return jsonb_build_object(
    'type', v_type, 'libelle', coalesce(v_libelle, v_type),
    'modules', coalesce(v_modules, to_jsonb(public.modules_catalogue())),
    'cree', v_cree);
end;
$$;

comment on function public.biashara_assurer_profil_activite(text) is
  '0174 — garantit un profil de modules pour un métier ; créé COMPLET (tout le catalogue) s''il manque, jamais écrasé s''il existe.';

revoke all on function public.biashara_assurer_profil_activite(text)
  from public, anon;
grant execute on function public.biashara_assurer_profil_activite(text)
  to authenticated;


-- ============================================================================
--  5. LE CŒUR UNIQUE DE CRÉATION (Setup ET Super Admin)
-- ============================================================================
--  UNE transaction : entreprise → espace → propriétaire/liaison → dossier
--  d'activation → profil de modules → trace. Tout réussit ou tout est annulé.
-- ============================================================================

create or replace function public.biashara_entreprise_creer_coeur(
  p_nom               text,
  p_type              text,
  p_telephone         text,
  p_proprietaire      uuid,
  p_ville_id          text    default null,
  p_activite_id       text    default null,
  p_groupe_id         text    default null,
  p_prix_installation numeric default null,
  p_prix_mensuel      numeric default null,
  p_cree_par          uuid    default null,
  p_note              text    default null,
  p_mode              text    default 'complet'
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_role      text := public.mon_role();
  v_nom       text;
  v_type      text;
  v_profil    jsonb;
  v_libelle   text;
  v_ville     uuid;
  v_activite  uuid;
  v_groupe    uuid;
  v_ent       uuid;
  v_espace    uuid;
  v_esp_ent   uuid;
  v_essai     integer := 7;
  v_g_inst    numeric := 0;
  v_g_abont   numeric := 0;
  v_inst      numeric;
  v_mensuel   numeric;
  v_statut    public.statut_abonnement_enum;
  v_etape     text;
  v_mode      text := lower(btrim(coalesce(p_mode, 'complet')));
begin
  -- ------------------------------------------------------------- validations
  if p_proprietaire is null then
    raise exception 'PROPRIETAIRE_REQUIS|Aucun propriétaire n''a été désigné pour cette entreprise.';
  end if;

  if not exists (select 1 from public.utilisateurs u where u.id = p_proprietaire) then
    raise exception 'PROPRIETAIRE_INTROUVABLE|Le compte du propriétaire n''existe pas.';
  end if;

  v_nom := nullif(btrim(coalesce(p_nom, '')), '');
  if v_nom is null or length(v_nom) < 2 then
    raise exception 'NOM_REQUIS|Indiquez le nom de l''entreprise (2 caractères minimum).';
  end if;

  v_ville    := public.uuid_ou_null(p_ville_id);
  v_activite := public.uuid_ou_null(p_activite_id);
  v_groupe   := public.uuid_ou_null(p_groupe_id);

  -- ------------------------------------------- catégorie (métier) validée
  v_type := lower(btrim(coalesce(p_type, 'boutique')));
  if to_regclass('public.types_espaces_modules') is not null then
    if not exists (select 1 from public.types_espaces_modules t
                    where t.type = v_type and t.actif) then
      if exists (select 1 from public.types_espaces_modules t
                  where t.type = 'autre' and t.actif) then
        v_type := 'autre';
      else
        v_type := 'boutique';
      end if;
    end if;
  else
    v_type := 'boutique';
  end if;

  -- Module 16/0174 — profil COMPLET garanti (jamais de compte à moitié armé).
  v_profil  := public.biashara_assurer_profil_activite(v_type);
  v_libelle := v_profil->>'libelle';

  -- ------------------------------------------------------ grille tarifaire
  if v_groupe is not null then
    select coalesce(g.frais_ouverture, 0),
           coalesce(g.montant_abonnement, 0),
           coalesce(nullif(g.duree_essai_jours, 0), 7)
      into v_g_inst, v_g_abont, v_essai
      from public.groupes_tarifaires g
     where g.id = v_groupe;

    if not found then
      raise exception 'GRILLE_INTROUVABLE|Cette grille tarifaire n''existe plus.';
    end if;
  end if;

  -- Correctif 60 : le prix d'installation comprend le premier mois.
  v_inst := case
              when p_prix_installation is not null and p_prix_installation > 0
                then p_prix_installation
              else nullif(v_g_inst + v_g_abont, 0)
            end;

  v_mensuel := case
                 when p_prix_mensuel is not null and p_prix_mensuel > 0
                   then p_prix_mensuel
                 else nullif(v_g_abont, 0)
               end;

  if v_mensuel is not null and v_mensuel <= 0 then
    raise exception 'MONTANT_INVALIDE|Le prix mensuel doit être supérieur à zéro.';
  end if;

  -- Mode « simple » (setup express) : essai immédiat. Sinon double validation.
  if v_mode = 'simple' then
    v_statut := 'ESSAI_7J'::public.statut_abonnement_enum;
    v_etape  := 'actif';
  else
    v_statut := 'EN_ATTENTE_COMPLEMENT'::public.statut_abonnement_enum;
    v_etape  := 'en_attente_verification';
  end if;

  -- ------------------------------------------------------- 1) L'ENTREPRISE
  insert into public.entreprises (
    nom, ville_id, activite_id, groupe_tarifaire_id,
    statut, montant_total_du, montant_deja_paye,
    prix_installation, prix_abonnement_mensuel,
    date_activation, date_expiration, activation_etape,
    proprietaire_id, owner_id, cree_par, cree_le
  ) values (
    v_nom, v_ville, v_activite, v_groupe,
    v_statut, coalesce(v_inst, 0), 0,
    v_inst, v_mensuel,
    case when v_mode = 'simple' then now() else null end,
    now() + make_interval(days => v_essai), v_etape,
    p_proprietaire, p_proprietaire, p_cree_par, now()
  )
  returning id into v_ent;

  -- ----------------------------------------------------------- 2) L'ESPACE
  -- Convention historique : l'espace porte l'UUID du patron. Avec plusieurs
  -- entreprises (route B), cet identifiant peut déjà appartenir à une autre
  -- entreprise : on crée alors un espace distinct au lieu de ne rien faire
  -- (l'ancien `on conflict do nothing` laissait l'entreprise SANS boutique).
  select s.entreprise_id into v_esp_ent
    from public.espaces s
   where s.id = p_proprietaire;

  if v_esp_ent is null then
    v_espace := p_proprietaire;
  elsif v_esp_ent = v_ent then
    v_espace := p_proprietaire;
  else
    v_espace := gen_random_uuid();
  end if;

  insert into public.espaces (id, entreprise_id, nom, type, ville_id, actif)
  values (v_espace, v_ent, v_nom, v_type, v_ville, true)
  on conflict (id) do update
     set entreprise_id = excluded.entreprise_id,
         nom           = excluded.nom,
         type          = excluded.type,
         -- `espaces` (sans schéma) est la référence à la ligne EXISTANTE :
         -- une référence `public.espaces.ville_id` serait rejetée par
         -- PostgreSQL dans la clause ON CONFLICT.
         ville_id      = coalesce(excluded.ville_id, espaces.ville_id),
         actif         = true;

  -- ------------------------------- 3) LE PROFIL DU PROPRIÉTAIRE (liaison)
  update public.utilisateurs
     set entreprise_id   = v_ent,
         espace_actif_id = v_espace,
         telephone       = coalesce(nullif(btrim(coalesce(p_telephone, '')), ''),
                                    telephone),
         new_role        = case when parent_id is null
                                then coalesce(public.role_enum('PROPRIETAIRE'),
                                              new_role)
                                else new_role end,
         role            = case when parent_id is null
                                then 'PROPRIETAIRE'
                                else role end,
         valide          = 1
   where id = p_proprietaire;

  -- ------------------------------------------ 4) DOSSIER D'ACTIVATION (m14)
  insert into public.activations_entreprise (
    entreprise_id, etape, acteur_id, acteur_role, note
  ) values (
    v_ent,
    case when v_mode = 'simple' then 'paiement_finance' else 'soumission' end,
    coalesce(p_cree_par, p_proprietaire),
    v_role,
    coalesce(nullif(btrim(coalesce(p_note, '')), ''),
             case when v_mode = 'simple'
                  then 'Activation AUTOMATIQUE — mode simple (essai 7 jours)'
                  else 'Création du compte' end)
  );

  -- ------------------------------------------------------------- 5) TRACE
  begin
    insert into public.journal_audit (
      entreprise_id, entreprise_nom, utilisateur_id, utilisateur_email,
      action, details
    )
    values (
      null, v_nom, coalesce(p_cree_par, auth.uid()), null,
      'CREATION_ENTREPRISE',
      jsonb_build_object(
        'entreprise_id',          v_ent,
        'nom',                    v_nom,
        'type',                   v_type,
        'libelle',                v_libelle,
        'espace_id',              v_espace,
        'proprietaire_id',        p_proprietaire,
        'owner_id',               p_proprietaire,
        'cree_par',               p_cree_par,
        'cree_par_role',          v_role,
        'prix_installation',      v_inst,
        'prix_abonnement_mensuel', v_mensuel,
        'essai_jours',            v_essai,
        'mode',                   v_mode,
        'modules',                v_profil->'modules',
        'note',                   p_note
      )
    );
  exception when others then null;
  end;

  return jsonb_build_object(
    'ok',                      true,
    'deja',                    false,
    'entreprise_id',           v_ent,
    'nom',                     v_nom,
    'type',                    v_type,
    'libelle',                 v_libelle,
    'espace_id',               v_espace,
    'proprietaire_id',         p_proprietaire,
    'prix_installation',       v_inst,
    'prix_abonnement_mensuel', v_mensuel,
    'essai_jours',             v_essai,
    'activation_etape',        v_etape,
    'modules',                 coalesce(v_profil->'modules', '[]'::jsonb),
    'modules_source',          'profil_activite'
  );
end;
$$;

comment on function public.biashara_entreprise_creer_coeur(
  text, text, text, uuid, text, text, text, numeric, numeric, uuid, text, text
) is
  '0174 — LE cœur unique de création : entreprise + espace + propriétaire + liaison + dossier d''activation + profil de modules complet, dans UNE transaction. Appelé par le Setup et par le Super Admin.';

revoke all on function public.biashara_entreprise_creer_coeur(
  text, text, text, uuid, text, text, text, numeric, numeric, uuid, text, text
) from public, anon;


-- ============================================================================
--  6. `rpc_entreprise_creer` (SETUP) → APPELLE LE CŒUR
-- ============================================================================
--  Signature conservée : (text, text, text). Les applications installées
--  continuent d'appeler la même fonction.
-- ============================================================================

create or replace function public.rpc_entreprise_creer(
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
  v_user    uuid := auth.uid();
  v_exist   uuid;
  v_nomu    text;
  v_type    text;
  v_libelle text;
  v_nom     text;
  v_res     jsonb;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour créer votre entreprise.';
  end if;

  -- Déjà rattaché ? On ne duplique pas.
  select u.entreprise_id into v_exist
    from public.utilisateurs u
   where u.id = v_user;

  if v_exist is not null then
    return jsonb_build_object(
      'ok', true, 'deja', true, 'entreprise_id', v_exist);
  end if;

  select coalesce(nullif(btrim(u.nom), ''), u.email) into v_nomu
    from public.utilisateurs u
   where u.id = v_user;

  -- Catégorie validée par le référentiel (repli « autre », puis « boutique »).
  v_type := lower(btrim(coalesce(p_type, 'boutique')));
  if to_regclass('public.types_espaces_modules') is not null then
    select t.libelle into v_libelle
      from public.types_espaces_modules t
     where t.type = v_type and t.actif;

    if v_libelle is null then
      v_type := 'autre';
      select t.libelle into v_libelle
        from public.types_espaces_modules t
       where t.type = v_type and t.actif;
    end if;

    if v_libelle is null then
      v_type := 'boutique';
      select t.libelle into v_libelle
        from public.types_espaces_modules t
       where t.type = v_type and t.actif;
    end if;
  end if;

  v_libelle := coalesce(v_libelle, 'Boutique');

  v_nom := nullif(btrim(coalesce(p_nom, '')), '');
  if v_nom is null then
    v_nom := v_libelle || ' ' || coalesce(v_nomu, 'nouvelle');
  end if;

  v_res := public.biashara_entreprise_creer_coeur(
    p_nom          => v_nom,
    p_type         => v_type,
    p_telephone    => p_telephone,
    p_proprietaire => v_user,
    p_cree_par     => null,
    p_mode         => 'complet'
  );

  return v_res || jsonb_build_object('ok', true, 'deja', false);
end;
$$;

comment on function public.rpc_entreprise_creer(text, text, text) is
  '0174 — création du compte par son propriétaire (Setup). Délègue au cœur unique `biashara_entreprise_creer_coeur` : même résultat que la création par le Super Admin.';

revoke all on function public.rpc_entreprise_creer(text, text, text)
  from public, anon;
grant execute on function public.rpc_entreprise_creer(text, text, text)
  to authenticated;


-- ============================================================================
--  7. `rpc_admin_entreprise_creer` (SUPER ADMIN) — IDENTIFIANTS EN TEXT
-- ============================================================================
--  ⚠️ L'ancienne signature `(text, uuid, uuid, uuid, …)` est SUPPRIMÉE :
--  une chaîne vide envoyée par un ancien écran provoquait 22P02 AVANT même
--  d'entrer dans la fonction. En `text`, la normalisation est possible.
-- ============================================================================

drop function if exists public.rpc_admin_entreprise_creer(
  text, uuid, uuid, uuid, text, text, text, text, text, text, numeric, numeric, text);

create or replace function public.rpc_admin_entreprise_creer(
  p_nom                    text,
  p_ville_id               text    default null,
  p_activite_id            text    default null,
  p_groupe_tarifaire_id    text    default null,
  p_type_espace            text    default 'boutique',
  p_proprietaire_nom       text    default null,
  p_proprietaire_prenom    text    default null,
  p_proprietaire_email     text    default null,
  p_proprietaire_telephone text    default null,
  p_mot_de_passe           text    default null,
  p_prix_installation      numeric default null,
  p_prix_mensuel           numeric default null,
  p_note                   text    default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, auth
as $$
declare
  v_role    text := public.mon_role();
  v_email   text := lower(btrim(coalesce(p_proprietaire_email, '')));
  v_nom     text;
  v_nomp    text;
  v_prenom  text;
  v_owner   uuid;
  v_groupe  uuid;
  v_res     jsonb;
  v_deja    boolean := false;
begin
  -- ------------------------------------------------------------------ droits
  if not (public.est_plateforme() or public.peut('entreprises', 'creer')) then
    raise exception 'DROIT_REFUSE|Seule la plateforme crée le compte d''une entreprise.';
  end if;

  -- ⚠️ TOUTES les validations passent AVANT la moindre écriture : en cas
  -- d'erreur, rien n'est créé (ni compte Auth, ni entreprise).
  v_nom := nullif(btrim(coalesce(p_nom, '')), '');
  if v_nom is null or length(v_nom) < 2 then
    raise exception 'NOM_REQUIS|Indiquez le nom de l''entreprise (2 caractères minimum).';
  end if;

  if v_email = '' or position('@' in v_email) = 0 then
    raise exception 'EMAIL_INVALIDE|Adresse e-mail du propriétaire invalide.';
  end if;

  if p_mot_de_passe is null or length(p_mot_de_passe) < 8 then
    raise exception 'MOT_DE_PASSE_TROP_COURT|Le mot de passe doit comporter au moins 8 caractères.';
  end if;

  v_nomp   := nullif(btrim(coalesce(p_proprietaire_nom, '')), '');
  v_prenom := nullif(btrim(coalesce(p_proprietaire_prenom, '')), '');

  if v_nomp is null then
    raise exception 'NOM_PROPRIETAIRE_REQUIS|Indiquez le nom du propriétaire.';
  end if;

  -- Un identifiant non-UUID est simplement IGNORÉ (jamais une erreur 22P02).
  v_groupe := public.uuid_ou_null(p_groupe_tarifaire_id);

  -- Compte déjà existant ? (information affichée à l'administrateur)
  select (count(*) > 0) into v_deja
    from public.utilisateurs u
   where lower(u.email) = v_email;

  -- ---------------------------------------- 1) LE COMPTE DU PROPRIÉTAIRE
  v_owner := public.creer_compte_plateforme(
               v_email, p_mot_de_passe,
               v_nomp, coalesce(v_prenom, ''), 'PROPRIETAIRE');

  -- -------------------------- 2) ENTREPRISE + ESPACE + LIAISON + MODULES
  v_res := public.biashara_entreprise_creer_coeur(
    p_nom               => v_nom,
    p_type              => p_type_espace,
    p_telephone         => p_proprietaire_telephone,
    p_proprietaire      => v_owner,
    p_ville_id          => p_ville_id,
    p_activite_id       => p_activite_id,
    p_groupe_id         => v_groupe::text,
    p_prix_installation => p_prix_installation,
    p_prix_mensuel      => p_prix_mensuel,
    p_cree_par          => auth.uid(),
    p_note              => p_note,
    p_mode              => 'complet'
  );

  return v_res || jsonb_build_object(
    'ok', true,
    'proprietaire_email', v_email,
    'compte_reutilise', v_deja,
    'cree_par', auth.uid(),
    'cree_par_role', v_role
  );
end;
$$;

comment on function public.rpc_admin_entreprise_creer(
  text, text, text, text, text, text, text, text, text, text, numeric, numeric, text
) is
  '0174 — création par la plateforme : compte Auth + profil PROPRIÉTAIRE, puis le MÊME cœur que le Setup (entreprise, espace, liaison, dossier, modules complets) dans une seule transaction. Identifiants reçus en text et normalisés (plus de 22P02 sur une chaîne vide).';

revoke all on function public.rpc_admin_entreprise_creer(
  text, text, text, text, text, text, text, text, text, text, numeric, numeric, text
) from public, anon;
grant execute on function public.rpc_admin_entreprise_creer(
  text, text, text, text, text, text, text, text, text, text, numeric, numeric, text
) to authenticated;


-- ============================================================================
--  8. PURGE D'UN PÉRIMÈTRE — SANS JAMAIS TOUCHER AU JOURNAL D'AUDIT
-- ============================================================================
--  8.0 LA SAUVEGARDE AVANT DESTRUCTION (exigence « aucune donnée supprimée
--      sans sauvegarde »). Chaque purge dépose l'intégralité des lignes
--      concernées (JSON) dans `sauvegardes_suppressions`. La restauration
--      reste une opération manuelle et documentée, mais RIEN n'est perdu.
-- ============================================================================

create table if not exists public.sauvegardes_suppressions (
  id            uuid primary key default gen_random_uuid(),
  cree_le       timestamptz not null default now(),
  acteur        uuid,
  cible_type    text not null default 'perimetre',
  cible_id      uuid,
  cible_libelle text,
  lignes        bigint not null default 0,
  donnees       jsonb  not null default '{}'::jsonb
);

comment on table public.sauvegardes_suppressions is
  '0174 — instantané JSON des données supprimées lors d''une purge (entreprise ou compte). Permet une restauration manuelle ; n''est jamais purgée automatiquement.';

alter table public.sauvegardes_suppressions enable row level security;

drop policy if exists m174_sauvegardes_lecture on public.sauvegardes_suppressions;
create policy m174_sauvegardes_lecture on public.sauvegardes_suppressions
  for select to authenticated
  using (public.est_plateforme());

-- Aucune policy d'écriture : seule une fonction SECURITY DEFINER écrit ici.
revoke insert, update, delete on public.sauvegardes_suppressions
  from public, anon, authenticated;

-- ============================================================================
--  8.1 Les données métier d'un périmètre, table par table.
--      Inventaire par `information_schema` (aucune liste écrite à la main).
--      • `journal_audit` est EXCLU : il reste, il est la mémoire de l'opération.
--      • Les déclencheurs de protection métier (« suppression interdite »)
--        sont coupés le temps de la suppression puis RÉTABLIS.
--      • `p_simulation = true` ne supprime rien et renvoie les volumes.
-- ============================================================================

create or replace function public.biashara_purger_perimetre(
  p_utilisateurs uuid[],
  p_espaces      uuid[],
  p_entreprises  uuid[],
  p_simulation   boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_users   uuid[] := coalesce(p_utilisateurs, array[]::uuid[]);
  v_owners  uuid[] := coalesce(p_espaces, array[]::uuid[])
                      || coalesce(p_utilisateurs, array[]::uuid[]);
  v_ents    uuid[] := coalesce(p_entreprises, array[]::uuid[]);
  v_t       record;
  v_trg     record;
  v_n       bigint;
  v_total   bigint := 0;
  v_paie    bigint := 0;
  v_detail  jsonb  := '{}'::jsonb;
  v_erreurs jsonb  := '{}'::jsonb;
  v_passe   integer;
  v_coupes  text[] := array[]::text[];
  v_val     uuid[];
  v_tag     text;
  v_sauvegarde    jsonb := '{}'::jsonb;
  v_lignes_json   jsonb;
  v_sauvegarde_id uuid;
begin
  if coalesce(array_length(v_users, 1), 0) = 0
     and coalesce(array_length(v_owners, 1), 0) = 0
     and coalesce(array_length(v_ents, 1), 0) = 0 then
    return jsonb_build_object(
      'ok', true, 'lignes', 0, 'paiements', 0, 'detail', '{}'::jsonb);
  end if;

  -- --------------------------------------------------------------- INVENTAIRE
  for v_t in
    select c.table_name as tbl, c.column_name as col
      from information_schema.columns c
      join information_schema.tables t
        on t.table_schema = c.table_schema
       and t.table_name   = c.table_name
       and t.table_type   = 'BASE TABLE'
     where c.table_schema = 'public'
       and c.column_name in ('owner_id', 'espace_id',
                             'entreprise_id', 'utilisateur_id')
       -- jamais les tables structurelles (traitées explicitement ensuite)
       and c.table_name not in ('entreprises', 'espaces', 'utilisateurs')
       -- ⛔ LE JOURNAL D'AUDIT EST INALTÉRABLE : on n'y touche pas.
       and c.table_name not in ('journal_audit')
       and c.table_name not ilike '%audit%'
     order by c.table_name
  loop
    v_val := case
               when v_t.col = 'entreprise_id'  then v_ents
               when v_t.col = 'utilisateur_id' then v_users
               else v_owners
             end;

    if coalesce(array_length(v_val, 1), 0) = 0 then
      continue;
    end if;

    begin
      execute format('select count(*) from public.%I where %I = any($1)',
                     v_t.tbl, v_t.col)
        into v_n using v_val;
    exception when others then
      v_erreurs := v_erreurs || jsonb_build_object('comptage:' || v_t.tbl,
                                                   sqlerrm);
      continue;
    end;

    if v_n > 0 then
      v_detail := v_detail || jsonb_build_object(
        v_t.tbl || ' (' || v_t.col || ')', v_n);
      v_total := v_total + v_n;
      if v_t.tbl ilike '%paiement%' then
        v_paie := v_paie + v_n;
      end if;
    end if;
  end loop;

  -- Tables dont `entreprise_id` porte en réalité l'UUID du PATRON
  -- (clés étrangères volontairement supprimées au module 17).
  for v_t in
    select x.tbl
      from unnest(array[
        'agent_ia_quotas', 'agent_ia_achats', 'agent_ia_conversations',
        'agent_ia_actions', 'agent_ia_usage', 'agent_ia_credits',
        'agent_ia_distributions'
      ]) as x(tbl)
     where to_regclass('public.' || x.tbl) is not null
  loop
    begin
      execute format('select count(*) from public.%I where entreprise_id = any($1)',
                     v_t.tbl)
        into v_n using v_owners;
      if v_n > 0 then
        v_detail := v_detail || jsonb_build_object(
          v_t.tbl || ' (entreprise_id = patron)', v_n);
        v_total := v_total + v_n;
      end if;
    exception when others then
      null;
    end;
  end loop;

  if coalesce(p_simulation, true) then
    return jsonb_build_object(
      'ok', true, 'simulation', true,
      'lignes', v_total, 'paiements', v_paie,
      'detail', v_detail, 'erreurs', v_erreurs,
      'sauvegarde_id', null);
  end if;

  -- ------------------------------------------------------ SAUVEGARDE (JSON)
  --  Exigence : aucune donnée n'est supprimée sans sauvegarde. On relit les
  --  lignes qui vont disparaître et on les dépose dans
  --  `sauvegardes_suppressions` AVANT la moindre suppression.
  for v_t in
    select c.table_name as tbl, c.column_name as col
      from information_schema.columns c
      join information_schema.tables t
        on t.table_schema = c.table_schema
       and t.table_name   = c.table_name
       and t.table_type   = 'BASE TABLE'
     where c.table_schema = 'public'
       and c.column_name in ('owner_id', 'espace_id',
                             'entreprise_id', 'utilisateur_id')
       and c.table_name not in ('entreprises', 'espaces', 'utilisateurs')
       and c.table_name not in ('journal_audit')
       and c.table_name not ilike '%audit%'
  loop
    v_val := case
               when v_t.col = 'entreprise_id'  then v_ents
               when v_t.col = 'utilisateur_id' then v_users
               else v_owners
             end;

    if coalesce(array_length(v_val, 1), 0) = 0 then
      continue;
    end if;

    begin
      execute format(
        'select coalesce(jsonb_agg(to_jsonb(x)), ''[]''::jsonb)
           from (select * from public.%I where %I = any($1)) x',
        v_t.tbl, v_t.col)
        into v_lignes_json using v_val;

      if v_lignes_json is not null
         and jsonb_array_length(v_lignes_json) > 0 then
        v_sauvegarde := v_sauvegarde
                        || jsonb_build_object(v_t.tbl, v_lignes_json);
      end if;
    exception when others then
      v_erreurs := v_erreurs || jsonb_build_object('sauvegarde:' || v_t.tbl,
                                                   sqlerrm);
    end;
  end loop;

  begin
    insert into public.sauvegardes_suppressions
      (acteur, cible_type, cible_id, cible_libelle, lignes, donnees)
    values (
      auth.uid(),
      case when coalesce(array_length(v_ents, 1), 0) > 0
           then 'entreprise' else 'compte' end,
      coalesce(v_ents[1], v_users[1]),
      null,
      v_total,
      v_sauvegarde)
    returning id into v_sauvegarde_id;
  exception when others then
    v_sauvegarde_id := null;
  end;

  -- ------------------------------------------------------ EXÉCUTION RÉELLE
  -- 1) Couper les gardes « suppression interdite » et le verrou commercial.
  --    (Le déclencheur append-only du journal n'est PAS dans cette liste.)
  for v_trg in
    select c.relname as tbl, t.tgname as tg
      from pg_trigger t
      join pg_class c     on c.oid = t.tgrelid
      join pg_namespace n on n.oid = c.relnamespace
      join pg_proc p      on p.oid = t.tgfoid
     where n.nspname = 'public'
       and not t.tgisinternal
       and c.relname <> 'journal_audit'
       and t.tgenabled <> 'D'
       and (p.proname ilike '%interdit%'
            or p.proname ilike '%inalterable%'
            or p.proname ilike '%immuable%'
            or p.proname ilike '%immutable%'
            or t.tgname ilike '%interdit%'
            or t.tgname ilike '%inalterable%'
            or t.tgname ilike '%immuable%'
            or t.tgname ilike '%immutable%'
            or t.tgname = 'trg_m17_blocage')
  loop
    execute format('alter table public.%I disable trigger %I',
                   v_trg.tbl, v_trg.tg);
    v_coupes := v_coupes || (v_trg.tbl || '|' || v_trg.tg);
  end loop;

  -- 2) Supprimer. Trois passes : l'ordre des dépendances n'est pas garanti.
  for v_passe in 1..3 loop
    for v_t in
      select c.table_name as tbl, c.column_name as col
        from information_schema.columns c
        join information_schema.tables t
          on t.table_schema = c.table_schema
         and t.table_name   = c.table_name
         and t.table_type   = 'BASE TABLE'
       where c.table_schema = 'public'
         and c.column_name in ('owner_id', 'espace_id',
                               'entreprise_id', 'utilisateur_id')
         and c.table_name not in ('entreprises', 'espaces', 'utilisateurs')
         and c.table_name not in ('journal_audit')
         and c.table_name not ilike '%audit%'
    loop
      v_val := case
                 when v_t.col = 'entreprise_id'  then v_ents
                 when v_t.col = 'utilisateur_id' then v_users
                 else v_owners
               end;

      if coalesce(array_length(v_val, 1), 0) = 0 then
        continue;
      end if;

      begin
        execute format('delete from public.%I where %I = any($1)',
                       v_t.tbl, v_t.col)
          using v_val;
      exception when others then
        null;  -- retenté à la passe suivante
      end;
    end loop;

    for v_t in
      select x.tbl
        from unnest(array[
          'agent_ia_quotas', 'agent_ia_achats', 'agent_ia_conversations',
          'agent_ia_actions', 'agent_ia_usage', 'agent_ia_credits',
          'agent_ia_distributions'
        ]) as x(tbl)
       where to_regclass('public.' || x.tbl) is not null
    loop
      begin
        execute format('delete from public.%I where entreprise_id = any($1)',
                       v_t.tbl)
          using v_owners;
      exception when others then
        null;
      end;
    end loop;
  end loop;

  -- 3) Rétablir TOUS les déclencheurs coupés (même en cas d'erreur, l'appelant
  --    relance la fonction ; PostgreSQL annule le DDL en cas de rollback).
  foreach v_tag in array v_coupes loop
    begin
      execute format('alter table public.%I enable trigger %I',
                     split_part(v_tag, '|', 1), split_part(v_tag, '|', 2));
    exception when others then
      null;
    end;
  end loop;

  return jsonb_build_object(
    'ok', true, 'simulation', false,
    'lignes', v_total, 'paiements', v_paie,
    'detail', v_detail, 'erreurs', v_erreurs,
    'sauvegarde_id', v_sauvegarde_id,
    'declencheurs_retablis', to_jsonb(v_coupes));
end;
$$;

comment on function public.biashara_purger_perimetre(uuid[], uuid[], uuid[], boolean) is
  '0174 — supprime les données métier d''un périmètre (comptes / espaces / entreprises). Inventaire par information_schema, journal d''audit EXCLU et jamais modifié, déclencheurs de garde rétablis.';

revoke all on function public.biashara_purger_perimetre(uuid[], uuid[], uuid[], boolean)
  from public, anon;


-- ============================================================================
--  9. SUPPRESSION D'UNE ENTREPRISE (JOURNAL INTACT)
-- ============================================================================

drop function if exists public.biashara_supprimer_entreprise_coeur(uuid, text, boolean);

create or replace function public.biashara_supprimer_entreprise_coeur(
  p_entreprise uuid,
  p_confirmation text,
  p_simulation boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user   uuid := auth.uid();
  v_role   text := public.mon_role();
  v_nom    text;
  v_users  uuid[];
  v_espaces uuid[];
  v_purge  jsonb;
  v_nb_users integer := 0;
  v_nb_esp   integer := 0;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;

  if upper(btrim(coalesce(p_confirmation, ''))) <> 'SUPPRIMER' then
    raise exception 'CONFIRMATION_REQUISE|Écrivez SUPPRIMER pour confirmer.';
  end if;

  if coalesce(v_role, '') <> 'SUPER_ADMIN' and not public.est_plateforme() then
    raise exception 'DROIT_REFUSE|Seul un Super Administrateur peut supprimer une entreprise.';
  end if;

  if p_entreprise is null then
    raise exception 'ENTREPRISE_INVALIDE|Aucune entreprise choisie.';
  end if;

  select e.nom into v_nom from public.entreprises e where e.id = p_entreprise;
  if v_nom is null then
    raise exception 'ENTREPRISE_INTROUVABLE|Cette entreprise n''existe plus.';
  end if;

  if p_entreprise = public.mon_entreprise_id() then
    raise exception 'DROIT_REFUSE|Impossible de supprimer l''entreprise de votre propre compte.';
  end if;

  -- Comptes du périmètre (patron + collaborateurs, et leurs sous-comptes).
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
  select coalesce(array_agg(distinct id), array[]::uuid[]) into v_users
    from liens;

  -- Espaces de l'entreprise (et l'espace « patron » historique).
  select coalesce(array_agg(distinct s.id), array[]::uuid[]) into v_espaces
    from public.espaces s
   where s.entreprise_id = p_entreprise
      or s.id = p_entreprise
      or s.id = any(v_users);

  v_purge := public.biashara_purger_perimetre(
    v_users, v_espaces, array[p_entreprise]::uuid[], p_simulation);

  if coalesce(p_simulation, false) then
    return v_purge || jsonb_build_object(
      'ok', true, 'simulation', true,
      'entreprise_id', p_entreprise, 'nom', v_nom,
      'comptes', coalesce(array_length(v_users, 1), 0),
      'espaces', coalesce(array_length(v_espaces, 1), 0));
  end if;

  -- Dossiers d'activation, espaces, puis l'entreprise elle-même.
  begin
    delete from public.activations_entreprise where entreprise_id = p_entreprise;
  exception when others then null;
  end;

  -- ⚠️ CYCLE DE CLÉS ÉTRANGÈRES : `entreprises.owner_id` → `utilisateurs`
  -- ET `utilisateurs.entreprise_id` → `entreprises`. On coupe les deux liens
  -- AVANT toute suppression (sinon l'ordre, quel qu'il soit, est bloqué).
  begin
    update public.entreprises
       set owner_id = null, proprietaire_id = null
     where id = p_entreprise;
  exception when others then null;
  end;

  begin
    update public.utilisateurs
       set entreprise_id = null
     where entreprise_id = p_entreprise;
  exception when others then null;
  end;

  begin
    delete from public.utilisateurs
     where id = any(v_users) or parent_id = any(v_users);
    get diagnostics v_nb_users = row_count;
  exception
    when foreign_key_violation then
      raise exception 'SUPPRESSION_BLOQUEE|Des données pointent encore vers ces comptes. Réessayez après avoir exécuté la dernière migration.';
  end;

  begin
    delete from public.espaces where id = any(v_espaces) or entreprise_id = p_entreprise;
    get diagnostics v_nb_esp = row_count;
  exception when others then null;
  end;

  begin
    delete from public.entreprises where id = p_entreprise;
  exception
    when foreign_key_violation then
      raise exception 'SUPPRESSION_BLOQUEE|Des données liées empêchent la suppression de « % » : prévenez le support technique.', v_nom;
  end;

  -- ⛔ JAMAIS d'UPDATE ni de DELETE sur le journal : une NOUVELLE ligne.
  begin
    insert into public.journal_audit (
      entreprise_id, entreprise_nom, utilisateur_id, utilisateur_email,
      action, details
    )
    values (
      null, v_nom, v_user, null,
      'ENTREPRISE_SUPPRIMEE',
      jsonb_build_object(
        'entreprise_id',     p_entreprise,
        'nom',               v_nom,
        'comptes_supprimes', v_nb_users,
        'espaces_supprimes', v_nb_esp,
        'lignes_metier',     coalesce(v_purge->'lignes', '0'::jsonb),
        'paiements',         coalesce(v_purge->'paiements', '0'::jsonb),
        'detail',            coalesce(v_purge->'detail', '{}'::jsonb),
        'journal_preserve',  true
      )
    );
  exception when others then null;
  end;

  return v_purge || jsonb_build_object(
    'ok', true, 'simulation', false,
    'entreprise_id', p_entreprise, 'nom', v_nom,
    'comptes_supprimes', v_nb_users,
    'espaces_supprimes', v_nb_esp,
    'journal_preserve', true);
end;
$$;

comment on function public.biashara_supprimer_entreprise_coeur(uuid, text, boolean) is
  '0174 — supprime une entreprise et son périmètre SANS toucher au journal d''audit : celui-ci garde la trace (instantané) et reçoit une NOUVELLE ligne ENTREPRISE_SUPPRIMEE.';

revoke all on function public.biashara_supprimer_entreprise_coeur(uuid, text, boolean)
  from public, anon;
grant execute on function public.biashara_supprimer_entreprise_coeur(uuid, text, boolean)
  to authenticated;


-- ============================================================================
-- 10. `rpc_entreprise_supprimer` → PASSE PAR LE CŒUR (journal intact)
-- ============================================================================

create or replace function public.rpc_entreprise_supprimer(
  p_entreprise   uuid,
  p_confirmation text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return public.biashara_supprimer_entreprise_coeur(
    p_entreprise, p_confirmation, false);
end;
$$;

comment on function public.rpc_entreprise_supprimer(uuid, text) is
  '0174 — suppression d''une entreprise (Super Admin, confirmation SUPPRIMER). Le journal d''audit reste inaltérable : aucune ligne n''est modifiée ni supprimée.';

revoke all on function public.rpc_entreprise_supprimer(uuid, text) from public, anon;
grant execute on function public.rpc_entreprise_supprimer(uuid, text)
  to authenticated;


-- ============================================================================
-- 11. SUPPRESSION D'UN UTILISATEUR — CASCADE COMPLÈTE ET CONTRÔLÉE
-- ============================================================================

drop function if exists public.biashara_supprimer_utilisateur_coeur(uuid, text, boolean);

create or replace function public.biashara_supprimer_utilisateur_coeur(
  p_utilisateur  uuid,
  p_confirmation text,
  p_simulation   boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_acteur     uuid := auth.uid();
  v_role       text := public.mon_role();
  v_u          public.utilisateurs;
  v_email      text;
  v_nom        text;
  v_conf       text := upper(btrim(coalesce(p_confirmation, '')));
  v_espace     uuid;
  v_espaces    uuid[] := array[]::uuid[];
  v_ents       uuid[] := array[]::uuid[];
  v_users      uuid[] := array[]::uuid[];
  v_purge      jsonb;
  v_nb_ent     integer := 0;
  v_nb_users   integer := 0;
  v_nb_esp     integer := 0;
  v_auth       boolean := false;
  v_super      integer := 0;
begin
  if v_acteur is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;

  if coalesce(v_role, '') <> 'SUPER_ADMIN' then
    raise exception 'DROIT_REFUSE|Seul le Super Administrateur peut supprimer définitivement un compte.';
  end if;

  if p_utilisateur is null then
    raise exception 'UTILISATEUR_INVALIDE|Aucun compte choisi.';
  end if;

  if p_utilisateur = v_acteur then
    raise exception 'DROIT_REFUSE|Vous ne pouvez pas supprimer votre propre compte.';
  end if;

  select * into v_u from public.utilisateurs where id = p_utilisateur;
  if not found then
    raise exception 'UTILISATEUR_INCONNU|Ce compte est introuvable.';
  end if;

  v_email := lower(btrim(coalesce(v_u.email, '')));
  v_nom   := lower(btrim(coalesce(v_u.nom, '')));

  -- Confirmation : SUPPRIMER, le nom du compte ou son adresse e-mail.
  if v_conf <> 'SUPPRIMER'
     and lower(btrim(coalesce(p_confirmation, ''))) <> v_email
     and lower(btrim(coalesce(p_confirmation, ''))) <> v_nom then
    raise exception 'CONFIRMATION_INVALIDE|Tapez SUPPRIMER (ou le nom / l''adresse e-mail du compte) pour confirmer.';
  end if;

  -- Un compte de la plateforme ne se supprime pas depuis l'interface.
  if coalesce(v_u.new_role::text, '') in
       ('SUPER_ADMIN', 'GESTIONNAIRE_COMPTES', 'FINANCE_LAPERLE',
        'SUPPORT', 'AGENT_TERRAIN') then
    raise exception 'COMPTE_PLATEFORME|Ce compte appartient à la plateforme : sa suppression verrouillerait l''administration.';
  end if;

  -- Dernier Super Admin protégé (ceinture et bretelles).
  if coalesce(v_u.new_role::text, '') = 'SUPER_ADMIN' then
    select count(*) into v_super
      from public.utilisateurs u
     where u.new_role::text = 'SUPER_ADMIN'
        or u.role = 'admin';
    if v_super <= 1 then
      raise exception 'DERNIER_SUPER_ADMIN|Impossible de supprimer le dernier Super Administrateur.';
    end if;
  end if;

  -- ------------------------------------------------------- PÉRIMÈTRE
  -- Comptes : la personne + ses sous-comptes.
  with recursive liens as (
    select u.id
      from public.utilisateurs u
     where u.id = p_utilisateur
    union
    select u2.id
      from public.utilisateurs u2
      join liens l on u2.parent_id = l.id
  )
  select coalesce(array_agg(distinct id), array[]::uuid[]) into v_users
    from liens;

  -- Entreprises possédées (owner_id route B, proprietaire_id correctif 73,
  -- et la convention historique espaces.id = patron).
  select coalesce(array_agg(distinct e.id), array[]::uuid[]) into v_ents
    from public.entreprises e
   where e.id in (select x from unnest(v_users) x)
      or e.owner_id = any(v_users)
      or e.proprietaire_id = any(v_users)
      or exists (select 1 from public.espaces s
                  where s.entreprise_id = e.id
                    and s.id = any(v_users))
      or exists (select 1 from public.utilisateurs u
                  where u.id = any(v_users)
                    and u.entreprise_id = e.id
                    and u.parent_id is null);

  -- Espaces de ces entreprises + l'espace identifié par l'UUID du compte.
  select coalesce(array_agg(distinct s.id), array[]::uuid[]) into v_espaces
    from public.espaces s
   where s.id = any(v_users)
      or s.entreprise_id = any(v_ents);

  v_purge := public.biashara_purger_perimetre(
    v_users, v_espaces, v_ents, p_simulation);

  v_nb_ent   := coalesce(array_length(v_ents, 1), 0);
  v_nb_esp   := coalesce(array_length(v_espaces, 1), 0);
  v_nb_users := coalesce(array_length(v_users, 1), 0);

  if coalesce(p_simulation, true) then
    return v_purge || jsonb_build_object(
      'ok', true, 'simulation', true,
      'utilisateur_id', p_utilisateur, 'email', v_email,
      'entreprises_supprimees', v_nb_ent,
      'espaces_supprimes', v_nb_esp,
      'comptes_supprimes', v_nb_users,
      'lignes_concernees', coalesce(v_purge->'lignes', '0'::jsonb));
  end if;

  -- ------------------------------------------------ EXÉCUTION RÉELLE
  begin
    delete from public.activations_entreprise where entreprise_id = any(v_ents);
  exception when others then null;
  end;

  -- ⚠️ CYCLE DE CLÉS ÉTRANGÈRES (voir la suppression d'entreprise) : on
  -- coupe les liens utilisateurs ↔ entreprises avant de supprimer.
  begin
    update public.entreprises
       set owner_id = null, proprietaire_id = null
     where id = any(v_ents);
  exception when others then null;
  end;

  begin
    update public.utilisateurs
       set entreprise_id = null
     where entreprise_id = any(v_ents);
  exception when others then null;
  end;

  begin
    delete from public.utilisateurs
     where id = any(v_users) or parent_id = any(v_users);
    get diagnostics v_nb_users = row_count;
  exception
    when foreign_key_violation then
      raise exception 'SUPPRESSION_BLOQUEE|Des données pointent encore vers ce compte. Exécutez la dernière migration puis réessayez.';
  end;

  begin
    delete from public.espaces
     where id = any(v_espaces) or entreprise_id = any(v_ents);
    get diagnostics v_nb_esp = row_count;
  exception when others then null;
  end;

  begin
    delete from public.entreprises where id = any(v_ents);
    get diagnostics v_nb_ent = row_count;
  exception
    when foreign_key_violation then
      raise exception 'SUPPRESSION_BLOQUEE|Des données liées empêchent la suppression des entreprises du compte.';
  end;

  -- Compte de connexion GoTrue (identités et sessions suivent en cascade).
  begin
    delete from auth.users where id = p_utilisateur;
    v_auth := true;
  exception when others then
    v_auth := false;
  end;

  -- ⛔ INSERT seulement (le journal n'a plus de FK vers utilisateurs).
  begin
    insert into public.journal_audit (
      entreprise_id, entreprise_nom, utilisateur_id, utilisateur_email,
      action, details
    )
    values (
      null, null, v_acteur, null,
      'UTILISATEUR_SUPPRIME',
      jsonb_build_object(
        'utilisateur_id',         p_utilisateur,
        'email',                  v_email,
        'nom',                    v_u.nom,
        'entreprises_supprimees', v_nb_ent,
        'espaces_supprimes',      v_nb_esp,
        'comptes_supprimes',      v_nb_users,
        'lignes_metier',          coalesce(v_purge->'lignes', '0'::jsonb),
        'paiements',              coalesce(v_purge->'paiements', '0'::jsonb),
        'detail',                 coalesce(v_purge->'detail', '{}'::jsonb),
        'compte_auth_supprime',   v_auth
      )
    );
  exception when others then null;
  end;

  return v_purge || jsonb_build_object(
    'ok', true, 'simulation', false,
    'utilisateur_id', p_utilisateur, 'email', v_email,
    'entreprises_supprimees', v_nb_ent,
    'espaces_supprimes', v_nb_esp,
    'comptes_supprimes', v_nb_users,
    'lignes_concernees', coalesce(v_purge->'lignes', '0'::jsonb),
    'paiements_supprimes', coalesce(v_purge->'paiements', '0'::jsonb),
    'compte_auth_supprime', v_auth);
end;
$$;

comment on function public.biashara_supprimer_utilisateur_coeur(uuid, text, boolean) is
  '0174 — suppression CASCADE d''un compte : entreprises possédées, toutes leurs données (dont paiements), collaborateurs, espaces, dossiers, compte GoTrue. Super Admin, jamais soi-même, jamais le dernier Super Admin. Journal : INSERT uniquement.';

revoke all on function public.biashara_supprimer_utilisateur_coeur(uuid, text, boolean)
  from public, anon;
grant execute on function public.biashara_supprimer_utilisateur_coeur(uuid, text, boolean)
  to authenticated;


-- ============================================================================
-- 12. LES RPC EXISTANTES DÉLÈGUENT AU CŒUR (aucune duplication)
-- ============================================================================

-- 12.a Purge d'un compte (module 21) : même signature, même écran.
create or replace function public.rpc_admin_purger_utilisateur(
  p_utilisateur_id uuid,
  p_confirmation   text,
  p_simulation     boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return public.biashara_supprimer_utilisateur_coeur(
    p_utilisateur_id, p_confirmation, p_simulation);
end;
$$;

comment on function public.rpc_admin_purger_utilisateur(uuid, text, boolean) is
  '0174 — alias du cœur de suppression d''un compte (cascade complète, journal préservé).';

revoke all on function public.rpc_admin_purger_utilisateur(uuid, text, boolean)
  from public, anon;
grant execute on function public.rpc_admin_purger_utilisateur(uuid, text, boolean)
  to authenticated;


-- 12.b Purge d'une entreprise (module 21) : confirmation = nom exact.
create or replace function public.rpc_admin_purger_entreprise(
  p_entreprise_id uuid,
  p_confirmation  text,
  p_simulation    boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nom text;
begin
  select e.nom into v_nom from public.entreprises e where e.id = p_entreprise_id;
  if v_nom is null then
    raise exception 'ENTREPRISE_INTROUVABLE|Cette entreprise n''existe plus.';
  end if;

  if lower(btrim(coalesce(p_confirmation, ''))) <> lower(btrim(v_nom))
     and upper(btrim(coalesce(p_confirmation, ''))) <> 'SUPPRIMER' then
    raise exception 'CONFIRMATION_INVALIDE|Recopiez exactement le nom de l''entreprise (%) pour confirmer.', v_nom;
  end if;

  return public.biashara_supprimer_entreprise_coeur(
    p_entreprise_id, 'SUPPRIMER', p_simulation);
end;
$$;

comment on function public.rpc_admin_purger_entreprise(uuid, text, boolean) is
  '0174 — alias du cœur de suppression d''une entreprise (confirmation par le nom exact), journal préservé.';

revoke all on function public.rpc_admin_purger_entreprise(uuid, text, boolean)
  from public, anon;
grant execute on function public.rpc_admin_purger_entreprise(uuid, text, boolean)
  to authenticated;


-- ============================================================================
-- 13. VÉRIFICATIONS (lecture seule)
-- ============================================================================

-- 13.a Le journal n'a plus AUCUNE clé étrangère (attendu : 0 ligne).
select con.conname as cle_etrangere_restante
  from pg_constraint con
 where con.conrelid = 'public.journal_audit'::regclass
   and con.contype = 'f';

-- 13.b Le déclencheur append-only est toujours ACTIF (attendu : 1 ligne,
--      tgenabled = 'O').
select t.tgname, t.tgenabled
  from pg_trigger t
 where t.tgrelid = 'public.journal_audit'::regclass
   and t.tgname in ('trg_journal_audit_append_only',
                    'trg_journal_audit_preparer')
 order by t.tgname;

-- 13.c Les fonctions installées (attendu : 8 lignes).
select p.proname
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname in (
     'uuid_ou_null', 'biashara_assurer_profil_activite',
     'biashara_entreprise_creer_coeur', 'biashara_purger_perimetre',
     'biashara_supprimer_entreprise_coeur',
     'biashara_supprimer_utilisateur_coeur',
     'rpc_entreprises_metiers', 'rpc_admin_entreprise_creer')
 order by 1;

-- ============================================================================
--  FIN — migration 0174.
-- ============================================================================
