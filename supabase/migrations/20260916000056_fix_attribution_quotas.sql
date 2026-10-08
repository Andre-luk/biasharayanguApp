-- ============================================================================
--  biashara_yangu — CORRECTIF 56 : ATTRIBUTION DE QUOTAS IA
--  Migration 20260916000056_fix_attribution_quotas.sql
-- ============================================================================
--
--  ⛔ AUCUNE COMPILATION, AUCUNE PUBLICATION : correction de base uniquement.
--
--  CE QUE LE DIAGNOSTIC A RÉVÉLÉ (08/10/2026, Biashara Group)
--  ----------------------------------------------------------
--    • le compte est PROPRIÉTAIRE de l'entreprise 111833d4… (donc l'écran
--      d'attribution EST bien affiché) ;
--    • il existe DEUX lignes « pool » pour la MÊME entreprise :
--         - entreprise_id = 111833d4… (l'ENTREPRISE) : 20 quotas
--         - entreprise_id = 1398f76d… (l'UTILISATEUR) :  5 quotas
--      La seconde vient du bonus de bienvenue, créé par `rpc_agent_ia_etat`
--      (migration 17) qui utilise `mon_proprietaire()` — un identifiant
--      d'UTILISATEUR — comme clé d'entreprise ;
--    • l'attribution ne voit que la ligne à 5 quotas, pas celle à 20 ;
--    • la liste des membres est vide… parce que l'entreprise n'a QU'UN SEUL
--      compte. Ce point n'était pas un bug.
--
--  LES TROIS DÉFAUTS CORRIGÉS ICI
--  ------------------------------
--  1. DROIT INVERSÉ — `rpc_agent_ia_attribuer` refuse sur :
--         if est_plateforme() or mon_role() <> 'PROPRIETAIRE' then REFUSER
--     ⇒ le personnel de la plateforme est refusé PAR CONSTRUCTION.
--     Corrigé en `not (est_plateforme() or mon_role() = 'PROPRIETAIRE')`.
--
--  2. CLÉ DE POOL ERRONÉE — les deux fonctions cherchent le pool avec
--     `entreprise_id = mon_proprietaire()`, c'est-à-dire un identifiant
--     d'UTILISATEUR comparé à une colonne qui contient un identifiant
--     d'ENTREPRISE. Elles ne tombent donc jamais sur la bonne ligne.
--     Corrigé avec `mon_entreprise_id()` (migration 50), qui renvoie la VRAIE
--     entreprise du compte.
--
--  3. LIGNES DE POOL EN DOUBLE — fusionnées sur la ligne de l'entreprise, en
--     ADDITIONNANT les soldes (aucun quota perdu) et en conservant le plus
--     grand `quotas_achetes_total`.
--
--  ⚠️ CE QUE CETTE MIGRATION NE FAIT PAS
--     L'écran n'affiche la section « Attribuer » que si le compte est
--     propriétaire : un Super Admin ne verra donc toujours pas le bouton. Le
--     droit côté base est réparé (l'appel API fonctionne), mais rendre le
--     bouton visible au Super Admin demande une modification de l'application
--     Flutter — hors du périmètre « base de données uniquement ».
--
--  IDEMPOTENTE : relançable sans effet de bord.
--
--  ⚠️ À EXÉCUTER APRÈS la migration 55.
--  OÙ : Supabase → SQL Editor → coller → Run
-- ============================================================================


select set_config('search_path', 'public, extensions', true);


-- ============================================================================
--  0. CONTRÔLES PRÉALABLES
-- ============================================================================

do $$
begin
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                  where n.nspname = 'public' and p.proname = 'mon_entreprise_id') then
    raise exception 'fonction public.mon_entreprise_id() absente : exécutez d''abord 20260916000050_fix_rls_entreprises.sql.';
  end if;

  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                  where n.nspname = 'public' and p.proname = 'rpc_agent_ia_etat') then
    raise exception 'rpc_agent_ia_etat absente : exécutez d''abord le module 13 (migrations 14 à 17).';
  end if;
end $$;


-- ============================================================================
--  1. FUSION DES LIGNES DE POOL EN DOUBLE
-- ============================================================================
--  Une ligne « pool » dont `entreprise_id` correspond à un `utilisateurs.id`
--  est une ligne héritée du bug : elle doit être rattachée à la VRAIE
--  entreprise de cet utilisateur. On additionne les soldes — jamais de perte.
--
--  Le balayage est fait sur une LISTE figée avant modification : on ne
--  parcourt pas une table qu'on est en train de modifier.

do $fusion_pool$
declare
  v_liste jsonb;
  v_l     record;
  v_cible uuid;
  v_dest  uuid;
  v_n     integer := 0;
begin
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
    -- Vraie entreprise de l'utilisateur porté par erreur dans entreprise_id.
    select coalesce(u.entreprise_id, p.entreprise_id)
      into v_cible
      from public.utilisateurs u
      left join public.utilisateurs p on p.id = u.parent_id
     where u.id = v_l.eid;

    -- Sans entreprise identifiée, ou si la cible est elle-même la ligne
    -- fautive, on ne touche à rien : mieux vaut une ligne bizarre qu'une perte.
    if v_cible is null or v_cible = v_l.eid then
      raise notice 'Pool : ligne % non rattachable (entreprise introuvable) — conservee telle quelle.', v_l.eid;
      continue;
    end if;

    -- La ligne de l'entreprise existe-t-elle ?
    select q.id into v_dest
      from public.agent_ia_quotas q
     where q.utilisateur_id is null
       and q.entreprise_id = v_cible;

    if v_dest is null then
      -- Aucune ligne cible : on DÉPLACE simplement la ligne fautive en la
      -- réétiquetant (aucune addition, aucun risque de doublon).
      update public.agent_ia_quotas
         set entreprise_id = v_cible,
             updated_at    = now()
       where id = v_l.id;
      raise notice 'Pool : ligne rattachee a l entreprise % (% quotas).', v_cible, v_l.dispo;
    else
      -- Fusion : on additionne les soldes sur la ligne de l'entreprise, puis on
      -- supprime la ligne héritée.
      update public.agent_ia_quotas
         set quotas_disponibles   = quotas_disponibles + v_l.dispo,
             quotas_achetes_total = quotas_achetes_total + v_l.achetes,
             updated_at           = now()
       where id = v_dest;

      delete from public.agent_ia_quotas where id = v_l.id;

      raise notice 'Pool : fusion % quotas (utilisateur %) -> entreprise %.',
                   v_l.dispo, v_l.eid, v_cible;
    end if;

    v_n := v_n + 1;
  end loop;

  if v_n = 0 then
    raise notice 'Pool : aucune ligne en double detectee.';
  else
    raise notice 'Pool : % ligne(s) heritee(s) traitee(s).', v_n;
  end if;
end $fusion_pool$;


-- ============================================================================
--  2. `rpc_agent_ia_etat` — LE POOL DE LA VRAIE ENTREPRISE + MEMBRES COMPLETS
-- ============================================================================
--  Base : version de la migration 17 (la dernière en date). Deux changements :
--    • le pool est cherché avec l'identifiant de l'ENTREPRISE
--      (`mon_entreprise_id()`), plus jamais avec celui de l'utilisateur ;
--    • les membres sont listés par `parent_id` OU par `entreprise_id`, pour ne
--      plus ignorer les comptes rattachés uniquement à l'entreprise.

create or replace function public.rpc_agent_ia_etat()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user       uuid := auth.uid();
  v_plateforme boolean;
  v_soc        uuid;
  v_config     public.agent_ia_config%rowtype;
  v_pool       public.agent_ia_quotas%rowtype;
  v_moi        public.agent_ia_quotas%rowtype;
  v_collab     jsonb := '[]'::jsonb;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour consulter vos quotas.';
  end if;

  v_plateforme := public.est_plateforme();

  select * into v_config from public.agent_ia_config limit 1;
  if v_config.id is null then
    raise exception 'CONFIG_ABSENTE|Configuration IA absente : exécutez 20260916000014_module13_agent_ia.sql.';
  end if;

  -- S'assurer qu'une entreprise (abonnement) existe pour la boutique.
  -- Best-effort : si la création échoue, les quotas fonctionnent quand même.
  if not v_plateforme then
    begin
      perform public.rpc_entreprise_creer(null);
    exception when others then null;
    end;
  end if;

  -- ⚠️ CORRECTIF 56 : l'identifiant de l'ENTREPRISE, et non celui du compte.
  v_soc := public.mon_entreprise_id();
  if v_soc is null then
    -- Repli : entreprise indisponible (compte plateforme, dossier incomplet).
    -- On retombe sur l'identifiant du compte pour ne rien casser — c'est
    -- exactement ce que faisait la version précédente.
    v_soc := v_user;
  end if;

  -- POOL de l'entreprise + bonus de bienvenue (une seule fois).
  if not v_plateforme then
    select * into v_pool
      from public.agent_ia_quotas
     where utilisateur_id is null
       and entreprise_id = v_soc;

    if v_pool.id is null then
      insert into public.agent_ia_quotas (
        utilisateur_id, entreprise_id, quotas_disponibles, quotas_achetes_total
      ) values (
        null, v_soc, greatest(coalesce(v_config.quotas_offerts_inscription, 0), 0), 0
      )
      on conflict do nothing;

      select * into v_pool
        from public.agent_ia_quotas
       where utilisateur_id is null
         and entreprise_id = v_soc;
    end if;
  end if;

  -- Mon allocation personnelle.
  select * into v_moi
    from public.agent_ia_quotas
   where utilisateur_id = v_user;

  -- Collaborateurs de l'entreprise (pour l'attribution par le patron).
  -- ⚠️ CORRECTIF 56 : on accepte aussi les comptes rattachés à l'ENTREPRISE
  --    (`entreprise_id`), et pas seulement ceux rattachés au patron.
  --    Le garde-fou est volontairement large (`not v_plateforme`) : c'est
  --    l'application qui décide d'afficher ou non la section, et un libellé de
  --    rôle inattendu ne doit pas vider la liste.
  if not v_plateforme then
    select coalesce(jsonb_agg(jsonb_build_object(
             'id',   u.id,
             'nom',  coalesce(nullif(btrim(u.nom), ''), u.email),
             'role', coalesce(u.new_role::text, u.role, '')
           ) order by u.nom), '[]'::jsonb)
      into v_collab
      from public.utilisateurs u
     where u.id <> v_user
       and (u.parent_id = v_user or u.entreprise_id = v_soc);
  end if;

  return jsonb_build_object(
    'config', jsonb_build_object(
      'tarif_par_quota',           v_config.tarif_par_quota,
      'caracteres_par_quota',      v_config.caracteres_par_quota,
      'prix_pack_10_quotas',       v_config.prix_pack_10_quotas,
      'quotas_offerts_inscription', v_config.quotas_offerts_inscription,
      'actif',                     v_config.actif
    ),
    'pool', case when v_pool.id is null then null else jsonb_build_object(
      'quotas_disponibles',   v_pool.quotas_disponibles,
      'quotas_achetes_total', v_pool.quotas_achetes_total
    ) end,
    'moi', jsonb_build_object(
      'quotas_disponibles',    coalesce(v_moi.quotas_disponibles, 0),
      'quotas_utilises_total', coalesce(v_moi.quotas_utilises_total, 0),
      'quotas_achetes_total',  coalesce(v_moi.quotas_achetes_total, 0)
    ),
    'role',            public.mon_role(),
    'est_proprietaire', (not v_plateforme and public.mon_role() = 'PROPRIETAIRE'),
    'est_plateforme',  v_plateforme,
    'est_super_admin', public.est_super_admin(),
    'collaborateurs',  v_collab
  );
