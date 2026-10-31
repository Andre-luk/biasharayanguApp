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
  v_prix    integer := 0;
  v_act     integer := 0;
  v_generee boolean := false;
begin
  -- ------------------------------------------------------------------------
  -- 0. `solde_restant` est-elle une colonne GÉNÉRÉE ?
  --
  -- Elle l'est dans certaines bases (elle se recalcule alors toute seule à
  -- partir de `montant_total_du - montant_deja_paye`) et ne l'est pas dans
  -- d'autres, où le moteur l'écrit lui-même. Écrire dans une colonne générée
  -- lève l'erreur 428C9 : on s'adapte donc au schéma réel plutôt que de
  -- supposer.
  -- ------------------------------------------------------------------------
  select coalesce(bool_or(is_generated = 'ALWAYS'), false)
    into v_generee
    from information_schema.columns
   where table_schema = 'public'
     and table_name = 'entreprises'
     and column_name = 'solde_restant';

  -- ------------------------------------------------------------------------
  -- 1. PRIX PAR DÉFAUT (uniquement là où ils manquent)
  -- ------------------------------------------------------------------------
  if exists (
    select 1 from information_schema.tables
     where table_schema = 'public' and table_name = 'bareme_abonnement'
  ) then

    -- UN SEUL passage, avec `coalesce` : on ne remplit QUE le champ vide.
    -- Un prix négocié (installation ou mensuel) n'est donc jamais écrasé,
    -- même si l'autre champ manque encore.
    update public.entreprises e
       set prix_installation = coalesce(e.prix_installation, b.prix_installation),
           prix_abonnement_mensuel =
             coalesce(e.prix_abonnement_mensuel, b.prix_mensuel),
           updated_at = now()
      from public.bareme_abonnement b
     where b.profil = case
                        when lower(btrim(coalesce(e.type_activite, ''))) = 'distribution'
                          then 'distribution'
                        else 'boutique_complete'
                      end
       and b.actif
       and (e.prix_installation is null or e.prix_abonnement_mensuel is null);
    get diagnostics v_prix = row_count;
  end if;

  -- ------------------------------------------------------------------------
  -- 2. ACTIVATION DES DOSSIERS EN ATTENTE
  --    → actif en essai 7 jours, sans aucune validation administrative.
  --
  -- Le solde de l'essai doit valoir 0. Sur une colonne générée, mettre les
  -- deux montants à 0 suffit (le solde suit) ; sur une colonne ordinaire, il
  -- faut aussi l'écrire.
  -- ------------------------------------------------------------------------
  if v_generee then
    update public.entreprises
       set activation_etape  = 'actif',
           statut            = 'ESSAI_7J'::public.statut_abonnement_enum,
           date_activation   = coalesce(date_activation, now()),
           date_expiration   = coalesce(date_expiration, now() + interval '7 days'),
           montant_total_du  = coalesce(montant_total_du, 0),
           montant_deja_paye = coalesce(montant_deja_paye, 0),
           updated_at        = now()
     where activation_etape = 'en_attente_verification';
  else
    update public.entreprises
       set activation_etape  = 'actif',
           statut            = 'ESSAI_7J'::public.statut_abonnement_enum,
           date_activation   = coalesce(date_activation, now()),
           date_expiration   = coalesce(date_expiration, now() + interval '7 days'),
           montant_total_du  = coalesce(montant_total_du, 0),
           montant_deja_paye = coalesce(montant_deja_paye, 0),
           solde_restant     = 0,
           updated_at        = now()
     where activation_etape = 'en_attente_verification';
  end if;
  get diagnostics v_act = row_count;

  raise notice
    'Rattrapage terminé : % entreprise(s) avec prix par défaut, '
    '% dossier(s) activé(s) en essai 7 jours. solde_restant générée : %',
    v_prix, v_act, v_generee;
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
