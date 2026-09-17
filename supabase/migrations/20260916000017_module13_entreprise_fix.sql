-- ============================================================================
--  biashara_yangu — MODULE 13 : CORRECTIF « ENTREPRISE » (17)
--
--  POURQUOI CE FICHIER
--  ────────────────────────────────────────────────────────────────────────
--  1. BUG : ouvrir « Assistant IA » / « Quotas IA » échouait avec
--         insert or update on table "agent_ia_quotas" violates foreign key
--         constraint "agent_ia_quotas_entreprise_id_fkey"
--     Cause : les tables du Module 13 déclaraient `entreprise_id` en CLÉ
--     ÉTRANGÈRE vers `public.entreprises`, alors que TOUT le reste de
--     l'application (produits, ventes, caisse, journal…) désigne la boutique
--     par l'**identifiant du PATRON** (`mon_proprietaire()` = parent_id ou
--     id de l'utilisateur). Le pool de quotas insérait donc un identifiant
--     d'utilisateur dans une colonne qui exigeait une ligne `entreprises`.
--     → Ce correctif retire ces 4 contraintes : `entreprise_id` redevient la
--       « clé boutique » (identifiant du patron), comme partout ailleurs.
--
--  2. MANQUE : aucune entreprise (`public.entreprises`) n'était créée pour
--     les boutiques — or c'est ELLE qui porte l'abonnement (essai 7 jours,
--     statut, dates, paiements de la plateforme).
--     → `rpc_entreprise_creer(nom)` crée l'entreprise de la boutique du
--       compte connecté, la rattache (`utilisateurs.entreprise_id`) et
--       l'application l'appelle automatiquement à l'inscription.
--     → Un remplissage crée l'entreprise des comptes existants qui n'en
--       avaient pas, et rattache les collaborateurs à celle de leur patron.
--
--  3. `rpc_agent_ia_etat` est remis à jour :
--       • il s'assure qu'une entreprise existe (best-effort) ;
--       • `est_proprietaire` se base sur le RÔLE (PROPRIETAIRE) et non plus
--         sur une comparaison d'identifiants.
--
--  OÙ L'EXÉCUTER
--    Supabase Dashboard → SQL Editor → New query → coller → Run
--
--  PRÉ-REQUIS : 14, 15 et 16 déjà exécutés (Module 13).
--  ⚠️ IDEMPOTENT : peut être relancé sans dupliquer ni détruire de données.
-- ============================================================================


select set_config('search_path', 'public, extensions', true);


-- ============================================================================
--  1. FIN DES CLÉS ÉTRANGÈRES MAL POSÉES (MODULE 13)
-- ============================================================================
--  `entreprise_id` = « clé boutique » = identifiant du PATRON (utilisateur),
--  jamais une ligne de `public.entreprises`. Les contraintes d'origine
--  empêchaient donc toute écriture (pool de quotas, demandes d'achat,
--  conversations et actions de l'IA).

alter table public.agent_ia_quotas
  drop constraint if exists agent_ia_quotas_entreprise_id_fkey;

alter table public.agent_ia_achats
  drop constraint if exists agent_ia_achats_entreprise_id_fkey;

alter table public.agent_ia_conversations
  drop constraint if exists agent_ia_conversations_entreprise_id_fkey;

alter table public.agent_ia_actions
  drop constraint if exists agent_ia_actions_entreprise_id_fkey;

comment on column public.agent_ia_quotas.entreprise_id is
  'Clé boutique = identifiant du PATRON (mon_proprietaire()) — PAS une ligne de public.entreprises (voir correctif 17).';


-- ============================================================================
--  2. `rpc_entreprise_creer` — CRÉER L'ENTREPRISE DE SA BOUTIQUE
-- ============================================================================
--  • appelée à l'inscription (nom de la boutique saisi par l'utilisateur) et
--    automatiquement en secours (nom de repli « Boutique <nom> ») ;
--  • l'essai de 7 jours, le statut et les dates sont posés par les DÉFAUTS
--    de `public.entreprises` ;
--  • idempotente : un compte déjà rattaché obtient l'entreprise existante.

