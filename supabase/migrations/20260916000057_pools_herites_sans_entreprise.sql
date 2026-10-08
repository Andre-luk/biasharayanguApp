-- ============================================================================
--  biashara_yangu — CORRECTIF 57 : POOLS HÉRITÉS SANS ENTREPRISE
--  Migration 20260916000057_pools_herites_sans_entreprise.sql
-- ============================================================================
--
--  ⛔ AUCUNE COMPILATION, AUCUNE PUBLICATION : correction de base uniquement.
--
--  D'OÙ VIENT CE FICHIER
--  --------------------
--  Après le correctif 56, la vérification montre :
--     • ✅  Biashara Group : une seule ligne pool, 25 quotas, clé = l'ENTREPRISE
--           (la fusion 20 + 5 a fonctionné) ;
--     • ⛔  QUATRE lignes pool restantes, chacune avec 5 quotas, dont la clé
--           `entreprise_id` est un identifiant d'UTILISATEUR.
--
--  POURQUOI LE 56 NE LES A PAS TRAITÉES
--  ------------------------------------
--  Le correctif 56 ne rattache une ligne héritée que s'il peut déterminer
--  l'ENTREPRISE de l'utilisateur concerné (`utilisateurs.entreprise_id`, ou
--  celle de son patron). Ces quatre comptes n'ont AUCUNE entreprise : le
--  correctif les a donc laissées intactes plutôt que de deviner — le bon choix
--  par défaut, mais ça laisse des quotas inutilisables.
--
--  POURQUOI CES QUOTAS SONT INUTILISABLES
--  --------------------------------------
--  Ce sont les « 5 quotas offerts » du bonus de bienvenue, créés par
--  `rpc_agent_ia_etat` avec pour clé l'identifiant du COMPTE (bug d'origine,
--  corrigé en 56 pour les nouveaux comptes). Or :
--     • l'assistant débite l'ALLOCATION du membre (`utilisateur_id`), jamais
--       le pool ;
--     • ces comptes n'ont aucun collaborateur à qui attribuer.
--  Ces 5 quotas ne peuvent donc jamais être consommés : ils dorment.
--
--  CE QUE FAIT CETTE MIGRATION
--  ---------------------------
--  Pour chaque ligne pool dont la clé est un identifiant d'utilisateur :
--     • si l'entreprise est déterminable  → FUSION dans le pool de l'entreprise
--       (addition des soldes, puis suppression de la ligne héritée) — c'est la
--       même règle que le correctif 56, au cas où de nouvelles lignes
--       apparaîtraient ;
--     • si l'entreprise est INTROUVABLE   → les quotas sont DÉPLACÉS vers
--       l'ALLOCATION de ce compte, seul endroit où ils peuvent servir, puis la
--       ligne héritée est supprimée.
--  Dans les deux cas : AUCUN quota n'est perdu (ils sont additionnés).
--
--  GARDE-FOUS
--  ----------
--    • jamais d'écriture sur les allocations existantes sans addition ;
--    • une ligne dont la clé n'est ni une entreprise ni un utilisateur connus
--      est LAISSÉE INTACTE et signalée ;
--    • le balayage travaille sur une liste figée avant modification.
--  IDEMPOTENTE : relançable sans effet de bord.
--
--  ⚠️ À EXÉCUTER APRÈS le correctif 56.
--  OÙ : Supabase → SQL Editor → coller → Run
-- ============================================================================


select set_config('search_path', 'public, extensions', true);


do $pools_herites$
declare
  v_liste   jsonb;
  v_l       record;
  v_cible   uuid;
  v_dest    uuid;
  v_n_fusion integer := 0;
  v_n_deplace integer := 0;
  v_n_ignore integer := 0;
