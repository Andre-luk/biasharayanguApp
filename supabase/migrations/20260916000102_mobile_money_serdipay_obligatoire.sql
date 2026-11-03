-- =============================================================================
-- PAIEMENTS MOBILE MONEY — PASSAGE OBLIGATOIRE PAR SERDIPAY (garde-fous)
-- =============================================================================
-- Constat (audit) : le moteur d'abonnement, la validation finance et le
-- paiement des quotas IA acceptent un « mode de paiement » libre. Avec
-- `Mobile Money`, l'écriture était créditée IMMÉDIATEMENT — comme des
-- espèces — sans aucune transaction SerdiPay. C'est faux : un abonnement ne
-- peut être activé que si SerdiPay a réellement confirmé l'encaissement.
--
-- Ce que fait ce script (aucune donnée supprimée, aucune colonne modifiée) :
--   1. `mode_paiement_mobile_money(text)` : reconnaissance normalisée des
--      libellés (« Mobile Money », « MOBILE_MONEY », « M-Pesa », « Orange
--      Money », « Airtel Money », « MM »…).
--   2. Un TRIGGER sur `paiements_abonnements_laperle` : toute écriture dont
--      le mode est Mobile Money est REFUSÉE tant qu'il n'existe pas, pour la
--      même entreprise et le même montant, une transaction SerdiPay en attente
--      POURVUE de sa référence fournisseur (`provider_reference`).
--      → Un clic sur « Mobile Money » sans passer par la passerelle échoue.
--      → Le webhook SerdiPay, lui, passe : la transaction existe déjà, créée
--        par `rpc_serdipay_ouvrir` puis `rpc_serdipay_definir_lien`.
--   3. Le même garde-fou sur `agent_ia_achats` quand le statut de paiement
--      passe à `paye` avec un mode Mobile Money.
--
-- ⚠️ Les paiements en ESPÈCES ne sont pas touchés : ils gardent leur circuit
--    (caisse, validation, historique) et ne passent jamais par SerdiPay.
-- ⚠️ Les ventes au comptoir (module 10) ne sont pas concernées : l'argent y
--    est reçu par le commerçant, pas par la plateforme.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Reconnaissance normalisée du mode « Mobile Money »
-- -----------------------------------------------------------------------------
create or replace function public.mode_paiement_mobile_money(p_mode text)
returns boolean
language sql
immutable
as $$
  select translate(upper(btrim(coalesce(p_mode, ''))), ' -/ ', '____')
         in ('MOBILE_MONEY', 'MOBILEMONEY', 'M_PESA', 'MPESA',
             'ORANGE_MONEY', 'ORANGEMONEY', 'AIRTEL_MONEY', 'AIRTELMONEY',
             'MM', 'MONEY', 'MOBILE');
$$;

comment on function public.mode_paiement_mobile_money(text) is
  'Vrai si le libellé de mode de paiement désigne un paiement Mobile Money (donc SerdiPay obligatoire).';

grant execute on function public.mode_paiement_mobile_money(text)
  to authenticated, anon;

-- -----------------------------------------------------------------------------
-- 2. Abonnements : interdiction d'un encaissement Mobile Money hors SerdiPay
-- -----------------------------------------------------------------------------
create or replace function public.paiement_mm_exige_serdipay()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.mode_paiement_mobile_money(new.mode_paiement) then
    return new;
  end if;

  -- Une transaction SerdiPay doit exister pour CETTE entreprise, ce MONTANT,
  -- et avoir reçu sa référence fournisseur (donc avoir été réellement créée
  -- chez SerdiPay). Le client ne peut pas fabriquer une telle ligne.
  if not exists (
    select 1
      from public.paiements_serdipay ps
     where ps.entreprise_id = new.entreprise_id
       and ps.statut = 'en_attente'
       and ps.provider_reference is not null
       and abs(ps.montant - new.montant) < 0.01
  ) then
    raise exception 'MOBILE_MONEY_SERDIPAY|Les paiements Mobile Money passent OBLIGATOIREMENT par SerdiPay : aucun encaissement Mobile Money manuel n''est accepté. Utilisez « Payer par Mobile Money ».';
  end if;

  return new;
end;
$$;

revoke all on function public.paiement_mm_exige_serdipay()
  from public, anon, authenticated;

drop trigger if exists trg_paiement_mm_serdipay
  on public.paiements_abonnements_laperle;
create trigger trg_paiement_mm_serdipay
  before insert on public.paiements_abonnements_laperle
  for each row execute function public.paiement_mm_exige_serdipay();

-- -----------------------------------------------------------------------------
-- 3. Quotas IA : même règle quand le paiement passe à « paye »
-- -----------------------------------------------------------------------------
create or replace function public.achat_quota_mm_exige_serdipay()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- On ne contrôle que le passage impaye → paye.
  if new.statut_paiement <> 'paye' then
    return new;
  end if;
  if tg_op = 'UPDATE' and old.statut_paiement = 'paye' then
    return new;
  end if;

  if not public.mode_paiement_mobile_money(new.mode_paiement) then
    return new;
  end if;

  if new.entreprise_id is null then
    raise exception 'MOBILE_MONEY_SERDIPAY|Aucune entreprise rattachée à cet achat : le paiement Mobile Money doit passer par SerdiPay.';
  end if;

  if not exists (
    select 1
      from public.paiements_serdipay ps
     where ps.entreprise_id = new.entreprise_id
       and ps.statut = 'en_attente'
       and ps.provider_reference is not null
       and abs(ps.montant - new.montant_cdf) < 1
  ) then
    raise exception 'MOBILE_MONEY_SERDIPAY|Les quotas IA achetés par Mobile Money ne peuvent être crédités qu''après confirmation de SerdiPay.';
  end if;

  return new;
end;
$$;

revoke all on function public.achat_quota_mm_exige_serdipay()
  from public, anon, authenticated;

drop trigger if exists trg_achat_quota_mm_serdipay
  on public.agent_ia_achats;
create trigger trg_achat_quota_mm_serdipay
  before insert or update of statut_paiement on public.agent_ia_achats
  for each row execute function public.achat_quota_mm_exige_serdipay();

-- =============================================================================
-- 4. Vue d'audit pour le Super Admin (lecture seule)
-- =============================================================================
-- Les transactions Mobile Money et leur devenir, sans jamais permettre de les
-- transformer en paiement réussi depuis l'interface.
create or replace view public.v_serdipay_audit as
select
  ps.id,
  ps.reference,
  ps.provider_reference,
  ps.entreprise_id,
  e.nom                     as entreprise_nom,
  ps.utilisateur_id,
  u.email                   as utilisateur_email,
  ps.objet,
  ps.objet_id,
  ps.montant,
  ps.devise,
  ps.statut,
  ps.type_paiement,
  ps.telephone,
  ps.operateur,
  ps.paye_le,
  ps.expire_le,
  ps.created_at,
  ps.mis_a_jour_le,
  ps.motif_echec
from public.paiements_serdipay ps
left join public.entreprises e on e.id = ps.entreprise_id
left join public.utilisateurs u on u.id = ps.utilisateur_id;

comment on view public.v_serdipay_audit is
  'Super Admin — toutes les transactions SerdiPay (lecture seule) : montants, entreprises, statuts, erreurs.';

grant select on public.v_serdipay_audit to authenticated;

-- =============================================================================
-- FIN — garde-fous Mobile Money
-- =============================================================================
