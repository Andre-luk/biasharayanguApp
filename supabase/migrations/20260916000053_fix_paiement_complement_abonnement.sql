-- ============================================================================
--  biashara_yangu — CORRECTIF 53 : LE COMPLÉMENT DE PAIEMENT EFFAÇAIT L'ACOMPTE
--  Migration 20260916000053_fix_paiement_complement_abonnement.sql
-- ============================================================================
--
--  À exécuter APRÈS la migration 43 (module 21) et la 51. IDEMPOTENTE :
--  peut être relancée sans effet de bord.
--
--  ⛔ AUCUNE COMPILATION, AUCUNE PUBLICATION : ce fichier ne touche QUE la base.
--
--  ---------------------------------------------------------------------------
--  LE BUG (constaté par l'utilisateur le 08/10/2026)
--  ---------------------------------------------------------------------------
--  Un abonnement de 30 000 CDF, dont 25 000 déjà réglés (solde 5 000).
--  L'administrateur encaisse le COMPLÉMENT de 5 000 pour solder le compte…
--  et la fiche affiche l'INVERSE :
--
--        montant dû      30 000 CDF
--        déjà payé        5 000 CDF     ← l'acompte de 25 000 a DISPARU
--        solde restant   25 000 CDF     ← et l'abonnement n'est PAS conclu
--
--  Au lieu de :  déjà payé 30 000 / solde 0 → abonnement ACTIF (30 jours).
--
--  ---------------------------------------------------------------------------
--  LA CAUSE
--  ---------------------------------------------------------------------------
--  Dans `public.rpc_abonnement_enregistrer_paiement` (version live : migration
--  23, complétée par le correctif 43), la réouverture de cycle est déclenchée
--  par :
--
--        if v_solde <= 0 or v_statut_avant in ('EXPIRE', 'EN_ATTENTE_COMPLEMENT')
--        then
--            ...
--            v_paye  := 0;          -- ⛔ EFFACE L'ACOMPTE
--            v_solde := v_total;
--        end if;
--
--  Or `EN_ATTENTE_COMPLEMENT` ne désigne PAS un nouveau cycle : c'est
--  précisément l'état d'un cycle EN COURS, partiellement réglé, qui attend son
--  complément (c'est le statut posé par ce même moteur après un paiement
--  partiel sur un compte échu). Traiter cet état comme un nouveau cycle remet
--  `montant_deja_paye` à zéro : le complément encaissé devient alors le SEUL
--  montant payé, et le solde repart à 30 000 − 5 000 = 25 000.
--
--  Déroulé exact du scénario :
--    1) compte à 30 000 / statut EXPIRE → paiement de 25 000
--         → nouveau cycle (paye 0 → 25 000, solde 5 000)
--         → statut passé à EN_ATTENTE_COMPLEMENT
--    2) complément de 5 000 → statut EN_ATTENTE_COMPLEMENT
--         → ⛔ RESET : paye := 0 puis + 5 000, solde := 30 000 − 5 000 = 25 000
--         → aucun cycle n'est soldé : l'abonnement n'est jamais conclu.
--
--  ---------------------------------------------------------------------------
--  LE CORRECTIF
--  ---------------------------------------------------------------------------
--  Seul `EXPIRE` ouvre un nouveau cycle de facturation (un abonnement échu
--  démarre une nouvelle période). « En attente de complément » reste le MÊME
--  cycle : les versements s'ADDITIONNENT (« v_paye + p_montant »), et le
--  compte passe ACTIF dès que le solde atteint zéro.
--
--  La correction est appliquée par RÉÉCRITURE CIBLÉE de la fonction
--  (`pg_get_functiondef` + `regexp_replace`), la même technique que le
--  correctif 43 : on ne redéfinit pas la fonction entière, ce qui préserverait
--  mal les correctifs déjà appliqués par-dessus (montant négocié, etc.).
--
--  ⚠️ Aucune fonction n'est appelée par l'application avec un nom ou une
--     signature différente : rien à changer côté Flutter, rien à republier.
--
--  OÙ L'EXÉCUTER
--    Supabase Dashboard → SQL Editor → New query → coller → Run
-- ============================================================================


select set_config('search_path', 'public, extensions', true);


-- ============================================================================
--  1. CONTRÔLES PRÉALABLES
-- ============================================================================

do $$
declare
  v_n integer;
