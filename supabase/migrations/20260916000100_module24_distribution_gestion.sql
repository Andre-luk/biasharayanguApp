-- ============================================================================
--  biashara_yangu — MODULE 24 : DISTRIBUTION (PRODUCTION, STOCK, TERRAIN)
--  Migration 20260916000100_module24_distribution_gestion.sql
-- ============================================================================
--
--  OBJET
--  -----
--  Donner au module Distribution sa propre organisation : collaborateurs
--  dédiés, stock d'INTRANTS séparé du stock de PRODUITS FINIS, réceptions à
--  double confirmation, demandes d'intrants de la production, productions
--  avec pertes motivées, demandes de produits des commerciaux, retours,
--  remises d'argent à TROIS confirmations, caisse et dépenses propres.
--
--  PRINCIPES NON NÉGOCIABLES
--  -------------------------
--   • Aucune quantité ne bouge sans un mouvement tracé (`dist_mouvements`).
--   • Les produits finis n'entrent en stock QU'APRÈS confirmation du stock.
--   • L'argent d'une vente n'entre en caisse QU'APRÈS la validation du
--     gérant (commercial → comptable → gérant).
--   • Chaque écriture passe par une RPC `security definer` : les tables
--     n'ont AUCUNE policy d'écriture (les droits sont vérifiés côté serveur).
--   • Les modules des autres activités ne sont PAS modifiés.
--
--  ⚠️ IDEMPOTENTE : relançable sans effet de bord.
--  ⚠️ À exécuter dans Supabase → SQL Editor.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);


-- ============================================================================
--  1. LE RÔLE DISTRIBUTION DU COMPTE
-- ============================================================================
--  Le rôle global (`utilisateurs.new_role`) reste la matrice de l'application.
--  Le rôle DISTRIBUTION est plus fin : il décide de ce que chacun fait dans
--  CE module (production, stock, gérant, commercial, comptable).
--  Un compte peut donc être VENDEUR (rôle global) et GÉRANT distribution.

do $$
begin
  if to_regclass('public.utilisateurs') is null then
    raise exception 'La table public.utilisateurs est absente.';
  end if;

  if not exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'utilisateurs'
       and column_name = 'role_distribution'
  ) then
    alter table public.utilisateurs
      add column role_distribution text;
  end if;

  if not exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'utilisateurs'
       and column_name = 'dist_actif'
  ) then
    alter table public.utilisateurs
      add column dist_actif boolean not null default true;
  end if;
end $$;

create index if not exists idx_utilisateurs_role_distribution
  on public.utilisateurs (parent_id, role_distribution);

comment on column public.utilisateurs.role_distribution is
  'Module 24 — rôle DANS la distribution : proprietaire, gerant, production, stock, commercial, comptable.';


-- ============================================================================
--  2. HELPERS DU MODULE
-- ============================================================================

create or replace function public.dist_role()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select case
           when auth.uid() is not null
                and public.mon_proprietaire() = auth.uid()
             then 'proprietaire'
           else coalesce(
             nullif(lower(btrim((
               select u.role_distribution
                 from public.utilisateurs u
                where u.id = auth.uid()
             ))), ''),
             'aucun')
         end;
$$;

comment on function public.dist_role() is
  'Module 24 — rôle du compte connecté dans la distribution du patron.';

