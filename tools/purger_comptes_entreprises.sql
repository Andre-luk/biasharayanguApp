-- ============================================================================
--  OUTIL DE MAINTENANCE — PURGE DES COMPTES ENTREPRISES (et de leurs données)
--  tools/purger_comptes_entreprises.sql
-- ============================================================================
--
--  ⚠️⚠️  DESTRUCTIF — À LIRE EN ENTIER AVANT D'EXÉCUTER  ⚠️⚠️
--
--  Objectif : ne garder que les COMPTES PLATEFORME (Super Admin, gestionnaire
--  des comptes, finance, support, agents terrain) et supprimer les comptes
--  d'entreprises d'essai avec TOUTES leurs données (boutiques, articles,
--  ventes, stock, clients, dettes, dépenses, caisse, abonnements, audits…).
--
--  CE SCRIPT NE PASSE PAS PAR L'APPLICATION : il s'exécute dans
--  Supabase → SQL Editor → coller → Run.
--
--  MODE D'EMPLOI (3 étapes, dans l'ordre)
--  --------------------------------------
--    1. lancez le script tel quel : il affiche la LISTE des entreprises
--       qui seraient supprimées et le volume de données concerné. RIEN n'est
--       supprimé (v_executer = false) ;
--    2. relisez la liste. Si elle contient une entreprise à CONSERVER,
--       ajoutez son `nom` ou son `id` au tableau `v_exclure` ;
--    3. passez `v_executer` à TRUE et relancez.
--
--  SÉCURITÉ : le script refuse de démarrer s'il ne trouve aucun compte
--  SUPER_ADMIN (la purge est réservée au Super Admin au sens du module 21).
-- ============================================================================

do $purge$
declare
  -- ▶▶▶ DOUBLE COMMUTATEUR ◀◀◀
  --   false = AUDIT (rien n'est supprimé)   |   true = SUPPRESSION RÉELLE
  v_executer boolean := false;

  -- Entreprises à CONSERVER même en mode réel : nom exact ou identifiant.
  -- Exemple : v_exclure text[] := array['Boutique démonstration',
  --                                    '11111111-2222-3333-4444-555555555555'];
  v_exclure text[] := array[]::text[];

  v_admin    uuid;
  v_rec      record;
  v_n        integer;
  v_total    bigint := 0;
  v_nb_ent   integer := 0;
  v_simu     jsonb;
begin
  -- ------------------------------------------------------------------ garde
  select u.id into v_admin
    from public.utilisateurs u
   where u.new_role::text = 'SUPER_ADMIN'
   order by u.created_at
   limit 1;

  if v_admin is null then
    raise exception 'Aucun compte SUPER_ADMIN trouvé : purge annulée.';
  end if;

  -- ⚠️ INDISPENSABLE : le SQL Editor n'a AUCUNE session utilisateur. Sans ces
  -- deux lignes, `auth.uid()` vaut NULL, donc `mon_role()` renvoie NULL et les
  -- RPC de purge répondent « DROIT_REFUSE » : la purge ne s'exécute pas, alors
  -- que le script semble avoir tourné. On se déclare Super Admin le temps de
  -- ce script uniquement (`is_local => true` : rien n'est conservé après).
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', v_admin::text,
                       'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', v_admin::text, true);

  raise notice '=== PURGE DES COMPTES ENTREPRISES — mode % ===',
    case when v_executer then 'SUPPRESSION RÉELLE' else 'AUDIT (aucune suppression)' end;

  -- -------------------------------------------------- entreprises candidates
  raise notice 'Entreprises qui seront traitées :';

  for v_rec in
    select e.id, e.nom,
           (select count(*) from public.espaces s where s.entreprise_id = e.id) as espaces,
           (select count(*) from public.utilisateurs u where u.entreprise_id = e.id) as comptes
      from public.entreprises e
     where not (e.nom = any(v_exclure))
       and e.id::text <> all(v_exclure)
     order by e.nom
  loop
    v_nb_ent := v_nb_ent + 1;
    raise notice '   [%] % — % boutique(s), % compte(s)',
      v_nb_ent, v_rec.nom, v_rec.espaces, v_rec.comptes;

    if v_executer then
      -- La confirmation exigée par la RPC est le nom exact de l'entreprise.
      v_simu := public.rpc_admin_purger_entreprise(
                  v_rec.id, v_rec.nom, false);
      v_total := v_total + coalesce((v_simu ->> 'lignes_concernees')::bigint, 0);

      raise notice '        → supprimée : % ligne(s).',
        coalesce(v_simu ->> 'lignes_concernees', '0');

      if v_simu -> 'erreurs' <> '{}'::jsonb then
        raise notice '        → ⚠ erreurs signalées : %', v_simu -> 'erreurs';
      end if;
    else
      -- AUDIT : la RPC de purge est appelée en SIMULATION, elle compte sans
      -- rien détruire (c'est le même code que celui qui supprimera réellement).
      v_simu := public.rpc_admin_purger_entreprise(
                  v_rec.id, v_rec.nom, true);
      v_total := v_total + coalesce((v_simu ->> 'lignes_concernees')::bigint, 0);

      raise notice '        → % ligne(s) seraient supprimées.',
        coalesce(v_simu ->> 'lignes_concernees', '0');
    end if;
  end loop;

  if v_nb_ent = 0 then
    raise notice 'Aucune entreprise à traiter : rien à faire.';
  end if;

  -- ------------------------------------------------- comptes plateforme (état)
  raise notice 'Comptes de la plateforme CONSERVÉS :';
  for v_rec in
    select u.email, u.new_role::text as role
      from public.utilisateurs u
     where u.entreprise_id is null
     order by u.new_role::text, u.email
  loop
    raise notice '   • % — %', coalesce(v_rec.email, '(sans e-mail)'), v_rec.role;
  end loop;

  raise notice '=== Bilan : % entreprise(s) traitée(s), % ligne(s) %. ===',
    v_nb_ent, v_total,
    case when v_executer then 'SUPPRIMÉES' else 'concernées (aucune suppression)' end;

  if not v_executer then
    raise notice 'POUR SUPPRIMER RÉELLEMENT : passez `v_executer` à TRUE puis relancez ce script.';
  end if;
end $purge$;


-- ============================================================================
--  CONTRÔLE APRÈS PURGE — à relancer pour constater l'état final
-- ============================================================================
select
  (select count(*) from public.entreprises)  as entreprises_restantes,
  (select count(*) from public.espaces)      as boutiques_restantes,
  (select count(*) from public.utilisateurs
    where entreprise_id is null)             as comptes_plateforme,
  (select count(*) from public.utilisateurs
    where entreprise_id is not null)         as comptes_entreprises;

-- ============================================================================
--  FIN — outil de maintenance.
-- ============================================================================