begin
  select count(*) into v_n
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname = 'rpc_abonnement_enregistrer_paiement';

  if v_n = 0 then
    raise exception
      'Moteur d''abonnement introuvable : exécutez d''abord les migrations du module 3 (20260916000003) puis la 23.';
  end if;

  if v_n > 1 then
    raise warning
      'Plusieurs surcharges de rpc_abonnement_enregistrer_paiement existent : le correctif sera appliqué à toutes.';
  end if;

  -- La fonction doit renvoyer la ligne d'entreprise (les appelants font
  -- `select * into v_e from public.rpc_abonnement_enregistrer_paiement(...)`).
  if not exists (
    select 1 from public.entreprises limit 1
  ) then
    raise warning 'La table entreprises est vide : aucune donnée à réparer.';
  end if;
end $$;


-- ============================================================================
--  2. CORRECTIF — LE COMPLÉMENT S'AJOUTE AU LIEU D'EFFACER L'ACOMPTE
-- ============================================================================
--  On remplace la seule condition de réouverture de cycle :
--      … or v_statut_avant in ('EXPIRE', 'EN_ATTENTE_COMPLEMENT') then
--   par
--      … or v_statut_avant = 'EXPIRE' then
--
--  ⚠️ L'apostrophe est proscrite dans le commentaire inséré : le texte est
--     injecté dans du code PL/pgSQL (piège déjà rencontré au correctif 43).

do $patch_complement$
declare
  v_regclass oid;
  v_def      text;
  v_new      text;
  v_motifs   text[] := array[
    -- Forme exacte de la migration 23 (parenthèses échappées : ce sont des
    -- métacaractères en expression régulière).
    $m1$v_statut_avant in \('EXPIRE', 'EN_ATTENTE_COMPLEMENT'\)$m1$,
    -- Variante tolérante aux espaces internes, au cas où.
    $m2$v_statut_avant\s+in\s*\(\s*'EXPIRE'\s*,\s*'EN_ATTENTE_COMPLEMENT'\s*\)$m2$
  ];
  -- ⛔ PIÈGE À NE PAS OUBLIER : ce texte est inséré AU MILIEU d'une ligne de
  --    code, juste avant le « then ». Un commentaire « -- » écrit à la suite
  --    sur la MÊME ligne avaleraiT ce « then » (le commentaire va jusqu'à la
  --    fin de la ligne) et casserait la fonction. On commence donc par un
  --    saut de ligne : le commentaire occupe sa propre ligne et l'expression
  --    se poursuit à la ligne suivante — ce qui reste du PL/pgSQL valide.
  --    Pas d'apostrophe dans ce commentaire : il entre dans du code PL/pgSQL.
  v_repl     text := $r$
      -- correctif 53 : un complement de paiement reste le MEME cycle
      v_statut_avant = 'EXPIRE'$r$;
  v_i        integer;
  v_ok       boolean := false;
  v_apres    text;
begin
  for v_regclass in
    select p.oid
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname = 'rpc_abonnement_enregistrer_paiement'
  loop
    v_ok  := false;
    v_def := pg_get_functiondef(v_regclass);

    -- Déjà corrigée ? (relance de la migration : on ne touche à rien)
    if position('correctif 53' in v_def) > 0 then
      raise notice 'Moteur d''abonnement : correctif 53 DEJA applique.';
      continue;
    end if;

    -- La fonction a-t-elle bien la structure attendue ?
    if position('EN_ATTENTE_COMPLEMENT' in v_def) = 0 then
      raise warning
        'Moteur d''abonnement : aucune reference a EN_ATTENTE_COMPLEMENT — variante inconnue, correctif 53 NON applique. Transmettez le contenu de la fonction (requete 5.a) pour un correctif cible.';
      continue;
    end if;

    v_new := v_def;
    for v_i in 1..array_length(v_motifs, 1) loop
      v_new := v_def;
      v_new := regexp_replace(v_new, v_motifs[v_i], v_repl, 'gn');
      if v_new <> v_def then
        execute v_new;
        v_ok := true;
        exit;
      end if;
    end loop;

    if v_ok then
      v_apres := pg_get_functiondef(v_regclass);
      if position('correctif 53' in v_apres) > 0 then
        raise notice 'Moteur d''abonnement : correctif 53 APPLIQUE (le complement s ajoute a l acompte et solde l abonnement).';
      else
        raise warning 'Moteur d''abonnement : reecriture effectuee mais le marqueur est absent — verifiez la requete 5.b.';
      end if;
    else
      raise warning
        'Moteur d''abonnement : variante inconnue, correctif 53 NON applique. Lancez la requete 5.a et transmettez le resultat.';
    end if;
  end loop;
end $patch_complement$;