create or replace function public.rpc_entreprise_creer(
  p_nom text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user  uuid := auth.uid();
  v_exist uuid;
  v_nomu  text;
  v_nom   text;
  v_new   uuid;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour créer votre entreprise.';
  end if;

  -- Déjà rattaché ? On ne duplique pas.
  select u.entreprise_id into v_exist
    from public.utilisateurs u
   where u.id = v_user;

  if v_exist is not null then
    return jsonb_build_object('ok', true, 'deja', true, 'entreprise_id', v_exist);
  end if;

  select coalesce(nullif(btrim(u.nom), ''), u.email) into v_nomu
    from public.utilisateurs u
   where u.id = v_user;

  v_nom := nullif(btrim(coalesce(p_nom, '')), '');
  if v_nom is null then
    v_nom := 'Boutique ' || coalesce(v_nomu, 'nouvelle');
  end if;

  insert into public.entreprises (nom)
  values (v_nom)
  returning id into v_new;

  update public.utilisateurs
     set entreprise_id = v_new
   where id = v_user;

  -- Trace (best-effort : ne doit jamais faire échouer la création).
  begin
    insert into public.journal_audit (entreprise_id, action, utilisateur_id, details)
    values (
      null, 'CREATION_ENTREPRISE', v_user,
      jsonb_build_object('entreprise_id', v_new, 'nom', v_nom)
    );
  exception when others then null;
  end;

  return jsonb_build_object('ok', true, 'deja', false,
                            'entreprise_id', v_new, 'nom', v_nom);
end;
$$;

comment on function public.rpc_entreprise_creer(text) is
  'Crée l''entreprise (abonnement/essai 7 jours) de la boutique du compte connecté et la lui rattache.';

revoke all on function public.rpc_entreprise_creer(text) from public;
revoke all on function public.rpc_entreprise_creer(text) from anon;
grant execute on function public.rpc_entreprise_creer(text) to authenticated;


-- ============================================================================
--  3. `rpc_agent_ia_etat` (v2) — SANS BLOCAGE PAR L'ENTREPRISE ABSENTE
-- ============================================================================

create or replace function public.rpc_agent_ia_etat()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user       uuid := auth.uid();
  v_plateforme boolean;
  v_owner      uuid;
  v_config     public.agent_ia_config%rowtype;
  v_pool       public.agent_ia_quotas%rowtype;
  v_moi        public.agent_ia_quotas%rowtype;
  v_collab     jsonb := '[]'::jsonb;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour consulter vos quotas.';
  end if;

  v_plateforme := public.est_plateforme();

  select * into v_config from public.agent_ia_config limit 1;
  if v_config.id is null then
    raise exception 'CONFIG_ABSENTE|Configuration IA absente : exécutez 20260916000014_module13_agent_ia.sql.';
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  -- S'assurer qu'une entreprise (abonnement) existe pour la boutique.
  -- Best-effort : si la création échoue, les quotas fonctionnent quand même.
  if not v_plateforme then
    begin
      perform public.rpc_entreprise_creer(null);
    exception when others then null;
    end;
  end if;

  -- POOL de l'entreprise + bonus de bienvenue (une seule fois).
  if not v_plateforme then
    select * into v_pool
      from public.agent_ia_quotas
     where utilisateur_id is null
       and entreprise_id = v_owner;

    if v_pool.id is null then
      insert into public.agent_ia_quotas (
        utilisateur_id, entreprise_id, quotas_disponibles, quotas_achetes_total
      ) values (
        null, v_owner, greatest(coalesce(v_config.quotas_offerts_inscription, 0), 0), 0
      )
      on conflict do nothing;

      select * into v_pool
        from public.agent_ia_quotas
       where utilisateur_id is null
         and entreprise_id = v_owner;
    end if;
  end if;

  -- Mon allocation personnelle.
  select * into v_moi
    from public.agent_ia_quotas
   where utilisateur_id = v_user;

  -- Collaborateurs de l'entreprise (pour l'attribution par le patron).
  if not v_plateforme and v_owner = v_user then
    select coalesce(jsonb_agg(jsonb_build_object(
             'id',   u.id,
             'nom',  coalesce(nullif(btrim(u.nom), ''), u.email),
             'role', coalesce(u.new_role::text, u.role, '')
           ) order by u.nom), '[]'::jsonb)
      into v_collab
      from public.utilisateurs u
     where u.id <> v_user
       and u.parent_id = v_owner;
  end if;

  return jsonb_build_object(
    'config', jsonb_build_object(
      'tarif_par_quota',           v_config.tarif_par_quota,
      'caracteres_par_quota',      v_config.caracteres_par_quota,
      'prix_pack_10_quotas',       v_config.prix_pack_10_quotas,
      'quotas_offerts_inscription', v_config.quotas_offerts_inscription,
      'actif',                     v_config.actif
    ),
    'pool', case when v_pool.id is null then null else jsonb_build_object(
      'quotas_disponibles',   v_pool.quotas_disponibles,
      'quotas_achetes_total', v_pool.quotas_achetes_total
    ) end,
    'moi', jsonb_build_object(
      'quotas_disponibles',    coalesce(v_moi.quotas_disponibles, 0),
      'quotas_utilises_total', coalesce(v_moi.quotas_utilises_total, 0),
      'quotas_achetes_total',  coalesce(v_moi.quotas_achetes_total, 0)
    ),
    'role',            public.mon_role(),
    'est_proprietaire', (not v_plateforme and public.mon_role() = 'PROPRIETAIRE'),
    'est_plateforme',  v_plateforme,
    'est_super_admin', public.est_super_admin(),
    'collaborateurs',  v_collab
  );
