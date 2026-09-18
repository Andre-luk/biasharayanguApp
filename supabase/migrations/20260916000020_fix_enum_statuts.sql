-- ============================================================================
--  biashara_yangu — CORRECTIF 20 : VALEURS MANQUANTES DANS L'ENUM DES STATUTS
--
--  POURQUOI ?
--  ─────────────────────────────────────────────────────────────────────────
--  L'application et les migrations écrivent deux valeurs qui n'ont jamais
--  été ajoutées au type `public.statut_abonnement_enum` :
--
--      • EN_ATTENTE_COMPLEMENT — création de compte (Modules 14/15) et
--        paiement partiel « en attente de complément » ;
--      • EXPIRE                — expiration automatique de l'abonnement.
--
--  CONSÉQUENCE CONSTATÉE (18/09/2026) :
--    chaque inscription de patron échouait avec
--      « invalid input value for enum statut_abonnement_enum:
--         "EN_ATTENTE_COMPLEMENT" »
--    → l'entreprise n'était PAS créée et le compte restait invisible dans
--      l'administration (l'appel étant « best-effort », l'utilisateur
--      continuait sans voir l'erreur).
--
--  ⚠️  DEUX ÉTAPES — CE FICHIER DOIT ÊTRE EXÉCUTÉ SEUL
--  PostgreSQL interdit d'UTILISER une nouvelle valeur d'enum dans la
--  transaction qui l'ajoute. Donc :
--      ÉTAPE 1 : exécutez CE fichier (et lui seul) → Run ;
--      ÉTAPE 2 : exécutez ensuite `20260916000021_rattrapage_comptes.sql`
--                (mise à jour du RPC + rattrapage des comptes + vérifs).
--
--  OÙ : Supabase → SQL Editor → coller → Run
--  IDEMPOTENT : `add value if not exists` → réexécutable sans effet.
-- ============================================================================


alter type public.statut_abonnement_enum
  add value if not exists 'EN_ATTENTE_COMPLEMENT';

alter type public.statut_abonnement_enum
  add value if not exists 'EXPIRE';