-- ============================================================================
--  3. RÉPARATION DES DOSSIERS DÉJÀ FAUSSÉS PAR LE BUG
-- ============================================================================
--  Le correctif ci-dessus empêche le bug de se reproduire, mais il ne répare
--  PAS les comptes déjà touchés : leur `montant_deja_paye` a été écrasé et
--  l'historique porte la trace de l'anomalie.
--
--  SIGNATURE DU BUG — infaillible : dans `paiements_abonnements_laperle`, la
--  colonne `total_apres` est le cumulé APRÈS le versement. Dans un cycle
--  correct, ce cumulé ne peut que CROÎTRE. Après un reset, il CHUTE.
--  On détecte donc les versements dont `total_apres` est INFÉRIEUR au cumulé
--  du versement précédent.
--
--  ⚠️ La réparation est présentée en RUN SÉPARÉ (en fin de fichier) pour que
--     vous VOYEZ d'abord les dossiers concernés : aucune écriture n'est faite
--     automatiquement ici.

do $$
declare
  v_n integer := 0;
begin
  select count(*) into v_n
    from (
      select lag(total_apres) over (
               partition by entreprise_id order by created_at
             ) as precedent,
             total_apres
        from public.paiements_abonnements_laperle
    ) t
   where t.precedent is not null
     and t.total_apres < t.precedent;

  if v_n = 0 then
    raise notice 'Reparation : aucun versement incoherent detecte — rien a reparer.';
  else
    raise notice 'Reparation : % versement(s) incoherent(s) detecte(s) (cumule en baisse). Lancez la requete 5.c pour voir les dossiers concernes, puis la 6 pour reparer.', v_n;
  end if;
exception when undefined_table then
  raise notice 'Reparation : table paiements_abonnements_laperle absente — etape ignoree.';
end $$;


-- ============================================================================
--  4. LE MOTEUR RESTE ACCESSIBLE — RAPPEL DES DROITS
-- ============================================================================
--  Le correctif réécrit la fonction : on s'assure que les droits d'exécution
--  sont toujours en place (sinon l'écran de paiement échouerait en
--  « permission denied for function »).

do $$
begin
  execute 'grant execute on function public.rpc_abonnement_enregistrer_paiement(uuid, numeric, text, text, text) to authenticated';
  raise notice 'Droits d''execution confirmes pour authenticated.';
exception when others then
  raise warning 'Droits d''execution a verifier manuellement : %', sqlerrm;
end $$;


