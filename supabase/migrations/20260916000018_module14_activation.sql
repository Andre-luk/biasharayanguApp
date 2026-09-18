-- ============================================================================
--  biashara_yangu — MODULE 14 : ACTIVATION DES COMPTES (DOUBLE VALIDATION)
--
--  PROCÉDURE OFFICIELLE (cahier des charges)
--  ─────────────────────────────────────────────────────────────────────────
--   1. CRÉATION        → statut « en attente de vérification » : le compte
--                        n'est PAS opérationnel (lecture seule).
--   2. GESTIONNAIRE    → vérifie les informations (commerce, responsable,
--      DES COMPTES       téléphone, ville, activité, pack, preuves) :
--                        ✓ transmet à la Finance   ✗ rejette / correction.
--   3. FINANCE         → vérifie que le paiement est RÉELLEMENT reçu
--                        (montant, mode, référence, preuve, date) :
--                        ✓ VALIDE → activation automatique   ✗ rejette.
--   4. ACTIVATION      → PAIEMENT PARTIEL : 7 jours d'essai (solde à
--                        compléter) — PAIEMENT TOTAL : 30 jours immédiats.
--   5. APRÈS ÉCHÉANCE  → solde impayé à la fin des 7 jours : compte
--                        RESTREINT (lecture seule : le client voit son solde,
--                        paie, suit la validation ; RIEN n'est supprimé).
--   6. RÉGULARISATION  → solde payé → Finance valide → compte ACTIVÉ et
--                        nouveau cycle de 30 jours.
--
--  RÈGLE DE SÉCURITÉ : le Gestionnaire des comptes ne peut JAMAIS activer un
--  compte seul — seule la FINANCE (ou le Super Admin) valide l'activation.
--  Chaque étape est journalisée (utilisateur, date, heure, action).
--
--  CONTENU DE CE FICHIER
--    1. Colonnes de workflow sur `entreprises` + table d'historique ;
--    2. Réparation des RPC de paiement des Modules 1 et 3 (ils écrivaient
--       dans `solde_restant`, colonne GÉNÉRÉE → erreur PostgreSQL) ;
--    3. `rpc_entreprise_creer` v3 : les NOUVELLES boutiques naissent en
--       attente de vérification (les comptes existants restent actifs) ;
--    4. RPC du workflow : vérifier / valider finance / lister / état /
--       synchroniser (restriction & réactivation automatiques).
--
--  OÙ L'EXÉCUTER : Supabase → SQL Editor → coller → Run
--  ⚠️ IDEMPOTENT : peut être relancé sans dupliquer ni détruire de données.
-- ============================================================================


select set_config('search_path', 'public, extensions', true);


-- ============================================================================
--  1. COLONNES DE WORKFLOW + HISTORIQUE DÉDIÉ
-- ============================================================================

alter table public.entreprises
  add column if not exists activation_etape text not null default 'actif';

-- Contrainte de valeurs (recréée proprement pour rester idempotente).
do $$
begin
  alter table public.entreprises
    drop constraint if exists chk_entreprises_activation_etape;
  alter table public.entreprises
    add constraint chk_entreprises_activation_etape
    check (activation_etape in (
      'en_attente_verification', 'verifie', 'actif', 'restreint', 'rejete'
    ));
end $$;

alter table public.entreprises
  add column if not exists verifie_par uuid;
alter table public.entreprises
  add column if not exists verifie_le timestamptz;
alter table public.entreprises
  add column if not exists valide_par_finance uuid;
alter table public.entreprises
  add column if not exists valide_le_finance timestamptz;

comment on column public.entreprises.activation_etape is
  'Module 14 — Étape du dossier : en_attente_verification → verifie → actif ; restreint (solde impayé) ; rejete.';
comment on column public.entreprises.verifie_par is
  'Gestionnaire des comptes qui a vérifié le dossier.';
comment on column public.entreprises.valide_par_finance is
  'Finance (La Perle) qui a validé le paiement et l''activation finale.';

create index if not exists idx_entreprises_activation_etape
  on public.entreprises (activation_etape);

-- Les entreprises EXISTANTES restent actives (grand-père) : le défaut
-- 'actif' les couvre automatiquement.


-- 1.b Historique dédié du workflow (paiements + validations + motifs).
create table if not exists public.activations_entreprise (
  id                    uuid primary key default gen_random_uuid(),
  entreprise_id         uuid not null references public.entreprises(id) on delete cascade,
  etape                 text not null
    check (etape in (
      'soumission', 'verification', 'rejet_verification',
      'paiement_finance', 'rejet_finance', 'restriction'
    )),
  acteur_id             uuid references public.utilisateurs(id) on delete set null,
  acteur_role           text,
  montant               numeric,
  mode_paiement         text,
  reference_transaction text,
  note                  text,
  created_at            timestamptz not null default now()
);

comment on table public.activations_entreprise is
  'Module 14 — Historique des vérifications (Gestionnaire) et validations (Finance) d''activation, avec paiements et références.';

create index if not exists idx_activations_entreprise_date
  on public.activations_entreprise (entreprise_id, created_at desc);

alter table public.activations_entreprise enable row level security;

drop policy if exists m14_activations_lecture on public.activations_entreprise;
create policy m14_activations_lecture on public.activations_entreprise
  for select to authenticated
  using (
    public.est_plateforme()
    or entreprise_id = (
      select u.entreprise_id from public.utilisateurs u where u.id = auth.uid()
    )
  );

revoke all on public.activations_entreprise from public;
revoke all on public.activations_entreprise from anon;
revoke insert, update, delete, truncate on public.activations_entreprise from authenticated;
grant select on public.activations_entreprise to authenticated;


-- ============================================================================
--  2. RÉPARATION DES RPC DE PAIEMENT (Modules 1 & 3)
-- ============================================================================
--  `entreprises.solde_restant` est une colonne GÉNÉRÉE : l'écrire déclenche
--  « column "solde_restant" can only be updated to default ». Les deux RPC
--  ci-dessous sont RECRÉÉES à l'identique, sans cette écriture (la base
--  recalcule le solde automatiquement).

