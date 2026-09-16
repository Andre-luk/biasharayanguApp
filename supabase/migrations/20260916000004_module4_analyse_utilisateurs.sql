-- ============================================================================
--  biashara_yangu — MODULE 4, ÉTAPE 1 : ANALYSE DES UTILISATEURS EXISTANTS
--
--  ⚠️ SCRIPT EN LECTURE SEULE : il ne crée, ne modifie et ne supprime RIEN.
--     Vous pouvez l'exécuter sans aucun risque, autant de fois que nécessaire.
--
--  OÙ L'EXÉCUTER
--    Supabase Dashboard → SQL Editor → New query → coller → Run
--
--  CE QU'IL RÉPOND
--    A. Quelles sont les colonnes réellement présentes dans `utilisateurs` ?
--    B. Quelles valeurs le type `role_utilisateur_enum` accepte-t-il ?
--    C. Combien d'utilisateurs par rôle (ancien `role` et nouveau `new_role`) ?
--    D. Qui sont les utilisateurs de la plateforme (sans entreprise) ?
--    E. Le nouveau rôle est-il déjà renseigné (new_role NULL) ?
--    F. Que contient `app_settings` (futur stockage des permissions) ?
--    G. Quelles policies / triggers protègent déjà ces tables ?
--
--  IMPORTANT
--    Copiez le résultat des sections A, B, C et E : ce sont elles qui
--    déterminent la migration Module 4 (mapping des rôles hérités).
-- ============================================================================


-- ============================================================================
--  A. COLONNES RÉELLES DE public.utilisateurs
-- ============================================================================

select
  column_name,
  data_type,
  udt_name,
  is_nullable,
  column_default
from information_schema.columns
where table_schema = 'public'
  and table_name = 'utilisateurs'
order by ordinal_position;


-- ============================================================================
--  B. VALEURS ACTUELLES DU TYPE role_utilisateur_enum
-- ============================================================================
--  C'est la liste de référence : tout rôle absent de ce résultat devra être
--  ajouté par `20260916000005_module4_permissions_enum.sql`.

select
  e.enumlabel  as valeur,
  e.enumsortorder as position
from pg_type t
join pg_enum e on e.enumtypid = t.oid
where t.typname = 'role_utilisateur_enum'
order by e.enumsortorder;


-- ============================================================================
--  C. RÉPARTITION DES UTILISATEURS PAR RÔLE
-- ============================================================================

select
  coalesce(role, '(NULL)')                       as ancien_role,
  coalesce(new_role::text, '(NULL)')             as nouveau_role,
  count(*)                                       as nb_utilisateurs,
  count(*) filter (where new_role is null)       as nb_sans_nouveau_role,
  count(*) filter (where entreprise_id is null)  as nb_sans_entreprise,
  count(*) filter (where parent_id is null)      as nb_sans_parent,
  count(*) filter (where coalesce(valide, 1) = 0) as nb_desactives
from public.utilisateurs
group by 1, 2
order by nb_utilisateurs desc, ancien_role;


-- ============================================================================
--  D. UTILISATEURS DE LA PLATEFORME (les seuls autorisés côté La Perle)
-- ============================================================================
--  Un compte « plateforme » = compte qui n'est rattaché à aucune entreprise
--  et qui n'est le collaborateur de personne.

select
  u.id,
  u.email,
  u.nom,
  u.prenom,
  coalesce(u.role, '(NULL)')            as ancien_role,
  coalesce(u.new_role::text, '(NULL)')  as nouveau_role,
  u.entreprise_id,
  u.parent_id,
  coalesce(u.valide, 1)                 as valide,
  u.created_at
from public.utilisateurs u
where u.entreprise_id is null
  and u.parent_id is null
order by
  case when u.role = 'admin' then 0 else 1 end,
  u.created_at;


-- ============================================================================
--  E. UTILISATEURS SANS NOUVEAU RÔLE (backfill nécessaire)
-- ============================================================================

select
  coalesce(role, '(NULL)')  as ancien_role,
  count(*)                  as nb_a_migrer
from public.utilisateurs
where new_role is null
group by 1
order by nb_a_migrer desc;

-- Détail (limité aux 100 premiers, suffisant pour un contrôle visuel) :
select
  u.id,
  u.email,
  coalesce(u.role, '(NULL)') as ancien_role,
  u.parent_id,
  u.entreprise_id,
  e.nom as entreprise
from public.utilisateurs u
left join public.entreprises e on e.id = u.entreprise_id
where u.new_role is null
order by u.created_at
limit 100;


-- ============================================================================
--  F. app_settings — support du stockage des permissions personnalisées
-- ============================================================================

select column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema = 'public'
  and table_name = 'app_settings'
order by ordinal_position;

select key, value, updated_at
from public.app_settings
order by key;


-- ============================================================================
--  G. POLICIES & TRIGGERS DÉJÀ EN PLACE
-- ============================================================================

select schemaname, tablename, policyname, cmd, roles, qual, with_check
from pg_policies
where schemaname = 'public'
  and tablename in ('utilisateurs', 'app_settings', 'entreprises', 'journal_audit')
order by tablename, policyname;

select
  c.relname          as table_concernee,
  t.tgname           as trigger,
  p.proname          as fonction,
  case when t.tgenabled = 'O' then 'actif' else t.tgenabled::text end as etat
from pg_trigger t
join pg_class c on c.oid = t.tgrelid
join pg_proc  p on p.oid = t.tgfoid
where not t.tgisinternal
  and c.relname in ('utilisateurs', 'app_settings', 'entreprises', 'auth_users_hack')
order by c.relname, t.tgname;

-- Triggers posés sur le schéma `auth` (création automatique du profil) :
select
  c.relname  as table_concernee,
  t.tgname   as trigger,
  p.proname  as fonction
from pg_trigger t
join pg_class c on c.oid = t.tgrelid
join pg_proc  p on p.oid = t.tgfoid
where not t.tgisinternal
  and c.relname in ('users', 'identities')
  and c.relnamespace = 'auth'::regnamespace
order by c.relname, t.tgname;


-- ============================================================================
--  H. SYNTHÈSE EN UNE LIGNE (pratique pour copier/coller dans l'écran)
-- ============================================================================

select
  (select count(*) from public.utilisateurs)                            as nb_utilisateurs,
  (select count(*) from public.utilisateurs where new_role is null)     as nb_sans_nouveau_role,
  (select count(*) from public.utilisateurs where entreprise_id is null) as nb_plateforme,
  (select count(distinct role) from public.utilisateurs)                as nb_roles_herites,
  (select count(*) from pg_enum e join pg_type t on t.oid = e.enumtypid
    where t.typname = 'role_utilisateur_enum')                          as nb_valeurs_enum;
