-- ============================================================================
--  MODULE 21 quater — FUITE DE LECTURE SUR `entreprises`
--  Migration 20260916000050_fix_rls_entreprises.sql
-- ============================================================================
--
--  À exécuter APRÈS les migrations 47, 48 et 49. IDEMPOTENTE.
--
--  LE DÉFAUT
--  ---------
--  La policy de lecture posée par le module 1 est TOTALE :
--
--      create policy "entreprises_lecture" on public.entreprises
--        for select to authenticated using (true);
--
--  Conséquence CONSTATÉE en production : un commerçant qui interroge
--  `entreprises` reçoit TOUTES les entreprises de la plateforme (nom, statut,
--  échéance, soldes) — pas seulement la sienne. Le module 4 avait laissé la
--  lecture ouverte par prudence (« l'application en dépend »), mais c'est une
--  fuite de données entre commerçants.
--
--  LA CORRECTION
--  -------------
--  La lecture est ramenée au PÉRIMÈTRE LÉGITIME :
--    • le personnel plateforme (Super Admin, gestionnaire, finance, support)
--      voit tout — c'est son métier ;
--    • un AGENT TERRAIN voit les entreprises qu'il a prises en charge
--      (`agent_id`), comme partout ailleurs depuis la migration 47 ;
--    • tout autre compte ne voit QUE SON entreprise (`utilisateurs.entreprise_id`,
--      ou celle de son patron pour un collaborateur).
--
--  Les ÉCRITURES ne changent pas : elles restent gouvernées par
--  `entreprises_ecriture_permissions` (module 4). Les RPC `security definer`
--  (création d'entreprise, activation, purge…) ne sont pas affectées : elles
--  s'exécutent avec les droits du propriétaire et contournent la RLS.
-- ============================================================================


-- ============================================================================
--  1. HELPER — L'ENTREPRISE DE L'UTILISATEUR CONNECTÉ
-- ============================================================================
--  Même règle que `rpc_entreprises_de_utilisateur` : la colonne de
--  l'utilisateur, ou celle de son patron quand il est collaborateur.

create or replace function public.mon_entreprise_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(utilisateur.entreprise_id, patron.entreprise_id)
    from public.utilisateurs utilisateur
    left join public.utilisateurs patron
           on patron.id = utilisateur.parent_id
   where utilisateur.id = auth.uid();
$$;

comment on function public.mon_entreprise_id() is
  'Module 21 quater — Entreprise de l''utilisateur connecté (celle de son patron pour un collaborateur).';

revoke all on function public.mon_entreprise_id() from public, anon;
grant execute on function public.mon_entreprise_id() to authenticated;


-- ============================================================================
--  2. POLICY DE LECTURE — CLOISONNÉE SUR LE PÉRIMÈTRE
-- ============================================================================

drop policy if exists "entreprises_lecture" on public.entreprises;
drop policy if exists entreprises_lecture_perimetre on public.entreprises;

create policy entreprises_lecture_perimetre on public.entreprises
  for select to authenticated
  using (
    public.est_plateforme()
    or public.agent_detient_entreprise(id)
    or id = public.mon_entreprise_id()
  );

comment on policy entreprises_lecture_perimetre on public.entreprises is
  'Module 21 quater — Lecture limitée au périmètre : plateforme = tout ; agent = ses entreprises ; commerçant = la sienne. Remplace la policy « entreprises_lecture » (using true) qui exposait toutes les entreprises.';


-- ============================================================================
--  3. VÉRIFICATION — RUN SÉPARÉ
-- ============================================================================
--  ⚠️ Le SQL Editor exécute tout en UNE transaction : ces contrôles sont
--  commentés pour ne pas annuler le DDL en cas d'échec.
--
--  -- Policy de lecture restante (doit être entreprises_lecture_perimetre,
--  -- et NON entreprises_lecture) :
--  select policyname, qual
--    from pg_policies
--   where schemaname = 'public' and tablename = 'entreprises'
--     and cmd in ('SELECT', 'ALL');
--
--  -- Avec la session d'un commerçant : ne doit renvoyer QUE son entreprise.
--  -- select id, nom, statut from public.entreprises;
-- ============================================================================
--  FIN — correctif 50.
-- ============================================================================
