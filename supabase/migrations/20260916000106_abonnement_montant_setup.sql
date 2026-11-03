-- =============================================================================
-- ABONNEMENT — LE MONTANT DÛ EXISTE DÈS LA CRÉATION « SETUP » (0106)
-- =============================================================================
-- Constat (boutique créée depuis « setup ») :
--   • l'écran de renouvellement affichait « montant à régler 0 CDF » et le
--     paiement Mobile Money refusait la transaction (SOLDE_NUL), parce que
--     `rpc_entreprise_creer_simple` écrivait `montant_total_du = 0` ;
--   • l'abonnement semblait « non calculé » alors que l'essai de 7 jours est
--     actif : à la fin de l'essai, il n'y avait aucun solde à réclamer.
--
-- Correction : l'essai reste ACTIF 7 jours (aucun blocage), mais le MONTANT DÛ
-- est immédiatement celui de la grille tarifaire de l'entreprise
-- (`groupes_tarifaires.montant_abonnement`, 20 000 CDF pour la distribution).
-- L'écran de renouvellement, la passerelle SerdiPay et la caisse travaillent
-- donc sur un montant réel dès le premier jour.
--
-- Les entreprises DÉJÀ créées en mode simple avec 0 CDF sont réparées par la
-- section 3 (même règle, uniquement pour les comptes en essai et à 0).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Création « setup » : montant dû = prix de la grille
-- -----------------------------------------------------------------------------
create or replace function public.rpc_entreprise_creer_simple(
  p_nom       text default null,
  p_telephone text default null,
  p_type      text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user  uuid := auth.uid();
  v_res   jsonb;
  v_id    uuid;
  v_deja  boolean;
  v_fin   timestamptz := now() + interval '7 days';
  v_prix  numeric := 0;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour créer votre entreprise.';
  end if;

  -- Création standard (nom, type validé, espace, rattachement, rôle).
  v_res := public.rpc_entreprise_creer(
    p_nom,
    p_telephone,
    coalesce(nullif(btrim(coalesce(p_type, '')), ''), 'boutique')
  );

  v_id := nullif(v_res->>'entreprise_id', '')::uuid;
  v_deja := coalesce((v_res->>'deja')::boolean, false);

  if v_id is null then
    raise exception 'CREATION_IMPOSSIBLE|L''entreprise n''a pas pu être créée.';
  end if;

  -- Déjà rattaché : on ne modifie pas un dossier existant (il garde son
  -- état d'activation et son abonnement en cours).
  if v_deja then
    return v_res || jsonb_build_object('mode', 'simple', 'essai', false);
  end if;

  -- Prix de l'abonnement : celui préparé sur l'entreprise
  -- (`entreprises.prix_installation`, écrit à la création depuis la grille),
  -- sinon le prix du cycle de la grille (`groupes_tarifaires.montant_abonnement`,
  -- 20 000 CDF pour la distribution). 0 seulement si aucune grille : on
  -- n'invente jamais un prix.
  select coalesce(
           nullif(e.prix_installation, 0),
           nullif(g.montant_abonnement, 0),
           0)
    into v_prix
    from public.entreprises e
    left join public.groupes_tarifaires g on g.id = e.groupe_tarifaire_id
   where e.id = v_id;

  v_prix := coalesce(v_prix, 0);

  -- MODE SIMPLE : l'essai de 7 jours est ACTIF tout de suite. Le compte peut
  -- vendre, encaisser et créer ses produits immédiatement. Le MONTANT DÛ est
  -- renseigné (il sera réclamé à l'échéance), mais rien n'est encaissé.
  update public.entreprises
     set activation_etape = 'actif',
         statut = 'ESSAI_7J'::public.statut_abonnement_enum,
         date_activation = now(),
         date_expiration = v_fin,
         montant_total_du = v_prix,
         montant_deja_paye = 0,
         updated_at = now()
   where id = v_id;

  -- Traçabilité du dossier : la soumission reste, l'activation automatique
  -- est ajoutée en clair (un auditeur doit pouvoir expliquer l'exception).
  begin
    insert into public.activations_entreprise (
      entreprise_id, etape, acteur_id, acteur_role, note
    ) values (
      v_id, 'paiement_finance', v_user, public.mon_role(),
      'Activation AUTOMATIQUE — mode simple (essai 7 jours, montant dû préparé)'
    );
  exception when others then
    -- Une table d'historique absente ne doit pas priver le commerçant de
    -- son entreprise : l'état de `entreprises` fait foi.
    null;
  end;

  begin
    insert into public.journal_audit (entreprise_id, action, utilisateur_id, details)
    values (
      null, 'ACTIVATION_AUTO_ESSAI', v_user,
      jsonb_build_object(
        'entreprise_id', v_id,
        'mode', 'simple',
        'essai_jours', 7,
        'date_expiration', v_fin,
        'montant_total_du', v_prix
      )
    );
  exception when others then null;
  end;

  return v_res || jsonb_build_object(
    'mode', 'simple',
    'essai', true,
    'essai_jours', 7,
    'date_expiration', v_fin,
    'activation_etape', 'actif',
    'montant_total_du', v_prix
  );
end;
$$;

comment on function public.rpc_entreprise_creer_simple(text, text, text) is
  'Mode setup — essai 7 jours actif + montant dû de la grille renseigné dès la création (0106).';

grant execute on function public.rpc_entreprise_creer_simple(text, text, text)
  to authenticated;

-- -----------------------------------------------------------------------------
-- 2. Réparation des entreprises créées AVANT ce correctif
-- -----------------------------------------------------------------------------
-- Uniquement : comptes en essai, jamais payés, montant dû à 0.
-- Aucun compte actif/payé/suspendu n'est touché.
do $$
declare
  v_lignes integer := 0;
begin
  with cible as (
    select e.id,
           coalesce(
             nullif(e.prix_installation, 0),
             nullif(g.montant_abonnement, 0),
             0) as prix
      from public.entreprises e
      left join public.groupes_tarifaires g on g.id = e.groupe_tarifaire_id
     where e.statut = 'ESSAI_7J'
       and coalesce(e.montant_total_du, 0) = 0
       and coalesce(e.montant_deja_paye, 0) = 0
  )
  update public.entreprises e
     set montant_total_du = c.prix,
         updated_at = now()
    from cible c
   where e.id = c.id
     and c.prix > 0;

  get diagnostics v_lignes = row_count;
  raise notice 'Essais réparés (montant dû renseigné) : %', v_lignes;
end $$;

-- -----------------------------------------------------------------------------
-- 3. Contrôle
-- -----------------------------------------------------------------------------
-- select id, nom, statut, montant_total_du, montant_deja_paye, solde_restant
--   from public.entreprises
--  where statut = 'ESSAI_7J'
--  order by created_at desc
--  limit 10;

-- =============================================================================
-- FIN — le montant dû existe dès la création setup
-- =============================================================================
