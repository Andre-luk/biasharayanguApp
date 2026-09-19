-- ============================================================================
--  biashara_yangu — MODULE 16 (PHASE C8) : VARIANTES (MODE) — TAILLES & COULEURS
--
--  OBJECTIF (roadmap multi-activités, module C8) :
--    Le type d'activité « Mode & vêtements » active le module `variantes` :
--      • `produits.attributs` (jsonb) porte les variantes SIMPLES de
--        l'article : taille, couleur, marque… (saisie libre en clair) ;
--      • la recherche d'articles couvre ces attributs ;
--      • aucune vente/stock spécial : chaque variante reste un ARTICLE à
--        part entière (simple et fiable), les attributs servent à les
--        retrouver et à les afficher.
--
--  CONTENU :
--    1. colonne `produits.attributs` ;
--    2. profil « Mode & vêtements » du référentiel des activités.
--
--  OÙ : Supabase → SQL Editor → coller → Run
--  IDEMPOTENT : peut être relancé sans effet de bord.
-- ============================================================================


-- ============================================================================
--  1. COLONNE `public.produits.attributs`
-- ============================================================================
--  Objet JSON libre : {"taille": "M", "couleur": "Bleu", "marque": "X"}
--  '{}' par défaut : les articles sans variante ne changent pas.

alter table public.produits
  add column if not exists attributs jsonb not null default '{}'::jsonb;

comment on column public.produits.attributs is
  'Module 16 C8 (mode) — variantes simples de l''article : {"taille","couleur","marque"} (objet JSON, {} si aucune).';


-- ============================================================================
--  2. PROFIL « MODE & VÊTEMENTS » — RÉFÉRENTIEL DES ACTIVITÉS (Module 16 A)
-- ============================================================================
insert into public.types_espaces_modules (type, libelle, modules) values
  ('mode', 'Mode & vêtements',
   '["ventes","produits","stock","qr","caisse","clients","finance","employes","rapports","assistant_ia","variantes"]'::jsonb)
on conflict (type) do nothing;


-- ============================================================================
--  3. VÉRIFICATIONS
-- ============================================================================

-- 3.a La colonne existe (attendu : 1 ligne, jsonb, défaut {}).
select column_name, data_type, column_default
  from information_schema.columns
 where table_schema = 'public'
   and table_name = 'produits'
   and column_name = 'attributs';

-- 3.b Le profil « Mode & vêtements » est enregistré (attendu : 1 ligne, 11 modules).
select type, libelle, jsonb_array_length(modules) as nb_modules
  from public.types_espaces_modules
 where type = 'mode';

-- 3.c Exemple (à exécuter avec un vrai compte) :
--     update public.produits
--        set attributs = '{"taille":"M","couleur":"Bleu","marque":"Casino"}'::jsonb
--      where nom = 'Chemise';

-- ============================================================================
--  FIN — Module 16 C8 (variantes). L'application (prochaine version) ajoute
--  les champs taille / couleur / marque à la fiche article, les affiche et
--  les inclut dans la recherche.
-- ============================================================================