end;
$$;

comment on function public.rpc_agent_ia_etat() is
  'Module 13 — État IA : config, pool (+ bonus de bienvenue une fois), allocation, collaborateurs (correctif 17).';

revoke all on function public.rpc_agent_ia_etat() from public;
revoke all on function public.rpc_agent_ia_etat() from anon;
grant execute on function public.rpc_agent_ia_etat() to authenticated;


-- ============================================================================
--  4. REMPLISSAGE — ENTREPRISES DES COMPTES EXISTANTS
-- ============================================================================

-- 4.a Les PATRONS autonomes (sans entreprise) en reçoivent une.
--     Les comptes plateforme La Perle sont exclus (pas de boutique).
do $$
declare
  r     record;
  v_nom text;
  v_id  uuid;
begin
  for r in
    select u.id, u.nom, u.email
      from public.utilisateurs u
     where u.entreprise_id is null
       and u.parent_id is null
       and coalesce(u.new_role::text, '') not in (
         'SUPER_ADMIN', 'GESTIONNAIRE_COMPTES', 'SUPPORT', 'FINANCE_LAPERLE'
       )
     order by u.created_at
  loop
    v_nom := 'Boutique ' || coalesce(nullif(btrim(r.nom), ''), r.email, 'nouvelle');
    insert into public.entreprises (nom) values (v_nom) returning id into v_id;
    update public.utilisateurs set entreprise_id = v_id where id = r.id;
  end loop;
end $$;

-- 4.b Les COLLABORATEURS (parent_id) héritent de l'entreprise du patron.
update public.utilisateurs c
   set entreprise_id = p.entreprise_id
  from public.utilisateurs p
 where c.parent_id = p.id
   and c.entreprise_id is null
   and p.entreprise_id is not null;


-- ============================================================================
--  5. VÉRIFICATIONS
-- ============================================================================

-- 5.a Plus aucune contrainte FK mal posée sur les tables IA (0 ligne attendue).
select conrelid::regclass as table_concernee, conname
  from pg_constraint
 where conname like 'agent_ia%entreprise_id_fkey';

-- 5.b Entreprises créées et rattachements.
select count(*) as entreprises_total from public.entreprises;

select u.new_role                as role,
       coalesce(u.nom, u.email)  as compte,
       e.nom                     as entreprise,
       e.statut                  as abonnement,
       e.date_expiration
  from public.utilisateurs u
  left join public.entreprises e on e.id = u.entreprise_id
 where u.entreprise_id is not null
 order by u.new_role, u.nom
 limit 40;

-- 5.c Contrôle du pool IA d'Anaclet (exemple — remplacez l'email) :
--
-- select utilisateur_id, entreprise_id, quotas_disponibles, quotas_achetes_total
--   from public.agent_ia_quotas
--  where entreprise_id = (select id from public.utilisateurs
--                          where email = 'ananclet@biashara.com');
