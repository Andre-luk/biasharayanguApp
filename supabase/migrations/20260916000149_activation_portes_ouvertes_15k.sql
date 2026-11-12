-- ============================================================================
--  biashara_yangu — MIGRATION 0149 : RÉACTIVER « Sté PORTES OUVERTES » 1 MOIS
--
--  DEMANDE
--    « Il avait déjà payé ses 60 000 FC d'installation et le mois était
--      inclus. Il a 2 collaborateurs, donc 15 000 FC par mois.
--      Il faut activer son abonnement d'un mois. »
--
--    Diagnostic fourni :
--      nom              = Sté Portes Ouvertes
--      statut           = EXPIRE
--      activation_etape = restreint
--      échéance         = 12/11/2026 09:17
--
--  CE QUE FAIT CE SCRIPT
--    1. Retrouve l'entreprise « Sté Portes Ouvertes » (nom exact, puis
--       insensible à la casse / aux accents de ponctuation).
--    2. Rouvre l'accès pour UN MOIS : statut ACTIF, étape `actif`,
--       échéance = +1 mois.
--    3. Recale la facture mensuelle à 15 000 FC
--       = 10 000 de base + 2 × 2 500 de collaborateurs.
--    4. Marque ce mois comme réglé (`montant_deja_paye`), puisque le mois
--       était inclus dans les 60 000 FC d'installation déjà encaissés.
--    5. Journalise l'opération et affiche un contrôle AVANT / APRÈS.
--
--  ⚠️ IDEMPOTENT : si l'échéance est DÉJÀ dans le futur, le script ne
--     rajoute AUCUN mois supplémentaire — il se contente de recaler les
--     montants et de le signaler. On peut donc le relancer sans risque.
--
--  ⚠️ Si le paiement du mois n'est pas réellement encaissé, remplacer dans
--     le bloc 3 la ligne `montant_deja_paye = ...` par
--     `montant_deja_paye = coalesce(montant_deja_paye, 0)` pour laisser
--     apparaître un solde dû de 15 000 FC.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);


-- ============================================================================
--  1. ÉTAT DES LIEUX (AVANT)
-- ============================================================================

select 'AVANT' as etape,
       e.id,
       e.nom,
       e.statut::text                                   as statut,
       e.activation_etape,
       to_char(e.date_activation, 'DD/MM/YYYY HH24:MI') as activation,
       to_char(e.date_expiration, 'DD/MM/YYYY HH24:MI') as echeance,
       (e.date_expiration - now())                       as temps_restant,
       e.prix_installation,
       e.montant_total_du,
       e.montant_deja_paye,
       (select string_agg(s.nom, ' · ') from public.espaces s
         where s.entreprise_id = e.id)                   as boutiques
  from public.entreprises e
 where lower(regexp_replace(e.nom, '[^[:alnum:]]', '', 'g'))
       = lower(regexp_replace('Sté Portes Ouvertes', '[^[:alnum:]]', '', 'g'));

-- Qui est facturé dans cette entreprise ? (attendu : 2 lignes, le patron exclu)
select 'COLLABORATEURS FACTURÉS' as etape,
       u.email,
       coalesce(u.nom, '') || ' ' || coalesce(u.prenom, '') as nom,
       coalesce(u.new_role::text, u.role)                   as role,
       u.valide,
       u.id = e.owner_id                                    as est_le_patron
  from public.entreprises e
  join public.utilisateurs u
    on u.entreprise_id = e.id
    or (u.entreprise_id is null and u.parent_id::text = e.owner_id::text)
 where lower(regexp_replace(e.nom, '[^[:alnum:]]', '', 'g'))
       = lower(regexp_replace('Sté Portes Ouvertes', '[^[:alnum:]]', '', 'g'))
 order by est_le_patron, u.email;


-- ============================================================================
--  2. ACTIVATION D'UN MOIS
-- ============================================================================

do $$
declare
  -- ─────────────────────────── PARAMÈTRES ───────────────────────────
  v_nom_cible   text    := 'Sté Portes Ouvertes';
  v_jours       integer := 30;      -- un mois
  v_base_cible  numeric := 10000;   -- abonnement de base mensuel
  v_prix_collab numeric := 2500;    -- par collaborateur actif
  v_marquer_paye boolean := true;   -- le mois était inclus dans les 60 000
  -- ──────────────────────────────────────────────────────────────────

  v_ent        uuid;
  v_nom        text;
  v_statut     text;
  v_exp_avant  timestamptz;
  v_exp_apres  timestamptz;
  v_base       numeric;
  v_collab     integer;
  v_sup        numeric;
  v_total      numeric;
  v_deja       numeric;
  v_deja_avant numeric;
