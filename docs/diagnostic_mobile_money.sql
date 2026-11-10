-- ============================================================================
--  BIASHARA YANGU — DIAGNOSTIC « PAIMENT MOBILE MONEY »
--  Fichier : docs/diagnostic_mobile_money.sql
--  ---------------------------------------------------------------------------
--  À exécuter dans l'éditeur SQL de Supabase — LECTURE SEULE, ne modifie rien.
--
--  Il répond à trois questions, dans l'ordre :
--    1. Quel est le TYPE RÉEL de la colonne `entreprise_id` des trois tables
--       du parcours de paiement ? (une table historique en `text` explique
--       l'erreur « operator does not exist: uuid = text »)
--    2. La correction 44 est-elle bien installée ? (comparaison en `::text`)
--    3. Pour un client précis (ex. Urembo Market), existe-t-il une transaction
--       SerdiPay EN ATTENTE avec sa référence fournisseur ? Sans elle, le
--       garde-fou refuse le paiement Mobile Money — et c'est normal.
-- ============================================================================

-- ============================================================================
--  1. LES TYPES RÉELS
-- ============================================================================
select table_name, column_name, data_type
  from information_schema.columns
 where table_schema = 'public'
   and (
        (table_name = 'paiements_serdipay'             and column_name = 'entreprise_id')
     or (table_name = 'paiements_abonnements_laperle'  and column_name = 'entreprise_id')
     or (table_name = 'agent_ia_achats'                and column_name = 'entreprise_id')
     or (table_name = 'entreprises'                    and column_name = 'id')
       )
 order by table_name;

-- Lecture : si `paiements_abonnements_laperle.entreprise_id` = `text` alors que
-- `paiements_serdipay.entreprise_id` = `uuid`, la cause de l'erreur est
-- confirmée (et la migration 0124 la neutralise).


-- ============================================================================
--  2. LA CORRECTION EST-ELLE INSTALLÉE ?
-- ============================================================================
select position('entreprise_id::text' in pg_get_functiondef(
         'public.paiement_mm_exige_serdipay()'::regprocedure)) > 0
         as garde_paiement_corrige,
       position('entreprise_id::text' in pg_get_functiondef(
         'public.achat_quota_mm_exige_serdipay()'::regprocedure)) > 0
         as garde_quota_corrige;

-- Attendu : true, true. Si l'un est false, rejouer
-- supabase/migrations/20260916000124_fix_mobile_money_uuid_text.sql


-- ============================================================================
--  3. LE CLIENT A-T-IL UNE TRANSACTION SERDIPAY EN ATTENTE ?
-- ============================================================================
--  Remplace « urembo » par le début du nom de la boutique si besoin.
select c.id                        as entreprise_id,
       c.nom                       as entreprise,
       (select count(*)
          from public.paiements_serdipay ps
         where ps.entreprise_id::text = c.id::text)          as transactions_totales,
       (select count(*)
          from public.paiements_serdipay ps
         where ps.entreprise_id::text = c.id::text
           and ps.statut = 'en_attente')                     as en_attente,
       (select count(*)
          from public.paiements_serdipay ps
         where ps.entreprise_id::text = c.id::text
           and ps.statut = 'en_attente'
           and ps.provider_reference is not null)            as exploitables
  from public.entreprises c
 where c.nom ilike '%urembo%'
 order by c.nom;

-- Lecture :
--   • `exploitables` > 0  → le garde-fou laissera passer le paiement.
--   • `exploitables` = 0 et `transactions_totales` > 0 → les transactions
--     existent mais n'ont jamais reçu de référence fournisseur : c'est
--     l'appel à SerdiPay qui n'a pas abouti (clé, URL ou compte marchand),
--     pas la base.
--   • `transactions_totales` = 0 → le paiement n'a jamais été ouvert :
--     l'erreur se produit AVANT l'insertion, en amont dans la passerelle.


-- ============================================================================
--  4. DERNIÈRES TRANSACTIONS (pour voir le motif d'échec exact)
-- ============================================================================
select reference,
       statut,
       montant,
       devise,
       operateur,
       provider_reference,
       motif_echec,
       created_at
  from public.paiements_serdipay
 order by created_at desc
 limit 10;
