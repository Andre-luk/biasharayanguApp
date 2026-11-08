-- ============================================================================
--  biashara_yangu — MODULE 33 : CHANGEMENT DE FORFAIT EN COURS DE CYCLE
--  ---------------------------------------------------------------------------
--  CE QUE LE PROPRIÉTAIRE DEMANDE
--    « Un client passe d'un forfait à un autre avant l'échéance. Il faut
--      calculer ce qu'il doit en plus (ou le crédit qu'on lui doit), sans
--      lui faire payer deux fois les jours déjà réglés. »
--
--  PRINCIPE
--    On raisonne au PRORATA des jours qui restent :
--      valeur_restante = ancien_prix × jours_restants / 30
--      nouveau_du      = nouveau_prix × jours_restants / 30
--      différence      = nouveau_du − valeur_restante
--
--    • différence > 0 → le client paie le complément (montant dû) ;
--    • différence ≤ 0 → RIEN à payer : la différence est enregistrée comme
--      crédit offert (journalisée), le solde dû passe à zéro.
--
--  CE QUE CE SCRIPT AJOUTE
--    `abonnement_changer_forfait(entreprise, nouveau_prix, motif)`.
--
--  ⚠️ RÈGLES
--    • Les DATES ne bougent pas : on change la valeur du cycle en cours, pas
--      sa durée. Un changement de forfait n'offre ni ne retire de jours.
--    • Aucun remboursement en espèces n'est déclenché automatiquement : un
--      crédit reste un crédit, visible dans le journal d'audit.
--    • Réservé à la plateforme / Finance : c'est un prix commercial.
--    • IDEMPOTENT.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);


create or replace function public.abonnement_changer_forfait(
  p_entreprise   uuid default null,
  p_prix_mensuel numeric default null,
  p_motif        text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user     uuid := auth.uid();
  v_owner    uuid;
  v_id       uuid;
  v_e        public.entreprises%rowtype;
  v_ancien   numeric := 0;
  v_nouveau  numeric := 0;
  v_jours    integer := 0;
  v_valeur   numeric := 0;
  v_du       numeric := 0;
  v_diff     numeric := 0;
  v_credit   numeric := 0;
  v_supp     numeric := 0;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;

  -- 💰 Un prix commercial : plateforme / Finance.
  if not (public.est_plateforme()
          or public.peut('abonnements', 'modifier')
          or public.peut('finance', 'modifier')) then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de changer un forfait.';
  end if;

  v_owner := public.mon_proprietaire();
  v_id := coalesce(p_entreprise, public.mon_entreprise_id(), v_owner, v_user);

  select * into v_e from public.entreprises where id = v_id for update;
  if not found then
    raise exception 'ENTREPRISE_INTROUVABLE|Cette entreprise n''existe pas.';
  end if;

  if coalesce(p_prix_mensuel, 0) <= 0 then
    raise exception 'PRIX_INVALIDE|Indiquez un prix mensuel supérieur à zéro.';
  end if;

  v_ancien  := coalesce(v_e.prix_abonnement_mensuel, 0);
  v_nouveau := round(p_prix_mensuel, 2);

  -- Jours restants sur l'accès en cours (0 si échu ou jamais activé).
  v_jours := case
               when v_e.date_expiration is null then 0
               when v_e.date_expiration <= now() then 0
               else greatest(
                 ceil(extract(epoch from (v_e.date_expiration - now())) / 86400),
                 0
               )::int
             end;

  -- Valeur des jours restants, à l'ancien et au nouveau prix.
  v_valeur := round(v_ancien * v_jours / 30.0, 2);
  v_du     := round(v_nouveau * v_jours / 30.0, 2);
  v_diff   := round(v_du - v_valeur, 2);

  -- Le supplément collaborateurs n'est PAS recalculé ici : il dépend du
  -- nombre réel de comptes actifs et reste facturé au prix en vigueur.
  v_supp := coalesce(v_e.supplement_collaborateurs, 0);

  if v_diff > 0.009 then
    v_credit := 0;
  else
    v_credit := round(-v_diff, 2);
    v_diff := 0;
  end if;

  update public.entreprises
     set prix_abonnement_mensuel = v_nouveau,
         -- Seul le complément du prorata reste dû ; les jours déjà payés
         -- ne sont jamais refacturés.
         montant_total_du = round(v_diff + v_supp, 2),
         montant_deja_paye = 0,
         cycles_prepayes = 1,
         updated_at = now()
   where id = v_id;

  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(), v_id, 'ABONNEMENT_FORFAIT_CHANGE', v_user,
    jsonb_build_object(
      'ancien_prix', v_ancien,
      'nouveau_prix', v_nouveau,
      'jours_restants', v_jours,
      'valeur_jours_ancien', v_valeur,
      'valeur_jours_nouveau', v_du,
      'complement_du', v_diff,
      'credit_offert', v_credit,
      'motif', nullif(btrim(coalesce(p_motif, '')), '')
    ),
    now()
  );

  return jsonb_build_object(
    'ok', true,
    'entreprise_id', v_id,
    'ancien_prix', v_ancien,
    'nouveau_prix', v_nouveau,
    'devise', coalesce(v_e.devise, 'CDF'),
    'jours_restants', v_jours,
    'valeur_jours_ancien', v_valeur,
    'valeur_jours_nouveau', v_du,
    'complement_du', v_diff,
    'credit_offert', v_credit,
    'montant_du_cycle', round(v_diff + v_supp, 2),
    'echeance', v_e.date_expiration,
    'hausse', v_nouveau > v_ancien
  );
end;
$$;

comment on function public.abonnement_changer_forfait(uuid, numeric, text) is
  'Module 33 — change le forfait au prorata des jours restants : complément à payer en cas de hausse, crédit journalisé en cas de baisse. Les dates ne bougent pas.';

revoke all on function public.abonnement_changer_forfait(uuid, numeric, text)
  from public, anon;
grant execute on function public.abonnement_changer_forfait(uuid, numeric, text)
  to authenticated;


-- ============================================================================
--  VÉRIFICATION
-- ============================================================================

select p.proname, pg_get_function_arguments(p.oid) as arguments
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname = 'abonnement_changer_forfait';