end;
$$;

comment on function public.rpc_agent_ia_etat() is
  'Module 13 — État IA : config, pool de l''ENTREPRISE (correctif 56 : mon_entreprise_id, plus mon_proprietaire), allocation, collaborateurs (parent_id ou entreprise_id).';

revoke all on function public.rpc_agent_ia_etat() from public, anon;
grant execute on function public.rpc_agent_ia_etat() to authenticated;


-- ============================================================================
--  3. `rpc_agent_ia_attribuer` — DROIT RÉPARÉ + POOL DE L'ENTREPRISE
-- ============================================================================
--  Base : migration 16. Trois changements :
--    • le droit n'est plus inversé (le personnel plateforme passe) ;
--    • le pool débité est celui de l'ENTREPRISE du destinataire ;
--    • le contrôle d'appartenance compare des identifiants comparables.

create or replace function public.rpc_agent_ia_attribuer(
  p_utilisateur uuid,
  p_quotas      integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user         uuid := auth.uid();
  v_plateforme   boolean;
  v_ma_soc       uuid;
  v_dest         public.utilisateurs;
  v_soc          uuid;
  v_pool_restant integer;
  v_solde_dest   integer;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour attribuer des quotas.';
  end if;

  v_plateforme := public.est_plateforme();

  -- ⚠️ CORRECTIF 56 — AVANT : `if est_plateforme() or mon_role() <> 'PROPRIETAIRE'
  --    then REFUSER`, ce qui refusait le personnel de la plateforme. La
  --    condition correcte est la NÉGATION de « plateforme OU propriétaire ».
  if not (v_plateforme or public.mon_role() = 'PROPRIETAIRE') then
    raise exception 'DROIT_REFUSE|Seuls le propriétaire de la boutique ou le personnel de la plateforme distribuent les quotas.';
  end if;

  if p_utilisateur is null or p_quotas is null or p_quotas < 1 or p_quotas > 10000 then
    raise exception 'PARAMETRES_INVALIDES|Choisissez un membre et un nombre de quotas valide (1 à 10 000).';
  end if;

  select * into v_dest from public.utilisateurs where id = p_utilisateur;
  if v_dest.id is null then
    raise exception 'UTILISATEUR_INCONNU|Ce collaborateur n''existe pas.';
  end if;

  -- Entreprise du DESTINATAIRE : c'est son pool qui sera débité.
  select coalesce(v_dest.entreprise_id, p.entreprise_id)
    into v_soc
    from public.utilisateurs p
   where p.id = v_dest.parent_id;

  -- Repli : l'entreprise du destinataire porte parfois l'identifiant d'un de
  -- ses membres (héritage du module 13) — on accepte les deux formes.
  if v_soc is null then
    v_soc := coalesce(v_dest.entreprise_id, v_dest.parent_id);
  end if;

  if v_soc is null then
    raise exception 'ENTREPRISE_INTROUVABLE|Impossible de determiner l''entreprise de ce collaborateur.';
  end if;

  -- Périmètre : hors plateforme, on ne distribue que dans SA propre entreprise.
  if not v_plateforme then
    v_ma_soc := public.mon_entreprise_id();
    if v_ma_soc is not null and v_soc <> v_ma_soc then
      raise exception 'HORS_BOUTIQUE|Ce collaborateur n''appartient pas a votre entreprise.';
    end if;
    -- Complément : le destinataire doit être rattaché à ma structure.
    if v_soc = v_ma_soc
       and v_dest.parent_id is distinct from v_user
       and v_dest.entreprise_id is distinct from v_soc
    then
      raise exception 'HORS_BOUTIQUE|Ce collaborateur n''appartient pas a votre entreprise.';
    end if;
  end if;

  -- Débit ATOMIQUE du pool de l'entreprise du destinataire.
  update public.agent_ia_quotas q
     set quotas_disponibles = q.quotas_disponibles - p_quotas,
         updated_at         = now()
   where q.utilisateur_id is null
     and q.entreprise_id = v_soc
     and q.quotas_disponibles >= p_quotas
  returning q.quotas_disponibles into v_pool_restant;

  if not found then
    raise exception 'POOL_INSUFFISANT|Le pool de l''entreprise ne contient pas assez de quotas : demandez ou achetez un pack.';
  end if;

  -- Crédit de l'allocation du membre (upsert).
  insert into public.agent_ia_quotas (
    utilisateur_id, entreprise_id, quotas_disponibles, attribue_par, attribue_le
  ) values (
    p_utilisateur, v_soc, p_quotas, v_user, now()
  )
  on conflict (utilisateur_id)
  do update set
    quotas_disponibles = public.agent_ia_quotas.quotas_disponibles + excluded.quotas_disponibles,
    attribue_par       = excluded.attribue_par,
    attribue_le        = excluded.attribue_le,
    updated_at         = now()
  returning quotas_disponibles into v_solde_dest;

  insert into public.journal_audit (id, entreprise_id, action, utilisateur_id, details, created_at)
  values (
    gen_random_uuid(), v_soc, 'AGENT_IA_ATTRIBUTION', v_user,
    jsonb_build_object(
      'destinataire',  p_utilisateur,
      'nombre_quotas', p_quotas,
      'pool_restant',  v_pool_restant,
      'solde_membre',  v_solde_dest,
      'boutique',      v_soc,
      'par_plateforme', v_plateforme,
      'correctif',     '56'
    ),
    now()
  );

  return jsonb_build_object(
    'ok',                 true,
    'pool_restant',       v_pool_restant,
    'solde_destinataire', v_solde_dest
  );
end;
$$;

comment on function public.rpc_agent_ia_attribuer(uuid, integer) is
  'Module 13 — Attribue des quotas du pool de l''ENTREPRISE à un membre (correctif 56 : droit réparé — le personnel plateforme passe — et pool identifié par mon_entreprise_id).';

revoke all on function public.rpc_agent_ia_attribuer(uuid, integer) from public, anon;
grant execute on function public.rpc_agent_ia_attribuer(uuid, integer) to authenticated;


-- ============================================================================
--  4. VÉRIFICATIONS — RUN SÉPARÉ
-- ============================================================================
--  4.a Plus aucune ligne de pool portant un identifiant d'utilisateur :
--
--      select q.entreprise_id,
--             case when exists (select 1 from public.utilisateurs u where u.id = q.entreprise_id)
--                  then '⛔ identifiant d UTILISATEUR' else '✅ identifiant d entreprise' end as nature,
--             q.quotas_disponibles
--        from public.agent_ia_quotas q
--       where q.utilisateur_id is null
--       order by 2, 1;
--
--  4.b L'état du compte, tel que l'écran le lira (pool + allocation) :
--
--      with cible as (
--        select coalesce(u.entreprise_id, p.entreprise_id) as eid, u.id as uid, u.email
--          from public.utilisateurs u
--          left join public.utilisateurs p on p.id = u.parent_id
--         where lower(btrim(u.email)) = lower(btrim('biasharagroup@gmail.com'))
--      )
--      select c.email, e.nom,
--             case when q.utilisateur_id is null then 'POOL entreprise' else 'ALLOCATION du compte' end as ligne,
--             coalesce(q.quotas_disponibles, 0) as dispo,
--             coalesce(q.quotas_utilises_total, 0) as utilises,
--             to_char(q.updated_at, 'DD/MM/YYYY HH24:MI') as maj
--        from cible c
--        left join public.entreprises e on e.id = c.eid
--        left join public.agent_ia_quotas q
--               on q.utilisateur_id = c.uid
--               or (q.utilisateur_id is null and q.entreprise_id = c.eid)
--       order by q.utilisateur_id nulls first;
--
--  4.c Le droit est réparé (les deux fonctions doivent accepter la plateforme) :
--
--      select p.proname,
--             position('not (v_plateforme' in pg_get_functiondef(p.oid)) > 0 as droit_corrige
--        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--       where n.nspname = 'public' and p.proname = 'rpc_agent_ia_attribuer';
--      Attendu : true
--
--  4.d Le pool est bien cherché par l'entreprise :
--
--      select position('mon_entreprise_id' in pg_get_functiondef(p.oid)) > 0 as utilise_mon_entreprise_id
--        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--       where n.nspname = 'public' and p.proname = 'rpc_agent_ia_etat';
--      Attendu : true
-- ============================================================================
--  FIN — correctif 56.
-- ============================================================================
