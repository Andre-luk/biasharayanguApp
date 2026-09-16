-- ============================================================================
--  biashara_yangu — MODULE 3 : MOTEUR D'ABONNEMENT
--  Script idempotent : peut être exécuté plusieurs fois sans effet de bord.
--
--  OÙ L'EXÉCUTER
--    Supabase Dashboard → SQL Editor → New query → coller → Run
--
--  PRÉREQUIS
--    Exécuter d'abord les scripts des Modules 1 et 2.
--
--  CE QUE FAIT CE SCRIPT
--    1. Colonnes manquantes sur `paiements_abonnements_laperle`
--    2. RLS + policies (lecture connectés, écriture admins)
--    3. Journalisation automatique des changements de statut (journal_audit)
--    4. RPC moteur : enregistrement d'un paiement (AVANCE/SOLDE/RENOUVELLEMENT)
--    5. RPC de vérification globale (EXPIRE / EN_ATTENTE_COMPLEMENT)
--    6. RPC de réactivation après paiement complet
--    7. Vérification finale
--
--  RÈGLES MÉTIER APPLIQUÉES
--    - Création         : ESSAI_7J, total = montant de la grille, expiration =
--                         now() + duree_essai_jours (fait par le Module 1).
--    - Paiement partiel : le statut reste ESSAI_7J (ou ACTIF si le cycle est
--                         encore en cours) ; après expiration, un paiement
--                         partiel passe en EN_ATTENTE_COMPLEMENT.
--    - Paiement complet : statut ACTIF, date_expiration =
--                         base + duree_abonnement_jours, où base =
--                         max(now(), ancienne expiration encore future) pour
--                         ne perdre aucun jour déjà payé (renouvellement
--                         anticipé), sinon now().
--    - Échéance dépassée : 0 payé → EXPIRE ; paiement partiel entamé →
--                         EN_ATTENTE_COMPLEMENT. Aucune donnée n'est jamais
--                         supprimée (l'historique reste dans la table La Perle).
--    - SUSPENDU          : jamais modifié automatiquement (décision admin).
--    - Aucune date n'est acceptée du client : tout est calculé avec now().
-- ============================================================================


-- ============================================================================
--  1. COLONNES MANQUANTES SUR LA TABLE D'HISTORIQUE
-- ============================================================================
--  La table existe déjà avec : id, entreprise_id, montant, type_paiement,
--  mode_paiement, enregistre_par, created_at.
--  On ajoute les colonnes utilisées par l'historique et le formulaire.

alter table public.paiements_abonnements_laperle
  add column if not exists note text;
alter table public.paiements_abonnements_laperle
  add column if not exists total_apres numeric;
alter table public.paiements_abonnements_laperle
  add column if not exists solde_apres numeric;
alter table public.paiements_abonnements_laperle
  add column if not exists prolongation_jours integer not null default 0;

-- Type de paiement limité aux trois valeurs métier (NOT VALID : les lignes
-- existantes, s'il y en a, ne bloquent pas la création du script).
do $$
begin
  alter table public.paiements_abonnements_laperle
    add constraint chk_paiements_laperle_type
    check (type_paiement in ('AVANCE', 'SOLDE', 'RENOUVELLEMENT')) not valid;
exception
  when duplicate_object then null;
end $$;

create index if not exists idx_paiements_laperle_entreprise
  on public.paiements_abonnements_laperle (entreprise_id, created_at desc);

-- Clés étrangères (idempotent).
do $$
begin
  alter table public.paiements_abonnements_laperle
    add constraint fk_paiements_laperle_entreprise
    foreign key (entreprise_id) references public.entreprises (id)
    on delete cascade;
exception
  when duplicate_object then null;
  when undefined_table then null;
end $$;

do $$
begin
  alter table public.paiements_abonnements_laperle
    add constraint fk_paiements_laperle_enregistre_par
    foreign key (enregistre_par) references public.utilisateurs (id)
    on delete set null;
exception
  when duplicate_object then null;
  when undefined_table then null;
end $$;

create index if not exists idx_journal_audit_entreprise
  on public.journal_audit (entreprise_id, created_at desc);


-- ============================================================================
--  2. RLS + POLICIES
-- ============================================================================
--  On active la RLS sur les deux tables du moteur : les utilisateurs
--  connectés lisent l'historique de leur espace, seuls les admins écrivent
--  directement (l'application passe de toute façon par les RPC ci-dessous,
--  qui sont `security definer`).

alter table public.paiements_abonnements_laperle enable row level security;
alter table public.journal_audit enable row level security;

drop policy if exists "paiements_laperle_lecture" on public.paiements_abonnements_laperle;
create policy "paiements_laperle_lecture" on public.paiements_abonnements_laperle
  for select to authenticated using (true);

drop policy if exists "paiements_laperle_insertion_admin" on public.paiements_abonnements_laperle;
create policy "paiements_laperle_insertion_admin" on public.paiements_abonnements_laperle
  for insert to authenticated
  with check (
    exists (
      select 1 from public.utilisateurs u
      where u.id = auth.uid() and u.role = 'admin'
    )
  );

-- Journal d'audit : lecture réservée aux admins ; l'écriture passe
-- exclusivement par les fonctions `security definer` (trigger + RPC).
drop policy if exists "journal_audit_lecture_admin" on public.journal_audit;
create policy "journal_audit_lecture_admin" on public.journal_audit
  for select to authenticated
  using (
    exists (
      select 1 from public.utilisateurs u
      where u.id = auth.uid() and u.role = 'admin'
    )
  );


-- ============================================================================
--  3. JOURNALISATION AUTOMATIQUE DES CHANGEMENTS DE STATUT
-- ============================================================================
--  Trigger `after` sur `entreprises` : toute bascule de statut (paiement,
--  vérification globale, suspension manuelle…) est tracée dans journal_audit,
--  quel que soit le chemin (application, Dashboard Supabase, SQL direct).
--
--  La fonction est `security definer` : elle écrit même si la RLS interdit
--  l'insertion directe à l'auteur du changement.

create or replace function public.journaliser_changement_statut()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.statut is distinct from new.statut then
    insert into public.journal_audit (
      id, entreprise_id, action, utilisateur_id, details, created_at
    ) values (
      gen_random_uuid(),
      new.id,
      'CHANGEMENT_STATUT',
      auth.uid(),
      jsonb_build_object(
        'ancien_statut', old.statut::text,
        'nouveau_statut', new.statut::text
      ),
      now()
    );
  end if;
  return new;
end;
$$;

drop trigger if exists trg_entreprises_audit_statut on public.entreprises;
create trigger trg_entreprises_audit_statut
  after update on public.entreprises
  for each row
  execute function public.journaliser_changement_statut();

-- Création d'une entreprise : on trace le statut initial.
create or replace function public.journaliser_creation_entreprise()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(),
    new.id,
    'CREATION_ENTREPRISE',
    auth.uid(),
    jsonb_build_object(
      'statut', new.statut::text,
      'montant_total_du', new.montant_total_du
    ),
    now()
  );
  return new;
end;
$$;

drop trigger if exists trg_entreprises_audit_creation on public.entreprises;
create trigger trg_entreprises_audit_creation
  after insert on public.entreprises
  for each row
  execute function public.journaliser_creation_entreprise();


-- ============================================================================
--  4. RPC MOTEUR — ENREGISTREMENT D'UN PAIEMENT
-- ============================================================================
--  Remplace pour le Module 3 l'équivalent du Module 1 (qui alimente l'autre
--  table d'historique, conservée séparément) :
--    - historise dans `paiements_abonnements_laperle` (type + mode + note),
--    - recalcule montants, statut et dates dans la même transaction,
--    - journalise l'opération dans `journal_audit`.
--
--  Le verrou `for update` rend l'opération atomique : deux encaissements
--  simultanés ne peuvent pas se perdre l'un l'autre.
--
--  Erreurs possibles (codes volontairement explicites) :
--    ACCES_REFUSE, MONTANT_INVALIDE, TYPE_PAIEMENT_INVALIDE,
--    ENTREPRISE_INTROUVABLE, MONTANT_TOTAL_INCONNU, MONTANT_SUPERIEUR.

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
  --  Le nouveau cycle repart du montant de l'abonnement de la grille.
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
         solde_restant      = v_nouveau_solde,
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


-- ============================================================================
--  5. RPC — VÉRIFICATION GLOBALE (à appeler au démarrage de l'application)
-- ============================================================================
--  Parcourt les abonnements dont la date d'expiration est dépassée :
--    - paiement partiel entamé → EN_ATTENTE_COMPLEMENT (accès lecture seule),
--    - aucun paiement          → EXPIRE.
--
--  Ne touche jamais : SUSPENDU, ni les dates, ni les montants, ni aucune
--  donnée : seule la colonne `statut` est normalisée.

create or replace function public.rpc_abonnement_verification_globale()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nb integer;
begin
  if auth.uid() is null then
    raise exception 'ACCES_REFUSE';
  end if;

  update public.entreprises
     set statut = case
                    when coalesce(montant_deja_paye, 0) > 0
                         and coalesce(solde_restant, 0) > 0
                      then 'EN_ATTENTE_COMPLEMENT'::public.statut_abonnement_enum
                    else 'EXPIRE'::public.statut_abonnement_enum
                  end,
         updated_at = now()
   where statut in ('ESSAI_7J', 'ACTIF')
     and date_expiration is not null
     and date_expiration < now();

  get diagnostics v_nb = row_count;
  return v_nb;
end;
$$;

-- L'ancienne fonction du Module 1 est conservée (l'app l'appelle au
-- chargement de la liste des entreprises) mais délègue désormais à la
-- nouvelle règle : EXPIRE / EN_ATTENTE_COMPLEMENT.
create or replace function public.rpc_actualiser_statuts_abonnements()
returns integer
language plpgsql
security definer
set search_path = public
as $$
begin
  return public.rpc_abonnement_verification_globale();
end;
$$;


-- ============================================================================
--  6. RPC — RÉACTIVATION APRÈS PAIEMENT COMPLET
-- ============================================================================
--  Utilisée pour les cas où l'abonnement est intégralement réglé mais que le
--  statut ne peut pas l'être automatiquement (compte suspendu réactivé par
--  l'admin, correction manuelle…). Calcule la nouvelle date d'expiration :
--    base = max(now(), date_expiration encore future) + duree_abonnement_jours.

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
  v_duree      integer := 0;
  v_base       timestamptz;
begin
  if not exists (
    select 1 from public.utilisateurs u
    where u.id = auth.uid() and u.role = 'admin'
  ) then
    raise exception 'ACCES_REFUSE';
  end if;

  select * into v_entreprise
  from public.entreprises
  where id = p_entreprise_id
  for update;

  if not found then
    raise exception 'ENTREPRISE_INTROUVABLE';
  end if;

  if coalesce(v_entreprise.solde_restant, 0) > 0 then
    raise exception 'SOLDE_RESTANT';
  end if;

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
    'REACTIVATION',
    auth.uid(),
    jsonb_build_object(
      'date_expiration', v_entreprise.date_expiration,
      'duree_jours', v_duree
    ),
    now()
  );

  return v_entreprise;
