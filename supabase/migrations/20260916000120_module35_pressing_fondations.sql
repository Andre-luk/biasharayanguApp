-- ============================================================================
--  biashara_yangu — MODULE 35 : PRESSING & BLANCHISSERIE
--  ÉTAPE 1/4 — LES FONDATIONS
--  ---------------------------------------------------------------------------
--  CE QUE CE SCRIPT INSTALLE
--    1. L'ACTIVITÉ « pressing » dans le référentiel type → modules
--       (`types_espaces_modules`), avec ses trois modules métier :
--         • press_depots    → dépôts, commandes, vêtements confiés
--         • press_atelier   → production, étapes, contrôle qualité
--         • press_retraits  → scan QRCode et remise des vêtements
--       + les modules communs réellement utiles (clients, caisse, finance,
--         employés, rapports, assistant IA).
--       ⚠️ NI `ventes`, NI `produits`, NI `stock` : un pressing ne vend pas
--          des marchandises, il garde des biens appartenant à ses clients.
--
--    2. Trois PAGES de permission nouvelles (`pressing_depots`,
--       `pressing_atelier`, `pressing_retraits`) et leur place dans la
--       matrice des rôles existante (propriétaire, vendeur, magasinier,
--       comptable).
--
--    3. LES TABLES DE PARAMÉTRAGE ET DE CATALOGUE du pressing :
--         • pressing_config      → délai, politique de remise, notifications…
--         • pressing_categories  → types de vêtements (chemise, costume…)
--         • pressing_prestations → lavage, repassage, détachage…
--         • pressing_tarifs      → prix par prestation ET par type de vêtement
--         • pressing_clients     → fiches clients du pressing
--
--    4. Les RPC de lecture/écriture de tout cela, avec contrôle de droits
--       ET isolation par entreprise (aucun pressing ne voit les tarifs d'un
--       autre).
--
--  ⚠️ CE SCRIPT NE TOUCHE À AUCUNE TABLE EXISTANTE (sauf des fonctions de
--     permissions ré-émises à l'identique + les 3 nouvelles pages).
--     Il est IDEMPOTENT : on peut le rejouer sans risque.
--
--  📌 OÙ L'EXÉCUTER : éditeur SQL de Supabase (pas de CLI sur la machine).
--     Les vérifications finales s'affichent en bas du script.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);


-- ============================================================================
--  1. LE CATALOGUE DES MODULES — 3 modules métier de plus
-- ============================================================================

create or replace function public.modules_catalogue()
returns text[]
language sql
immutable
as $$
  select array[
    -- Modules généraux (déjà codés dans l'application).
    'ventes', 'produits', 'stock', 'qr', 'caisse', 'clients', 'finance',
    'employes', 'rapports', 'assistant_ia',
    -- Modules métier.
    'chambres', 'reservations', 'checkin', 'tables', 'commandes', 'cuisine',
    'salles', 'evenements', 'lots_expiration', 'production', 'pesee',
    'variantes',
    -- 🧺 MODULE 35 — pressing & blanchisserie.
    'press_depots', 'press_atelier', 'press_retraits',
    -- 🚚 Distribution.
    'distribution'
  ]::text[];
$$;

comment on function public.modules_catalogue() is
  'Module 16 — Catalogue des modules connus (validation des profils). Miroir de ModuleActivite.catalogue (Dart). + Module 35 (pressing).';

revoke all on function public.modules_catalogue() from public, anon;
grant execute on function public.modules_catalogue() to authenticated;


-- ============================================================================
--  2. LE PROFIL DE L'ACTIVITÉ « pressing »
-- ============================================================================
--    On insère UNIQUEMENT s'il n'existe pas : un profil personnalisé par
--    l'administrateur de la plateforme n'est jamais écrasé.

insert into public.types_espaces_modules (type, libelle, modules)
values (
  'pressing',
  'Pressing & Blanchisserie',
  '["clients","caisse","finance","employes","rapports","assistant_ia",
    "press_depots","press_atelier","press_retraits"]'::jsonb
)
on conflict (type) do nothing;

-- Si le profil existait déjà sans les modules métier (créé à la main), on
-- ajoute les trois modules du pressing sans rien retirer d'autre.
do $$
declare
  v_modules jsonb;
begin
  select modules into v_modules
    from public.types_espaces_modules where type = 'pressing';

  if v_modules is null then
    return;
  end if;

  if not (v_modules ? 'press_depots') then
    v_modules := v_modules || '["press_depots"]'::jsonb;
  end if;
  if not (v_modules ? 'press_atelier') then
    v_modules := v_modules || '["press_atelier"]'::jsonb;
  end if;
  if not (v_modules ? 'press_retraits') then
    v_modules := v_modules || '["press_retraits"]'::jsonb;
  end if;

  update public.types_espaces_modules
     set modules = v_modules,
         updated_at = now()
   where type = 'pressing'
     and modules is distinct from v_modules;
end $$;


-- ============================================================================
--  3. PAGES DE PERMISSION — 3 pages métier
-- ============================================================================
--    Ré-émission complète (la fonction est immuable et remplacée d'un bloc).

create or replace function public.pages_permissions()
returns text[]
language sql
immutable
as $$
  select array[
    'dashboard', 'entreprises', 'utilisateurs', 'villes', 'activites',
    'groupes_tarifaires', 'abonnements', 'paiements', 'finance', 'audit',
    'securite', 'notifications', 'assistance', 'parametres', 'ventes',
    'caisse', 'scanner', 'panier', 'articles', 'stock', 'clients',
    'fournisseurs', 'depenses', 'collaborateurs', 'qr_codes', 'rapports',
    'assistant_ia',
    -- 🏨 MODULE 16 C2 — hôtel.
    'chambres', 'reservations', 'reception',
    -- 🍽️ MODULE 16 C3 — restaurant.
    'tables', 'commandes', 'cuisine',
    -- 🎉 MODULE 16 C4 — salle des fêtes.
    'salles', 'evenements',
    -- 🥖 MODULE 16 C5 — boulangerie.
    'production',
    -- 🛒 MODULE 19 — marketplace local géolocalisé.
    'publications', 'visibilite', 'publicites',
    -- 🛡️ MODULE 20 — administration plateforme.
    'boutiques', 'moderation',
    -- 🧺 MODULE 35 — pressing & blanchisserie.
    'pressing_depots', 'pressing_atelier', 'pressing_retraits'
  ];
$$;

comment on function public.pages_permissions() is
  'Liste officielle des pages de permission (Module 4 → Module 35 : + pressing).';


create or replace function public.permissions_defaut(p_role text)
returns jsonb
language plpgsql
immutable
as $$
declare
  v_role    text := upper(btrim(coalesce(p_role, '')));
  v_pages   text[];
  v_actions text[];
  v_result  jsonb := '{}'::jsonb;
  v_page    text;
begin
  if v_role = 'SUPER_ADMIN' then
    select jsonb_object_agg(p, to_jsonb(public.actions_permissions()))
      into v_result
      from unnest(public.pages_permissions()) as p;
    return coalesce(v_result, '{}'::jsonb);
  end if;

  case v_role
    when 'GESTIONNAIRE_COMPTES' then
      v_pages   := array['entreprises', 'utilisateurs', 'villes', 'activites',
                         'groupes_tarifaires', 'abonnements', 'assistance',
                         'notifications',
                         'boutiques', 'moderation'];
      v_actions := array['voir', 'creer', 'modifier'];

    when 'FINANCE_LAPERLE' then
      v_pages   := array['dashboard', 'abonnements', 'paiements', 'finance',
                         'rapports', 'audit', 'notifications'];
      v_actions := array['voir', 'creer', 'valider'];

    when 'SUPPORT' then
      v_pages   := array['dashboard', 'assistance', 'entreprises', 'utilisateurs',
                         'abonnements', 'notifications',
                         'boutiques'];
      v_actions := array['voir'];

    when 'PROPRIETAIRE' then
      v_pages   := array['dashboard', 'ventes', 'caisse', 'scanner', 'panier',
                         'articles', 'qr_codes', 'stock', 'clients', 'fournisseurs',
                         'finance', 'depenses', 'collaborateurs', 'rapports',
                         'abonnements', 'audit', 'assistant_ia', 'parametres',
                         'chambres', 'reservations', 'reception',
                         'tables', 'commandes', 'cuisine',
                         'salles', 'evenements',
                         'production',
                         'publications', 'visibilite', 'publicites',
                         -- 🧺 MODULE 35 — le propriétaire a tout le pressing.
                         'pressing_depots', 'pressing_atelier', 'pressing_retraits'];
      v_actions := public.actions_permissions();

    when 'VENDEUR' then
      v_pages   := array['ventes', 'caisse', 'scanner', 'panier', 'assistant_ia',
                         'chambres', 'reservations', 'reception',
                         'tables', 'commandes', 'cuisine',
                         'salles', 'evenements',
                         'production',
                         -- 🧺 Accueil et remise : le cœur du travail d'agent.
                         'pressing_depots', 'pressing_retraits'];
      v_actions := array['voir', 'creer'];

    when 'MAGASINIER' then
      v_pages   := array['stock', 'articles', 'qr_codes', 'rapports',
                         'assistant_ia', 'production',
                         -- 🧺 L'atelier : traitement et contrôle qualité.
                         'pressing_atelier'];
      v_actions := array['voir'];

    when 'COMPTABLE_ENTREPRISE' then
      v_pages   := array['dashboard', 'ventes', 'caisse', 'depenses', 'rapports',
                         'finance', 'assistant_ia', 'parametres',
                         -- 🧺 Le comptable consulte les dépôts (donc les
                         -- soldes dus) sans pouvoir les modifier.
                         'pressing_depots'];
      v_actions := array['voir'];

    else
      return '{}'::jsonb;
  end case;

  foreach v_page in array v_pages loop
    v_result := jsonb_set(v_result, array[v_page], to_jsonb(v_actions), true);
  end loop;

  -- Exceptions par page.
  v_result := case v_role
    when 'SUPPORT' then v_result
      || jsonb_build_object('assistance',    to_jsonb(array['voir', 'modifier']))
      || jsonb_build_object('notifications', to_jsonb(array['voir', 'modifier']))
    when 'MAGASINIER' then v_result
      || jsonb_build_object('stock',        to_jsonb(array['voir', 'creer', 'modifier']))
      || jsonb_build_object('qr_codes',     to_jsonb(array['voir', 'creer']))
      || jsonb_build_object('assistant_ia', to_jsonb(array['voir', 'creer']))
      || jsonb_build_object('production',   to_jsonb(array['voir', 'creer', 'modifier']))
      || jsonb_build_object('pressing_atelier',
                            to_jsonb(array['voir', 'creer', 'modifier']))
    when 'COMPTABLE_ENTREPRISE' then v_result
      || jsonb_build_object('depenses',     to_jsonb(array['voir', 'creer', 'valider']))
      || jsonb_build_object('rapports',     to_jsonb(array['voir', 'valider']))
      || jsonb_build_object('assistant_ia', to_jsonb(array['voir', 'creer']))
    when 'VENDEUR' then v_result
      || jsonb_build_object('chambres', to_jsonb(array['voir']))
      || jsonb_build_object('tables',   to_jsonb(array['voir']))
      || jsonb_build_object('salles',   to_jsonb(array['voir']))
      || jsonb_build_object('pressing_depots',
                            to_jsonb(array['voir', 'creer', 'modifier']))
      || jsonb_build_object('pressing_retraits',
                            to_jsonb(array['voir', 'creer', 'valider']))
    else v_result
  end;

  return v_result;
end;
$$;

comment on function public.permissions_defaut(text) is
  'Matrice des permissions par défaut (Module 4 → Module 35 : + pressing).';


-- ============================================================================
--  4. L'ENTREPRISE COURANTE (raccourci interne au module)
-- ============================================================================
--    Toutes les tables du pressing portent `entreprise_id`. Cette fonction
--    évite de recopier le `coalesce` partout et garantit qu'on ne peut
--    écrire que pour SA propre entreprise.

create or replace function public.pressing_entreprise()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    public.mon_entreprise_id(),
    public.mon_proprietaire(),
    auth.uid()
  );
$$;

comment on function public.pressing_entreprise() is
  'Module 35 — entreprise (propriétaire) de la session, utilisée par toutes les tables du pressing.';

revoke all on function public.pressing_entreprise() from public, anon;
grant execute on function public.pressing_entreprise() to authenticated;


-- ============================================================================
--  5. LES TABLES DU PRESSING
-- ============================================================================

-- 5.1 Réglages du pressing (une ligne par entreprise).
create table if not exists public.pressing_config (
  id                     uuid primary key default gen_random_uuid(),
  entreprise_id          uuid not null unique,
  devise                 text not null default 'CDF',
  -- Délai proposé par défaut lors d'un dépôt.
  delai_standard_jours   integer not null default 3,
  -- Supplément appliqué aux prestations « express » (montant, pas un %).
  supplement_urgence     numeric(12, 2) not null default 0,
  -- Politique de remise : solde exigé, ou remise possible avec dette.
  politique_remise       text not null default 'SOLDE_OBLIGATOIRE',
  collecte_active        boolean not null default false,
  frais_collecte         numeric(12, 2) not null default 0,
  fidelite_active        boolean not null default false,
  fidelite_seuil         numeric(14, 2) not null default 0,
  fidelite_remise_pct    numeric(5, 2) not null default 0,
  notify_depot           boolean not null default true,
  notify_pret            boolean not null default true,
  notify_retard          boolean not null default true,
  notify_paiement        boolean not null default true,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now()
);

do $$
begin
  alter table public.pressing_config
    add constraint chk_pressing_politique
    check (politique_remise in ('SOLDE_OBLIGATOIRE', 'REMISE_POSSIBLE'));
exception when duplicate_object then null;
end $$;

comment on table public.pressing_config is
  'Module 35 — réglages d''un pressing (délai, politique de remise, notifications, fidélité).';


-- 5.2 Types de vêtements (catalogue 100 % propre à chaque pressing).
create table if not exists public.pressing_categories (
  id            uuid primary key default gen_random_uuid(),
  entreprise_id uuid not null,
  nom           text not null,
  ordre         integer not null default 100,
  actif         boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create unique index if not exists idx_pressing_categories_nom
  on public.pressing_categories (entreprise_id, lower(btrim(nom)));

comment on table public.pressing_categories is
  'Module 35 — types de vêtements d''un pressing (chemise, pantalon, costume, couverture…). Chaque établissement a son propre catalogue.';


-- 5.3 Prestations (lavage, repassage, détachage…).
create table if not exists public.pressing_prestations (
  id                 uuid primary key default gen_random_uuid(),
  entreprise_id      uuid not null,
  nom                text not null,
  description        text,
  -- Durée de travail estimée (information atelier).
  duree_heures       integer not null default 24,
  -- Délai promis au client, en jours.
  delai_jours        integer not null default 3,
  -- Supplément d'urgence propre à la prestation (s'ajoute au réglage global).
  supplement_urgence numeric(12, 2) not null default 0,
  actif              boolean not null default true,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

create unique index if not exists idx_pressing_prestations_nom
  on public.pressing_prestations (entreprise_id, lower(btrim(nom)));

comment on table public.pressing_prestations is
  'Module 35 — prestations facturables d''un pressing (lavage simple, lavage + repassage, nettoyage à sec, détachage, express…).';


-- 5.4 Tarifs : un prix par (prestation, type de vêtement).
--     `categorie_id` NULL = prix par défaut de la prestation (tous vêtements).
create table if not exists public.pressing_tarifs (
  id            uuid primary key default gen_random_uuid(),
  entreprise_id uuid not null,
  prestation_id uuid not null
    references public.pressing_prestations (id) on delete cascade,
  categorie_id  uuid
    references public.pressing_categories (id) on delete cascade,
  prix          numeric(12, 2) not null check (prix >= 0),
  actif         boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

-- Un seul tarif par couple (prestation, type de vêtement) — y compris le
-- tarif « par défaut » où `categorie_id` est NULL.
create unique index if not exists idx_pressing_tarifs_unique
  on public.pressing_tarifs (
    entreprise_id,
    prestation_id,
    coalesce(categorie_id, '00000000-0000-0000-0000-000000000000'::uuid)
  );

comment on table public.pressing_tarifs is
  'Module 35 — grille tarifaire : prix d''une prestation pour un type de vêtement (categorie_id NULL = tarif par défaut).';


-- 5.5 Clients du pressing.
--     ⚠️ Table SÉPARÉE de `public.clients` (boutiques) : un client de
--        pressing a des vêtements en garde, pas des achats. Les deux mondes
--        ne doivent jamais se mélanger dans les listes.
create table if not exists public.pressing_clients (
  id                uuid primary key default gen_random_uuid(),
  entreprise_id     uuid not null,
  nom               text not null,
  telephone         text,
  -- Téléphone normalisé (chiffres seulement) pour la recherche et
  -- l'anti-doublon.
  telephone_norm    text,
  adresse           text,
  email             text,
  notes             text,
  cree_par          uuid,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  derniere_activite timestamptz
);

create unique index if not exists idx_pressing_clients_tel
  on public.pressing_clients (entreprise_id, telephone_norm)
  where telephone_norm is not null and telephone_norm <> '';

create index if not exists idx_pressing_clients_nom
  on public.pressing_clients (entreprise_id, lower(btrim(nom)));

comment on table public.pressing_clients is
  'Module 35 — clients d''un pressing (nom, téléphone, adresse, historique lisible via les commandes).';


-- ============================================================================
--  6. SÉCURITÉ (RLS) — chaque entreprise ne voit QUE ses données
-- ============================================================================

alter table public.pressing_config     enable row level security;
alter table public.pressing_categories enable row level security;
alter table public.pressing_prestations enable row level security;
alter table public.pressing_tarifs     enable row level security;
alter table public.pressing_clients    enable row level security;

-- Fonction de lecture commune : l'entreprise propriétaire OU la plateforme.
-- (Les écritures passent par les RPC, qui revérifient tout.)

drop policy if exists pressing_config_lecture on public.pressing_config;
create policy pressing_config_lecture on public.pressing_config
  for select to authenticated
  using (
    entreprise_id = public.pressing_entreprise()
    or public.est_plateforme()
  );

drop policy if exists pressing_categories_lecture on public.pressing_categories;
create policy pressing_categories_lecture on public.pressing_categories
  for select to authenticated
  using (
    entreprise_id = public.pressing_entreprise()
    or public.est_plateforme()
  );

drop policy if exists pressing_prestations_lecture on public.pressing_prestations;
create policy pressing_prestations_lecture on public.pressing_prestations
  for select to authenticated
  using (
    entreprise_id = public.pressing_entreprise()
    or public.est_plateforme()
  );

drop policy if exists pressing_tarifs_lecture on public.pressing_tarifs;
create policy pressing_tarifs_lecture on public.pressing_tarifs
  for select to authenticated
  using (
    entreprise_id = public.pressing_entreprise()
    or public.est_plateforme()
  );

drop policy if exists pressing_clients_lecture on public.pressing_clients;
create policy pressing_clients_lecture on public.pressing_clients
  for select to authenticated
  using (
    entreprise_id = public.pressing_entreprise()
    or public.est_plateforme()
  );

-- Aucune écriture directe : tout passe par les RPC (contrôle des droits).
revoke insert, update, delete on public.pressing_config      from authenticated, anon;
revoke insert, update, delete on public.pressing_categories  from authenticated, anon;
revoke insert, update, delete on public.pressing_prestations from authenticated, anon;
revoke insert, update, delete on public.pressing_tarifs      from authenticated, anon;
revoke insert, update, delete on public.pressing_clients     from authenticated, anon;


-- ============================================================================
--  7. LES RPC — RÉGLAGES
-- ============================================================================

create or replace function public.pressing_config_lire()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ent uuid := public.pressing_entreprise();
  v_c   public.pressing_config%rowtype;
begin
  if auth.uid() is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;
  if v_ent is null then
    raise exception 'ENTREPRISE_INTROUVABLE|Aucune entreprise rattachée à ce compte.';
  end if;
  if not public.peut('pressing_depots', 'voir') then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas d''ouvrir le pressing.';
  end if;

  insert into public.pressing_config (entreprise_id)
  values (v_ent)
  on conflict (entreprise_id) do nothing;

  select * into v_c from public.pressing_config where entreprise_id = v_ent;

  return jsonb_build_object(
    'entreprise_id', v_c.entreprise_id,
    'devise', v_c.devise,
    'delai_standard_jours', v_c.delai_standard_jours,
    'supplement_urgence', v_c.supplement_urgence,
    'politique_remise', v_c.politique_remise,
    'collecte_active', v_c.collecte_active,
    'frais_collecte', v_c.frais_collecte,
    'fidelite_active', v_c.fidelite_active,
    'fidelite_seuil', v_c.fidelite_seuil,
    'fidelite_remise_pct', v_c.fidelite_remise_pct,
    'notify_depot', v_c.notify_depot,
    'notify_pret', v_c.notify_pret,
    'notify_retard', v_c.notify_retard,
    'notify_paiement', v_c.notify_paiement
  );
end;
$$;

comment on function public.pressing_config_lire() is
  'Module 35 — réglages du pressing de l''entreprise (créés à la demande avec les valeurs par défaut).';

revoke all on function public.pressing_config_lire() from public, anon;
grant execute on function public.pressing_config_lire() to authenticated;


create or replace function public.pressing_config_enregistrer(p_champs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ent uuid := public.pressing_entreprise();
begin
  if auth.uid() is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;
  if not (public.peut('pressing_depots', 'modifier') or public.est_plateforme()) then
    raise exception 'DROIT_REFUSE|Seul le responsable peut modifier les réglages du pressing.';
  end if;
  if p_champs is null or jsonb_typeof(p_champs) <> 'object' then
    raise exception 'DONNEES_INVALIDES|Aucun réglage transmis.';
  end if;

  if p_champs ? 'politique_remise'
     and nullif(btrim(p_champs->>'politique_remise'), '') is not null
     and p_champs->>'politique_remise' not in ('SOLDE_OBLIGATOIRE',
                                               'REMISE_POSSIBLE') then
    raise exception 'VALEUR_INVALIDE|Politique de remise inconnue.';
  end if;

  insert into public.pressing_config (entreprise_id)
  values (v_ent)
  on conflict (entreprise_id) do nothing;

  update public.pressing_config set
    devise               = coalesce(nullif(p_champs->>'devise', ''), devise),
    delai_standard_jours = coalesce(nullif(p_champs->>'delai_standard_jours', '')::integer,
                                    delai_standard_jours),
    supplement_urgence   = coalesce(nullif(p_champs->>'supplement_urgence', '')::numeric,
                                    supplement_urgence),
    politique_remise     = coalesce(nullif(p_champs->>'politique_remise', ''),
                                    politique_remise),
    collecte_active      = coalesce(nullif(p_champs->>'collecte_active', '')::boolean,
                                    collecte_active),
    frais_collecte       = coalesce(nullif(p_champs->>'frais_collecte', '')::numeric,
                                    frais_collecte),
    fidelite_active      = coalesce(nullif(p_champs->>'fidelite_active', '')::boolean,
                                    fidelite_active),
    fidelite_seuil       = coalesce(nullif(p_champs->>'fidelite_seuil', '')::numeric,
                                    fidelite_seuil),
    fidelite_remise_pct  = coalesce(nullif(p_champs->>'fidelite_remise_pct', '')::numeric,
                                    fidelite_remise_pct),
    notify_depot         = coalesce(nullif(p_champs->>'notify_depot', '')::boolean,
                                    notify_depot),
    notify_pret          = coalesce(nullif(p_champs->>'notify_pret', '')::boolean,
                                    notify_pret),
    notify_retard        = coalesce(nullif(p_champs->>'notify_retard', '')::boolean,
                                    notify_retard),
    notify_paiement      = coalesce(nullif(p_champs->>'notify_paiement', '')::boolean,
                                    notify_paiement),
    updated_at           = now()
  where entreprise_id = v_ent;

  return public.pressing_config_lire();
end;
$$;

comment on function public.pressing_config_enregistrer(jsonb) is
  'Module 35 — enregistre les réglages du pressing (les champs absents restent inchangés).';

revoke all on function public.pressing_config_enregistrer(jsonb) from public, anon;
grant execute on function public.pressing_config_enregistrer(jsonb) to authenticated;


-- ============================================================================
--  8. LES RPC — CATALOGUE (types de vêtements, prestations, tarifs)
-- ============================================================================

create or replace function public.pressing_catalogue_lister()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_ent   uuid := public.pressing_entreprise();
  v_cat   jsonb;
  v_pres  jsonb;
  v_tar   jsonb;
begin
  if auth.uid() is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', c.id,
           'nom', c.nom,
           'ordre', c.ordre,
           'actif', c.actif
         ) order by c.ordre, c.nom), '[]'::jsonb)
    into v_cat
    from public.pressing_categories c
   where c.entreprise_id = v_ent;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', p.id,
           'nom', p.nom,
           'description', p.description,
           'duree_heures', p.duree_heures,
           'delai_jours', p.delai_jours,
           'supplement_urgence', p.supplement_urgence,
           'actif', p.actif
         ) order by p.nom), '[]'::jsonb)
    into v_pres
    from public.pressing_prestations p
   where p.entreprise_id = v_ent;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', t.id,
           'prestation_id', t.prestation_id,
           'categorie_id', t.categorie_id,
           'prix', t.prix,
           'actif', t.actif
         )), '[]'::jsonb)
    into v_tar
    from public.pressing_tarifs t
   where t.entreprise_id = v_ent;

  return jsonb_build_object(
    'categories', v_cat,
    'prestations', v_pres,
    'tarifs', v_tar
  );
