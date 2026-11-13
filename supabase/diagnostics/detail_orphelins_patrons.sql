-- ============================================================================
--  DIAGNOSTIC — les 6 patrons orphelins possèdent-ils encore une entreprise ?
--
--  LECTURE SEULE. À exécuter dans le SQL Editor.
--  Copier UNIQUEMENT la dernière ligne.
--
--  owner_id orphelins constatés :
--    007a0852… « km hôtel »       29f2138d… « Jambo mr »
--    33b3ca9e… « Patron Diag »    bc07ab43… « Jean-Luc Takalashi »
--    de005aaf… « Hôtel KZ »       fbc5eee3… « Anaclet Ntumba »
--  Tous : parent_id NULL, entreprise_id NULL, espace_actif NULL.
--
--  On regarde s'ils possèdent une entreprise (`entreprises.owner_id`) et si
--  cette entreprise a un espace où rattacher leurs données.
--  On regarde aussi le patron 56c414cf… (parent des 2 collaborateurs sans
--  entreprise).
-- ============================================================================

select set_config('search_path', 'public, extensions', true);

with cibles as (
  select unnest(array[
    '007a0852-4a9a-4b2e-bdd7-be9c8e80eb34',
    '29f2138d-daa9-4222-bae9-e2f2170ec226',
    '33b3ca9e-aeda-4752-a011-c09dd0235338',
    'bc07ab43-dca5-4049-b48e-090fc308515a',
    'de005aaf-11b1-4caf-ac32-7e15b9deb444',
    'fbc5eee3-1dcf-4785-85f8-e4e4ef2bf115'
  ]::uuid[]) as id
),
lignes as (
  select c.id,
         u.nom,
         (select count(*) from public.entreprises e where e.owner_id = c.id) as nb_ent,
         (select string_agg(e.id::text, ',' order by e.created_at)
            from public.entreprises e where e.owner_id = c.id) as ents,
         (select string_agg(s.id::text || ':' || s.nom, ', ' order by s.created_at)
            from public.espaces s
            join public.entreprises e on e.id = s.entreprise_id
           where e.owner_id = c.id) as espaces
    from cibles c
    left join public.utilisateurs u on u.id = c.id
),
patron_deux as (
  select u.nom,
         u.entreprise_id,
         u.espace_actif_id,
         (select string_agg(s.id::text || ':' || s.nom, ', ')
            from public.espaces s
            join public.entreprises e on e.id = s.entreprise_id
           where e.owner_id = coalesce(u.parent_id, u.id)
              or e.id = u.entreprise_id) as espaces_patron
    from public.utilisateurs u
   where u.id = '56c414cf-5584-481b-9317-5a80dcc6c399'
)
select 'PATRONS ORPHELINS — ' ||
       coalesce((
         select string_agg(
                  coalesce(l.nom, '?') || ' [' || l.id || ']' ||
                  ' entreprises=' || coalesce(l.nb_ent::text, '0') ||
                  ' ids=' || coalesce(l.ents, '-') ||
                  ' espaces=' || coalesce(l.espaces, '-'),
                  ' | ' order by l.id)
           from lignes l
       ), '(aucun)') ||
       ' || PATRON 56c414cf — ' ||
       coalesce((
         select coalesce(p.nom, '?') ||
                ' entreprise=' || coalesce(p.entreprise_id::text, '-') ||
                ' espace_actif=' || coalesce(p.espace_actif_id::text, '-') ||
                ' espaces_dispo=' || coalesce(p.espaces_patron, '-')
           from patron_deux p
       ), '(introuvable)') as verdict;
