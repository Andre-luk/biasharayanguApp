-- ============================================================================
--  biashara_yangu — MODULE 23 : DISTRIBUTION TERRAIN, CONSIGNES & BONUS
--
--  Objectif métier
--  ---------------
--  Une entreprise (eau minérale, PGC, marketing…) confie une DOTATION à un
--  agent qui part en tournée. L'agent ne peut vendre QUE ce qu'il a reçu.
--  Le patron obtient un rapport par agent : attribué, vendu, rendu, écart,
--  chiffre d'affaires, consignes restées chez les clients, bonus accordés.
--
--  DÉCISIONS (à ne pas casser)
--  ---------------------------
--   1) La dotation est une RÉSERVATION : elle ne bouge PAS le stock.
--      Le stock ne diminue qu'à la VENTE, par le trigger du Module 8.
--   2) Une seule tournée active (preparee / en_cours) par agent.
--   3) La vente d'un agent passe par `rpc_tournee_vente`, qui appelle
--      `rpc_vente_valider` : prix relus en base, caisse, numéro, journal.
--   4) Les écritures directes sur les tables du module sont RÉVOQUÉES :
--      tout passe par les RPC (security definer).
--
--  PRÉ-REQUIS : Modules 4, 5, 8 exécutés (peut, mon_proprietaire, ventes,
--  rpc_vente_valider, journal_audit).
--
--  ⚠️ IDEMPOTENT : peut être relancé.
--  ⚠️ À exécuter dans le SQL Editor Supabase (DDL impossible via PostgREST).
-- ============================================================================

select set_config('search_path', 'public, extensions', true);

-- Contrôle préalable ---------------------------------------------------------
do $$
begin
  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where p.proname = 'mon_proprietaire' and n.nspname = 'public'
  ) then
    raise exception 'Module 5 absent : exécutez 20260916000008_module5_articles.sql.';
  end if;
  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where p.proname = 'rpc_vente_valider' and n.nspname = 'public'
  ) then
    raise exception 'Module 8 absent : exécutez 20260916000009_module8_ventes.sql.';
  end if;
end $$;


-- ============================================================================
--  1. COLONNES COMPLÉMENTAIRES
-- ============================================================================

-- Mode rapide : un produit peut être vendu sans suivi de stock.
alter table public.produits
  add column if not exists stock_illimite boolean not null default false;

-- Zone / quartier du client (rapport par zone, consignes).
alter table public.clients add column if not exists zone     text;
alter table public.clients add column if not exists quartier text;

-- Rattachement d'une vente à une tournée (CA par agent).
alter table public.ventes add column if not exists tournee_id uuid;

create index if not exists idx_ventes_tournee
  on public.ventes (tournee_id)
  where tournee_id is not null;
create index if not exists idx_clients_zone
  on public.clients (zone);


-- ============================================================================
--  2. TABLES DU MODULE
-- ============================================================================

create table if not exists public.tournees (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid not null,
  agent_id      uuid not null,
  reference     text not null,
  date_tournee  date not null default current_date,
  zone          text,
  statut        text not null default 'preparee'
                check (statut in ('preparee', 'en_cours', 'cloturee', 'annulee')),
  note          text,
  cree_par      uuid default auth.uid(),
  cree_le       timestamptz not null default now(),
  demarree_le   timestamptz,
  cloturee_le   timestamptz,
  constraint tournees_reference_unique unique (owner_id, reference)
);

create index if not exists idx_tournees_owner_date
  on public.tournees (owner_id, date_tournee desc);
create index if not exists idx_tournees_agent
  on public.tournees (agent_id, statut);

comment on table public.tournees is
  'Tournée de distribution : dotation d''un agent pour une date et une zone.';

create table if not exists public.tournee_lignes (
  id                  uuid primary key default gen_random_uuid(),
  tournee_id          uuid not null references public.tournees (id) on delete cascade,
  produit_id          bigint not null,
  nom_produit         text not null default '',
  unite               text,
  quantite_attribuee  real not null,
  quantite_vendue     real not null default 0,
  quantite_retournee  real not null default 0,
  prix_vente          real,
  constraint tournee_lignes_produit_unique unique (tournee_id, produit_id),
  constraint tournee_lignes_attribuee_positive check (quantite_attribuee > 0),
  constraint tournee_lignes_quantites_positives
    check (quantite_vendue >= 0 and quantite_retournee >= 0),
  constraint tournee_lignes_coherence
    check (quantite_vendue + quantite_retournee <= quantite_attribuee + 0.0001)
);

create index if not exists idx_tournee_lignes_tournee
  on public.tournee_lignes (tournee_id);

comment on table public.tournee_lignes is
  'Dotation par produit : quantités attribuées, vendues et rendues (instantané du nom).';

create table if not exists public.consignes (
  id                 uuid primary key default gen_random_uuid(),
  owner_id           uuid not null,
  agent_id           uuid,
  client_id          bigint,
  client_nom         text,
  zone               text,
  tournee_id         uuid references public.tournees (id) on delete set null,
  libelle_contenant  text not null default 'Récipient',
  quantite           integer not null check (quantite > 0),
  quantite_recuperee integer not null default 0 check (quantite_recuperee >= 0),
  statut             text not null default 'chez_client'
                     check (statut in ('chez_client', 'partielle', 'recuperee', 'perdue')),
  date_consigne      timestamptz not null default now(),
  derniere_maj       timestamptz not null default now(),
  note               text,
  constraint consignes_recuperation_coherente
    check (quantite_recuperee <= quantite)
);

