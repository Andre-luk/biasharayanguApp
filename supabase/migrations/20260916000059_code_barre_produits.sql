-- ============================================================================
--  biashara_yangu — CORRECTIF 59 : CODE-BARRES DU PRODUIT
--  Migration 20260916000059_code_barre_produits.sql
-- ============================================================================
--
--  ⛔ AUCUNE COMPILATION, AUCUNE PUBLICATION : préparation de base uniquement.
--
--  LE BESOIN
--  ---------
--  Chaque produit arrive avec son code-barres fabricant (EAN-13, UPC, Code 128,
--  ITF-14…). Le patron veut :
--     • enregistrer un produit en scannant son code-barres ;
--     • vendre en scannant (le plus rapide à la caisse) ;
--     • retrouver un produit en le scannant depuis la liste, une entrée de
--       stock ou un inventaire.
--
--  CE QUI EXISTAIT DÉJÀ
--  --------------------
--    • `mobile_scanner` est déjà installé, et `lib/pages/scanner_page.dart`
--      sait scanner — mais il ne lit QUE les QR codes (BarcodeFormat.qrCode),
--      c'est-à-dire les étiquettes générées par l'application ;
--    • un champ `code_barre_texte` existe déjà, mais sur les CONDITIONNEMENTS
--      (farde, carton), pas sur le produit lui-même ;
--    • la recherche d'articles sait déjà interroger `code_barre_texte`.
--
--  CE QUE FAIT CETTE MIGRATION
--  ---------------------------
--    1. ajoute `produits.code_barre` — le code-barres du produit, valable
--       pour son UNITÉ DE BASE (décision du patron : le code vit sur le
--       produit) ;
--    2. normalise les valeurs (espaces retirés, chaîne vide → NULL) ;
--    3. garantit qu'un même patron ne peut pas avoir DEUX produits avec le
--       même code-barres (index unique partiel) — sans cette garantie, un
--       scan serait ambigu et vendrait le mauvais article ;
--    4. ajoute les index de recherche, y compris sur l'ancien champ
--       `conditionnements.code_barre_texte` qui sert désormais de REPLI :
--       un code déjà enregistré sur un emballage reste scannable.
--
--  ⚠️ PORTÉE : l'unicité est vérifiée PAR PATRON (`owner_id`), pas par
--     produit : « 1234567890123 » peut donc exister chez deux boutiques
--     différentes sans conflit. C'est voulu (deux commerçants indépendants
--     peuvent vendre le même article du même fabricant).
--
--  AUCUNE DONNÉE N'EST MODIFIÉE : la colonne est neuve, donc vide. La mise à
--  jour de normalisation ne concerne que les valeurs saisies après coup.
--  IDEMPOTENTE : relançable sans effet de bord.
--
--  OÙ : Supabase → SQL Editor → coller → Run
-- ============================================================================


select set_config('search_path', 'public, extensions', true);


-- ============================================================================
--  1. LA COLONNE
-- ============================================================================

alter table public.produits add column if not exists code_barre text;

comment on column public.produits.code_barre is
  'Code-barres fabricant du produit (EAN-13, UPC, Code 128, ITF-14…), valable pour son unité de base. Vide (NULL) = non renseigné. Unique par patron. Correctif 59.';


-- ============================================================================
--  2. NORMALISATION DES VALEURS EXISTANTES
-- ============================================================================
--  Un code-barres ne contient ni espace ni chaîne vide. On ramène donc
--  « 123  » à « 123 » et «   » à NULL : sans cela, deux saisies du même code
--  pourraient coexister et fausser le contrôle d'unicité.

update public.produits
   set code_barre = nullif(btrim(code_barre), '')
 where code_barre is not null
   and btrim(code_barre) is distinct from code_barre;


-- ============================================================================
--  3. UNICITÉ PAR PATRON
-- ============================================================================
--  Index PARTIEL : seules les lignes réellement renseignées sont contrôlées,
--  donc aucun conflit entre les produits sans code-barres (le cas courant).

create unique index if not exists idx_produits_code_barre_unique
  on public.produits (owner_id, code_barre)
  where code_barre is not null;


-- ============================================================================
--  4. RECHERCHE RAPIDE PAR CODE
-- ============================================================================

--  Le scan cherche un code SEUL (la RLS restreint ensuite au patron).
create index if not exists idx_produits_code_barre
  on public.produits (code_barre)
  where code_barre is not null;

--  REPLI : les codes déjà enregistrés sur un emballage restent scannables.
create index if not exists idx_conditionnements_code_barre
  on public.conditionnements (code_barre_texte)
  where code_barre_texte is not null;


-- ============================================================================
--  5. CONTRÔLE — la colonne et les index sont-ils en place ?
-- ============================================================================

do $verif_code_barre$
begin
  if not exists (
    select 1 from information_schema.columns
     where table_schema = 'public'
       and table_name   = 'produits'
       and column_name  = 'code_barre'
  ) then
    raise exception 'Correctif 59 : la colonne produits.code_barre est absente.';
  end if;

  if not exists (
    select 1 from pg_indexes
     where schemaname = 'public'
       and indexname  = 'idx_produits_code_barre_unique'
  ) then
    raise exception 'Correctif 59 : l''index d''unicite produits.code_barre est absent.';
  end if;

  raise notice 'Correctif 59 : colonne et index en place.';
end $verif_code_barre$;


-- ============================================================================
--  RAPPORT FINAL
--  ⚠️ En DERNIER : le SQL Editor n'affiche que le résultat de la dernière
--     instruction du script.
-- ============================================================================

select '1. COLONNE' as bloc,
       'produits.code_barre' as objet,
       case when exists (select 1 from information_schema.columns
                          where table_schema = 'public'
                            and table_name   = 'produits'
                            and column_name  = 'code_barre')
            then 'OK' else 'ABSENTE' end as etat,
       coalesce((select data_type from information_schema.columns
                  where table_schema = 'public'
                    and table_name   = 'produits'
                    and column_name  = 'code_barre'), '—') as detail

union all

select '2. INDEX',
       indexname,
       'OK',
       coalesce(indexdef, '—')
  from pg_indexes
 where schemaname = 'public'
   and indexname in ('idx_produits_code_barre_unique',
                     'idx_produits_code_barre',
                     'idx_conditionnements_code_barre')

union all

select '3. DONNEES',
       'produits',
       count(*)::text || ' produits',
       count(code_barre)::text || ' avec un code-barres renseigne'
  from public.produits

 order by 1, 2;


-- ============================================================================
--  NOTE — CE QUI SERA FAIT CÔTÉ APPLICATION (même version, non compilée ici)
--  ------------------------------------------------------------------------
--    • `Article` : nouveau champ `codeBarre` (lu dans `code_barre`) ;
--    • `ArticleService` : écriture normalisée + message clair en cas de
--      doublon (« ce code-barres est déjà utilisé par <produit> ») ;
--    • `ScannerService` : résolution d'un code BRUT (non-Biashara) par
--      `produits.code_barre`, puis repli sur `conditionnements.code_barre_texte` ;
--    • un lecteur RÉUTILISABLE (caméra + douchette USB/Bluetooth) appelable
--      depuis le formulaire produit, la caisse, l'entrée de stock, la liste
--      des produits et l'inventaire.
-- ============================================================================
