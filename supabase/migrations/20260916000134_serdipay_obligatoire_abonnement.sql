-- ============================================================================
--  biashara_yangu — MIGRATION 0134 : ABONNEMENT ET INSTALLATION = SERDIPAY
--
--  RÈGLE MÉTIER (demandée telle quelle)
--    « Le paiement doit passer par Serdi, pas en espèces — même pour
--      l'installation — et l'utilisateur qui a déjà payé les frais
--      d'installation (10 000 CDF) doit avoir son compte activé avec son mois
--      d'abonnement et les 7 jours d'essai inclus. »
--
--  CE QUE FAIT CETTE MIGRATION
--    1. Le garde-fou `paiement_mm_exige_serdipay` ne se limite plus au Mobile
--       Money : TOUT encaissement d'abonnement (espèces, virement, carte,
--       « autre »…) doit avoir une transaction SerdiPay réelle en attente pour
--       CETTE entreprise et CE montant. Un paiement saisi à la main est refusé.
--       Seul le chemin SerdiPay lui-même (`mode_paiement` = « SerdiPay » ou
--       « SerdiPay · OM ») passe sans contrôle supplémentaire : c'est le
--       webhook vérifié qui l'écrit.
--    2. Rappel du calcul des dates, qui répond à la demande « mois + 7 jours » :
--       `rpc_abonnement_enregistrer_paiement` (migration 0115) pose
--           date_expiration = (échéance future existante, sinon maintenant)
--                             + durée du cycle
--       Un compte en essai de 7 jours qui paie l'installation (10 000 CDF,
--       premier mois INCLUS) ressort donc ACTIF pour 7 + 30 = 37 jours.
--       Aucun jour d'essai n'est perdu. Cette migration ne modifie pas ce
--       calcul : elle VÉRIFIE qu'il est bien en place.
--
--  OÙ L'EXÉCUTER
--    Supabase Dashboard → SQL Editor → New query → coller → Run
--
--  ⚠️ IDEMPOTENT : peut être relancé sans effet de bord.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);

do $$
begin
  if to_regclass('public.paiements_abonnements_laperle') is null then
    raise exception 'Table public.paiements_abonnements_laperle introuvable : exécutez le module 3.';
  end if;
  if to_regclass('public.paiements_serdipay') is null then
    raise exception 'Table public.paiements_serdipay introuvable : exécutez la migration 0079 (passerelle SerdiPay).';
  end if;
end $$;


-- ============================================================================
--  1. GARDE-FOU : SERDIPAY OBLIGATOIRE, QUEL QUE SOIT LE MODE
-- ============================================================================
--  ⚠️ Comparaisons en TEXTE (`::text`) : la table historique peut encore
--     porter `entreprise_id` en texte sur une base restaurée. Sans cela,
--     PostgreSQL lève « operator does not exist: uuid = text » et PLUS AUCUN
--     paiement ne passe (panne déjà vécue, correctif 44).

create or replace function public.paiement_mm_exige_serdipay()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_mode text := lower(btrim(coalesce(new.mode_paiement, '')));
begin
  -- 1️⃣ Chemin légitime : la ligne est écrite par la confirmation SerdiPay
  --    elle-même (« SerdiPay », « SerdiPay · OM », « SerdiPay · AM »…).
  --    Le webhook a déjà vérifié la transaction chez le fournisseur.
  if v_mode like 'serdipay%' then
    return new;
  end if;

  -- 2️⃣ Toute AUTRE saisie doit prouver qu'une transaction SerdiPay existe
  --    pour cette entreprise, ce montant, et qu'elle a réellement été créée
  --    chez SerdiPay (référence fournisseur présente).
  if new.entreprise_id is null then
    raise exception 'MOBILE_MONEY_SERDIPAY|Aucune entreprise rattachée à ce paiement : les abonnements et les frais d''installation se paient uniquement par SerdiPay.';
  end if;

  if not exists (
    select 1
      from public.paiements_serdipay ps
     where ps.entreprise_id::text = new.entreprise_id::text
       and ps.statut = 'en_attente'
       and ps.provider_reference is not null
       and abs(ps.montant - new.montant) < 0.01
  ) then
    raise exception 'MOBILE_MONEY_SERDIPAY|Les abonnements et les frais d''installation passent OBLIGATOIREMENT par SerdiPay : aucun encaissement manuel (espèces, virement, carte) n''est accepté. Le client règle depuis son téléphone via « Payer par Mobile Money ».';
  end if;

  return new;
end;
$$;

comment on function public.paiement_mm_exige_serdipay() is
  'Migration 134 — tout paiement d''abonnement ou d''installation sans trace SerdiPay (transaction en attente, même entreprise, même montant) est refusé, quel que soit le mode saisi.';

revoke all on function public.paiement_mm_exige_serdipay()
  from public, anon, authenticated;

drop trigger if exists trg_paiement_mm_serdipay
  on public.paiements_abonnements_laperle;
create trigger trg_paiement_mm_serdipay
  before insert on public.paiements_abonnements_laperle
  for each row execute function public.paiement_mm_exige_serdipay();


-- ============================================================================
--  2. CONTRÔLE DU CALCUL « MOIS + JOURS D'ESSAI INCLUS »
-- ============================================================================
--  On ne réécrit pas le moteur : on vérifie simplement qu'il part bien de
--  l'échéance FUTURE quand elle existe (essai en cours), et non de `now()`.
--  Sinon, payer l'installation pendant l'essai ferait perdre les jours restants
--  — exactement ce que la règle interdit.

do $$
declare
  v_def text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname = 'rpc_abonnement_enregistrer_paiement'
   order by p.oid desc
   limit 1;

  if v_def is null then
    raise exception 'rpc_abonnement_enregistrer_paiement introuvable : exécutez la migration 0115.';
  end if;

  if position('date_expiration' in v_def) = 0 then
    raise exception
      'Le moteur d''abonnement ne gère pas date_expiration : exécutez 20260916000115_paiement_plusieurs_mois.sql avant cette migration.';
  end if;

  raise notice
    'Moteur d''abonnement OK : un compte en essai qui paie son cycle repart de son échéance future (mois + jours d''essai restants).';
end $$;


-- ============================================================================
--  3. DIAGNOSTIC (lecture seule)
-- ============================================================================

select 'GARDE-FOU SERDIPAY' as controle,
       exists (select 1 from pg_trigger where tgname = 'trg_paiement_mm_serdipay') as trigger_ok,
       (select pg_get_functiondef(p.oid) like '%serdipay%'
          from pg_proc p
          join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public'
           and p.proname = 'paiement_mm_exige_serdipay'
         limit 1) as fonction_ok;

--  Comptes en essai : ce que produirait le paiement de l'installation
--  (premier mois inclus) s'il était réglé maintenant.
select e.nom,
       e.statut,
       e.prix_installation,
       e.date_expiration                       as fin_essai_actuelle,
       (e.date_expiration + interval '30 days') as expiration_apres_paiement
  from public.entreprises e
 where e.date_expiration is not null
   and e.date_expiration > now()
   and coalesce(e.prix_installation, 0) > 0
 order by e.date_expiration asc
 limit 20;

--  Paiements d'abonnement enregistrés SANS trace SerdiPay depuis la mise en
--  place du garde-fou (doit rester vide).
select p.id, p.entreprise_id, p.montant, p.mode_paiement, p.created_at
  from public.paiements_abonnements_laperle p
 where p.created_at > now() - interval '1 day'
   and lower(btrim(coalesce(p.mode_paiement, ''))) not like 'serdipay%'
 order by p.created_at desc
 limit 20;