-- ============================================================================
--  5. VÉRIFICATIONS — RUN SÉPARÉ (aucune écriture)
-- ============================================================================
--
--  5.a — VOIR LE CODE RÉELLEMENT INSTALLÉ (si le correctif n'a pas pris) :
--
--      select pg_get_functiondef(p.oid)
--        from pg_proc p
--        join pg_namespace n on n.oid = p.pronamespace
--       where n.nspname = 'public'
--         and p.proname = 'rpc_abonnement_enregistrer_paiement';
--
--      Vous devez y trouver (le correctif est signalé, puis la ligne change) :
--
--        if v_solde <= 0 or
--            -- correctif 53 : un complement de paiement reste le MEME cycle
--            v_statut_avant = 'EXPIRE' then
--
--      et NE PLUS y trouver :
--        or v_statut_avant in ('EXPIRE', 'EN_ATTENTE_COMPLEMENT')
--
--  5.b — CONFIRMATION DU CORRECTIF :
--
--      select position('correctif 53' in
--               pg_get_functiondef(p.oid)) > 0 as correctif_53_applique
--        from pg_proc p
--        join pg_namespace n on n.oid = p.pronamespace
--       where n.nspname = 'public'
--         and p.proname = 'rpc_abonnement_enregistrer_paiement';
--      Attendu : true
--
--  5.c — DOSSIERS FAUSSÉS PAR LE BUG (à examiner avant de réparer) :
--
--      with versements as (
--        select entreprise_id, created_at, montant, total_apres,
--               lag(total_apres) over (
--                 partition by entreprise_id order by created_at
--               ) as precedent
--          from public.paiements_abonnements_laperle
--      )
--      select e.nom,
--             v.created_at                      as versement_du,
--             v.montant                         as verse,
--             v.precedent                       as cumule_avant,
--             v.total_apres                     as cumule_enregistre,
--             (v.precedent + v.montant)         as cumule_corrige,
--             e.montant_total_du,
--             e.montant_deja_paye,
--             e.solde_restant,
--             e.statut::text,
--             e.activation_etape
--        from versements v
--        join public.entreprises e on e.id = v.entreprise_id
--       where v.precedent is not null
--         and v.total_apres < v.precedent
--       order by v.created_at desc;
--
--      Lecture : `cumule_corrige` est le montant que le compte aurait dû
--      afficher. Si `cumule_corrige` atteint `montant_total_du`, l'abonnement
--      aurait dû être ACTIF.
--
-- ============================================================================
--  6. RÉPARATION — RUN SÉPARÉ, À EXÉCUTER APRÈS AVOIR LU LA REQUÊTE 5.c
-- ============================================================================
--  Décommentez (retirez les « -- ») après avoir constaté la liste 5.c.
--
--  ⚠️ La mise à jour n'ABAISSE JAMAIS un montant déjà enregistré (GREATEST) et
--     ne dépasse jamais le montant total dû : elle ne peut donc pas créer de
--     solde négatif ni effacer un paiement légitime.
--
--  -- 6.a Rétablir le cumulé correct sur chaque dossier touché -------------
--  with versements as (
--    select entreprise_id, created_at, montant, total_apres,
--           lag(total_apres) over (
--             partition by entreprise_id order by created_at
--           ) as precedent
--      from public.paiements_abonnements_laperle
--  ),
--  corrige as (
--    select entreprise_id,
--           max(precedent + montant) as cumule_corrige
--      from versements
--     where precedent is not null
--       and total_apres < precedent
--     group by entreprise_id
--  )
--  update public.entreprises e
--     set montant_deja_paye = least(c.cumule_corrige,
--                                   coalesce(e.montant_total_du, c.cumule_corrige)),
--         updated_at        = now()
--    from corrige c
--   where e.id = c.entreprise_id
--     and c.cumule_corrige
--         > least(c.cumule_corrige,
--                 coalesce(e.montant_total_du, c.cumule_corrige))
--     and c.cumule_corrige > coalesce(e.montant_deja_paye, 0);
--  -- `solde_restant` est une colonne GÉNÉRÉE (total − payé) : elle suit toute
--  -- seule, aucune écriture nécessaire.
--
--  -- 6.b Conclure les abonnements désormais intégralement réglés -----------
--  --     (à exécuter UNIQUEMENT après 6.a, et après avoir constaté dans 6.c
--  --      que la liste correspond bien à des dossiers soldés)
--  update public.entreprises e
--     set statut           = 'ACTIF'::public.statut_abonnement_enum,
--         activation_etape = case
--                              when e.activation_etape in ('verifie','restreint')
--                                then 'actif'
--                              else e.activation_etape
--                            end,
--         date_activation  = coalesce(e.date_activation, now()),
--         date_expiration  = greatest(
--                              coalesce(e.date_expiration, now()),
--                              now()
--                            ) + make_interval(
--                              days => coalesce(
--                                (select nullif(g.duree_abonnement_jours, 0)
--                                   from public.groupes_tarifaires g
--                                  where g.id = e.groupe_tarifaire_id), 30)),
--         updated_at       = now()
--   where coalesce(e.solde_restant, 0) <= 0
--     and coalesce(e.montant_total_du, 0) > 0
--     and e.statut::text <> 'ACTIF'
--     and e.statut::text <> 'SUSPENDU';   -- une suspension reste une décision humaine
--
--  -- 6.c Contrôle final : plus aucun abonnement soldé non actif -------------
--  select e.nom, e.statut::text, e.activation_etape,
--         e.montant_total_du, e.montant_deja_paye, e.solde_restant,
--         e.date_expiration
--    from public.entreprises e
--   where coalesce(e.montant_total_du, 0) > 0
--     and coalesce(e.montant_deja_paye, 0) >= coalesce(e.montant_total_du, 0)
--     and e.statut::text <> 'ACTIF'
--   order by e.nom;


-- ============================================================================
--  7. TEST DE NON-RÉGRESSION — à jouer sur un dossier de recette (RUN SÉPARÉ)
-- ============================================================================
--  Après le correctif, rejouez le scénario de l'utilisateur sur un compte de
--  test (30 000 dû) :
--    1) enregistrer 25 000  → attendu : déjà payé 25 000, solde 5 000,
--                             statut EN_ATTENTE_COMPLEMENT ;
--    2) enregistrer  5 000  → attendu : déjà payé 30 000, solde 0,
--                             statut ACTIF, expiration à +30 jours.
--
--  Contrôle :
--      select nom, montant_total_du, montant_deja_paye, solde_restant,
--             statut::text, activation_etape, date_expiration
--        from public.entreprises
--       where id = '<identifiant du compte de test>';
-- ============================================================================
--  FIN — correctif 53.
-- ============================================================================