begin
  -- 1) Retrouver l'entreprise : nom exact, puis via ses boutiques.
  select e.id, e.nom into v_ent, v_nom
    from public.entreprises e
   where lower(regexp_replace(e.nom, '[^[:alnum:]]', '', 'g'))
         = lower(regexp_replace(v_nom_cible, '[^[:alnum:]]', '', 'g'))
   order by e.created_at
   limit 1;

  if v_ent is null then
    select e.id, e.nom into v_ent, v_nom
      from public.entreprises e
      join public.espaces s on s.entreprise_id = e.id
     where lower(regexp_replace(s.nom, '[^[:alnum:]]', '', 'g'))
           = lower(regexp_replace(v_nom_cible, '[^[:alnum:]]', '', 'g'))
     order by e.created_at
     limit 1;
  end if;

  if v_ent is null then
    raise exception
      'ENTREPRISE_INTROUVABLE|Aucune entreprise ne correspond à « % ».', v_nom_cible;
  end if;

  -- 2) Verrou + état courant.
  select e.statut::text, e.date_expiration, e.montant_deja_paye
    into v_statut, v_exp_avant, v_deja_avant
    from public.entreprises e
   where e.id = v_ent
     for update;

  -- 3) Un mois de plus — SEULEMENT si l'accès est réellement fermé.
  if v_exp_avant is not null and v_exp_avant > now() then
    v_exp_apres := v_exp_avant;
    raise notice
      'Aucun mois ajouté : « % » est déjà actif jusqu''au % (relance sans effet).',
      v_nom, to_char(v_exp_avant, 'DD/MM/YYYY HH24:MI');
  else
    v_exp_apres := greatest(coalesce(v_exp_avant, now()), now())
                   + make_interval(days => v_jours);
    raise notice 'Nouvelle échéance : % → %',
      coalesce(to_char(v_exp_avant, 'DD/MM/YYYY HH24:MI'), 'aucune'),
      to_char(v_exp_apres, 'DD/MM/YYYY HH24:MI');
  end if;

  update public.entreprises
     set statut           = 'ACTIF'::public.statut_abonnement_enum,
         activation_etape = 'actif',
         date_activation  = coalesce(date_activation, now()),
         date_expiration  = v_exp_apres,
         updated_at       = now()
   where id = v_ent;

  -- 4) Facture mensuelle : base + 2 × 2 500.
  v_base := coalesce(public.abonnement_prix_base(v_ent), 0);

  -- Garde-fou : `abonnement_prix_base()` renvoie les frais d'installation
  -- (60 000) quand `date_activation` était vide — ce n'est pas un
  -- abonnement mensuel. Tout montant nul ou anormalement élevé est donc
  -- ramené au tarif de base mensuel.
  if v_base <= 0 or v_base > v_base_cible * 5 then
    v_base := v_base_cible;
  end if;

  v_collab := coalesce(public.abonnement_collaborateurs_actifs(v_ent), 0);

  -- Garde-fou : le prix unitaire doit venir de la plateforme, pas d'un
  -- réglage vidé.
  if coalesce(public.abonnement_prix_collaborateur(), 0) > 0 then
    v_prix_collab := public.abonnement_prix_collaborateur();
  end if;

  v_sup   := v_collab * v_prix_collab;
  v_total := v_base + v_sup;

  -- Le mois est déjà réglé : le règlement d'installation l'incluait.
  v_deja := case
              when v_marquer_paye
                then greatest(coalesce(v_deja_avant, 0), v_total)
              else coalesce(v_deja_avant, 0)
            end;

  update public.entreprises
     set montant_total_du       = v_total,
         supplement_collaborateurs = v_sup,
         montant_deja_paye      = v_deja,
         updated_at             = now()
   where id = v_ent;

  -- 5) Journal d'audit.
  insert into public.journal_audit
         (id, entreprise_id, action, utilisateur_id, details, created_at)
  values (gen_random_uuid(), v_ent, 'ABONNEMENT_ACTIVE_1_MOIS', null,
          jsonb_build_object(
            'entreprise',      v_nom,
            'statut_avant',    v_statut,
            'echeance_avant',  v_exp_avant,
            'echeance_apres',  v_exp_apres,
            'base',            v_base,
            'collaborateurs',  v_collab,
            'prix_collaborateur', v_prix_collab,
            'total_du',        v_total,
            'deja_paye',       v_deja,
            'motif',           'Installation 60 000 FC payée, mois inclus'),
          now());

  raise notice
    '✅ « % » actif jusqu''au % — % FC/mois (base % + % × %).',
    v_nom, to_char(v_exp_apres, 'DD/MM/YYYY HH24:MI'),
    v_total, v_base, v_collab, v_prix_collab;
end $$;


-- ============================================================================
--  3. CONTRÔLE (APRÈS)
-- ============================================================================

select 'APRÈS' as etape,
       e.nom,
       e.statut::text                                    as statut,
       e.activation_etape,
       to_char(e.date_expiration, 'DD/MM/YYYY HH24:MI')  as echeance,
       (e.date_expiration - now())                        as temps_restant,
       public.abonnement_prix_base(e.id)                  as base,
       public.abonnement_collaborateurs_actifs(e.id)      as nb_collaborateurs,
       public.abonnement_supplement_collaborateurs(e.id)  as supplement,
       e.montant_total_du                                 as total_du,
       e.montant_deja_paye                                as deja_paye,
       (e.montant_total_du - coalesce(e.montant_deja_paye, 0)) as solde,
       case
         when e.activation_etape = 'actif' and e.date_expiration > now()
           then '✅ ACCÈS OUVERT (1 mois)'
         else '❌ À VÉRIFIER'
       end                                                as resultat
  from public.entreprises e
 where lower(regexp_replace(e.nom, '[^[:alnum:]]', '', 'g'))
       = lower(regexp_replace('Sté Portes Ouvertes', '[^[:alnum:]]', '', 'g'));

select 'MIGRATION 0149 TERMINÉE' as controle,
       'Déconnectez-vous puis reconnectez-vous dans l''application.' as consigne;
