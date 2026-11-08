-- ============================================================================
--  biashara_yangu — MODULE 29 : CHAQUE ARTICLE PEUT AVOIR SA PROPRE DEVISE
--  ---------------------------------------------------------------------------
--  CE QUE LE PROPRIÉTAIRE DEMANDE
--    « Dans une même entreprise, un produit peut être en CDF et l'autre en
--      USD : je dois pouvoir choisir la devise au moment de créer l'article. »
--
--  CE QUE CE SCRIPT AJOUTE
--    `produits.devise` — code de la devise du prix de CET article
--    (`CDF`, `USD`…). `NULL` = la devise de l'entreprise (comportement
--    historique, aucune donnée existante n'est modifiée).
--
--  ⚠️ RÈGLES
--    • Le prix enregistré reste CELUI QUE LE COMMERÇANT SAISIT, dans la
--      devise de l'article : on ne convertit rien en base.
--    • La conversion en devise de l'entreprise se fait à la VENTE, avec le
--      taux du jour (`rpc_devise_etat`, Module 18) : c'est la seule façon
--      d'avoir des totaux justes sans figer un taux dans le catalogue.
--    • Les emballages (`conditionnements`) partagent la devise de leur
--      article : pas de colonne supplémentaire, donc aucune incohérence
--      possible entre un produit et sa farde.
--    • IDEMPOTENT.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);

alter table public.produits
  add column if not exists devise text;

comment on column public.produits.devise is
  'Module 29 — devise du prix de cet article (CDF, USD…). NULL = devise de l''entreprise. Le prix reste stocké tel que saisi ; la conversion se fait à la vente avec le taux du jour.';

-- Index partiel : retrouver rapidement les articles d'une devise donnée
-- (utile aux rapports « combien de mon catalogue est en USD »).
create index if not exists idx_produits_devise
  on public.produits (devise)
  where devise is not null;


-- ============================================================================
--  VÉRIFICATION
-- ============================================================================

select column_name, data_type, is_nullable
  from information_schema.columns
 where table_schema = 'public'
   and table_name = 'produits'
   and column_name = 'devise';