drop function if exists public.rpc_enregistrer_paiement(uuid, numeric);

create or replace function public.rpc_enregistrer_paiement(
  p_entreprise_id uuid,
  p_montant       numeric,
  p_prolonger     boolean default false
)
returns public.entreprises
language plpgsql
security definer
set search_path = public
as $$
declare
  v_entreprise public.entreprises;
  v_paye       numeric;
  v_total      numeric;
  v_solde      numeric;
  v_duree      integer := 0;
  v_base       timestamptz;
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

  select * into v_entreprise
  from public.entreprises
  where id = p_entreprise_id
  for update;

  if not found then
    raise exception 'ENTREPRISE_INTROUVABLE';
  end if;

  v_paye  := coalesce(v_entreprise.montant_deja_paye, 0);
  v_total := coalesce(v_entreprise.montant_total_du, 0);
  v_solde := coalesce(v_entreprise.solde_restant, greatest(v_total - v_paye, 0));

  if p_montant > v_solde then
    raise exception 'MONTANT_SUPERIEUR';
  end if;

  -- 3.1 Montants (le solde est recalculé par la base : colonne générée).
  update public.entreprises
     set montant_deja_paye = v_paye + p_montant,
         updated_at         = now()
   where id = p_entreprise_id;

  -- 3.2 Prolongation éventuelle
  if p_prolonger then
    select coalesce(g.duree_abonnement_jours, 0) into v_duree
    from public.groupes_tarifaires g
    where g.id = v_entreprise.groupe_tarifaire_id;

    v_duree := coalesce(v_duree, 0);

    -- On repart de la date d'expiration si elle est encore future, de
    -- maintenant sinon : un abonnement échu ne cumule pas de retard.
    v_base := greatest(coalesce(v_entreprise.date_expiration, now()), now());

    update public.entreprises
       set date_expiration = v_base + make_interval(days => v_duree),
           date_activation = coalesce(date_activation, now()),
           statut          = 'ACTIF',
           updated_at      = now()
     where id = p_entreprise_id;
  end if;

  select * into v_entreprise from public.entreprises where id = p_entreprise_id;

  -- 3.3 Historique
  insert into public.paiements_abonnement (
    entreprise_id,
    montant,
    total_apres,
    solde_apres,
    prolongation_jours,
    enregistre_par
  ) values (
    p_entreprise_id,
    p_montant,
    v_entreprise.montant_deja_paye,
    v_entreprise.solde_restant,
    case when p_prolonger then v_duree else 0 end,
    auth.uid()
  );

  return v_entreprise;
