-- ============================================================================
--  biashara_yangu — PHASE 2 : FORFAITS PAR TYPE D'ACTIVITÉ
--                    ET ÉTAT DE L'INSTALLATION
--  ---------------------------------------------------------------------------
--  Deux questions auxquelles l'application doit répondre SANS DEVINER :
--
--   1. « Quels forfaits proposer à cette entreprise ? »
--      → ceux de son type d'activité, plus les forfaits communs (type NULL).
--
--   2. « L'installation a-t-elle déjà été réglée ? »
--      → lecture de l'historique réel des versements, jamais d'une case à
--        cocher. Une installation ne se paie qu'UNE fois dans la vie d'une
--        entreprise : le premier cycle comprend le premier mois.
--
--  ⚠️ CETTE MIGRATION N'ÉCRIT RIEN ET NE REMPLACE AUCUN MOTEUR.
--     En particulier, `rpc_abonnement_enregistrer_paiement` n'est PAS
--     redéfini : le correctif 60 y applique déjà la règle « prix
--     d'installation au premier cycle (date_activation nulle), prix mensuel
--     ensuite ». On se contente d'exposer cet état à l'écran.
--
--  PRÉ-REQUIS : 20260916000060 (prix_installation) et
--              20260916000083 (type_activite) exécutées.
--  ⚠️ IDEMPOTENT.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);

-- Contrôle préalable ---------------------------------------------------------
do $$
begin
  if not exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'entreprises'
       and column_name = 'prix_installation'
  ) then
    raise exception 'Migration 0060 absente : exécutez 20260916000060_prix_installation_et_mensuel.sql.';
  end if;
  if not exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'groupes_tarifaires'
       and column_name = 'type_activite'
  ) then
    raise exception 'Migration 0083 absente : exécutez 20260916000083_type_activite_entreprise.sql.';
  end if;
end $$;


-- ============================================================================
--  1. FORFAITS D'UNE ENTREPRISE — filtrés, jamais fermés
-- ============================================================================
--  Deux niveaux de filtrage, du plus fin au plus large :
--    1. `type_activite` du forfait : NULL = commun à tous les types ;
--    2. `activite_id` (métier : restaurant, pharmacie…) quand il est fourni.
create or replace function public.rpc_forfaits_entreprise(
  p_entreprise uuid default null,
  p_type       text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_user   uuid := auth.uid();
  v_type   text;
  v_liste  jsonb;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour consulter les forfaits.';
  end if;

  v_type := lower(btrim(coalesce(p_type, '')));

  -- Sans type explicite, on prend celui de l'entreprise demandée (ou la
  -- sienne). Un type inconnu laisse TOUT visible : on n'enferme personne.
  if v_type = '' and p_entreprise is not null then
    select lower(btrim(coalesce(e.type_activite, '')))
      into v_type
      from public.entreprises e
     where e.id = p_entreprise;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', g.id,
           'nom', g.nom,
           'type_activite', g.type_activite,
           'frais_ouverture', coalesce(g.frais_ouverture, 0),
           'montant_abonnement', coalesce(g.montant_abonnement, 0),
           'duree_essai_jours', coalesce(g.duree_essai_jours, 0),
           'duree_abonnement_jours', coalesce(g.duree_abonnement_jours, 30),
           'prix_par_collaborateur', coalesce(g.prix_par_collaborateur, 0),
           'max_collaborateurs', coalesce(g.max_collaborateurs, 0),
           'max_espaces', coalesce(g.max_espaces, 1)
         ) order by coalesce(g.frais_ouverture, 0), g.nom), '[]'::jsonb)
    into v_liste
    from public.groupes_tarifaires g
   where v_type = ''
      or g.type_activite is null
      or lower(btrim(g.type_activite)) = v_type;

  return jsonb_build_object(
    'ok', true,
    'type_activite', nullif(v_type, ''),
    'forfaits', coalesce(v_liste, '[]'::jsonb)
  );
end;
$$;

comment on function public.rpc_forfaits_entreprise(uuid, text) is
  'Forfaits proposables à une entreprise : ceux de son type d''activité et les forfaits communs (type NULL). Type inconnu → tout est proposé.';


