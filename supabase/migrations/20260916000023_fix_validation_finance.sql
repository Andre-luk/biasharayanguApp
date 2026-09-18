-- ============================================================================
--  biashara_yangu — CORRECTIF 23 : « MONTANT_TOTAL_INCONNU » À LA FINANCE
--
--  PROBLÈME (constaté le 18/09/2026 en test de bout en bout) :
--    La validation finance appelait `rpc_abonnement_enregistrer_paiement`
--    qui, pour tout NOUVEAU CYCLE (statut EXPIRE / EN_ATTENTE_COMPLEMENT —
--    c'est-à-dire CHAQUE PREMIER PAIEMENT d'un compte), lisait le prix dans
--    la grille tarifaire via `select ... into v_total`. Sans grille
--    affectée, PostgreSQL mettait v_total à NULL → lever
--    « MONTANT_TOTAL_INCONNU ». Résultat : AUCUNE activation de compte
--    n'était possible, même avec le montant correct.
--
--  CORRECTIF :
--    Le nouveau cycle utilise, dans l'ordre :
--      1. le prix de la grille tarifaire (`montant_abonnement`) ;
--      2. sinon le montant total déjà porté par l'entreprise ;
--      3. sinon → exception (montant réellement inconnu).
--
--  OÙ : Supabase → SQL Editor → coller → Run
--  IDEMPOTENT : peut être relancé sans effet de bord.
-- ============================================================================


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
begin
  -- Réservé aux administrateurs.
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

  -- Durée d'abonnement de la grille tarifaire (30 jours par défaut).
  select coalesce(g.duree_abonnement_jours, 30)
    into v_duree
    from public.groupes_tarifaires g
   where g.id = v_entreprise.groupe_tarifaire_id;
  v_duree := coalesce(v_duree, 30);

  v_paye  := coalesce(v_entreprise.montant_deja_paye, 0);
  v_total := coalesce(v_entreprise.montant_total_du, 0);
  v_solde := coalesce(v_entreprise.solde_restant, greatest(v_total - v_paye, 0));

  -- Ouverture d'un nouveau cycle de facturation si :
  --   - le cycle courant est soldé (renouvellement), ou
  --   - l'abonnement est échu / en attente de complément.
  if v_solde <= 0 or v_statut_avant in ('EXPIRE', 'EN_ATTENTE_COMPLEMENT') then
    -- Correctif 23 — nouveau cycle : prix du pack s'il est défini, sinon le
    -- montant total porté par l'entreprise. AVANT : sans grille tarifaire
    -- affectée, le SELECT INTO mettait v_total à NULL → exception
    -- « MONTANT_TOTAL_INCONNU » et TOUTE première validation finance
    -- échouait (constaté le 18/09/2026 : l'activation était impossible).
    v_total := coalesce(
      (select nullif(g.montant_abonnement, 0)
         from public.groupes_tarifaires g
        where g.id = v_entreprise.groupe_tarifaire_id),
      nullif(v_total, 0),
      0
    );

    if v_total <= 0 then
      raise exception 'MONTANT_TOTAL_INCONNU';
    end if;

    v_paye  := 0;
    v_solde := v_total;
  end if;

  if p_montant > v_solde + 0.001 then
    raise exception 'MONTANT_SUPERIEUR';
  end if;

  v_nouveau_paye  := v_paye + p_montant;
  v_nouveau_solde := greatest(v_solde - p_montant, 0);

  -- Cycle intégralement réglé : activation.
  --  Un compte SUSPENDU n'est jamais réactivé par un paiement : la
  --  réactivation reste une décision de l'administrateur.
  if v_nouveau_solde <= 0 and v_statut_avant <> 'SUSPENDU' then
    v_activer := true;
    v_prolongation := v_duree;

    -- Renouvellement anticipé : on repart de la date d'expiration si elle est
    -- encore future pour ne perdre aucun jour payé ; sinon de maintenant
    -- (essai, abonnement échu, attente de complément).
    if v_statut_avant = 'ACTIF'
       and v_entreprise.date_expiration is not null
       and v_entreprise.date_expiration > now() then
      v_base := v_entreprise.date_expiration;
    else
      v_base := now();
    end if;
  end if;

  update public.entreprises
     set montant_total_du   = v_total,
         montant_deja_paye  = v_nouveau_paye,
         -- `solde_restant` est GÉNÉRÉ (total − payé) : jamais écrit ici.
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

  -- Historique Module 3 (table dédiée, séparée de paiements_abonnement).
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

  -- Journal d'audit (le trigger ci-dessus trace en plus le changement de
  -- statut, le cas échéant).
  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(),
    p_entreprise_id,
    'PAIEMENT_ENREGISTRE',
    auth.uid(),
    jsonb_build_object(
      'montant', p_montant,
      'type_paiement', v_type,
      'mode_paiement', nullif(btrim(p_mode_paiement), ''),
      'statut_avant', v_statut_avant,
      'statut_apres', v_entreprise.statut::text,
      'solde_apres', v_entreprise.solde_restant,
      'prolongation_jours', v_prolongation
    ),
    now()
  );

  return v_entreprise;
end;
$$;

revoke all on function public.rpc_abonnement_enregistrer_paiement(uuid, numeric, text, text, text) from public;
revoke all on function public.rpc_abonnement_enregistrer_paiement(uuid, numeric, text, text, text) from anon;
grant execute on function public.rpc_abonnement_enregistrer_paiement(uuid, numeric, text, text, text) to authenticated;