create or replace function public.dist_est_membre(p_owner uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select auth.uid() is not null
     and (
       auth.uid() = p_owner
       or exists (
         select 1 from public.utilisateurs u
          where u.id = auth.uid() and u.parent_id = p_owner
       )
     );
$$;

create or replace function public.dist_owner_requis()
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_owner uuid := public.mon_proprietaire();
begin
  if v_owner is null then
    raise exception 'SESSION_ABSENTE|Aucune entreprise rattachée à ce compte.';
  end if;
  return v_owner;
end;
$$;

create or replace function public.dist_exige(p_roles text[])
returns void
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_role text := public.dist_role();
begin
  if not (v_role = any (p_roles)) then
    raise exception 'DROIT_REFUSE|Opération réservée aux rôles : %.',
      array_to_string(p_roles, ', ');
  end if;
end;
$$;

create or replace function public.dist_journaliser(
  p_owner      uuid,
  p_action     text,
  p_entite     text,
  p_entite_id  uuid,
  p_details    jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.dist_journal (owner_id, action, entite, entite_id, details, auteur_id)
  values (p_owner, p_action, p_entite, p_entite_id, coalesce(p_details, '{}'::jsonb), auth.uid());
end;
$$;

create or replace function public.dist_numero(p_owner uuid, p_prefixe text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_n integer;
  v_jour date := current_date;
begin
  insert into public.dist_compteurs (owner_id, prefixe, jour, compteur)
  values (p_owner, upper(p_prefixe), v_jour, 1)
  on conflict (owner_id, prefixe, jour)
  do update set compteur = public.dist_compteurs.compteur + 1
  returning compteur into v_n;

  return upper(p_prefixe) || '-' || to_char(v_jour, 'YYYYMMDD') || '-' ||
         lpad(v_n::text, 4, '0');
end;
$$;

create or replace function public.dist_caisse_solde(p_owner uuid)
returns numeric
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_solde numeric;
begin
  select coalesce((select p.solde_initial from public.dist_parametres p
                    where p.owner_id = p_owner), 0)
       + coalesce((select sum(case when c.sens = 'entree' then c.montant
                                   else -c.montant end)
                     from public.dist_caisse c
                    where c.owner_id = p_owner), 0)
    into v_solde;
  return coalesce(v_solde, 0);
end;
$$;


-- ============================================================================
--  3. TABLES
-- ============================================================================

create table if not exists public.dist_parametres (
  owner_id                 uuid primary key,
  devise                   text   not null default 'CDF',
  solde_initial            numeric(16,2) not null default 0,
  autoriser_solde_negatif  boolean not null default false,
  updated_at               timestamptz not null default now()
);

create table if not exists public.dist_intrants (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid not null,
  code          text,
  nom           text not null,
  unite         text not null default 'unité',
  stock         numeric(16,3) not null default 0,
  seuil_alerte  numeric(16,3) not null default 0,
  prix_unitaire numeric(16,2) not null default 0,
  actif         boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists idx_dist_intrants_owner on public.dist_intrants (owner_id, actif);

create table if not exists public.dist_produits (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null,
  code        text,
  nom         text not null,
  format      text not null default 'farde',
  unite       text not null default 'unité',
  stock       numeric(16,3) not null default 0,
  prix_vente  numeric(16,2) not null default 0,
  prix_achat  numeric(16,2) not null default 0,
  actif       boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists idx_dist_produits_owner on public.dist_produits (owner_id, actif);

create table if not exists public.dist_stock_commercial (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid not null,
  commercial_id uuid not null,
  produit_id    uuid not null references public.dist_produits(id) on delete cascade,
  quantite      numeric(16,3) not null default 0,
  updated_at    timestamptz not null default now(),
  unique (commercial_id, produit_id)
);

create table if not exists public.dist_mouvements (
  id             bigint generated always as identity primary key,
  owner_id       uuid not null,
  nature         text not null check (nature in (
                   'intrant_entree', 'intrant_sortie_production',
                   'intrant_retour_production', 'production_entree',
                   'production_perte', 'transfert_commercial',
                   'retour_commercial', 'vente_commercial',
                   'regularisation_intrant', 'regularisation_produit')),
  intrant_id     uuid references public.dist_intrants(id) on delete set null,
  produit_id     uuid references public.dist_produits(id) on delete set null,
  commercial_id  uuid,
  quantite       numeric(16,3) not null,
  stock_avant    numeric(16,3),
  stock_apres    numeric(16,3),
  reference_type text,
  reference_id   uuid,
  motif          text,
  auteur_id      uuid,
  created_at     timestamptz not null default now(),
  check (intrant_id is not null or produit_id is not null)
);
create index if not exists idx_dist_mouvements_owner
  on public.dist_mouvements (owner_id, created_at desc);
create index if not exists idx_dist_mouvements_commercial
  on public.dist_mouvements (commercial_id, created_at desc);

create table if not exists public.dist_receptions (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid not null,
  numero        text not null,
  fournisseur   text,
  note          text,
  statut        text not null default 'attente_gerant'
                check (statut in ('attente_gerant', 'validee', 'refusee')),
  cree_par      uuid,
  cree_le       timestamptz not null default now(),
  confirme_par  uuid,
  confirme_le   timestamptz,
  motif         text
);
create index if not exists idx_dist_receptions_owner
  on public.dist_receptions (owner_id, statut, cree_le desc);

create table if not exists public.dist_reception_lignes (
  id                 uuid primary key default gen_random_uuid(),
  reception_id       uuid not null references public.dist_receptions(id) on delete cascade,
  intrant_id         uuid not null references public.dist_intrants(id),
  quantite_annoncee  numeric(16,3) not null default 0,
  quantite_comptee   numeric(16,3) not null default 0
);
create index if not exists idx_dist_reception_lignes_reception
  on public.dist_reception_lignes (reception_id);

create table if not exists public.dist_demandes_intrants (
  id             uuid primary key default gen_random_uuid(),
  owner_id       uuid not null,
  numero         text not null,
  demandeur_id   uuid not null,
  statut         text not null default 'attente_stock'
                 check (statut in ('attente_stock', 'refusee',
                                   'attente_reception', 'recue', 'en_litige')),
  note           text,
  motif          text,
  cree_le        timestamptz not null default now(),
  traite_par     uuid,
  traite_le      timestamptz,
  recu_par       uuid,
  recu_le        timestamptz
);
create index if not exists idx_dist_demandes_intrants_owner
  on public.dist_demandes_intrants (owner_id, statut, cree_le desc);

create table if not exists public.dist_demande_intrants_lignes (
  id                   uuid primary key default gen_random_uuid(),
  demande_id           uuid not null references public.dist_demandes_intrants(id) on delete cascade,
  intrant_id           uuid not null references public.dist_intrants(id),
  quantite_demandee    numeric(16,3) not null default 0,
  quantite_autorisee   numeric(16,3) not null default 0,
  quantite_sortie      numeric(16,3) not null default 0,
  quantite_recue       numeric(16,3),
  ecart_motif          text
);

create table if not exists public.dist_productions (
  id             uuid primary key default gen_random_uuid(),
  owner_id       uuid not null,
  numero         text not null,
  responsable_id uuid not null,
  demande_id     uuid references public.dist_demandes_intrants(id) on delete set null,
  statut         text not null default 'attente_stock'
                 check (statut in ('attente_stock', 'cloturee', 'en_litige')),
  motif_pertes   text,
  note           text,
  cree_le        timestamptz not null default now(),
  recepteur_id   uuid,
  recepte_le     timestamptz
);
create index if not exists idx_dist_productions_owner
  on public.dist_productions (owner_id, statut, cree_le desc);

create table if not exists public.dist_production_intrants (
  id                  uuid primary key default gen_random_uuid(),
  production_id       uuid not null references public.dist_productions(id) on delete cascade,
  intrant_id          uuid not null references public.dist_intrants(id),
  quantite_recue      numeric(16,3) not null default 0,
  quantite_consommee  numeric(16,3) not null default 0,
  quantite_perdue     numeric(16,3) not null default 0,
  quantite_restante   numeric(16,3) not null default 0
);

create table if not exists public.dist_production_sorties (
  id                  uuid primary key default gen_random_uuid(),
  production_id       uuid not null references public.dist_productions(id) on delete cascade,
  produit_id          uuid not null references public.dist_produits(id),
  quantite_produite   numeric(16,3) not null default 0,
  quantite_remise     numeric(16,3) not null default 0,
  quantite_recue      numeric(16,3),
  constat             text
);

create table if not exists public.dist_demandes_commercial (
  id                uuid primary key default gen_random_uuid(),
  owner_id          uuid not null,
  numero            text not null,
  commercial_id     uuid not null,
  statut            text not null default 'attente_production'
                    check (statut in ('attente_production', 'refusee_production',
                                      'attente_stock', 'refusee_stock',
                                      'attente_commercial', 'recue', 'en_litige')),
  note              text,
  motif             text,
  cree_le           timestamptz not null default now(),
  production_par    uuid,
  production_le     timestamptz,
  stock_par         uuid,
  stock_le          timestamptz,
  recu_le           timestamptz
);
create index if not exists idx_dist_demandes_commercial_owner
  on public.dist_demandes_commercial (owner_id, statut, cree_le desc);

create table if not exists public.dist_demande_commercial_lignes (
  id                   uuid primary key default gen_random_uuid(),
  demande_id           uuid not null references public.dist_demandes_commercial(id) on delete cascade,
  produit_id           uuid not null references public.dist_produits(id),
  quantite_demandee    numeric(16,3) not null default 0,
  quantite_confirmee   numeric(16,3) not null default 0,
  quantite_sortie      numeric(16,3) not null default 0,
  quantite_recue       numeric(16,3)
);

create table if not exists public.dist_clients (
  id             uuid primary key default gen_random_uuid(),
  owner_id       uuid not null,
  commercial_id  uuid not null,
  nom            text not null,
  telephone      text,
  adresse        text,
  zone           text,
  note           text,
  actif          boolean not null default true,
  cree_le        timestamptz not null default now()
);
create unique index if not exists dist_clients_unique
  on public.dist_clients (owner_id, commercial_id, lower(btrim(nom)),
                          coalesce(btrim(telephone), ''));
create index if not exists idx_dist_clients_commercial
  on public.dist_clients (commercial_id, actif);

create table if not exists public.dist_ventes (
  id              uuid primary key default gen_random_uuid(),
  owner_id        uuid not null,
  numero          text not null,
  commercial_id   uuid not null,
  client_id       uuid references public.dist_clients(id) on delete set null,
  total           numeric(16,2) not null default 0,
  montant_paye    numeric(16,2) not null default 0,
  credit          numeric(16,2) not null default 0,
  mode_paiement   text not null default 'especes',
  note            text,
  date_vente      timestamptz not null default now()
);
create index if not exists idx_dist_ventes_commercial
  on public.dist_ventes (commercial_id, date_vente desc);
create index if not exists idx_dist_ventes_owner
  on public.dist_ventes (owner_id, date_vente desc);

create table if not exists public.dist_vente_lignes (
  id             uuid primary key default gen_random_uuid(),
  vente_id       uuid not null references public.dist_ventes(id) on delete cascade,
  produit_id     uuid references public.dist_produits(id) on delete set null,
  nom_produit    text not null,
  quantite       numeric(16,3) not null default 0,
  prix_unitaire  numeric(16,2) not null default 0,
  total          numeric(16,2) not null default 0
);

create table if not exists public.dist_retours (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid not null,
  numero        text not null,
  commercial_id uuid not null,
  statut        text not null default 'attente_stock'
                check (statut in ('attente_stock', 'recue', 'en_litige')),
  note          text,
  motif         text,
  cree_le       timestamptz not null default now(),
  recepteur_id  uuid,
  recu_le       timestamptz
);
create index if not exists idx_dist_retours_owner
  on public.dist_retours (owner_id, statut, cree_le desc);

create table if not exists public.dist_retour_lignes (
  id                  uuid primary key default gen_random_uuid(),
  retour_id           uuid not null references public.dist_retours(id) on delete cascade,
  produit_id          uuid not null references public.dist_produits(id),
  quantite_declaree   numeric(16,3) not null default 0,
  quantite_recue      numeric(16,3)
);

create table if not exists public.dist_remises (
  id                 uuid primary key default gen_random_uuid(),
  owner_id           uuid not null,
  numero             text not null,
  commercial_id      uuid not null,
  montant_declare    numeric(16,2) not null default 0,
  montant_recu       numeric(16,2),
  montant_valide     numeric(16,2),
  mode_paiement      text not null default 'especes',
  statut             text not null default 'declaree'
                     check (statut in ('declaree', 'recue', 'litige',
                                       'validee', 'refusee')),
  motif              text,
  declare_le         timestamptz not null default now(),
  receptionnaire_id  uuid,
  recu_le            timestamptz,
  valide_par         uuid,
  valide_le          timestamptz
);
create index if not exists idx_dist_remises_owner
  on public.dist_remises (owner_id, statut, declare_le desc);

create table if not exists public.dist_caisse (
  id             bigint generated always as identity primary key,
  owner_id       uuid not null,
  sens           text not null check (sens in ('entree', 'sortie')),
  montant        numeric(16,2) not null check (montant > 0),
  motif          text not null,
  categorie      text,
  reference_type text,
  reference_id   uuid,
  auteur_id      uuid,
  created_at     timestamptz not null default now()
);
create index if not exists idx_dist_caisse_owner
  on public.dist_caisse (owner_id, created_at desc);

create table if not exists public.dist_depenses (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid not null,
  numero        text not null,
  categorie     text not null default 'autre',
  montant       numeric(16,2) not null check (montant > 0),
  devise        text not null default 'CDF',
  motif         text not null,
  date_depense  date not null default current_date,
  justificatif  text,
  statut        text not null default 'en_attente'
                check (statut in ('en_attente', 'validee', 'refusee')),
  cree_par      uuid,
  cree_le       timestamptz not null default now(),
  valide_par    uuid,
  valide_le     timestamptz,
  motif_refus   text
);
create index if not exists idx_dist_depenses_owner
  on public.dist_depenses (owner_id, statut, date_depense desc);

create table if not exists public.dist_anomalies (
  id             uuid primary key default gen_random_uuid(),
  owner_id       uuid not null,
  type           text not null,
  reference_type text,
  reference_id   uuid,
  description    text not null,
  quantite       numeric(16,3),
  montant        numeric(16,2),
  statut         text not null default 'ouverte'
                 check (statut in ('ouverte', 'resolue')),
  cree_le        timestamptz not null default now(),
  resolu_par     uuid,
  resolu_le      timestamptz,
  decision       text,
  motif          text
);
create index if not exists idx_dist_anomalies_owner
  on public.dist_anomalies (owner_id, statut, cree_le desc);

create table if not exists public.dist_journal (
  id         bigint generated always as identity primary key,
  owner_id   uuid not null,
  action     text not null,
  entite     text,
  entite_id  uuid,
  details    jsonb not null default '{}'::jsonb,
  auteur_id  uuid,
  created_at timestamptz not null default now()
);
create index if not exists idx_dist_journal_owner
  on public.dist_journal (owner_id, created_at desc);

create table if not exists public.dist_compteurs (
  owner_id  uuid not null,
  prefixe   text not null,
  jour      date not null default current_date,
  compteur  integer not null default 0,
  primary key (owner_id, prefixe, jour)
);


-- ============================================================================
--  4. MOUVEMENTS DE STOCK (le seul chemin autorisé)
-- ============================================================================

create or replace function public.dist_bouger_intrant(
  p_owner       uuid,
  p_intrant     uuid,
  p_delta       numeric,
  p_nature      text,
  p_ref_type    text,
  p_ref_id      uuid,
  p_motif       text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_avant numeric(16,3);
  v_apres numeric(16,3);
begin
  if p_delta is null or p_delta = 0 then
    return;
  end if;

  select i.stock into v_avant
    from public.dist_intrants i
   where i.id = p_intrant and i.owner_id = p_owner
   for update;

  if v_avant is null then
    raise exception 'INTRANT_INCONNU|Ce stock d''intrant n''existe pas.';
  end if;

  v_apres := v_avant + p_delta;
  if v_apres < -0.0001 then
    raise exception 'STOCK_INSUFFISANT|Stock insuffisant : % disponible(s).',
      trim(to_char(v_avant, 'FM999999990.###'));
  end if;

  update public.dist_intrants
     set stock = v_apres, updated_at = now()
   where id = p_intrant;

  insert into public.dist_mouvements (
    owner_id, nature, intrant_id, quantite, stock_avant, stock_apres,
    reference_type, reference_id, motif, auteur_id
  ) values (
    p_owner, p_nature, p_intrant, p_delta, v_avant, v_apres,
    p_ref_type, p_ref_id, p_motif, auth.uid()
  );
end;
$$;

create or replace function public.dist_bouger_produit(
  p_owner       uuid,
  p_produit     uuid,
  p_delta       numeric,
  p_nature      text,
  p_ref_type    text,
  p_ref_id      uuid,
  p_motif       text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_avant numeric(16,3);
  v_apres numeric(16,3);
begin
  if p_delta is null or p_delta = 0 then
    return;
  end if;

  select p.stock into v_avant
    from public.dist_produits p
   where p.id = p_produit and p.owner_id = p_owner
   for update;

  if v_avant is null then
    raise exception 'PRODUIT_INCONNU|Ce produit fini n''existe pas.';
  end if;

  v_apres := v_avant + p_delta;
  if v_apres < -0.0001 then
    raise exception 'STOCK_INSUFFISANT|Stock insuffisant : % disponible(s).',
      trim(to_char(v_avant, 'FM999999990.###'));
  end if;

  update public.dist_produits
     set stock = v_apres, updated_at = now()
   where id = p_produit;

  insert into public.dist_mouvements (
    owner_id, nature, produit_id, quantite, stock_avant, stock_apres,
    reference_type, reference_id, motif, auteur_id
  ) values (
    p_owner, p_nature, p_produit, p_delta, v_avant, v_apres,
    p_ref_type, p_ref_id, p_motif, auth.uid()
  );
end;
$$;

create or replace function public.dist_bouger_commercial(
  p_owner       uuid,
  p_commercial  uuid,
  p_produit     uuid,
  p_delta       numeric,
  p_nature      text,
  p_ref_type    text,
  p_ref_id      uuid,
  p_motif       text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_avant numeric(16,3);
  v_apres numeric(16,3);
begin
  insert into public.dist_stock_commercial (owner_id, commercial_id, produit_id, quantite)
  values (p_owner, p_commercial, p_produit, 0)
  on conflict (commercial_id, produit_id) do nothing;

  select s.quantite into v_avant
    from public.dist_stock_commercial s
   where s.commercial_id = p_commercial and s.produit_id = p_produit
   for update;

  v_apres := coalesce(v_avant, 0) + p_delta;
  if v_apres < -0.0001 then
    raise exception 'STOCK_COMMERCIAL_INSUFFISANT|Le commercial ne détient que % unité(s).',
      trim(to_char(coalesce(v_avant, 0), 'FM999999990.###'));
  end if;

  update public.dist_stock_commercial
     set quantite = v_apres, updated_at = now()
   where commercial_id = p_commercial and produit_id = p_produit;

  insert into public.dist_mouvements (
    owner_id, nature, produit_id, commercial_id, quantite,
    stock_avant, stock_apres, reference_type, reference_id, motif, auteur_id
  ) values (
    p_owner, p_nature, p_produit, p_commercial, p_delta,
    coalesce(v_avant, 0), v_apres, p_ref_type, p_ref_id, p_motif, auth.uid()
  );
end;
$$;

create or replace function public.dist_anomalie(
  p_owner uuid, p_type text, p_ref_type text, p_ref_id uuid,
  p_description text, p_quantite numeric default null,
  p_montant numeric default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  insert into public.dist_anomalies (
    owner_id, type, reference_type, reference_id, description, quantite, montant
  ) values (
    p_owner, p_type, p_ref_type, p_ref_id, p_description, p_quantite, p_montant
  ) returning id into v_id;

  perform public.dist_journaliser(p_owner, 'ANOMALIE_OUVERTE', p_ref_type, p_ref_id,
    jsonb_build_object('anomalie_id', v_id, 'type', p_type,
                       'description', p_description, 'quantite', p_quantite));
  return v_id;
end;
$$;


-- ============================================================================
--  5. COLLABORATEURS DISTRIBUTION
-- ============================================================================

create or replace function public.dist_collaborateurs_lister()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_owner uuid := public.dist_owner_requis();
  v_items jsonb;
begin
  perform public.dist_exige(array['proprietaire', 'gerant']);

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', u.id,
           'nom', u.nom,
           'prenom', u.prenom,
           'email', u.email,
           'telephone', u.telephone,
           'role_distribution', u.role_distribution,
           'role_global', u.new_role,
           'actif', coalesce(u.dist_actif, true),
           'valide', u.valide
         ) order by u.role_distribution, u.nom), '[]'::jsonb)
    into v_items
    from public.utilisateurs u
   where u.parent_id = v_owner;

  return jsonb_build_object('ok', true, 'role', public.dist_role(),
                            'items', v_items);
end;
$$;

create or replace function public.dist_collaborateur_creer(
  p_nom           text,
  p_prenom        text,
  p_email         text,
  p_telephone     text,
  p_mot_de_passe  text,
  p_role          text,
  p_identifiant   text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, auth
as $$
declare
  v_owner    uuid := public.dist_owner_requis();
  v_role     text := lower(btrim(coalesce(p_role, '')));
  v_email    text := lower(btrim(coalesce(p_email, '')));
  v_nom      text := nullif(btrim(coalesce(p_nom, '')), '');
  v_prenom   text := coalesce(btrim(coalesce(p_prenom, '')), '');
  v_tel      text := nullif(btrim(coalesce(p_telephone, '')), '');
  v_new_role text;
  v_user     uuid;
  v_entreprise uuid;
  v_existant uuid;
begin
  perform public.dist_exige(array['proprietaire']);

  if v_role not in ('gerant', 'production', 'stock', 'commercial', 'comptable') then
    raise exception 'ROLE_INVALIDE|Rôle inconnu : choisissez gérant, production, stock, commercial ou comptable.';
  end if;

  if v_nom is null then
    raise exception 'NOM_REQUIS|Indiquez le nom du collaborateur.';
  end if;

  if v_email = '' or position('@' in v_email) = 0 then
    raise exception 'EMAIL_INVALIDE|Indiquez une adresse e-mail valide (elle sert d''identifiant de connexion).';
  end if;

  if p_mot_de_passe is null or length(p_mot_de_passe) < 8 then
    raise exception 'MOT_DE_PASSE_TROP_COURT|Le mot de passe doit comporter au moins 8 caractères.';
  end if;

  v_new_role := case v_role
                  when 'production' then 'MAGASINIER'
                  when 'stock'      then 'MAGASINIER'
                  when 'comptable'  then 'COMPTABLE_ENTREPRISE'
                  else 'VENDEUR'
                end;

  select u.entreprise_id into v_entreprise
    from public.utilisateurs u where u.id = v_owner;

  select u.id into v_existant
    from public.utilisateurs u
   where lower(u.email) = v_email
   limit 1;

  if v_existant is not null then
    if exists (
      select 1 from public.utilisateurs u
       where u.id = v_existant
         and u.parent_id is not null
         and u.parent_id <> v_owner
    ) then
      raise exception 'COMPTE_EXISTANT|Cette adresse e-mail appartient déjà à un collaborateur d''une autre entreprise.';
    end if;

    -- Compte déjà rattaché (ou nouvellement créé par la plateforme) :
    -- on réaligne le mot de passe et le profil sans toucher à l'entreprise.
    update auth.users
       set encrypted_password = crypt(p_mot_de_passe, gen_salt('bf')),
           email_confirmed_at = coalesce(email_confirmed_at, now()),
           updated_at = now()
     where id = v_existant;

    v_user := v_existant;
  else
    v_user := public.creer_compte_plateforme(
      v_email, p_mot_de_passe, v_nom, v_prenom, v_new_role);
  end if;

  update public.utilisateurs
     set nom = v_nom,
         prenom = v_prenom,
         email = v_email,
         telephone = coalesce(v_tel, telephone),
         role = 'collaborator',
         new_role = coalesce(public.role_enum(v_new_role), new_role),
         valide = 1,
         parent_id = v_owner,
         entreprise_id = coalesce(v_entreprise, entreprise_id),
         espace_actif_id = v_owner,
         role_distribution = v_role,
         dist_actif = true
   where id = v_user;

  perform public.dist_journaliser(v_owner, 'COLLABORATEUR_CREE', 'utilisateurs', v_user,
    jsonb_build_object('role_distribution', v_role, 'email', v_email,
                       'identifiant', p_identifiant));

  return jsonb_build_object('ok', true, 'id', v_user, 'email', v_email,
                            'role_distribution', v_role);
end;
$$;

create or replace function public.dist_collaborateur_maj(
  p_id            uuid,
  p_nom           text,
  p_prenom        text,
  p_telephone     text,
  p_role          text,
  p_actif         boolean default true,
  p_mot_de_passe  text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, auth
as $$
declare
  v_owner uuid := public.dist_owner_requis();
  v_role  text := lower(btrim(coalesce(p_role, '')));
  v_new_role text;
begin
  perform public.dist_exige(array['proprietaire']);

  if not exists (
    select 1 from public.utilisateurs u
     where u.id = p_id and u.parent_id = v_owner
  ) then
    raise exception 'COLLABORATEUR_INTROUVABLE|Ce collaborateur n''appartient pas à votre entreprise.';
  end if;

  if v_role not in ('gerant', 'production', 'stock', 'commercial', 'comptable') then
    raise exception 'ROLE_INVALIDE|Rôle inconnu.';
  end if;

  v_new_role := case v_role
                  when 'production' then 'MAGASINIER'
                  when 'stock'      then 'MAGASINIER'
                  when 'comptable'  then 'COMPTABLE_ENTREPRISE'
                  else 'VENDEUR'
                end;

  update public.utilisateurs
     set nom = coalesce(nullif(btrim(coalesce(p_nom, '')), ''), nom),
         prenom = coalesce(btrim(coalesce(p_prenom, '')), prenom),
         telephone = coalesce(nullif(btrim(coalesce(p_telephone, '')), ''), telephone),
         role_distribution = v_role,
         dist_actif = coalesce(p_actif, true),
         new_role = coalesce(public.role_enum(v_new_role), new_role)
   where id = p_id;

  if p_mot_de_passe is not null and length(p_mot_de_passe) >= 8 then
    update auth.users
       set encrypted_password = crypt(p_mot_de_passe, gen_salt('bf')),
           updated_at = now()
     where id = p_id;
  end if;

  perform public.dist_journaliser(v_owner, 'COLLABORATEUR_MAJ', 'utilisateurs', p_id,
    jsonb_build_object('role_distribution', v_role, 'actif', p_actif));

  return jsonb_build_object('ok', true);
end;
$$;


-- ============================================================================
--  6. CATALOGUE ET STOCK
-- ============================================================================

create or replace function public.dist_stock_resume()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_owner uuid := public.dist_owner_requis();
  v_intrants jsonb;
  v_produits jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', i.id, 'nom', i.nom, 'unite', i.unite,
           'stock', i.stock, 'seuil', i.seuil_alerte,
           'prix', i.prix_unitaire, 'actif', i.actif,
           'alerte', i.stock <= i.seuil_alerte
         ) order by i.nom), '[]'::jsonb)
    into v_intrants
    from public.dist_intrants i
   where i.owner_id = v_owner;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', p.id, 'nom', p.nom, 'format', p.format, 'unite', p.unite,
           'stock', p.stock, 'prix_vente', p.prix_vente,
           'prix_achat', p.prix_achat, 'actif', p.actif
         ) order by p.nom), '[]'::jsonb)
    into v_produits
    from public.dist_produits p
   where p.owner_id = v_owner;

  return jsonb_build_object('ok', true, 'role', public.dist_role(),
                            'intrants', v_intrants, 'produits', v_produits);
end;
$$;

create or replace function public.dist_intrant_enregistrer(
  p_id     uuid,
  p_nom    text,
  p_unite  text default 'unité',
  p_seuil  numeric default 0,
  p_prix   numeric default 0,
  p_code   text default null,
  p_actif  boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid := public.dist_owner_requis();
  v_id uuid;
begin
  perform public.dist_exige(array['stock', 'gerant', 'proprietaire']);

  if nullif(btrim(coalesce(p_nom, '')), '') is null then
    raise exception 'NOM_REQUIS|Indiquez le nom de l''intrant.';
  end if;

  if p_id is null then
    insert into public.dist_intrants (owner_id, nom, unite, seuil_alerte, prix_unitaire, code, actif)
    values (v_owner, btrim(p_nom), coalesce(nullif(btrim(p_unite), ''), 'unité'),
            coalesce(p_seuil, 0), coalesce(p_prix, 0), nullif(btrim(p_code), ''), coalesce(p_actif, true))
    returning id into v_id;
  else
    update public.dist_intrants
       set nom = btrim(p_nom),
           unite = coalesce(nullif(btrim(p_unite), ''), unite),
           seuil_alerte = coalesce(p_seuil, seuil_alerte),
           prix_unitaire = coalesce(p_prix, prix_unitaire),
           code = coalesce(nullif(btrim(p_code), ''), code),
           actif = coalesce(p_actif, actif),
           updated_at = now()
     where id = p_id and owner_id = v_owner
     returning id into v_id;

    if v_id is null then
      raise exception 'INTRANT_INCONNU|Cet intrant n''existe pas.';
    end if;
  end if;

  perform public.dist_journaliser(v_owner, 'INTRANT_ENREGISTRE', 'dist_intrants', v_id,
    jsonb_build_object('nom', p_nom));
  return jsonb_build_object('ok', true, 'id', v_id);
end;
$$;

create or replace function public.dist_produit_enregistrer(
  p_id          uuid,
  p_nom         text,
  p_format      text default 'farde',
  p_unite       text default 'unité',
  p_prix_vente  numeric default 0,
  p_prix_achat  numeric default 0,
  p_code        text default null,
  p_actif       boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid := public.dist_owner_requis();
  v_id uuid;
begin
  perform public.dist_exige(array['gerant', 'proprietaire']);

  if nullif(btrim(coalesce(p_nom, '')), '') is null then
    raise exception 'NOM_REQUIS|Indiquez le nom du produit fini.';
  end if;

  if p_id is null then
    insert into public.dist_produits (owner_id, nom, format, unite, prix_vente, prix_achat, code, actif)
    values (v_owner, btrim(p_nom), coalesce(nullif(btrim(p_format), ''), 'farde'),
            coalesce(nullif(btrim(p_unite), ''), 'unité'),
            coalesce(p_prix_vente, 0), coalesce(p_prix_achat, 0),
            nullif(btrim(p_code), ''), coalesce(p_actif, true))
    returning id into v_id;
  else
    update public.dist_produits
       set nom = btrim(p_nom),
           format = coalesce(nullif(btrim(p_format), ''), format),
           unite = coalesce(nullif(btrim(p_unite), ''), unite),
           prix_vente = coalesce(p_prix_vente, prix_vente),
           prix_achat = coalesce(p_prix_achat, prix_achat),
           code = coalesce(nullif(btrim(p_code), ''), code),
           actif = coalesce(p_actif, actif),
           updated_at = now()
     where id = p_id and owner_id = v_owner
     returning id into v_id;

    if v_id is null then
      raise exception 'PRODUIT_INCONNU|Ce produit fini n''existe pas.';
    end if;
  end if;

  perform public.dist_journaliser(v_owner, 'PRODUIT_FINI_ENREGISTRE', 'dist_produits', v_id,
    jsonb_build_object('nom', p_nom, 'prix_vente', p_prix_vente));
  return jsonb_build_object('ok', true, 'id', v_id);
end;
$$;

create or replace function public.dist_stock_ajuster(
  p_intrant_id       uuid,
  p_produit_id       uuid,
  p_nouvelle_quantite numeric,
  p_motif            text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid := public.dist_owner_requis();
  v_avant numeric(16,3);
  v_delta numeric(16,3);
begin
  perform public.dist_exige(array['stock', 'gerant', 'proprietaire']);

  if nullif(btrim(coalesce(p_motif, '')), '') is null or length(btrim(p_motif)) < 3 then
    raise exception 'MOTIF_REQUIS|Expliquez la correction (3 caractères minimum).';
  end if;

  if (p_intrant_id is null) = (p_produit_id is null) then
    raise exception 'CIBLE_INVALIDE|Indiquez soit un intrant, soit un produit fini.';
  end if;

  if p_intrant_id is not null then
    select stock into v_avant from public.dist_intrants
     where id = p_intrant_id and owner_id = v_owner for update;
    if v_avant is null then
      raise exception 'INTRANT_INCONNU|Intrant introuvable.';
    end if;
    v_delta := coalesce(p_nouvelle_quantite, 0) - v_avant;
    perform public.dist_bouger_intrant(v_owner, p_intrant_id, v_delta,
      'regularisation_intrant', 'ajustement', null, p_motif);
  else
    select stock into v_avant from public.dist_produits
     where id = p_produit_id and owner_id = v_owner for update;
    if v_avant is null then
      raise exception 'PRODUIT_INCONNU|Produit fini introuvable.';
    end if;
    v_delta := coalesce(p_nouvelle_quantite, 0) - v_avant;
    perform public.dist_bouger_produit(v_owner, p_produit_id, v_delta,
      'regularisation_produit', 'ajustement', null, p_motif);
  end if;

  perform public.dist_journaliser(v_owner, 'STOCK_AJUSTE', 'dist_mouvements', null,
    jsonb_build_object('intrant_id', p_intrant_id, 'produit_id', p_produit_id,
                       'delta', v_delta, 'motif', p_motif));

  return jsonb_build_object('ok', true, 'delta', v_delta);
end;
$$;


-- ============================================================================
--  7. RÉCEPTION DES INTRANTS (double confirmation)
-- ============================================================================

create or replace function public.dist_reception_intrants_enregistrer(
  p_lignes     jsonb,
  p_fournisseur text default null,
  p_note        text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid := public.dist_owner_requis();
  v_id uuid;
  v_num text;
  v_l record;
begin
  perform public.dist_exige(array['stock', 'gerant', 'proprietaire']);

  if p_lignes is null or jsonb_typeof(p_lignes) <> 'array'
     or jsonb_array_length(p_lignes) = 0 then
    raise exception 'LIGNES_VIDES|Ajoutez au moins un intrant reçu.';
  end if;

  v_num := public.dist_numero(v_owner, 'REC');

  insert into public.dist_receptions (owner_id, numero, fournisseur, note, statut, cree_par)
  values (v_owner, v_num, nullif(btrim(coalesce(p_fournisseur, '')), ''),
          nullif(btrim(coalesce(p_note, '')), ''), 'attente_gerant', auth.uid())
  returning id into v_id;

  for v_l in
    select * from jsonb_to_recordset(p_lignes)
      as x(intrant_id uuid, quantite numeric, quantite_annoncee numeric)
  loop
    if v_l.intrant_id is null or v_l.quantite is null or v_l.quantite < 0 then
      raise exception 'QUANTITE_INVALIDE|Quantité reçue invalide.';
    end if;

    if not exists (
      select 1 from public.dist_intrants i
       where i.id = v_l.intrant_id and i.owner_id = v_owner
    ) then
      raise exception 'INTRANT_INCONNU|Un des intrants n''existe pas.';
    end if;

    insert into public.dist_reception_lignes (
      reception_id, intrant_id, quantite_annoncee, quantite_comptee
    ) values (
      v_id, v_l.intrant_id,
      coalesce(v_l.quantite_annoncee, v_l.quantite), v_l.quantite
    );
  end loop;

  perform public.dist_journaliser(v_owner, 'RECEPTION_INTRANTS_ENREGISTREE',
    'dist_receptions', v_id, jsonb_build_object('numero', v_num));

  return jsonb_build_object('ok', true, 'id', v_id, 'numero', v_num,
                            'statut', 'attente_gerant');
end;
$$;

create or replace function public.dist_reception_intrants_confirmer(
  p_reception uuid,
  p_lignes    jsonb default null,
  p_motif     text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid := public.dist_owner_requis();
  v_rec record;
  v_l record;
  v_ecart boolean := false;
  v_nb integer := 0;
begin
  perform public.dist_exige(array['gerant', 'proprietaire']);

  select * into v_rec
    from public.dist_receptions
   where id = p_reception and owner_id = v_owner
   for update;

  if v_rec.id is null then
    raise exception 'RECEPTION_INTROUVABLE|Cette réception n''existe pas.';
  end if;
  if v_rec.statut <> 'attente_gerant' then
    raise exception 'STATUT_INVALIDE|Cette réception a déjà été traitée.';
  end if;

  if p_lignes is not null and jsonb_typeof(p_lignes) = 'array' then
    for v_l in
      select * from jsonb_to_recordset(p_lignes)
        as x(intrant_id uuid, quantite_comptee numeric)
    loop
      update public.dist_reception_lignes
         set quantite_comptee = coalesce(v_l.quantite_comptee, quantite_comptee)
       where reception_id = p_reception and intrant_id = v_l.intrant_id;
    end loop;
  end if;

  for v_l in
    select rl.intrant_id, rl.quantite_annoncee, rl.quantite_comptee
      from public.dist_reception_lignes rl
     where rl.reception_id = p_reception
  loop
    if abs(v_l.quantite_comptee - v_l.quantite_annoncee) > 0.0001 then
      v_ecart := true;
    end if;

    if v_l.quantite_comptee > 0 then
      perform public.dist_bouger_intrant(v_owner, v_l.intrant_id,
        v_l.quantite_comptee, 'intrant_entree', 'reception', p_reception,
        'Réception ' || v_rec.numero);
      v_nb := v_nb + 1;
    end if;
  end loop;

  if v_nb = 0 then
    raise exception 'LIGNES_VIDES|Aucune quantité à valider.';
  end if;

  if v_ecart and nullif(btrim(coalesce(p_motif, '')), '') is null then
    raise exception 'ECART_SANS_MOTIF|Les quantités comptées diffèrent des quantités annoncées : indiquez un motif.';
  end if;

  if v_ecart then
    perform public.dist_anomalie(v_owner, 'ECART_RECEPTION', 'dist_receptions', p_reception,
      'Écart constaté à la réception ' || v_rec.numero ||
      ' — motif : ' || btrim(coalesce(p_motif, 'non précisé')));
  end if;

  update public.dist_receptions
     set statut = 'validee',
         confirme_par = auth.uid(),
         confirme_le = now(),
         motif = nullif(btrim(coalesce(p_motif, '')), '')
   where id = p_reception;

  perform public.dist_journaliser(v_owner, 'RECEPTION_INTRANTS_CONFIRMEE',
    'dist_receptions', p_reception,
    jsonb_build_object('numero', v_rec.numero, 'ecart', v_ecart));

  return jsonb_build_object('ok', true, 'ecart', v_ecart, 'lignes', v_nb);
end;
$$;

create or replace function public.dist_receptions_lister(p_statut text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_owner uuid := public.dist_owner_requis();
  v_items jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', r.id, 'numero', r.numero, 'fournisseur', r.fournisseur,
           'statut', r.statut, 'cree_le', r.cree_le, 'note', r.note,
           'lignes', (
             select coalesce(jsonb_agg(jsonb_build_object(
               'intrant_id', rl.intrant_id,
               'nom', i.nom, 'unite', i.unite,
               'quantite_annoncee', rl.quantite_annoncee,
               'quantite_comptee', rl.quantite_comptee
             ) order by i.nom), '[]'::jsonb)
               from public.dist_reception_lignes rl
               join public.dist_intrants i on i.id = rl.intrant_id
              where rl.reception_id = r.id)
         ) order by r.cree_le desc), '[]'::jsonb)
    into v_items
    from public.dist_receptions r
   where r.owner_id = v_owner
     and (p_statut is null or r.statut = p_statut);

  return jsonb_build_object('ok', true, 'items', v_items);
end;
$$;


-- ============================================================================
--  8. DEMANDES D'INTRANTS (production → stock → production)
-- ============================================================================

create or replace function public.dist_demande_intrants_creer(
  p_lignes jsonb,
  p_note   text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid := public.dist_owner_requis();
  v_id uuid;
  v_num text;
  v_l record;
begin
  perform public.dist_exige(array['production', 'gerant', 'proprietaire']);

  if p_lignes is null or jsonb_typeof(p_lignes) <> 'array'
     or jsonb_array_length(p_lignes) = 0 then
    raise exception 'LIGNES_VIDES|Ajoutez au moins un intrant à demander.';
  end if;

  v_num := public.dist_numero(v_owner, 'DIN');

  insert into public.dist_demandes_intrants (owner_id, numero, demandeur_id, statut, note)
  values (v_owner, v_num, auth.uid(), 'attente_stock',
          nullif(btrim(coalesce(p_note, '')), ''))
  returning id into v_id;

  for v_l in
    select * from jsonb_to_recordset(p_lignes)
      as x(intrant_id uuid, quantite numeric)
  loop
    if v_l.intrant_id is null or v_l.quantite is null or v_l.quantite <= 0 then
      raise exception 'QUANTITE_INVALIDE|Quantité demandée invalide.';
    end if;

    if not exists (
      select 1 from public.dist_intrants i
       where i.id = v_l.intrant_id and i.owner_id = v_owner
    ) then
      raise exception 'INTRANT_INCONNU|Un des intrants n''existe pas.';
    end if;

    insert into public.dist_demande_intrants_lignes (
      demande_id, intrant_id, quantite_demandee
    ) values (v_id, v_l.intrant_id, v_l.quantite);
  end loop;

  perform public.dist_journaliser(v_owner, 'DEMANDE_INTRANTS_CREEE',
    'dist_demandes_intrants', v_id, jsonb_build_object('numero', v_num));

  return jsonb_build_object('ok', true, 'id', v_id, 'numero', v_num);
end;
$$;

create or replace function public.dist_demande_intrants_traiter(
  p_demande  uuid,
  p_lignes   jsonb default null,
  p_refuser  boolean default false,
  p_motif    text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid := public.dist_owner_requis();
  v_dem record;
  v_l record;
begin
  perform public.dist_exige(array['stock', 'gerant', 'proprietaire']);

  select * into v_dem
    from public.dist_demandes_intrants
   where id = p_demande and owner_id = v_owner
   for update;

  if v_dem.id is null then
    raise exception 'DEMANDE_INTROUVABLE|Cette demande n''existe pas.';
  end if;
  if v_dem.statut <> 'attente_stock' then
    raise exception 'STATUT_INVALIDE|Cette demande a déjà été traitée.';
  end if;

  if coalesce(p_refuser, false) then
    if nullif(btrim(coalesce(p_motif, '')), '') is null then
      raise exception 'MOTIF_REQUIS|Indiquez pourquoi la demande est refusée.';
    end if;
    update public.dist_demandes_intrants
       set statut = 'refusee', motif = btrim(p_motif),
           traite_par = auth.uid(), traite_le = now()
     where id = p_demande;
    perform public.dist_journaliser(v_owner, 'DEMANDE_INTRANTS_REFUSEE',
      'dist_demandes_intrants', p_demande, jsonb_build_object('motif', p_motif));
    return jsonb_build_object('ok', true, 'statut', 'refusee');
  end if;

  if p_lignes is not null and jsonb_typeof(p_lignes) = 'array' then
    for v_l in
      select * from jsonb_to_recordset(p_lignes)
        as x(intrant_id uuid, quantite_autorisee numeric)
    loop
      update public.dist_demande_intrants_lignes
         set quantite_autorisee = greatest(coalesce(v_l.quantite_autorisee, quantite_demandee), 0)
       where demande_id = p_demande and intrant_id = v_l.intrant_id;
    end loop;
  end if;

  for v_l in
    select l.intrant_id,
           case when l.quantite_autorisee > 0 then l.quantite_autorisee
                else l.quantite_demandee end as autorisee
      from public.dist_demande_intrants_lignes l
     where l.demande_id = p_demande
  loop
    perform public.dist_bouger_intrant(v_owner, v_l.intrant_id,
      -v_l.autorisee, 'intrant_sortie_production',
      'demande_intrants', p_demande,
      'Sortie vers production ' || v_dem.numero);

    update public.dist_demande_intrants_lignes
       set quantite_autorisee = v_l.autorisee,
           quantite_sortie = v_l.autorisee
     where demande_id = p_demande and intrant_id = v_l.intrant_id;
  end loop;

  update public.dist_demandes_intrants
     set statut = 'attente_reception', traite_par = auth.uid(), traite_le = now(),
         motif = nullif(btrim(coalesce(p_motif, '')), '')
   where id = p_demande;

  perform public.dist_journaliser(v_owner, 'DEMANDE_INTRANTS_AUTORISEE',
    'dist_demandes_intrants', p_demande, jsonb_build_object('numero', v_dem.numero));

  return jsonb_build_object('ok', true, 'statut', 'attente_reception');
end;
$$;

create or replace function public.dist_demande_intrants_receptionner(
  p_demande uuid,
  p_lignes  jsonb default null,
  p_motif   text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid := public.dist_owner_requis();
  v_dem record;
  v_l record;
  v_litige boolean := false;
begin
  perform public.dist_exige(array['production', 'gerant', 'proprietaire']);

  select * into v_dem
    from public.dist_demandes_intrants
   where id = p_demande and owner_id = v_owner
   for update;

  if v_dem.id is null then
    raise exception 'DEMANDE_INTROUVABLE|Cette demande n''existe pas.';
  end if;
  if v_dem.statut <> 'attente_reception' then
    raise exception 'STATUT_INVALIDE|Cette demande n''attend pas de réception.';
  end if;
  if v_dem.demandeur_id <> auth.uid()
     and public.dist_role() not in ('gerant', 'proprietaire') then
    raise exception 'DROIT_REFUSE|Seul le demandeur confirme sa réception.';
  end if;

  if p_lignes is not null and jsonb_typeof(p_lignes) = 'array' then
    for v_l in
      select * from jsonb_to_recordset(p_lignes)
        as x(intrant_id uuid, quantite_recue numeric)
    loop
      update public.dist_demande_intrants_lignes
         set quantite_recue = coalesce(v_l.quantite_recue, quantite_sortie)
       where demande_id = p_demande and intrant_id = v_l.intrant_id;
    end loop;
  end if;

  for v_l in
    select l.intrant_id, l.quantite_sortie,
           coalesce(l.quantite_recue, l.quantite_sortie) as recue
      from public.dist_demande_intrants_lignes l
     where l.demande_id = p_demande
  loop
    if v_l.recue < 0 or v_l.recue > v_l.quantite_sortie then
      raise exception 'QUANTITE_INVALIDE|La quantité reçue dépasse la quantité sortie.';
    end if;

    update public.dist_demande_intrants_lignes
       set quantite_recue = v_l.recue
     where demande_id = p_demande and intrant_id = v_l.intrant_id;

    if v_l.recue < v_l.quantite_sortie - 0.0001 then
      v_litige := true;
      perform public.dist_anomalie(v_owner, 'ECART_INTRANTS_PRODUCTION',
        'dist_demandes_intrants', p_demande,
        'Le producteur déclare ' || trim(to_char(v_l.recue, 'FM999999990.###')) ||
        ' reçu(s) sur ' || trim(to_char(v_l.quantite_sortie, 'FM999999990.###')) ||
        ' sorti(s).',
        v_l.quantite_sortie - v_l.recue);
    end if;
  end loop;

  if v_litige and nullif(btrim(coalesce(p_motif, '')), '') is null then
    raise exception 'MOTIF_REQUIS|Un écart a été constaté : expliquez-le.';
  end if;

  update public.dist_demandes_intrants
     set statut = case when v_litige then 'en_litige' else 'recue' end,
         motif = nullif(btrim(coalesce(p_motif, '')), ''),
         recu_par = auth.uid(), recu_le = now()
   where id = p_demande;

  perform public.dist_journaliser(v_owner, 'DEMANDE_INTRANTS_RECUE',
    'dist_demandes_intrants', p_demande,
    jsonb_build_object('numero', v_dem.numero, 'litige', v_litige));

  return jsonb_build_object('ok', true,
                            'statut', case when v_litige then 'en_litige' else 'recue' end);
end;
$$;

create or replace function public.dist_demandes_intrants_lister()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_owner uuid := public.dist_owner_requis();
  v_items jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', d.id, 'numero', d.numero, 'statut', d.statut,
           'note', d.note, 'motif', d.motif, 'cree_le', d.cree_le,
           'demandeur', coalesce(u.nom, 'Production'),
           'lignes', (
             select coalesce(jsonb_agg(jsonb_build_object(
               'intrant_id', l.intrant_id, 'nom', i.nom, 'unite', i.unite,
               'quantite_demandee', l.quantite_demandee,
               'quantite_autorisee', l.quantite_autorisee,
               'quantite_sortie', l.quantite_sortie,
               'quantite_recue', l.quantite_recue
             ) order by i.nom), '[]'::jsonb)
               from public.dist_demande_intrants_lignes l
               join public.dist_intrants i on i.id = l.intrant_id
              where l.demande_id = d.id)
         ) order by d.cree_le desc), '[]'::jsonb)
    into v_items
    from public.dist_demandes_intrants d
    left join public.utilisateurs u on u.id = d.demandeur_id
   where d.owner_id = v_owner;

  return jsonb_build_object('ok', true, 'items', v_items);
end;
$$;


-- ============================================================================
--  9. PRODUCTIONS
-- ============================================================================

create or replace function public.dist_production_enregistrer(
  p_demande_id    uuid,
  p_intrants      jsonb,
  p_sorties       jsonb,
  p_motif_pertes  text default null,
  p_note          text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid := public.dist_owner_requis();
  v_id uuid;
  v_num text;
  v_l record;
  v_s record;
  v_dem public.dist_demandes_intrants%rowtype;
  v_perte boolean := false;
  v_recue numeric;
begin
  perform public.dist_exige(array['production', 'gerant', 'proprietaire']);

  if p_sorties is null or jsonb_typeof(p_sorties) <> 'array'
     or jsonb_array_length(p_sorties) = 0 then
    raise exception 'SORTIES_VIDES|Déclarez au moins un produit fabriqué.';
  end if;

  if p_intrants is null or jsonb_typeof(p_intrants) <> 'array'
     or jsonb_array_length(p_intrants) = 0 then
    raise exception 'INTRANTS_VIDES|Déclarez les intrants utilisés.';
  end if;

  if p_demande_id is not null then
    select * into v_dem
      from public.dist_demandes_intrants
     where id = p_demande_id and owner_id = v_owner
     for update;

    if v_dem.id is null then
      raise exception 'DEMANDE_INTROUVABLE|La demande d''intrants n''existe pas.';
    end if;
    if v_dem.statut not in ('recue', 'en_litige') then
      raise exception 'STATUT_INVALIDE|Les intrants doivent d''abord être reçus.';
    end if;
  end if;

  v_num := public.dist_numero(v_owner, 'PRD');

  insert into public.dist_productions (
    owner_id, numero, responsable_id, demande_id, statut, note
  ) values (
    v_owner, v_num, auth.uid(), p_demande_id, 'attente_stock',
    nullif(btrim(coalesce(p_note, '')), '')
  ) returning id into v_id;

  for v_l in
    select * from jsonb_to_recordset(p_intrants)
      as x(intrant_id uuid, quantite_recue numeric,
           quantite_consommee numeric, quantite_perdue numeric)
  loop
    if v_l.intrant_id is null then
      raise exception 'INTRANT_INCONNU|Intrant manquant.';
    end if;

    if p_demande_id is not null then
      select coalesce(l.quantite_recue, l.quantite_sortie) into v_recue
        from public.dist_demande_intrants_lignes l
       where l.demande_id = p_demande_id and l.intrant_id = v_l.intrant_id;

      if v_recue is null then
        raise exception 'INTRANT_NON_RECU|Cet intrant ne figure pas dans la demande reçue.';
      end if;
    else
      v_recue := coalesce(v_l.quantite_recue, 0);
      if v_recue <= 0 then
        raise exception 'QUANTITE_INVALIDE|Quantité reçue invalide.';
      end if;
      perform public.dist_bouger_intrant(v_owner, v_l.intrant_id, -v_recue,
        'intrant_sortie_production', 'production', v_id,
        'Production ' || v_num);
    end if;

    if coalesce(v_l.quantite_consommee, 0) < 0
       or coalesce(v_l.quantite_perdue, 0) < 0
       or coalesce(v_l.quantite_consommee, 0) + coalesce(v_l.quantite_perdue, 0)
          > v_recue + 0.0001 then
      raise exception 'QUANTITE_INVALIDE|Consommé + perdu dépasse la quantité reçue.';
    end if;

    if coalesce(v_l.quantite_perdue, 0) > 0 then
      v_perte := true;
    end if;

    insert into public.dist_production_intrants (
      production_id, intrant_id, quantite_recue, quantite_consommee,
      quantite_perdue, quantite_restante
    ) values (
      v_id, v_l.intrant_id, v_recue,
      coalesce(v_l.quantite_consommee, 0), coalesce(v_l.quantite_perdue, 0),
      greatest(v_recue - coalesce(v_l.quantite_consommee, 0)
                        - coalesce(v_l.quantite_perdue, 0), 0)
    );
  end loop;

  if v_perte and nullif(btrim(coalesce(p_motif_pertes, '')), '') is null then
    raise exception 'PERTE_SANS_MOTIF|Expliquez la perte constatée en production.';
  end if;

  update public.dist_productions
     set motif_pertes = nullif(btrim(coalesce(p_motif_pertes, '')), '')
   where id = v_id;

  for v_s in
    select * from jsonb_to_recordset(p_sorties)
      as x(produit_id uuid, quantite numeric)
  loop
    if v_s.produit_id is null or v_s.quantite is null or v_s.quantite <= 0 then
      raise exception 'QUANTITE_INVALIDE|Quantité produite invalide.';
    end if;

    if not exists (
      select 1 from public.dist_produits p
       where p.id = v_s.produit_id and p.owner_id = v_owner
    ) then
      raise exception 'PRODUIT_INCONNU|Un des produits finis n''existe pas.';
    end if;

    insert into public.dist_production_sorties (
      production_id, produit_id, quantite_produite, quantite_remise
    ) values (v_id, v_s.produit_id, v_s.quantite, v_s.quantite);
  end loop;

  perform public.dist_journaliser(v_owner, 'PRODUCTION_DECLAREE',
    'dist_productions', v_id,
    jsonb_build_object('numero', v_num, 'demande_id', p_demande_id,
                       'pertes', v_perte));

  return jsonb_build_object('ok', true, 'id', v_id, 'numero', v_num,
                            'statut', 'attente_stock');
end;
$$;

create or replace function public.dist_production_receptionner(
  p_production uuid,
  p_lignes     jsonb default null,
  p_motif      text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid := public.dist_owner_requis();
  v_prod record;
  v_s record;
  v_recue numeric;
  v_litige boolean := false;
begin
  perform public.dist_exige(array['stock', 'gerant', 'proprietaire']);

  select * into v_prod
    from public.dist_productions
   where id = p_production and owner_id = v_owner
   for update;

  if v_prod.id is null then
    raise exception 'PRODUCTION_INTROUVABLE|Cette production n''existe pas.';
  end if;
  if v_prod.statut <> 'attente_stock' then
    raise exception 'STATUT_INVALIDE|Cette production a déjà été réceptionnée.';
  end if;

  if p_lignes is not null and jsonb_typeof(p_lignes) = 'array' then
    for v_s in
      select * from jsonb_to_recordset(p_lignes)
        as x(produit_id uuid, quantite_recue numeric)
    loop
      update public.dist_production_sorties
         set quantite_recue = coalesce(v_s.quantite_recue, quantite_remise)
       where production_id = p_production and produit_id = v_s.produit_id;
    end loop;
  end if;

  for v_s in
    select s.produit_id, s.quantite_remise,
           coalesce(s.quantite_recue, s.quantite_remise) as recue
      from public.dist_production_sorties s
     where s.production_id = p_production
  loop
    v_recue := v_s.recue;

    if v_recue < 0 or v_recue > v_s.quantite_remise + 0.0001 then
      raise exception 'QUANTITE_INVALIDE|La quantité reçue dépasse la quantité remise.';
    end if;

    update public.dist_production_sorties
       set quantite_recue = v_recue,
           constat = case when v_recue < v_s.quantite_remise - 0.0001
                          then btrim(coalesce(p_motif, 'non précisé'))
                          else null end
     where production_id = p_production and produit_id = v_s.produit_id;

    if v_recue > 0 then
      perform public.dist_bouger_produit(v_owner, v_s.produit_id, v_recue,
        'production_entree', 'production', p_production,
        'Production ' || v_prod.numero);
    end if;

    if v_recue < v_s.quantite_remise - 0.0001 then
      v_litige := true;
      perform public.dist_anomalie(v_owner, 'ECART_PRODUCTION_STOCK',
        'dist_productions', p_production,
        'La production déclare ' ||
        trim(to_char(v_s.quantite_remise, 'FM999999990.###')) ||
        ' remis, le stock n''en reçoit que ' ||
        trim(to_char(v_recue, 'FM999999990.###')) || '.',
        v_s.quantite_remise - v_recue);
    end if;
  end loop;

  if v_litige and nullif(btrim(coalesce(p_motif, '')), '') is null then
    raise exception 'MOTIF_REQUIS|Un écart a été constaté : expliquez-le.';
  end if;

  update public.dist_productions
     set statut = case when v_litige then 'en_litige' else 'cloturee' end,
         recepteur_id = auth.uid(), recepte_le = now()
   where id = p_production;

  perform public.dist_journaliser(v_owner, 'PRODUCTION_RECEPTIONNEE',
    'dist_productions', p_production,
    jsonb_build_object('numero', v_prod.numero, 'litige', v_litige));

  return jsonb_build_object('ok', true,
                            'statut', case when v_litige then 'en_litige' else 'cloturee' end);
end;
$$;

create or replace function public.dist_production_reintegrer(
  p_production uuid,
  p_intrant    uuid,
  p_quantite   numeric,
  p_motif      text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid := public.dist_owner_requis();
  v_reste numeric(16,3);
begin
  perform public.dist_exige(array['production', 'gerant', 'proprietaire']);

  if p_quantite is null or p_quantite <= 0 then
    raise exception 'QUANTITE_INVALIDE|Quantité invalide.';
  end if;

  select quantite_restante into v_reste
    from public.dist_production_intrants
   where production_id = p_production and intrant_id = p_intrant
   for update;

  if v_reste is null or v_reste < p_quantite - 0.0001 then
    raise exception 'QUANTITE_INVALIDE|Il ne reste pas autant d''intrants non utilisés.';
  end if;

  update public.dist_production_intrants
     set quantite_restante = quantite_restante - p_quantite
   where production_id = p_production and intrant_id = p_intrant;

  perform public.dist_bouger_intrant(v_owner, p_intrant, p_quantite,
    'intrant_retour_production', 'production', p_production,
    coalesce(nullif(btrim(p_motif), ''), 'Retour d''intrants non utilisés'));

  return jsonb_build_object('ok', true);
end;
$$;

create or replace function public.dist_productions_lister()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_owner uuid := public.dist_owner_requis();
  v_items jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', p.id, 'numero', p.numero, 'statut', p.statut,
           'note', p.note, 'motif_pertes', p.motif_pertes,
           'cree_le', p.cree_le, 'demande_id', p.demande_id,
           'responsable', coalesce(u.nom, 'Production'),
           'intrants', (
             select coalesce(jsonb_agg(jsonb_build_object(
               'intrant_id', pi.intrant_id, 'nom', i.nom, 'unite', i.unite,
               'quantite_recue', pi.quantite_recue,
               'quantite_consommee', pi.quantite_consommee,
               'quantite_perdue', pi.quantite_perdue,
               'quantite_restante', pi.quantite_restante
             ) order by i.nom), '[]'::jsonb)
               from public.dist_production_intrants pi
               join public.dist_intrants i on i.id = pi.intrant_id
              where pi.production_id = p.id),
           'sorties', (
             select coalesce(jsonb_agg(jsonb_build_object(
               'produit_id', ps.produit_id, 'nom', pr.nom, 'unite', pr.unite,
               'quantite_produite', ps.quantite_produite,
               'quantite_remise', ps.quantite_remise,
               'quantite_recue', ps.quantite_recue,
               'constat', ps.constat
             ) order by pr.nom), '[]'::jsonb)
               from public.dist_production_sorties ps
               join public.dist_produits pr on pr.id = ps.produit_id
              where ps.production_id = p.id)
         ) order by p.cree_le desc), '[]'::jsonb)
    into v_items
    from public.dist_productions p
    left join public.utilisateurs u on u.id = p.responsable_id
   where p.owner_id = v_owner;

  return jsonb_build_object('ok', true, 'items', v_items);
end;
$$;


-- ============================================================================
--  10. DEMANDES DE PRODUITS DES COMMERCIAUX
-- ============================================================================

create or replace function public.dist_demande_commercial_creer(
  p_lignes        jsonb,
  p_note          text default null,
  p_commercial_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid := public.dist_owner_requis();
  v_commercial uuid;
  v_id uuid;
  v_num text;
  v_l record;
begin
  if public.dist_role() = 'commercial' then
    v_commercial := auth.uid();
  else
    perform public.dist_exige(array['proprietaire', 'gerant']);
    v_commercial := coalesce(p_commercial_id, auth.uid());
    if not exists (select 1 from public.utilisateurs u
                    where u.id = v_commercial and u.parent_id = v_owner
                      and u.role_distribution = 'commercial') then
      raise exception 'COMMERCIAL_INVALIDE|Choisissez un commercial de votre entreprise.';
    end if;
  end if;

  if p_lignes is null or jsonb_typeof(p_lignes) <> 'array'
     or jsonb_array_length(p_lignes) = 0 then
    raise exception 'LIGNES_VIDES|Ajoutez au moins un produit à demander.';
  end if;

  v_num := public.dist_numero(v_owner, 'DCO');

  insert into public.dist_demandes_commercial (
    owner_id, numero, commercial_id, statut, note
  ) values (
    v_owner, v_num, v_commercial, 'attente_production',
    nullif(btrim(coalesce(p_note, '')), '')
  ) returning id into v_id;

  for v_l in
    select * from jsonb_to_recordset(p_lignes)
      as x(produit_id uuid, quantite numeric)
  loop
    if v_l.produit_id is null or v_l.quantite is null or v_l.quantite <= 0 then
      raise exception 'QUANTITE_INVALIDE|Quantité demandée invalide.';
    end if;

    if not exists (
      select 1 from public.dist_produits p
       where p.id = v_l.produit_id and p.owner_id = v_owner
    ) then
      raise exception 'PRODUIT_INCONNU|Un des produits n''existe pas.';
    end if;

    insert into public.dist_demande_commercial_lignes (
      demande_id, produit_id, quantite_demandee
    ) values (v_id, v_l.produit_id, v_l.quantite);
  end loop;

  perform public.dist_journaliser(v_owner, 'DEMANDE_COMMERCIALE_CREEE',
    'dist_demandes_commercial', v_id,
    jsonb_build_object('numero', v_num, 'commercial_id', v_commercial));

  return jsonb_build_object('ok', true, 'id', v_id, 'numero', v_num);
end;
$$;

create or replace function public.dist_demande_commercial_confirmer(
  p_demande uuid,
  p_lignes  jsonb default null,
  p_refuser boolean default false,
  p_motif   text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid := public.dist_owner_requis();
  v_dem record;
  v_l record;
begin
  perform public.dist_exige(array['production', 'gerant', 'proprietaire']);

  select * into v_dem from public.dist_demandes_commercial
   where id = p_demande and owner_id = v_owner for update;

  if v_dem.id is null then
    raise exception 'DEMANDE_INTROUVABLE|Cette demande n''existe pas.';
  end if;
  if v_dem.statut <> 'attente_production' then
    raise exception 'STATUT_INVALIDE|Cette demande n''attend pas la production.';
  end if;

  if coalesce(p_refuser, false) then
    if nullif(btrim(coalesce(p_motif, '')), '') is null then
      raise exception 'MOTIF_REQUIS|Indiquez pourquoi la production refuse.';
    end if;
    update public.dist_demandes_commercial
       set statut = 'refusee_production', motif = btrim(p_motif),
           production_par = auth.uid(), production_le = now()
     where id = p_demande;
    perform public.dist_journaliser(v_owner, 'DEMANDE_COMMERCIALE_REFUSEE_PRODUCTION',
      'dist_demandes_commercial', p_demande, jsonb_build_object('motif', p_motif));
    return jsonb_build_object('ok', true, 'statut', 'refusee_production');
  end if;

  if p_lignes is not null and jsonb_typeof(p_lignes) = 'array' then
    for v_l in
      select * from jsonb_to_recordset(p_lignes)
        as x(produit_id uuid, quantite_confirmee numeric)
    loop
      update public.dist_demande_commercial_lignes
         set quantite_confirmee = greatest(coalesce(v_l.quantite_confirmee, quantite_demandee), 0)
       where demande_id = p_demande and produit_id = v_l.produit_id;
    end loop;
  end if;

  update public.dist_demande_commercial_lignes
     set quantite_confirmee = quantite_demandee
   where demande_id = p_demande and quantite_confirmee = 0;

  update public.dist_demandes_commercial
     set statut = 'attente_stock', production_par = auth.uid(),
         production_le = now(), motif = nullif(btrim(coalesce(p_motif, '')), '')
   where id = p_demande;

  perform public.dist_journaliser(v_owner, 'DEMANDE_COMMERCIALE_CONFIRMEE_PRODUCTION',
    'dist_demandes_commercial', p_demande, jsonb_build_object('numero', v_dem.numero));

  return jsonb_build_object('ok', true, 'statut', 'attente_stock');
end;
$$;

create or replace function public.dist_demande_commercial_autoriser(
  p_demande uuid,
  p_lignes  jsonb default null,
  p_refuser boolean default false,
  p_motif   text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid := public.dist_owner_requis();
  v_dem record;
  v_l record;
begin
  perform public.dist_exige(array['stock', 'gerant', 'proprietaire']);

  select * into v_dem from public.dist_demandes_commercial
   where id = p_demande and owner_id = v_owner for update;

  if v_dem.id is null then
    raise exception 'DEMANDE_INTROUVABLE|Cette demande n''existe pas.';
  end if;
  if v_dem.statut <> 'attente_stock' then
    raise exception 'STATUT_INVALIDE|Cette demande n''attend pas le stock.';
  end if;

  if coalesce(p_refuser, false) then
    if nullif(btrim(coalesce(p_motif, '')), '') is null then
      raise exception 'MOTIF_REQUIS|Indiquez pourquoi le stock refuse.';
    end if;
    update public.dist_demandes_commercial
       set statut = 'refusee_stock', motif = btrim(p_motif),
           stock_par = auth.uid(), stock_le = now()
     where id = p_demande;
    perform public.dist_journaliser(v_owner, 'DEMANDE_COMMERCIALE_REFUSEE_STOCK',
      'dist_demandes_commercial', p_demande, jsonb_build_object('motif', p_motif));
    return jsonb_build_object('ok', true, 'statut', 'refusee_stock');
  end if;

  if p_lignes is not null and jsonb_typeof(p_lignes) = 'array' then
    for v_l in
      select * from jsonb_to_recordset(p_lignes)
        as x(produit_id uuid, quantite_sortie numeric)
    loop
      update public.dist_demande_commercial_lignes
         set quantite_sortie = greatest(coalesce(v_l.quantite_sortie,
             nullif(quantite_confirmee, 0), quantite_demandee), 0)
       where demande_id = p_demande and produit_id = v_l.produit_id;
    end loop;
  end if;

  for v_l in
    select l.produit_id,
           greatest(coalesce(nullif(l.quantite_sortie, 0),
                             nullif(l.quantite_confirmee, 0),
                             l.quantite_demandee), 0) as sortie
      from public.dist_demande_commercial_lignes l
     where l.demande_id = p_demande
  loop
    perform public.dist_bouger_produit(v_owner, v_l.produit_id, -v_l.sortie,
      'transfert_commercial', 'demande_commercial', p_demande,
      'Attribution au commercial ' || v_dem.numero);

    perform public.dist_bouger_commercial(v_owner, v_dem.commercial_id,
      v_l.produit_id, v_l.sortie, 'transfert_commercial',
      'demande_commercial', p_demande,
      'Dotation ' || v_dem.numero);

    update public.dist_demande_commercial_lignes
       set quantite_sortie = v_l.sortie
     where demande_id = p_demande and produit_id = v_l.produit_id;
  end loop;

  update public.dist_demandes_commercial
     set statut = 'attente_commercial', stock_par = auth.uid(),
         stock_le = now(), motif = nullif(btrim(coalesce(p_motif, '')), '')
   where id = p_demande;

  perform public.dist_journaliser(v_owner, 'DEMANDE_COMMERCIALE_AUTORISEE',
    'dist_demandes_commercial', p_demande, jsonb_build_object('numero', v_dem.numero));

  return jsonb_build_object('ok', true, 'statut', 'attente_commercial');
end;
$$;

create or replace function public.dist_demande_commercial_receptionner(
  p_demande uuid,
  p_lignes  jsonb default null,
  p_motif   text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid := public.dist_owner_requis();
  v_dem record;
  v_l record;
  v_litige boolean := false;
begin
  if public.dist_role() = 'commercial' then
    null;
  else
    perform public.dist_exige(array['gerant', 'proprietaire']);
  end if;

  select * into v_dem from public.dist_demandes_commercial
   where id = p_demande and owner_id = v_owner for update;

  if v_dem.id is null then
    raise exception 'DEMANDE_INTROUVABLE|Cette demande n''existe pas.';
  end if;
  if v_dem.statut <> 'attente_commercial' then
    raise exception 'STATUT_INVALIDE|Cette demande n''attend pas de réception.';
  end if;
  if public.dist_role() = 'commercial' and v_dem.commercial_id <> auth.uid() then
    raise exception 'DROIT_REFUSE|Cette dotation ne vous appartient pas.';
  end if;

  if p_lignes is not null and jsonb_typeof(p_lignes) = 'array' then
    for v_l in
      select * from jsonb_to_recordset(p_lignes)
        as x(produit_id uuid, quantite_recue numeric)
    loop
      update public.dist_demande_commercial_lignes
         set quantite_recue = coalesce(v_l.quantite_recue, quantite_sortie)
       where demande_id = p_demande and produit_id = v_l.produit_id;
    end loop;
  end if;

  for v_l in
    select l.produit_id, l.quantite_sortie,
           coalesce(l.quantite_recue, l.quantite_sortie) as recue
      from public.dist_demande_commercial_lignes l
     where l.demande_id = p_demande
  loop
    if v_l.recue < 0 or v_l.recue > v_l.quantite_sortie + 0.0001 then
      raise exception 'QUANTITE_INVALIDE|La quantité reçue dépasse la quantité sortie.';
    end if;

    update public.dist_demande_commercial_lignes
       set quantite_recue = v_l.recue
     where demande_id = p_demande and produit_id = v_l.produit_id;

    if v_l.recue < v_l.quantite_sortie - 0.0001 then
      v_litige := true;
      -- Le commercial n'a pas reçu ce qui était sorti : on retire la
      -- différence de SON stock (elle n'a jamais existé chez lui).
      perform public.dist_bouger_commercial(v_owner, v_dem.commercial_id,
        v_l.produit_id, -(v_l.quantite_sortie - v_l.recue),
        'regularisation_produit', 'demande_commercial', p_demande,
        'Écart de réception ' || v_dem.numero);

      perform public.dist_anomalie(v_owner, 'ECART_DOTATION_COMMERCIAL',
        'dist_demandes_commercial', p_demande,
        'Le commercial déclare ' || trim(to_char(v_l.recue, 'FM999999990.###')) ||
        ' reçu(s) sur ' || trim(to_char(v_l.quantite_sortie, 'FM999999990.###')) ||
        ' attribué(s).',
        v_l.quantite_sortie - v_l.recue);
    end if;
  end loop;

  if v_litige and nullif(btrim(coalesce(p_motif, '')), '') is null then
    raise exception 'MOTIF_REQUIS|Un écart a été constaté : expliquez-le.';
  end if;

  update public.dist_demandes_commercial
     set statut = case when v_litige then 'en_litige' else 'recue' end,
         motif = nullif(btrim(coalesce(p_motif, '')), ''),
         recu_le = now()
   where id = p_demande;

  perform public.dist_journaliser(v_owner, 'DEMANDE_COMMERCIALE_RECUE',
    'dist_demandes_commercial', p_demande,
    jsonb_build_object('numero', v_dem.numero, 'litige', v_litige));

  return jsonb_build_object('ok', true,
                            'statut', case when v_litige then 'en_litige' else 'recue' end);
end;
$$;

create or replace function public.dist_demandes_commercial_lister()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_owner uuid := public.dist_owner_requis();
  v_role text := public.dist_role();
  v_items jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', d.id, 'numero', d.numero, 'statut', d.statut,
           'note', d.note, 'motif', d.motif, 'cree_le', d.cree_le,
           'commercial_id', d.commercial_id,
           'commercial', coalesce(u.nom, 'Commercial'),
           'lignes', (
             select coalesce(jsonb_agg(jsonb_build_object(
               'produit_id', l.produit_id, 'nom', p.nom, 'unite', p.unite,
               'quantite_demandee', l.quantite_demandee,
               'quantite_confirmee', l.quantite_confirmee,
               'quantite_sortie', l.quantite_sortie,
               'quantite_recue', l.quantite_recue
             ) order by p.nom), '[]'::jsonb)
               from public.dist_demande_commercial_lignes l
               join public.dist_produits p on p.id = l.produit_id
              where l.demande_id = d.id)
         ) order by d.cree_le desc), '[]'::jsonb)
    into v_items
    from public.dist_demandes_commercial d
    left join public.utilisateurs u on u.id = d.commercial_id
   where d.owner_id = v_owner
     and (v_role <> 'commercial' or d.commercial_id = auth.uid());

  return jsonb_build_object('ok', true, 'items', v_items);
end;
$$;


-- ============================================================================
--  11. CLIENTS ET VENTES DU COMMERCIAL
-- ============================================================================

create or replace function public.dist_client_enregistrer(
  p_id        uuid,
  p_nom       text,
  p_telephone text default null,
  p_adresse   text default null,
  p_zone      text default null,
  p_note      text default null,
  p_commercial_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid := public.dist_owner_requis();
  v_commercial uuid;
  v_nom text := nullif(btrim(coalesce(p_nom, '')), '');
  v_tel text := nullif(btrim(coalesce(p_telephone, '')), '');
  v_id uuid;
  v_doublon_id uuid;
  v_doublon_nom text;
begin
  if public.dist_role() = 'commercial' then
    v_commercial := auth.uid();
  else
    perform public.dist_exige(array['proprietaire', 'gerant']);
    v_commercial := coalesce(p_commercial_id, auth.uid());
  end if;

  if v_nom is null then
    raise exception 'NOM_REQUIS|Indiquez le nom du client.';
  end if;

  -- Doublon chez CE commercial : même nom ou même téléphone.
  select c.id, c.nom into v_doublon_id, v_doublon_nom
    from public.dist_clients c
   where c.owner_id = v_owner
     and c.commercial_id = v_commercial
     and c.actif
     and (lower(btrim(c.nom)) = lower(v_nom)
          or (v_tel is not null and btrim(coalesce(c.telephone, '')) = v_tel))
     and (p_id is null or c.id <> p_id)
   limit 1;

  if v_doublon_id is not null then
    raise exception 'DOUBLON_CLIENT|Ce client existe déjà : %.', v_doublon_nom;
  end if;

  -- Même téléphone chez un AUTRE commercial : on n'en dit pas plus
  -- (les clients d'un commercial ne regardent pas les autres).
  if v_tel is not null and exists (
    select 1 from public.dist_clients c
     where c.owner_id = v_owner
       and c.commercial_id <> v_commercial
       and btrim(coalesce(c.telephone, '')) = v_tel
  ) then
    raise exception 'DOUBLON_ENTREPRISE|Un client avec ce numéro existe déjà dans l''entreprise. Contactez le gérant.';
  end if;

  if p_id is null then
    insert into public.dist_clients (
      owner_id, commercial_id, nom, telephone, adresse, zone, note
    ) values (v_owner, v_commercial, v_nom, v_tel, nullif(btrim(coalesce(p_adresse, '')), ''),
              nullif(btrim(coalesce(p_zone, '')), ''), nullif(btrim(coalesce(p_note, '')), ''))
    returning id into v_id;
  else
    update public.dist_clients
       set nom = v_nom, telephone = v_tel,
           adresse = coalesce(nullif(btrim(coalesce(p_adresse, '')), ''), adresse),
           zone = coalesce(nullif(btrim(coalesce(p_zone, '')), ''), zone),
           note = coalesce(nullif(btrim(coalesce(p_note, '')), ''), note)
     where id = p_id and owner_id = v_owner
       and (commercial_id = v_commercial
            or public.dist_role() in ('proprietaire', 'gerant'))
     returning id into v_id;

    if v_id is null then
      raise exception 'CLIENT_INTROUVABLE|Ce client n''existe pas.';
    end if;
  end if;

  return jsonb_build_object('ok', true, 'id', v_id);
end;
$$;

create or replace function public.dist_clients_lister(p_commercial_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_owner uuid := public.dist_owner_requis();
  v_role text := public.dist_role();
  v_items jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', c.id, 'nom', c.nom, 'telephone', c.telephone,
           'adresse', c.adresse, 'zone', c.zone, 'note', c.note,
           'commercial_id', c.commercial_id,
           'commercial', coalesce(u.nom, 'Commercial'),
           'cree_le', c.cree_le
         ) order by c.nom), '[]'::jsonb)
    into v_items
    from public.dist_clients c
    left join public.utilisateurs u on u.id = c.commercial_id
   where c.owner_id = v_owner
     and c.actif
     and (v_role <> 'commercial' or c.commercial_id = auth.uid())
     and (p_commercial_id is null or c.commercial_id = p_commercial_id);

  return jsonb_build_object('ok', true, 'items', v_items);
end;
$$;

create or replace function public.dist_facture_json(p_vente uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_owner uuid := public.dist_owner_requis();
  v_role text := public.dist_role();
  v_v record;
  v_client record;
  v_ent record;
  v_lignes jsonb;
begin
  select * into v_v from public.dist_ventes
   where id = p_vente and owner_id = v_owner;

  if v_v.id is null then
    raise exception 'VENTE_INTROUVABLE|Cette vente n''existe pas.';
  end if;

  if v_role = 'commercial' and v_v.commercial_id <> auth.uid() then
    raise exception 'DROIT_REFUSE|Cette facture ne vous appartient pas.';
  end if;

  select c.nom, c.telephone, c.adresse, c.zone into v_client
    from public.dist_clients c where c.id = v_v.client_id;

  -- `entreprises` est une table historique : on lit les champs optionnels
  -- via `to_jsonb` pour ne jamais échouer si une colonne n'existe pas.
  select e.nom,
         to_jsonb(e)->>'adresse'   as adresse,
         to_jsonb(e)->>'telephone' as telephone
    into v_ent
    from public.entreprises e
    join public.utilisateurs u on u.entreprise_id = e.id
   where u.id = v_owner;

  select coalesce(jsonb_agg(jsonb_build_object(
           'nom', l.nom_produit, 'quantite', l.quantite,
           'prix_unitaire', l.prix_unitaire, 'total', l.total
         ) order by l.nom_produit), '[]'::jsonb)
    into v_lignes
    from public.dist_vente_lignes l
   where l.vente_id = p_vente;

  return jsonb_build_object(
    'ok', true,
    'entreprise', coalesce(v_ent.nom, 'Entreprise'),
    'entreprise_adresse', v_ent.adresse,
    'entreprise_telephone', v_ent.telephone,
    'numero', v_v.numero,
    'date', v_v.date_vente,
    'commercial', coalesce((select u.nom from public.utilisateurs u
                             where u.id = v_v.commercial_id), 'Commercial'),
    'client', coalesce(v_client.nom, 'Client comptant'),
    'client_telephone', v_client.telephone,
    'client_adresse', v_client.adresse,
    'mode_paiement', v_v.mode_paiement,
    'lignes', v_lignes,
    'total', v_v.total,
    'montant_paye', v_v.montant_paye,
    'credit', v_v.credit
  );
end;
$$;

create or replace function public.dist_vente_enregistrer(
  p_client_id   uuid,
  p_lignes      jsonb,
  p_montant_paye numeric default null,
  p_mode        text default 'especes',
  p_note        text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid := public.dist_owner_requis();
  v_commercial uuid := auth.uid();
  v_id uuid;
  v_num text;
  v_l record;
  v_prod record;
  v_total numeric(16,2) := 0;
  v_paye numeric(16,2);
  v_prix numeric(16,2);
begin
  perform public.dist_exige(array['commercial']);

  if p_lignes is null or jsonb_typeof(p_lignes) <> 'array'
     or jsonb_array_length(p_lignes) = 0 then
    raise exception 'LIGNES_VIDES|Ajoutez au moins un produit vendu.';
  end if;

  if p_client_id is not null and not exists (
    select 1 from public.dist_clients c
     where c.id = p_client_id and c.owner_id = v_owner
       and c.commercial_id = v_commercial and c.actif
  ) then
    raise exception 'CLIENT_INTROUVABLE|Ce client ne vous appartient pas.';
  end if;

  v_num := public.dist_numero(v_owner, 'FAC');

  insert into public.dist_ventes (
    owner_id, numero, commercial_id, client_id, mode_paiement, note
  ) values (
    v_owner, v_num, v_commercial, p_client_id,
    coalesce(nullif(btrim(p_mode), ''), 'especes'),
    nullif(btrim(coalesce(p_note, '')), '')
  ) returning id into v_id;

  for v_l in
    select * from jsonb_to_recordset(p_lignes)
      as x(produit_id uuid, quantite numeric)
  loop
    if v_l.produit_id is null or v_l.quantite is null or v_l.quantite <= 0 then
      raise exception 'QUANTITE_INVALIDE|Quantité vendue invalide.';
    end if;

    select p.nom, p.prix_vente into v_prod
      from public.dist_produits p
     where p.id = v_l.produit_id and p.owner_id = v_owner and p.actif;

    if v_prod.nom is null then
      raise exception 'PRODUIT_INCONNU|Un des produits n''existe pas.';
    end if;

    v_prix := coalesce(v_prod.prix_vente, 0);

    -- Le stock PERSONNEL du commercial est le seul débité ici.
    perform public.dist_bouger_commercial(v_owner, v_commercial,
      v_l.produit_id, -v_l.quantite, 'vente_commercial',
      'vente', v_id, 'Vente ' || v_num);

    insert into public.dist_vente_lignes (
      vente_id, produit_id, nom_produit, quantite, prix_unitaire, total
    ) values (
      v_id, v_l.produit_id, v_prod.nom, v_l.quantite, v_prix,
      round((v_l.quantite * v_prix)::numeric, 2)
    );

    v_total := v_total + round((v_l.quantite * v_prix)::numeric, 2);
  end loop;

  v_paye := coalesce(p_montant_paye, v_total);
  if v_paye < 0 or v_paye > v_total + 0.009 then
    raise exception 'MONTANT_INVALIDE|Le montant reçu doit être compris entre 0 et le total.';
  end if;

  update public.dist_ventes
     set total = v_total,
         montant_paye = v_paye,
         credit = v_total - v_paye
   where id = v_id;

  perform public.dist_journaliser(v_owner, 'VENTE_DISTRIBUTION',
    'dist_ventes', v_id,
    jsonb_build_object('numero', v_num, 'total', v_total,
                       'paye', v_paye, 'credit', v_total - v_paye,
                       'commercial_id', v_commercial));

  return public.dist_facture_json(v_id);
end;
$$;

create or replace function public.dist_ventes_lister(
  p_debut date default null,
  p_fin   date default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_owner uuid := public.dist_owner_requis();
  v_role text := public.dist_role();
  v_items jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', v.id, 'numero', v.numero, 'date', v.date_vente,
           'commercial_id', v.commercial_id,
           'commercial', coalesce(u.nom, 'Commercial'),
           'client', coalesce(c.nom, 'Client comptant'),
           'total', v.total, 'montant_paye', v.montant_paye,
           'credit', v.credit, 'mode_paiement', v.mode_paiement,
           'lignes', (
             select coalesce(jsonb_agg(jsonb_build_object(
               'nom', l.nom_produit, 'quantite', l.quantite,
               'prix_unitaire', l.prix_unitaire, 'total', l.total
             ) order by l.nom_produit), '[]'::jsonb)
               from public.dist_vente_lignes l where l.vente_id = v.id)
         ) order by v.date_vente desc), '[]'::jsonb)
    into v_items
    from public.dist_ventes v
    left join public.utilisateurs u on u.id = v.commercial_id
    left join public.dist_clients c on c.id = v.client_id
   where v.owner_id = v_owner
     and (v_role <> 'commercial' or v.commercial_id = auth.uid())
     and (p_debut is null or v.date_vente >= p_debut::timestamptz)
     and (p_fin is null or v.date_vente < (p_fin + 1)::timestamptz);

  return jsonb_build_object('ok', true, 'items', v_items);
end;
$$;

create or replace function public.dist_produits_catalogue()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_owner uuid := public.dist_owner_requis();
  v_items jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', p.id, 'nom', p.nom, 'format', p.format, 'unite', p.unite,
           'prix_vente', p.prix_vente, 'stock_central', p.stock
         ) order by p.nom), '[]'::jsonb)
    into v_items
    from public.dist_produits p
   where p.owner_id = v_owner and p.actif;

  return jsonb_build_object('ok', true, 'items', v_items);
end;
$$;

create or replace function public.dist_mes_produits()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_owner uuid := public.dist_owner_requis();
  v_commercial uuid := auth.uid();
  v_items jsonb;
begin
  if public.dist_role() <> 'commercial' then
    raise exception 'DROIT_REFUSE|Cette vue est réservée au commercial.';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'produit_id', s.produit_id, 'nom', p.nom, 'unite', p.unite,
           'quantite', s.quantite, 'prix_vente', p.prix_vente
         ) order by p.nom), '[]'::jsonb)
    into v_items
    from public.dist_stock_commercial s
    join public.dist_produits p on p.id = s.produit_id
   where s.owner_id = v_owner and s.commercial_id = v_commercial;

  return jsonb_build_object('ok', true, 'items', v_items);
end;
$$;


-- ============================================================================
--  12. RETOURS DE MARCHANDISES
-- ============================================================================

create or replace function public.dist_retour_declarer(
  p_lignes jsonb,
  p_note   text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid := public.dist_owner_requis();
  v_commercial uuid := auth.uid();
  v_id uuid;
  v_num text;
  v_l record;
begin
  perform public.dist_exige(array['commercial']);

  if p_lignes is null or jsonb_typeof(p_lignes) <> 'array'
     or jsonb_array_length(p_lignes) = 0 then
    raise exception 'LIGNES_VIDES|Déclarez au moins un produit retourné.';
  end if;

  v_num := public.dist_numero(v_owner, 'RET');

  insert into public.dist_retours (owner_id, numero, commercial_id, statut, note)
  values (v_owner, v_num, v_commercial, 'attente_stock',
          nullif(btrim(coalesce(p_note, '')), ''))
  returning id into v_id;

  for v_l in
    select * from jsonb_to_recordset(p_lignes)
      as x(produit_id uuid, quantite numeric)
  loop
    if v_l.produit_id is null or v_l.quantite is null or v_l.quantite <= 0 then
      raise exception 'QUANTITE_INVALIDE|Quantité retournée invalide.';
    end if;

    -- Le produit quitte le stock du commercial dès la déclaration ;
    -- il n'entre au stock central qu'après comptage par le stockier.
    perform public.dist_bouger_commercial(v_owner, v_commercial,
      v_l.produit_id, -v_l.quantite, 'retour_commercial',
      'retour', v_id, 'Retour déclaré ' || v_num);

    insert into public.dist_retour_lignes (retour_id, produit_id, quantite_declaree)
    values (v_id, v_l.produit_id, v_l.quantite);
  end loop;

  perform public.dist_journaliser(v_owner, 'RETOUR_DECLARE', 'dist_retours', v_id,
    jsonb_build_object('numero', v_num, 'commercial_id', v_commercial));

  return jsonb_build_object('ok', true, 'id', v_id, 'numero', v_num);
end;
$$;

create or replace function public.dist_retour_receptionner(
  p_retour uuid,
  p_lignes jsonb default null,
  p_motif  text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid := public.dist_owner_requis();
  v_ret record;
  v_l record;
  v_litige boolean := false;
begin
  perform public.dist_exige(array['stock', 'gerant', 'proprietaire']);

  select * into v_ret from public.dist_retours
   where id = p_retour and owner_id = v_owner for update;

  if v_ret.id is null then
    raise exception 'RETOUR_INTROUVABLE|Ce retour n''existe pas.';
  end if;
  if v_ret.statut <> 'attente_stock' then
    raise exception 'STATUT_INVALIDE|Ce retour a déjà été traité.';
  end if;

  if p_lignes is not null and jsonb_typeof(p_lignes) = 'array' then
    for v_l in
      select * from jsonb_to_recordset(p_lignes)
        as x(produit_id uuid, quantite_recue numeric)
    loop
      update public.dist_retour_lignes
         set quantite_recue = coalesce(v_l.quantite_recue, quantite_declaree)
       where retour_id = p_retour and produit_id = v_l.produit_id;
    end loop;
  end if;

  for v_l in
    select l.produit_id, l.quantite_declaree,
           coalesce(l.quantite_recue, l.quantite_declaree) as recue
      from public.dist_retour_lignes l
     where l.retour_id = p_retour
  loop
    if v_l.recue < 0 or v_l.recue > v_l.quantite_declaree + 0.0001 then
      raise exception 'QUANTITE_INVALIDE|La quantité comptée dépasse la quantité déclarée.';
    end if;

    update public.dist_retour_lignes
       set quantite_recue = v_l.recue
     where retour_id = p_retour and produit_id = v_l.produit_id;

    if v_l.recue > 0 then
      perform public.dist_bouger_produit(v_owner, v_l.produit_id, v_l.recue,
        'retour_commercial', 'retour', p_retour, 'Retour ' || v_ret.numero);
    end if;

    if v_l.recue < v_l.quantite_declaree - 0.0001 then
      v_litige := true;
      perform public.dist_anomalie(v_owner, 'ECART_RETOUR_COMMERCIAL',
        'dist_retours', p_retour,
        'Le commercial déclare ' ||
        trim(to_char(v_l.quantite_declaree, 'FM999999990.###')) ||
        ', le stock n''en compte que ' ||
        trim(to_char(v_l.recue, 'FM999999990.###')) || '.',
        v_l.quantite_declaree - v_l.recue);
    end if;
  end loop;

  if v_litige and nullif(btrim(coalesce(p_motif, '')), '') is null then
    raise exception 'MOTIF_REQUIS|Un écart a été constaté : expliquez-le.';
  end if;

  update public.dist_retours
     set statut = case when v_litige then 'en_litige' else 'recue' end,
         motif = nullif(btrim(coalesce(p_motif, '')), ''),
         recepteur_id = auth.uid(), recu_le = now()
   where id = p_retour;

  perform public.dist_journaliser(v_owner, 'RETOUR_RECEPTIONNE', 'dist_retours', p_retour,
    jsonb_build_object('numero', v_ret.numero, 'litige', v_litige));

  return jsonb_build_object('ok', true,
                            'statut', case when v_litige then 'en_litige' else 'recue' end);
end;
$$;

create or replace function public.dist_retours_lister()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_owner uuid := public.dist_owner_requis();
  v_role text := public.dist_role();
  v_items jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', r.id, 'numero', r.numero, 'statut', r.statut,
           'note', r.note, 'motif', r.motif, 'cree_le', r.cree_le,
           'commercial_id', r.commercial_id,
           'commercial', coalesce(u.nom, 'Commercial'),
           'lignes', (
             select coalesce(jsonb_agg(jsonb_build_object(
               'produit_id', l.produit_id, 'nom', p.nom, 'unite', p.unite,
               'quantite_declaree', l.quantite_declaree,
               'quantite_recue', l.quantite_recue
             ) order by p.nom), '[]'::jsonb)
               from public.dist_retour_lignes l
               join public.dist_produits p on p.id = l.produit_id
              where l.retour_id = r.id)
         ) order by r.cree_le desc), '[]'::jsonb)
    into v_items
    from public.dist_retours r
    left join public.utilisateurs u on u.id = r.commercial_id
   where r.owner_id = v_owner
     and (v_role <> 'commercial' or r.commercial_id = auth.uid());

  return jsonb_build_object('ok', true, 'items', v_items);
