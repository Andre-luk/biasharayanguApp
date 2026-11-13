-- ============================================================================
--  AUDIT — `owner_id` hors espaces + état des collaborateurs
--
--  LECTURE SEULE. À exécuter dans le SQL Editor.
--  Copier UNIQUEMENT la dernière ligne (aucun secret).
--
--  POURQUOI
--    Les FK `owner_id` → `espaces` ont été ajoutées en `NOT VALID` (0166,
--    0169) : les NOUVELLES lignes sont contrôlées, mais les anciennes
--    peuvent encore porter un UUID qui n'est pas un espace (ex. UUID d'un
--    collaborateur). Ces lignes sont invisibles dans l'application ou
--    comptées dans la mauvaise entreprise.
--
--  Si un compteur est > 0, exécuter ensuite la requête de détail (en bas).
-- ============================================================================

select set_config('search_path', 'public, extensions', true);

select 'AUDIT owner_id — ' ||
  'produits: ' || (select count(*) from public.produits p
                     left join public.espaces s on s.id = p.owner_id
                    where s.id is null) ||
  ' | ventes: ' || (select count(*) from public.ventes v
                      left join public.espaces s on s.id = v.owner_id
                     where s.id is null) ||
  ' | clients: ' || (select count(*) from public.clients c
                       left join public.espaces s on s.id = c.owner_id
                      where s.id is null) ||
  ' | depenses: ' || (select count(*) from public.depenses d
                        left join public.espaces s on s.id = d.owner_id
                       where s.id is null) ||
  ' | dettes: ' || (select count(*) from public.dettes x
                      left join public.espaces s on s.id = x.owner_id
                     where s.id is null) ||
  ' | inventaires: ' || (select count(*) from public.inventaires_quotidiens i
                           left join public.espaces s on s.id = i.owner_id
                          where s.id is null) ||
  ' | caisse: ' || (select count(*) from public.caisse ca
                      left join public.espaces s on s.id = ca.owner_id
                     where s.id is null) ||
  ' | lots: ' || (select count(*) from public.produits_lots l
                    left join public.espaces s on s.id = l.owner_id
                   where s.id is null) ||
  ' | mouvements_lots: ' || (select count(*) from public.produits_lots_mouvements m
                               left join public.espaces s on s.id = m.owner_id
                              where s.id is null) ||
  ' || COLLABORATEURS — total: ' ||
  (select count(*) from public.utilisateurs u where u.parent_id is not null) ||
  ' | sans entreprise: ' ||
  (select count(*) from public.utilisateurs u
    where u.parent_id is not null and u.entreprise_id is null) ||
  ' | sans espace actif: ' ||
  (select count(*) from public.utilisateurs u
    where u.parent_id is not null and u.espace_actif_id is null) ||
  ' | inactifs: ' ||
  (select count(*) from public.utilisateurs u
    where u.parent_id is not null and coalesce(u.valide, 1) = 0)
  as verdict;

-- ⚠️ DÉTAIL (à exécuter seulement si un compteur est > 0).
--    Remplacez la table/colonne selon le compteur concerné.
--
-- select p.id, p.nom, p.owner_id, p.created_at,
--        u.nom as proprietaire_probable, u.parent_id
--   from public.produits p
--   left join public.espaces s on s.id = p.owner_id
--   left join public.utilisateurs u on u.id = p.owner_id
--  where s.id is null
--  order by p.created_at desc
--  limit 50;