end;
$$;

comment on function public.pressing_catalogue_lister() is
  'Module 35 — catalogue complet du pressing : types de vêtements, prestations et grille tarifaire.';

revoke all on function public.pressing_catalogue_lister() from public, anon;
grant execute on function public.pressing_catalogue_lister() to authenticated;


create or replace function public.pressing_categorie_enregistrer(
  p_id    uuid,
  p_nom   text,
  p_ordre integer default 100,
  p_actif boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ent uuid := public.pressing_entreprise();
  v_id  uuid;
begin
  if auth.uid() is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;
  if not (public.peut('pressing_depots', 'modifier') or public.est_plateforme()) then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de modifier le catalogue.';
  end if;
  if btrim(coalesce(p_nom, '')) = '' then
    raise exception 'NOM_VIDE|Indiquez le nom du type de vêtement.';
  end if;

  if p_id is null then
    insert into public.pressing_categories (entreprise_id, nom, ordre, actif)
    values (v_ent, btrim(p_nom), coalesce(p_ordre, 100), coalesce(p_actif, true))
    returning id into v_id;
  else
    update public.pressing_categories
       set nom = btrim(p_nom),
           ordre = coalesce(p_ordre, ordre),
           actif = coalesce(p_actif, actif),
           updated_at = now()
     where id = p_id and entreprise_id = v_ent
     returning id into v_id;

    if v_id is null then
      raise exception 'INTROUVABLE|Ce type de vêtement n''existe pas.';
    end if;
  end if;

  return jsonb_build_object('ok', true, 'id', v_id);
exception
  when unique_violation then
    raise exception 'DOUBLON|Ce type de vêtement existe déjà.';
end;
$$;

comment on function public.pressing_categorie_enregistrer(uuid, text, integer, boolean) is
  'Module 35 — crée ou modifie un type de vêtement du catalogue.';

revoke all on function public.pressing_categorie_enregistrer(uuid, text, integer, boolean)
  from public, anon;
grant execute on function public.pressing_categorie_enregistrer(uuid, text, integer, boolean)
  to authenticated;


create or replace function public.pressing_prestation_enregistrer(
  p_id                 uuid,
  p_nom                text,
  p_description        text default null,
  p_duree_heures       integer default 24,
  p_delai_jours        integer default 3,
  p_supplement_urgence numeric default 0,
  p_actif              boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ent uuid := public.pressing_entreprise();
  v_id  uuid;
begin
  if auth.uid() is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;
  if not (public.peut('pressing_depots', 'modifier') or public.est_plateforme()) then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de modifier le catalogue.';
  end if;
  if btrim(coalesce(p_nom, '')) = '' then
    raise exception 'NOM_VIDE|Indiquez le nom de la prestation.';
  end if;
  if coalesce(p_supplement_urgence, 0) < 0 then
    raise exception 'MONTANT_INVALIDE|Le supplément ne peut pas être négatif.';
  end if;

  if p_id is null then
    insert into public.pressing_prestations (
      entreprise_id, nom, description, duree_heures, delai_jours,
      supplement_urgence, actif
    ) values (
      v_ent, btrim(p_nom), nullif(btrim(coalesce(p_description, '')), ''),
      greatest(coalesce(p_duree_heures, 24), 0),
      greatest(coalesce(p_delai_jours, 3), 0),
      coalesce(p_supplement_urgence, 0),
      coalesce(p_actif, true)
    )
    returning id into v_id;
  else
    update public.pressing_prestations
       set nom = btrim(p_nom),
           description = nullif(btrim(coalesce(p_description, '')), ''),
           duree_heures = coalesce(p_duree_heures, duree_heures),
           delai_jours = coalesce(p_delai_jours, delai_jours),
           supplement_urgence = coalesce(p_supplement_urgence, supplement_urgence),
           actif = coalesce(p_actif, actif),
           updated_at = now()
     where id = p_id and entreprise_id = v_ent
     returning id into v_id;

    if v_id is null then
      raise exception 'INTROUVABLE|Cette prestation n''existe pas.';
    end if;
  end if;

  return jsonb_build_object('ok', true, 'id', v_id);
exception
  when unique_violation then
    raise exception 'DOUBLON|Cette prestation existe déjà.';
end;
$$;

comment on function public.pressing_prestation_enregistrer(uuid, text, text, integer, integer, numeric, boolean) is
  'Module 35 — crée ou modifie une prestation du catalogue.';

revoke all on function public.pressing_prestation_enregistrer(uuid, text, text, integer, integer, numeric, boolean)
  from public, anon;
grant execute on function public.pressing_prestation_enregistrer(uuid, text, text, integer, integer, numeric, boolean)
  to authenticated;


create or replace function public.pressing_tarif_definir(
  p_prestation_id uuid,
  p_categorie_id  uuid default null,
  p_prix          numeric default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ent uuid := public.pressing_entreprise();
  v_id  uuid;
begin
  if auth.uid() is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;
  if not (public.peut('pressing_depots', 'modifier') or public.est_plateforme()) then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de modifier les tarifs.';
  end if;
  if p_prix is null or p_prix < 0 then
    raise exception 'MONTANT_INVALIDE|Le prix doit être positif ou nul.';
  end if;
  if not exists (select 1 from public.pressing_prestations
                  where id = p_prestation_id and entreprise_id = v_ent) then
    raise exception 'INTROUVABLE|Cette prestation n''existe pas.';
  end if;
  if p_categorie_id is not null
     and not exists (select 1 from public.pressing_categories
                      where id = p_categorie_id and entreprise_id = v_ent) then
    raise exception 'INTROUVABLE|Ce type de vêtement n''existe pas.';
  end if;

  insert into public.pressing_tarifs (
    entreprise_id, prestation_id, categorie_id, prix, actif
  ) values (
    v_ent, p_prestation_id, p_categorie_id, p_prix, true
  )
  on conflict (
    entreprise_id, prestation_id,
    coalesce(categorie_id, '00000000-0000-0000-0000-000000000000'::uuid)
  )
  do update set prix = excluded.prix, actif = true, updated_at = now()
  returning id into v_id;

  return jsonb_build_object('ok', true, 'id', v_id, 'prix', p_prix);
end;
$$;

comment on function public.pressing_tarif_definir(uuid, uuid, numeric) is
  'Module 35 — fixe le prix d''une prestation pour un type de vêtement (categorie_id NULL = tarif par défaut).';

revoke all on function public.pressing_tarif_definir(uuid, uuid, numeric)
  from public, anon;
grant execute on function public.pressing_tarif_definir(uuid, uuid, numeric)
  to authenticated;


create or replace function public.pressing_tarif_supprimer(p_tarif_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ent uuid := public.pressing_entreprise();
begin
  if auth.uid() is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;
  if not (public.peut('pressing_depots', 'modifier') or public.est_plateforme()) then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de modifier les tarifs.';
  end if;

  -- Suppression LOGIQUE : un tarif déjà utilisé par une commande passée ne
  -- doit pas disparaître de l'historique (les commandes gardent de toute
  -- façon une copie du prix appliqué).
  update public.pressing_tarifs
     set actif = false, updated_at = now()
   where id = p_tarif_id and entreprise_id = v_ent;

  return jsonb_build_object('ok', true);
end;
$$;

comment on function public.pressing_tarif_supprimer(uuid) is
  'Module 35 — désactive un tarif (jamais de suppression physique).';

revoke all on function public.pressing_tarif_supprimer(uuid) from public, anon;
grant execute on function public.pressing_tarif_supprimer(uuid) to authenticated;


-- ============================================================================
--  9. LES RPC — CLIENTS DU PRESSING
-- ============================================================================

create or replace function public.pressing_client_enregistrer(
  p_id        uuid,
  p_nom       text,
  p_telephone text default null,
  p_adresse   text default null,
  p_email     text default null,
  p_notes     text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ent  uuid := public.pressing_entreprise();
  v_id   uuid;
  v_norm text;
begin
  if auth.uid() is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;
  if not (public.peut('pressing_depots', 'creer') or public.est_plateforme()) then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas d''enregistrer un client.';
  end if;
  if btrim(coalesce(p_nom, '')) = '' then
    raise exception 'NOM_VIDE|Indiquez le nom du client.';
  end if;

  v_norm := nullif(regexp_replace(coalesce(p_telephone, ''), '[^0-9]', '', 'g'), '');

  -- Anti-doublon : même téléphone ⇒ on complète la fiche existante.
  if p_id is null and v_norm is not null then
    select id into v_id
      from public.pressing_clients
     where entreprise_id = v_ent and telephone_norm = v_norm;

    if v_id is not null then
      update public.pressing_clients
         set nom = btrim(p_nom),
             telephone = nullif(btrim(coalesce(p_telephone, '')), ''),
             adresse = coalesce(nullif(btrim(coalesce(p_adresse, '')), ''), adresse),
             email = coalesce(nullif(btrim(coalesce(p_email, '')), ''), email),
             notes = coalesce(nullif(btrim(coalesce(p_notes, '')), ''), notes),
             updated_at = now()
       where id = v_id;

      return jsonb_build_object('ok', true, 'id', v_id, 'existant', true);
    end if;
  end if;

  if p_id is null then
    insert into public.pressing_clients (
      entreprise_id, nom, telephone, telephone_norm, adresse, email, notes,
      cree_par, derniere_activite
    ) values (
      v_ent, btrim(p_nom),
      nullif(btrim(coalesce(p_telephone, '')), ''), v_norm,
      nullif(btrim(coalesce(p_adresse, '')), ''),
      nullif(btrim(coalesce(p_email, '')), ''),
      nullif(btrim(coalesce(p_notes, '')), ''),
      auth.uid(), now()
    )
    returning id into v_id;
  else
    update public.pressing_clients
       set nom = btrim(p_nom),
           telephone = nullif(btrim(coalesce(p_telephone, '')), ''),
           telephone_norm = v_norm,
           adresse = nullif(btrim(coalesce(p_adresse, '')), ''),
           email = nullif(btrim(coalesce(p_email, '')), ''),
           notes = nullif(btrim(coalesce(p_notes, '')), ''),
           updated_at = now()
     where id = p_id and entreprise_id = v_ent
     returning id into v_id;

    if v_id is null then
      raise exception 'INTROUVABLE|Ce client n''existe pas.';
    end if;
  end if;

  return jsonb_build_object('ok', true, 'id', v_id, 'existant', false);
exception
  when unique_violation then
    raise exception 'DOUBLON|Un client avec ce numéro de téléphone existe déjà.';
end;
$$;

comment on function public.pressing_client_enregistrer(uuid, text, text, text, text, text) is
  'Module 35 — crée ou met à jour un client du pressing (anti-doublon sur le téléphone).';

revoke all on function public.pressing_client_enregistrer(uuid, text, text, text, text, text)
  from public, anon;
grant execute on function public.pressing_client_enregistrer(uuid, text, text, text, text, text)
  to authenticated;


create or replace function public.pressing_clients_lister(
  p_recherche text default null,
  p_limite    integer default 100
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_ent    uuid := public.pressing_entreprise();
  v_like   text;
  v_chiffres text;
  v_rows   jsonb;
begin
  if auth.uid() is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;

  v_like := nullif(btrim(coalesce(p_recherche, '')), '');
  -- On ne filtre sur le téléphone que si la recherche contient des chiffres :
  -- sinon `like '%%'` ramènerait TOUS les clients.
  v_chiffres := nullif(regexp_replace(coalesce(v_like, ''), '[^0-9]', '', 'g'), '');

  select coalesce(jsonb_agg(x order by x->>'nom'), '[]'::jsonb)
    into v_rows
    from (
      select jsonb_build_object(
               'id', c.id,
               'nom', c.nom,
               'telephone', c.telephone,
               'adresse', c.adresse,
               'email', c.email,
               'notes', c.notes,
               'derniere_activite', c.derniere_activite,
               'created_at', c.created_at
             ) as x
        from public.pressing_clients c
       where c.entreprise_id = v_ent
         and (v_like is null
              or coalesce(c.nom, '') ilike '%' || v_like || '%'
              or coalesce(c.telephone, '') ilike '%' || v_like || '%'
              or (v_chiffres is not null
                  and coalesce(c.telephone_norm, '') like '%' || v_chiffres || '%')
              or coalesce(c.email, '') ilike '%' || v_like || '%')
       order by c.nom
       limit greatest(coalesce(p_limite, 100), 1)
    ) s;

  return v_rows;
end;
$$;

comment on function public.pressing_clients_lister(text, integer) is
  'Module 35 — recherche rapide d''un client du pressing (nom, téléphone, e-mail).';

revoke all on function public.pressing_clients_lister(text, integer) from public, anon;
grant execute on function public.pressing_clients_lister(text, integer) to authenticated;


-- ============================================================================
--  10. JEU DE DÉPART (facultatif, jamais imposé)
-- ============================================================================
--    Aucun tarif n'est imposé : le propriétaire fixe SES prix. On crée
--    seulement, s'il n'a encore RIEN créé, une liste de types de vêtements
--    et de prestations vides de prix — pour qu'il n'ait pas à tout taper.
--    ⚠️ Aucun prix n'est inventé : sans prix, le dépôt demandera le montant.

create or replace function public.pressing_amorcer_catalogue()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ent  uuid := public.pressing_entreprise();
  v_nb   integer;
  v_noms text[] := array['Chemise', 'Pantalon', 'Veste', 'Costume', 'Robe',
                         'Jupe', 'Manteau', 'Drap', 'Couverture', 'Rideau',
                         'Serviette', 'Chaussures'];
  v_pres text[] := array['Lavage simple', 'Lavage et repassage',
                         'Repassage uniquement', 'Nettoyage à sec',
                         'Détachage', 'Traitement spécial', 'Express'];
  v_n    text;
  v_ordre integer := 10;
begin
  if auth.uid() is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;
  if not (public.peut('pressing_depots', 'modifier') or public.est_plateforme()) then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de modifier le catalogue.';
  end if;

  select count(*) into v_nb
    from public.pressing_categories where entreprise_id = v_ent;
  if v_nb = 0 then
    foreach v_n in array v_noms loop
      insert into public.pressing_categories (entreprise_id, nom, ordre)
      values (v_ent, v_n, v_ordre)
      on conflict do nothing;
      v_ordre := v_ordre + 10;
    end loop;
  end if;

  select count(*) into v_nb
    from public.pressing_prestations where entreprise_id = v_ent;
  if v_nb = 0 then
    foreach v_n in array v_pres loop
      insert into public.pressing_prestations (entreprise_id, nom)
      values (v_ent, v_n)
      on conflict do nothing;
    end loop;
  end if;

  return public.pressing_catalogue_lister();
end;
$$;

comment on function public.pressing_amorcer_catalogue() is
  'Module 35 — crée les types de vêtements et prestations de départ (sans aucun prix) si le catalogue est vide.';

revoke all on function public.pressing_amorcer_catalogue() from public, anon;
grant execute on function public.pressing_amorcer_catalogue() to authenticated;


-- ============================================================================
--  VÉRIFICATIONS (résultats visibles dans l'éditeur SQL)
-- ============================================================================

-- V1. L'activité « pressing » existe et porte bien ses 3 modules.
select position('press_depots'  in modules::text) > 0 as mod_depots,
       position('press_atelier' in modules::text) > 0 as mod_atelier,
       position('press_retraits' in modules::text) > 0 as mod_retraits
  from public.types_espaces_modules
 where type = 'pressing';

-- V2. Les 3 pages de permission sont déclarées (attendu : 3 true, true).
select position('pressing_depots'  in array_to_string(public.pages_permissions(), ',')) > 0 as page_depots,
       position('pressing_atelier' in array_to_string(public.pages_permissions(), ',')) > 0 as page_atelier,
       position('pressing_retraits' in array_to_string(public.pages_permissions(), ',')) > 0 as page_retraits,
       public.permissions_defaut('PROPRIETAIRE') ? 'pressing_depots' as proprio_depots;

-- V3. Les 5 tables sont créées.
select count(*) as tables_pressing
  from information_schema.tables
 where table_schema = 'public'
   and table_name in ('pressing_config', 'pressing_categories',
                      'pressing_prestations', 'pressing_tarifs',
                      'pressing_clients');

-- V4. Les RPC sont installées.
select proname
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and proname like 'pressing\_%'
 order by proname;
