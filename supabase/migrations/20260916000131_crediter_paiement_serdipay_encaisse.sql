-- ============================================================================
--  BIASHARA YANGU — MIGRATION 131
--  CRÉDITER UN PAIEMENT SERDIPAY DÉJÀ ENCAISSÉ MAIS RESTÉ « EN ATTENTE »
--  ---------------------------------------------------------------------------
--  SITUATION RÉELLE (10/11/2026)
--    Le client a payé depuis son téléphone, SerdiPay a DÉBITÉ son compte (il a
--    validé la demande avec son code PIN), mais l'abonnement n'a jamais été
--    crédité : la transaction est restée `en_attente` parce que le webhook ne
--    pouvait pas la traiter (erreur de type, puis `ACCES_REFUSE`).
--
--    L'argent est encaissé. Il ne faut donc SURTOUT PAS demander au client de
--    payer une seconde fois : il faut CRÉDITER ce qui a déjà été payé.
--
--  POURQUOI UNE FONCTION DÉDIÉE
--    `abonnement_ouvrir_avance_multi` (migration 127) calcule les cycles à
--    partir du prix ACTUEL. Or le tarif a changé depuis le paiement (le
--    supplément collaborateurs de la migration 128 est entré dans le prix) :
--         30 000 CDF payés  ÷  12 500 CDF actuels  =  2,4 cycles
--    … ce n'est pas un entier : ouvrir 3 cycles réclamerait 37 500 et le
--    moteur refuserait le paiement de 30 000 (`MONTANT_SUPERIEUR`).
--
--    Cette fonction part donc du MONTANT RÉELLEMENT PAYÉ :
--      • le total dû est figé à ce montant (aucun centime inventé) ;
--      • le nombre de jours suit ce que ce montant achète au prix de base
--        (30 000 ÷ 10 000 = 3 périodes → 90 jours) ;
--      • le crédit passe par `rpc_serdipay_confirmer`, donc par le moteur
--        habituel (journal, facture, dates) — aucune écriture sauvage.
--
--  SÉCURITÉ
--    • Depuis l'application : réservé à la plateforme.
--    • Depuis l'éditeur SQL (aucune session) : autorisé — c'est l'opérateur.
--    • Refuse une transaction sans référence SerdiPay (aucun argent n'a pu
--      être encaissé) et un compte SUSPENDU.
--
--  ⚠️ PRÉREQUIS : migrations 0127, 0128, 0129 et 0130 exécutées.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);


