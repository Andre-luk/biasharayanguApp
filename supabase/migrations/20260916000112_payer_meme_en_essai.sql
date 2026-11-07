-- ============================================================================
--  biashara_yangu — CORRECTIF 112 : PAYER SON ABONNEMENT MÊME EN ESSAI
--  ---------------------------------------------------------------------------
--  CE QUE LE PROPRIÉTAIRE DEMANDE (07/11/2026)
--    « Le système doit détecter quelqu'un qui n'a pas encore payé, même
--      pendant les 7 jours d'essai, et lui montrer un bouton pour payer. »
--
--  LE BLOCAGE RÉEL
--    La passerelle Mobile Money (`rpc_serdipay_ouvrir`) ne sait encaisser
--    qu'un MONTANT DÛ. Or un compte en essai (ou déjà actif) a
--    `solde_restant = 0` : elle répondait « SOLDE_NUL — rien à payer ».
--    Le client ne pouvait donc PAS payer avant l'échéance, et l'écran ne lui
--    proposait aucun bouton.
--
--  LA SOLUTION
--    `abonnement_ouvrir_avance(uuid)` ouvre le PROCHAIN cycle (prix de base +
--    supplément collaborateurs) SANS toucher au statut ni aux dates :
--      • l'accès en cours est conservé (aucune coupure injustifiée) ;
--      • la passerelle trouve un montant à encaisser ;
--      • au paiement, le moteur prolonge à partir de la date d'expiration
--        existante → les jours déjà payés ne sont jamais perdus.
--
--  ⚠️ IDEMPOTENT : si un solde est déjà ouvert, la fonction ne fait rien.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);

do $$
begin
  if not exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where p.proname = 'rpc_abonnement_enregistrer_paiement' and n.nspname = 'public'
  ) then
    raise exception
      'Moteur d''abonnement absent : exécutez d''abord la migration 000109.';
  end if;
end $$;


create or replace function public.abonnement_ouvrir_avance(
  p_entreprise uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user    uuid := auth.uid();
  v_owner   uuid;
  v_id      uuid;
  v_e       public.entreprises%rowtype;
  v_base    numeric := 0;
  v_supp    numeric := 0;
  v_total   numeric := 0;
  v_solde   numeric := 0;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour payer votre abonnement.';
  end if;

  v_owner := public.mon_proprietaire();
  v_id := coalesce(p_entreprise, public.mon_entreprise_id(), v_owner, v_user);

  select * into v_e from public.entreprises where id = v_id for update;
  if not found then
    raise exception 'ENTREPRISE_INTROUVABLE|Cette entreprise n''existe pas.';
  end if;

  -- Portée stricte : son entreprise, ou la plateforme.
  if not (v_user = v_e.id
          or v_user = v_owner
          or public.est_plateforme()) then
    raise exception 'DROIT_REFUSE|Vous n''avez pas accès à ce dossier.';
  end if;

  v_solde := coalesce(v_e.solde_restant, 0);

  -- Un montant est déjà réclamé : on n'ouvre rien, on laisse payer celui-là.
  if v_solde > 0.009 then
    return jsonb_build_object(
      'ok', true,
      'ouvert', false,
      'motif', 'DEJA_DU',
      'montant', v_solde,
      'echeance', v_e.date_expiration,
      'devise', coalesce(v_e.devise, 'CDF')
    );
  end if;

  v_base := public.abonnement_prix_base(v_id);
  if v_base <= 0 then
    raise exception 'PRIX_ABSENT|Aucun prix d''abonnement n''est défini pour ce compte : contactez la plateforme.';
  end if;

  v_supp  := public.abonnement_supplement_collaborateurs(v_id);
  v_total := round(v_base + v_supp, 2);

  -- ⚠️ On ne touche NI au statut NI aux dates : l'accès en cours continue.
  --    Le cycle anticipé est simplement « à encaisser ».
  update public.entreprises
     set montant_total_du          = v_total,
         montant_deja_paye         = 0,
         supplement_collaborateurs = v_supp,
         updated_at                = now()
   where id = v_id;

  begin
    perform public.abonnement_photographier_periode(v_id, v_base);
  exception when others then null;
  end;

  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(), v_id, 'ABONNEMENT_AVANCE_OUVERTE', v_user,
    jsonb_build_object(
      'base', v_base,
      'supplement_collaborateurs', v_supp,
      'montant', v_total,
      'echeance_actuelle', v_e.date_expiration,
      'statut', v_e.statut
    ),
    now()
  );

  return jsonb_build_object(
    'ok', true,
    'ouvert', true,
    'motif', 'CYCLE_ANTICIPE',
    'montant', v_total,
    'base', v_base,
    'supplement_collaborateurs', v_supp,
    'echeance', v_e.date_expiration,
    'jours_restants', case
      when v_e.date_expiration is null then null
      else greatest(ceil(extract(epoch from (v_e.date_expiration - now())) / 86400), 0)::int
    end,
    'devise', coalesce(v_e.devise, 'CDF')
  );
