-- ============================================================================
--  biashara_yangu — PHASE 11 ter : RATTRAPAGE DES COMPTES DÉJÀ EXISTANTS
--  ---------------------------------------------------------------------------
--  Les migrations 0091/0092 n'agissent que sur les écritures SUIVANTES :
--  un trigger `BEFORE INSERT OR UPDATE` n'a aucun effet rétroactif.
--
--  Conséquence concrète après leur exécution :
--    • les entreprises créées AVANT 0091 gardent
--      `prix_installation` / `prix_abonnement_mensuel` à NULL → le moteur
--      ne peut pas calculer de cycle (« prix absent ») ;
--    • celles restées à `en_attente_verification` attendent toujours une
--      validation administrative qui n'existe plus.
--
--  Cette migration fait donc, UNE SEULE FOIS, ce que le trigger fera
--  désormais tout seul. Elle est IDEMPOTENTE : la relancer ne change rien.
--
--  ⚠️ Elle ne touche PAS :
--      • les prix déjà renseignés (négociation respectée) ;
--      • les comptes déjà `actif`, `restreint` ou `rejete` ;
--      • les abonnements en cours (aucune date d'expiration réécrite).
-- ============================================================================

select set_config('search_path', 'public, extensions', true);

do $$
declare
  v_prix  integer := 0;
  v_act   integer := 0;
  v_reste integer := 0;
begin
  -- ------------------------------------------------------------------------
  -- 1. PRIX PAR DÉFAUT (uniquement là où ils manquent)
  -- ------------------------------------------------------------------------
  if exists (
    select 1 from information_schema.tables
     where table_schema = 'public' and table_name = 'bareme_abonnement'
  ) then

    -- Boutiques (et types non renseignés) : 30 000 installation / 10 000 mois.
    update public.entreprises e
       set prix_installation = b.prix_installation,
           prix_abonnement_mensuel = b.prix_mensuel,
           updated_at = now()
      from public.bareme_abonnement b
     where b.profil = 'boutique_complete'
       and b.actif
       and lower(btrim(coalesce(e.type_activite, ''))) <> 'distribution'
       and e.prix_installation is null
       and e.prix_abonnement_mensuel is null;
    get diagnostics v_prix = row_count;

    -- Distribution : 50 000 / 20 000.
    update public.entreprises e
       set prix_installation = b.prix_installation,
           prix_abonnement_mensuel = b.prix_mensuel,
           updated_at = now()
      from public.bareme_abonnement b
     where b.profil = 'distribution'
       and b.actif
       and lower(btrim(coalesce(e.type_activite, ''))) = 'distribution'
       and e.prix_installation is null
       and e.prix_abonnement_mensuel is null;
    get diagnostics v_reste = row_count;
    v_prix := v_prix + v_reste;

    -- Prix partiellement renseignés : on complète le champ manquant.
    update public.entreprises e
       set prix_installation = b.prix_installation,
           prix_abonnement_mensuel = b.prix_mensuel,
           updated_at = now()
      from public.bareme_abonnement b
     where b.profil = case
                        when lower(btrim(coalesce(e.type_activite, ''))) = 'distribution'
                          then 'distribution'
                        else 'boutique_complete'
                      end
       and b.actif
       and e.prix_installation is null
       and e.prix_abonnement_mensuel is not null;
    get diagnostics v_reste = row_count;
    v_prix := v_prix + v_reste;
  end if;

  -- ------------------------------------------------------------------------
  -- 2. ACTIVATION DES DOSSIERS EN ATTENTE
  --    → actif en essai 7 jours, sans aucune validation administrative.
  -- ------------------------------------------------------------------------
  update public.entreprises
     set activation_etape  = 'actif',
         statut            = 'ESSAI_7J'::public.statut_abonnement_enum,
         date_activation   = coalesce(date_activation, now()),
         date_expiration   = coalesce(date_expiration, now() + interval '7 days'),
         montant_total_du  = coalesce(montant_total_du, 0),
         montant_deja_paye = coalesce(montant_deja_paye, 0),
         solde_restant     = coalesce(solde_restant, 0),
         updated_at        = now()
   where activation_etape = 'en_attente_verification';
  get diagnostics v_act = row_count;

  raise notice
    'Rattrapage terminé : % entreprise(s) avec prix par défaut, '
    '% dossier(s) activé(s) en essai 7 jours.', v_prix, v_act;
end $$;

-- ----------------------------------------------------------------------------
-- 3. CONTRÔLE — reste-t-il des comptes sans prix ?
-- ----------------------------------------------------------------------------
do $$
declare
  v_sans_prix integer;
begin
  select count(*) into v_sans_prix
    from public.entreprises
   where coalesce(prix_abonnement_mensuel, 0) <= 0;

  if v_sans_prix > 0 then
    raise warning
      '% entreprise(s) sans prix mensuel : elles ne pourront pas payer tant '
      'qu''un prix (barème ou négocié) ne sera pas fixé.', v_sans_prix;
  end if;
end $$;

-- ============================================================================
--  FIN — PHASE 11 ter
-- ============================================================================