create index if not exists idx_consignes_owner_statut
  on public.consignes (owner_id, statut);
create index if not exists idx_consignes_client
  on public.consignes (client_id);

comment on table public.consignes is
  'Récipients de l''entreprise restés chez un client (casiers, bouteilles vides…).';

create table if not exists public.bonus_clients (
  id           uuid primary key default gen_random_uuid(),
  owner_id     uuid not null,
  agent_id     uuid,
  client_id    bigint,
  client_nom   text,
  tournee_id   uuid references public.tournees (id) on delete set null,
  nature       text not null default 'remise'
               check (nature in ('remise', 'cadeau', 'fidelite', 'autre')),
  montant      real not null default 0 check (montant >= 0),
  description  text,
  date_bonus   timestamptz not null default now()
);

create index if not exists idx_bonus_owner_date
  on public.bonus_clients (owner_id, date_bonus desc);

comment on table public.bonus_clients is
  'Bonus, remises et cadeaux accordés à un client, rattachés à un agent et une tournée.';

-- Compteur journalier des références de tournée.
create table if not exists public.compteurs_tournee (
  owner_id uuid    not null,
  jour     date    not null default current_date,
  dernier  integer not null default 0,
  primary key (owner_id, jour)
);

comment on table public.compteurs_tournee is
  'Compteur des références de tournée (TOU-AAAAMMJJ-XXXX) par boutique et par jour.';