end;
$$;

comment on function public.abonnement_ouvrir_avance(uuid) is
  'Correctif 112 — ouvre le prochain cycle (base + collaborateurs) sans toucher au statut ni aux dates, pour permettre le paiement pendant l''essai ou avant l''échéance.';

revoke all on function public.abonnement_ouvrir_avance(uuid) from public, anon;
grant execute on function public.abonnement_ouvrir_avance(uuid) to authenticated;


-- ============================================================================
--  2. LE MOTEUR PROLONGE À PARTIR DE L'ÉCHÉANCE RÉELLE
-- ============================================================================
--  Sans ce correctif, un paiement EFFECTUÉ PENDANT L'ESSAI repartait de
--  « maintenant » (le statut n'était pas ACTIF) et le client perdait les jours
--  d'essai restants. Désormais la prolongation part de la date d'expiration
--  dès qu'elle est future : essai, abonnement actif ou mois déjà réglé.
--
--  ⚠️ Reprise INTÉGRALE du moteur (migration 000109) : une seule condition
--     change. IDEMPOTENT.

create or replace function public.rpc_abonnement_enregistrer_paiement(
  p_entreprise_id uuid,
  p_montant       numeric,
  p_type_paiement text default 'AVANCE',
  p_mode_paiement text default null,
  p_note          text default null
)
returns public.entreprises
language plpgsql
security definer
set search_path = public
as $$
declare
  v_entreprise    public.entreprises;
  v_type          text;
  v_duree         integer := 0;
  v_paye          numeric;
  v_total         numeric;
  v_solde         numeric;
  v_statut_avant  text;
  v_nouveau_paye  numeric;
  v_nouveau_solde numeric;
  v_prolongation  integer := 0;
  v_base          timestamptz;
  v_activer       boolean := false;
  v_abo_grille    numeric := 0;
  v_ouv_grille    numeric := 0;
  v_premier_cycle boolean := false;
  v_inst_ecrire   numeric;
  v_mens_ecrire   numeric;
  -- Module 26
  v_supplement    numeric := 0;
  v_supp_ecrire   numeric;
  v_base_prix     numeric;
begin
  if not exists (
    select 1 from public.utilisateurs u
    where u.id = auth.uid() and u.role = 'admin'
  ) then
    raise exception 'ACCES_REFUSE';
  end if;

  if p_montant is null or p_montant <= 0 then
    raise exception 'MONTANT_INVALIDE';
  end if;

  v_type := upper(btrim(coalesce(p_type_paiement, 'AVANCE')));
  if v_type not in ('AVANCE', 'SOLDE', 'RENOUVELLEMENT') then
    raise exception 'TYPE_PAIEMENT_INVALIDE';
  end if;

  select * into v_entreprise
  from public.entreprises
  where id = p_entreprise_id
  for update;

  if not found then
    raise exception 'ENTREPRISE_INTROUVABLE';
  end if;

  v_statut_avant := v_entreprise.statut::text;

  select coalesce(g.duree_abonnement_jours, 30)
    into v_duree
    from public.groupes_tarifaires g
   where g.id = v_entreprise.groupe_tarifaire_id;
  v_duree := coalesce(v_duree, 30);

  select coalesce(g.montant_abonnement, 0),
         coalesce(g.frais_ouverture, 0)
    into v_abo_grille, v_ouv_grille
    from public.groupes_tarifaires g
   where g.id = v_entreprise.groupe_tarifaire_id;
  v_abo_grille := coalesce(v_abo_grille, 0);
  v_ouv_grille := coalesce(v_ouv_grille, 0);

  v_paye  := coalesce(v_entreprise.montant_deja_paye, 0);
  v_total := coalesce(v_entreprise.montant_total_du, 0);
  v_solde := coalesce(v_entreprise.solde_restant, greatest(v_total - v_paye, 0));

  if v_solde <= 0 or v_statut_avant = 'EXPIRE' then

    v_premier_cycle := (v_entreprise.date_activation is null);

    if v_premier_cycle then
      v_total := coalesce(
        nullif(v_entreprise.prix_installation, 0),
        nullif(v_total, 0),
        nullif(v_ouv_grille + v_abo_grille, 0),
        nullif(v_abo_grille, 0),
        0
      );

      if v_total <= 0 then
        raise exception 'MONTANT_TOTAL_INCONNU';
      end if;

      v_inst_ecrire := v_total;

    else
      v_total := coalesce(
        nullif(v_entreprise.prix_abonnement_mensuel, 0),
        nullif(v_abo_grille, 0),
        case
          when v_entreprise.prix_installation is not null
               and v_total = v_entreprise.prix_installation
            then null
          --  On retire le supplément du cycle précédent : il sera recalculé
          --  juste après, sinon il serait compté deux fois.
          else nullif(v_total - coalesce(v_entreprise.supplement_collaborateurs, 0), 0)
        end,
        case
          when v_entreprise.prix_installation is not null
               and p_montant = v_entreprise.prix_installation
            then null
          else p_montant
        end,
        0
      );

      if v_total <= 0 then
        raise exception
          'PRIX_MENSUEL_ABSENT|La somme saisie correspond exactement au prix d''installation (%, premier mois deja inclus) : elle ne peut pas etre reclamee une seconde fois. Saisissez le montant negocie du mois.',
          coalesce(v_entreprise.prix_installation, 0);
      end if;

      v_mens_ecrire := v_total;
    end if;

    -- 🧮 MODULE 26 — SUPPLÉMENT COLLABORATEURS ---------------------------
    --  Ajouté APRÈS l'apprentissage des prix de base : `prix_abonnement_mensuel`
    --  ne contient jamais le supplément, il est recalculé à chaque cycle.
    v_base_prix  := v_total;
    v_supplement := public.abonnement_supplement_collaborateurs(p_entreprise_id);
    v_total      := round(v_total + v_supplement, 2);
    v_supp_ecrire := v_supplement;

    begin
      perform public.abonnement_photographier_periode(p_entreprise_id, v_base_prix);
    exception when others then null;
    end;

    v_paye  := 0;
    v_solde := v_total;
  end if;

  if p_montant > v_solde + 0.001 then
    raise exception 'MONTANT_SUPERIEUR';
  end if;

  v_nouveau_paye  := v_paye + p_montant;
  v_nouveau_solde := greatest(v_solde - p_montant, 0);

  if v_nouveau_solde <= 0 and v_statut_avant <> 'SUSPENDU' then
    v_activer := true;
    v_prolongation := v_duree;

    -- 🩹 AUCUN JOUR DÉJÀ PAYÉ N'EST PERDU : la règle ne dépend plus du
    --  STATUT mais de la DATE. Pendant un essai (statut ESSAI_7J) ou un mois
    --  déjà réglé, le nouveau cycle part de l'échéance future.
    if v_entreprise.date_expiration is not null
       and v_entreprise.date_expiration > now() then
      v_base := v_entreprise.date_expiration;
    else
      v_base := now();
    end if;
  end if;

  update public.entreprises
     set montant_total_du   = v_total,
         montant_deja_paye  = v_nouveau_paye,
         prix_installation       = coalesce(v_inst_ecrire, prix_installation),
         prix_abonnement_mensuel = coalesce(v_mens_ecrire, prix_abonnement_mensuel),
         supplement_collaborateurs = coalesce(v_supp_ecrire, supplement_collaborateurs),
         statut             = case
                                when v_activer then 'ACTIF'::public.statut_abonnement_enum
                                when v_statut_avant = 'EXPIRE'
                                  then 'EN_ATTENTE_COMPLEMENT'::public.statut_abonnement_enum
                                else v_entreprise.statut
                              end,
         date_activation    = case
                                when v_activer
                                  then coalesce(v_entreprise.date_activation, now())
                                else v_entreprise.date_activation
                              end,
         date_expiration    = case
                                when v_activer
                                  then v_base + make_interval(days => v_duree)
                                else v_entreprise.date_expiration
                              end,
         updated_at         = now()
   where id = p_entreprise_id
   returning * into v_entreprise;

  insert into public.paiements_abonnements_laperle (
    id, entreprise_id, montant, type_paiement, mode_paiement,
    note, total_apres, solde_apres, prolongation_jours,
    enregistre_par, created_at
  ) values (
    gen_random_uuid(),
    p_entreprise_id,
    p_montant,
    v_type,
    nullif(btrim(p_mode_paiement), ''),
    nullif(btrim(p_note), ''),
    v_entreprise.montant_deja_paye,
    v_entreprise.solde_restant,
    v_prolongation,
    auth.uid(),
    now()
  );

  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(),
    p_entreprise_id,
    'PAIEMENT_ENREGISTRE',
    auth.uid(),
    jsonb_build_object(
      'montant',        p_montant,
      'type',           v_type,
      'total_cycle',    v_total,
      'supplement_collaborateurs', v_supplement,
      'collaborateurs_actifs', public.abonnement_collaborateurs_actifs(p_entreprise_id),
      'reste_a_payer',  v_nouveau_solde
    ),
    now()
  );

  return v_entreprise;
end;
$$;

comment on function public.rpc_abonnement_enregistrer_paiement(uuid, numeric, text, text, text) is
  'Correctif 112 — moteur de paiement : cycle = base + supplément collaborateurs, prolongation à partir de l''échéance réelle (aucun jour payé perdu).';

revoke all on function public.rpc_abonnement_enregistrer_paiement(uuid, numeric, text, text, text) from public, anon;


-- ============================================================================
--  VÉRIFICATION
-- ============================================================================
select p.proname, pg_get_function_arguments(p.oid) as arguments
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname = 'abonnement_ouvrir_avance';
