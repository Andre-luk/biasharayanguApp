-- ============================================================================
--  biashara_yangu — CORRECTIF 63 : SÉCURITÉ DES DROITS D'ÉCRITURE
--  Migration 20260916000063_agent_sans_droit_de_suspension.sql
-- ============================================================================
--
--  ⛔ AUCUNE COMPILATION, AUCUNE PUBLICATION : correction de base uniquement.
--
--  DEUX PROBLÈMES, DONT UN CRITIQUE
--  --------------------------------
--  1. 🔴 CRITIQUE — REMISE À ZÉRO OUVERTE À TOUT LE MONDE
--     `rpc_admin_remise_a_zero` (migration 44) n'exige QUE la phrase
--     « JE VEUX TOUT EFFACER ». Il n'y a AUCUN contrôle de rôle, et la
--     fonction est ouverte à `authenticated` — donc à TOUT compte connecté :
--     un agent, un vendeur, un commerçant. La fonction étant SECURITY
--     DEFINER, elle s'exécute avec les droits du propriétaire : la RLS ne la
--     protège pas. Un compte quelconque peut donc effacer l'ensemble des
--     comptes et des entreprises de la plateforme.
--
--     CORRECTIF : garde-fou `est_super_admin()` ajouté DANS la fonction.
--     (On ne peut pas simplement retirer le droit d'exécution :
--     l'application se connecte avec le rôle `authenticated`, le Super Admin
--     compris.)
--
--  2. 🟠 L'AGENT PEUT SUSPENDRE OU RÉACTIVER UN COMPTE
--     Le patron est formel : « l'agent n'a pas le droit de désactiver les
--     comptes ». Or l'agent possède `entreprises.modifier`, ce qui suffit à
--     traverser la policy RLS `entreprises_ecriture_permissions` (`for all`).
--     La suspension passe par un UPDATE DIRECT de `entreprises.statut` —
--     aucun contrôle serveur, aucune trace.
--
--     CORRECTIF : policies RLS RESTRICTIVES sur `entreprises` et
--     `utilisateurs` qui interdisent à l'agent de MODIFIER ou SUPPRIMER.
--     La lecture, la création et surtout les RPC `security definer`
--     (activation, rattachement, dossier) restent intactes : le métier de
--     l'agent n'est pas touché, il perd seulement le pouvoir de suspendre,
--     réactiver ou supprimer.
--
--  ⚠️ POURQUOI UNE POLICY RESTRICTIVE ET PAS SEULEMENT LA MATRICE
--  --------------------------------------------------------------
--  Les permissions par défaut peuvent être SURCHARGÉES dans `app_settings`
--  (`permissions_roles`). Une correction de la matrice serait donc écrasable
--  par une surcharge existante. Une policy RESTRICTIVE, elle, s'applique EN
--  PLUS des policies permissives : elle ne peut pas être contournée.
--  → La base refuse désormais, quoi qu'affiche l'interface.
--
--  IDEMPOTENTE : relançable sans effet de bord.
--  OÙ : Supabase → SQL Editor → coller → Run
-- ============================================================================


select set_config('search_path', 'public, extensions', true);


-- ============================================================================
--  1. 🔴 GARDE-FOU SUR LA REMISE À ZÉRO
-- ============================================================================
--  Patch ciblé (remplacement de chaîne littérale) plutôt que réécriture : le
--  corps de la fonction reste celui d'origine, on insère uniquement le
--  contrôle de rôle juste avant la résolution du Super Admin.

do $garde_remise_a_zero$
declare
  v_def        text;
  v_new        text;
  v_motif      text := E'select u.id into v_admin\n    from public.utilisateurs u';
  v_repl       text := E'if not public.est_super_admin() then\n'
                     || E'    raise exception ''DROIT_REFUSE|Seul le Super Admin peut lancer une remise a zero de la plateforme.'';\n'
                     || E'  end if;\n\n'
                     || E'  select u.id into v_admin\n'
                     || E'    from public.utilisateurs u';
  v_occurrences integer;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname = 'rpc_admin_remise_a_zero'
   limit 1;

  if v_def is null then
    raise warning 'Correctif 63 : rpc_admin_remise_a_zero introuvable — garde-fou NON pose.';
    return;
  end if;

  if position('est_super_admin()' in v_def) > 0 then
    raise notice 'Correctif 63 : la remise a zero est deja protegee.';
    return;
  end if;

  --  Le motif doit être présent EXACTEMENT une fois, sinon on ne touche à rien.
  v_occurrences := (length(v_def) - length(replace(v_def, v_motif, '')))
                   / length(v_motif);

  if v_occurrences <> 1 then
    raise warning 'Correctif 63 : motif de la remise a zero present % fois (attendu 1) — AUCUNE modification. Transmettez ce message.',
                  v_occurrences;
    return;
  end if;

  v_new := replace(v_def, v_motif, v_repl);
  execute v_new;

  raise notice 'Correctif 63 : remise a zero reservee au Super Admin.';
