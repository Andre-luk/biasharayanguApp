-- ============================================================================
--  biashara_yangu — VÉRIFICATION APRÈS 0157 (compte josephissa)
--  À exécuter dans le SQL Editor APRÈS 20260916000157_pharmacie_coherence.sql
--
--  ⚠️ L'éditeur SQL n'affiche que le DERNIER résultat : tout tient donc dans
--     UNE seule ligne, à lire de gauche à droite.
--
--  Ce que l'on veut voir :
--    • entreprise_id_aligne        = true   (l'entreprise suit l'espace actif)
--    • type_activite               = pharmacie
--    • mon_proprietaire_effectif   = l'UUID de l'espace pharmacie
--    • articles_pharmacie          = le nombre d'articles réellement stockés
--    • articles_visibles           = ce que l'application verra
-- ============================================================================

select set_config('search_path', 'public, extensions', true);

with patron as (
  select u.id, u.entreprise_id, u.espace_actif_id
    from public.utilisateurs u
   where lower(u.email) = 'josephissa@gmail.com'
   order by u.created_at
   limit 1
),
pharma as (
  select e.id as entreprise_id, e.nom, e.type_activite,
         s.id as espace_id, s.nom as espace_nom
    from public.entreprises e
    join public.espaces s on s.entreprise_id = e.id
   where lower(coalesce(e.type_activite, '')) = 'pharmacie'
      or s.id = (select p.espace_actif_id from patron p)
   order by e.created_at
   limit 1
)
select jsonb_pretty(
  jsonb_build_object(
    'compte',                      (select u.email from public.utilisateurs u
                                      where u.id = (select p.id from patron p)),
    'entreprise_active',           (select e.nom from public.entreprises e
                                      where e.id = (select p.entreprise_id from patron p)),
    'espace_actif',                (select s.nom from public.espaces s
                                      where s.id = (select p.espace_actif_id from patron p)),

    -- 1. La cohérence réparée par 0157
    'entreprise_id_aligne',        (select (p.entreprise_id = ph.entreprise_id)
                                      from patron p, pharma ph),

    -- 2. Le métier (pilote les modules : lots_expiration → péremption)
    'entreprise_pharmacie',        (select ph.nom from pharma ph),
    'type_activite',               (select ph.type_activite from pharma ph),
    'module_lots_expiration',      exists (
                                      select 1
                                        from public.types_activite t
                                       where t.type = (select ph.type_activite from pharma ph)
                                         and t.modules ? 'lots_expiration'),

    -- 3. La portée des données (ce que la RLS compare à owner_id)
    'espace_pharmacie_id',         (select ph.espace_id from pharma ph),
    'mon_proprietaire_effectif',   public.mon_proprietaire(),
    'mon_patron',                  public.mon_patron(),

    -- 4. Les articles : stockés sous quel propriétaire ?
    'articles_pharmacie',          (select count(*) from public.produits pr
                                      where pr.owner_id = (select ph.espace_id from pharma ph)),
    'articles_patron',             (select count(*) from public.produits pr
                                      where pr.owner_id = (select p.id from patron p)),
    'articles_orphelins',          (select count(*) from public.produits pr
                                      where pr.owner_id is not null
                                        and not exists (select 1 from public.espaces s
                                                         where s.id = pr.owner_id)
                                        and not exists (select 1 from public.utilisateurs u
                                                         where u.id = pr.owner_id)),

    -- 5. Le pack du métier (le module doit être autorisé par l'abonnement)
    'modules_pharmacie',           (
      select coalesce(jsonb_agg(m order by m), '[]'::jsonb)
        from public.types_activite t,
             jsonb_array_elements_text(t.modules) as m
       where t.type = (select ph.type_activite from pharma ph)
         and m in ('produits', 'stock', 'lots_expiration', 'employes')),

    'verdict', case
      when (select p.espace_actif_id from patron p)
           = public.mon_proprietaire() then '✅ portée cohérente'
      else '⚠️ espace actif non retenu : se déconnecter puis se reconnecter'
    end
  )
) as verification;