create or replace function public.prochain_numero_tournee(
  p_owner uuid,
  p_jour  date default current_date
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_dernier integer;
begin
  insert into public.compteurs_tournee (owner_id, jour, dernier)
  values (p_owner, p_jour, 1)
  on conflict (owner_id, jour)
  do update set dernier = compteurs_tournee.dernier + 1
  returning dernier into v_dernier;

  return 'TOU-' || to_char(p_jour, 'YYYYMMDD') || '-' || lpad(v_dernier::text, 4, '0');
end;
$$;

revoke all on function public.prochain_numero_tournee(uuid, date) from public;
grant execute on function public.prochain_numero_tournee(uuid, date) to authenticated;


-- ============================================================================
--  3. RLS — LECTURE SEULE CÔTÉ CLIENT, ÉCRITURES PAR RPC
-- ============================================================================

alter table public.tournees         enable row level security;
alter table public.tournee_lignes   enable row level security;
alter table public.consignes        enable row level security;
alter table public.bonus_clients    enable row level security;
alter table public.compteurs_tournee enable row level security;

do $$
declare
  r record;
begin
  -- Policies du module 23 uniquement (les autres modules ne sont pas touchés).
  for r in
    select tablename, policyname from pg_policies
     where schemaname = 'public'
       and tablename in ('tournees', 'tournee_lignes', 'consignes',
                         'bonus_clients', 'compteurs_tournee')
       and policyname like 'm23_%'
  loop
    execute format('drop policy if exists %I on public.%I', r.policyname, r.tablename);
  end loop;
end $$;

create policy m23_tournees_lecture on public.tournees
  for select to authenticated
  using (
    owner_id = auth.uid()
    or owner_id = public.mon_proprietaire()
    or agent_id = auth.uid()
    or public.est_plateforme()
  );

create policy m23_tournee_lignes_lecture on public.tournee_lignes
  for select to authenticated
  using (
    exists (
      select 1 from public.tournees t
       where t.id = tournee_lignes.tournee_id
         and (t.owner_id = auth.uid()
              or t.owner_id = public.mon_proprietaire()
              or t.agent_id = auth.uid()
              or public.est_plateforme())
    )
  );

create policy m23_consignes_lecture on public.consignes
  for select to authenticated
  using (
    owner_id = auth.uid()
    or owner_id = public.mon_proprietaire()
    or agent_id = auth.uid()
    or public.est_plateforme()
  );

create policy m23_bonus_lecture on public.bonus_clients
  for select to authenticated
  using (
    owner_id = auth.uid()
    or owner_id = public.mon_proprietaire()
    or agent_id = auth.uid()
    or public.est_plateforme()
  );

-- Aucune policy sur compteurs_tournee : seul le definer y accède.

-- Écritures directes refusées (tout passe par les RPC).
revoke insert, update, delete on public.tournees          from public, anon, authenticated;
revoke insert, update, delete on public.tournee_lignes    from public, anon, authenticated;
revoke insert, update, delete on public.consignes         from public, anon, authenticated;
revoke insert, update, delete on public.bonus_clients     from public, anon, authenticated;
revoke insert, update, delete on public.compteurs_tournee from public, anon, authenticated;


-- ============================================================================
--  4. RPC — PRÉPARATION ET SUIVI DE LA TOURNÉE
-- ============================================================================

create or replace function public.rpc_tournee_creer(
  p_agent  uuid,
  p_date   date default current_date,
  p_zone   text default null,
  p_note   text default null,
  p_lignes jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user       uuid := auth.uid();
  v_owner      uuid;
  v_tournee    uuid := gen_random_uuid();
  v_reference  text;
  v_ligne      jsonb;
  v_pid        bigint;
  v_qte        numeric;
  v_nom        text;
  v_unite      text;
  v_prix       numeric;
  v_owner_prod uuid;
  v_nb         integer := 0;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour préparer une tournée.';
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  if v_user <> v_owner and not public.est_plateforme() then
    raise exception 'DROIT_REFUSE|Seul le propriétaire prépare une tournée.';
  end if;

  if p_agent is null then
    raise exception 'AGENT_REQUIS|Choisissez l''agent qui part en tournée.';
  end if;

  if not exists (
    select 1 from public.utilisateurs u
     where u.id = p_agent
       and (u.id = v_owner or u.parent_id = v_owner)
  ) then
    raise exception 'AGENT_INVALIDE|Cet agent n''appartient pas à votre entreprise.';
  end if;

  if exists (
    select 1 from public.tournees t
     where t.agent_id = p_agent
       and t.statut in ('preparee', 'en_cours')
  ) then
    raise exception 'TOURNEE_ACTIVE|Cet agent a déjà une tournée en cours : clôturez-la avant d''en préparer une nouvelle.';
  end if;

  if p_lignes is null
     or jsonb_typeof(p_lignes) <> 'array'
     or jsonb_array_length(p_lignes) = 0 then
    raise exception 'LIGNES_VIDES|Ajoutez au moins un produit à la dotation.';
  end if;

  v_reference := public.prochain_numero_tournee(v_owner, coalesce(p_date, current_date));

  insert into public.tournees (
    id, owner_id, agent_id, reference, date_tournee, zone, note, statut, cree_par
  ) values (
    v_tournee, v_owner, p_agent, v_reference, coalesce(p_date, current_date),
    nullif(btrim(coalesce(p_zone, '')), ''),
    nullif(btrim(coalesce(p_note, '')), ''),
    'preparee', v_user
  );

  for v_ligne in select * from jsonb_array_elements(p_lignes)
  loop
    v_pid := nullif(v_ligne->>'produit_id', '')::bigint;
    v_qte := coalesce((v_ligne->>'quantite')::numeric, 0);

    if v_pid is null or v_qte <= 0 then
      raise exception 'LIGNE_INVALIDE|Chaque ligne doit avoir un article et une quantité positive.';
    end if;

    select p.nom, p.unite_mesure, p.prix_vente, p.owner_id
      into v_nom, v_unite, v_prix, v_owner_prod
      from public.produits p
     where p.id = v_pid;

    if not found then
      raise exception 'PRODUIT_INTROUVABLE|Article n° % introuvable.', v_pid;
    end if;

    if v_owner_prod is distinct from v_owner and not public.est_plateforme() then
      raise exception 'HORS_BOUTIQUE|L''article % n''appartient pas à votre boutique.', v_nom;
    end if;

    insert into public.tournee_lignes (
      tournee_id, produit_id, nom_produit, unite,
      quantite_attribuee, prix_vente
    ) values (
      v_tournee, v_pid, v_nom, v_unite, v_qte, v_prix
    )
    on conflict (tournee_id, produit_id)
    do update set
      quantite_attribuee = tournee_lignes.quantite_attribuee
                           + excluded.quantite_attribuee;

    v_nb := v_nb + 1;
  end loop;

  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(), null, 'TOURNEE_CREEE', v_user,
    jsonb_build_object(
      'tournee', v_tournee, 'reference', v_reference,
      'agent', p_agent, 'lignes', v_nb, 'zone', p_zone
    ),
    now()
  );

  return jsonb_build_object(
    'ok', true,
    'id', v_tournee,
    'reference', v_reference,
    'agent_id', p_agent,
    'date_tournee', coalesce(p_date, current_date),
    'lignes', v_nb
  );
end;
$$;

comment on function public.rpc_tournee_creer(uuid, date, text, text, jsonb) is
  'Prépare une tournée (dotation) pour un agent : réservation, sans mouvement de stock.';


create or replace function public.rpc_tournee_demarrer(p_tournee uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_t    public.tournees%rowtype;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour démarrer une tournée.';
  end if;

  select * into v_t from public.tournees where id = p_tournee for update;
  if not found then
    raise exception 'TOURNEE_INTROUVABLE|Cette tournée n''existe plus.';
  end if;

  if not (v_user = v_t.owner_id or v_user = v_t.agent_id or public.est_plateforme()) then
    raise exception 'DROIT_REFUSE|Vous n''avez pas accès à cette tournée.';
  end if;

  if v_t.statut not in ('preparee', 'en_cours') then
    raise exception 'STATUT_INVALIDE|Cette tournée est déjà clôturée.';
  end if;

  update public.tournees
     set statut = 'en_cours',
         demarree_le = coalesce(demarree_le, now())
   where id = p_tournee;

  return jsonb_build_object('ok', true, 'id', p_tournee, 'statut', 'en_cours');
end;
$$;


-- ============================================================================
--  5. RPC — VENTE D'UN AGENT (CONTRAINTE PAR LA DOTATION)
-- ============================================================================

create or replace function public.rpc_tournee_vente(
  p_lignes             jsonb,
  p_mode_paiement      text default 'especes',
  p_montant_recu       numeric default null,
  p_numero_transaction text default null,
  p_client_id          bigint default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user    uuid := auth.uid();
  v_t       public.tournees%rowtype;
  v_l       public.tournee_lignes%rowtype;
  v_ligne   jsonb;
  v_pid     bigint;
  v_qte     numeric;
  v_dispo   numeric;
  v_payload jsonb := '[]'::jsonb;
  v_res     jsonb;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour vendre.';
  end if;

  -- La tournée EN COURS de l'agent connecté (une seule possible).
  select * into v_t
    from public.tournees
   where agent_id = v_user
     and statut = 'en_cours'
   order by date_tournee desc, cree_le desc
   limit 1
     for update;

  if not found then
    raise exception 'AUCUNE_TOURNEE|Aucune tournée en cours : demandez au patron de démarrer votre tournée.';
  end if;

  if p_lignes is null
     or jsonb_typeof(p_lignes) <> 'array'
     or jsonb_array_length(p_lignes) = 0 then
    raise exception 'PANIER_VIDE|Ajoutez au moins un article à la vente.';
  end if;

  for v_ligne in select * from jsonb_array_elements(p_lignes)
  loop
    v_pid := nullif(v_ligne->>'produit_id', '')::bigint;
    v_qte := coalesce((v_ligne->>'quantite')::numeric, 0);

    if v_pid is null or v_qte <= 0 then
      raise exception 'LIGNE_INVALIDE|Ligne de vente invalide.';
    end if;

    select * into v_l
      from public.tournee_lignes l
     where l.tournee_id = v_t.id
       and l.produit_id = v_pid
       for update;

    if not found then
      raise exception 'PRODUIT_NON_ATTRIBUE|Cet article ne fait pas partie de votre dotation du jour.';
    end if;

    v_dispo := v_l.quantite_attribuee - v_l.quantite_vendue - v_l.quantite_retournee;
    if v_dispo < v_qte then
      raise exception 'ATTRIBUTION_EPUISEE|Il ne vous reste que % de « % » : vente refusée.',
        v_dispo, v_l.nom_produit;
    end if;

    v_payload := v_payload || jsonb_build_object(
      'produit_id', v_pid,
      'quantite', v_qte,
      'quantite_vendue', v_qte
    );
  end loop;

  -- Vente RÉELLE : stock, prix relus en base, caisse, numéro, journal.
  v_res := public.rpc_vente_valider(
    v_payload,
    coalesce(p_mode_paiement, 'especes'),
    p_montant_recu,
    p_numero_transaction,
    p_client_id
  );

  -- Rattachement de la vente à la tournée (CA par agent).
  update public.ventes
     set tournee_id = v_t.id
   where vente_uuid = (v_res->>'vente_uuid')::uuid;

  -- Consommation de la dotation.
  for v_ligne in select * from jsonb_array_elements(p_lignes)
  loop
    v_pid := (v_ligne->>'produit_id')::bigint;
    v_qte := coalesce((v_ligne->>'quantite')::numeric, 0);
    update public.tournee_lignes
       set quantite_vendue = quantite_vendue + v_qte
     where tournee_id = v_t.id
       and produit_id = v_pid;
  end loop;

  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(), null, 'TOURNEE_VENTE', v_user,
    jsonb_build_object(
      'tournee', v_t.id, 'reference_tournee', v_t.reference,
      'numero_vente', v_res->>'numero_vente',
      'total', v_res->>'total'
    ),
    now()
  );

  return v_res || jsonb_build_object(
    'tournee_id', v_t.id,
    'reference_tournee', v_t.reference
  );
end;
$$;

comment on function public.rpc_tournee_vente(jsonb, text, numeric, text, bigint) is
  'Vente d''un agent, plafonnée par sa dotation ; délègue à rpc_vente_valider.';


-- ============================================================================
--  6. RPC — CLÔTURE (RETOURS ET ÉCARTS)
-- ============================================================================

create or replace function public.rpc_tournee_cloturer(
  p_tournee uuid,
  p_retours jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user     uuid := auth.uid();
  v_t        public.tournees%rowtype;
  v_l        public.tournee_lignes%rowtype;
  v_ligne    jsonb;
  v_pid      bigint;
  v_qte      numeric;
  v_ecart    numeric := 0;
  v_ca       numeric := 0;
  v_lignes   jsonb := '[]'::jsonb;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour clôturer une tournée.';
  end if;

  select * into v_t from public.tournees where id = p_tournee for update;
  if not found then
    raise exception 'TOURNEE_INTROUVABLE|Cette tournée n''existe plus.';
  end if;

  if not (v_user = v_t.owner_id or v_user = v_t.agent_id or public.est_plateforme()) then
    raise exception 'DROIT_REFUSE|Vous n''avez pas accès à cette tournée.';
  end if;

  if v_t.statut <> 'en_cours' then
    raise exception 'STATUT_INVALIDE|Seule une tournée EN COURS peut être clôturée.';
  end if;

  -- Les retours déclarés remplacent la valeur précédente (reprise possible).
  for v_ligne in select * from jsonb_array_elements(coalesce(p_retours, '[]'::jsonb))
  loop
    v_pid := nullif(v_ligne->>'produit_id', '')::bigint;
    v_qte := coalesce((v_ligne->>'quantite')::numeric, 0);

    if v_pid is null or v_qte < 0 then
      raise exception 'LIGNE_INVALIDE|Retour invalide.';
    end if;

    select * into v_l from public.tournee_lignes l
     where l.tournee_id = p_tournee and l.produit_id = v_pid
       for update;

    if not found then
      raise exception 'PRODUIT_NON_ATTRIBUE|Cet article ne fait pas partie de la tournée.';
    end if;

    if v_l.quantite_vendue + v_qte > v_l.quantite_attribuee + 0.0001 then
      raise exception 'RETOUR_SUPERIEUR|Le retour dépasse ce qui restait pour « % ».', v_l.nom_produit;
    end if;

    update public.tournee_lignes
       set quantite_retournee = v_qte
     where id = v_l.id;
  end loop;

  -- Consolidation ligne par ligne.
  for v_l in
    select * from public.tournee_lignes where tournee_id = p_tournee order by nom_produit
  loop
    v_ecart := v_ecart + (v_l.quantite_attribuee - v_l.quantite_vendue - v_l.quantite_retournee);
    v_lignes := v_lignes || jsonb_build_object(
      'produit_id', v_l.produit_id,
      'nom', v_l.nom_produit,
      'unite', v_l.unite,
      'attribuee', v_l.quantite_attribuee,
      'vendue', v_l.quantite_vendue,
      'retournee', v_l.quantite_retournee,
      'ecart', v_l.quantite_attribuee - v_l.quantite_vendue - v_l.quantite_retournee
    );
  end loop;

  select coalesce(sum(v.prix), 0) into v_ca
    from public.ventes v
   where v.tournee_id = p_tournee;

  update public.tournees
     set statut = 'cloturee',
         cloturee_le = now()
   where id = p_tournee;

  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(), null, 'TOURNEE_CLOTUREE', v_user,
    jsonb_build_object(
      'tournee', p_tournee, 'reference', v_t.reference,
      'ca', v_ca, 'ecart', v_ecart
    ),
    now()
  );

  return jsonb_build_object(
    'ok', true,
    'id', p_tournee,
    'reference', v_t.reference,
    'statut', 'cloturee',
    'chiffre_affaires', v_ca,
    'ecart_total', v_ecart,
    'lignes', v_lignes
  );
end;
$$;


-- ============================================================================
--  7. RPC — MA TOURNÉE (AGENT)
-- ============================================================================

create or replace function public.rpc_ma_tournee()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_t    public.tournees%rowtype;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour voir votre tournée.';
  end if;

  select * into v_t
    from public.tournees
   where agent_id = v_user
     and statut in ('preparee', 'en_cours')
   order by date_tournee desc, cree_le desc
   limit 1;

  if not found then
    return jsonb_build_object('ok', false, 'motif', 'AUCUNE_TOURNEE');
  end if;

  return jsonb_build_object(
    'ok', true,
    'tournee', jsonb_build_object(
      'id', v_t.id,
      'reference', v_t.reference,
      'date_tournee', v_t.date_tournee,
      'zone', v_t.zone,
      'statut', v_t.statut,
      'note', v_t.note
    ),
    'lignes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'produit_id', l.produit_id,
        'nom', l.nom_produit,
        'unite', l.unite,
        'attribuee', l.quantite_attribuee,
        'vendue', l.quantite_vendue,
        'retournee', l.quantite_retournee,
        'restante', l.quantite_attribuee - l.quantite_vendue - l.quantite_retournee,
        'prix_vente', l.prix_vente
      ) order by l.nom_produit)
      from public.tournee_lignes l
      where l.tournee_id = v_t.id
    ), '[]'::jsonb),
    'consignes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', c.id,
        'client_id', c.client_id,
        'client_nom', c.client_nom,
        'zone', c.zone,
        'libelle', c.libelle_contenant,
        'quantite', c.quantite,
        'recuperee', c.quantite_recuperee,
        'restante', c.quantite - c.quantite_recuperee,
        'statut', c.statut,
        'date', c.date_consigne
      ) order by c.date_consigne desc)
      from public.consignes c
      where c.owner_id = v_t.owner_id
        and c.statut in ('chez_client', 'partielle')
    ), '[]'::jsonb),
    'bonus', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', b.id,
        'client_nom', b.client_nom,
        'nature', b.nature,
        'montant', b.montant,
        'description', b.description,
        'date', b.date_bonus
      ) order by b.date_bonus desc)
      from public.bonus_clients b
      where b.agent_id = v_user
        and b.date_bonus::date = current_date
    ), '[]'::jsonb)
  );
