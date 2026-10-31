-- ============================================================================
--  biashara_yangu — CONTRÔLE D'INSTALLATION DES MIGRATIONS 0083 → 0093
--  ---------------------------------------------------------------------------
--  À COPIER-COLLER TEL QUEL dans le SQL Editor de Supabase, puis « Run ».
--
--  Le résultat affiche une ligne par objet attendu :
--      OK        → l'objet existe, la fonctionnalité est active
--      MANQUANT  → la migration correspondante n'a pas été exécutée
--
--  Lecture seule : ce script ne modifie AUCUNE donnée.
-- ============================================================================

with attendus as (
  -- ---- fonctions RPC -----------------------------------------------------
  select 'rpc_entreprise_type_activite'      as objet, 'fonction' as type, '0083' as migration union all
  select 'rpc_entreprise_definir_type_activite', 'fonction', '0083' union all
  select 'rpc_forfaits_lister',                  'fonction', '0083' union all
  select 'rpc_tournee_parametrer',               'fonction', '0085' union all
  select 'rpc_tournee_declarer_ecart',           'fonction', '0085' union all
  select 'rpc_radar_tournee',                    'fonction', '0086' union all
  select 'rpc_radar_agent',                      'fonction', '0086' union all
  select 'rpc_forfaits_entreprise',              'fonction', '0087' union all
  select 'rpc_abonnement_installation_etat',     'fonction', '0087' union all
  select 'rpc_abonnement_definir_quotas_ia',     'fonction', '0088' union all
  select 'rpc_abonnement_prix_du_cycle',         'fonction', '0090' union all
  select 'rpc_abonnement_preparer_renouvellement','fonction','0090' union all
  select 'rpc_abonnement_type_cycle',            'fonction', '0090' union all
  select 'rpc_serdipay_ouvrir',                  'fonction', '0092' union all
  select 'rpc_entreprise_supprimer',             'fonction', '0088' union all
  select 'rpc_rapport_tournee_detail',           'fonction', '0089' union all
  select 'rpc_bareme_abonnement',                'fonction', '0091' union all
  select 'rpc_entreprise_creer_simple',          'fonction', '0091' union all
  select 'rpc_abonnement_simulation_avance',     'fonction', '0091' union all
  select 'agent_de_entreprise',                  'fonction', '0092' union all
  -- ---- tables ------------------------------------------------------------
  select 'bareme_abonnement',                    'table',    '0091'
),
verif_fonctions as (
  select a.objet, a.type, a.migration,
         exists (
           select 1 from pg_proc p
             join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.proname = a.objet
         ) as present
    from attendus a
   where a.type = 'fonction'
),
verif_tables as (
  select a.objet, a.type, a.migration,
         exists (
           select 1 from information_schema.tables t
            where t.table_schema = 'public' and t.table_name = a.objet
         ) as present
    from attendus a
   where a.type = 'table'
),
tout as (
  select * from verif_fonctions
  union all
  select * from verif_tables
)
select
  migration,
  type,
  objet,
  case when present then 'OK' else 'MANQUANT' end as etat
from tout
order by (case when present then 1 else 0 end), migration, objet;

-- ============================================================================
--  CONTRÔLES DE DONNÉES (à lancer séparément, un bloc à la fois)
-- ============================================================================
--
--  1) Le barème est-il en place ?
--     select * from public.bareme_abonnement order by prix_installation;
--     → 3 lignes attendues : 10 000 / 30 000 / 50 000.
--
--  2) Reste-t-il des comptes sans prix (donc incapables de payer) ?
--     select id, nom, type_activite, activation_etape, statut,
--            prix_installation, prix_abonnement_mensuel
--       from public.entreprises
--      where coalesce(prix_abonnement_mensuel, 0) <= 0;
--     → doit être vide.
--
--  3) Reste-t-il des dossiers en attente de validation administrative ?
--     select count(*) from public.entreprises
--      where activation_etape = 'en_attente_verification';
--     → doit valoir 0 après la migration 0093.
--
--  4) Les entreprises de distribution ont-elles leur type ?
--     select nom, type_activite, prix_installation, prix_abonnement_mensuel
--       from public.entreprises
--      where lower(coalesce(type_activite, '')) = 'distribution';
--     → 50 000 / 20 000 attendus.
--
--  5) Les agents ont-ils bien leurs dossiers rattachés ?
--     select count(*) filter (where agent_id is not null) as avec_agent,
--            count(*)                                    as total
--       from public.entreprises;
--     → `avec_agent` = nombre de dossiers qu'un agent peut encaisser.
-- ============================================================================
