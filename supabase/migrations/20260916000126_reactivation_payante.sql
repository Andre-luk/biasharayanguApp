-- ============================================================================
--  BIASHARA YANGU — MIGRATION 126
--  LA RÉACTIVATION D'UN ABONNEMENT DEVIENT PAYANTE (Mobile Money / SerdiPay)
--  ---------------------------------------------------------------------------
--  PROBLÈME RÉEL (10/11/2026)
--    Le bouton « Réactiver l'abonnement » de la fiche abonnement appelait
--    `rpc_abonnement_reactiver`. Cette fonction se contentait de vérifier que
--    le solde était nul, puis repoussait la date d'expiration de 30 jours
--    SANS ENCAISSER UN FRANC. Un clic = un mois offert, sans aucune trace
--    d'argent. C'est le seul chemin du produit où un abonnement se prolonge
--    sans paiement.
--
--  NOUVELLE RÈGLE — UN SEUL PRINCIPE : L'ARGENT D'ABORD
--    Réactiver = vendre le cycle suivant. La fonction exige donc une PREUVE
--    DE PAIEMENT POSTÉRIEURE À L'ÉCHÉANCE :
--      • une transaction SerdiPay `paye` (Mobile Money réellement encaissé) ;
--      • ou un versement du moteur enregistré après cette même échéance
--        (espèces ou Mobile Money saisi par la Finance / l'agent).
--    Sans preuve : refus explicite, ZÉRO jour accordé.
--
--    Les jours offerts restent possibles, mais seulement par une action
--    délibérée et tracée : `abonnement_geste_commercial()` (Super Admin,
--    motif obligatoire, inscrite au journal d'audit).
--
--  ⚠️ AUCUNE PUBLICATION D'APPLICATION N'EST NÉCESSAIRE : tout est appliqué
--     côté serveur. L'écran actuel affichera « Le moteur d'abonnement a
--     refusé l'opération. » — c'est VOULU : plus aucun mois gratuit. La
--     version suivante de l'application remplacera ce bouton par un
--     encaissement Mobile Money (aucun client n'a à réinstaller pour que
--     l'argent soit protégé).
--
--  ORDRE D'EXÉCUTION : après 20260916000124 et 20260916000125.
--  ⚠️ Supabase Dashboard → SQL Editor → New query → coller → Run.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);


-- ============================================================================
--  0. PRÉ-CONTRÔLES — de quoi dépend cette migration ?
-- ============================================================================

do $$
begin
  if to_regclass('public.entreprises') is null
     or to_regclass('public.paiements_abonnements_laperle') is null then
    raise exception 'Module 3 absent : exécutez 20260916000003_module3_abonnement.sql.';
  end if;

  if to_regclass('public.paiements_serdipay') is null then
    raise exception 'Passerelle absente : exécutez 20260916000079_passerelle_serdipay.sql.';
  end if;

  if to_regprocedure('public.rpc_abonnement_prix_du_cycle(uuid)') is null then
    raise exception 'Prix du cycle absent : exécutez 20260916000090_mode_simple_abonnement_obligatoire.sql.';
  end if;
end $$;


-- ============================================================================
--  1. RÉACTIVATION — EXIGE UN PAIEMENT RÉEL DU CYCLE QUI COMMENCE
-- ============================================================================
--  Même signature qu'avant (l'application appelle avec 1 argument) : aucun
--  écran ne casse, c'est le COMPORTEMENT qui devient strict.

create or replace function public.rpc_abonnement_reactiver(
  p_entreprise_id uuid
)
returns public.entreprises
language plpgsql
security definer
set search_path = public
as $$
declare
  v_entreprise public.entreprises;
  v_duree      integer := 30;
  v_base       timestamptz;
  v_echeance   timestamptz;
  v_prix       numeric := 0;
  v_argent     numeric := 0;
  v_ref        text;
  v_devise     text;
begin
  if not public.a_permission(public.mon_role(), 'paiements', 'valider') then
    raise exception 'ACCES_REFUSE';
  end if;

  if p_entreprise_id is null then
    raise exception 'ENTREPRISE_INTROUVABLE';
  end if;

  select * into v_entreprise
    from public.entreprises
   where id = p_entreprise_id
   for update;

  if not found then
    raise exception 'ENTREPRISE_INTROUVABLE';
  end if;

  -- Un cycle encore en cours de règlement doit d'abord être soldé.
  if coalesce(v_entreprise.solde_restant, 0) > 0 then
    raise exception 'SOLDE_RESTANT';
  end if;

  v_devise := coalesce(nullif(btrim(v_entreprise.devise), ''), 'CDF');

  -- Fin de la période écoulée : tout argent postérieur est une preuve.
  v_echeance := coalesce(
    v_entreprise.date_expiration,
    v_entreprise.date_activation,
    '-infinity'::timestamptz
  );

  v_prix := coalesce(public.rpc_abonnement_prix_du_cycle(p_entreprise_id), 0);

  -- ── 1️⃣ PREUVE LA PLUS FORTE : MOBILE MONEY CONFIRMÉ PAR SERDIPAY ────────
  select coalesce(sum(ps.montant), 0), min(ps.reference)
    into v_argent, v_ref
    from public.paiements_serdipay ps
   where ps.entreprise_id::text = p_entreprise_id::text
     and ps.statut = 'paye'
     and ps.paye_le is not null
     and ps.paye_le > v_echeance;

  -- ── 2️⃣ À DÉFAUT : VERSEMENT DU MOTEUR (espèces / Mobile Money saisi) ─────
  if coalesce(v_argent, 0) <= 0 then
    select coalesce(sum(p.montant), 0)
      into v_argent
      from public.paiements_abonnements_laperle p
     where p.entreprise_id::text = p_entreprise_id::text
       and p.created_at > v_echeance;

    v_ref := null;
  end if;

  v_argent := coalesce(v_argent, 0);

  -- ── 3️⃣ SANS PAIEMENT, AUCUN JOUR N'EST ACCORDÉ ───────────────────────────
  if v_argent <= 0 or (v_prix > 0 and v_argent + 0.01 < v_prix) then
    raise exception
      'REACTIVATION_PAYANTE|La réactivation ouvre un NOUVEAU cycle : elle exige un paiement réel de % %. Aucun règlement postérieur à l''échéance n''a été trouvé. Faites payer le client par Mobile Money (SerdiPay) depuis sa fiche, ou encaissez avec « Enregistrer un paiement ». Pour offrir des jours, utilisez abonnement_geste_commercial().',
      round(v_prix, 2), v_devise;
  end if;

  -- ── 4️⃣ LE PAIEMENT EXISTE : on prolonge (comme avant) ────────────────────
  select coalesce(g.duree_abonnement_jours, 30)
    into v_duree
    from public.groupes_tarifaires g
   where g.id = v_entreprise.groupe_tarifaire_id;
  v_duree := coalesce(v_duree, 30);

  v_base := greatest(coalesce(v_entreprise.date_expiration, now()), now());

  update public.entreprises
     set statut          = 'ACTIF'::public.statut_abonnement_enum,
         date_activation = coalesce(date_activation, now()),
         date_expiration = v_base + make_interval(days => v_duree),
         updated_at      = now()
   where id = p_entreprise_id
   returning * into v_entreprise;

  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(),
    p_entreprise_id,
    'REACTIVATION_PAYANTE',
    auth.uid(),
    jsonb_build_object(
      'date_expiration', v_entreprise.date_expiration,
      'duree_jours', v_duree,
      'prix_cycle', v_prix,
      'montant_constate', v_argent,
      'preuve_serdipay', v_ref,
      'role', public.mon_role()
    ),
    now()
  );

  return v_entreprise;