end;
$$;


-- ============================================================================
--  13. REMISES D'ARGENT (commercial → comptable → gérant)
-- ============================================================================

create or replace function public.dist_solde_commercial(p_owner uuid, p_commercial uuid)
returns numeric
language sql
stable
security definer
set search_path = public
as $$
  select greatest(
    coalesce((select sum(v.montant_paye) from public.dist_ventes v
               where v.owner_id = p_owner and v.commercial_id = p_commercial), 0)
    - coalesce((select sum(r.montant_declare) from public.dist_remises r
                 where r.owner_id = p_owner and r.commercial_id = p_commercial
                   and r.statut <> 'refusee'), 0),
    0);
$$;

create or replace function public.dist_remise_declarer(
  p_montant numeric,
  p_mode    text default 'especes',
  p_note    text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid := public.dist_owner_requis();
  v_commercial uuid := auth.uid();
  v_dispo numeric(16,2);
  v_id uuid;
  v_num text;
begin
  perform public.dist_exige(array['commercial']);

  if p_montant is null or p_montant <= 0 then
    raise exception 'MONTANT_INVALIDE|Le montant à remettre doit être supérieur à zéro.';
  end if;

  v_dispo := public.dist_solde_commercial(v_owner, v_commercial);
  if p_montant > v_dispo + 0.01 then
    raise exception 'MONTANT_SUPERIEUR|Vous ne détenez que % à remettre.',
      trim(to_char(v_dispo, 'FM999999990.00'));
  end if;

  v_num := public.dist_numero(v_owner, 'REM');

  insert into public.dist_remises (
    owner_id, numero, commercial_id, montant_declare, mode_paiement, statut, motif
  ) values (
    v_owner, v_num, v_commercial, p_montant,
    coalesce(nullif(btrim(p_mode), ''), 'especes'), 'declaree',
    nullif(btrim(coalesce(p_note, '')), '')
  ) returning id into v_id;

  perform public.dist_journaliser(v_owner, 'REMISE_DECLAREE', 'dist_remises', v_id,
    jsonb_build_object('numero', v_num, 'montant', p_montant,
                       'commercial_id', v_commercial));

  return jsonb_build_object('ok', true, 'id', v_id, 'numero', v_num,
                            'montant', p_montant);
end;
$$;

create or replace function public.dist_remise_receptionner(
  p_remise       uuid,
  p_montant_recu numeric,
  p_motif        text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid := public.dist_owner_requis();
  v_rem record;
  v_ecart boolean;
begin
  perform public.dist_exige(array['comptable', 'gerant', 'proprietaire']);

  select * into v_rem from public.dist_remises
   where id = p_remise and owner_id = v_owner for update;

  if v_rem.id is null then
    raise exception 'REMISE_INTROUVABLE|Cette remise n''existe pas.';
  end if;
  if v_rem.statut <> 'declaree' then
    raise exception 'STATUT_INVALIDE|Cette remise a déjà été réceptionnée.';
  end if;

  if p_montant_recu is null or p_montant_recu < 0 then
    raise exception 'MONTANT_INVALIDE|Montant reçu invalide.';
  end if;

  v_ecart := abs(p_montant_recu - v_rem.montant_declare) > 0.009;

  if v_ecart and nullif(btrim(coalesce(p_motif, '')), '') is null then
    raise exception 'ECART_SANS_MOTIF|Le montant reçu diffère du montant déclaré : indiquez un motif.';
  end if;

  if v_ecart then
    perform public.dist_anomalie(v_owner, 'ECART_REMISE', 'dist_remises', p_remise,
      'Remise ' || v_rem.numero || ' : déclaré ' ||
      trim(to_char(v_rem.montant_declare, 'FM999999990.00')) ||
      ', reçu ' || trim(to_char(p_montant_recu, 'FM999999990.00')) ||
      '. Motif : ' || btrim(coalesce(p_motif, 'non précisé')),
      null, v_rem.montant_declare - p_montant_recu);
  end if;

  update public.dist_remises
     set montant_recu = p_montant_recu,
         statut = case when v_ecart then 'litige' else 'recue' end,
         motif = coalesce(nullif(btrim(coalesce(p_motif, '')), ''), motif),
         receptionnaire_id = auth.uid(), recu_le = now()
   where id = p_remise;

  perform public.dist_journaliser(v_owner, 'REMISE_RECEPTIONNEE', 'dist_remises', p_remise,
    jsonb_build_object('numero', v_rem.numero, 'montant_recu', p_montant_recu,
                       'ecart', v_ecart));

  return jsonb_build_object('ok', true,
                            'statut', case when v_ecart then 'litige' else 'recue' end);
end;
$$;

create or replace function public.dist_remise_valider(
  p_remise        uuid,
  p_montant_valide numeric default null,
  p_motif         text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid := public.dist_owner_requis();
  v_rem record;
  v_montant numeric(16,2);
begin
  perform public.dist_exige(array['gerant', 'proprietaire']);

  select * into v_rem from public.dist_remises
   where id = p_remise and owner_id = v_owner for update;

  if v_rem.id is null then
    raise exception 'REMISE_INTROUVABLE|Cette remise n''existe pas.';
  end if;
  if v_rem.statut not in ('recue', 'litige') then
    raise exception 'STATUT_INVALIDE|Le comptable doit d''abord réceptionner la remise.';
  end if;

  v_montant := coalesce(p_montant_valide, v_rem.montant_recu, v_rem.montant_declare);

  if v_montant is null or v_montant < 0 then
    raise exception 'MONTANT_INVALIDE|Montant à valider invalide.';
  end if;

  if abs(v_montant - coalesce(v_rem.montant_recu, 0)) > 0.009
     and nullif(btrim(coalesce(p_motif, '')), '') is null then
    raise exception 'ECART_SANS_MOTIF|Le montant validé diffère du montant reçu : indiquez un motif.';
  end if;

  if v_montant > 0 then
    insert into public.dist_caisse (
      owner_id, sens, montant, motif, categorie, reference_type, reference_id, auteur_id
    ) values (
      v_owner, 'entree', v_montant,
      'Remise commerciale ' || v_rem.numero, 'remise_commercial',
      'dist_remises', p_remise, auth.uid()
    );
  end if;

  update public.dist_remises
     set montant_valide = v_montant,
         statut = 'validee',
         motif = coalesce(nullif(btrim(coalesce(p_motif, '')), ''), motif),
         valide_par = auth.uid(), valide_le = now()
   where id = p_remise;

  perform public.dist_journaliser(v_owner, 'REMISE_VALIDEE', 'dist_remises', p_remise,
    jsonb_build_object('numero', v_rem.numero, 'montant_valide', v_montant,
                       'commercial_id', v_rem.commercial_id));

  return jsonb_build_object('ok', true, 'montant_valide', v_montant,
                            'solde_caisse', public.dist_caisse_solde(v_owner));
end;
$$;

create or replace function public.dist_remises_lister()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_owner uuid := public.dist_owner_requis();
  v_role text := public.dist_role();
  v_items jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', r.id, 'numero', r.numero, 'statut', r.statut,
           'commercial_id', r.commercial_id,
           'commercial', coalesce(u.nom, 'Commercial'),
           'montant_declare', r.montant_declare,
           'montant_recu', r.montant_recu,
           'montant_valide', r.montant_valide,
           'mode_paiement', r.mode_paiement,
           'motif', r.motif, 'declare_le', r.declare_le,
           'recu_le', r.recu_le, 'valide_le', r.valide_le
         ) order by r.declare_le desc), '[]'::jsonb)
    into v_items
    from public.dist_remises r
    left join public.utilisateurs u on u.id = r.commercial_id
   where r.owner_id = v_owner
     and (v_role <> 'commercial' or r.commercial_id = auth.uid());

  return jsonb_build_object('ok', true, 'items', v_items,
                            'solde_commercial',
                            case when v_role = 'commercial'
                                 then public.dist_solde_commercial(v_owner, auth.uid())
                                 else null end);
