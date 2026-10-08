-- ============================================================================
--  biashara_yangu — CORRECTIF 54 : ABONNEMENT « biasharagroup@gmail.com »
--  Migration 20260916000054_abonnement_biasharagroup_correction.sql
-- ============================================================================
--
--  LE DOSSIER
--  ----------
--  Le client a TOUT payé, mais son compteur est resté sur le dernier versement
--  (5 000 CDF) : le bug du complément de paiement (voir le correctif 53) avait
--  remis `montant_deja_paye` à zéro juste avant de l'encaisser. Résultat :
--      deja paye    5 000 CDF     ← au lieu du montant total
--      solde restant 25 000 CDF
--      statut       EN_ATTENTE_COMPLEMENT   ← abonnement jamais conclu
--
--  CE QUE FAIT CETTE MIGRATION
--  ---------------------------
--    1. retrouve l'entreprise du compte ;
--    2. relève le montant dû porté par la fiche et l'historique des versements ;
--    3. remet `montant_deja_paye` au montant DÛ (`solde_restant` suit tout seul :
--       c'est une colonne générée) ;
--    4. CONCLUT l'abonnement : statut ACTIF, étape « actif », période de la
--       grille tarifaire (30 jours par défaut).
--
--  ⚠️ CE QUE L'HISTORIQUE A RÉVÉLÉ (07/10/2026, 21:17 → 21:22)
--  -----------------------------------------------------------
--  Le journal des versements de ce dossier contient 7 lignes pour 115 000 CDF,
--  alors que l'abonnement est de 30 000 CDF : l'essai du bug a été rejoué
--  quatre fois, et chaque tentative a laissé sa trace.
--      • trois lignes de 5 000 portent la marque du bug (cumulé en BAISSE :
--        25 000 puis 5 000) ;
--      • les quatre séquences « 25 000 puis 5 000 » représentent en réalité le
--        MÊME abonnement de 30 000 CDF, payé quatre fois en essai.
--
--  Conclusion : la SOMME des versements ne peut pas servir de référence — elle
--  donnerait 115 000 CDF pour un abonnement de 30 000. C'est pourquoi cette
--  migration retient le MONTANT DÛ de la fiche, borne le paiement entre ce qui
--  est déjà enregistré et ce qui est dû, et vous ALERTE si les versements
--  dépassent nettement le montant dû (versements d'essai à nettoyer : ils
--  gonflent sinon les rapports de chiffre d'affaires).
--
--  GARDE-FOUS
--  ----------
--    • le montant n'est JAMAIS abaissé, ni poussé au-delà du montant dû ;
--    • si la fiche ne porte AUCUN montant dû, la migration ne devine pas : elle
--      s'arrête et vous indique la commande pour le renseigner
--      (ou renseignez `v_montant_du_force` en tête de fichier) ;
--    • un compte SUSPENDU n'est PAS réactivé automatiquement : la révocation
--      reste une décision humaine ;
--    • si le compte est introuvable, la migration ne casse rien : elle prévient.
--  IDEMPOTENTE : la relancer ne cumule rien.
--
--  ⚠️ À EXÉCUTER APRÈS le correctif 53
--     (20260916000053_fix_paiement_complement_abonnement.sql), sinon le bug
--     se reproduira au prochain paiement.
--
--  OÙ : Supabase → SQL Editor → coller → Run
-- ============================================================================


select set_config('search_path', 'public, extensions', true);


do $$
declare
  -- ─────────────────────────────  RÉGLAGES  ─────────────────────────────
  v_email    text := 'biasharagroup@gmail.com';

  -- Montant dû de l'abonnement.
  --   NULL  = on utilise le montant porté par la fiche (cas normal).
  --   valeur = on l'impose, ET on l'écrit sur la fiche — à n'utiliser que si
  --            la fiche n'indique aucun montant dû.
  -- ⚠️ Ne JAMAIS laisser la migration déduire le montant dû de la somme des
  --    versements : l'historique d'essai de ce dossier totalise 115 000 CDF
  --    pour un abonnement de 30 000, ce qui produirait une fiche absurde.
  v_montant_du_force numeric := null;
  -- ───────────────────────────────────────────────────────────────────────

  v_user       public.utilisateurs;
  v_eid        uuid;
  v_e          public.entreprises;
  v_verse      numeric := 0;   -- total des versements enregistrés
  v_paye       numeric := 0;   -- montant enregistré avant correction
  v_montant_du numeric := 0;   -- montant dû retenu
  v_cible      numeric := 0;   -- montant à rétablir
  v_duree      integer := 30;
begin
  -- ------------------------------------------------------------------ 1) compte
  select * into v_user
    from public.utilisateurs u
   where lower(btrim(u.email)) = lower(btrim(v_email))
   limit 1;

  if v_user.id is null then
    raise warning 'Correctif 54 : aucun compte « % » — migration sans effet.', v_email;
    return;
  end if;

  -- L'entreprise du compte (ou celle de son patron : mêmes règles que
  -- public.mon_entreprise_id, qui couvre les comptes rattachés).
  select coalesce(u.entreprise_id, p.entreprise_id)
    into v_eid
    from public.utilisateurs u
    left join public.utilisateurs p on p.id = u.parent_id
   where u.id = v_user.id;

  if v_eid is null then
    raise warning 'Correctif 54 : le compte « % » n''est rattaché à aucune entreprise.', v_email;
    return;
  end if;

  select * into v_e from public.entreprises where id = v_eid;
  if v_e.id is null then
    raise warning 'Correctif 54 : entreprise introuvable pour « % ».', v_email;
    return;
  end if;

  v_paye := coalesce(v_e.montant_deja_paye, 0);

  -- ------------------------------------------------------- 2) montant versé
  -- Somme des versements enregistrés. C'est un INDICE, pas une référence : le
  -- dossier d'essai ci-dessous totalise 115 000 CDF pour 30 000 dus, chaque
  -- essai ayant laissé sa trace. Cette somme sert uniquement d'alerte.
  select coalesce(sum(h.montant), 0)
    into v_verse
    from public.paiements_abonnements_laperle h
   where h.entreprise_id = v_eid;

  -- --------------------------------------------------------- 3) montant dû
  v_montant_du := coalesce(
    nullif(v_montant_du_force, 0),      -- valeur imposée en tête, si fournie
    nullif(v_e.montant_total_du, 0),    -- sinon celle de la fiche
    0
  );

  raise notice 'Correctif 54 — dossier « % »', v_e.nom;
  raise notice '   montant du (fiche)  : %', coalesce(v_e.montant_total_du, 0);
  raise notice '   deja paye (fiche)   : %', v_paye;
  raise notice '   solde restant       : %', coalesce(v_e.solde_restant, 0);
  raise notice '   statut avant        : %', v_e.statut::text;
  raise notice '   versements enregistres : % (total %)',
               (select count(*) from public.paiements_abonnements_laperle h
                 where h.entreprise_id = v_eid), v_verse;

  -- Alerte : beaucoup plus de versements que le montant dû = essais empilés.
  if v_montant_du > 0 and v_verse > v_montant_du * 1.5 then
    raise warning
      'Correctif 54 : % verses pour % dus — l''historique contient des versements d''essai. Le montant retenu reste celui de la fiche ; pensez a nettoyer ces lignes si elles faussent vos rapports.',
      v_verse, v_montant_du;
  end if;

  -- Sans montant dû, on ne devine PAS : mieux vaut ne rien conclure que
  -- fabriquer un abonnement incohérent.
  if v_montant_du <= 0 then
    raise warning
      'Correctif 54 : montant du inconnu sur la fiche — migration sans effet sur le montant. Renseignez-le puis relancez : select public.rpc_activation_definir_montant_total(''%'', <montant>, ''Correctif 54'');',
      v_eid;
    return;
  end if;

  -- Si un montant a été imposé, on l'écrit sur la fiche.
  if nullif(v_montant_du_force, 0) is not null
     and coalesce(v_e.montant_total_du, 0) <> v_montant_du then
    update public.entreprises
       set montant_total_du = v_montant_du,
           updated_at       = now()
     where id = v_eid
    returning * into v_e;
    raise notice '   montant du force    : %  (ecrit sur la fiche)', v_montant_du;
  end if;

  -- ------------------------------------------------------------- 4) cible
  --  Le montant dû fait foi. On ne retient jamais moins que ce qui est déjà
  --  enregistré, ni plus que ce qui est dû : impossible de fabriquer un solde
  --  négatif ou un trop-perçu.
  v_cible := least(greatest(v_paye, v_montant_du), v_montant_du);

  if v_cible > v_paye then
    update public.entreprises
       set montant_deja_paye = v_cible,
           updated_at        = now()
     where id = v_eid
    returning * into v_e;
    raise notice '   deja paye           : %  ->  %', v_paye, v_cible;
  else
    raise notice '   deja paye           : %  (aucune correction necessaire)', v_paye;
  end if;

  raise notice '   solde restant       : %', coalesce(v_e.solde_restant, 0);

  -- --------------------------------------------------------- 5) conclusion
  -- Tout est réglé → l'abonnement est conclu, sauf compte suspendu.
  if coalesce(v_e.solde_restant, 0) <= 0
     and coalesce(v_e.montant_deja_paye, 0) > 0
     and v_e.statut::text <> 'SUSPENDU'
  then
    select coalesce(nullif(g.duree_abonnement_jours, 0), 30)
      into v_duree
      from public.groupes_tarifaires g
     where g.id = v_e.groupe_tarifaire_id;
    v_duree := coalesce(v_duree, 30);

    update public.entreprises
       set statut           = 'ACTIF'::public.statut_abonnement_enum,
           activation_etape = case
                                when activation_etape in ('verifie', 'restreint')
                                  then 'actif'
                                else activation_etape
                              end,
           date_activation  = coalesce(date_activation, now()),
           -- On repart d'une date future s'il y en a une : le client ne perd
           -- aucun jour déjà payé.
           date_expiration  = greatest(coalesce(date_expiration, now()), now())
                              + make_interval(days => v_duree),
           valide_le_finance = coalesce(valide_le_finance, now()),
           updated_at       = now()
     where id = v_eid
    returning * into v_e;

    raise notice '   ABONNEMENT CONCLU : ACTIF, expiration % (+% jours)',
                 to_char(v_e.date_expiration, 'DD/MM/YYYY'), v_duree;
  elsif v_e.statut::text = 'SUSPENDU' then
    raise notice '   compte SUSPENDU : reactivation laissee a l''administrateur';
  else
    raise notice '   il reste un solde : abonnement non conclu';
  end if;

  -- ------------------------------------------------------------- 5) traçabilité
  --  `id` est fourni explicitement (comme dans la migration 23) : la colonne
  --  peut ne pas avoir de valeur par défaut, et une insertion sans elle
  --  échouerait en NOT NULL, ce qui annulerait toute la migration.
  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(),
    v_eid, 'ABONNEMENT_CORRIGE_M54', null,
    jsonb_build_object(
      'compte', v_email,
      'montant_deja_paye_avant', v_paye,
      'montant_deja_paye_apres', coalesce(v_e.montant_deja_paye, 0),
      'total_verse_historique', v_verse,
      'solde_restant', coalesce(v_e.solde_restant, 0),
      'statut', v_e.statut::text,
      'date_expiration', v_e.date_expiration,
      'motif', 'correctif 53 — acompte efface, abonnement conclu'
    ),
    now()
  );