begin
  -- Liste FIGÉE des lignes pool dont la clé est un identifiant d'utilisateur.
  select coalesce(jsonb_agg(jsonb_build_object(
           'id',      q.id,
           'eid',     q.entreprise_id,
           'dispo',   q.quotas_disponibles,
           'achetes', q.quotas_achetes_total
         )), '[]'::jsonb)
    into v_liste
    from public.agent_ia_quotas q
   where q.utilisateur_id is null
     and exists (select 1 from public.utilisateurs u where u.id = q.entreprise_id);

  for v_l in
    select * from jsonb_to_recordset(v_liste)
      as x(id uuid, eid uuid, dispo integer, achetes integer)
  loop
    -- ── 1. L'entreprise de ce compte est-elle déterminable ? ────────────────
    select coalesce(u.entreprise_id, p.entreprise_id)
      into v_cible
      from public.utilisateurs u
      left join public.utilisateurs p on p.id = u.parent_id
     where u.id = v_l.eid;

    if v_cible is not null and v_cible <> v_l.eid then
      -- ── CAS A : une entreprise existe → on fusionne dans son pool ─────────
      select q.id into v_dest
        from public.agent_ia_quotas q
       where q.utilisateur_id is null
         and q.entreprise_id = v_cible;

      if v_dest is null then
        update public.agent_ia_quotas
           set entreprise_id = v_cible,
               updated_at    = now()
         where id = v_l.id;
        raise notice 'Pool : ligne % rattachee a l entreprise % (% quotas).',
                     left(v_l.eid::text, 8), left(v_cible::text, 8), v_l.dispo;
      else
        update public.agent_ia_quotas
           set quotas_disponibles   = quotas_disponibles + v_l.dispo,
               quotas_achetes_total = quotas_achetes_total + v_l.achetes,
               updated_at           = now()
         where id = v_dest;
        delete from public.agent_ia_quotas where id = v_l.id;
        raise notice 'Pool : fusion % quotas (compte %) -> entreprise %.',
                     v_l.dispo, left(v_l.eid::text, 8), left(v_cible::text, 8);
      end if;

      v_n_fusion := v_n_fusion + 1;

    elsif exists (select 1 from public.utilisateurs u where u.id = v_l.eid) then
      -- ── CAS B : aucune entreprise → les quotas passent a l'ALLOCATION ─────
      --  C'est le seul endroit où ils peuvent servir : sans entreprise, il n'y
      --  a personne a qui les attribuer, et l'assistant ne lit que l'allocation.
      insert into public.agent_ia_quotas (
        utilisateur_id, entreprise_id, quotas_disponibles, attribue_par, attribue_le
      ) values (
        v_l.eid, v_l.eid, v_l.dispo, null, now()
      )
      on conflict (utilisateur_id)
      do update set
        quotas_disponibles = public.agent_ia_quotas.quotas_disponibles + excluded.quotas_disponibles,
        updated_at         = now();

      delete from public.agent_ia_quotas where id = v_l.id;

      raise notice 'Pool : % quota(s) du compte % (sans entreprise) deplaces vers SON allocation.',
                   v_l.dispo, left(v_l.eid::text, 8);
      v_n_deplace := v_n_deplace + 1;

    else
      raise notice 'Pool : ligne % non identifiable — CONSERVEE telle quelle.', left(v_l.eid::text, 8);
      v_n_ignore := v_n_ignore + 1;
    end if;
  end loop;

  raise notice 'Pools herites : % fusionne(s), % deplace(s) vers une allocation, % conserve(s).',
               v_n_fusion, v_n_deplace, v_n_ignore;
end $pools_herites$;


-- ============================================================================
--  RAPPORT FINAL — l'état des réserves après correction
--  ⚠️ En DERNIER : le SQL Editor n'affiche que le résultat de la dernière
--     instruction du script.
-- ============================================================================

select case when q.utilisateur_id is null then 'POOL (reserve)' else 'ALLOCATION' end as type,
       left(q.entreprise_id::text, 8) as cle_entreprise,
       case
         when q.utilisateur_id is not null then 'compte ' || left(q.utilisateur_id::text, 8)
         when exists (select 1 from public.utilisateurs u where u.id = q.entreprise_id)
           then '⛔ cle = un COMPTE (a surveiller)'
         else coalesce((select left(e.nom, 28) from public.entreprises e where e.id = q.entreprise_id),
                       '⚠️ entreprise inconnue')
       end as qui,
       q.quotas_disponibles as dispo,
       q.quotas_utilises_total as utilises,
       q.quotas_achetes_total as achetes
  from public.agent_ia_quotas q
 order by 1, 2;