end $garde_remise_a_zero$;


-- ============================================================================
--  2. 🟠 L'AGENT PERD LE DROIT DE MODIFIER OU SUPPRIMER UN COMPTE
-- ============================================================================
--  Policies RESTRICTIVES : elles se combinent en AND avec les policies
--  permissives existantes. L'agent peut encore LIRE, CRÉER et, surtout,
--  utiliser toutes les RPC d'activation (elles sont `security definer` et
--  s'exécutent avec les droits du propriétaire).

drop policy if exists entreprises_agent_sans_modification on public.entreprises;
create policy entreprises_agent_sans_modification on public.entreprises
  as restrictive
  for update
  to authenticated
  using (not public.est_agent_terrain())
  with check (not public.est_agent_terrain());

drop policy if exists entreprises_agent_sans_suppression on public.entreprises;
create policy entreprises_agent_sans_suppression on public.entreprises
  as restrictive
  for delete
  to authenticated
  using (not public.est_agent_terrain());

--  Même règle sur les COMPTES UTILISATEURS : désactiver un compte, c'est
--  aussi passer `utilisateurs.valide` à false.
drop policy if exists utilisateurs_agent_sans_modification on public.utilisateurs;
create policy utilisateurs_agent_sans_modification on public.utilisateurs
  as restrictive
  for update
  to authenticated
  using (not public.est_agent_terrain())
  with check (not public.est_agent_terrain());

drop policy if exists utilisateurs_agent_sans_suppression on public.utilisateurs;
create policy utilisateurs_agent_sans_suppression on public.utilisateurs
  as restrictive
  for delete
  to authenticated
  using (not public.est_agent_terrain());


-- ============================================================================
--  3. CONTRÔLE
-- ============================================================================

do $verif_securite$
declare
  v_def text;
  v_nb  integer;
begin
  --  3.a Le garde-fou de la remise à zéro.
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname = 'rpc_admin_remise_a_zero'
   limit 1;

  if v_def is not null and position('est_super_admin()' in v_def) = 0 then
    raise exception 'Correctif 63 : la remise a zero reste OUVERTE — ne poursuivez pas, transmettez ce message.';
  end if;

  --  3.b Les quatre policies restrictives.
  select count(*) into v_nb
    from pg_policies
   where schemaname = 'public'
     and policyname in ('entreprises_agent_sans_modification',
                        'entreprises_agent_sans_suppression',
                        'utilisateurs_agent_sans_modification',
                        'utilisateurs_agent_sans_suppression');

  if v_nb <> 4 then
    raise exception 'Correctif 63 : % policy(ies) restrictive(s) sur 4 installee(s).', v_nb;
  end if;

  raise notice 'Correctif 63 : remise a zero protegee, agent prive d ecriture sur les comptes.';
end $verif_securite$;


-- ============================================================================
--  RAPPORT FINAL
--  ⚠️ En DERNIER : le SQL Editor n'affiche que le résultat de la dernière
--     instruction du script.
-- ============================================================================

select p.schemaname                as schema,
       p.tablename                 as table_cible,
       p.policyname                as regle,
       p.cmd                       as operation,
       p.permissive                as type_regle,
       coalesce(left(p.qual, 60), '—') as condition
  from pg_policies p
 where p.schemaname = 'public'
   and p.policyname in ('entreprises_agent_sans_modification',
                        'entreprises_agent_sans_suppression',
                        'utilisateurs_agent_sans_modification',
                        'utilisateurs_agent_sans_suppression')
 order by p.tablename, p.cmd;


-- ============================================================================
--  NOTE — CE QU'IL RESTE À FAIRE CÔTÉ APPLICATION (prochaine compilation)
--  ------------------------------------------------------------------------
--  La base refuse désormais l'écriture. Reste à NE PLUS AFFICHER les boutons
--  à l'agent, pour qu'il ne reçoive pas un refus incompréhensible :
--
--    • `lib/services/permission_service.dart` — retirer `modifier` de
--      `PageAccess.entreprises` dans la matrice du rôle `agentTerrain` ;
--    • `lib/pages/entreprise_detail_page.dart` — entourer le bouton
--      « Suspendre / Activer » (≈ ligne 516) d'un `PermissionGate`.
--
--  ⚠️ VÉRIFIER AUSSI LES SURCHARGES DE PERMISSIONS : si un réglage
--  `app_settings → permissions_roles` accorde `entreprises.modifier` à
--  AGENT_TERRAIN, le bouton restera affiché (la base refusera l'écriture).
--  Pour le contrôler :
--
--    select public.permissions_effectives('AGENT_TERRAIN');
--
--  et pour revenir aux droits par défaut :
--
--    select public.rpc_permissions_reset('AGENT_TERRAIN');
-- ============================================================================
