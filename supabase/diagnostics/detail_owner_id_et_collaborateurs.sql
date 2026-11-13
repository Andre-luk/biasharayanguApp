-- ============================================================================
--  DIAGNOSTIC — détail des `owner_id` hors espaces + collaborateurs incomplets
--
--  LECTURE SEULE. À exécuter dans le SQL Editor.
--  Copier UNIQUEMENT la dernière ligne (aucun secret).
--
--  Sert à préparer la migration de réparation : on veut savoir À QUI
--  appartiennent les 25 lignes historiques (utilisateur ? entreprise ?
--  espace proposé) avant de réécrire quoi que ce soit.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);

with orphelins as (
  select 'produits' as table_source, p.id::text as ligne_id, p.owner_id
    from public.produits p
    left join public.espaces s on s.id = p.owner_id
   where s.id is null
  union all
  select 'ventes', v.id::text, v.owner_id
    from public.ventes v
    left join public.espaces s on s.id = v.owner_id
   where s.id is null
  union all
  select 'clients', c.id::text, c.owner_id
    from public.clients c
    left join public.espaces s on s.id = c.owner_id
   where s.id is null
  union all
  select 'depenses', d.id::text, d.owner_id
    from public.depenses d
    left join public.espaces s on s.id = d.owner_id
   where s.id is null
  union all
  select 'dettes', x.id::text, x.owner_id
    from public.dettes x
    left join public.espaces s on s.id = x.owner_id
   where s.id is null
  union all
  select 'inventaires', i.id::text, i.owner_id
    from public.inventaires_quotidiens i
    left join public.espaces s on s.id = i.owner_id
   where s.id is null
  union all
  select 'caisse', ca.id::text, ca.owner_id
    from public.caisse ca
    left join public.espaces s on s.id = ca.owner_id
   where s.id is null
),
proprietaires as (
  select o.owner_id,
         count(*) as nb_lignes,
         string_agg(distinct o.table_source, ',') as tables,
         u.nom,
         u.parent_id,
         u.entreprise_id,
         u.espace_actif_id
    from orphelins o
    left join public.utilisateurs u on u.id = o.owner_id
   group by o.owner_id, u.nom, u.parent_id, u.entreprise_id, u.espace_actif_id
)
select 'DÉTAIL owner_id — ' ||
       coalesce((
         select string_agg(
                  coalesce(p.nom, 'UTILISATEUR INCONNU') ||
                  ' [' || p.tables || ' ×' || p.nb_lignes || ']' ||
                  ' owner=' || p.owner_id ||
                  ' parent=' || coalesce(p.parent_id::text, '-') ||
                  ' entreprise=' || coalesce(p.entreprise_id::text, '-') ||
                  ' espace_actif=' || coalesce(p.espace_actif_id::text, '-'),
                  ' | ' order by p.owner_id)
           from proprietaires p
       ), '(aucune ligne orpheline)') ||
       ' || SANS ENTREPRISE — ' ||
       coalesce((
         select string_agg(
                  coalesce(u.nom, '?') || ' id=' || u.id ||
                  ' parent=' || coalesce(u.parent_id::text, '-') ||
                  ' espace=' || coalesce(u.espace_actif_id::text, '-'),
                  ' | ' order by u.id)
           from public.utilisateurs u
          where u.parent_id is not null
            and u.entreprise_id is null
       ), '(aucun)') ||
       ' || SANS ESPACE ACTIF — ' ||
       coalesce((
         select string_agg(
                  coalesce(u.nom, '?') || ' id=' || u.id ||
                  ' entreprise=' || u.entreprise_id ||
                  ' rôle=' || coalesce(u.new_role::text, u.role, '-'),
                  ' | ' order by u.id)
           from public.utilisateurs u
          where u.parent_id is not null
            and u.entreprise_id is not null
            and u.espace_actif_id is null
       ), '(aucun)') as verdict;