end;
$$;

comment on function public.rpc_abonnement_reactiver(uuid) is
  'Migration 126 — réactivation PAYANTE : exige une transaction SerdiPay payée '
  '(Mobile Money) ou un versement postérieur à l''échéance. Aucun jour gratuit.';


-- ============================================================================
--  2. JOURS OFFERTS — ACTION DÉLIBÉRÉE, TRACÉE, RÉSERVÉE AU SUPER ADMIN
-- ============================================================================
--  Remplace l'ancien mois gratuit « par accident ». Volontairement séparée :
--  un geste commercial doit être un choix explicite, avec un motif écrit.

create or replace function public.abonnement_geste_commercial(
  p_entreprise_id uuid,
  p_jours         integer default 30,
  p_motif         text default null
)
returns public.entreprises
language plpgsql
security definer
set search_path = public
as $$
declare
  v_entreprise public.entreprises;
  v_jours      integer;
  v_motif      text := nullif(btrim(coalesce(p_motif, '')), '');
begin
  if not public.est_super_admin() then
    raise exception
      'ACCES_REFUSE|Seul le super administrateur peut offrir des jours d''abonnement.';
  end if;

  if p_entreprise_id is null then
    raise exception 'ENTREPRISE_INTROUVABLE';
  end if;

  if v_motif is null or length(v_motif) < 5 then
    raise exception
      'MOTIF_REQUIS|Indiquez le motif du geste commercial (5 caractères minimum) : il est inscrit au journal d''audit.';
  end if;

  v_jours := greatest(1, least(coalesce(p_jours, 30), 365));

  select * into v_entreprise
    from public.entreprises
   where id = p_entreprise_id
   for update;

  if not found then
    raise exception 'ENTREPRISE_INTROUVABLE';
  end if;

  update public.entreprises
     set statut          = 'ACTIF'::public.statut_abonnement_enum,
         date_activation = coalesce(date_activation, now()),
         date_expiration = greatest(coalesce(date_expiration, now()), now())
                           + make_interval(days => v_jours),
         updated_at      = now()
   where id = p_entreprise_id
   returning * into v_entreprise;

  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(),
    p_entreprise_id,
    'GESTE_COMMERCIAL',
    auth.uid(),
    jsonb_build_object(
      'jours_offerts', v_jours,
      'motif', v_motif,
      'date_expiration', v_entreprise.date_expiration,
      'role', public.mon_role()
    ),
    now()
  );

  return v_entreprise;
