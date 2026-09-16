-- ============================================================================
--  biashara_yangu — MODULE 4 : PERMISSIONS, ÉTAPE 2a — TYPE DES RÔLES
--
--  ⚠️ À EXÉCUTER EN PREMIER, ET DANS UNE EXÉCUTION SÉPARÉE
--     (une seule requête : ce fichier ne fait que compléter le type enum).
--
--  OÙ L'EXÉCUTER
--    Supabase Dashboard → SQL Editor → New query → coller → Run
--    puis exécuter `20260916000006_module4_permissions.sql` dans une
--    NOUVELLE requête.
--
--  POURQUOI UN FICHIER SÉPARÉ
--    PostgreSQL interdit d'UTILISER une valeur d'enum ajoutée dans la même
--    transaction que le `alter type`. En isolant l'ajout ici, le script
--    principal peut ensuite manipuler les rôles sans contrainte.
--    (Le script principal reste malgré tout protégé : il passe par
--    `public.role_enum(...)`, jamais par un littéral typé.)
--
--  IDEMPOTENT : `add value if not exists` → réexécutable sans effet de bord.
-- ============================================================================


-- ============================================================================
--  1. LE TYPE EXISTE-T-IL ?
-- ============================================================================
--  Votre base possède déjà `public.role_utilisateur_enum`. Sur une base
--  vierge, on le crée avec les huit rôles du Module 4.

do $$
begin
  if not exists (
    select 1
      from pg_type t
      join pg_namespace n on n.oid = t.typnamespace
     where t.typname = 'role_utilisateur_enum'
       and n.nspname = 'public'
  ) then
    create type public.role_utilisateur_enum as enum (
      'SUPER_ADMIN',
      'GESTIONNAIRE_COMPTES',
      'FINANCE_LAPERLE',
      'SUPPORT',
      'PROPRIETAIRE',
      'VENDEUR',
      'MAGASINIER',
      'COMPTABLE_ENTREPRISE'
    );
  end if;
end $$;


-- ============================================================================
--  2. AJOUT DES HUIT RÔLES (ceux déjà présents sont ignorés)
-- ============================================================================
--  Un rôle déjà utilisé ne peut évidemment pas être retiré : ce script ne
--  fait qu'ajouter. L'ordre d'ajout n'a aucune importance.

alter type public.role_utilisateur_enum add value if not exists 'SUPER_ADMIN';
alter type public.role_utilisateur_enum add value if not exists 'GESTIONNAIRE_COMPTES';
alter type public.role_utilisateur_enum add value if not exists 'FINANCE_LAPERLE';
alter type public.role_utilisateur_enum add value if not exists 'SUPPORT';
alter type public.role_utilisateur_enum add value if not exists 'PROPRIETAIRE';
alter type public.role_utilisateur_enum add value if not exists 'VENDEUR';
alter type public.role_utilisateur_enum add value if not exists 'MAGASINIER';
alter type public.role_utilisateur_enum add value if not exists 'COMPTABLE_ENTREPRISE';


-- ============================================================================
--  3. VÉRIFICATION
-- ============================================================================
--  Doit renvoyer les huit rôles ci-dessus (au minimum).

select
  e.enumlabel    as role_disponible,
  e.enumsortorder as position
from pg_type t
join pg_enum e on e.enumtypid = t.oid
join pg_namespace n on n.oid = t.typnamespace
where t.typname = 'role_utilisateur_enum'
  and n.nspname = 'public'
order by e.enumsortorder;
