-- ============================================================================
--  OUTIL DE MAINTENANCE — PURGE DES COMPTES ORPHELINS (sans entreprise)
--  tools/purger_comptes_orphelins.sql
-- ============================================================================
--
--  POURQUOI CE SECOND SCRIPT
--  -------------------------
--  `tools/purger_comptes_entreprises.sql` ne parcourt que les ENTREPRISES.
--  Un compte dont `entreprise_id` est NULL (compte « orphelin » : l'entreprise
--  a déjà été supprimée, ou le rattachement n'a jamais été fait) n'est donc
--  JAMAIS atteint par ce script — c'est la raison pour laquelle les compteurs
--  ne bougent plus.
--
--  Or ton installation compte 27 comptes orphelins, dont certains sont des
--  comptes d'essai. C'est CE script qui les traite.
--
--  MODE D'EMPLOI
--  -------------
--   1. lancez-le tel quel : il AFFICHE chaque compte orphelin avec son rôle
--      et le VOLUME de données qui lui est rattaché. Rien n'est supprimé
--      (`v_simulation := true`, `v_a_purger` vide) ;
--   2. recopiez dans `v_a_purger` UNIQUEMENT les adresses que vous voulez
--      vraiment supprimer ;
--   3. passez `v_simulation := false` et relancez.
--
--  ⚠️ GARDE-FOUS
--    • les comptes de la plateforme (SUPER_ADMIN, GESTIONNAIRE_COMPTES,
--      FINANCE_LAPERLE, SUPPORT, AGENT_TERRAIN) sont PROTÉGÉS : même inscrits
--      dans `v_a_purger`, ils sont refusés avec un message explicite ;
--    • un compte qui porte des données est supprimé LUI AUSSI, mais le volume
--      est affiché AVANT (ventes, paiements, dettes, audits) ;
--    • par défaut, RIEN n'est supprimé : aucune adresse n'est pré-remplie.
-- ============================================================================

do $orphelins$
declare
  -- ▶▶▶ DOUBLE COMMUTATEUR ◀◀◀
  v_simulation boolean := true;   -- false = SUPPRESSION RÉELLE

  -- Adresses à supprimer. VOLONTAIREMENT VIDE : à vous de les nommer.
  -- Exemple :
  --   v_a_purger text[] := array['diag.patron.1789744067@biasharayangu.cd',
  --                              'test17.hotel.1789910548@biasharayangu.cd'];
  v_a_purger text[] := array[]::text[];

  v_admin  uuid;
  v_rec    record;
  v_dep    jsonb;
  v_res    jsonb;
  v_ok     integer := 0;
  v_ko     integer := 0;
begin
  -- ------------------------------------------------------- session Super Admin
  -- Le SQL Editor n'a aucune session : sans ces lignes, `auth.uid()` est NULL
  -- et les RPC répondent « DROIT_REFUSE ».
  select u.id into v_admin
    from public.utilisateurs u
   where u.new_role::text = 'SUPER_ADMIN'
   order by u.created_at
   limit 1;

  if v_admin is null then
    raise exception 'Aucun SUPER_ADMIN trouvé : script annulé.';
  end if;

  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', v_admin::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', v_admin::text, true);

  raise notice '=== COMPTES ORPHELINS (sans entreprise) — mode % ===',
    case when v_simulation then 'AUDIT (aucune suppression)'
         else 'SUPPRESSION RÉELLE' end;

  -- ------------------------------------------------------------- inventaire
  for v_rec in
    select u.id, u.email,
           coalesce(u.new_role::text, '(aucun rôle)') as role,
           u.valide,
           u.created_at::date as cree_le
      from public.utilisateurs u
     where u.entreprise_id is null
     order by u.new_role::text nulls last, u.email
  loop
    v_dep := public.rpc_admin_utilisateur_dependances(v_rec.id);

    raise notice '   • % | % | valide=% | créé le % | % donnée(s), % boutique(s)',
      rpad(coalesce(v_rec.email, '(sans e-mail)'), 42),
      rpad(v_rec.role, 20),
      v_rec.valide,
      v_rec.cree_le,
      coalesce(v_dep ->> 'total_donnees', '0'),
      coalesce(v_dep ->> 'nb_espaces', '0');

    if coalesce(v_rec.email, '') = any(v_a_purger) then
      if v_simulation then
        raise notice '        ↳ SERAIT SUPPRIMÉ (à confirmer : v_simulation := false)';
      else
        begin
          v_res := public.rpc_admin_purger_utilisateur(
                     v_rec.id, v_rec.email, false);
          v_ok := v_ok + 1;
          raise notice '        ↳ SUPPRIMÉ : % ligne(s), compte de connexion %.',
            coalesce(v_res ->> 'lignes_concernees', '0'),
            case when v_res ->> 'compte_auth_supprime' = 'true'
                 then 'supprimé' else 'NON supprimé' end;
        exception when others then
          v_ko := v_ko + 1;
          raise warning '        ↳ REFUSÉ pour % : %', v_rec.email, sqlerrm;
        end;
      end if;
    end if;
  end loop;

  -- ------------------------------------------------------------------ bilan
  if array_length(v_a_purger, 1) is null then
    raise notice '=== AUDIT SEUL : aucune adresse dans `v_a_purger`, donc AUCUNE suppression. ===';
    raise notice 'Recopiez les adresses à supprimer dans `v_a_purger`, puis relancez.';
  else
    raise notice '=== Bilan : % suppression(s) réussie(s), % refusée(s). ===', v_ok, v_ko;
  end if;
end $orphelins$;


-- ============================================================================
--  CONTRÔLE FINAL — à relancer après la purge
-- ============================================================================
select
  (select count(*) from public.utilisateurs where entreprise_id is null)
    as comptes_sans_entreprise,
  (select count(*) from public.utilisateurs where entreprise_id is not null)
    as comptes_avec_entreprise,
  (select count(*) from public.utilisateurs
    where new_role::text in ('SUPER_ADMIN', 'GESTIONNAIRE_COMPTES',
                             'FINANCE_LAPERLE', 'SUPPORT', 'AGENT_TERRAIN'))
    as comptes_plateforme_officiels,
  (select count(*) from public.entreprises) as entreprises,
  (select count(*) from public.espaces)     as boutiques;

-- ============================================================================
--  FIN — outil de maintenance.
-- ============================================================================