end;
$$;


-- ============================================================================
--  14. CAISSE ET DÉPENSES
-- ============================================================================

create or replace function public.dist_caisse_apport(
  p_montant numeric,
  p_motif   text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid := public.dist_owner_requis();
begin
  perform public.dist_exige(array['proprietaire']);

  if p_montant is null or p_montant <= 0 then
    raise exception 'MONTANT_INVALIDE|Le montant doit être supérieur à zéro.';
  end if;
  if nullif(btrim(coalesce(p_motif, '')), '') is null then
    raise exception 'MOTIF_REQUIS|Indiquez l''origine de l''apport.';
  end if;

  insert into public.dist_caisse (owner_id, sens, montant, motif, categorie, auteur_id)
  values (v_owner, 'entree', p_montant, btrim(p_motif), 'apport', auth.uid());

  perform public.dist_journaliser(v_owner, 'CAISSE_APPORT', 'dist_caisse', null,
    jsonb_build_object('montant', p_montant, 'motif', p_motif));

  return jsonb_build_object('ok', true, 'solde', public.dist_caisse_solde(v_owner));
end;
$$;

create or replace function public.dist_caisse_resume()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_owner uuid := public.dist_owner_requis();
  v_initial numeric;
  v_entrees numeric;
  v_sorties numeric;
  v_mouvements jsonb;
begin
  select coalesce(solde_initial, 0) into v_initial
    from public.dist_parametres where owner_id = v_owner;
  v_initial := coalesce(v_initial, 0);

  select coalesce(sum(case when sens = 'entree' then montant else 0 end), 0),
         coalesce(sum(case when sens = 'sortie' then montant else 0 end), 0)
    into v_entrees, v_sorties
    from public.dist_caisse where owner_id = v_owner;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', c.id, 'sens', c.sens, 'montant', c.montant,
           'motif', c.motif, 'categorie', c.categorie,
           'date', c.created_at,
           'auteur', coalesce(u.nom, 'Système')
         ) order by c.created_at desc), '[]'::jsonb)
    into v_mouvements
    from public.dist_caisse c
    left join public.utilisateurs u on u.id = c.auteur_id
   where c.owner_id = v_owner;

  return jsonb_build_object(
    'ok', true,
    'solde_initial', v_initial,
    'entrees', v_entrees,
    'sorties', v_sorties,
    'solde', v_initial + v_entrees - v_sorties,
    'mouvements', v_mouvements
  );
