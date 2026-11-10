-- ============================================================================
--  BIASHARA YANGU — MIGRATION 130
--  LE WEBHOOK SERDIPAY PEUT ENFIN CRÉDITER L'ABONNEMENT (ACCES_REFUSE)
--  ---------------------------------------------------------------------------
--  SYMPTÔME RÉEL (10/11/2026)
--    Le client saisit son code PIN Mobile Money, la demande est validée sur
--    son téléphone… et rien ne se passe : l'écran tourne, l'abonnement n'est
--    jamais crédité, la transaction reste `en_attente`.
--
--  POURQUOI
--    `rpc_serdipay_confirmer` (appelée par le webhook) n'a pas de session :
--    elle EMPRUNTE l'identité d'un compte pour appeler le moteur
--    `rpc_abonnement_enregistrer_paiement`. Or le moteur vérifie
--
--        if not exists (select 1 from utilisateurs u
--                        where u.id = auth.uid() and u.role = 'admin')
--          then raise 'ACCES_REFUSE';
--
--    … c'est-à-dire l'ANCIEN rôle (`role`), pas le nouveau (`new_role`).
--    Le code choisissait le premier compte `new_role = 'FINANCE_LAPERLE'`
--    — sans regarder son ancien rôle. Si ce compte n'a pas `role = 'admin'`,
--    le moteur refuse, la transaction entière est annulée et la ligne
--    retombe en `en_attente` à chaque rejeu du webhook.
--
--    Rien ne le signale à l'utilisateur : le webhook répond une erreur que
--    SerdiPay ne montre pas, et l'application se contente de « en attente ».
--
--  LA CORRECTION
--    L'acteur emprunté est choisi pour SATISFAIRE le moteur :
--      1. un compte FINANCE_LAPERLE dont l'ancien rôle est `admin` ;
--      2. sinon n'importe quel compte dont l'ancien rôle est `admin`
--         (SUPER_ADMIN en premier).
--    Si aucun compte ne convient, l'erreur est explicite au lieu d'être
--    silencieuse.
--
--  ⚠️ La signature et les droits ne changent pas. Idempotent.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);