end;
$$;


-- ============================================================================
--  8. RPC — RAPPORT PAR AGENT (PATRON)
-- ============================================================================

create or replace function public.rpc_tournee_rapport(
  p_debut date default (current_date - 30),
  p_fin   date default current_date,
  p_agent uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user  uuid := auth.uid();
  v_owner uuid;
  v_lignes jsonb;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour consulter le rapport.';
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  if v_user <> v_owner and not public.est_plateforme() then
    raise exception 'DROIT_REFUSE|Seul le propriétaire consulte le rapport de distribution.';
  end if;

  select coalesce(jsonb_agg(x order by x.date_tournee desc, x.reference desc), '[]'::jsonb)
    into v_lignes
    from (
      select
        t.id,
        t.reference,
        t.date_tournee,
        t.zone,
        t.statut,
        coalesce(u.nom, 'Agent supprimé') as agent_nom,
        t.agent_id,
        (select count(*) from public.tournee_lignes l where l.tournee_id = t.id) as nb_articles,
        coalesce((select sum(l.quantite_attribuee) from public.tournee_lignes l
                   where l.tournee_id = t.id), 0) as quantite_attribuee,
        coalesce((select sum(l.quantite_vendue) from public.tournee_lignes l
                   where l.tournee_id = t.id), 0) as quantite_vendue,
        coalesce((select sum(l.quantite_retournee) from public.tournee_lignes l
                   where l.tournee_id = t.id), 0) as quantite_retournee,
        coalesce((select sum(l.quantite_attribuee - l.quantite_vendue - l.quantite_retournee)
                    from public.tournee_lignes l where l.tournee_id = t.id), 0) as ecart,
        coalesce((select sum(v.prix) from public.ventes v where v.tournee_id = t.id), 0) as chiffre_affaires,
        coalesce((select sum(c.quantite - c.quantite_recuperee)
                    from public.consignes c
                   where c.tournee_id = t.id and c.statut in ('chez_client', 'partielle')), 0) as consignes_ouvertes,
        coalesce((select sum(c.quantite) from public.consignes c where c.tournee_id = t.id), 0) as consignes_total,
        coalesce((select sum(b.montant) from public.bonus_clients b where b.tournee_id = t.id), 0) as bonus_total
      from public.tournees t
      left join public.utilisateurs u on u.id = t.agent_id
      where t.owner_id = v_owner
        and t.date_tournee between coalesce(p_debut, current_date - 30) and coalesce(p_fin, current_date)
        and (p_agent is null or t.agent_id = p_agent)
    ) x;

  return jsonb_build_object(
    'ok', true,
    'debut', coalesce(p_debut, current_date - 30),
    'fin', coalesce(p_fin, current_date),
    'lignes', v_lignes,
    'totaux', jsonb_build_object(
      'tournees', (select count(*) from jsonb_array_elements(v_lignes)),
      'chiffre_affaires', (select coalesce(sum((e->>'chiffre_affaires')::numeric), 0)
                             from jsonb_array_elements(v_lignes) e),
      'quantite_vendue', (select coalesce(sum((e->>'quantite_vendue')::numeric), 0)
                            from jsonb_array_elements(v_lignes) e),
      'ecart', (select coalesce(sum((e->>'ecart')::numeric), 0)
                  from jsonb_array_elements(v_lignes) e),
      'consignes_ouvertes', (select coalesce(sum((e->>'consignes_ouvertes')::numeric), 0)
                               from jsonb_array_elements(v_lignes) e),
      'bonus', (select coalesce(sum((e->>'bonus_total')::numeric), 0)
                  from jsonb_array_elements(v_lignes) e)
    )
  );
end;
$$;


-- ============================================================================
--  9. RPC — CONSIGNES ET BONUS
-- ============================================================================

create or replace function public.rpc_consigne_enregistrer(
  p_client_id  bigint default null,
  p_client_nom text default null,
  p_zone       text default null,
  p_libelle    text default 'Récipient',
  p_quantite   integer default 1,
  p_note       text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user   uuid := auth.uid();
  v_owner  uuid;
  v_id     uuid := gen_random_uuid();
  v_nom    text;
  v_zone   text;
  v_tournee uuid;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour enregistrer une consigne.';
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  if not (v_user = v_owner
          or exists (select 1 from public.utilisateurs u
                      where u.id = v_user and u.parent_id = v_owner)
          or public.est_plateforme()) then
    raise exception 'DROIT_REFUSE|Vous n''appartenez pas à cette entreprise.';
  end if;

  if coalesce(p_quantite, 0) <= 0 then
    raise exception 'QUANTITE_INVALIDE|Indiquez au moins un récipient.';
  end if;

  select nullif(btrim(coalesce(p_client_nom, '')), '') into v_nom;
  select nullif(btrim(coalesce(p_zone, '')), '') into v_zone;

  if p_client_id is not null then
    select c.nom, nullif(btrim(coalesce(p_zone, c.zone, '')), '')
      into v_nom, v_zone
      from public.clients c
     where c.id = p_client_id;

    if not found then
      raise exception 'CLIENT_INTROUVABLE|Ce client n''existe plus.';
    end if;

    if v_zone is not null then
      update public.clients set zone = v_zone where id = p_client_id;
    end if;
  end if;

  select t.id into v_tournee
    from public.tournees t
   where t.agent_id = v_user and t.statut = 'en_cours'
   order by t.date_tournee desc
   limit 1;

  insert into public.consignes (
    id, owner_id, agent_id, client_id, client_nom, zone, tournee_id,
    libelle_contenant, quantite, note
  ) values (
    v_id, v_owner, v_user, p_client_id, v_nom, v_zone, v_tournee,
    coalesce(nullif(btrim(coalesce(p_libelle, '')), ''), 'Récipient'),
    p_quantite, nullif(btrim(coalesce(p_note, '')), '')
  );

  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(), null, 'CONSIGNE_AJOUTEE', v_user,
    jsonb_build_object('consigne', v_id, 'client', v_nom,
                       'quantite', p_quantite, 'zone', v_zone),
    now()
  );

  return jsonb_build_object('ok', true, 'id', v_id, 'quantite', p_quantite);
end;
$$;


create or replace function public.rpc_consigne_recuperer(
  p_consigne uuid,
  p_quantite integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user  uuid := auth.uid();
  v_c     public.consignes%rowtype;
  v_rest  integer;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour récupérer une consigne.';
  end if;

  select * into v_c from public.consignes where id = p_consigne for update;
  if not found then
    raise exception 'CONSIGNE_INTROUVABLE|Cette consigne n''existe plus.';
  end if;

  if not (v_user = v_c.owner_id or v_user = v_c.agent_id
          or v_c.owner_id = public.mon_proprietaire()
          or public.est_plateforme()) then
    raise exception 'DROIT_REFUSE|Vous n''avez pas accès à cette consigne.';
  end if;

  v_rest := v_c.quantite - v_c.quantite_recuperee;

  if coalesce(p_quantite, 0) <= 0 or p_quantite > v_rest then
    raise exception 'QUANTITE_INVALIDE|Il reste % récipient(s) à récupérer.', v_rest;
  end if;

  update public.consignes
     set quantite_recuperee = quantite_recuperee + p_quantite,
         statut = case
                    when quantite_recuperee + p_quantite >= quantite then 'recuperee'
                    else 'partielle'
                  end,
         derniere_maj = now()
   where id = p_consigne;

  return jsonb_build_object(
    'ok', true,
    'id', p_consigne,
    'restant', v_rest - p_quantite
  );
end;
$$;


create or replace function public.rpc_bonus_enregistrer(
  p_client_id    bigint default null,
  p_client_nom   text default null,
  p_nature       text default 'remise',
  p_montant      numeric default 0,
  p_description  text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user    uuid := auth.uid();
  v_owner   uuid;
  v_id      uuid := gen_random_uuid();
  v_nom     text;
  v_nature  text := lower(btrim(coalesce(p_nature, 'remise')));
  v_tournee uuid;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour enregistrer un bonus.';
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  if not (v_user = v_owner
          or exists (select 1 from public.utilisateurs u
                      where u.id = v_user and u.parent_id = v_owner)
          or public.est_plateforme()) then
    raise exception 'DROIT_REFUSE|Vous n''appartenez pas à cette entreprise.';
  end if;

  if v_nature not in ('remise', 'cadeau', 'fidelite', 'autre') then
    raise exception 'NATURE_INVALIDE|Type de bonus inconnu.';
  end if;

  if coalesce(p_montant, 0) < 0 then
    raise exception 'MONTANT_INVALIDE|Le montant du bonus ne peut pas être négatif.';
  end if;

  select nullif(btrim(coalesce(p_client_nom, '')), '') into v_nom;
  if p_client_id is not null then
    select c.nom into v_nom from public.clients c where c.id = p_client_id;
    if not found then
      raise exception 'CLIENT_INTROUVABLE|Ce client n''existe plus.';
    end if;
  end if;

  select t.id into v_tournee
    from public.tournees t
   where t.agent_id = v_user and t.statut = 'en_cours'
   order by t.date_tournee desc
   limit 1;

  insert into public.bonus_clients (
    id, owner_id, agent_id, client_id, client_nom, tournee_id,
    nature, montant, description
  ) values (
    v_id, v_owner, v_user, p_client_id, v_nom, v_tournee,
    v_nature, coalesce(p_montant, 0),
    nullif(btrim(coalesce(p_description, '')), '')
  );

  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(), null, 'BONUS_CLIENT', v_user,
    jsonb_build_object('bonus', v_id, 'client', v_nom,
                       'nature', v_nature, 'montant', p_montant),
    now()
  );

  return jsonb_build_object('ok', true, 'id', v_id);
end;
$$;


-- ============================================================================
-- 10. RPC — COMPTEURS DE LA CARTE D'ACCUEIL
-- ============================================================================

create or replace function public.rpc_distribution_accueil()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user  uuid := auth.uid();
  v_owner uuid;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  return jsonb_build_object(
    'ok', true,
    'tournees_actives', (
      select count(*) from public.tournees t
       where t.owner_id = v_owner and t.statut in ('preparee', 'en_cours')
    ),
    'agents_actifs', (
      select count(distinct t.agent_id) from public.tournees t
       where t.owner_id = v_owner and t.statut in ('preparee', 'en_cours')
    ),
    'consignes_ouvertes', (
      select coalesce(sum(c.quantite - c.quantite_recuperee), 0)
        from public.consignes c
       where c.owner_id = v_owner and c.statut in ('chez_client', 'partielle')
    ),
    'bonus_mois', (
      select coalesce(sum(b.montant), 0)
        from public.bonus_clients b
       where b.owner_id = v_owner
         and b.date_bonus >= date_trunc('month', now())
    )
  );
end;
$$;


-- ============================================================================
-- 11. RPC — STATISTIQUES DE L'ACCUEIL (SOURCE DE VÉRITÉ SERVEUR)
-- ============================================================================
--  Le tableau de bord lisait la copie SQLite du téléphone : une vente faite
--  sur un autre appareil n'y apparaissait qu'après synchronisation. Ces
--  chiffres sont désormais calculés par le serveur, sur les vraies lignes.

create or replace function public.rpc_accueil_stats()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user  uuid := auth.uid();
  v_owner uuid;
  -- Minuit LOCAL (Lubumbashi, UTC+2) : une vente de 23 h compte bien dans la
  -- journée du commerçant, pas dans celle du serveur UTC.
  v_debut timestamptz :=
    (date_trunc('day', now() at time zone 'Africa/Lubumbashi'))
      at time zone 'Africa/Lubumbashi';
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  return jsonb_build_object(
    'ok', true,
    'produits', (
      select count(*) from public.produits p where p.owner_id = v_owner
    ),
    'stock_alertes', (
      select count(*) from public.produits p
       where p.owner_id = v_owner
         and not coalesce(p.stock_illimite, false)
         and coalesce(p.quantite, 0) <= coalesce(p.seuil_alerte, 5)
    ),
    'ventes_jour', (
      select count(*) from public.ventes v
       where v.owner_id = v_owner and v.date >= v_debut
    ),
    'ca_jour', (
      select coalesce(sum(v.prix), 0) from public.ventes v
       where v.owner_id = v_owner and v.date >= v_debut
    ),
    'ca_total', (
      select coalesce(sum(v.prix), 0) from public.ventes v
       where v.owner_id = v_owner
    )
  );
end;
$$;

revoke all on function public.rpc_accueil_stats() from public;
grant execute on function public.rpc_accueil_stats() to authenticated;


-- ============================================================================
-- 12. DROITS D'EXÉCUTION
-- ============================================================================

revoke all on function public.rpc_tournee_creer(uuid, date, text, text, jsonb) from public;
revoke all on function public.rpc_tournee_demarrer(uuid) from public;
revoke all on function public.rpc_tournee_vente(jsonb, text, numeric, text, bigint) from public;
revoke all on function public.rpc_tournee_cloturer(uuid, jsonb) from public;
revoke all on function public.rpc_ma_tournee() from public;
revoke all on function public.rpc_tournee_rapport(date, date, uuid) from public;
revoke all on function public.rpc_consigne_enregistrer(bigint, text, text, text, integer, text) from public;
revoke all on function public.rpc_consigne_recuperer(uuid, integer) from public;
revoke all on function public.rpc_bonus_enregistrer(bigint, text, text, numeric, text) from public;
revoke all on function public.rpc_distribution_accueil() from public;
revoke all on function public.rpc_accueil_stats() from public;

grant execute on function public.rpc_tournee_creer(uuid, date, text, text, jsonb) to authenticated;
grant execute on function public.rpc_tournee_demarrer(uuid) to authenticated;
grant execute on function public.rpc_tournee_vente(jsonb, text, numeric, text, bigint) to authenticated;
grant execute on function public.rpc_tournee_cloturer(uuid, jsonb) to authenticated;
grant execute on function public.rpc_ma_tournee() to authenticated;
grant execute on function public.rpc_tournee_rapport(date, date, uuid) to authenticated;
grant execute on function public.rpc_consigne_enregistrer(bigint, text, text, text, integer, text) to authenticated;
grant execute on function public.rpc_consigne_recuperer(uuid, integer) to authenticated;
grant execute on function public.rpc_bonus_enregistrer(bigint, text, text, numeric, text) to authenticated;
grant execute on function public.rpc_distribution_accueil() to authenticated;
grant execute on function public.rpc_accueil_stats() to authenticated;


-- ============================================================================
-- 13. TEMPS RÉEL — LA VÉRITÉ ARRIVE SUR TOUS LES TÉLÉPHONES
-- ============================================================================
--  Sans cette publication, les abonnements Realtime de l'application ne
--  reçoivent AUCUN événement : c'est l'une des causes du tableau de bord
--  figé et des produits « qui traînent » d'un appareil à l'autre.

do $$
declare
  t text;
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    foreach t in array array[
      'produits', 'conditionnements', 'ventes', 'clients', 'caisse',
      'tournees', 'tournee_lignes', 'consignes', 'bonus_clients'
    ]
    loop
      if not exists (
        select 1 from pg_publication_tables
         where pubname = 'supabase_realtime'
           and schemaname = 'public'
           and tablename = t
      ) then
        execute format('alter publication supabase_realtime add table public.%I', t);
        raise notice 'Realtime activé pour public.%', t;
      end if;
    end loop;
  else
    raise notice 'Publication supabase_realtime absente : temps réel non configuré.';
  end if;
end $$;


-- ============================================================================
-- 14. VÉRIFICATIONS
-- ============================================================================

select table_name
  from information_schema.tables
 where table_schema = 'public'
   and table_name in ('tournees', 'tournee_lignes', 'consignes',
                      'bonus_clients', 'compteurs_tournee')
 order by table_name;

select proname
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and (proname like 'rpc_tournee%' or proname like 'rpc_consigne%'
        or proname = 'rpc_ma_tournee' or proname = 'rpc_bonus_enregistrer'
        or proname = 'rpc_distribution_accueil')
 order by proname;
