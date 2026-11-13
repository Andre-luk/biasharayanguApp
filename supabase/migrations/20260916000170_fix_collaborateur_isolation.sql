-- ============================================================================
--  biashara_yangu — MIGRATION 0170 : UN COLLABORATEUR NE VOIT QUE SON ENTREPRISE
--
--  CONSTAT LIVE (13/11/2026, compte harold@gmail.com — VENDEUR de HEKIMA)
--    • Isolation des DONNÉES : correcte (0 produit Urembo visible, écriture
--      refusée, bascule vers Urembo refusée `DROIT_REFUSE`).
--    • MAIS `rpc_espaces_lister` lui renvoyait les DEUX entreprises
--      (Urembo Market + HEKIMA PHARMA) : le nom et l'activité de l'autre
--      affaire du patron étaient exposés dans son sélecteur.
--    • Risque latent : un collaborateur SANS `espace_actif_id` retombait sur
--      `parent_id` = UUID du patron = espace par DÉFAUT (Urembo), donc dans
--      la mauvaise entreprise.
--
--  CORRECTIF
--    1. `rpc_espaces_lister()` : un collaborateur ne reçoit QUE les boutiques
--       de son entreprise (`utilisateurs.entreprise_id`).
--    2. `mon_proprietaire()` : pour un collaborateur sans espace actif, le
--       repli devient la première boutique active de SON entreprise (et non
--       plus l'UUID du patron). Le comportement du patron est inchangé.
--
--  ⚠️ Aucune donnée modifiée. Idempotent.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);

-- ---------------------------------------------------------------------------
-- 1. PORTÉE DES DONNÉES : repli sûr pour un collaborateur
-- ---------------------------------------------------------------------------
create or replace function public.mon_proprietaire()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    -- 1. L'espace de travail choisi, s'il est encore valable.
    (select u.espace_actif_id
       from public.utilisateurs u
      where u.id = auth.uid()
        and u.espace_actif_id is not null
        and exists (
          select 1
            from public.espaces s
           where s.id = u.espace_actif_id
             and s.actif
             and (
               s.entreprise_id = u.entreprise_id
               or (u.parent_id is null
                   and exists (
                     select 1 from public.entreprises e
                      where e.id = s.entreprise_id
                        and e.owner_id = u.id))
             )
        )),
    -- 2. Repli :
    --    • PATRON      → son UUID (espace par défaut, compatibilité) ;
    --    • COLLABORATEUR → première boutique active de SON entreprise ;
    --    • à défaut    → parent, puis identité.
    (select coalesce(
       case when u.parent_id is null then u.id end,
       (select s.id
          from public.espaces s
         where s.entreprise_id = u.entreprise_id
           and s.actif
         order by s.created_at nulls last, s.nom
         limit 1),
       u.parent_id,
       u.id)
       from public.utilisateurs u
      where u.id = auth.uid())
  );
$$;

comment on function public.mon_proprietaire() is
  'Module 15/0157/0170 — PORTÉE DES DONNÉES : espace actif ; repli collaborateur = une boutique de SON entreprise (jamais l''espace par défaut du patron).';

revoke all on function public.mon_proprietaire() from public, anon;
grant execute on function public.mon_proprietaire() to authenticated;


-- ---------------------------------------------------------------------------
-- 2. SÉLECTEUR : un collaborateur ne voit QUE son entreprise
-- ---------------------------------------------------------------------------
create or replace function public.rpc_espaces_lister()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_user      uuid := auth.uid();
  v_patron    uuid;
  v_role      text := public.mon_role();
  v_max       integer := 1;
  v_nb_ent    integer := 0;
  v_actif     uuid;
  v_liste     jsonb := '[]'::jsonb;
  v_ent_collab uuid;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour voir vos entreprises.';
  end if;

  v_patron := public.mon_patron();
  if v_patron is null then
    return jsonb_build_object(
      'espaces', '[]'::jsonb, 'actif_id', null, 'max_espaces', 1,
      'role', v_role, 'peut_creer', false, 'raison', 'aucune_entreprise');
  end if;

  -- Un collaborateur (parent_id renseigné) est borné à SON entreprise.
  select u.entreprise_id into v_ent_collab
    from public.utilisateurs u
   where u.id = v_user
     and u.parent_id is not null;

  -- Quota : nombre d'ENTREPRISES autorisées par le pack.
  select greatest(coalesce(max(g.max_espaces), 1), 1) into v_max
    from public.entreprises e
    left join public.groupes_tarifaires g on g.id = e.groupe_tarifaire_id
   where e.owner_id = v_patron;

  select count(*) into v_nb_ent
    from public.entreprises e
   where e.owner_id = v_patron;

  -- Boutiques : toutes celles du patron, ou celles de l'entreprise du
  -- collaborateur (jamais celles d'une autre affaire du patron).
  select coalesce(jsonb_agg(jsonb_build_object(
           'id',            s.id,
           'nom',           s.nom,
           'type',          s.type,
           'actif',         s.actif,
           'est_actif',     s.id = u_actif.espace_actif_id,
           'entreprise_id',   e.id,
           'entreprise_nom',  e.nom,
           'etat_abonnement', e.statut::text,
           'date_expiration', e.date_expiration,
           'created_at',    s.created_at
         ) order by e.created_at nulls first, s.created_at, s.nom), '[]'::jsonb)
    into v_liste
    from public.entreprises e
    join public.espaces s on s.entreprise_id = e.id
    cross join (select u2.espace_actif_id from public.utilisateurs u2
                 where u2.id = v_user) u_actif
   where e.owner_id = v_patron
     and (v_ent_collab is null or e.id = v_ent_collab);

  -- Espace actif effectif.
  select u.espace_actif_id into v_actif
    from public.utilisateurs u
   where u.id = v_user
     and u.espace_actif_id is not null
     and exists (select 1 from public.espaces s
                  where s.id = u.espace_actif_id and s.actif);

  if v_actif is null then
    v_actif := public.mon_proprietaire();
  end if;

  return jsonb_build_object(
    'espaces',     v_liste,
    'actif_id',    v_actif,
    'max_espaces', v_max,
    'nb_entreprises', v_nb_ent,
    'role',        v_role,
    'peut_creer',  (v_role = 'PROPRIETAIRE' and v_nb_ent < v_max),
    'raison',      case
                     when v_role <> 'PROPRIETAIRE' then 'role'
                     when v_nb_ent >= v_max then 'quota'
                     else null
                   end
  );
end;
$$;

comment on function public.rpc_espaces_lister() is
  'Route B (0146/0170) — boutiques du patron ; pour un COLLABORATEUR, uniquement celles de son entreprise.';

revoke all on function public.rpc_espaces_lister() from public, anon;
grant execute on function public.rpc_espaces_lister() to authenticated;

-- Verdict (une seule ligne).
select 'Correctif 0170 — sélecteur collaborateur borné à son entreprise ; repli mon_proprietaire sûr : installé.' as verdict;