end;
$$;

create or replace function public.dist_depense_creer(
  p_categorie    text,
  p_montant      numeric,
  p_motif        text,
  p_date         date default current_date,
  p_justificatif text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid := public.dist_owner_requis();
  v_id uuid;
  v_num text;
  v_devise text;
begin
  perform public.dist_exige(array['comptable', 'gerant', 'proprietaire']);

  if p_montant is null or p_montant <= 0 then
    raise exception 'MONTANT_INVALIDE|Le montant de la dépense doit être supérieur à zéro.';
  end if;
  if nullif(btrim(coalesce(p_motif, '')), '') is null or length(btrim(p_motif)) < 3 then
    raise exception 'MOTIF_REQUIS|Expliquez la dépense (3 caractères minimum).';
  end if;

  select coalesce(devise, 'CDF') into v_devise
    from public.dist_parametres where owner_id = v_owner;
  v_devise := coalesce(v_devise, 'CDF');

  v_num := public.dist_numero(v_owner, 'DEP');

  insert into public.dist_depenses (
    owner_id, numero, categorie, montant, devise, motif, date_depense,
    justificatif, statut, cree_par
  ) values (
    v_owner, v_num, coalesce(nullif(btrim(p_categorie), ''), 'autre'),
    p_montant, v_devise, btrim(p_motif), coalesce(p_date, current_date),
    nullif(btrim(coalesce(p_justificatif, '')), ''), 'en_attente', auth.uid()
  ) returning id into v_id;

  perform public.dist_journaliser(v_owner, 'DEPENSE_CREEE', 'dist_depenses', v_id,
    jsonb_build_object('numero', v_num, 'montant', p_montant, 'motif', p_motif));

  return jsonb_build_object('ok', true, 'id', v_id, 'numero', v_num);
end;
$$;

create or replace function public.dist_depense_valider(
  p_depense  uuid,
  p_accepter boolean,
  p_motif    text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid := public.dist_owner_requis();
  v_dep record;
  v_solde numeric;
  v_neg boolean := false;
begin
  perform public.dist_exige(array['gerant', 'proprietaire']);

  select * into v_dep from public.dist_depenses
   where id = p_depense and owner_id = v_owner for update;

  if v_dep.id is null then
    raise exception 'DEPENSE_INTROUVABLE|Cette dépense n''existe pas.';
  end if;
  if v_dep.statut <> 'en_attente' then
    raise exception 'STATUT_INVALIDE|Cette dépense a déjà été traitée.';
  end if;

  if not coalesce(p_accepter, false) then
    if nullif(btrim(coalesce(p_motif, '')), '') is null then
      raise exception 'MOTIF_REQUIS|Indiquez pourquoi la dépense est refusée.';
    end if;
    update public.dist_depenses
       set statut = 'refusee', motif_refus = btrim(p_motif),
           valide_par = auth.uid(), valide_le = now()
     where id = p_depense;
    perform public.dist_journaliser(v_owner, 'DEPENSE_REFUSEE', 'dist_depenses', p_depense,
      jsonb_build_object('motif', p_motif));
    return jsonb_build_object('ok', true, 'statut', 'refusee');
  end if;

  select coalesce(autoriser_solde_negatif, false) into v_neg
    from public.dist_parametres where owner_id = v_owner;

  v_solde := public.dist_caisse_solde(v_owner);
  if v_dep.montant > v_solde + 0.009 and not coalesce(v_neg, false) then
    raise exception 'SOLDE_INSUFFISANT|La caisse ne contient que %.',
      trim(to_char(v_solde, 'FM999999990.00'));
  end if;

  insert into public.dist_caisse (
    owner_id, sens, montant, motif, categorie, reference_type, reference_id, auteur_id
  ) values (
    v_owner, 'sortie', v_dep.montant,
    v_dep.motif, v_dep.categorie, 'dist_depenses', p_depense, auth.uid()
  );

  update public.dist_depenses
     set statut = 'validee', valide_par = auth.uid(), valide_le = now()
   where id = p_depense;

  perform public.dist_journaliser(v_owner, 'DEPENSE_VALIDEE', 'dist_depenses', p_depense,
    jsonb_build_object('numero', v_dep.numero, 'montant', v_dep.montant));

  return jsonb_build_object('ok', true, 'statut', 'validee',
                            'solde_caisse', public.dist_caisse_solde(v_owner));
end;
$$;

create or replace function public.dist_depenses_lister()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_owner uuid := public.dist_owner_requis();
  v_items jsonb;
begin
  perform public.dist_exige(array['comptable', 'gerant', 'proprietaire']);

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', d.id, 'numero', d.numero, 'categorie', d.categorie,
           'montant', d.montant, 'devise', d.devise, 'motif', d.motif,
           'date_depense', d.date_depense, 'justificatif', d.justificatif,
           'statut', d.statut, 'motif_refus', d.motif_refus,
           'cree_le', d.cree_le,
           'auteur', coalesce(u.nom, 'Système')
         ) order by d.date_depense desc, d.cree_le desc), '[]'::jsonb)
    into v_items
    from public.dist_depenses d
    left join public.utilisateurs u on u.id = d.cree_par
   where d.owner_id = v_owner;

  return jsonb_build_object('ok', true, 'items', v_items);
