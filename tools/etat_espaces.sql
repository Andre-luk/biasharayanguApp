-- ============================================================================
--  biashara_yangu — ÉTAT RÉEL DES ENTREPRISES ET DE LEURS ESPACES
--
--  Pourquoi : dans l'application, une entreprise peut porter un métier
--  (`entreprises.type_activite`) différent de celui de son espace
--  (`espaces.type`). Les deux pilotent les modules ; quand ils divergent, on
--  obtient exactement les symptômes constatés (pas de champ péremption, cartes
--  métier absentes…).
--
--  Ce script montre TOUT d'un coup, en UNE ligne :
--    • chaque entreprise, son métier déclaré ;
--    • chaque espace (nom + type) ;
--    • le nombre d'articles réellement stockés sous cet espace ;
--    • la portée de données effective (`mon_proprietaire()`).
--
--  Aucune écriture.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);

select jsonb_pretty(
  jsonb_build_object(
    'entreprise_de_travail', (
      select e.nom
        from public.utilisateurs u
        join public.espaces s      on s.id = u.espace_actif_id
        join public.entreprises e  on e.id = s.entreprise_id
       where u.id = auth.uid()),

    'espace_actif',      (select s.nom from public.utilisateurs u
                            join public.espaces s on s.id = u.espace_actif_id
                           where u.id = auth.uid()),
    'mon_proprietaire',  public.mon_proprietaire(),

    -- Le tableau complet : entreprise → espaces (nom + type + articles)
    'entreprises', (
      select coalesce(
               jsonb_agg(
                 jsonb_build_object(
                   'entreprise',    e.nom,
                   'metier',        e.type_activite,
                   'espaces', (
                     select coalesce(
                              jsonb_agg(
                                jsonb_build_object(
                                  'nom',      s2.nom,
                                  'type',     s2.type,
                                  'actif',    s2.actif,
                                  'articles', (select count(*) from public.produits p
                                                where p.owner_id = s2.id)
                                ) order by s2.created_at), '[]'::jsonb)
                       from public.espaces s2
                      where s2.entreprise_id = e.id)
                 ) order by e.created_at),
               '[]'::jsonb)
        from public.entreprises e),

    -- Où sont réellement les articles, par propriétaire (owner_id)
    'articles_par_proprietaire', (
      select coalesce(
               jsonb_agg(
                 jsonb_build_object(
                   'owner_id',    p.owner_id,
                   'espace',      (select s3.nom  from public.espaces s3 where s3.id = p.owner_id),
                   'entreprise',  (select e3.nom  from public.espaces s3
                                     join public.entreprises e3 on e3.id = s3.entreprise_id
                                    where s3.id = p.owner_id),
                   'est_un_utilisateur', exists (select 1 from public.utilisateurs u3
                                                  where u3.id = p.owner_id),
                   'articles',    p.nb
                 ) order by p.nb desc),
               '[]'::jsonb)
        from (select pr.owner_id, count(*) as nb
                from public.produits pr
               group by pr.owner_id) p)
  )
) as etat;