end;
$$;


-- ============================================================================
--  7. DROITS D'EXÉCUTION
-- ============================================================================
--  Les utilisateurs connectés peuvent appeler les RPC ; le rôle anonyme en
--  est explicitement privé (durcissement — les anciennes fonctions des
--  Modules 1/2 sont également retirées au rôle anonyme, elles restent
--  accessibles aux utilisateurs connectés).

grant execute on function public.rpc_abonnement_enregistrer_paiement(uuid, numeric, text, text, text)
  to authenticated;
grant execute on function public.rpc_abonnement_verification_globale()
  to authenticated;
grant execute on function public.rpc_abonnement_reactiver(uuid)
  to authenticated;

revoke execute on function public.rpc_abonnement_enregistrer_paiement(uuid, numeric, text, text, text)
  from anon, public;
revoke execute on function public.rpc_abonnement_verification_globale()
  from anon, public;
revoke execute on function public.rpc_abonnement_reactiver(uuid)
  from anon, public;

revoke execute on function public.rpc_enregistrer_paiement(uuid, numeric, boolean)
  from anon, public;
revoke execute on function public.rpc_actualiser_statuts_abonnements()
  from anon, public;
revoke execute on function public.rpc_entreprises_de_utilisateur(uuid)
  from anon, public;


-- ============================================================================
--  8. VÉRIFICATION
-- ============================================================================

select
  (select count(*) from public.paiements_abonnements_laperle) as nb_paiements_laperle,
  (select count(*) from public.journal_audit)                 as nb_journal_audit,
  (select count(*) from public.entreprises)                   as nb_entreprises;

-- Doit renvoyer : note, total_apres, solde_apres, prolongation_jours.
select column_name
  from information_schema.columns
 where table_schema = 'public'
   and table_name = 'paiements_abonnements_laperle'
   and column_name in ('note', 'total_apres', 'solde_apres', 'prolongation_jours',
                       'type_paiement', 'mode_paiement')
 order by column_name;

-- Doit renvoyer les trois fonctions du moteur.
select proname, pronargs
  from pg_proc
 where proname in ('rpc_abonnement_enregistrer_paiement',
                   'rpc_abonnement_verification_globale',
                   'rpc_abonnement_reactiver')
 order by proname;

-- Doit renvoyer les deux triggers de journalisation.
select tgname
  from pg_trigger
 where not tgisinternal
   and tgname in ('trg_entreprises_audit_statut', 'trg_entreprises_audit_creation')
 order by tgname;
