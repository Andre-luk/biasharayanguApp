-- ============================================================================
--  biashara_yangu — CONTRÔLE DES DONNÉES APRÈS MIGRATIONS 0091 → 0094
--  ---------------------------------------------------------------------------
--  À COPIER-COLLER TEL QUEL dans le SQL Editor de Supabase, puis « Run ».
--
--  Pourquoi ce second contrôle ?
--    `docs/verification_migrations.sql` prouve que les OBJETS existent
--    (fonctions, table). Mais les migrations 0093 et 0094 ne créent AUCUN
--    objet : elles corrigent des DONNÉES et un SCHÉMA. Elles sont donc
--    invisibles pour ce contrôle-là.
--
--  Ici, une seule requête renvoie une ligne par vérification :
--      OK          → rien à faire
--      À CORRIGER  → l'explication est dans la colonne `constat`
--
--  Lecture seule : ce script ne modifie AUCUNE donnée.
-- ============================================================================

with bases as (
  select
    (select count(*) from public.bareme_abonnement where actif) as nb_bareme,
    (select count(*) from public.entreprises
      where coalesce(prix_abonnement_mensuel, 0) <= 0)             as sans_prix,
    (select count(*) from public.entreprises
      where activation_etape = 'en_attente_verification')          as en_attente,
    (select count(*) from public.entreprises
      where lower(coalesce(type_activite, '')) = 'distribution')   as nb_distribution,
    (select count(*) from public.entreprises e
       join public.bareme_abonnement b on b.profil = 'distribution'
      where lower(coalesce(e.type_activite, '')) = 'distribution'
        and coalesce(e.prix_abonnement_mensuel, 0) <> b.prix_mensuel) as distribution_prix_faux,
    (select count(*) from information_schema.columns
      where table_schema = 'public' and table_name = 'entreprises'
        and is_generated = 'ALWAYS')                               as colonnes_generees,
    (select count(*) from pg_trigger
      where tgname = 'trg_abonnement_politique')                   as nb_trigger,
    (select count(*) from pg_proc p
       join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public'
        and p.proname = 'rpc_serdipay_ouvrir')                     as nb_serdipay,
    (select pronargs from pg_proc p
       join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public'
        and p.proname = 'rpc_serdipay_ouvrir'
      order by pronargs desc limit 1)                              as args_serdipay,
    (select count(*) filter (where agent_id is not null)
       from public.entreprises)                                    as dossiers_avec_agent,
    (select count(*) from public.entreprises)                      as nb_entreprises,
    -- Correctif 96 : type d'activité réellement renseigné partout ?
    (select count(*) from public.entreprises
      where type_activite is null or btrim(type_activite) = '')    as sans_type,
    (select count(*) from public.types_espaces_modules
      where type = 'distribution' and coalesce(actif, true))       as profil_distribution,
    (select count(*) from pg_trigger
      where tgname = 'trg_espace_aligne_type_activite')            as nb_trigger_type,
    -- Correctif 95 : les espaces « distribution » ont-ils le bon profil ?
    (select count(*) from public.espaces
      where lower(coalesce(type, '')) = 'distribution')            as espaces_distribution
),
controles as (
  select 1 as ordre, 'Barème présent (3 profils actifs)' as controle,
         case when nb_bareme >= 3 then 'OK' else 'À CORRIGER' end as etat,
         nb_bareme || ' profil(s) actif(s) — attendu : 3 '
           || '(10 000 / 30 000 / 50 000)' as constat,
         'Migration 0091' as migration
    from bases
  union all
  select 2, 'Aucun compte sans prix mensuel',
         case when sans_prix = 0 then 'OK' else 'À CORRIGER' end,
         sans_prix || ' entreprise(s) sans prix — elles ne peuvent pas payer',
         'Migration 0093'
    from bases
  union all
  select 3, 'Aucun dossier en attente de validation admin',
         case when en_attente = 0 then 'OK' else 'À CORRIGER' end,
         en_attente || ' dossier(s) bloqué(s) — attendu : 0',
         'Migration 0093'
    from bases
  union all
  select 4, 'Prix de distribution conformes au barème',
         case when distribution_prix_faux = 0 then 'OK' else 'À CORRIGER' end,
         nb_distribution || ' entreprise(s) de distribution, '
           || distribution_prix_faux || ' avec un prix différent du barème '
           || '(normal si négocié)',
         'Migrations 0091/0093'
    from bases
  union all
  select 5, 'Aucune colonne générée sur entreprises',
         case when colonnes_generees = 0 then 'OK' else 'À CORRIGER' end,
         colonnes_generees || ' colonne(s) générée(s) — si solde_restant en '
           || 'fait partie, les paiements échoueront (428C9) : lancer 0094',
         'Migration 0094'
    from bases
  union all
  select 6, 'Activation automatique installée (trigger)',
         case when nb_trigger > 0 then 'OK' else 'À CORRIGER' end,
         nb_trigger || ' déclencheur trg_abonnement_politique — attendu : 1',
         'Migration 0091'
    from bases
  union all
  select 7, 'Paiement pour une entreprise (v3, 6 paramètres)',
         case when coalesce(args_serdipay, 0) >= 6 then 'OK' else 'À CORRIGER' end,
         'rpc_serdipay_ouvrir a ' || coalesce(args_serdipay::text, '0')
           || ' paramètre(s) — attendu : 6 (dont p_montant)',
         'Migration 0092'
    from bases
  union all
  select 8, 'Dossiers rattachés à un agent (information)',
         'OK',
         dossiers_avec_agent || ' dossier(s) sur ' || nb_entreprises
           || ' peuvent être encaissés par un agent',
         'Migration 0092'
    from bases
  union all
  select 9, 'Profil de modules « distribution » proposé',
         case when profil_distribution > 0 then 'OK' else 'À CORRIGER' end,
         profil_distribution || ' profil(s) actif(s) — attendu : 1 '
           || '(sinon Distribution n''apparaît pas à la création)',
         'Migration 0096'
    from bases
  union all
  select 10, 'Chaque entreprise a un type d''activité',
         case when sans_type = 0 then 'OK' else 'À CORRIGER' end,
         sans_type || ' entreprise(s) sans type — elles affichent TOUS les '
           || 'écrans, y compris ceux de distribution',
         'Migration 0096'
    from bases
  union all
  select 11, 'Type déduit automatiquement à la création',
         case when nb_trigger_type > 0 then 'OK' else 'À CORRIGER' end,
         nb_trigger_type || ' déclencheur(s) trg_espace_aligne_type_activite '
           || '— attendu : 1',
         'Migration 0096'
    from bases
  union all
  select 12, 'Espaces en profil distribution (information)',
         'OK',
         espaces_distribution || ' espace(s) sur ' || nb_entreprises
           || ' utilisent le profil distribution',
         'Migration 0096'
    from bases
)
select ordre, migration, controle, etat, constat
  from controles
 order by (case when etat = 'OK' then 1 else 0 end), ordre;

-- ============================================================================
--  LECTURE DU RÉSULTAT
--  ---------------------------------------------------------------------------
--  • Toutes les lignes « OK »            → la base est prête.
--  • Une ligne « À CORRIGER » sur 0093   → relancer 0093 (rattrapage).
--  • Une ligne « À CORRIGER » sur 0094   → relancer 0094 (colonne générée).
--  • Ligne 4 « prix différent du barème » → souvent NORMAL : un prix négocié
--    est prioritaire sur le barème. À vérifier entreprise par entreprise avec :
--
--      select nom, type_activite, prix_installation, prix_abonnement_mensuel
--        from public.entreprises
--       where lower(coalesce(type_activite, '')) = 'distribution';
-- ============================================================================
