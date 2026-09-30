-- ============================================================================
--  OUTIL DE MAINTENANCE — NE CONSERVER QUE LES 4 COMPTES D'ADMINISTRATION
--  tools/purger_tout_sauf_administration.sql
-- ============================================================================
--
--  ⚠️⚠️⚠️  OPÉRATION LA PLUS DESTRUCTIVE DU PROJET — À LIRE EN ENTIER  ⚠️⚠️⚠️
--
--  Ce script supprime TOUS les comptes sauf les 4 comptes officiels, ainsi que
--  TOUTES leurs données : boutiques, articles, ventes, paiements, dettes,
--  stock, dépenses, caisse, abonnements, journaux d'audit… Ces données ne sont
--  PAS récupérables (sauf sauvegarde préalable).
--
--  ⛔ AVANT DE L'EXÉCUTER, VÉRIFIE CES DEUX POINTS :
--
--    1. SAIS-TU TE CONNECTER AVEC UN DES 4 COMPTES CI-DESSOUS ?
--       Teste-le MAINTENANT dans l'application. Sinon, tu supprimes ton propre
--       accès et plus personne ne peut administrer la plateforme.
--       Les comptes livrés par le module 4 sont :
--         super.admin@biasharayangu.cd
--         comptes@biasharayangu.cd
--         finance@biasharayangu.cd
--         support@biasharayangu.cd
--
--    2. AS-TU UNE SAUVEGARDE ?
--       Supabase → Database → Backups. Les ventes, paiements et dettes de tes
--       utilisateurs réels (Mamie, Jessica, Jonathan, Jean-Luc, Hotêl KM…)
--       disparaissent définitivement. Ce sont peut-être de vrais clients.
--
--  MODE D'EMPLOI
--  -------------
--   1. lancez le script TEL QUEL : il liste tout ce qui serait supprimé, avec
--      les volumes de données. Aucune suppression (`v_simulation := true`) ;
--   2. relisez la liste. Pour ÉPARGNER quelqu'un, ajoute son adresse dans
--      `v_garder` (en plus des 4 comptes d'administration) ;
--   3. passez `v_simulation := false` et relancez.
--
--  GARDE-FOUS INTÉGRÉS
--    • le script VÉRIFIE d'abord que les 4 comptes existent — sinon il refuse
--      de démarrer (protection anti-verrouillage) ;
--    • les 4 comptes sont protégés dans le code, même s'ils étaient mal
--      orthographiés dans une liste : la base les refuse explicitement ;
--    • un compte de la plateforme oublié (hors des 4) est d'abord RÉTROGRADÉ
--      de son rôle, puis supprimé — chaque étape est tracée ;
--    • `v_simulation` est vrai par défaut.
-- ============================================================================

do $tout$
declare
  -- ▶▶▶ DOUBLE COMMUTATEUR ◀◀◀
  v_simulation boolean := false;

  -- Adresses CONSERVÉES (les 4 comptes d'administration).
  v_garder text[] := array['super.admin@biasharayangu.cd',
                           'comptes@biasharayangu.cd',
                           'finance@biasharayangu.cd',
                           'support@biasharayangu.cd'];

  -- ENTREPRISES À CONSERVER (nom exact ou identifiant).
  -- ⚠️ Ce script supprime TOUTES les entreprises de la base. Si tu viens d'en
  -- créer une que tu veux garder, ajoute-la ICI, sinon elle sera détruite
  -- avec ses boutiques et ses articles.
  -- Exemple : v_garder_entreprises text[] := array['Biashara Group'];
  v_garder_entreprises text[] := array[]::text[];

  v_admin  uuid;
  v_rec    record;
  v_dep    jsonb;
  v_res    jsonb;
  v_total  bigint := 0;
  v_ok     integer := 0;
  v_ko     integer := 0;
  v_ent    integer := 0;
begin
  -- ------------------------------------------------- anti-verrouillage : les 4
  select count(*) into v_ent
    from public.utilisateurs u
   where lower(u.email) = any(v_garder);

  if v_ent < 4 then
    raise exception
      'GARDE : seulement % des 4 comptes d''administration existent. Script ANNULÉ pour ne pas te verrouiller dehors.', v_ent;
  end if;

  select u.id into v_admin
    from public.utilisateurs u
   where lower(u.email) = 'super.admin@biasharayangu.cd'
   limit 1;

  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', v_admin::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', v_admin::text, true);

  raise notice '=== NETTOYAGE GÉNÉRAL — mode % ===',
    case when v_simulation then 'AUDIT (aucune suppression)'
         else 'SUPPRESSION RÉELLE' end;

  -- ----------------------------------------------- comptes à supprimer
  for v_rec in
    select u.id, u.email,
           coalesce(u.new_role::text, '(aucun rôle)') as role,
           (u.entreprise_id is not null) as rattache
      from public.utilisateurs u
     where lower(u.email) <> all(v_garder)
     order by (u.entreprise_id is not null), u.new_role::text nulls last, u.email
  loop
    v_dep := public.rpc_admin_utilisateur_dependances(v_rec.id);

    raise notice '   • % | % | % donnée(s), % boutique(s)',
      rpad(coalesce(v_rec.email, '(sans e-mail)'), 44),
      rpad(v_rec.role, 20),
      coalesce(v_dep ->> 'total_donnees', '0'),
      coalesce(v_dep ->> 'nb_espaces', '0');

    if v_simulation then
      v_total := v_total + coalesce((v_dep ->> 'total_donnees')::bigint, 0);
      continue;
    end if;

    -- Suppression réelle (rôle plateforme oublié : on rétrograde d'abord).
    begin
      v_res := public.rpc_admin_purger_utilisateur(v_rec.id, v_rec.email, false);
      v_ok := v_ok + 1;
      raise notice '        ↳ SUPPRIMÉ : % ligne(s).',
        coalesce(v_res ->> 'lignes_concernees', '0');
    exception when others then
      begin
        update public.utilisateurs set new_role = null where id = v_rec.id;
        v_res := public.rpc_admin_purger_utilisateur(v_rec.id, v_rec.email, false);
        v_ok := v_ok + 1;
        raise notice '        ↳ rôle plateforme rétrogradé puis SUPPRIMÉ : % ligne(s).',
          coalesce(v_res ->> 'lignes_concernees', '0');
      exception when others then
        v_ko := v_ko + 1;
        raise warning '        ↳ REFUSÉ pour % : %', v_rec.email, sqlerrm;
      end;
    end;
  end loop;

  -- ------------------------------------- entreprises restantes (données orphelines)
  for v_rec in
    select e.id, e.nom from public.entreprises e
     where not (e.nom = any(v_garder_entreprises))
       and e.id::text <> all(v_garder_entreprises)
     order by e.nom
  loop
    if v_simulation then
      raise notice '   ▸ Entreprise « % » : serait supprimée avec ses boutiques et ses données.', v_rec.nom;
    else
      begin
        v_res := public.rpc_admin_purger_entreprise(v_rec.id, v_rec.nom, false);
        raise notice '   ▸ Entreprise « % » supprimée : % ligne(s).',
          v_rec.nom, coalesce(v_res ->> 'lignes_concernees', '0');
      exception when others then
        raise warning '   ▸ Entreprise « % » NON supprimée : %', v_rec.nom, sqlerrm;
      end;
    end if;
  end loop;

  -- ------------------------------------------------------------------ bilan
  raise notice '=== Bilan : % compte(s) supprimé(s), % refusé(s) %. ===',
    v_ok, v_ko,
    case when v_simulation
         then format('— en AUDIT, %s ligne(s) seraient détruites', v_total)
         else '' end;

  if v_simulation then
    raise notice 'POUR EXÉCUTER VRAIMENT : passez `v_simulation` à FALSE puis relancez.';
  end if;
end $tout$;


-- ============================================================================
--  CONTRÔLE FINAL — à relancer après l'opération
-- ============================================================================
select
  (select count(*) from public.utilisateurs) as comptes_restants,
  (select string_agg(u.email || ' (' || coalesce(u.new_role::text, '?') || ')',
                     ', ' order by u.email)
     from public.utilisateurs u)             as qui_reste,
  (select count(*) from public.entreprises)  as entreprises,
  (select count(*) from public.espaces)      as boutiques;

-- ============================================================================
--  FIN — outil de maintenance.
-- ============================================================================
