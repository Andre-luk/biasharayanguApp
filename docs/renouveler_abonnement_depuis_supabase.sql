-- ============================================================================
--  BIASHARA YANGU — RENOUVELER / RÉACTIVER UN ABONNEMENT, DIRECTEMENT DANS
--  SUPABASE (sans publier l'application, sans faire réinstaller le client).
--  Fichier : docs/renouveler_abonnement_depuis_supabase.sql
--  ---------------------------------------------------------------------------
--  OÙ : éditeur SQL de Supabase (rôle postgres → contourne la RLS et le
--       contrôle de permission, qui exige une session utilisateur).
--
--  POURQUOI CE SCRIPT ET PAS LE BOUTON
--    Le bouton « Réactiver l'abonnement » et « Enregistrer un renouvellement »
--    de l'application appellent des fonctions serveur qui vérifient
--    `auth.uid()` : lancées depuis l'éditeur SQL, elles répondraient
--    « ACCES_REFUSE ». Ce script fait donc la MÊME chose, mais en écriture
--    directe, avec les mêmes garde-fous métier.
--
--  CE QU'IL FAIT, DANS L'ORDRE
--    1. retrouve l'entreprise ;
--    2. affiche son état AVANT (statut, dates, montants) ;
--    3. si un montant est fourni : ouvre le cycle si besoin, enregistre le
--       versement dans l'historique (la facture est générée automatiquement
--       par le déclencheur du correctif 67) ;
--    4. si le dossier est intégralement réglé : passe le statut à ACTIF et
--       repousse la date d'expiration (durée du groupe tarifaire × mois payés,
--       en partant de l'échéance encore future s'il y en a une) ;
--    5. écrit la trace dans `journal_audit` ;
--    6. affiche l'état APRÈS.
--
--  ⚠️ MODE DE PAIEMENT : ne mettez JAMAIS ici un libellé Mobile Money
--     (« Mobile Money », « M-Pesa », « Orange Money »…). Le déclencheur du
--     correctif 44 exigerait une transaction SerdiPay réelle et refuserait
--     l'écriture. Un encaissement fait « à la main » est un encaissement
--     en espèces / manuel : c'est ce que le script écrit.
--
--  ⚠️ IDEMPOTENT dans le sens « rejouable sans dégât » : si le dossier est
--     déjà actif et soldé et que le montant est 0, il ne fait rien.
-- ============================================================================

do $$
declare
  -- ═══════════════════════════════════════════════════════════════════════
  --  🔧 À MODIFIER — LES SEULES LIGNES À TOUCHER
  -- ═══════════════════════════════════════════════════════════════════════
  v_recherche   text    := 'urembo';            -- début du nom du client
  v_montant     numeric := 0;                   -- 0 = réactivation SANS encaissement
  v_mode        text    := 'Espèces';           -- jamais un libellé Mobile Money
  v_note        text    := 'Renouvellement enregistré depuis l''éditeur SQL Supabase';
  v_auteur      text    := null;                -- e-mail de l'agent (facultatif)
  -- ═══════════════════════════════════════════════════════════════════════

  v_id          uuid;
  v_avant       public.entreprises%rowtype;
  v_duree       integer := 30;
  v_prix        numeric := 0;
  v_total       numeric := 0;
  v_paye        numeric := 0;
  v_solde       numeric := 0;
  v_mois        integer := 1;
  v_base        timestamptz;
  v_statut      public.statut_abonnement_enum;
  v_type_paie   text;
  v_auteur_id   uuid;
  v_nb          integer;