end $$;


-- ============================================================================
--  CONTRÔLE — le tableau qui confirme le résultat
-- ============================================================================

select u.email                     as compte,
       e.nom                       as entreprise,
       e.montant_total_du          as montant_du,
       e.montant_deja_paye         as deja_paye,
       e.solde_restant             as solde_restant,
       e.statut::text              as statut,
       e.activation_etape          as etape,
       to_char(e.date_expiration, 'DD/MM/YYYY') as expiration,
       (e.date_expiration - now()) as jours_restants
  from public.utilisateurs u
  left join public.utilisateurs p on p.id = u.parent_id
  join public.entreprises e on e.id = coalesce(u.entreprise_id, p.entreprise_id)
 where lower(btrim(u.email)) = lower(btrim('biasharagroup@gmail.com'));


-- ============================================================================
--  HISTORIQUE DES VERSEMENTS — ce que le client a réellement payé
-- ============================================================================

select to_char(h.created_at, 'DD/MM/YYYY HH24:MI') as "date",
       h.montant                                    as verse,
       h.type_paiement                              as "type",
       h.total_apres                                as cumule_apres,
       lag(h.total_apres) over (order by h.created_at) as cumule_precedent,
       case when h.total_apres < lag(h.total_apres) over (order by h.created_at)
            then 'cumule en baisse = bug du complement'
            else '' end                             as observation
  from public.paiements_abonnements_laperle h
  join public.entreprises e on e.id = h.entreprise_id
  join public.utilisateurs u on lower(btrim(u.email)) = lower(btrim('biasharagroup@gmail.com'))
  left join public.utilisateurs p on p.id = u.parent_id
 where e.id = coalesce(u.entreprise_id, p.entreprise_id)
 order by h.created_at;

-- ============================================================================
--  FIN — correctif 54.
-- ============================================================================
