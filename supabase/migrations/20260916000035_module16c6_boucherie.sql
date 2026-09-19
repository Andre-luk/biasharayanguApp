-- ============================================================================
--  biashara_yangu — MODULE 16 (PHASE C6) : BOUCHERIE — VENTE AU POIDS
--
--  OBJECTIF (roadmap multi-activités, module C6) :
--    Le type d'activité « Boucherie » active le module `pesee` : certains
--    articles se vendent au POIDS (kg) et non à la pièce.
--      • `produits.vendable_au_poids` marque l'article vendu au kg ;
--      • les quantités DÉCIMALES sont déjà acceptées de bout en bout
--        (panier, `rpc_vente_valider`, stock, reçus) — aucune autre
--        modification serveur n'est nécessaire ;
--      • l'application adapte la caisse : saisie du poids (0,75 kg),
--        pas de 0,5 kg, prix au kg, ticket avec le poids.
--
--  CONTENU :
--    1. colonne `produits.vendable_au_poids` ;
--    2. profil « Boucherie » du référentiel des activités.
--
--  OÙ : Supabase → SQL Editor → coller → Run
--  IDEMPOTENT : peut être relancé sans effet de bord.
-- ============================================================================


-- ============================================================================
--  1. COLONNE `public.produits.vendable_au_poids`
-- ============================================================================
--  `true` = l'article se vend au poids : la caisse propose la saisie en
--  kg (quantités décimales) et l'unité de mesure doit être 'kg'.
--  Les ventes, le stock et les reçus acceptent déjà les décimales
--  (Module 8 : `quantite` numérique) — aucun changement des RPC.

alter table public.produits
  add column if not exists vendable_au_poids boolean not null default false;

comment on column public.produits.vendable_au_poids is
  'Module 16 C6 (boucherie) — article vendu au poids (kg) : la caisse propose la saisie du poids, pas de 0,5 kg.';


-- ============================================================================
--  2. PROFIL « BOUCHERIE » — RÉFÉRENTIEL DES ACTIVITÉS (Module 16 A)
-- ============================================================================
insert into public.types_espaces_modules (type, libelle, modules) values
  ('boucherie', 'Boucherie',
   '["ventes","produits","stock","qr","caisse","clients","finance","employes","rapports","assistant_ia","pesee"]'::jsonb)
on conflict (type) do nothing;


-- ============================================================================
--  3. VÉRIFICATIONS
-- ============================================================================

-- 3.a La colonne existe (attendu : 1 ligne, boolean, défaut false).
select column_name, data_type, column_default
  from information_schema.columns
 where table_schema = 'public'
   and table_name = 'produits'
   and column_name = 'vendable_au_poids';

-- 3.b Le profil « Boucherie » est enregistré (attendu : 1 ligne, 11 modules).
select type, libelle, jsonb_array_length(modules) as nb_modules
  from public.types_espaces_modules
 where type = 'boucherie';

-- 3.c Exemple (à exécuter avec un vrai compte) :
--     update public.produits
--        set vendable_au_poids = true, unite_mesure = 'kg'
--      where nom = 'Viande de bœuf (filet)';

-- ============================================================================
--  FIN — Module 16 C6 (boucherie). L'application (prochaine version) adapte
--  la caisse : article « au kg » ou « au poids », saisie 0,75 kg, pas de
--  0,5 kg, ticket avec le poids.
-- ============================================================================
