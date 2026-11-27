-- ============================================================================
--  biashara_yangu — MIGRATION 0182 / CORRECTIF 182
--  PÉRIMÈTRE DES VENTES : L'UTILISATEUR PATRON N'ENTRE PLUS DANS LE PÉRIMÈTRE
-- ---------------------------------------------------------------------------
--  📌 OÙ L'EXÉCUTER : éditeur SQL de Supabase, APRÈS la 0181.
--  ⚠️ IDEMPOTENT. Aucune donnée métier modifiée.
--
--  ════════════════════════════════════════════════════════════════════════
--  CONSTAT LIVE (27/11/2026, compte josephissa@gmail.com)
--  ════════════════════════════════════════════════════════════════════════
--  Après la 0181, les tableaux de bord d'Urembo et de HEKIMA affichaient
--  ENCORE les mêmes ventes (84 / 88 500 CDF), alors que les produits,
--  l'équipe et la finance étaient bien cloisonnés.
--
--  Sonde du périmètre :
--    Urembo (entreprise 31a30b1a) → [07a0cdf1, cba118e7]
--    HEKIMA (entreprise fa095fd7) → [07a0cdf1, be5a5d15, dc165e6b]
--
--  `07a0cdf1` est l'UUID du PATRON. Il entre dans le périmètre de HEKIMA
--  par la branche « utilisateurs de l'entreprise » : à chaque bascule,
--  `rpc_espace_basculer` met `utilisateurs.entreprise_id` du patron sur
--  l'entreprise active. Or cet UUID est AUSSI l'identifiant du tout premier
--  espace (Urembo) → les ventes d'Urembo sont comptées dans HEKIMA.
--
--  La 0181 avait exclu `entreprises.owner_id` : insuffisant, puisque le même
--  UUID revient par `utilisateurs.id`.
--
--  ════════════════════════════════════════════════════════════════════════
--  CORRECTIF
--  ════════════════════════════════════════════════════════════════════════
--  Dans `perimetre_entreprise()` :
--    • on EXCLUT de la branche utilisateurs le propriétaire de l'entreprise ;
--    • on EXCLUT tout utilisateur dont l'ID est aussi un ESPACE (convention
--      historique : le patron et son espace par défaut partagent l'UUID).
--  Les données portées par ces identifiants restent comptées là où elles
--  appartiennent : par la branche « espaces », dans leur propre entreprise.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);

create or replace function public.perimetre_entreprise(
  p_entreprise_id uuid default null
)
returns text[]
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_eid   uuid;
  v_owner uuid;
  v_arr   text[];
begin
  v_eid := public.resoudre_entreprise(p_entreprise_id);

  if v_eid is not null then
    select e.owner_id into v_owner
      from public.entreprises e
     where e.id = v_eid;

    select coalesce(array_agg(distinct x::text), array[]::text[])
      into v_arr
      from (
        -- 1. Les espaces de l'entreprise (les données sont chez eux).
        select s.id as x
          from public.espaces s
         where s.entreprise_id::text = v_eid::text
        union
        -- 2. Les utilisateurs de l'entreprise, pour les données historiques
        --    écrites avec l'UUID d'un membre.
        --    ⚠️ MAIS JAMAIS :
        --      – le propriétaire (son UUID appartient à toutes ses
        --        entreprises ; c'est LE mélange constaté) ;
        --      – un utilisateur dont l'ID est aussi un ESPACE (l'espace par
        --        défaut porte l'UUID du patron : ses données sont déjà
        --        comptées par la branche 1).
        select u.id
          from public.utilisateurs u
         where u.entreprise_id::text = v_eid::text
           and (v_owner is null or u.id is distinct from v_owner)
           and not exists (
             select 1 from public.espaces s3 where s3.id = u.id)
        union
        -- 3. Compatibilité : l'UUID du patron, UNIQUEMENT pour une
        --    entreprise sans aucun espace (comptes d'avant le module 15).
        select e.owner_id
          from public.entreprises e
         where e.id = v_eid
           and e.owner_id is not null
           and not exists (
             select 1 from public.espaces s2 where s2.entreprise_id = e.id)
      ) t;
  end if;

  if v_arr is null or coalesce(array_length(v_arr, 1), 0) = 0 then
    v_arr := array[
      coalesce(public.mon_proprietaire(), auth.uid())::text
    ];
  end if;

  return array_remove(v_arr, null);
end;
$$;

comment on function public.perimetre_entreprise(uuid) is
  '0181/0182 — identifiants porteurs de données d''une entreprise : ses espaces + ses utilisateurs (jamais le patron, jamais un utilisateur qui est aussi un espace).';

grant execute on function public.perimetre_entreprise(uuid) to authenticated;


-- ============================================================================
--  VERDICT — contrôle INDÉPENDANT de la session
-- ============================================================================
--  Aucun identifiant d'espace ne doit apparaître dans le périmètre d'une
--  AUTRE entreprise. (L'ancien contrôle « périmètres qui se croisent »
--  comparait deux périmètres calculés dans la même session : le patron
--  n'était présent que dans celui de l'entreprise active → 0 trompeur.)
select 'Correctif 0182 — identifiants d''espace vus depuis une AUTRE entreprise : ' ||
       coalesce((
         select count(*)::text
           from public.espaces s
           join public.entreprises e on e.id <> s.entreprise_id
          where s.id::text = any (public.perimetre_entreprise(e.id))
       ), '0') ||
       ' (0 attendu) | périmètre Urembo/HEKIMA désormais distincts' as verdict;