end;
$$;

comment on function public.abonnement_geste_commercial(uuid, integer, text) is
  'Migration 126 — offre N jours (1..365) de façon DÉLIBÉRÉE et TRACÉE. '
  'Super Admin uniquement, motif obligatoire. Remplace l''ancien mois gratuit accidentel.';

revoke all on function public.abonnement_geste_commercial(uuid, integer, text)
  from public, anon;
grant execute on function public.abonnement_geste_commercial(uuid, integer, text)
  to authenticated, service_role;


-- ============================================================================
--  3. CONTRÔLES
-- ============================================================================

do $$
declare
  v_def      text;
  v_mm       boolean;
  v_refus    boolean;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname = 'rpc_abonnement_reactiver'
     and pg_get_function_identity_arguments(p.oid) = 'p_entreprise_id uuid';

  if v_def is null then
    raise exception 'rpc_abonnement_reactiver(uuid) est introuvable après la migration.';
  end if;

  v_mm := position('paiements_serdipay' in v_def) > 0;
  v_refus := position('REACTIVATION_PAYANTE' in v_def) > 0;

  if not v_mm or not v_refus then
    raise exception
      'Migration 126 incomplète : preuve SerdiPay=% (attendu true), refus=% (attendu true).',
      v_mm, v_refus;
  end if;

  raise notice 'Migration 126 OK : la réactivation exige désormais un paiement réel (SerdiPay / versement) et les jours offerts passent par abonnement_geste_commercial().';
end $$;

-- Une seule signature pour la réactivation (attendu : 1 ligne).
select p.oid::regprocedure::text as fonction,
       pg_get_function_identity_arguments(p.oid) as arguments
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname = 'rpc_abonnement_reactiver';

-- Les triggers Mobile Money sont-ils toujours en place ? (attendu : 2 lignes)
select event_object_table as table_cible, trigger_name
  from information_schema.triggers
 where trigger_schema = 'public'
   and trigger_name in ('trg_paiement_mm_serdipay', 'trg_achat_quota_mm_serdipay')
 order by table_cible;