create or replace function public.abonnement_crediter_paiement_serdipay(
  p_reference text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_s      public.paiements_serdipay%rowtype;
  v_e      public.entreprises%rowtype;
  v_prix   numeric := 0;
  v_cycles integer := 1;
  v_res    jsonb;
begin
  -- Depuis l'application, seule la plateforme peut créditer.
  -- Depuis l'éditeur SQL, `auth.uid()` est nul : c'est l'opérateur.
  if auth.uid() is not null and not public.est_plateforme() then
    raise exception
      'ACCES_REFUSE|Seule la plateforme peut créditer un paiement SerdiPay.';
  end if;

  select * into v_s
    from public.paiements_serdipay
   where reference = btrim(p_reference)
     for update;

  if not found then
    raise exception 'REFERENCE_INCONNUE|Aucune transaction « % ».', p_reference;
  end if;

  -- Déjà créditée : on ne fait rien (idempotent).
  if v_s.statut = 'paye' then
    return jsonb_build_object(
      'ok', true,
      'deja', true,
      'reference', v_s.reference,
      'message', 'Cette transaction est déjà payée : aucun crédit supplémentaire.'
    );
  end if;

  -- Sans référence fournisseur, la demande n'a jamais été créée chez SerdiPay :
  -- aucun argent n'a pu être encaissé, il ne faut rien créditer.
  if coalesce(btrim(v_s.provider_reference), '') = '' then
    raise exception
      'TRANSACTION_NON_CHEZ_SERDIPAY|La transaction « % » n''a jamais reçu de référence SerdiPay : aucun encaissement n''a eu lieu. Vérifiez le tableau de bord SerdiPay avant de créditer.',
      v_s.reference;
  end if;

  select * into v_e
    from public.entreprises
   where id = v_s.entreprise_id
     for update;

  if not found then
    raise exception 'ENTREPRISE_INTROUVABLE';
  end if;

  if v_e.statut = 'SUSPENDU' then
    raise exception
      'COMPTE_SUSPENDU|Le compte « % » est suspendu : le paiement doit être traité par la plateforme, ce crédit ne lève pas la suspension.',
      v_e.nom;
  end if;

  -- Combien de périodes ce montant achète-t-il, au prix de base ?
  v_prix := coalesce(public.rpc_abonnement_prix_du_cycle(v_s.entreprise_id), 0);
  if v_prix <= 0 then
    raise exception
      'PRIX_ABSENT|Aucun prix de cycle pour « % » : créditez ce paiement manuellement après avoir fixé le tarif.',
      v_e.nom;
  end if;

  v_cycles := greatest(1, round(v_s.montant / v_prix)::integer);

  -- On FIGE exactement ce qui a été encaissé : ni plus, ni moins.
  update public.entreprises
     set montant_total_du = v_s.montant,
         montant_deja_paye = 0,
         cycles_prepayes = v_cycles,
         statut = 'EN_ATTENTE_COMPLEMENT'::public.statut_abonnement_enum,
         updated_at = now()
   where id = v_s.entreprise_id;

  -- Crédit réel par le moteur (dates, journal, facture).
  v_res := public.rpc_serdipay_confirmer(
    p_reference          => v_s.reference,
    p_statut             => 'paye',
    p_provider_reference => v_s.provider_reference,
    p_montant_recu       => v_s.montant,
    p_payload            => jsonb_build_object('source', 'recuperation_operateur')
  );

  return v_res || jsonb_build_object(
    'cycles', v_cycles,
    'prix_base', v_prix,
    'montant_credite', v_s.montant,
    'periodes_jours', v_cycles * 30
  );
end;
$$;

comment on function public.abonnement_crediter_paiement_serdipay(text) is
  'Migration 131 — crédite un paiement SerdiPay DÉJÀ ENCAISSÉ (référence '
  'fournisseur présente) resté en attente. Fige le montant réellement payé, '
  'en déduit le nombre de périodes et passe par le moteur habituel.';

revoke all on function public.abonnement_crediter_paiement_serdipay(text)
  from public, anon;
grant execute on function public.abonnement_crediter_paiement_serdipay(text)
  to authenticated, service_role;


-- ============================================================================
--  AIDE : QUELS PAIEMENTS ATTENDENT D'ÊTRE RÉCUPÉRÉS ?
-- ============================================================================
--  Ce sont exactement les paiements dont le client affirme avoir été débité :
--  SerdiPay a créé la transaction (référence fournisseur présente) mais notre
--  base n'a jamais pu la créditer.

select s.reference,
       e.nom                                   as entreprise,
       s.statut,
       s.montant,
       s.devise,
       s.operateur,
       s.provider_reference,
       s.created_at,
       round(s.montant
             / nullif(public.rpc_abonnement_prix_du_cycle(s.entreprise_id), 0)
            )::integer                         as cycles_a_crediter
  from public.paiements_serdipay s
  join public.entreprises e on e.id = s.entreprise_id
 where s.statut = 'en_attente'
   and coalesce(btrim(s.provider_reference), '') <> ''
 order by s.created_at desc;


-- ============================================================================
--  CONTRÔLE
-- ============================================================================

do $$
declare
  v_def text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname = 'abonnement_crediter_paiement_serdipay';

  if v_def is null then
    raise exception 'abonnement_crediter_paiement_serdipay introuvable après la migration.';
  end if;

  if position('rpc_serdipay_confirmer' in v_def) = 0 then
    raise exception
      'Migration 131 incomplète : le crédit ne passe pas par le moteur SerdiPay.';
  end if;

  raise notice
    'Migration 131 OK : un paiement déjà débité par SerdiPay peut être crédité au montant réellement payé, sans double facturation.';
end $$;