begin
  -- ── 1. Le dossier ──────────────────────────────────────────────────────
  select count(*) into v_nb
    from public.entreprises e
   where e.nom ilike '%' || v_recherche || '%';

  if v_nb = 0 then
    raise exception 'Aucune entreprise ne contient « % » dans son nom.', v_recherche;
  elsif v_nb > 1 then
    raise warning 'Plusieurs dossiers contiennent « % » : le premier par ordre alphabétique sera utilisé. Précisez le nom pour éviter toute erreur.', v_recherche;
  end if;

  select * into v_avant
    from public.entreprises e
   where e.nom ilike '%' || v_recherche || '%'
   order by e.nom
   limit 1
   for update;

  raise notice '── DOSSIER : % (%)', v_avant.nom, v_avant.id;
  raise notice '   AVANT → statut=% | expiration=% | total=% | payé=% | solde=%',
    v_avant.statut, v_avant.date_expiration,
    v_avant.montant_total_du, v_avant.montant_deja_paye, v_avant.solde_restant;

  -- Rien à faire ?
  if coalesce(v_avant.solde_restant, 0) <= 0.001
     and v_avant.statut = 'ACTIF'
     and v_avant.date_expiration is not null
     and v_avant.date_expiration > now()
     and v_montant <= 0 then
    raise notice 'RIEN À FAIRE : cet abonnement est déjà actif, soldé, et court jusqu''au %.', v_avant.date_expiration;
    return;
  end if;

  -- ── 2. Durée et prix de référence ──────────────────────────────────────
  select coalesce(g.duree_abonnement_jours, 30)
    into v_duree
    from public.groupes_tarifaires g
   where g.id = v_avant.groupe_tarifaire_id;
  v_duree := coalesce(v_duree, 30);

  begin
    v_prix := public.rpc_abonnement_prix_du_cycle(v_avant.id);
  exception when others then
    raise warning 'Prix du cycle illisible (% %) : repli sur les colonnes du dossier.', sqlstate, sqlerrm;
    v_prix := 0;
  end;

  v_prix := coalesce(nullif(v_prix, 0),
                     nullif(v_avant.prix_abonnement_mensuel, 0),
                     0);

  if v_auteur is not null then
    select u.id into v_auteur_id
      from public.utilisateurs u
     where lower(u.email) = lower(btrim(v_auteur))
     limit 1;
    if v_auteur_id is null then
      raise warning 'Auteur « % » introuvable : le versement sera enregistré sans agent.', v_auteur;
    end if;
  end if;

  -- ── 3. L'ARGENT (facultatif) ───────────────────────────────────────────
  if v_montant > 0 then

    if coalesce(v_avant.solde_restant, 0) > 0.001 then
      -- Un cycle est DÉJÀ ouvert : on ne refacture rien, on encaisse.
      v_total := coalesce(v_avant.montant_total_du, v_prix);
      v_paye  := coalesce(v_avant.montant_deja_paye, 0) + v_montant;
      v_type_paie := case
                       when v_total - v_paye <= 0.001 then 'SOLDE'
                       else 'AVANCE'
                     end;
    else
      -- Cycle soldé : on ouvre le suivant au prix du moment.
      if v_prix <= 0 then
        raise exception 'Aucun prix d''abonnement n''est défini pour ce dossier : renseignez prix_abonnement_mensuel (ou le groupe tarifaire) avant d''encaisser.';
      end if;
      v_total := v_prix;
      v_paye  := v_montant;
      v_type_paie := 'RENOUVELLEMENT';
    end if;

    if v_paye - v_total > 0.01 then
      raise exception 'Le montant saisi (%) dépasse le dû (%). Corrigez v_montant : le moteur n''accepte pas de trop-perçu.', v_montant, v_total;
    end if;

    v_solde := greatest(v_total - v_paye, 0);
  else
    v_total := coalesce(v_avant.montant_total_du, 0);
    v_paye  := coalesce(v_avant.montant_deja_paye, 0);
    v_solde := coalesce(v_avant.solde_restant, greatest(v_total - v_paye, 0));
  end if;

  -- ── 4. Le mois payés → la prolongation ─────────────────────────────────
  if v_montant > 0 and v_prix > 0 then
    v_mois := greatest(1, least(12, round(v_montant / v_prix)::integer));
  else
    v_mois := greatest(1, least(12, coalesce(v_avant.cycles_prepayes, 1)));
  end if;

  -- Aucun jour déjà payé n'est perdu : on repart de l'échéance future.
  v_base := greatest(coalesce(v_avant.date_expiration, now()), now());

  v_statut := case
                when v_solde <= 0.001 then 'ACTIF'::public.statut_abonnement_enum
                when v_avant.statut = 'EXPIRE'
                  then 'EN_ATTENTE_COMPLEMENT'::public.statut_abonnement_enum
                else v_avant.statut
              end;

  -- ── 5. L'écriture ──────────────────────────────────────────────────────
  update public.entreprises
     set montant_total_du  = v_total,
         montant_deja_paye = v_paye,
         solde_restant     = v_solde,
         cycles_prepayes   = 1,
         statut            = v_statut,
         date_activation   = coalesce(date_activation, now()),
         date_expiration   = case
                               when v_solde <= 0.001
                                 then v_base + make_interval(days => v_duree * v_mois)
                               else date_expiration
                             end,
         updated_at        = now()
   where id = v_avant.id;

  if v_montant > 0 then
    insert into public.paiements_abonnements_laperle (
      id, entreprise_id, montant, type_paiement, mode_paiement,
      note, total_apres, solde_apres, prolongation_jours,
      enregistre_par, created_at
    ) values (
      gen_random_uuid(),
      v_avant.id,
      v_montant,
      v_type_paie,
      nullif(btrim(v_mode), ''),
      nullif(btrim(v_note), ''),
      v_paye,
      v_solde,
      case when v_solde <= 0.001 then v_duree * v_mois else 0 end,
      v_auteur_id,
      now()
    );

    raise notice '   VERSEMENT : % % (%) — reste dû %',
      v_montant, coalesce(v_avant.devise, 'CDF'), v_type_paie, v_solde;
  end if;

  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(),
    v_avant.id,
    'REACTIVATION',
    v_auteur_id,
    jsonb_build_object(
      'origine',          'editeur_sql_supabase',
      'montant',          v_montant,
      'mode_paiement',    v_mode,
      'statut_avant',     v_avant.statut,
      'expiration_avant', v_avant.date_expiration,
      'mois',             v_mois,
      'duree_jours',      v_duree
    ),
    now()
  );

  -- ── 6. L'état APRÈS ────────────────────────────────────────────────────
  select * into v_avant from public.entreprises where id = v_avant.id;

  raise notice '   APRÈS → statut=% | activation=% | expiration=% | total=% | payé=% | solde=%',
    v_avant.statut, v_avant.date_activation, v_avant.date_expiration,
    v_avant.montant_total_du, v_avant.montant_deja_paye, v_avant.solde_restant;

  if v_avant.statut = 'ACTIF' then
    raise notice '✅ ABONNEMENT ACTIF jusqu''au %. Le client n''a rien à réinstaller : il lui suffit de rafraîchir (ou de se reconnecter).', v_avant.date_expiration;
  else
    raise notice '⏳ Il reste % dû : le compte reste « % ». Relancez ce script avec v_montant = % pour solder.', v_avant.solde_restant, v_avant.statut, v_avant.solde_restant;
  end if;
end $$;


-- ============================================================================
--  CONTRÔLE (lecture seule) — le dossier tel que le voient les clients
-- ============================================================================

select e.nom,
       e.statut::text        as statut,
       e.date_activation,
       e.date_expiration,
       e.montant_total_du,
       e.montant_deja_paye,
       e.solde_restant,
       e.devise,
       (select count(*) from public.paiements_abonnements_laperle p
         where p.entreprise_id::text = e.id::text)             as versements,
       (select count(*) from public.factures_abonnement f
         where f.entreprise_id = e.id)                          as factures
  from public.entreprises e
 where e.nom ilike '%urembo%'
 order by e.nom;
