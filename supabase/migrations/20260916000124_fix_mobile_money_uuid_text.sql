-- ============================================================================
--  biashara_yangu — CORRECTIF 44 : « operator does not exist: uuid = text »
--  sur le paiement Mobile Money d'un abonnement (renouvellement).
--  ---------------------------------------------------------------------------
--  SYMPTÔME SIGNALÉ
--    Un client (Urembo Market) paie son abonnement en espèces : OK.
--    Le même renouvellement par MOBILE MONEY échoue sur :
--        operator does not exist: uuid = text
--
--  D'OÙ VIENT CETTE ERREUR
--    PostgreSQL refuse de comparer deux colonnes de types différents.
--    Dans le chemin Mobile Money, deux fonctions de contrôle (introduites par
--    la migration 0102) comparent l'identifiant de l'entreprise du paiement
--    à celui de la transaction SerdiPay :
--
--        where ps.entreprise_id = new.entreprise_id      -- uuid = ??? 
--
--    Si la table historique `paiements_abonnements_laperle` a été créée
--    autrefois avec un `entreprise_id` en TEXTE (ce projet a des tables
--    héritées), la comparaison devient `uuid = text` et TOUT paiement Mobile
--    Money est refusé — alors que le paiement en espèces, lui, sort de la
--    fonction avant cette comparaison.
--
--  CE QUE FAIT CE SCRIPT
--    1. Réécrit les deux garde-fous avec une comparaison INDÉPENDANTE DES
--       TYPES (`::text` des deux côtés) : le contrôle reste EXACTEMENT le
--       même (« une transaction SerdiPay en attente, du bon montant, pour
--       cette entreprise »), mais il ne casse plus sur un type hérité.
--    2. Affiche, à la fin, le TYPE RÉEL des colonnes concernées : c'est la
--       preuve permettant de savoir si la table historique est en texte.
--
--  ⚠️ IDEMPOTENT — peut être rejoué. Aucune donnée modifiée.
--  📌 OÙ L'EXÉCUTER : éditeur SQL de Supabase.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);


-- ============================================================================
--  1. GARDE-FOU DES PAIEMENTS D'ABONNEMENT
-- ============================================================================

create or replace function public.paiement_mm_exige_serdipay()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Seuls les paiements Mobile Money sont concernés.
  if not public.mode_paiement_mobile_money(new.mode_paiement) then
    return new;
  end if;

  if new.entreprise_id is null then
    raise exception 'MOBILE_MONEY_SERDIPAY|Aucune entreprise rattachée à ce paiement : le paiement Mobile Money doit passer par SerdiPay.';
  end if;

  -- Une transaction SerdiPay doit exister pour CETTE entreprise, ce MONTANT,
  -- et avoir reçu sa référence fournisseur (donc avoir été réellement créée
  -- chez SerdiPay).
  --
  -- ⚠️ CORRECTIF 44 : comparaison en TEXTE des deux côtés. `paiements_serdipay`
  --    est en uuid ; la table historique des paiements peut être en texte.
  --    Sans ce `::text`, PostgreSQL lève « operator does not exist: uuid = text »
  --    et le client ne peut JAMAIS payer par Mobile Money.
  if not exists (
    select 1
      from public.paiements_serdipay ps
     where ps.entreprise_id::text = new.entreprise_id::text
       and ps.statut = 'en_attente'
       and ps.provider_reference is not null
       and abs(ps.montant - new.montant) < 0.01
  ) then
    raise exception 'MOBILE_MONEY_SERDIPAY|Les paiements Mobile Money passent OBLIGATOIREMENT par SerdiPay : aucun encaissement Mobile Money manuel n''est accepté. Utilisez « Payer par Mobile Money ».';
  end if;

  return new;
end;
$$;

comment on function public.paiement_mm_exige_serdipay() is
  'Module 27/Correctif 44 — un encaissement Mobile Money d''abonnement exige une transaction SerdiPay en attente (comparaison tolérante aux types hérités).';

revoke all on function public.paiement_mm_exige_serdipay()
  from public, anon, authenticated;

drop trigger if exists trg_paiement_mm_serdipay
  on public.paiements_abonnements_laperle;
create trigger trg_paiement_mm_serdipay
  before insert on public.paiements_abonnements_laperle
  for each row execute function public.paiement_mm_exige_serdipay();


-- ============================================================================
--  2. GARDE-FOU DES ACHATS DE QUOTAS IA
-- ============================================================================

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

  -- ⚠️ CORRECTIF 44 — même précaution de type que ci-dessus.
  if not exists (
    select 1
      from public.paiements_serdipay ps
     where ps.entreprise_id::text = new.entreprise_id::text
       and ps.statut = 'en_attente'
       and ps.provider_reference is not null
       and abs(ps.montant - new.montant_cdf) < 1
  ) then
    raise exception 'MOBILE_MONEY_SERDIPAY|Les quotas IA achetés par Mobile Money ne peuvent être crédités qu''après confirmation de SerdiPay.';
  end if;

  return new;
end;
$$;

comment on function public.achat_quota_mm_exige_serdipay() is
  'Module 27/Correctif 44 — un achat de quotas IA par Mobile Money exige une transaction SerdiPay confirmée (comparaison tolérante aux types).';

revoke all on function public.achat_quota_mm_exige_serdipay()
  from public, anon, authenticated;

drop trigger if exists trg_achat_quota_mm_serdipay
  on public.agent_ia_achats;
create trigger trg_achat_quota_mm_serdipay
  before insert or update of statut_paiement on public.agent_ia_achats
  for each row execute function public.achat_quota_mm_exige_serdipay();


-- ============================================================================
--  3. DIAGNOSTIC — LES TYPES RÉELS DES COLONNES EN CAUSE
-- ============================================================================
--  Cette requête ne modifie rien : elle dit simplement si une table héritée
--  est bien en TEXTE (ce qui explique l'erreur d'origine).

select table_name, column_name, data_type
  from information_schema.columns
 where table_schema = 'public'
   and (
        (table_name = 'paiements_serdipay'            and column_name = 'entreprise_id')
     or (table_name = 'paiements_abonnements_laperle' and column_name = 'entreprise_id')
     or (table_name = 'agent_ia_achats'               and column_name = 'entreprise_id')
     or (table_name = 'entreprises'                   and column_name = 'id')
       )
 order by table_name;


-- ============================================================================
--  VÉRIFICATIONS
-- ============================================================================

-- V1. Les deux garde-fous comparent désormais en texte (attendu : true, true).
select position('entreprise_id::text' in pg_get_functiondef(
         'public.paiement_mm_exige_serdipay()'::regprocedure)) > 0
         as garde_paiement_corrige,
       position('entreprise_id::text' in pg_get_functiondef(
         'public.achat_quota_mm_exige_serdipay()'::regprocedure)) > 0
         as garde_quota_corrige;

-- V2. Les deux triggers sont bien en place (attendu : 2 lignes).
select event_object_table as table_cible, trigger_name
  from information_schema.triggers
 where trigger_schema = 'public'
   and trigger_name in ('trg_paiement_mm_serdipay', 'trg_achat_quota_mm_serdipay')
 order by table_cible;
