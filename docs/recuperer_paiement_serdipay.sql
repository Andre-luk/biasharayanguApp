-- ============================================================================
--  BIASHARA YANGU — RÉCUPÉRER UN PAIEMENT MOBILE MONEY RESTÉ « EN ATTENTE »
--  Fichier : docs/recuperer_paiement_serdipay.sql
--  ---------------------------------------------------------------------------
--  À QUOI ÇA SERT
--    Une transaction SerdiPay peut rester `en_attente` alors que le client a
--    réellement payé : le webhook est arrivé, mais le crédit de l'abonnement a
--    échoué (ex. erreur `uuid = text` du 03/11/2026) — toute la transaction est
--    alors annulée et la ligne repasse en `en_attente` à chaque rejeu.
--
--  ⚠️ RÈGLE ABSOLUE
--    N'exécutez la section 3 QUE si le tableau de bord SerdiPay (ou leur
--    support) confirme que la transaction a été PAYÉE. Sinon vous créditerez un
--    abonnement sans argent reçu.
--
--  Tout est exécuté dans UN SEUL bloc : l'identité « FINANCE » est empruntée
--  le temps de la transaction (comme le fait le webhook), puis rendue.
--
--  ⚠️ PRÉREQUIS : migrations 0124, 0125 et 0127 exécutées.
--     Sans la 0127, ouvrir plusieurs cycles sur un dossier ÉCHU laisse le
--     statut à `EXPIRE` et le moteur répond `MONTANT_SUPERIEUR` (il recalcule
--     un seul cycle) : l'argent reste bloqué.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);


-- ============================================================================
--  1. LIRE LA TRANSACTION — que dit la base ?
-- ============================================================================
select s.reference,
       s.statut,
       s.montant,
       s.devise,
       s.operateur,
       s.telephone,
       s.provider_reference,
       s.created_at,
       s.expire_le,
       e.nom as entreprise,
       public.rpc_abonnement_prix_du_cycle(s.entreprise_id) as prix_du_cycle,
       -- Combien de cycles ce montant représente-t-il ?
       case
         when public.rpc_abonnement_prix_du_cycle(s.entreprise_id) > 0
           then round(s.montant / public.rpc_abonnement_prix_du_cycle(s.entreprise_id), 2)
         else null
       end as cycles_couverts
  from public.paiements_serdipay s
  join public.entreprises e on e.id = s.entreprise_id
 where s.reference = 'SER-20261103-E217C61D';   -- ← à remplacer


-- ============================================================================
--  2. VÉRIFIER AVANT D'AGIR (lecture seule)
-- ============================================================================
--  `cycles_couverts` doit être un ENTIER. Exemple réel (Urembo Market) :
--     montant = 30 000 CDF, prix du cycle = 10 000  →  3 cycles
--  Si ce n'est pas un entier, ne lancez pas la section 3 : le montant reçu ne
--  correspond pas au tarif et doit être arbitré à la main.


-- ============================================================================
--  3. CONFIRMER LE PAIEMENT ET CRÉDITER L'ABONNEMENT
-- ============================================================================
--  Le bloc :
--    1. emprunte l'identité du compte FINANCE de la plateforme ;
--    2. ouvre autant de cycles que le montant en couvre (30 000 ÷ 10 000 = 3) ;
--    3. confirme la transaction SerdiPay → le moteur crédite, active et
--       prolonge de 30 jours × nombre de cycles.
--  Idempotent : si la transaction est déjà `paye`, la fonction répond
--  « déjà » et ne crédite rien une seconde fois.

-- do $$
-- declare
--   v_ref      text := 'SER-20261103-E217C61D';   -- ← référence interne
--   v_provider text;
--   v_acteur   uuid;
--   v_s        public.paiements_serdipay%rowtype;
--   v_prix     numeric := 0;
--   v_mois     integer;
--   v_prep     jsonb;
-- begin
--   select * into v_s
--     from public.paiements_serdipay
--    where reference = v_ref
--      for update;
--
--   if v_s.id is null then
--     raise exception 'Référence % inconnue.', v_ref;
--   end if;
--
--   if v_s.statut = 'paye' then
--     raise notice 'Cette transaction est DÉJÀ payée : rien à faire.';
--     return;
--   end if;
--
--   v_prix := public.rpc_abonnement_prix_du_cycle(v_s.entreprise_id);
--   if v_prix is null or v_prix <= 0 then
--     raise exception 'Aucun prix de cycle pour cette entreprise : arbitrez à la main.';
--   end if;
--
--   v_mois := round(v_s.montant / v_prix);
--   if v_mois < 1 or abs(v_mois * v_prix - v_s.montant) > 0.01 then
--     raise exception
--       'Le montant reçu (% %) ne correspond pas à un nombre entier de cycles de % % : traitez ce dossier manuellement.',
--       v_s.montant, v_s.devise, v_prix, v_s.devise;
--   end if;
--
--   -- Identité de confiance : la même que celle utilisée par le webhook.
--   select u.id into v_acteur
--     from public.utilisateurs u
--    where u.new_role = 'FINANCE_LAPERLE'
--    order by u.id limit 1;
--
--   if v_acteur is null then
--     raise exception 'Aucun compte FINANCE_LAPERLE : impossible de créditer.';
--   end if;
--
--   perform set_config('request.jwt.claim.sub', v_acteur::text, true);
--   perform set_config(
--     'request.jwt.claims',
--     jsonb_build_object('sub', v_acteur::text, 'role', 'authenticated')::text,
--     true
--   );
--
--   -- Ouvre N cycles à encaisser (montant_total_du = prix × N).
--   -- Sur un dossier échu, la migration 127 le place en EN_ATTENTE_COMPLEMENT
--   -- pour que le moteur crédite le montant figé au lieu de le recalculer.
--   v_prep := public.abonnement_ouvrir_avance_multi(v_s.entreprise_id, v_mois);
--   raise notice 'Cycles ouverts : % → montant réclamé % %',
--     v_prep ->> 'mois', v_prep ->> 'montant', v_prep ->> 'devise';
--
--   -- Confirme SerdiPay : vérifie le montant, puis crédite via le moteur.
--   v_provider := v_s.provider_reference;
--
--   perform public.rpc_serdipay_confirmer(
--     p_reference          => v_s.reference,
--     p_statut             => 'paye',
--     p_provider_reference => v_provider,
--     p_montant_recu       => v_s.montant,
--     p_payload            => jsonb_build_object('source', 'recuperation_operateur')
--   );
--
--   raise notice 'Paiement confirmé : abonnement crédité et prolongé.';
-- end $$;


-- ============================================================================
--  4. CONTRÔLE APRÈS COUP
-- ============================================================================
select s.reference,
       s.statut,
       s.paye_le,
       e.nom,
       e.statut::text     as statut_abonnement,
       e.date_expiration,
       e.montant_deja_paye,
       e.solde_restant
  from public.paiements_serdipay s
  join public.entreprises e on e.id = s.entreprise_id
 where s.reference = 'SER-20261103-E217C61D';   -- ← à remplacer

-- Attendu : statut = paye, statut_abonnement = ACTIF, solde_restant = 0,
-- date_expiration repoussée de 30 jours × nombre de cycles.
