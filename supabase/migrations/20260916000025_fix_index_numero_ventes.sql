-- ============================================================================
--  biashara_yangu — CORRECTIF 25 : VENTES MULTI-ARTICLES IMPOSSIBLES
--  (index unique incompatible avec les ventes à plusieurs lignes)
--
--  PROBLÈME (constaté le 18/09/2026 en test de bout en bout) :
--    L'index `idx_ventes_numero_unique` était UNIQUE sur
--    (owner_id, numero_vente). Or TOUTES LES LIGNES d'une même vente
--    partagent le même numéro « VTE-… » (c'est voulu : le numéro identifie
--    la VENTE, pas la ligne). Conséquence : dès qu'un panier contenait
--    DEUX articles ou plus, l'attribution du numéro violait l'index
--    (« duplicate key value … already exists ») et la vente ÉCHOUAIT
--    entièrement. Seules les ventes à UNE SEULE ligne pouvaient aboutir.
--
--  CORRECTIF :
--    • l'unicité du numéro par boutique est conservée pour les lignes
--      LEGACY (vente_uuid null : une ligne = une vente) ;
--    • pour le nouveau flux, l'unicité des numéros est déjà GARANTIE par
--      `prochain_numero_vente()` (compteur atomique par boutique et par
--      jour) → un simple index de recherche est ajouté ;
--    • aucune donnée n'est modifiée.
--
--  OÙ : Supabase → SQL Editor → coller → Run
--  IDEMPOTENT : peut être relancé sans effet de bord.
-- ============================================================================


drop index if exists public.idx_ventes_numero_unique;

-- Lignes legacy : chaque ligne portait son propre numéro (vente_uuid absent).
create unique index if not exists idx_ventes_numero_legacy_unique
  on public.ventes (owner_id, numero_vente)
  where numero_vente is not null
    and vente_uuid is null;

-- Recherche rapide par numéro (NON unique : toutes les lignes d'une vente
-- partagent volontairement le même numéro).
create index if not exists idx_ventes_numero
  on public.ventes (owner_id, numero_vente);