create or replace function public.rpc_serdipay_confirmer(
  p_reference          text,
  p_statut             text,
  p_provider_reference text default null,
  p_montant_recu       numeric default null,
  p_payload            jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ligne    public.paiements_serdipay%rowtype;
  v_statut   text := lower(btrim(coalesce(p_statut, 'paye')));
  v_acteur   uuid;
  v_entreprise public.entreprises%rowtype;
  v_mode     text;
begin
  if v_statut not in ('paye', 'echoue', 'annule', 'expire') then
    raise exception 'STATUT_INVALIDE';
  end if;

  select * into v_ligne
    from public.paiements_serdipay
   where reference = btrim(p_reference)
   for update;

  if not found then
    raise exception 'REFERENCE_INCONNUE';
  end if;

  -- Déjà payé : on répond « succès » sans rien recréditer (idempotence).
  if v_ligne.statut = 'paye' then
    return jsonb_build_object(
      'ok', true,
      'deja', true,
      'reference', v_ligne.reference,
      'statut', 'paye',
      'montant', v_ligne.montant
    );
  end if;

  if v_statut <> 'paye' then
    update public.paiements_serdipay
       set statut          = v_statut,
           motif_echec     = case when v_statut = 'echoue'
                                  then left(coalesce(v_ligne.motif_echec, 'REFUSE_FOURNISSEUR'), 500)
                                  else motif_echec end,
           webhook_payload = coalesce(p_payload, webhook_payload),
           provider_reference = coalesce(nullif(btrim(p_provider_reference), ''), provider_reference)
     where id = v_ligne.id;

    return jsonb_build_object(
      'ok', true,
      'deja', false,
      'reference', v_ligne.reference,
      'statut', v_statut
    );
  end if;

  -- Le fournisseur ne peut pas changer la référence qu'il avait fournie.
  if v_ligne.provider_reference is not null
     and nullif(btrim(p_provider_reference), '') is not null
     and v_ligne.provider_reference <> btrim(p_provider_reference) then
    raise exception 'REFERENCE_FOURNISSEUR_DIFFERENTE';
  end if;

  -- Contrôle du montant : un webhook ne fixe pas le prix.
  if p_montant_recu is not null
     and abs(p_montant_recu - v_ligne.montant) > 0.01 then
    update public.paiements_serdipay
       set statut      = 'echoue',
           motif_echec = 'MONTANT_INCORRECT',
           webhook_payload = coalesce(p_payload, webhook_payload)
     where id = v_ligne.id;

    raise exception 'MONTANT_INCORRECT|Montant reçu % % alors que % % était attendu.',
      p_montant_recu, v_ligne.devise, v_ligne.montant, v_ligne.devise;
  end if;

  -- ── ACTEUR DE CONFIANCE ─────────────────────────────────────────────────
  -- ⚠️ CORRECTIF 130 : le moteur vérifie l'ANCIEN rôle (`role = 'admin'`).
  --    On choisit donc un compte qui le satisfait, et on PREFERE le compte
  --    FINANCE de la plateforme.
  select u.id into v_acteur
    from public.utilisateurs u
   where lower(coalesce(u.role::text, '')) = 'admin'
     and coalesce(u.new_role::text, '') = 'FINANCE_LAPERLE'
   order by u.id
   limit 1;

  if v_acteur is null then
    select u.id into v_acteur
      from public.utilisateurs u
     where lower(coalesce(u.role::text, '')) = 'admin'
     order by (case when coalesce(u.new_role::text, '') = 'SUPER_ADMIN'
                    then 0 else 1 end),
              u.id
     limit 1;
  end if;

  if v_acteur is null then
    raise exception
      'ACTEUR_FINANCE_INTROUVABLE|Aucun compte dont l''ancien rôle est « admin » : impossible de créditer un paiement SerdiPay. Corrigez le rôle du compte FINANCE puis rejouez la confirmation.';
  end if;

  v_mode := case
              when v_ligne.operateur is null then 'SerdiPay'
              else 'SerdiPay · ' || v_ligne.operateur
            end;

  -- Le moteur lit `auth.uid()` : on l'emprunte le temps de la transaction.
  perform set_config('request.jwt.claim.sub', v_acteur::text, true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', v_acteur::text, 'role', 'authenticated')::text,
    true
  );

  -- Crédit réel (moteur module 3 + facture automatique + journal).
  -- Si le moteur lève une exception, TOUTE la transaction est annulée :
  -- la ligne reste `en_attente` et le fournisseur pourra rejouer son webhook.
  select * into v_entreprise
    from public.rpc_abonnement_enregistrer_paiement(
      v_ligne.entreprise_id,
      v_ligne.montant,
      v_ligne.type_paiement,
      v_mode,
      'Paiement SerdiPay ' || v_ligne.reference
    );

  update public.paiements_serdipay
     set statut             = 'paye',
         paye_le            = now(),
         provider_reference = coalesce(nullif(btrim(p_provider_reference), ''), provider_reference),
         webhook_payload    = coalesce(p_payload, webhook_payload)
   where id = v_ligne.id;

  begin
    insert into public.journal_audit (entreprise_id, action, utilisateur_id, details)
    values (
      v_ligne.entreprise_id, 'SERDIPAY_PAYE', v_acteur,
      jsonb_build_object(
        'reference', v_ligne.reference,
        'provider_reference', coalesce(nullif(btrim(p_provider_reference), ''), v_ligne.provider_reference),
        'montant', v_ligne.montant,
        'devise', v_ligne.devise,
        'operateur', v_ligne.operateur,
        'acteur', v_acteur
      )
    );
  exception when others then null;
  end;

  return jsonb_build_object(
    'ok', true,
    'deja', false,
    'reference', v_ligne.reference,
    'statut', 'paye',
    'montant', v_ligne.montant,
    'devise', v_ligne.devise,
    'entreprise_id', v_ligne.entreprise_id,
    'statut_abonnement', v_entreprise.statut,
    'date_expiration', v_entreprise.date_expiration,
    'solde_restant', v_entreprise.solde_restant,
    'acteur', v_acteur
  );
end;
$$;

comment on function public.rpc_serdipay_confirmer(text, text, text, numeric, jsonb) is
  'Confirme un paiement SerdiPay (webhook). Idempotent, vérifie le montant, '
  'puis crédite l''abonnement via rpc_abonnement_enregistrer_paiement. '
  'Correctif 130 : l''acteur emprunté satisfait le contrôle « role = admin ».';


-- ============================================================================
--  DIAGNOSTIC — qui peut créditer un paiement ?
-- ============================================================================
--  `peut_crediter = true` : le compte satisfait le moteur.
--  S'il n'y a AUCUNE ligne `true`, plus aucun paiement Mobile Money ne peut
--  être crédité : c'est la cause du « j'ai mis mon PIN et rien ne se passe ».

select u.email,
       u.new_role::text                       as role_metier,
       u.role::text                           as ancien_role,
       (lower(coalesce(u.role::text, '')) = 'admin') as peut_crediter
  from public.utilisateurs u
 where lower(coalesce(u.role::text, '')) = 'admin'
    or coalesce(u.new_role::text, '') in ('FINANCE_LAPERLE', 'SUPER_ADMIN')
 order by peut_crediter desc, u.new_role, u.email;


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
     and p.proname = 'rpc_serdipay_confirmer';

  if v_def is null then
    raise exception 'rpc_serdipay_confirmer introuvable après la migration.';
  end if;

  if position('role::text' in v_def) = 0 then
    raise exception
      'Migration 130 incomplète : la sélection de l''acteur ne vérifie pas l''ancien rôle.';
  end if;

  raise notice
    'Migration 130 OK : le webhook emprunte désormais un compte dont l''ancien rôle est « admin », donc le crédit ne peut plus être refusé pour ACCES_REFUSE.';
end $$;