end;
$$;


-- ============================================================================
--  15. TABLEAU DE BORD ET FILE DES VALIDATIONS
-- ============================================================================

create or replace function public.dist_tableau_bord()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_owner uuid := public.dist_owner_requis();
  v_role text := public.dist_role();
  v_pet numeric := 0;
  v_caps numeric := 0;
  v_vides numeric := 0;
  v_intrants_total numeric := 0;
  v_fardes numeric := 0;
  v_bouteilles numeric := 0;
  v_bidons numeric := 0;
  v_produits_total numeric := 0;
  v_attribues numeric := 0;
  v_demandes_prod integer := 0;
  v_demandes_stock integer := 0;
  v_productions integer := 0;
  v_prod_attente integer := 0;
  v_receptions integer := 0;
  v_demandes_com integer := 0;
  v_retours integer := 0;
  v_remises_comptable integer := 0;
  v_remises_gerant integer := 0;
  v_depenses integer := 0;
  v_ventes numeric := 0;
  v_collecte numeric := 0;
  v_recu_comptable numeric := 0;
  v_depenses_mois numeric := 0;
  v_anomalies integer := 0;
  v_tournees integer := 0;
  v_operations jsonb;
begin
  select coalesce(sum(i.stock), 0) into v_intrants_total
    from public.dist_intrants i where i.owner_id = v_owner and i.actif;

  select
    coalesce(sum(case when lower(i.nom) like '%pet%' or lower(coalesce(i.code,'')) = 'pet'
                      then i.stock else 0 end), 0),
    coalesce(sum(case when lower(i.nom) like '%cap%' or lower(i.nom) like '%bouchon%'
                       or lower(coalesce(i.code,'')) in ('caps','bouchon')
                      then i.stock else 0 end), 0),
    coalesce(sum(case when lower(i.nom) like '%bouteille%'
                       and (lower(i.nom) like '%vide%' or lower(coalesce(i.code,'')) = 'bouteille_vide')
                      then i.stock else 0 end), 0)
    into v_pet, v_caps, v_vides
    from public.dist_intrants i where i.owner_id = v_owner and i.actif;

  select coalesce(sum(p.stock), 0) into v_produits_total
    from public.dist_produits p where p.owner_id = v_owner and p.actif;

  select
    coalesce(sum(case when lower(p.nom) like '%farde%' or lower(p.format) = 'farde'
                      then p.stock else 0 end), 0),
    coalesce(sum(case when lower(p.nom) like '%bouteille%'
                      then p.stock else 0 end), 0),
    coalesce(sum(case when lower(p.nom) like '%bidon%' or lower(p.format) = 'bidon'
                      then p.stock else 0 end), 0)
    into v_fardes, v_bouteilles, v_bidons
    from public.dist_produits p where p.owner_id = v_owner and p.actif;

  select coalesce(sum(s.quantite), 0) into v_attribues
    from public.dist_stock_commercial s where s.owner_id = v_owner;

  select count(*) into v_demandes_prod
    from public.dist_demandes_intrants d
   where d.owner_id = v_owner and d.statut = 'attente_stock';

  select count(*) into v_demandes_stock
    from public.dist_demandes_intrants d
   where d.owner_id = v_owner and d.statut = 'attente_reception';

  select count(*) into v_productions
    from public.dist_productions p
   where p.owner_id = v_owner and p.statut = 'attente_stock';

  select count(*) into v_prod_attente
    from public.dist_productions p
   where p.owner_id = v_owner and p.statut in ('attente_stock', 'en_litige');

  select count(*) into v_receptions
    from public.dist_receptions r
   where r.owner_id = v_owner and r.statut = 'attente_gerant';

  select count(*) into v_demandes_com
    from public.dist_demandes_commercial d
   where d.owner_id = v_owner
     and d.statut in ('attente_production', 'attente_stock', 'attente_commercial');

  select count(*) into v_retours
    from public.dist_retours r
   where r.owner_id = v_owner and r.statut = 'attente_stock';

  select count(*) into v_remises_comptable
    from public.dist_remises r
   where r.owner_id = v_owner and r.statut = 'declaree';

  select count(*) into v_remises_gerant
    from public.dist_remises r
   where r.owner_id = v_owner and r.statut in ('recue', 'litige');

  select count(*) into v_depenses
    from public.dist_depenses d
   where d.owner_id = v_owner and d.statut = 'en_attente';

  select coalesce(sum(v.total), 0), coalesce(sum(v.montant_paye), 0)
    into v_ventes, v_collecte
    from public.dist_ventes v where v.owner_id = v_owner;

  select coalesce(sum(r.montant_valide), 0) into v_recu_comptable
    from public.dist_remises r
   where r.owner_id = v_owner and r.statut = 'validee';

  select coalesce(sum(d.montant), 0) into v_depenses_mois
    from public.dist_depenses d
   where d.owner_id = v_owner and d.statut = 'validee'
     and d.date_depense >= date_trunc('month', current_date)::date;

  select count(*) into v_anomalies
    from public.dist_anomalies a
   where a.owner_id = v_owner and a.statut = 'ouverte';

  -- Le module 23 (tournées) peut ne pas être installé : on ne le lit que
  -- s'il existe, et on ne bloque jamais le tableau de bord pour autant.
  if to_regclass('public.tournees') is not null then
    select count(*) into v_tournees
      from public.tournees t
     where t.owner_id = v_owner and t.statut in ('preparee', 'en_cours');
  end if;

  v_operations := public.dist_validations();

  return jsonb_build_object(
    'ok', true,
    'role', v_role,
    'devise', coalesce((select devise from public.dist_parametres
                         where owner_id = v_owner), 'CDF'),
    'intrants', jsonb_build_object(
      'total', v_intrants_total, 'pet', v_pet, 'caps', v_caps,
      'bouteilles_vides', v_vides),
    'produits', jsonb_build_object(
      'total', v_produits_total, 'fardes', v_fardes,
      'bouteilles', v_bouteilles, 'bidons', v_bidons),
    'attribues_commerciaux', v_attribues,
    'demandes_intrants_attente_stock', v_demandes_prod,
    'demandes_intrants_attente_production', v_demandes_stock,
    'productions_attente_stock', v_productions,
    'productions_en_attente', v_prod_attente,
    'receptions_attente_gerant', v_receptions,
    'demandes_commerciales_en_cours', v_demandes_com,
    'retours_attente_stock', v_retours,
    'remises_attente_comptable', v_remises_comptable,
    'remises_attente_gerant', v_remises_gerant,
    'depenses_attente', v_depenses,
    'ventes_total', v_ventes,
    'collecte_commerciaux', v_collecte,
    'montant_recu_comptable', v_recu_comptable,
    'collecte_non_remise', greatest(v_collecte - v_recu_comptable, 0),
    'caisse_solde', public.dist_caisse_solde(v_owner),
    'depenses_mois', v_depenses_mois,
    'anomalies_ouvertes', v_anomalies,
    'tournees_en_cours', v_tournees,
    'operations', v_operations
  );
