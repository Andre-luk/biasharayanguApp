-- ============================================================================
--  biashara_yangu — MIGRATION 0164 : CORRECTIF `rpc_lots_ecarts`
--
--  POURQUOI
--    `produits.quantite` est un REAL. Dans `rpc_lots_ecarts`, la soustraction
--    « stock fiche − stock lots » était donc calculée en DOUBLE PRÉCISION,
--    et PostgreSQL n'a pas de `round(double precision, integer)` :
--
--      ERROR: function round(double precision, integer) does not exist
--
--    Constaté en direct le 13/11/2026 (compte josephissa@gmail.com) :
--    l'écran de diagnostic des lots répondait une erreur 400.
--
--  CORRECTIF
--    Cast explicite en NUMERIC AVANT l'arrondi (et avant la comparaison).
--    Aucune table, aucune donnée, aucun droit modifié.
--
--  À exécuter après 20260916000163. Idempotent (create or replace).
-- ============================================================================

select set_config('search_path', 'public, extensions', true);

create or replace function public.rpc_lots_ecarts()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_user  uuid := auth.uid();
  v_owner uuid;
  v_lignes jsonb;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour contrôler les lots.';
  end if;

  if not (public.peut('stock', 'voir') or public.est_plateforme()) then
    raise exception 'DROIT_REFUSE|Vous n''avez pas le droit de consulter le stock.';
  end if;

  v_owner := coalesce(public.mon_proprietaire(), v_user);

  select coalesce(jsonb_agg(ordre), '[]'::jsonb)
    into v_lignes
    from (
      select jsonb_build_object(
               'produit_id', p.id,
               'produit', p.nom,
               'stock_fiche', coalesce(p.quantite, 0),
               'stock_lots', coalesce(s.total, 0),
               'ecart', round(
                 (coalesce(p.quantite, 0) - coalesce(s.total, 0))::numeric,
                 3)
             ) as ordre
        from public.produits p
        left join (
          select l.produit_id, sum(l.quantite_restante) as total
            from public.produits_lots l
           where l.retire_le is null
           group by l.produit_id
        ) s on s.produit_id = p.id
       where p.owner_id = v_owner
         and s.produit_id is not null
         and abs((coalesce(p.quantite, 0) - coalesce(s.total, 0))::numeric)
             > 0.0005
       order by p.nom asc
    ) s;

  return jsonb_build_object('ok', true, 'ecarts', v_lignes);
end;
$$;

comment on function public.rpc_lots_ecarts() is
  'Module 36 (0163/0164) — diagnostic : articles dont le stock de la fiche diffère de la somme des lots.';

revoke all on function public.rpc_lots_ecarts() from public, anon;
grant execute on function public.rpc_lots_ecarts() to authenticated;

-- Verdict (l'éditeur SQL n'affiche que le dernier résultat)
select 'Correctif 0164 — rpc_lots_ecarts : ' ||
       case
         when exists (
           select 1
             from pg_proc p
             join pg_namespace n on n.oid = p.pronamespace
            where p.proname = 'rpc_lots_ecarts'
              and n.nspname = 'public'
         )
         then 'OK (remplacée)'
         else 'ABSENTE — relisez l''erreur ci-dessus'
       end as verdict;
