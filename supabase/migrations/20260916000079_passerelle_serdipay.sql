-- ============================================================================
--  biashara_yangu — MIGRATION 79 : PASSERELLE DE PAIEMENT SERDIPAY
-- ============================================================================
--  Objectif : permettre à un commerçant de régler son ABONNEMENT (ou une
--  FACTURE d'abonnement) en ligne par Mobile Money / carte, via l'agrégateur
--  congolais SerdiPay (Orange Money, Airtel Money, M-Pesa, Afrimoney, carte).
--
--  ARCHITECTURE (à lire avant toute modification)
--  ---------------------------------------------
--    1. L'application appelle l'Edge Function `serdipay` (route /initier)
--       avec son JWT. La fonction demande l'ouverture d'un paiement à la
--       base via `rpc_serdipay_ouvrir`.
--    2. `rpc_serdipay_ouvrir` calcule le MONTANT CÔTÉ SERVEUR (jamais envoyé
--       par le client) et insère une ligne `paiements_serdipay` en attente.
--    3. L'Edge Function crée la transaction chez SerdiPay, puis enregistre
--       l'URL de paiement et la référence fournisseur
--       (`rpc_serdipay_definir_lien`).
--    4. SerdiPay appelle le webhook `/functions/v1/serdipay/webhook`.
--       L'Edge Function vérifie la SIGNATURE HMAC, puis appelle
--       `rpc_serdipay_confirmer`.
--    5. `rpc_serdipay_confirmer` : verrouille la ligne, vérifie le MONTANT
--       REÇU, puis crédite l'abonnement en réutilisant le moteur existant
--       `rpc_abonnement_enregistrer_paiement` (aucune duplication de la
--       logique d'abonnement, donc aucun risque de régression sur les
--       correctifs 43 / 53 / 60).
--
--  SÉCURITÉ
--  --------
--    • Aucune policy d'ÉCRITURE : les tables ne sont alimentées que par des
--      fonctions `security definer`. Le client ne peut que LIRE ses lignes.
--    • `rpc_serdipay_ouvrir` et `rpc_serdipay_statut` : `authenticated`.
--    • `rpc_serdipay_confirmer`, `rpc_serdipay_definir_lien` et
--      `rpc_serdipay_echec` : `service_role` UNIQUEMENT (Edge Function).
--    • Le montant est RELU EN BASE à chaque étape ; un webhook annonçant un
--      montant différent est REFUSÉ (paiement passé en `echoue`).
--    • Idempotence : `reference` est unique et la confirmation n'accepte que
--      la transition `en_attente` → `paye`. Un webhook rejoué ne crédite
--      jamais deux fois.
--
--  ⚠️ EXÉCUTION
--    Supabase Dashboard → SQL Editor → New query → coller → Run.
--    (DDL + fonctions : impossible via PostgREST/anon.)
-- ============================================================================

select set_config('search_path', 'public, extensions', true);


-- ============================================================================
--  1. TABLE DES PAIEMENTS SERDIPAY
-- ============================================================================

create table if not exists public.paiements_serdipay (
  id                  uuid primary key default gen_random_uuid(),

  -- Référence INTERNE, communiquée à SerdiPay : SER-AAAAMMJJ-XXXXXXXX.
  reference           text not null unique,

  entreprise_id       uuid not null
                      references public.entreprises (id) on delete cascade,
  utilisateur_id      uuid
                      references public.utilisateurs (id) on delete set null,

  -- Ce qui est payé : le cycle d'abonnement en cours, ou une facture précise.
  objet               text not null default 'abonnement',
  objet_id            uuid,

  -- Montant FIGÉ au moment de l'ouverture (relu en base, jamais du client).
  montant             numeric(14, 2) not null,
  devise              text not null default 'CDF',

  -- Type attendu par le moteur d'abonnement (AVANCE / SOLDE / RENOUVELLEMENT).
  type_paiement       text not null default 'SOLDE',

  telephone           text,
  operateur           text,

  statut              text not null default 'en_attente',

  -- Données fournisseur (jamais exposées au client).
  provider_reference  text,
  url_paiement        text,
  provider_payload    jsonb,
  webhook_payload     jsonb,
  motif_echec         text,

  expire_le           timestamptz not null
                      default (now() + interval '30 minutes'),
  paye_le             timestamptz,

  created_at          timestamptz not null default now(),
  mis_a_jour_le       timestamptz not null default now(),

  constraint paiements_serdipay_objet_check
    check (objet in ('abonnement', 'facture')),
  constraint paiements_serdipay_statut_check
    check (statut in ('en_attente', 'paye', 'echoue', 'annule', 'expire')),
  constraint paiements_serdipay_type_check
    check (type_paiement in ('AVANCE', 'SOLDE', 'RENOUVELLEMENT')),
  constraint paiements_serdipay_montant_check
    check (montant > 0)
);

comment on table public.paiements_serdipay is
  'Passerelle SerdiPay (migration 79) — une ligne par tentative de paiement. '
  'Le montant est calculé côté serveur ; aucun accès en écriture pour le client.';

-- Une référence fournisseur ne peut pas désigner deux paiements.
create unique index if not exists paiements_serdipay_provider_ref_uidx
  on public.paiements_serdipay (provider_reference)
  where provider_reference is not null;

create index if not exists paiements_serdipay_entreprise_idx
  on public.paiements_serdipay (entreprise_id, created_at desc);

create index if not exists paiements_serdipay_statut_idx
  on public.paiements_serdipay (statut, created_at desc);

-- Horodatage automatique.
create or replace function public.serdipay_toucher()
returns trigger
language plpgsql
as $$
begin
  new.mis_a_jour_le := now();
  return new;
end;
$$;

drop trigger if exists trg_serdipay_toucher on public.paiements_serdipay;
create trigger trg_serdipay_toucher
  before update on public.paiements_serdipay
  for each row execute function public.serdipay_toucher();


-- ============================================================================
--  2. RLS — LECTURE SEULE POUR LE CLIENT
-- ============================================================================

alter table public.paiements_serdipay enable row level security;

drop policy if exists serdipay_lecture on public.paiements_serdipay;
create policy serdipay_lecture on public.paiements_serdipay
  for select to authenticated
  using (
    public.est_plateforme()
    or entreprise_id = public.mon_entreprise_id()
    or utilisateur_id = auth.uid()
  );

-- Aucune policy insert/update/delete : voulu. Les écritures passent par les
-- fonctions `security definer` ci-dessous (le client ne peut pas fabriquer
-- un « paiement payé »).

grant select on public.paiements_serdipay to authenticated;


-- ============================================================================
--  3. GÉNÉRATEUR DE RÉFÉRENCE INTERNE
-- ============================================================================

create or replace function public.serdipay_reference()
returns text
language sql
volatile
as $$
  select 'SER-' || to_char(now(), 'YYYYMMDD') || '-' ||
         upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
$$;

comment on function public.serdipay_reference() is
  'Référence interne SerdiPay : SER-AAAAMMJJ-XXXXXXXX (8 caractères aléatoires).';

revoke all on function public.serdipay_reference() from public, anon, authenticated;


-- ============================================================================
--  4. OUVRIR UN PAIEMENT (appelée par l'Edge Function, JWT utilisateur)
-- ============================================================================

create or replace function public.rpc_serdipay_ouvrir(
  p_objet         text,
  p_objet_id      uuid default null,
  p_telephone     text default null,
  p_operateur     text default null,
  p_entreprise_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user     uuid := auth.uid();
  v_ent      uuid;
  v_ligne    public.entreprises%rowtype;
  v_objet    text := lower(btrim(coalesce(p_objet, 'abonnement')));
  v_montant  numeric := 0;
  v_devise   text := 'CDF';
  v_type     text := 'SOLDE';
  v_tel      text;
  v_op       text;
  v_ref      text;
  v_id       uuid;
  v_expire   timestamptz;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE';
  end if;

  -- Entreprise ciblée : celle de l'espace actif par défaut.
  -- Un identifiant explicite n'est accepté QUE s'il correspond à l'entreprise
  -- de l'appelant, ou si l'appelant appartient à la plateforme.
  v_ent := public.mon_entreprise_id();

  if p_entreprise_id is not null then
    if p_entreprise_id = v_ent then
      v_ent := p_entreprise_id;
    elsif public.est_plateforme() then
      v_ent := p_entreprise_id;
    else
      raise exception 'ENTREPRISE_REFUSEE';
    end if;
  end if;

  if v_ent is null then
    raise exception 'ENTREPRISE_INTROUVABLE';
  end if;

  select * into v_ligne from public.entreprises where id = v_ent;
  if not found then
    raise exception 'ENTREPRISE_INTROUVABLE';
  end if;

  v_devise := coalesce(nullif(btrim(v_ligne.devise), ''), 'CDF');

  -- Téléphone : chiffres uniquement (indicatif accepté).
  v_tel := nullif(regexp_replace(coalesce(p_telephone, ''), '[^0-9]', '', 'g'), '');
  if v_tel is null or length(v_tel) < 9 or length(v_tel) > 15 then
    raise exception 'TELEPHONE_INVALIDE';
  end if;

  v_op := nullif(lower(btrim(coalesce(p_operateur, ''))), '');

  -- MONTANT : toujours calculé ici, jamais fourni par le client.
  if v_objet = 'facture' then
    if p_objet_id is null then
      raise exception 'OBJET_REQUIS';
    end if;

    select coalesce(f.solde_restant, 0)
      into v_montant
      from public.factures_abonnement f
     where f.id = p_objet_id
       and f.entreprise_id = v_ent;

    if v_montant is null then
      raise exception 'FACTURE_INTROUVABLE';
    end if;

  elsif v_objet = 'abonnement' then
    v_montant := coalesce(v_ligne.solde_restant, 0);
  else
    raise exception 'OBJET_INVALIDE';
  end if;

  if v_montant <= 0 then
    raise exception 'SOLDE_NUL';
  end if;

  -- Type attendu par le moteur d'abonnement.
  v_type := case
              when coalesce(v_ligne.montant_deja_paye, 0) > 0 then 'SOLDE'
              when v_ligne.date_activation is null then 'AVANCE'
              else 'RENOUVELLEMENT'
            end;

  v_ref := public.serdipay_reference();

  insert into public.paiements_serdipay (
    reference, entreprise_id, utilisateur_id, objet, objet_id,
    montant, devise, type_paiement, telephone, operateur, statut
  ) values (
    v_ref, v_ent, v_user, v_objet, p_objet_id,
    v_montant, v_devise, v_type, v_tel, v_op, 'en_attente'
  )
  returning id, expire_le into v_id, v_expire;

  begin
    insert into public.journal_audit (entreprise_id, action, utilisateur_id, details)
    values (
      v_ent, 'SERDIPAY_INITIE', v_user,
      jsonb_build_object(
        'reference', v_ref,
        'objet', v_objet,
        'montant', v_montant,
        'devise', v_devise,
        'operateur', v_op
      )
    );
  exception when others then null;
  end;

  return jsonb_build_object(
    'id', v_id,
    'reference', v_ref,
    'entreprise_id', v_ent,
    'objet', v_objet,
    'objet_id', p_objet_id,
    'montant', v_montant,
    'devise', v_devise,
    'type_paiement', v_type,
    'telephone', v_tel,
    'operateur', v_op,
    'statut', 'en_attente',
    'expire_le', v_expire
  );
end;
$$;

comment on function public.rpc_serdipay_ouvrir(text, uuid, text, text, uuid) is
  'Ouvre une tentative de paiement SerdiPay. Montant calculé côté serveur '
  '(solde d''abonnement ou solde de facture). Aucun montant client accepté.';

revoke all on function public.rpc_serdipay_ouvrir(text, uuid, text, text, uuid)
  from public, anon;
grant execute on function public.rpc_serdipay_ouvrir(text, uuid, text, text, uuid)
  to authenticated;


-- ============================================================================
--  5. ENREGISTRER LE LIEN DE PAIEMENT (service_role)
-- ============================================================================

create or replace function public.rpc_serdipay_definir_lien(
  p_reference          text,
  p_url_paiement       text,
  p_provider_reference text default null,
  p_payload            jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ligne public.paiements_serdipay%rowtype;
begin
  update public.paiements_serdipay
     set url_paiement       = coalesce(nullif(btrim(p_url_paiement), ''), url_paiement),
         provider_reference = coalesce(nullif(btrim(p_provider_reference), ''), provider_reference),
         provider_payload   = coalesce(p_payload, provider_payload)
   where reference = btrim(p_reference)
     and statut = 'en_attente'
  returning * into v_ligne;

  if v_ligne.id is null then
    -- Déjà confirmé ou inconnu : ne rien casser côté fournisseur.
    select * into v_ligne
      from public.paiements_serdipay
     where reference = btrim(p_reference);
  end if;

  if v_ligne.id is null then
    raise exception 'REFERENCE_INCONNUE';
  end if;

  return jsonb_build_object(
    'ok', true,
    'reference', v_ligne.reference,
    'statut', v_ligne.statut,
    'url_paiement', v_ligne.url_paiement,
    'provider_reference', v_ligne.provider_reference
  );
end;
$$;

revoke all on function public.rpc_serdipay_definir_lien(text, text, text, jsonb)
  from public, anon, authenticated;
grant execute on function public.rpc_serdipay_definir_lien(text, text, text, jsonb)
  to service_role;


-- ============================================================================
--  6. MARQUER UN ÉCHEC (service_role)
-- ============================================================================

create or replace function public.rpc_serdipay_echec(
  p_reference text,
  p_motif     text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ligne public.paiements_serdipay%rowtype;
begin
  update public.paiements_serdipay
     set statut      = 'echoue',
         motif_echec = left(coalesce(p_motif, 'ERREUR_FOURNISSEUR'), 500)
   where reference = btrim(p_reference)
     and statut = 'en_attente'
  returning * into v_ligne;

  return jsonb_build_object(
    'ok', true,
    'reference', btrim(p_reference),
    'statut', coalesce(v_ligne.statut, 'inchange')
  );
end;
$$;

revoke all on function public.rpc_serdipay_echec(text, text)
  from public, anon, authenticated;
grant execute on function public.rpc_serdipay_echec(text, text) to service_role;


-- ============================================================================
--  7. CONFIRMER UN PAIEMENT (webhook, service_role)
-- ============================================================================
--  ⚠️ Point le plus sensible du module. Trois garde-fous :
--    1. `for update` : deux webhooks simultanés ne peuvent pas créditer deux
--       fois (le second trouve le statut déjà `paye`).
--    2. Contrôle du MONTANT REÇU (tolérance 0,01 = arrondi).
--    3. Le crédit passe par le moteur d'abonnement EXISTANT — on ne réécrit
--       aucun calcul de cycle, de date d'expiration ni de solde.
--
--  Le moteur exige un rôle possédant `paiements/creer`. Le contexte
--  `service_role` n'a pas d'`auth.uid()` : on emprunte donc l'identité du
--  compte FINANCE de la plateforme, le temps de l'appel
--  (`set_config(..., true)` = limité à la transaction). C'est le SEUL endroit
--  du projet où cette technique est utilisée, et la fonction est
--  inatteignable par `authenticated`.
-- ============================================================================

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

  -- Acteur de confiance pour le moteur (FINANCE de la plateforme).
  select u.id into v_acteur
    from public.utilisateurs u
   where u.new_role = 'FINANCE_LAPERLE'
   order by u.id
   limit 1;

  if v_acteur is null then
    select u.id into v_acteur
      from public.utilisateurs u
     where u.new_role = 'SUPER_ADMIN'
     order by u.id
     limit 1;
  end if;

  if v_acteur is null then
    raise exception 'ACTEUR_FINANCE_INTROUVABLE';
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
        'operateur', v_ligne.operateur
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
    'solde_restant', v_entreprise.solde_restant
  );
end;
$$;

comment on function public.rpc_serdipay_confirmer(text, text, text, numeric, jsonb) is
  'Confirme un paiement SerdiPay (webhook). Idempotent, vérifie le montant, '
  'puis crédite l''abonnement via rpc_abonnement_enregistrer_paiement.';

revoke all on function public.rpc_serdipay_confirmer(text, text, text, numeric, jsonb)
  from public, anon, authenticated;
grant execute on function public.rpc_serdipay_confirmer(text, text, text, numeric, jsonb)
  to service_role;


-- ============================================================================
--  8. CONSULTER L'ÉTAT D'UN PAIEMENT (sondage de l'application)
-- ============================================================================

create or replace function public.rpc_serdipay_statut(p_reference text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ligne public.paiements_serdipay%rowtype;
begin
  select * into v_ligne
    from public.paiements_serdipay
   where reference = btrim(p_reference);

  if not found then
    raise exception 'REFERENCE_INCONNUE';
  end if;

  if not (
    v_ligne.utilisateur_id = auth.uid()
    or v_ligne.entreprise_id = public.mon_entreprise_id()
    or public.est_plateforme()
  ) then
    raise exception 'ACCES_REFUSE';
  end if;

  -- Expiration constatée à la lecture (aucun pg_cron dans le projet).
  if v_ligne.statut = 'en_attente' and v_ligne.expire_le < now() then
    update public.paiements_serdipay
       set statut = 'expire'
     where id = v_ligne.id
       and statut = 'en_attente';
    v_ligne.statut := 'expire';
  end if;

  return jsonb_build_object(
    'ok', true,
    'reference', v_ligne.reference,
    'objet', v_ligne.objet,
    'objet_id', v_ligne.objet_id,
    'montant', v_ligne.montant,
    'devise', v_ligne.devise,
    'statut', v_ligne.statut,
    'operateur', v_ligne.operateur,
    'url_paiement', v_ligne.url_paiement,
    'motif_echec', v_ligne.motif_echec,
    'expire_le', v_ligne.expire_le,
    'paye_le', v_ligne.paye_le,
    'created_at', v_ligne.created_at
  );
end;
$$;

revoke all on function public.rpc_serdipay_statut(text) from public, anon;
grant execute on function public.rpc_serdipay_statut(text) to authenticated;


-- ============================================================================
--  9. CONTRÔLE FINAL
-- ============================================================================

do $$
declare
  v_table integer;
  v_fonctions integer;
begin
  select count(*) into v_table
    from information_schema.tables
   where table_schema = 'public'
     and table_name = 'paiements_serdipay';

  select count(*) into v_fonctions
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname in (
       'serdipay_reference',
       'rpc_serdipay_ouvrir',
       'rpc_serdipay_definir_lien',
       'rpc_serdipay_echec',
       'rpc_serdipay_confirmer',
       'rpc_serdipay_statut'
     );

  if v_table <> 1 or v_fonctions <> 6 then
    raise exception
      'Migration 79 incomplète : table=% (attendu 1), fonctions=% (attendu 6).',
      v_table, v_fonctions;
  end if;

  raise notice
    'Migration 79 OK : table paiements_serdipay + 6 fonctions installées.';
end;
$$;