end;
$$;

create or replace function public.dist_validations()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_owner uuid := public.dist_owner_requis();
  v_role text := public.dist_role();
  v_items jsonb;
begin
  select coalesce(jsonb_agg(x order by x->>'date' desc), '[]'::jsonb)
    into v_items
    from (
      select jsonb_build_object(
               'type', 'reception_intrants', 'id', r.id, 'numero', r.numero,
               'libelle', 'Réception d''intrants à confirmer par le gérant',
               'role', 'gerant', 'date', r.cree_le) as x
        from public.dist_receptions r
       where r.owner_id = v_owner and r.statut = 'attente_gerant'
      union all
      select jsonb_build_object(
               'type', 'demande_intrants_stock', 'id', d.id, 'numero', d.numero,
               'libelle', 'Demande d''intrants à traiter par le stock',
               'role', 'stock', 'date', d.cree_le)
        from public.dist_demandes_intrants d
       where d.owner_id = v_owner and d.statut = 'attente_stock'
      union all
      select jsonb_build_object(
               'type', 'demande_intrants_reception', 'id', d.id, 'numero', d.numero,
               'libelle', 'Intrants remis : le producteur confirme la réception',
               'role', 'production', 'date', d.traite_le)
        from public.dist_demandes_intrants d
       where d.owner_id = v_owner and d.statut = 'attente_reception'
      union all
      select jsonb_build_object(
               'type', 'production_reception', 'id', p.id, 'numero', p.numero,
               'libelle', 'Production terminée : le stock confirme la réception',
               'role', 'stock', 'date', p.cree_le)
        from public.dist_productions p
       where p.owner_id = v_owner and p.statut = 'attente_stock'
      union all
      select jsonb_build_object(
               'type', 'demande_commercial_production', 'id', d.id, 'numero', d.numero,
               'libelle', 'Demande commerciale à confirmer par la production',
               'role', 'production', 'date', d.cree_le)
        from public.dist_demandes_commercial d
       where d.owner_id = v_owner and d.statut = 'attente_production'
      union all
      select jsonb_build_object(
               'type', 'demande_commercial_stock', 'id', d.id, 'numero', d.numero,
               'libelle', 'Demande commerciale à autoriser par le stock',
               'role', 'stock', 'date', d.production_le)
        from public.dist_demandes_commercial d
       where d.owner_id = v_owner and d.statut = 'attente_stock'
      union all
      select jsonb_build_object(
               'type', 'demande_commercial_reception', 'id', d.id, 'numero', d.numero,
               'libelle', 'Marchandises attribuées : le commercial confirme',
               'role', 'commercial', 'date', d.stock_le)
        from public.dist_demandes_commercial d
       where d.owner_id = v_owner and d.statut = 'attente_commercial'
      union all
      select jsonb_build_object(
               'type', 'retour_reception', 'id', r.id, 'numero', r.numero,
               'libelle', 'Retour de marchandises à compter par le stock',
               'role', 'stock', 'date', r.cree_le)
        from public.dist_retours r
       where r.owner_id = v_owner and r.statut = 'attente_stock'
      union all
      select jsonb_build_object(
               'type', 'remise_comptable', 'id', r.id, 'numero', r.numero,
               'libelle', 'Remise d''argent à recevoir par le comptable',
               'role', 'comptable', 'date', r.declare_le)
        from public.dist_remises r
       where r.owner_id = v_owner and r.statut = 'declaree'
      union all
      select jsonb_build_object(
               'type', 'remise_gerant', 'id', r.id, 'numero', r.numero,
               'libelle', 'Remise reçue par le comptable : validation du gérant',
               'role', 'gerant', 'date', r.recu_le)
        from public.dist_remises r
       where r.owner_id = v_owner and r.statut in ('recue', 'litige')
      union all
      select jsonb_build_object(
               'type', 'depense_validation', 'id', d.id, 'numero', d.numero,
               'libelle', 'Dépense à autoriser par le gérant',
               'role', 'gerant', 'date', d.cree_le)
        from public.dist_depenses d
       where d.owner_id = v_owner and d.statut = 'en_attente'
      union all
      select jsonb_build_object(
               'type', 'anomalie', 'id', a.id, 'numero', null,
               'libelle', a.description,
               'role', 'gerant', 'date', a.cree_le)
        from public.dist_anomalies a
       where a.owner_id = v_owner and a.statut = 'ouverte'
    ) s
   where v_role in ('proprietaire', 'gerant')
      or (s.x->>'role') = v_role;

  return v_items;
