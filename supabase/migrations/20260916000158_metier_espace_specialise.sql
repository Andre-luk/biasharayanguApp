-- ============================================================================
--  biashara_yangu — MIGRATION 0158 : LE MÉTIER D'UNE ENTREPRISE SPÉCIALISÉE
--
--  CE QUE L'INVENTAIRE A RÉVÉLÉ (12/11/2026)
--    « HEKIMA PHARMA » porte `entreprises.type_activite = 'boutique'`
--    alors que son espace de travail est une pharmacie.
--
--    Conséquence en cascade :
--      • `rpc_mes_modules()` lit `entreprises.type_activite` EN PREMIER
--        (migration 0154) → l'entreprise reçoit le profil « boutique » ;
--      • le profil boutique ne contient PAS `lots_expiration` ;
--      • `ArticleFormPage` masque donc la section « Lot + date de
--        péremption »… alors que l'accueil, lui, affiche déjà la carte
--        Expirations.
--
--    0157 ne pouvait pas le corriger : il ne remplissait `type_activite`
--    que lorsqu'elle était VIDE, jamais lorsqu'elle était fausse.
--
--  CE QUE FAIT CE SCRIPT (idempotent, aucune donnée supprimée)
--    1. Le type de l'entreprise suit ses ESPACES quand ceux-ci sont
--       unanimes sur un métier SPÉCIALISÉ (pharmacie, hôtel, restaurant,
--       pressing, boulangerie, salle des fêtes, dépôt).
--       Une entreprise dont l'espace est « boutique » n'est jamais touchée.
--    2. Un espace resté en « boutique »/« autre » dans une entreprise
--       spécialisée prend le métier de son entreprise (cohérence inverse).
--    3. Verdict en UNE ligne : métier, espace, modules réellement servis.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);


-- ============================================================================
--  1. L'ENTREPRISE SUIT SES ESPACES (métier spécialisé unanime)
-- ============================================================================

with candidat as (
  select e.id,
         min(s.type)                   as type_unique,
         count(distinct s.type)        as nb_types,
         count(*)                      as nb_espaces
    from public.entreprises e
    join public.espaces s on s.entreprise_id = e.id
   group by e.id
)
update public.entreprises e
   set type_activite = c.type_unique
  from candidat c
 where e.id = c.id
   and c.nb_types = 1
   and c.nb_espaces >= 1
   -- Uniquement un métier SPÉCIALISÉ : « boutique » et « autre » ne sont
   -- jamais imposés (ce sont les valeurs par défaut).
   and c.type_unique in (
         'pharmacie', 'hotel', 'restaurant', 'pressing',
         'boulangerie', 'salle_fetes', 'depot')
   and coalesce(btrim(e.type_activite), '') <> c.type_unique;


-- ============================================================================
--  2. L'ESPACE SUIT SON ENTREPRISE (cohérence inverse)
-- ============================================================================

update public.espaces s
   set type = e.type_activite
  from public.entreprises e
 where e.id = s.entreprise_id
   and coalesce(btrim(e.type_activite), '') in (
         'pharmacie', 'hotel', 'restaurant', 'pressing',
         'boulangerie', 'salle_fetes', 'depot')
   and coalesce(btrim(s.type), '') in ('', 'boutique', 'autre');


-- ============================================================================
--  3. VERDICT — UNE SEULE LIGNE
-- ============================================================================

with cible as (
  select e.nom, e.type_activite,
         (select s.nom  from public.espaces s
           where s.entreprise_id = e.id order by s.created_at limit 1) as espace_nom,
         (select s.id   from public.espaces s
           where s.entreprise_id = e.id order by s.created_at limit 1) as espace_id,
         (select s.type from public.espaces s
           where s.entreprise_id = e.id order by s.created_at limit 1) as espace_type
    from public.entreprises e
   where lower(coalesce(e.type_activite, '')) = 'pharmacie'
   order by e.created_at
   limit 1
)
select jsonb_pretty(
  jsonb_build_object(
    'entreprise',        (select c.nom from cible c),
    'type_activite',     (select c.type_activite from cible c),
    'espace',            (select c.espace_nom from cible c),
    'espace_type',       (select c.espace_type from cible c),

    -- Le profil de modules du métier (référentiel 0027)
    'profil_modules',    (select t.modules
                            from public.types_espaces_modules t
                           join cible c on c.type_activite = t.type),

    -- Le module qui commande le champ date de péremption
    'lots_expiration',   exists (
                           select 1
                             from public.types_espaces_modules t
                             join cible c on c.type_activite = t.type
                            where t.modules ? 'lots_expiration'),

    -- Les articles déjà enregistrés pour cet espace
    'articles',          (select count(*) from public.produits p
                            join cible c on p.owner_id = c.espace_id),

    'verdict', case
      when exists (select 1 from public.types_espaces_modules t
                     join cible c on c.type_activite = t.type
                    where t.modules ? 'lots_expiration')
        then '✅ le formulaire d''article proposera le lot et la date de péremption'
      else '⚠️ profil sans lots_expiration : vérifier rpc_mes_modules()'
    end
  )
) as verdict;