end;
$$;

grant execute on function public.rpc_enregistrer_paiement(uuid, numeric, boolean)
  to authenticated;


-- 2.b Module 3 — enregistrement d'un paiement d'abonnement (sans solde_restant).
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
    select coalesce(g.montant_abonnement, v_total)
      into v_total
      from public.groupes_tarifaires g
     where g.id = v_entreprise.groupe_tarifaire_id;
    v_total := coalesce(v_total, 0);

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

grant execute on function public.rpc_abonnement_enregistrer_paiement(uuid, numeric, text, text, text)
  to authenticated;


-- ============================================================================
--  3. `rpc_entreprise_creer` v3 — LES NOUVELLES BOUTIQUES NAISSENT EN ATTENTE
-- ============================================================================
--  ⚠️ Les entreprises DÉJÀ existantes ne sont pas touchées (elles restent
--  « actif ») : seule la création de nouvelles boutiques bascule dans le
--  circuit de double validation.

create or replace function public.rpc_entreprise_creer(
  p_nom text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user  uuid := auth.uid();
  v_exist uuid;
  v_nomu  text;
  v_nom   text;
  v_new   uuid;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour créer votre entreprise.';
  end if;

  -- Déjà rattaché ? On ne duplique pas.
  select u.entreprise_id into v_exist
    from public.utilisateurs u
   where u.id = v_user;

  if v_exist is not null then
    return jsonb_build_object('ok', true, 'deja', true, 'entreprise_id', v_exist);
  end if;

  select coalesce(nullif(btrim(u.nom), ''), u.email) into v_nomu
    from public.utilisateurs u
   where u.id = v_user;

  v_nom := nullif(btrim(coalesce(p_nom, '')), '');
  if v_nom is null then
    v_nom := 'Boutique ' || coalesce(v_nomu, 'nouvelle');
  end if;

  insert into public.entreprises (nom)
  values (v_nom)
  returning id into v_new;

  update public.utilisateurs
     set entreprise_id = v_new
   where id = v_user;

  -- 🛡️ MODULE 14 — double validation obligatoire : le compte n'est PAS
  -- opérationnel tant que le gestionnaire puis la finance n'ont pas validé.
  -- `EN_ATTENTE_COMPLEMENT` = lecture seule (moteur Module 3).
  update public.entreprises
     set activation_etape = 'en_attente_verification',
         statut = 'EN_ATTENTE_COMPLEMENT'::public.statut_abonnement_enum,
         updated_at = now()
   where id = v_new;

  insert into public.activations_entreprise (
    entreprise_id, etape, acteur_id, acteur_role, note
  ) values (
    v_new, 'soumission', v_user, public.mon_role(), 'Création du compte'
  );

  -- Trace (best-effort : ne doit jamais faire échouer la création).
  begin
    insert into public.journal_audit (entreprise_id, action, utilisateur_id, details)
    values (
      null, 'CREATION_ENTREPRISE', v_user,
      jsonb_build_object(
        'entreprise_id', v_new, 'nom', v_nom,
        'activation_etape', 'en_attente_verification'
      )
    );
  exception when others then null;
  end;

  return jsonb_build_object('ok', true, 'deja', false,
                            'entreprise_id', v_new, 'nom', v_nom,
                            'activation_etape', 'en_attente_verification');
end;
$$;

comment on function public.rpc_entreprise_creer(text) is
  'Module 14 — Crée l''entreprise de la boutique et la place EN ATTENTE DE VÉRIFICATION (double validation gestionnaire → finance).';

revoke all on function public.rpc_entreprise_creer(text) from public;
revoke all on function public.rpc_entreprise_creer(text) from anon;
grant execute on function public.rpc_entreprise_creer(text) to authenticated;


-- ============================================================================
--  4. RPC DU WORKFLOW D'ACTIVATION
-- ============================================================================

-- 4.a PREMIÈRE VÉRIFICATION — GESTIONNAIRE DES COMPTES -----------------------
create or replace function public.rpc_activation_verifier(
  p_entreprise_id uuid,
  p_approuver     boolean,
  p_note          text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text := public.mon_role();
  v_e    public.entreprises;
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
begin
  -- 🔒 SÉPARATION DES RESPONSABILITÉS : le gestionnaire vérifie, il
  -- n'active JAMAIS (seule la finance valide l'activation finale).
  if v_role not in ('GESTIONNAIRE_COMPTES', 'SUPER_ADMIN') then
    raise exception 'DROIT_REFUSE|Seul le gestionnaire des comptes vérifie un dossier.';
  end if;

  select * into v_e
    from public.entreprises
   where id = p_entreprise_id
   for update;

  if not found then
    raise exception 'ENTREPRISE_INTROUVABLE|Ce compte n''existe plus.';
  end if;

  if v_e.activation_etape not in ('en_attente_verification', 'rejete') then
    raise exception 'ETAPE_INVALIDE|Ce dossier n''est pas en attente de vérification.';
  end if;

  if coalesce(p_approuver, false) then
    update public.entreprises
       set activation_etape = 'verifie',
           verifie_par      = auth.uid(),
           verifie_le       = now(),
           updated_at       = now()
     where id = p_entreprise_id
     returning * into v_e;

    insert into public.activations_entreprise (
      entreprise_id, etape, acteur_id, acteur_role, note
    ) values (
      p_entreprise_id, 'verification', auth.uid(), v_role, v_note
    );

    begin
      insert into public.journal_audit (entreprise_id, action, utilisateur_id, details)
      values (
        null, 'ACTIVATION_VERIFIEE', auth.uid(),
        jsonb_build_object('entreprise_id', p_entreprise_id, 'boutique', v_e.nom, 'note', v_note)
      );
    exception when others then null;
    end;
  else
    if v_note is null or length(v_note) < 3 then
      raise exception 'NOTE_REQUISE|Précisez le motif du rejet (3 caractères minimum).';
    end if;

    update public.entreprises
       set activation_etape = 'rejete',
           updated_at       = now()
     where id = p_entreprise_id
     returning * into v_e;

    insert into public.activations_entreprise (
      entreprise_id, etape, acteur_id, acteur_role, note
    ) values (
      p_entreprise_id, 'rejet_verification', auth.uid(), v_role, v_note
    );

    begin
      insert into public.journal_audit (entreprise_id, action, utilisateur_id, details)
      values (
        null, 'ACTIVATION_REJETEE', auth.uid(),
        jsonb_build_object('entreprise_id', p_entreprise_id, 'boutique', v_e.nom, 'motif', v_note)
      );
    exception when others then null;
    end;
  end if;

  return jsonb_build_object(
    'ok', true,
    'etape', v_e.activation_etape,
    'approuve', coalesce(p_approuver, false)
  );
end;
$$;

comment on function public.rpc_activation_verifier(uuid, boolean, text) is
  'Module 14 — Vérification du dossier par le gestionnaire des comptes (transmet à la finance ou rejette).';

revoke all on function public.rpc_activation_verifier(uuid, boolean, text) from public;
revoke all on function public.rpc_activation_verifier(uuid, boolean, text) from anon;
grant execute on function public.rpc_activation_verifier(uuid, boolean, text) to authenticated;


-- 4.b DEUXIÈME CONTRÔLE — FINANCE (VALIDATION FINALE + ACTIVATION) ----------
create or replace function public.rpc_activation_valider_finance(
  p_entreprise_id          uuid,
  p_approuver              boolean,
  p_montant                numeric default null,
  p_mode_paiement          text default null,
  p_reference_transaction  text default null,
  p_note                   text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role        text := public.mon_role();
  v_e           public.entreprises;
  v_avant       text;
  v_avant_paye  numeric;
  v_note        text := nullif(btrim(coalesce(p_note, '')), '');
  v_type        text;
  v_duree_essai integer;
  v_kind        text := 'rejet';
begin
  -- 🔒 Seule la finance (ou le Super Admin) valide l'activation finale.
  if v_role not in ('FINANCE_LAPERLE', 'SUPER_ADMIN') then
    raise exception 'DROIT_REFUSE|Seule la finance valide le paiement et active le compte.';
  end if;

  select * into v_e
    from public.entreprises
   where id = p_entreprise_id
   for update;

  if not found then
    raise exception 'ENTREPRISE_INTROUVABLE|Ce compte n''existe plus.';
  end if;

  -- Le dossier doit d'abord être passé par le gestionnaire des comptes.
  if v_e.activation_etape not in ('verifie', 'actif', 'restreint') then
    raise exception 'ETAPE_INVALIDE|Le dossier doit d''abord être vérifié par le gestionnaire des comptes.';
  end if;

  v_avant      := v_e.activation_etape;
  v_avant_paye := coalesce(v_e.montant_deja_paye, 0);

  if coalesce(p_approuver, false) then
    if p_montant is null or p_montant <= 0 then
      raise exception 'MONTANT_INVALIDE|Saisissez le montant réellement reçu.';
    end if;

    -- Étiquette du paiement : solde lorsqu'un complément est réglé.
    v_type := case
                when v_avant = 'restreint' or v_avant_paye > 0 then 'SOLDE'
                else 'AVANCE'
              end;

    -- Moteur Module 3 : montants, statut, dates, historique des paiements.
    select * into v_e
      from public.rpc_abonnement_enregistrer_paiement(
        p_entreprise_id, p_montant, v_type, p_mode_paiement, p_note
      );

    if coalesce(v_e.solde_restant, 0) <= 0 then
      -- 💰 PAIEMENT TOTAL → activation directe, abonnement de 30 jours.
      v_kind := 'total';

      update public.entreprises
         set activation_etape     = 'actif',
             valide_par_finance   = auth.uid(),
             valide_le_finance    = now(),
             updated_at           = now()
       where id = p_entreprise_id
       returning * into v_e;
    else
      -- 💳 PAIEMENT PARTIEL → 7 jours d'utilisation initiale.
      v_kind := 'partiel';

      if v_avant = 'verifie' then
        select coalesce(g.duree_essai_jours, 7) into v_duree_essai
          from public.groupes_tarifaires g
         where g.id = v_e.groupe_tarifaire_id;
        v_duree_essai := coalesce(v_duree_essai, 7);

        update public.entreprises
           set statut               = 'ESSAI_7J'::public.statut_abonnement_enum,
               date_activation      = coalesce(date_activation, now()),
               date_expiration      = now() + make_interval(days => v_duree_essai),
               activation_etape     = 'actif',
               valide_par_finance   = auth.uid(),
               valide_le_finance    = now(),
               updated_at           = now()
         where id = p_entreprise_id
         returning * into v_e;
      else
        -- Complément partiel pendant un cycle en cours (avance) : on note
        -- simplement la validation ; le solde et le statut restent inchangés.
        update public.entreprises
           set valide_par_finance = auth.uid(),
               valide_le_finance  = now(),
               updated_at         = now()
         where id = p_entreprise_id
         returning * into v_e;
      end if;
    end if;

    insert into public.activations_entreprise (
      entreprise_id, etape, acteur_id, acteur_role,
      montant, mode_paiement, reference_transaction, note
    ) values (
      p_entreprise_id, 'paiement_finance', auth.uid(), v_role,
      p_montant, nullif(btrim(coalesce(p_mode_paiement, '')), ''),
      nullif(btrim(coalesce(p_reference_transaction, '')), ''), v_note
    );

    begin
      insert into public.journal_audit (entreprise_id, action, utilisateur_id, details)
      values (
        null, 'ACTIVATION_FINANCE', auth.uid(),
        jsonb_build_object(
          'entreprise_id', p_entreprise_id,
          'boutique', v_e.nom,
          'montant', p_montant,
          'mode_paiement', nullif(btrim(coalesce(p_mode_paiement, '')), ''),
          'reference_transaction', nullif(btrim(coalesce(p_reference_transaction, '')), ''),
          'scenario', v_kind,
          'etape_apres', v_e.activation_etape,
          'statut_apres', v_e.statut::text,
          'solde_restant', v_e.solde_restant
        )
      );
    exception when others then null;
    end;
  else
    -- ✗ Paiement non confirmé : on garde l'étape, on consigne le motif.
    if v_note is null or length(v_note) < 3 then
      raise exception 'NOTE_REQUISE|Précisez le motif du rejet (3 caractères minimum).';
    end if;

    insert into public.activations_entreprise (
      entreprise_id, etape, acteur_id, acteur_role,
      montant, mode_paiement, reference_transaction, note
    ) values (
      p_entreprise_id, 'rejet_finance', auth.uid(), v_role,
      p_montant, nullif(btrim(coalesce(p_mode_paiement, '')), ''),
      nullif(btrim(coalesce(p_reference_transaction, '')), ''), v_note
    );

    begin
      insert into public.journal_audit (entreprise_id, action, utilisateur_id, details)
      values (
        null, 'PAIEMENT_REJETE_FINANCE', auth.uid(),
        jsonb_build_object('entreprise_id', p_entreprise_id, 'boutique', v_e.nom,
                           'montant_annonce', p_montant, 'motif', v_note)
      );
    exception when others then null;
    end;
  end if;

  return jsonb_build_object(
    'ok', true,
    'etape', v_e.activation_etape,
    'statut', v_e.statut::text,
    'scenario', v_kind,
    'montant_deja_paye', v_e.montant_deja_paye,
    'solde_restant', v_e.solde_restant,
    'date_activation', v_e.date_activation,
    'date_expiration', v_e.date_expiration
  );
end;
$$;

comment on function public.rpc_activation_valider_finance(uuid, boolean, numeric, text, text, text) is
  'Module 14 — Validation finance : enregistre le paiement (montant/mode/référence) et active automatiquement (partiel = 7 j, total = 30 j).';

revoke all on function public.rpc_activation_valider_finance(uuid, boolean, numeric, text, text, text) from public;
revoke all on function public.rpc_activation_valider_finance(uuid, boolean, numeric, text, text, text) from anon;
grant execute on function public.rpc_activation_valider_finance(uuid, boolean, numeric, text, text, text) to authenticated;


-- 4.c LISTE DES DOSSIERS — ÉCRANS ADMIN (GESTIONNAIRE & FINANCE) ------------
create or replace function public.rpc_activation_lister(
  p_etape text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text := public.mon_role();
begin
  if v_role not in ('GESTIONNAIRE_COMPTES', 'FINANCE_LAPERLE', 'SUPER_ADMIN') then
    raise exception 'DROIT_REFUSE|Réservé au personnel de la plateforme.';
  end if;

  return coalesce((
    select jsonb_agg(t)
      from (
        select jsonb_build_object(
          'id', e.id,
          'nom', e.nom,
          'etape', e.activation_etape,
          'statut', e.statut::text,
          'ville', v.nom,
          'activite', a.nom,
          'montant_total_du', e.montant_total_du,
          'montant_deja_paye', e.montant_deja_paye,
          'solde_restant', e.solde_restant,
          'date_activation', e.date_activation,
          'date_expiration', e.date_expiration,
          'created_at', e.created_at,
          'verifie_le', e.verifie_le,
          'valide_le_finance', e.valide_le_finance,
          'responsable', (
            select coalesce(nullif(btrim(u.nom), ''), u.email)
              from public.utilisateurs u
             where u.entreprise_id = e.id and u.parent_id is null
             order by u.created_at limit 1
          ),
          'contact', (
            select u.email
              from public.utilisateurs u
             where u.entreprise_id = e.id and u.parent_id is null
             order by u.created_at limit 1
          ),
          'telephone', (
            select to_jsonb(u) ->> 'telephone'
              from public.utilisateurs u
             where u.entreprise_id = e.id and u.parent_id is null
             order by u.created_at limit 1
          ),
          'dernier_motif', (
            select h.note
              from public.activations_entreprise h
             where h.entreprise_id = e.id
               and h.etape in ('rejet_verification', 'rejet_finance')
             order by h.created_at desc limit 1
          )
        ) as t
          from public.entreprises e
          left join public.villes v on v.id = e.ville_id
          left join public.activites a on a.id = e.activite_id
         where p_etape is null or e.activation_etape = btrim(p_etape)
         order by e.created_at desc
         limit 200
      ) s
  ), '[]'::jsonb);
end;
$$;

comment on function public.rpc_activation_lister(text) is
  'Module 14 — Liste des dossiers d''activation (Gestionnaire : à vérifier ; Finance : à valider).';

revoke all on function public.rpc_activation_lister(text) from public;
revoke all on function public.rpc_activation_lister(text) from anon;
grant execute on function public.rpc_activation_lister(text) to authenticated;


-- 4.d ÉTAT DU DOSSIER — TABLEAU DE BORD CLIENT -------------------------------
create or replace function public.rpc_activation_etat(
  p_entreprise_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_role text;
  v_ent  uuid;
  v_e    public.entreprises;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour consulter votre dossier.';
  end if;

  v_role := public.mon_role();

  if p_entreprise_id is not null then
    v_ent := p_entreprise_id;

    if v_role not in ('GESTIONNAIRE_COMPTES', 'FINANCE_LAPERLE', 'SUPER_ADMIN')
       and not exists (
         select 1 from public.utilisateurs u
          where u.id = v_user and u.entreprise_id = v_ent
       ) then
      raise exception 'DROIT_REFUSE|Vous n''avez pas accès à ce dossier.';
    end if;
  else
    select u.entreprise_id into v_ent
      from public.utilisateurs u
     where u.id = v_user;
  end if;

  if v_ent is null then
    return jsonb_build_object('etape', 'aucune');
  end if;

  select * into v_e from public.entreprises where id = v_ent;
  if not found then
    return jsonb_build_object('etape', 'aucune');
  end if;

  return jsonb_build_object(
    'entreprise_id', v_e.id,
    'nom', v_e.nom,
    'etape', v_e.activation_etape,
    'statut', v_e.statut::text,
    'type_paiement', case
                       when coalesce(v_e.solde_restant, 0) <= 0 then 'total'
                       when coalesce(v_e.montant_deja_paye, 0) > 0 then 'partiel'
                       else 'aucun'
                     end,
    'montant_total_du', v_e.montant_total_du,
    'montant_deja_paye', v_e.montant_deja_paye,
    'solde_restant', v_e.solde_restant,
    'date_activation', v_e.date_activation,
    'date_expiration', v_e.date_expiration,
    'jours_restants', case
                        when v_e.date_expiration is null then null
                        else greatest(
                          0,
                          ceil(extract(epoch from (v_e.date_expiration - now())) / 86400.0)
                        )::int
                      end,
    'verifie_le', v_e.verifie_le,
    'valide_le_finance', v_e.valide_le_finance,
    'historique', coalesce((
      select jsonb_agg(jsonb_build_object(
               'etape', h.etape,
               'role', h.acteur_role,
               'montant', h.montant,
               'mode_paiement', h.mode_paiement,
               'reference', h.reference_transaction,
               'note', h.note,
               'le', h.created_at
             ) order by h.created_at desc)
        from public.activations_entreprise h
       where h.entreprise_id = v_e.id
    ), '[]'::jsonb)
  );
end;
$$;

comment on function public.rpc_activation_etat(uuid) is
  'Module 14 — Tableau de bord du dossier : étape, montants, dates, jours restants, historique des paiements et validations.';

revoke all on function public.rpc_activation_etat(uuid) from public;
revoke all on function public.rpc_activation_etat(uuid) from anon;
grant execute on function public.rpc_activation_etat(uuid) to authenticated;


-- 4.e SYNCHRONISATION AUTOMATIQUE (restriction / réactivation) --------------
create or replace function public.rpc_activation_synchroniser()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_restreint int := 0;
  v_reactive  int := 0;
begin
  -- 🔒 Restriction automatique : fin des 7 jours (ou échéance) avec solde
  -- impayé → dossier « restreint » (lecture seule côté moteur Module 3).
  --  Les données ne sont JAMAIS supprimées.
  with maj as (
    update public.entreprises e
       set activation_etape = 'restreint',
           updated_at = now()
     where e.activation_etape = 'actif'
       and coalesce(e.solde_restant, 0) > 0
       and (
         e.statut::text = 'EXPIRE'
         or e.statut::text = 'EN_ATTENTE_COMPLEMENT'
         or (e.statut::text = 'ESSAI_7J'
             and e.date_expiration is not null
             and e.date_expiration < now())
       )
     returning e.id, e.nom, e.solde_restant
  ),
  trace as (
    insert into public.journal_audit (entreprise_id, action, utilisateur_id, details)
    select null, 'ACTIVATION_RESTREINTE', null,
           jsonb_build_object('entreprise_id', id, 'boutique', nom, 'solde', solde_restant)
      from maj
    returning 1
  )
  select count(*) into v_restreint from maj;

  -- Réactivation : un paiement validé (ou un encaissement Module 1/3) a
  -- remis le statut d'abonnement en règle.
  with maj2 as (
    update public.entreprises e
       set activation_etape = 'actif',
           updated_at = now()
     where e.activation_etape = 'restreint'
       and e.statut::text in ('ACTIF', 'ESSAI_7J')
     returning e.id
  )
  select count(*) into v_reactive from maj2;

  return jsonb_build_object('restreintes', v_restreint, 'reactivees', v_reactive);
end;
$$;

comment on function public.rpc_activation_synchroniser() is
  'Module 14 — Restriction automatique (solde impayé à l''échéance) et réactivation après régularisation.';

revoke all on function public.rpc_activation_synchroniser() from public;
revoke all on function public.rpc_activation_synchroniser() from anon;
grant execute on function public.rpc_activation_synchroniser() to authenticated;


-- ============================================================================
--  5. VÉRIFICATIONS
-- ============================================================================

-- 5.a Répartition des dossiers par étape.
select activation_etape, count(*) as nombre
  from public.entreprises
 group by activation_etape
 order by activation_etape;

-- 5.b Dossiers en attente de vérification (le gestionnaire doit les traiter).
select e.nom, e.created_at,
       (select u.email from public.utilisateurs u
         where u.entreprise_id = e.id and u.parent_id is null
         order by u.created_at limit 1) as responsable
  from public.entreprises e
 where e.activation_etape = 'en_attente_verification'
 order by e.created_at;

-- 5.c Historique du workflow (les 10 dernières actions).
select h.created_at, e.nom as boutique, h.etape, h.acteur_role,
       h.montant, h.reference_transaction, h.note
  from public.activations_entreprise h
  join public.entreprises e on e.id = h.entreprise_id
 order by h.created_at desc
 limit 10;