end;
$$;

create or replace function public.dist_anomalies_lister()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_owner uuid := public.dist_owner_requis();
  v_items jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', a.id, 'type', a.type, 'description', a.description,
           'quantite', a.quantite, 'montant', a.montant,
           'statut', a.statut, 'cree_le', a.cree_le,
           'decision', a.decision, 'motif', a.motif
         ) order by a.cree_le desc), '[]'::jsonb)
    into v_items
    from public.dist_anomalies a
   where a.owner_id = v_owner
     and public.dist_role() in ('proprietaire', 'gerant');

  return jsonb_build_object('ok', true, 'items', v_items);
end;
$$;

create or replace function public.dist_anomalie_resoudre(
  p_anomalie uuid,
  p_decision text,
  p_motif    text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid := public.dist_owner_requis();
begin
  perform public.dist_exige(array['gerant', 'proprietaire']);

  if nullif(btrim(coalesce(p_decision, '')), '') is null then
    raise exception 'DECISION_REQUISE|Indiquez la décision prise.';
  end if;

  update public.dist_anomalies
     set statut = 'resolue', decision = btrim(p_decision),
         motif = nullif(btrim(coalesce(p_motif, '')), ''),
         resolu_par = auth.uid(), resolu_le = now()
   where id = p_anomalie and owner_id = v_owner;

  if not found then
    raise exception 'ANOMALIE_INTROUVABLE|Cette anomalie n''existe pas.';
  end if;

  perform public.dist_journaliser(v_owner, 'ANOMALIE_RESOLUE', 'dist_anomalies',
    p_anomalie, jsonb_build_object('decision', p_decision));
  return jsonb_build_object('ok', true);
end;
$$;

create or replace function public.dist_parametres_definir(
  p_devise                 text default null,
  p_solde_initial          numeric default null,
  p_autoriser_solde_negatif boolean default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid := public.dist_owner_requis();
  v_actuel numeric;
begin
  perform public.dist_exige(array['proprietaire']);

  -- Le solde d'ouverture ne se réécrit pas une fois la caisse mouvementée :
  -- sinon on pourrait « corriger » l'histoire sans mouvement. Un apport
  -- (`dist_caisse_apport`) reste la seule façon d'ajouter de l'argent.
  select coalesce(solde_initial, 0) into v_actuel
    from public.dist_parametres where owner_id = v_owner;
  v_actuel := coalesce(v_actuel, 0);

  if p_solde_initial is not null
     and abs(p_solde_initial - v_actuel) > 0.009
     and exists (select 1 from public.dist_caisse where owner_id = v_owner)
  then
    raise exception 'SOLDE_INITIAL_VERROUILLE|La caisse a déjà des mouvements : utilisez un apport pour ajouter de l''argent.';
  end if;

  insert into public.dist_parametres (owner_id, devise, solde_initial, autoriser_solde_negatif)
  values (v_owner, coalesce(nullif(upper(btrim(p_devise)), ''), 'CDF'),
          coalesce(p_solde_initial, 0), coalesce(p_autoriser_solde_negatif, false))
  on conflict (owner_id) do update
     set devise = coalesce(nullif(upper(btrim(p_devise)), ''), public.dist_parametres.devise),
         solde_initial = coalesce(p_solde_initial, public.dist_parametres.solde_initial),
         autoriser_solde_negatif = coalesce(p_autoriser_solde_negatif,
                                            public.dist_parametres.autoriser_solde_negatif),
         updated_at = now();

  perform public.dist_journaliser(v_owner, 'PARAMETRES_DISTRIBUTION', 'dist_parametres', null,
    jsonb_build_object('devise', p_devise, 'solde_initial', p_solde_initial));
  return jsonb_build_object('ok', true);
end;
$$;


create or replace function public.dist_mouvements_lister(
  p_intrant_id uuid default null,
  p_produit_id uuid default null,
  p_limit      integer default 150
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_owner uuid := public.dist_owner_requis();
  v_items jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', m.id, 'nature', m.nature, 'quantite', m.quantite,
           'stock_avant', m.stock_avant, 'stock_apres', m.stock_apres,
           'motif', m.motif, 'date', m.created_at,
           'intrant', coalesce(i.nom, ''),
           'produit', coalesce(p.nom, ''),
           'commercial', coalesce(u.nom, '')
         ) order by m.created_at desc), '[]'::jsonb)
    into v_items
    from (
      select * from public.dist_mouvements
       where owner_id = v_owner
         and (p_intrant_id is null or intrant_id = p_intrant_id)
         and (p_produit_id is null or produit_id = p_produit_id)
       order by created_at desc
       limit greatest(coalesce(p_limit, 150), 1)
    ) m
    left join public.dist_intrants i on i.id = m.intrant_id
    left join public.dist_produits p on p.id = m.produit_id
    left join public.utilisateurs u on u.id = m.commercial_id;

  return jsonb_build_object('ok', true, 'items', v_items);
end;
$$;

create or replace function public.dist_facture(p_vente uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  return public.dist_facture_json(p_vente);
end;
$$;

create or replace function public.dist_anomalies_ouvertes()
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select count(*)::integer
    from public.dist_anomalies a
   where a.owner_id = public.dist_owner_requis()
     and a.statut = 'ouverte';
$$;


-- ============================================================================
--  16. SÉCURITÉ : LECTURE SEULE POUR LES MEMBRES, ÉCRITURE PAR RPC
-- ============================================================================

do $$
declare
  t text;
  tables text[] := array[
    'dist_parametres', 'dist_intrants', 'dist_produits',
    'dist_stock_commercial', 'dist_mouvements', 'dist_receptions',
    'dist_reception_lignes', 'dist_demandes_intrants',
    'dist_demande_intrants_lignes', 'dist_productions',
    'dist_production_intrants', 'dist_production_sorties',
    'dist_demandes_commercial', 'dist_demande_commercial_lignes',
    'dist_clients', 'dist_ventes', 'dist_vente_lignes', 'dist_retours',
    'dist_retour_lignes', 'dist_remises', 'dist_caisse', 'dist_depenses',
    'dist_anomalies', 'dist_journal', 'dist_compteurs'
  ];
begin
  foreach t in array tables loop
    execute format('alter table public.%I enable row level security', t);

    -- Toutes les anciennes policies du module sont retirées : la seule
    -- policy est recréée juste après.
    execute format(
      'do $inner$ declare r record; begin
         for r in select policyname from pg_policies
                   where schemaname = ''public'' and tablename = %L
         loop
           execute format(''drop policy if exists %%I on public.%%I'', r.policyname, %L);
         end loop;
       end $inner$', t, t);
  end loop;
end $$;

-- Lecture générique : uniquement les tables qui portent DIRECTEMENT
-- `owner_id`. Les tables filles (lignes) ont leur propre policy plus bas,
-- basée sur leur table parente : elles n'ont pas de colonne `owner_id`.
do $$
declare
  t text;
  tables text[] := array[
    'dist_parametres', 'dist_intrants', 'dist_produits',
    'dist_stock_commercial', 'dist_mouvements', 'dist_receptions',
    'dist_demandes_intrants', 'dist_productions',
    'dist_demandes_commercial', 'dist_depenses',
    'dist_anomalies', 'dist_journal', 'dist_compteurs'
  ];
begin
  foreach t in array tables loop
    execute format(
      'create policy %I on public.%I for select to authenticated using (public.dist_est_membre(owner_id))',
      'dist_read_' || t, t);
  end loop;
end $$;

-- Tables filles : lecture par le propriétaire de la LIGNE PARENTE.
create policy dist_read_dist_reception_lignes on public.dist_reception_lignes
  for select to authenticated
  using (exists (
    select 1 from public.dist_receptions r
     where r.id = reception_id and public.dist_est_membre(r.owner_id)
  ));

create policy dist_read_dist_demande_intrants_lignes
  on public.dist_demande_intrants_lignes
  for select to authenticated
  using (exists (
    select 1 from public.dist_demandes_intrants d
     where d.id = demande_id and public.dist_est_membre(d.owner_id)
  ));

create policy dist_read_dist_production_intrants
  on public.dist_production_intrants
  for select to authenticated
  using (exists (
    select 1 from public.dist_productions p
     where p.id = production_id and public.dist_est_membre(p.owner_id)
  ));

create policy dist_read_dist_production_sorties
  on public.dist_production_sorties
  for select to authenticated
  using (exists (
    select 1 from public.dist_productions p
     where p.id = production_id and public.dist_est_membre(p.owner_id)
  ));

create policy dist_read_dist_demande_commercial_lignes
  on public.dist_demande_commercial_lignes
  for select to authenticated
  using (exists (
    select 1 from public.dist_demandes_commercial d
     where d.id = demande_id and public.dist_est_membre(d.owner_id)
  ));

-- Lignes de vente : même règle que la vente (le commercial ne voit que les siennes).
create policy dist_read_dist_vente_lignes on public.dist_vente_lignes
  for select to authenticated
  using (exists (
    select 1 from public.dist_ventes v
     where v.id = vente_id
       and public.dist_est_membre(v.owner_id)
       and (
         public.dist_role() in ('proprietaire', 'gerant', 'comptable')
         or v.commercial_id = auth.uid()
       )
  ));

-- Lignes de retour : direction, stock, ou le commercial concerné.
create policy dist_read_dist_retour_lignes on public.dist_retour_lignes
  for select to authenticated
  using (exists (
    select 1 from public.dist_retours r
     where r.id = retour_id
       and public.dist_est_membre(r.owner_id)
       and (
         public.dist_role() in ('proprietaire', 'gerant', 'stock')
         or r.commercial_id = auth.uid()
       )
  ));

-- Clients : le commercial ne voit QUE les siens ; la direction voit tout.
create policy dist_read_dist_clients on public.dist_clients
  for select to authenticated
  using (
    public.dist_est_membre(owner_id)
    and (
      public.dist_role() in ('proprietaire', 'gerant')
      or commercial_id = auth.uid()
    )
  );

create policy dist_read_dist_ventes on public.dist_ventes
  for select to authenticated
  using (
    public.dist_est_membre(owner_id)
    and (
      public.dist_role() in ('proprietaire', 'gerant', 'comptable')
      or commercial_id = auth.uid()
    )
  );

create policy dist_read_dist_remises on public.dist_remises
  for select to authenticated
  using (
    public.dist_est_membre(owner_id)
    and (
      public.dist_role() in ('proprietaire', 'gerant', 'comptable')
      or commercial_id = auth.uid()
    )
  );

create policy dist_read_dist_retours on public.dist_retours
  for select to authenticated
  using (
    public.dist_est_membre(owner_id)
    and (
      public.dist_role() in ('proprietaire', 'gerant', 'stock')
      or commercial_id = auth.uid()
    )
  );

create policy dist_read_dist_caisse on public.dist_caisse
  for select to authenticated
  using (
    public.dist_est_membre(owner_id)
    and public.dist_role() in ('proprietaire', 'gerant', 'comptable')
  );

-- Les RPC sont exécutables par tout compte authentifié : chacune vérifie
-- elle-même le rôle distribution (dist_exige) AVANT d'écrire.
do $$
declare
  f record;
  -- Fonctions INTERNES : elles ne doivent JAMAIS être appelables par un
  -- client. Les exposer permettrait de modifier un stock sans passer par
  -- une demande, ou de calculer un solde hors workflow.
  --
  -- ⚠️ `dist_role` et `dist_est_membre` sont VOLONTAIREMENT absentes de
  -- cette liste : PostgreSQL évalue les policies RLS avec les privilèges de
  -- l'utilisateur courant, qui doit donc pouvoir les exécuter pour LIRE les
  -- tables. Elles ne font que renvoyer le rôle de l'appelant et son
  -- appartenance à une entreprise : aucun secret n'est exposé.
  internes text[] := array[
    'dist_owner_requis', 'dist_exige',
    'dist_journaliser', 'dist_numero', 'dist_caisse_solde',
    'dist_solde_commercial', 'dist_bouger_intrant', 'dist_bouger_produit',
    'dist_bouger_commercial', 'dist_anomalie', 'dist_facture_json'
  ];
begin
  for f in
    select p.oid::regprocedure as signature, p.proname as nom
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname like 'dist\_%' escape '\'
  loop
    if f.nom = any (internes) then
      execute format('revoke all on function %s from public, anon, authenticated', f.signature);
    else
      execute format('revoke all on function %s from public, anon', f.signature);
      execute format('grant execute on function %s to authenticated', f.signature);
    end if;
  end loop;
end $$;


-- ============================================================================
--  17. CONTRÔLE
-- ============================================================================
select
  (select count(*) from information_schema.tables
    where table_schema = 'public' and table_name like 'dist\_%' escape '\') as tables_distribution,
  (select count(*) from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname like 'dist\_%' escape '\') as fonctions_distribution,
  (select count(*) from information_schema.columns
    where table_schema = 'public' and table_name = 'utilisateurs'
      and column_name in ('role_distribution', 'dist_actif')) as colonnes_role;

-- ============================================================================
--  FIN — MODULE 24
-- ============================================================================
