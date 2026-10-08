-- ============================================================================
--  BIASHARA YANGU — DIAGNOSTIC DE L'ATTRIBUTION DE QUOTAS IA
--  Fichier : tools/diagnostic_attribution_quotas.sql
-- ============================================================================
--
--  À QUOI ÇA SERT
--  --------------
--  L'écran « Quotas IA » refuse d'attribuer des quotas, ou la liste des
--  membres est vide. Ce script photographié l'état réel pour savoir POURQUOI,
--  sans rien modifier (lecture seule).
--
--  ⚠️ Supabase n'affiche que le résultat de la DERNIÈRE instruction : tout est
--     donc réuni en UNE seule requête, sous forme de tableau (section / clé /
--     valeur) qu'il suffit de lire de haut en bas.
--
--  OÙ : Supabase → SQL Editor → coller → Run
-- ============================================================================

with moi as (
  select u.id,
         u.email,
         u.parent_id,
         u.entreprise_id,
         coalesce(u.parent_id, u.id)          as proprietaire,
         coalesce(u.new_role::text, u.role)   as role
    from public.utilisateurs u
   where lower(btrim(u.email)) = lower(btrim('biasharagroup@gmail.com'))
   limit 1
),
soc as (
  select m.id as uid,
         m.proprietaire,
         coalesce(
           m.entreprise_id,
           (select p.entreprise_id from public.utilisateurs p where p.id = m.parent_id)
         ) as eid
    from moi m
)
-- 1) Le compte lui-même ------------------------------------------------------
select '1. COMPTE'                                  as section,
       'id'                                         as cle,
       m.id::text                                   as valeur
  from moi m
union all
select '1. COMPTE', 'email', m.email from moi m
union all
select '1. COMPTE', 'parent_id', coalesce(m.parent_id::text, '(VIDE)') from moi m
union all
select '1. COMPTE', 'entreprise_id', coalesce(m.entreprise_id::text, '(VIDE)') from moi m
union all
select '1. COMPTE', 'mon_proprietaire() renverra', m.proprietaire::text from moi m
union all
select '1. COMPTE', 'role', m.role from moi m

-- 2) L'entreprise ------------------------------------------------------------
union all
select '2. ENTREPRISE', 'id', coalesce(s.eid::text, '(AUCUNE)') from soc s
union all
select '2. ENTREPRISE', 'nom', coalesce(e.nom, '(AUCUNE)')
  from soc s left join public.entreprises e on e.id = s.eid

-- 3) TOUTES les lignes de quotas liées à ce compte ---------------------------
--    C'est ici qu'on voit si l'entreprise a DEUX lignes « pool » : une avec
--    l'identifiant de l'ENTREPRISE, une avec celui de l'UTILISATEUR (le
--    module 13 a longtemps mélangé les deux — voir migration 17).
union all
select '3. LIGNES DE QUOTAS',
       case when q.utilisateur_id is null then 'POOL  entreprise_id=' || coalesce(q.entreprise_id::text, '?')
            else 'ALLOCATION du compte'
       end,
       'dispo=' || q.quotas_disponibles ||
       ' | utilises=' || q.quotas_utilises_total ||
       ' | achetes=' || q.quotas_achetes_total ||
       ' | maj=' || to_char(q.updated_at, 'DD/MM/YYYY HH24:MI')
  from soc s
  join public.agent_ia_quotas q
    on q.utilisateur_id = s.uid
    or q.entreprise_id = s.eid
    or q.entreprise_id = s.uid

-- 4) Les membres VUS par l'écran aujourd'hui (logique en place) -------------
union all
select '4. MEMBRES vus par l ecran',
       coalesce(nullif(btrim(u.nom), ''), u.email),
       'parent_id=' || coalesce(u.parent_id::text, '(vide)') ||
       ' | entreprise_id=' || coalesce(u.entreprise_id::text, '(vide)')
  from public.utilisateurs u
 where u.id <> (select id from moi)
   and (u.parent_id = (select proprietaire from moi)
        or u.entreprise_id = (select proprietaire from moi))

-- 5) Les membres que l'écran DEVRAIT voir (bonne logique) -------------------
union all
select '5. MEMBRES attendus',
       coalesce(nullif(btrim(u.nom), ''), u.email),
       'parent_id=' || coalesce(u.parent_id::text, '(vide)') ||
       ' | entreprise_id=' || coalesce(u.entreprise_id::text, '(vide)') ||
       ' | role=' || coalesce(u.new_role::text, u.role, '?')
  from public.utilisateurs u
 where u.id <> (select id from moi)
   and (u.parent_id = (select id from moi)
        or u.entreprise_id = (select eid from soc))

-- 6) Rappel du bug de droit (informatif) ------------------------------------
union all
select '6. RAPPEL',
       'Condition actuelle de rpc_agent_ia_attribuer',
       'if est_plateforme() OR mon_role() <> PROPRIETAIRE then REFUSER '
       || '-> le Super Admin est TOUJOURS refuse (condition inversee)'
order by 1, 2;

-- ============================================================================
--  LECTURE DU RÉSULTAT
-- ----------------------------------------------------------------------------
--  • Section 3 : s'il y a DEUX lignes « POOL » avec des entreprise_id
--    différents, c'est la cause du désordre — le moteur d'attribution cherche
--    le pool avec l'identifiant de l'UTILISATEUR, alors que la ligne créée
--    porte celui de l'ENTREPRISE. Il ne la trouve pas → « pool insuffisant ».
--
--  • Section 4 vide alors que la section 5 est remplie : la liste des membres
--    est construite en comparant `entreprise_id` (identifiant d'ENTREPRISE) à
--    un identifiant d'UTILISATEUR — aucune ligne ne peut correspondre.
--
--  • Section 4 ET 5 vides : l'entreprise n'a réellement qu'un seul compte.
--    Il n'y a alors personne à qui attribuer — c'est normal.
-- ============================================================================
