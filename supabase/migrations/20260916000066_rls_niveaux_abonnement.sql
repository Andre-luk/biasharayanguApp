-- ============================================================================
--  biashara_yangu — CORRECTIF 66 : SÉCURITÉ DE LA TABLE DES NIVEAUX
--  Migration 20260916000066_rls_niveaux_abonnement.sql
-- ============================================================================
--
--  ⛔ AUCUNE COMPILATION, AUCUNE PUBLICATION : correction de base uniquement.
--
--  LE TROU QUE JE DOIS FERMER — ET SON ORIGINE
--  -------------------------------------------
--  La migration 65 a créé la table `niveaux_abonnement` SANS activer la
--  sécurité par ligne (RLS). Or, sur Supabase, une table du schéma `public`
--  sans RLS est accessible en LECTURE **ET EN ÉCRITURE** à tout compte
--  connecté via l'API (PostgREST).
--
--  Conséquence : n'importe quel commerçant authentifié aurait pu, avec une
--  simple requête, s'octroyer le niveau « Premium » — c'est-à-dire toutes les
--  fonctionnalités — ou modifier les prix affichés du catalogue.
--
--  C'est exactement le genre de défaut qu'il faut corriger AVANT de publier,
--  et non après.
--
--  CE QUE FAIT CETTE MIGRATION
--  ---------------------------
--    1. ACTIVE la sécurité par ligne sur `niveaux_abonnement` ;
--    2. accorde UNIQUEMENT la LECTURE (le catalogue des offres est public :
--       un commerçant doit pouvoir voir ce que chaque niveau contient) ;
--    3. n'accorde AUCUNE écriture directe : les seules écritures passent par
--       les RPC `rpc_abonnement_niveau_enregistrer` et
--       `rpc_abonnement_niveau_supprimer`, qui vérifient le rôle et
--       journalisent l'opération.
--
--  POURQUOI LES RPC CONTINUENT DE FONCTIONNER
--  ------------------------------------------
--  Elles sont `security definer` : elles s'exécutent avec les droits du
--  propriétaire et ne sont donc pas soumises à ces policies. La RLS bloque
--  l'écriture DIRECTE depuis l'application — c'est précisément ce qu'on veut.
--
--  IDEMPOTENTE : relançable sans effet de bord.
--  OÙ : Supabase → SQL Editor → coller → Run
--  ⚠️ À EXÉCUTER APRÈS le correctif 65.
-- ============================================================================


select set_config('search_path', 'public, extensions', true);


-- ============================================================================
--  1. SÉCURITÉ PAR LIGNE
-- ============================================================================

alter table public.niveaux_abonnement enable row level security;

--  Lecture : ouverte aux comptes connectés (c'est la grille des offres).
drop policy if exists niveaux_abonnement_lecture on public.niveaux_abonnement;
create policy niveaux_abonnement_lecture on public.niveaux_abonnement
  for select
  to authenticated
  using (true);

--  ⚠️ AUCUNE policy d'écriture n'est créée — volontairement.
--  Sans policy permissive d'INSERT/UPDATE/DELETE, toute écriture DIRECTE est
--  refusée, même à un Super Admin. Pour modifier un niveau, l'application
--  passe obligatoirement par les RPC, qui vérifient le rôle ET laissent une
--  trace dans le journal d'audit.

revoke all on table public.niveaux_abonnement from anon;
revoke insert, update, delete, truncate on table public.niveaux_abonnement from authenticated;


-- ============================================================================
--  2. CONTRÔLE
-- ============================================================================

do $verif_rls_niveaux$
declare
  v_rls    boolean;
  v_select integer;
  v_ecrit  integer;
begin
  select c.relrowsecurity into v_rls
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relname = 'niveaux_abonnement';

  if not coalesce(v_rls, false) then
    raise exception 'Correctif 66 : la securite par ligne n''est PAS activee sur niveaux_abonnement — ne poursuivez pas.';
  end if;

  select count(*) into v_select
    from pg_policies
   where schemaname = 'public'
     and tablename = 'niveaux_abonnement'
     and cmd = 'SELECT';

  if v_select < 1 then
    raise exception 'Correctif 66 : aucune policy de lecture — le catalogue serait invisible.';
  end if;

  select count(*) into v_ecrit
    from pg_policies
   where schemaname = 'public'
     and tablename = 'niveaux_abonnement'
     and cmd in ('INSERT', 'UPDATE', 'DELETE', 'ALL');

  if v_ecrit > 0 then
    raise exception 'Correctif 66 : % policy(ies) d''ecriture directe subsistent — a retirer.', v_ecrit;
  end if;

  raise notice 'Correctif 66 : catalogue des niveaux protege (lecture seule, ecriture par RPC).';
end $verif_rls_niveaux$;


-- ============================================================================
--  RAPPORT FINAL
--  ⚠️ En DERNIER : le SQL Editor n'affiche que le résultat de la dernière
--     instruction du script.
-- ============================================================================

select c.relname                          as table_cible,
       case when c.relrowsecurity then 'ACTIVE' else '⛔ DESACTIVEE' end as securite_par_ligne,
       coalesce(p.policyname, '—')         as regle,
       coalesce(p.cmd, '—')                as operation,
       case
         when p.cmd = 'SELECT' then 'lecture autorisee'
         when p.cmd is null     then 'aucune ecriture directe : passer par les RPC'
         else '⚠️ a verifier'
       end                                 as verdict
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  left join pg_policies p
         on p.schemaname = n.nspname and p.tablename = c.relname
 where n.nspname = 'public'
   and c.relname = 'niveaux_abonnement'
 order by p.cmd nulls first;


-- ============================================================================
--  NOTE — CE QUI EST DÉSORMAIS POSSIBLE, ET CE QUI NE L'EST PLUS
--  ------------------------------------------------------------------------
--    ✅ tout compte connecté LIT le catalogue (nom, ordre, prix conseillé,
--       liste des fonctionnalités) ;
--    ✅ un Super Admin MODIFIE un niveau — via l'application, qui appelle
--       `rpc_abonnement_niveau_enregistrer` (rôle vérifié + journalisé) ;
--    ⛔ une écriture DIRECTE sur la table est refusée, quel que soit le rôle.
--       Un commerçant ne peut donc PAS s'octroyer un niveau supérieur.
--
--  Même précaution à vérifier pour les autres tables créées récemment :
--
--    select tablename, rowsecurity
--      from pg_tables
--     where schemaname = 'public' and not rowsecurity
--     order by tablename;
--
--  Toute table métier listée ici mérite une policy (les tables de
--  référentiel de Supabase, elles, sont protégées autrement).
-- ============================================================================
