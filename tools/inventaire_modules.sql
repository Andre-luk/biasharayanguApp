-- ============================================================================
--  biashara_yangu — INVENTAIRE : CE QUE LA BASE CONTIENT VRAIMENT
--
--  À exécuter quand un script échoue sur « relation ... does not exist » :
--  il dit, en UNE ligne, quels objets des migrations récentes existent ou non.
--
--  Aucune écriture. Aucune supposition.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);

select jsonb_pretty(
  jsonb_build_object(
    -- Tables
    'table_entreprises',            to_regclass('public.entreprises') is not null,
    'table_espaces',                to_regclass('public.espaces') is not null,
    'table_produits',               to_regclass('public.produits') is not null,
    'table_types_espaces_modules',  to_regclass('public.types_espaces_modules') is not null,

    -- Colonnes clés du multi-entreprises
    'col_entreprises_owner_id',     exists (
      select 1 from information_schema.columns
       where table_schema = 'public' and table_name = 'entreprises'
         and column_name = 'owner_id'),
    'col_entreprises_type_activite', exists (
      select 1 from information_schema.columns
       where table_schema = 'public' and table_name = 'entreprises'
         and column_name = 'type_activite'),
    'col_utilisateurs_espace_actif_id', exists (
      select 1 from information_schema.columns
       where table_schema = 'public' and table_name = 'utilisateurs'
         and column_name = 'espace_actif_id'),
    'col_produits_date_expiration', exists (
      select 1 from information_schema.columns
       where table_schema = 'public' and table_name = 'produits'
         and column_name = 'date_expiration'),

    -- Fonctions indispensables
    'fn_mon_proprietaire',          to_regprocedure('public.mon_proprietaire()') is not null,
    'fn_mon_patron',                to_regprocedure('public.mon_patron()') is not null,
    'fn_rpc_espaces_lister',        to_regprocedure('public.rpc_espaces_lister()') is not null,
    'fn_rpc_espace_basculer',       to_regprocedure('public.rpc_espace_basculer(uuid)') is not null,
    'fn_rpc_mes_modules',           to_regprocedure('public.rpc_mes_modules()') is not null,
    'fn_rpc_collaborateur_creer',   to_regprocedure(
                                      'public.rpc_collaborateur_creer(text, text, text, text, text, text, uuid)') is not null,

    -- Ce que l'application recevra comme profil de modules
    'metier_par_entreprise',        (
      select coalesce(jsonb_agg(jsonb_build_object(
               'entreprise', e.nom,
               'type_activite', e.type_activite) order by e.created_at), '[]'::jsonb)
        from public.entreprises e),

    'conclusion', case
      when to_regprocedure('public.mon_proprietaire()') is null
        then '⚠️ base incomplète : exécuter les migrations dans l''ordre'
      else '✅ socle présent — voir tools/verifier_pharmacie_josephissa.sql'
    end
  )
) as inventaire;