-- ============================================================================
--  2. ÉTAT DE L'INSTALLATION — lu dans l'historique, pas déclaré
-- ============================================================================

create or replace function public.rpc_abonnement_installation_etat(
  p_entreprise uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_user      uuid := auth.uid();
  v_id        uuid;
  v_e         public.entreprises%rowtype;
  v_owner     uuid;
  v_cycles    integer := 0;
  v_inst_paye numeric := 0;
  v_deja      boolean := false;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour consulter l''abonnement.';
  end if;

  v_owner := public.mon_proprietaire();
  v_id := p_entreprise;

  if v_id is null then
    -- L'entreprise de l'utilisateur : la sienne, ou celle dont il dépend.
    v_id := coalesce(v_owner, v_user);
  end if;

  select * into v_e from public.entreprises where id = v_id;
  if not found then
    raise exception 'ENTREPRISE_INTROUVABLE|Cette entreprise n''existe pas.';
  end if;

  -- Périmètre : l'entreprise elle-même, son propriétaire, ou la plateforme.
  if not (v_user = v_e.id
          or v_user = coalesce(v_owner, v_e.id)
          or public.est_plateforme()) then
    raise exception 'DROIT_REFUSE|Vous n''avez pas accès à ce dossier.';
  end if;

  -- Nombre de cycles déjà réglés (un cycle soldé = un versement qui a amené
  -- le solde à zéro). On ne devine pas : on compte les faits.
  select count(*) filter (where coalesce(p.solde_apres, 0) <= 0)
    into v_cycles
    from public.paiements_abonnements_laperle p
   where p.entreprise_id = v_id;

  select coalesce(sum(p.montant), 0)
    into v_inst_paye
    from public.paiements_abonnements_laperle p
   where p.entreprise_id = v_id
     and lower(coalesce(p.type_paiement, '')) in ('installation', 'ouverture');

  -- L'installation est réputée réglée si :
  --   • l'entreprise a déjà été activée un jour (règle du moteur, correctif 60) ;
  --   • OU un versement de nature « installation / ouverture » existe ;
  --   • OU au moins un cycle complet a été soldé.
  v_deja := (v_e.date_activation is not null)
            or (v_inst_paye > 0)
            or (v_cycles > 0);

  return jsonb_build_object(
    'ok', true,
    'entreprise_id', v_id,
    'devise', coalesce(v_e.devise, 'CDF'),
    'prix_installation', coalesce(v_e.prix_installation, 0),
    'prix_mensuel', coalesce(v_e.prix_abonnement_mensuel, 0),
    'montant_total_du', coalesce(v_e.montant_total_du, 0),
    'montant_deja_paye', coalesce(v_e.montant_deja_paye, 0),
    'solde_restant', coalesce(v_e.solde_restant, 0),
    'statut', coalesce(v_e.statut, ''),
    'date_activation', v_e.date_activation,
    'date_expiration', v_e.date_expiration,
    'installation_deja_reglee', v_deja,
    'installation_reglee_montant', v_inst_paye,
    'cycles_soldes', v_cycles,
    -- Ce que le PROCHAIN encaissement doit demander : l'installation si elle
    -- n'a jamais été réglée, le mensuel sinon. Jamais les deux.
    'prochain_cycle', case when v_deja then 'abonnement' else 'installation' end,
    'prochain_montant', case
      when v_deja then coalesce(v_e.prix_abonnement_mensuel, 0)
      else coalesce(nullif(v_e.prix_installation, 0),
                    nullif(v_e.montant_total_du, 0), 0)
    end
  );
end;
$$;

comment on function public.rpc_abonnement_installation_etat(uuid) is
  'État de l''installation : déjà réglée ou non, lue dans l''historique réel des versements. Le prochain cycle est soit l''installation, soit le mensuel — jamais les deux.';


-- ============================================================================
--  3. PRIVILÈGES
-- ============================================================================

revoke all on function public.rpc_forfaits_entreprise(uuid, text) from public;
revoke all on function public.rpc_abonnement_installation_etat(uuid) from public;

grant execute on function public.rpc_forfaits_entreprise(uuid, text) to authenticated;
grant execute on function public.rpc_abonnement_installation_etat(uuid) to authenticated;

-- ============================================================================
--  FIN — PHASE 2
-- ============================================================================
