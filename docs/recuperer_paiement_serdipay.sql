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
--  ⚠️ PRÉREQUIS : migrations 0124 à 0131 exécutées (surtout 0127, 0128, 0129
--     0130 et 0131).
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
--  3. CRÉDITER LE PAIEMENT DÉJÀ ENCAISSÉ
-- ============================================================================
--  UN SEUL APPEL. La fonction (migration 0131) :
--    • refuse une transaction sans référence SerdiPay (rien n'a pu être
--      encaissé), un compte suspendu, une transaction déjà payée ;
--    • FIGE le montant réellement payé (aucun centime inventé) ;
--    • en déduit le nombre de périodes au prix de base
--      (30 000 ÷ 10 000 = 3 → 90 jours) ;
--    • crédite via le moteur habituel (dates, journal, facture).
--
--  Idempotent : relancer ne crédite jamais deux fois.
--
--  Remplacez la référence, décommentez, exécutez :

-- select public.abonnement_crediter_paiement_serdipay('SER-20261103-E217C61D');


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
