-- ============================================================================
--  MODULE 19 — « BIASHARA : MARKETPLACE LOCAL GÉOLOCALISÉ »
--  Migration 20260916000040_module19_marketplace.sql
-- ============================================================================
--
--  OBJECTIF
--  --------
--  Permettre à QUICONQUE (y compris SANS COMPTE) de chercher un produit et de
--  découvrir les commerces qui le vendent AUTOUR DE LUI, de comparer les prix,
--  de voir la distance et d'obtenir un itinéraire. Les commerçants, eux,
--  mesurent la visibilité que Biashara leur apporte et peuvent préparer des
--  campagnes publicitaires clairement identifiées.
--
--  PRINCIPES D'ARCHITECTURE (aucune régression)
--  --------------------------------------------
--  1. AUCUNE table existante n'est remplacée. On AJOUTE :
--       • des colonnes à `espaces` (localisation + vitrine publique) ;
--       • de NOUVELLES tables (`produits_publications`, `recherches_publiques`,
--         `biashara_evenements`, `publicites`, `publicite_cibles`,
--         `publicite_evenements`, `liens_attribution`).
--     `produits`, `ventes`, `caisse`, `depenses`, `clients`, `dettes`,
--     `conditionnements` ne sont PAS modifiées.
--
--  2. SÉPARATION STRICTE PRIVÉ / PUBLIC.
--     Le catalogue public n'est JAMAIS lu directement dans les tables :
--     tout passe par des RPC `security definer` qui n'exposent qu'une LISTE
--     BLANCHE de colonnes. Aucune colonne privée (`prix_achat`, `quantite`
--     exacte, `clients`, `dettes`, `depenses`, bénéfices) n'est atteignable
--     par un visiteur, même en cas d'erreur d'application : `anon` ne reçoit
--     AUCUN `select` sur les tables du module.
--
--  3. GÉOLOCALISATION SANS EXTENSION OBLIGATOIRE.
--     PostGIS n'est pas requis : une fonction Haversine pure SQL
--     (`public.distance_km`) calcule les distances en kilomètres. Sur un
--     catalogue de cette taille, c'est plus que suffisant et cela reste
--     réversible (on pourra passer à PostGIS plus tard sans changer l'API).
--
--  4. VIE PRIVÉE DES VISITEURS.
--     Aucune position de visiteur n'est stockée : la position ne sert qu'à
--     calculer des distances À LA VOLÉE. Les évaluations analytiques ne
--     conservent qu'une TRANCHE de distance (« <1 km », « 1-3 km »…), jamais
--     de coordonnées, ni IP, ni identifiant de session. Les recherches
--     publiques ne conservent que le texte normalisé, la ville et le nombre
--     de résultats (aucun lien avec une personne).
--
--  5. VISIBILITÉ TRANSPARENTE.
--     Le classement « pertinence » ne dépend QUE de la correspondance du
--     texte, de la distance, de la complétude de la fiche et de la
--     disponibilité. Il ne dépend JAMAIS de la taille de l'entreprise, de son
--     ancienneté ou de ses revenus : une petite boutique bien renseignée et
--     proche passe devant. Les contenus sponsorisés vivent dans un ARRAY
--     SÉPARÉ (`publicites`) et portent la mention « PUBLICITÉ » : ils ne sont
--     jamais mélangés aux résultats organiques.
--
--  6. IDEMPOTENCE. Toutes les instructions sont rejouables sans erreur
--     (`if not exists`, `drop policy if exists`, `create or replace`).
--
--  ⚠️ Cette migration est exécutée par l'utilisateur dans le SQL Editor
--     Supabase (DDL impossible via PostgREST).
-- ============================================================================


-- ============================================================================
--  1. GÉOLOCALISATION & VITRINE PUBLIQUE DE LA BOUTIQUE (`espaces`)
-- ============================================================================
--  Chaque espace (entreprise du compte : boutique, hôtel, pharmacie…) peut
--  désormais publier :
--    • sa position (latitude / longitude + précision + statut) ;
--    • son adresse lisible par un visiteur qui ne connaît pas la ville
--      (adresse, quartier, avenue, numéro, point de repère, ville) ;
--    • ses coordonnées publiques (téléphone, WhatsApp) et ses horaires ;
--    • son logo et sa photo de devanture ;
--    • un texte de présentation.
--  `visible_publiquement` est un OPT-IN explicite du commerçant : tant qu'il
--  vaut `false`, la boutique n'apparaît nulle part dans le catalogue public.

alter table public.espaces
  add column if not exists description_publique text,
  add column if not exists telephone_public     text,
  add column if not exists whatsapp             text,
  add column if not exists horaires             jsonb not null default '{}'::jsonb,
  add column if not exists logo_url             text,
  add column if not exists photo_url            text,
  add column if not exists adresse              text,
  add column if not exists quartier             text,
  add column if not exists avenue               text,
  add column if not exists numero               text,
  add column if not exists point_repere         text,
  add column if not exists latitude             double precision,
  add column if not exists longitude            double precision,
  add column if not exists precision_localisation text,
  add column if not exists statut_localisation  text not null default 'non_renseignee',
  add column if not exists localisation_maj_le  timestamptz,
  add column if not exists visible_publiquement boolean not null default false,
  add column if not exists slug                 text;

do $$
begin
  -- Précision déclarée de la position retenue par le commerçant.
  alter table public.espaces
    drop constraint if exists chk_espaces_precision_localisation;
  alter table public.espaces
    add constraint chk_espaces_precision_localisation
    check (
      precision_localisation is null
      or precision_localisation in ('gps', 'carte', 'adresse', 'manuelle')
    );

  -- État de la localisation : le commerçant CONFIRME que le point correspond
  -- bien à sa boutique avant l'enregistrement final.
  alter table public.espaces
    drop constraint if exists chk_espaces_statut_localisation;
  alter table public.espaces
    add constraint chk_espaces_statut_localisation
    check (statut_localisation in ('non_renseignee', 'a_verifier', 'verifiee'));

  -- Bornes géographiques : évite qu'une saisie erronée (0, 0) ou un clic
  -- malencontreux fasse apparaître une boutique au milieu de l'océan.
  alter table public.espaces
    drop constraint if exists chk_espaces_coordonnees;
  alter table public.espaces
    add constraint chk_espaces_coordonnees
    check (
      (latitude is null and longitude is null)
      or (
        latitude is not null and longitude is not null
        and latitude between -90 and 90
        and longitude between -180 and 180
      )
    );

  alter table public.espaces
    drop constraint if exists chk_espaces_slug;
  alter table public.espaces
    add constraint chk_espaces_slug
    check (slug is null or slug ~ '^[a-z0-9][a-z0-9_-]{0,80}$');
end $$;

create unique index if not exists idx_espaces_slug_unique
  on public.espaces (slug)
  where slug is not null;

-- Recherche « boutiques proches » : index partiel sur les boutiques publiées
-- et géolocalisées (les seules interrogées par le catalogue public).
create index if not exists idx_espaces_publiees
  on public.espaces (visible_publiquement, actif)
  where visible_publiquement and latitude is not null;

create index if not exists idx_espaces_ville
  on public.espaces (ville_id)
  where visible_publiquement;

comment on column public.espaces.visible_publiquement is
  'Module 19 — Opt-in : la boutique apparaît dans le catalogue public Biashara (produits publiés + position + contacts publics uniquement).';
comment on column public.espaces.statut_localisation is
  'Module 19 — non_renseignee (jamais localisée) / a_verifier (position proposée, non confirmée) / verifiee (le commerçant a confirmé l''emplacement).';
comment on column public.espaces.precision_localisation is
  'Module 19 — Origine de la position : gps (ma position), carte (choix sur la carte), adresse (recherche d''adresse), manuelle.';
comment on column public.espaces.horaires is
  'Module 19 — Horaires publics : {"jours":[{"j":"lun","o":"08:00","f":"18:00"}],"note":"..."} (objet libre, affiché tel quel).';


-- ============================================================================
--  2. OUTILS GÉOGRAPHIQUES & TEXTE (purs, sans extension)
-- ============================================================================

-- 2.a Distance en kilomètres entre deux points (formule de Haversine).
create or replace function public.distance_km(
  p_lat1 double precision,
  p_lng1 double precision,
  p_lat2 double precision,
  p_lng2 double precision
)
returns double precision
language sql
immutable
as $$
  select case
    when p_lat1 is null or p_lng1 is null or p_lat2 is null or p_lng2 is null
      then null
    else 6371.0088 * 2 * asin(
      least(
        1.0::double precision,
        sqrt(
          power(sin(radians(p_lat2 - p_lat1) / 2), 2)
          + cos(radians(p_lat1)) * cos(radians(p_lat2))
            * power(sin(radians(p_lng2 - p_lng1) / 2), 2)
        )
      )
    )
  end;
$$;

comment on function public.distance_km(double precision, double precision, double precision, double precision) is
  'Module 19 — Distance en km (Haversine). Aucune extension requise ; NULL si une coordonnée manque.';


-- 2.b Tranche de distance (analytique SANS position précise conservée).
create or replace function public.biashara_tranche_distance(p_km double precision)
returns text
language sql
immutable
as $$
  select case
    when p_km is null then 'inconnue'
    when p_km < 1 then '<1'
    when p_km < 3 then '1-3'
    when p_km < 10 then '3-10'
    else '>10'
  end;
$$;

comment on function public.biashara_tranche_distance(double precision) is
  'Module 19 — Tranche de distance utilisée pour les statistiques : la position exacte du visiteur n''est jamais enregistrée.';


-- 2.c Normalisation du texte (minuscules, sans accents, espaces compactés).
create or replace function public.biashara_normaliser(p_texte text)
returns text
language sql
immutable
as $$
  select btrim(
    regexp_replace(
      lower(
        translate(
          coalesce(p_texte, ''),
          'àâäéèêëîïôöùûüçÀÂÄÉÈÊËÎÏÔÖÙÛÜÇ',
          'aaaeeeeiioouuucAAAEEEEIIOOUUUC'
        )
      ),
      '\s+', ' ', 'g'
    )
  );
$$;

comment on function public.biashara_normaliser(text) is
  'Module 19 — Normalisation de recherche : minuscules, accents retirés, espaces compactés (miroir Dart : MarketplaceService.normaliser).';


-- 2.d Slug d'URL (boutique partageable : /boutique/<slug>).
create or replace function public.biashara_slugifier(p_texte text)
returns text
language sql
immutable
as $$
  select coalesce(
    nullif(
      btrim(
        regexp_replace(
          regexp_replace(
            public.biashara_normaliser(p_texte),
            '[^a-z0-9]+', '-', 'g'
          ),
          '^-+|-+$', '', 'g'
        ),
        '-'
      ),
      ''
    ),
    'boutique'
  );
$$;

-- 2.e Slug UNIQUE pour un espace donné (ajoute un suffixe court si occupé).
create or replace function public.biashara_slug_unique(
  p_base text,
  p_espace_id uuid
)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_base text := left(public.biashara_slugifier(p_base), 60);
  v_slug text := v_base;
  v_i    integer := 0;
begin
  loop
    exit when not exists (
      select 1 from public.espaces e
       where e.slug = v_slug
         and (p_espace_id is null or e.id <> p_espace_id)
    );
    v_i := v_i + 1;
    v_slug := v_base || '-' || v_i::text;
    exit when v_i > 50;
  end loop;

  return v_slug;
end;
$$;

comment on function public.biashara_slug_unique(text, uuid) is
  'Module 19 — Retourne un slug unique pour la fiche publique d''une boutique.';


-- 2.f Catégorie analytique d'un événement (4 niveaux du cahier des charges :
--     VISIBILITÉ → INTÉRÊT → INTENTION → CONVERSION).
create or replace function public.biashara_categorie_evenement(p_type text)
returns text
language sql
immutable
as $$
  select case lower(btrim(coalesce(p_type, '')))
    when 'impression_produit'    then 'visibilite'
    when 'impression_boutique'   then 'visibilite'
    when 'impression_publicite'  then 'visibilite'
    when 'recherche'             then 'visibilite'
    when 'vue_produit'           then 'interet'
    when 'vue_boutique'          then 'interet'
    when 'partage'               then 'interet'
    when 'clic_publicite'        then 'interet'
    when 'clic_itineraire'       then 'intention'
    when 'clic_telephone'        then 'intention'
    when 'clic_whatsapp'         then 'intention'
    when 'clic_site'             then 'intention'
    when 'conversion'            then 'conversion'
    else 'autre'
  end;
$$;

comment on function public.biashara_categorie_evenement(text) is
  'Module 19 — Classe un événement analytique : visibilite (impressions), interet (vues/clics), intention (itinéraire, appel, WhatsApp), conversion (achat attribué).';


-- ============================================================================
--  3. TRIGGER — SLUG AUTOMATIQUE & HORODATAGE DE LA LOCALISATION
-- ============================================================================
--  Le slug est produit dès qu'une boutique devient publique : le commerçant
--  n'a jamais à s'en occuper, et le lien de partage reste stable.

create or replace function public.trg_m19_espace_slug()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.slug is null or btrim(new.slug) = '' then
    if new.visible_publiquement then
      new.slug := public.biashara_slug_unique(new.nom, new.id);
    end if;
  end if;

  if tg_op = 'UPDATE'
     and (
       new.latitude is distinct from old.latitude
       or new.longitude is distinct from old.longitude
       or new.adresse is distinct from old.adresse
       or new.quartier is distinct from old.quartier
       or new.point_repere is distinct from old.point_repere
     ) then
    new.localisation_maj_le := now();
  end if;

  return new;
end;
$$;

drop trigger if exists trg_m19_espace_slug on public.espaces;
create trigger trg_m19_espace_slug
  before insert or update on public.espaces
  for each row
  execute function public.trg_m19_espace_slug();


-- ============================================================================
--  4. TABLE `produits_publications` — CE QUI EST VISIBLE PUBLIQUEMENT
-- ============================================================================
--  Le commerçant choisit explicitement les articles qu'il publie. On ne
--  modifie PAS `produits` : la publication est une couche de présentation
--  (prix public éventuellement promotionnel, description courte, photo).
--  Supprimer l'article supprime sa publication (cascade).

create table if not exists public.produits_publications (
  id                 uuid primary key default gen_random_uuid(),
  produit_id         bigint not null
                       references public.produits(id) on delete cascade,
  owner_id           uuid not null,
  espace_id          uuid references public.espaces(id) on delete set null,
  publie             boolean not null default true,
  disponible         boolean not null default true,
  prix_public        real,
  unite              text,
  description_courte text,
  photo_url          text,
  mots_cles          text,
  vues               bigint not null default 0,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

create unique index if not exists idx_produits_publications_produit
  on public.produits_publications (produit_id);

create index if not exists idx_produits_publications_owner
  on public.produits_publications (owner_id, publie);

create index if not exists idx_produits_publications_espace
  on public.produits_publications (espace_id);

create index if not exists idx_produits_publications_publie
  on public.produits_publications (publie, disponible);

alter table public.produits_publications enable row level security;

-- Le patron (ou la plateforme) peut LIRE ses publications. Les ÉCRITURES
-- passent exclusivement par les RPC du module 19 : aucune policy d'insertion
-- ou de modification n'est créée, et les droits sont révoqués en fin de
-- section. Un visiteur (`anon`) n'a AUCUN accès à cette table.
drop policy if exists m19_publications_lecture on public.produits_publications;
create policy m19_publications_lecture on public.produits_publications
  for select to authenticated
  using (
    public.est_plateforme()
    or owner_id = public.mon_proprietaire()
    or owner_id = auth.uid()
  );

comment on table public.produits_publications is
  'Module 19 — Publications du catalogue public : quels articles sont visibles, à quel prix public, avec quels visuels. La table `produits` n''est jamais modifiée par ce module.';


-- ============================================================================
--  5. TABLE `recherches_publiques` — MESURER LES RECHERCHES SANS ESPIONNER
-- ============================================================================
--  On ne conserve QUE : le texte normalisé (≤ 120 caractères), la ville
--  choisie, la catégorie, le nombre de résultats et le critère de tri.
--  NI IP, NI identifiant d'appareil, NI position : une recherche n'est pas
--  rattachable à une personne.

create table if not exists public.recherches_publiques (
  id            bigserial primary key,
  texte         text not null,
  ville_id      uuid references public.villes(id) on delete set null,
  categorie     text,
  nb_resultats  integer not null default 0,
  tri           text,
  le            timestamptz not null default now()
);

create index if not exists idx_recherches_publiques_le
  on public.recherches_publiques (le desc);

create index if not exists idx_recherches_publiques_texte
  on public.recherches_publiques (texte);

alter table public.recherches_publiques enable row level security;
-- Aucune policy : table alimentée par les RPC `security definer` seulement.
-- (Le personnel plateforme la consulte via `rpc_biashara_visibilite`.)

comment on table public.recherches_publiques is
  'Module 19 — Volume de recherches publiques (texte normalisé, ville, nb de résultats). Aucune donnée personnelle ni position de visiteur.';


-- ============================================================================
--  6. TABLE `biashara_evenements` — ANALYTIQUE DE VISIBILITÉ
-- ============================================================================
--  Chaque événement est rattaché à la BOUTIQUE (owner_id / espace_id) et non
--  au visiteur. La distance est enregistrée en TRANCHE, jamais en clair.

create table if not exists public.biashara_evenements (
  id                bigserial primary key,
  categorie         text not null,
  type_evenement    text not null,
  entite_type       text,
  entite_id         text,
  owner_id          uuid,
  espace_id         uuid,
  publicite_id      uuid,
  recherche_id      bigint,
  ville_id          uuid references public.villes(id) on delete set null,
  quartier          text,
  tranche_distance  text,
  le                timestamptz not null default now()
);

do $$
begin
  alter table public.biashara_evenements
    drop constraint if exists chk_biashara_evenements_categorie;
  alter table public.biashara_evenements
    add constraint chk_biashara_evenements_categorie
    check (categorie in ('visibilite', 'interet', 'intention', 'conversion', 'autre'));

  alter table public.biashara_evenements
    drop constraint if exists chk_biashara_evenements_entite;
  alter table public.biashara_evenements
    add constraint chk_biashara_evenements_entite
    check (entite_type is null or entite_type in ('produit', 'boutique', 'publicite', 'recherche'));
end $$;

create index if not exists idx_biashara_evenements_owner
  on public.biashara_evenements (owner_id, le desc);

create index if not exists idx_biashara_evenements_entite
  on public.biashara_evenements (entite_type, entite_id, le desc);

create index if not exists idx_biashara_evenements_type
  on public.biashara_evenements (type_evenement, le desc);

alter table public.biashara_evenements enable row level security;

-- Le patron lit SES statistiques (l'agrégation est faite par RPC, mais on
-- ouvre la lecture pour permettre des vérifications manuelles).
drop policy if exists m19_evenements_lecture on public.biashara_evenements;
create policy m19_evenements_lecture on public.biashara_evenements
  for select to authenticated
  using (public.est_plateforme() or owner_id = public.mon_proprietaire());

comment on table public.biashara_evenements is
  'Module 19 — Événements de visibilité Biashara (impression, vue, recherche, itinéraire, appel, WhatsApp, partage, conversion). Aucune donnée personnelle : ni IP, ni identifiant d''appareil, ni position exacte.';


-- ============================================================================
--  7. TABLES PUBLICITAIRES (préparation commerciale)
-- ============================================================================
--  Architecture volontairement complète mais INACTIVE par défaut : une
--  campagne suit un cycle brouillon → soumise → active → terminee (ou
--  refusee / pause). Le ciblage géographique et par catégorie permet
--  notamment à une boutique de Lubumbashi de promouvoir un produit auprès
--  des personnes qui cherchent cette catégorie dans une zone donnée — sans
--  jamais accéder à la position d'un visiteur.

create table if not exists public.publicites (
  id                 uuid primary key default gen_random_uuid(),
  owner_id           uuid not null,
  espace_id          uuid references public.espaces(id) on delete set null,
  titre              text not null,
  message            text,
  mention            text not null default 'PUBLICITÉ',
  type_contenu       text not null default 'produit',
  produit_id         bigint references public.produits(id) on delete set null,
  image_url          text,
  prix_promo         real,
  date_debut         timestamptz,
  date_fin           timestamptz,
  budget             real,
  plafond_impressions integer,
  statut             text not null default 'brouillon',
  impressions        bigint not null default 0,
  clics              bigint not null default 0,
  conversions        bigint not null default 0,
  note_moderation    text,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

do $$
begin
  alter table public.publicites
    drop constraint if exists chk_publicites_type_contenu;
  alter table public.publicites
    add constraint chk_publicites_type_contenu
    check (type_contenu in ('produit', 'boutique', 'promotion', 'offre'));

  alter table public.publicites
    drop constraint if exists chk_publicites_statut;
  alter table public.publicites
    add constraint chk_publicites_statut
    check (statut in ('brouillon', 'soumise', 'active', 'pause', 'terminee', 'refusee'));
end $$;

create index if not exists idx_publicites_owner
  on public.publicites (owner_id, statut);

create index if not exists idx_publicites_active
  on public.publicites (statut, date_debut, date_fin)
  where statut = 'active';

alter table public.publicites enable row level security;

drop policy if exists m19_publicites_lecture on public.publicites;
create policy m19_publicites_lecture on public.publicites
  for select to authenticated
  using (
    public.est_plateforme()
    or owner_id = public.mon_proprietaire()
    or owner_id = auth.uid()
  );

comment on table public.publicites is
  'Module 19 — Campagnes publicitaires Biashara (toujours affichées avec la mention « PUBLICITÉ »). Cycle : brouillon → soumise → active → terminee (ou refusee / pause).';


-- 7.b CIBLAGE : ville, quartier, rayon autour d'un point, catégorie.
create table if not exists public.publicite_cibles (
  id           uuid primary key default gen_random_uuid(),
  publicite_id uuid not null references public.publicites(id) on delete cascade,
  type_cible   text not null,
  ville_id     uuid references public.villes(id) on delete set null,
  quartier     text,
  categorie    text,
  rayon_km     double precision,
  centre_lat   double precision,
  centre_lng   double precision,
  created_at   timestamptz not null default now()
);

do $$
begin
  alter table public.publicite_cibles
    drop constraint if exists chk_publicite_cibles_type;
  alter table public.publicite_cibles
    add constraint chk_publicite_cibles_type
    check (type_cible in ('ville', 'quartier', 'rayon', 'categorie'));
end $$;

create index if not exists idx_publicite_cibles_publicite
  on public.publicite_cibles (publicite_id);

alter table public.publicite_cibles enable row level security;

drop policy if exists m19_publicite_cibles_lecture on public.publicite_cibles;
create policy m19_publicite_cibles_lecture on public.publicite_cibles
  for select to authenticated
  using (
    exists (
      select 1 from public.publicites p
       where p.id = publicite_id
         and (public.est_plateforme()
              or p.owner_id = public.mon_proprietaire()
              or p.owner_id = auth.uid())
    )
  );

comment on table public.publicite_cibles is
  'Module 19 — Zones/catégories visées par une campagne (ville, quartier, rayon autour d''un point, catégorie). Le rayon sert au CIBLAGE, jamais à localiser un visiteur.';


-- 7.c ÉVÉNEMENTS PUBLICITAIRES (impressions / clics / conversions).
create table if not exists public.publicite_evenements (
  id           bigserial primary key,
  publicite_id uuid not null references public.publicites(id) on delete cascade,
  owner_id     uuid,
  type_evenement text not null,
  ville_id     uuid references public.villes(id) on delete set null,
  quartier     text,
  tranche_distance text,
  le           timestamptz not null default now()
);

do $$
begin
  alter table public.publicite_evenements
    drop constraint if exists chk_publicite_evenements_type;
  alter table public.publicite_evenements
    add constraint chk_publicite_evenements_type
    check (type_evenement in ('impression', 'clic', 'conversion'));
end $$;

create index if not exists idx_publicite_evenements_pub
  on public.publicite_evenements (publicite_id, le desc);

alter table public.publicite_evenements enable row level security;

drop policy if exists m19_publicite_evenements_lecture on public.publicite_evenements;
create policy m19_publicite_evenements_lecture on public.publicite_evenements
  for select to authenticated
  using (public.est_plateforme() or owner_id = public.mon_proprietaire());

comment on table public.publicite_evenements is
  'Module 19 — Impressions, clics et conversions d''une campagne. Aucune donnée personnelle.';


-- ============================================================================
--  8. TABLE `liens_attribution` — POURQUOI UNE VENTE EST ATTRIBUÉE À BIASHARA
-- ============================================================================
--  Mécanisme PROGRESSIF : un code/lien traçable (QR sur la vitrine, bouton
--  « Acheter chez cette boutique », code promotionnel) permet d'attribuer une
--  vente SANS jamais prétendre qu'une simple consultation est un achat. Le
--  module 8 (`rpc_vente_valider`) n'est PAS modifié : l'exploitation du code
--  se fera par une évolution dédiée qui enregistrera un événement
--  `conversion` avec la référence du lien.

create table if not exists public.liens_attribution (
  id          uuid primary key default gen_random_uuid(),
  code        text not null,
  owner_id    uuid not null,
  espace_id   uuid references public.espaces(id) on delete set null,
  produit_id  bigint references public.produits(id) on delete set null,
  publicite_id uuid references public.publicites(id) on delete set null,
  type_lien   text not null default 'qr',
  libelle     text,
  cible_url   text,
  actif       boolean not null default true,
  utilisations bigint not null default 0,
  created_at  timestamptz not null default now()
);

do $$
begin
  alter table public.liens_attribution
    drop constraint if exists chk_liens_attribution_type;
  alter table public.liens_attribution
    add constraint chk_liens_attribution_type
    check (type_lien in ('qr', 'lien', 'code'));
end $$;

create unique index if not exists idx_liens_attribution_code
  on public.liens_attribution (upper(code));

create index if not exists idx_liens_attribution_owner
  on public.liens_attribution (owner_id, actif);

alter table public.liens_attribution enable row level security;

drop policy if exists m19_liens_lecture on public.liens_attribution;
create policy m19_liens_lecture on public.liens_attribution
  for select to authenticated
  using (
    public.est_plateforme()
    or owner_id = public.mon_proprietaire()
    or owner_id = auth.uid()
  );

comment on table public.liens_attribution is
  'Module 19 — Codes/liens/QR d''attribution (BIA-XXXXXX). Permet de mesurer une conversion réelle, sans modifier le module 8 : l''exploitation est une évolution dédiée.';


-- ============================================================================
--  8 bis. COMPTE OPÉRATIONNEL & PROTECTION DES ÉCRITURES DU MODULE
-- ============================================================================
--  Politique retenue, cohérente avec la double validation du module 14 :
--    • un commerçant dont le dossier est EN ATTENTE DE VÉRIFICATION peut
--      PRÉPARER entièrement sa vitrine (position, horaires, articles à
--      publier) : il ne doit pas être bloqué pendant l'instruction ;
--    • un compte REJETÉ ou SUSPENDU ne peut plus rien écrire dans le module
--      (aucune nouvelle publication) ;
--    • seule la VISIBILITÉ PUBLIQUE est conditionnée à l'activation : la vue
--      `v_biashara_boutiques` ne présente que des boutiques validées. Le
--      commerçant voit donc dans son application « vitrine prête, publication
--      dès l'activation », ce qui est la vérité.

create or replace function public.biashara_compte_operationnel(p_entreprise uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_etape  text;
  v_statut text;
begin
  if p_entreprise is null then
    return true; -- fail-open : mieux vaut laisser passer que bloquer à tort.
  end if;

  select coalesce(t.activation_etape, 'actif'), coalesce(t.statut::text, '')
    into v_etape, v_statut
    from public.entreprises t
   where t.id = p_entreprise;

  if not found then
    return true;
  end if;

  if v_etape = 'rejete' then return false; end if;
  if v_statut = 'SUSPENDU' then return false; end if;
  return true;
end;
$$;

comment on function public.biashara_compte_operationnel(uuid) is
  'Module 19 — Le compte peut-il écrire dans le module marketplace ? (rejeté ou suspendu = non ; en attente de validation = oui, pour préparer la vitrine).';


create or replace function public.trg_m19_blocage()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ent uuid;
begin
  -- La plateforme n'est jamais soumise à ce contrôle.
  if public.est_plateforme() then
    return new;
  end if;

  if tg_table_name = 'espaces' then
    v_ent := new.entreprise_id;
  elsif tg_table_name in ('produits_publications', 'publicites', 'liens_attribution') then
    select u.entreprise_id into v_ent
      from public.utilisateurs u where u.id = new.owner_id;
  elsif tg_table_name = 'publicite_cibles' then
    select u.entreprise_id into v_ent
      from public.publicites p
      join public.utilisateurs u on u.id = p.owner_id
     where p.id = new.publicite_id;
  end if;

  if not public.biashara_compte_operationnel(v_ent) then
    raise exception
      'ACTIVATION_REQUISE|Votre compte est rejeté ou suspendu : la vitrine Biashara ne peut plus être modifiée. Contactez l''assistance.';
  end if;

  return new;
end;
$$;

comment on function public.trg_m19_blocage() is
  'Module 19 — Refuse toute écriture du module marketplace pour un compte rejeté ou suspendu (la plateforme est exemptée).';

-- Note : le déclencheur sur `espaces` est volontairement en AFTER INSERT OR
-- UPDATE avec un contrôle conditionnel, pour ne JAMAIS gêner la création
-- d'entreprise à l'inscription.
drop trigger if exists trg_m19_blocage_espaces on public.espaces;
create trigger trg_m19_blocage_espaces
  before update on public.espaces
  for each row
  execute function public.trg_m19_blocage();

drop trigger if exists trg_m19_blocage_publications on public.produits_publications;
create trigger trg_m19_blocage_publications
  before insert or update on public.produits_publications
  for each row
  execute function public.trg_m19_blocage();

drop trigger if exists trg_m19_blocage_publicites on public.publicites;
create trigger trg_m19_blocage_publicites
  before insert or update on public.publicites
  for each row
  execute function public.trg_m19_blocage();

drop trigger if exists trg_m19_blocage_cibles on public.publicite_cibles;
create trigger trg_m19_blocage_cibles
  before insert or update on public.publicite_cibles
  for each row
  execute function public.trg_m19_blocage();

drop trigger if exists trg_m19_blocage_liens on public.liens_attribution;
create trigger trg_m19_blocage_liens
  before insert or update on public.liens_attribution
  for each row
  execute function public.trg_m19_blocage();


-- ============================================================================
--  9. VUES DE LECTURE PUBLIQUE (whitelist de colonnes)
-- ============================================================================
--  Les RPC publiques s'appuient sur ces vues `security_invoker = false` :
--  elles ne contiennent QUE des informations destinées au public. Aucune
--  donnée privée n'y figure, ce qui rend une fuite accidentelle impossible
--  au niveau de la requête.

create or replace view public.v_biashara_boutiques
as
  select
    e.id                as espace_id,
    e.nom               as nom,
    e.slug              as slug,
    coalesce(e.type, 'boutique') as type,
    e.description_publique as description,
    e.telephone_public  as telephone,
    e.whatsapp          as whatsapp,
    e.horaires          as horaires,
    e.logo_url          as logo_url,
    e.photo_url         as photo_url,
    e.adresse           as adresse,
    e.quartier          as quartier,
    e.avenue            as avenue,
    e.numero            as numero,
    e.point_repere      as point_repere,
    e.latitude          as latitude,
    e.longitude         as longitude,
    e.statut_localisation as statut_localisation,
    e.precision_localisation as precision_localisation,
    e.ville_id          as ville_id,
    (select v.nom from public.villes v where v.id = e.ville_id) as ville,
    (select v.pays from public.villes v where v.id = e.ville_id) as pays,
    -- `espaces` ne porte pas d'`owner_id` : le patron est TOUJOURS résolu par
    -- jointure sur `utilisateurs` (aucune donnée dupliquée, donc aucune
    -- désynchronisation possible si le propriétaire change).
    (select u.id
       from public.utilisateurs u
      where u.entreprise_id = e.entreprise_id
        and u.parent_id is null
      order by u.created_at
      limit 1) as owner_id,
    e.created_at        as created_at,
    -- État du compte (utilisé par l'application pour expliquer au commerçant
    -- pourquoi sa vitrine n'est pas encore visible du public).
    coalesce(t.activation_etape, 'actif') as activation_etape,
    coalesce(t.statut::text, '') as statut_abonnement
  from public.espaces e
  join public.entreprises t on t.id = e.entreprise_id
 where e.visible_publiquement
   and e.actif
   and e.latitude is not null
   and e.longitude is not null
   -- Le catalogue public ne présente que des boutiques VALIDÉES : un compte
   -- rejeté ou suspendu disparaît ; une boutique en attente de validation est
   -- préparée par son patron mais publiée à l'activation (module 14).
   and coalesce(t.activation_etape, 'actif') in ('actif', 'restreint')
   and coalesce(t.statut::text, '') <> 'SUSPENDU';

comment on view public.v_biashara_boutiques is
  'Module 19 — Vue PUBLIQUE des boutiques participantes (colonnes en liste blanche : aucun prix d''achat, aucune donnée interne).';


-- ============================================================================
--  10. RPC — CATALOGUE PUBLIC (accessibles SANS COMPTE)
-- ============================================================================

-- 10.a RECHERCHE PUBLIQUE — cœur du module.
--
--  Critères de tri (au choix du visiteur) :
--    • 'pertinence' (défaut) : correspondance du texte, puis complétude de la
--      fiche, disponibilité et proximité ;
--    • 'distance'   : le plus proche d'abord (les boutiques sans position
--      restent en fin de liste) ;
--    • 'prix'       : prix public croissant.
--
--  Le score de pertinence ne comporte AUCUN critère de taille d'entreprise :
--  une petite boutique proche, disponible et bien renseignée peut passer
--  devant une grande enseigne éloignée.
create or replace function public.rpc_biashara_rechercher(
  p_texte      text default null,
  p_lat        double precision default null,
  p_lng        double precision default null,
  p_ville_id   uuid default null,
  p_tri        text default 'pertinence',
  p_categorie  text default null,
  p_limite     integer default 20,
  p_decalage   integer default 0,
  p_enregistrer boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_q        text := public.biashara_normaliser(p_texte);
  v_tri      text := lower(btrim(coalesce(p_tri, 'pertinence')));
  v_limite   integer := least(greatest(coalesce(p_limite, 20), 1), 50);
  v_decalage integer := greatest(coalesce(p_decalage, 0), 0);
  v_recherche_id bigint;
  v_total    integer := 0;
  v_resultats jsonb := '[]'::jsonb;
  v_boutiques integer := 0;
  v_publicites jsonb := '[]'::jsonb;
begin
  if v_tri not in ('pertinence', 'distance', 'prix') then
    v_tri := 'pertinence';
  end if;

  if length(v_q) > 120 then
    v_q := left(v_q, 120);
  end if;

  -- Nombre de résultats AVANT pagination.
  select count(*)
    into v_total
    from public.produits_publications pb
    join public.produits p on p.id = pb.produit_id
    join public.v_biashara_boutiques b on b.espace_id = pb.espace_id
   where pb.publie
     and (v_q = '' or public.biashara_normaliser(
            p.nom || ' ' || coalesce(p.categorie, '') || ' '
            || coalesce(pb.description_courte, '') || ' '
            || coalesce(pb.mots_cles, '')) like '%' || v_q || '%')
     and (p_categorie is null or btrim(p_categorie) = ''
          or public.biashara_normaliser(p.categorie)
             = public.biashara_normaliser(p_categorie))
     and (p_ville_id is null or b.ville_id = p_ville_id);

  select count(distinct pb.espace_id)
    into v_boutiques
    from public.produits_publications pb
    join public.produits p on p.id = pb.produit_id
    join public.v_biashara_boutiques b on b.espace_id = pb.espace_id
   where pb.publie
     and (v_q = '' or public.biashara_normaliser(
            p.nom || ' ' || coalesce(p.categorie, '') || ' '
            || coalesce(pb.description_courte, '') || ' '
            || coalesce(pb.mots_cles, '')) like '%' || v_q || '%')
     and (p_categorie is null or btrim(p_categorie) = ''
          or public.biashara_normaliser(p.categorie)
             = public.biashara_normaliser(p_categorie))
     and (p_ville_id is null or b.ville_id = p_ville_id);

  -- Résultats paginés. Le score de PERTINENCE ne dépend jamais de la taille de
  -- l'entreprise : uniquement de la correspondance du texte, de la complétude
  -- de la fiche, de la disponibilité et de la proximité.
  select coalesce(jsonb_agg(q.ligne order by
           q.ordre_prix       asc  nulls last,
           q.ordre_distance   asc  nulls last,
           q.ordre_score      desc nulls last,
           q.ordre_proche     asc  nulls last), '[]'::jsonb)
    into v_resultats
    from (
      select
        jsonb_build_object(
          'publication_id', pb.id,
          'produit_id',     p.id,
          'nom',            p.nom,
          'description',    coalesce(nullif(btrim(pb.description_courte), ''),
                                    nullif(btrim(p.description), '')),
          'photo',          coalesce(pb.photo_url, p.photo),
          'prix',           coalesce(pb.prix_public, p.prix_vente),
          'unite',          coalesce(nullif(btrim(pb.unite), ''), p.unite_mesure),
          'categorie',      nullif(btrim(p.categorie), ''),
          'disponible',     pb.disponible and p.quantite > 0,
          'vendable_au_poids', coalesce(p.vendable_au_poids, false),
          'attributs',      case when p.attributs is null
                                    or p.attributs = '{}'::jsonb
                                 then null else p.attributs end,
          'boutique', jsonb_build_object(
            'espace_id',  b.espace_id,
            'nom',        b.nom,
            'slug',       b.slug,
            'type',       b.type,
            'logo_url',   b.logo_url,
            'quartier',   b.quartier,
            'adresse',    b.adresse,
            'ville',      b.ville,
            'telephone',  b.telephone,
            'whatsapp',   b.whatsapp,
            'latitude',   b.latitude,
            'longitude',  b.longitude,
            'localisation_verifiee', b.statut_localisation = 'verifiee'
          ),
          'distance_km', round(
            (case when p_lat is not null and p_lng is not null
                  then public.distance_km(p_lat, p_lng, b.latitude, b.longitude)
             end)::numeric, 2)
        ) as ligne,
        -- Critères d'ordonnancement : une seule branche est non nulle selon
        -- le tri demandé, les autres servent de départage stable.
        (case when v_tri = 'prix'
              then coalesce(pb.prix_public, p.prix_vente) end)      as ordre_prix,
        (case when v_tri = 'distance'
              then public.distance_km(p_lat, p_lng, b.latitude, b.longitude)
         end)                                                        as ordre_distance,
        (case when v_tri = 'pertinence' then
           (case
              when v_q = '' then 40
              when public.biashara_normaliser(p.nom) = v_q then 100
              when public.biashara_normaliser(p.nom) like v_q || '%' then 85
              when public.biashara_normaliser(p.nom) like '%' || v_q || '%' then 70
              else 55
            end)
           + (case when pb.disponible and p.quantite > 0 then 8 else 0 end)
           + (case when coalesce(pb.photo_url, p.photo) is not null then 4 else 0 end)
           + (case when nullif(btrim(coalesce(pb.description_courte, p.description)), '') is not null
                   then 4 else 0 end)
           + (case when b.quartier is not null and b.point_repere is not null then 4 else 0 end)
           + (case when b.statut_localisation = 'verifiee' then 5 else 0 end)
         end)                                                        as ordre_score,
        public.distance_km(p_lat, p_lng, b.latitude, b.longitude)    as ordre_proche
      from public.produits_publications pb
      join public.produits p on p.id = pb.produit_id
      join public.v_biashara_boutiques b on b.espace_id = pb.espace_id
     where pb.publie
       and (v_q = '' or public.biashara_normaliser(
              p.nom || ' ' || coalesce(p.categorie, '') || ' '
              || coalesce(pb.description_courte, '') || ' '
              || coalesce(pb.mots_cles, '')) like '%' || v_q || '%')
       and (p_categorie is null or btrim(p_categorie) = ''
            or public.biashara_normaliser(p.categorie)
               = public.biashara_normaliser(p_categorie))
       and (p_ville_id is null or b.ville_id = p_ville_id)
     order by
       (case when v_tri = 'prix'
             then coalesce(pb.prix_public, p.prix_vente) end)  asc  nulls last,
       (case when v_tri = 'distance'
             then public.distance_km(p_lat, p_lng, b.latitude, b.longitude)
        end)                                                    asc  nulls last,
       (case when v_tri = 'pertinence' then
          (case
             when v_q = '' then 40
             when public.biashara_normaliser(p.nom) = v_q then 100
             when public.biashara_normaliser(p.nom) like v_q || '%' then 85
             when public.biashara_normaliser(p.nom) like '%' || v_q || '%' then 70
             else 55
           end)
          + (case when pb.disponible and p.quantite > 0 then 8 else 0 end)
          + (case when coalesce(pb.photo_url, p.photo) is not null then 4 else 0 end)
          + (case when nullif(btrim(coalesce(pb.description_courte, p.description)), '') is not null
                  then 4 else 0 end)
          + (case when b.quartier is not null and b.point_repere is not null then 4 else 0 end)
          + (case when b.statut_localisation = 'verifiee' then 5 else 0 end)
        end)                                                    desc nulls last,
       public.distance_km(p_lat, p_lng, b.latitude, b.longitude) asc nulls last
     limit v_limite offset v_decalage
    ) q;

  -- Enregistrement de la recherche (aucune donnée personnelle).
  if p_enregistrer and v_q <> '' then
    insert into public.recherches_publiques (texte, ville_id, categorie, nb_resultats, tri)
    values (left(v_q, 120), p_ville_id, nullif(btrim(coalesce(p_categorie, '')), ''),
            v_total, v_tri)
    returning id into v_recherche_id;
  end if;

  -- Publicités en ARRAY SÉPARÉ (jamais mélangées aux résultats organiques).
  v_publicites := public.biashara_publicites_servir(
    p_lat, p_lng, p_ville_id, p_categorie, 3
  );

  return jsonb_build_object(
    'ok', true,
    'texte', p_texte,
    'tri', v_tri,
    'rayon_km', null,
    'total', v_total,
    'nb_boutiques', v_boutiques,
    'resultats', v_resultats,
    'publicites', v_publicites,
    'recherche_id', v_recherche_id
  );
end;
$$;

comment on function public.rpc_biashara_rechercher(text, double precision, double precision, uuid, text, text, integer, integer, boolean) is
  'Module 19 — Recherche PUBLIQUE sans compte : produits publiés des boutiques participantes, triés par pertinence, distance ou prix. Les publicités sont renvoyées séparément et toujours marquées.';


-- 10.b FICHE PUBLIQUE D'UNE BOUTIQUE (par slug ou par identifiant).
create or replace function public.rpc_biashara_boutique(
  p_slug text,
  p_lat  double precision default null,
  p_lng  double precision default null,
  p_limite integer default 60
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cle    text := btrim(coalesce(p_slug, ''));
  v_limite integer := least(greatest(coalesce(p_limite, 60), 1), 200);
  v_b      public.v_biashara_boutiques;
  v_produits jsonb := '[]'::jsonb;
  v_nb     integer := 0;
  v_distance double precision;
begin
  if v_cle = '' then
    raise exception 'BOUTIQUE_INCONNUE|Aucune boutique demandée.';
  end if;

  select * into v_b
    from public.v_biashara_boutiques b
   where b.slug = v_cle
      or b.espace_id::text = v_cle
   limit 1;

  if v_b.espace_id is null then
    raise exception 'BOUTIQUE_INCONNUE|Cette boutique n''est pas (ou plus) présente sur Biashara.';
  end if;

  v_distance := public.distance_km(p_lat, p_lng, v_b.latitude, v_b.longitude);

  select count(*)
    into v_nb
    from public.produits_publications pb
   where pb.espace_id = v_b.espace_id and pb.publie;

  select coalesce(jsonb_agg(jsonb_build_object(
           'publication_id', pb.id,
           'produit_id',     p.id,
           'nom',            p.nom,
           'description',    coalesce(nullif(btrim(pb.description_courte), ''),
                                     nullif(btrim(p.description), '')),
           'photo',          coalesce(pb.photo_url, p.photo),
           'prix',           coalesce(pb.prix_public, p.prix_vente),
           'unite',          coalesce(nullif(btrim(pb.unite), ''), p.unite_mesure),
           'categorie',      nullif(btrim(p.categorie), ''),
           'disponible',     pb.disponible and p.quantite > 0,
           'vendable_au_poids', coalesce(p.vendable_au_poids, false)
         ) order by (pb.disponible and p.quantite > 0) desc, p.nom), '[]'::jsonb)
    into v_produits
    from public.produits_publications pb
    join public.produits p on p.id = pb.produit_id
   where pb.espace_id = v_b.espace_id and pb.publie
   limit v_limite;

  return jsonb_build_object(
    'ok', true,
    'boutique', jsonb_build_object(
      'espace_id',   v_b.espace_id,
      'nom',         v_b.nom,
      'slug',        v_b.slug,
      'type',        v_b.type,
      'description', v_b.description,
      'telephone',   v_b.telephone,
      'whatsapp',    v_b.whatsapp,
      'horaires',    v_b.horaires,
      'logo_url',    v_b.logo_url,
      'photo_url',   v_b.photo_url,
      'adresse',     v_b.adresse,
      'quartier',    v_b.quartier,
      'avenue',      v_b.avenue,
      'numero',      v_b.numero,
      'point_repere', v_b.point_repere,
      'latitude',    v_b.latitude,
      'longitude',   v_b.longitude,
      'ville',       v_b.ville,
      'pays',        v_b.pays,
      'localisation_verifiee', v_b.statut_localisation = 'verifiee',
      'distance_km', round(coalesce(v_distance, null)::numeric, 2)
    ),
    'produits', v_produits,
    'nb_produits', v_nb,
    'publicites', public.biashara_publicites_servir(
                    p_lat, p_lng, v_b.ville_id, null, 2
                  )
  );
end;
$$;

comment on function public.rpc_biashara_boutique(text, double precision, double precision, integer) is
  'Module 19 — Fiche PUBLIQUE d''une boutique (slug partageable) : vitrine, horaires, contacts et produits publiés. Aucune donnée interne.';


-- 10.c FICHE PUBLIQUE D'UN PRODUIT + COMPARAISON DES PRIX.
create or replace function public.rpc_biashara_produit(
  p_publication_id uuid,
  p_lat double precision default null,
  p_lng double precision default null,
  p_limite integer default 12
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_limite integer := least(greatest(coalesce(p_limite, 12), 1), 40);
  v_pub  public.produits_publications;
  v_prod public.produits;
  v_b    public.v_biashara_boutiques;
  v_autres jsonb := '[]'::jsonb;
  v_distance double precision;
  v_q text;
begin
  select * into v_pub from public.produits_publications where id = p_publication_id;
  if v_pub.id is null or not v_pub.publie then
    raise exception 'PRODUIT_INCONNU|Ce produit n''est pas (ou plus) disponible sur Biashara.';
  end if;

  select * into v_prod from public.produits where id = v_pub.produit_id;
  select * into v_b from public.v_biashara_boutiques where espace_id = v_pub.espace_id;

  if v_b.espace_id is null then
    raise exception 'PRODUIT_INCONNU|La boutique qui vend ce produit n''est plus présente sur Biashara.';
  end if;

  v_distance := public.distance_km(p_lat, p_lng, v_b.latitude, v_b.longitude);
  v_q := public.biashara_normaliser(v_prod.nom);

  -- Autres boutiques proposant un produit CORRESPONDANT (même nom normalisé,
  -- sinon même préfixe) : c'est la base de la comparaison des prix.
  select coalesce(jsonb_agg(jsonb_build_object(
           'publication_id', o.publication_id,
           'produit_id',     o.produit_id,
           'nom',            o.nom,
           'prix',           o.prix,
           'unite',          o.unite,
           'disponible',     o.disponible,
           'photo',          o.photo,
           'espace_id',      o.espace_id,
           'boutique_nom',   o.boutique_nom,
           'boutique_slug',  o.boutique_slug,
           'quartier',       o.quartier,
           'ville',          o.ville,
           'telephone',      o.telephone,
           'whatsapp',       o.whatsapp,
           'latitude',       o.latitude,
           'longitude',      o.longitude,
           'distance_km',    o.distance_km
         ) order by o.prix asc, o.distance_km asc nulls last), '[]'::jsonb)
    into v_autres
    from (
      select pb.id as publication_id, p.id as produit_id, p.nom,
             coalesce(pb.prix_public, p.prix_vente) as prix,
             coalesce(nullif(btrim(pb.unite), ''), p.unite_mesure) as unite,
             (pb.disponible and p.quantite > 0) as disponible,
             coalesce(pb.photo_url, p.photo) as photo,
             b.espace_id, b.nom as boutique_nom, b.slug as boutique_slug,
             b.quartier, b.ville, b.telephone, b.whatsapp,
             b.latitude, b.longitude,
             round((case when p_lat is not null and p_lng is not null
                         then public.distance_km(p_lat, p_lng, b.latitude, b.longitude)
                    end)::numeric, 2) as distance_km,
             (case when public.biashara_normaliser(p.nom) = v_q then 0 else 1 end) as rang
        from public.produits_publications pb
        join public.produits p on p.id = pb.produit_id
        join public.v_biashara_boutiques b on b.espace_id = pb.espace_id
       where pb.publie
         and pb.id <> v_pub.id
         and (
           public.biashara_normaliser(p.nom) = v_q
           or public.biashara_normaliser(p.nom) like v_q || '%'
           or v_q like public.biashara_normaliser(p.nom) || '%'
         )
       order by rang, prix asc
       limit v_limite
    ) o;

  return jsonb_build_object(
    'ok', true,
    'produit', jsonb_build_object(
      'publication_id', v_pub.id,
      'produit_id',     v_prod.id,
      'nom',            v_prod.nom,
      'description',    coalesce(nullif(btrim(v_pub.description_courte), ''),
                                 nullif(btrim(v_prod.description), '')),
      'photo',          coalesce(v_pub.photo_url, v_prod.photo),
      'prix',           coalesce(v_pub.prix_public, v_prod.prix_vente),
      'unite',          coalesce(nullif(btrim(v_pub.unite), ''), v_prod.unite_mesure),
      'categorie',      nullif(btrim(v_prod.categorie), ''),
      'disponible',     v_pub.disponible and v_prod.quantite > 0,
      'vendable_au_poids', coalesce(v_prod.vendable_au_poids, false),
      'attributs',      case when v_prod.attributs is null
                                  or v_prod.attributs = '{}'::jsonb
                             then null else v_prod.attributs end
    ),
    'boutique', jsonb_build_object(
      'espace_id',  v_b.espace_id,
      'nom',        v_b.nom,
      'slug',       v_b.slug,
      'type',       v_b.type,
      'logo_url',   v_b.logo_url,
      'adresse',    v_b.adresse,
      'quartier',   v_b.quartier,
      'avenue',     v_b.avenue,
      'point_repere', v_b.point_repere,
      'ville',      v_b.ville,
      'telephone',  v_b.telephone,
      'whatsapp',   v_b.whatsapp,
      'horaires',   v_b.horaires,
      'latitude',   v_b.latitude,
      'longitude',  v_b.longitude,
      'localisation_verifiee', v_b.statut_localisation = 'verifiee',
      'distance_km', round(coalesce(v_distance, null)::numeric, 2)
    ),
    'autres_boutiques', v_autres,
    'publicites', public.biashara_publicites_servir(
                    p_lat, p_lng, v_b.ville_id, v_prod.categorie, 2
                  )
  );
end;
$$;

comment on function public.rpc_biashara_produit(uuid, double precision, double precision, integer) is
  'Module 19 — Fiche PUBLIQUE d''un produit + comparaison des prix entre les boutiques qui le proposent.';


-- 10.d BOUTIQUES LES PLUS PROCHES (page d'accueil publique + carte).
create or replace function public.rpc_biashara_boutiques_proches(
  p_lat      double precision default null,
  p_lng      double precision default null,
  p_ville_id uuid default null,
  p_limite   integer default 12,
  p_rayon_km double precision default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_limite integer := least(greatest(coalesce(p_limite, 12), 1), 60);
  v_liste  jsonb := '[]'::jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object(
           'espace_id', b.espace_id,
           'nom',       b.nom,
           'slug',      b.slug,
           'type',      b.type,
           'logo_url',  b.logo_url,
           'photo_url', b.photo_url,
           'quartier',  b.quartier,
           'adresse',   b.adresse,
           'ville',     b.ville,
           'telephone', b.telephone,
           'whatsapp',  b.whatsapp,
           'latitude',  b.latitude,
           'longitude', b.longitude,
           'localisation_verifiee', b.statut_localisation = 'verifiee',
           'nb_produits', (select count(*) from public.produits_publications pb
                            where pb.espace_id = b.espace_id and pb.publie),
           'distance_km', round(o.distance::numeric, 2)
         ) order by o.distance asc nulls last, b.nom), '[]'::jsonb)
    into v_liste
    from (
      select b0.espace_id,
             public.distance_km(p_lat, p_lng, b0.latitude, b0.longitude) as distance
        from public.v_biashara_boutiques b0
       where (p_ville_id is null or b0.ville_id = p_ville_id)
         and (
           p_rayon_km is null
           or p_lat is null or p_lng is null
           or public.distance_km(p_lat, p_lng, b0.latitude, b0.longitude) <= p_rayon_km
         )
         and exists (
           select 1 from public.produits_publications pb
            where pb.espace_id = b0.espace_id and pb.publie
         )
       order by distance asc nulls last
       limit v_limite
    ) o
    join public.v_biashara_boutiques b on b.espace_id = o.espace_id;

  return jsonb_build_object('ok', true, 'boutiques', v_liste);
end;
$$;

comment on function public.rpc_biashara_boutiques_proches(double precision, double precision, uuid, integer, double precision) is
  'Module 19 — Boutiques participantes les plus proches (ou d''une ville choisie quand le visiteur refuse la géolocalisation).';


-- 10.e CATÉGORIES POPULAIRES + VILLES DISPONIBLES.
create or replace function public.rpc_biashara_categories(
  p_ville_id uuid default null,
  p_limite   integer default 12
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_limite integer := least(greatest(coalesce(p_limite, 12), 1), 40);
  v_liste  jsonb := '[]'::jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object(
           'categorie',   c.categorie,
           'libelle',     c.categorie,
           'nb_produits', c.nb
         ) order by c.nb desc, c.categorie), '[]'::jsonb)
    into v_liste
    from (
      select nullif(btrim(p.categorie), '') as categorie, count(*) as nb
        from public.produits_publications pb
        join public.produits p on p.id = pb.produit_id
        join public.v_biashara_boutiques b on b.espace_id = pb.espace_id
       where pb.publie
         and nullif(btrim(p.categorie), '') is not null
         and (p_ville_id is null or b.ville_id = p_ville_id)
       group by 1
       order by count(*) desc
       limit v_limite
    ) c;

  return jsonb_build_object('ok', true, 'categories', v_liste);
end;
$$;

comment on function public.rpc_biashara_categories(uuid, integer) is
  'Module 19 — Catégories les plus représentées dans le catalogue public (page d''accueil publique).';


create or replace function public.rpc_biashara_villes()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_liste jsonb := '[]'::jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object(
           'id',          v.id,
           'nom',         v.nom,
           'pays',        v.pays,
           'nb_boutiques', s.nb
         ) order by s.nb desc, v.nom), '[]'::jsonb)
    into v_liste
    from (
      select b.ville_id, count(*) as nb
        from public.v_biashara_boutiques b
       where b.ville_id is not null
       group by b.ville_id
    ) s
    join public.villes v on v.id = s.ville_id;

  return jsonb_build_object('ok', true, 'villes', v_liste);
end;
$$;

comment on function public.rpc_biashara_villes() is
  'Module 19 — Villes où des boutiques sont publiées (repli « Rechercher dans une ville » quand le visiteur refuse la géolocalisation).';


-- 10.f ACCUEIL PUBLIC (une seule requête pour la page Welcome).
create or replace function public.rpc_biashara_accueil(
  p_lat      double precision default null,
  p_lng      double precision default null,
  p_ville_id uuid default null,
  p_limite   integer default 8
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_limite integer := least(greatest(coalesce(p_limite, 8), 1), 20);
  v_categories jsonb;
  v_produits jsonb := '[]'::jsonb;
  v_boutiques jsonb;
begin
  v_categories := public.rpc_biashara_categories(p_ville_id, 10) -> 'categories';
  v_boutiques := public.rpc_biashara_boutiques_proches(
                   p_lat, p_lng, p_ville_id, v_limite, null
                 ) -> 'boutiques';

  -- « Produits autour de vous » : les produits publiés les plus proches.
  select coalesce(jsonb_agg(jsonb_build_object(
           'publication_id', o.publication_id,
           'produit_id',     o.produit_id,
           'nom',            o.nom,
           'photo',          o.photo,
           'prix',           o.prix,
           'unite',          o.unite,
           'disponible',     o.disponible,
           'boutique_nom',   o.boutique_nom,
           'boutique_slug',  o.boutique_slug,
           'quartier',       o.quartier,
           'ville',          o.ville,
           'distance_km',    o.distance_km
         ) order by o.distance asc nulls last, o.nom), '[]'::jsonb)
    into v_produits
    from (
      select pb.id as publication_id, p.id as produit_id, p.nom,
             coalesce(pb.photo_url, p.photo) as photo,
             coalesce(pb.prix_public, p.prix_vente) as prix,
             coalesce(nullif(btrim(pb.unite), ''), p.unite_mesure) as unite,
             (pb.disponible and p.quantite > 0) as disponible,
             b.nom as boutique_nom, b.slug as boutique_slug, b.quartier, b.ville,
             public.distance_km(p_lat, p_lng, b.latitude, b.longitude) as distance
        from public.produits_publications pb
        join public.produits p on p.id = pb.produit_id
        join public.v_biashara_boutiques b on b.espace_id = pb.espace_id
       where pb.publie
         and (p_ville_id is null or b.ville_id = p_ville_id)
       order by distance asc nulls last, pb.updated_at desc
       limit v_limite
    ) o;

  return jsonb_build_object(
    'ok', true,
    'categories', coalesce(v_categories, '[]'::jsonb),
    'produits', v_produits,
    'boutiques', coalesce(v_boutiques, '[]'::jsonb),
    'publicites', public.biashara_publicites_servir(p_lat, p_lng, p_ville_id, null, 3)
  );
end;
$$;

comment on function public.rpc_biashara_accueil(double precision, double precision, uuid, integer) is
  'Module 19 — Données de la page d''accueil PUBLIQUE (catégories populaires, produits autour de vous, boutiques proches, publicités séparées).';


-- 10.g PUBLICITÉS À AFFICHER (« PUBLICITÉ » toujours visible).
create or replace function public.biashara_publicites_servir(
  p_lat      double precision default null,
  p_lng      double precision default null,
  p_ville_id uuid default null,
  p_categorie text default null,
  p_limite   integer default 3
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_limite integer := least(greatest(coalesce(p_limite, 3), 1), 10);
  v_liste  jsonb := '[]'::jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object(
           'id',          s.id,
           'titre',       s.titre,
           'message',     s.message,
           'mention',     s.mention,
           'type_contenu', s.type_contenu,
           'image_url',   s.image_url,
           'prix_promo',  s.prix_promo,
           'produit_id',  s.produit_id,
           'publication_id', s.publication_id,
           'espace_id',   s.espace_id,
           'boutique_nom', s.boutique_nom,
           'boutique_slug', s.boutique_slug,
           'quartier',    s.quartier,
           'ville',       s.ville
         ) order by s.vues asc, s.created_at desc), '[]'::jsonb)
    into v_liste
    from (
      select p.id, p.titre, p.message, p.mention, p.type_contenu, p.image_url,
             p.prix_promo, p.produit_id, p.espace_id, p.created_at,
             b.nom as boutique_nom, b.slug as boutique_slug,
             b.quartier, b.ville, b.ville_id,
             coalesce(p.impressions, 0) as vues,
             pb.id as publication_id
        from public.publicites p
        left join public.produits_publications pb
               on pb.produit_id = p.produit_id and pb.publie
        left join public.v_biashara_boutiques b
               on b.espace_id = coalesce(p.espace_id, pb.espace_id)
       where p.statut = 'active'
         and (p.date_debut is null or p.date_debut <= now())
         and (p.date_fin is null or p.date_fin >= now())
         and (p.plafond_impressions is null or p.impressions < p.plafond_impressions)
         -- Ciblage : une campagne SANS cible est visible partout ; sinon elle
         -- n'est servie que si AU MOINS une cible correspond au contexte.
         -- (Le ciblage ne localise jamais le visiteur : on compare seulement
         --  sa ville choisie, la catégorie consultée ou un rayon demandé.)
         and (
           not exists (
             select 1 from public.publicite_cibles c where c.publicite_id = p.id
           )
           or exists (
             select 1 from public.publicite_cibles c
              where c.publicite_id = p.id
                and (
                  (c.type_cible = 'ville'
                   and p_ville_id is not null and c.ville_id = p_ville_id)
                  or (c.type_cible = 'categorie'
                      and p_categorie is not null and btrim(p_categorie) <> ''
                      and public.biashara_normaliser(c.categorie)
                          = public.biashara_normaliser(p_categorie))
                  -- Sans information de quartier côté visiteur, une cible
                  -- « quartier » ne peut pas être évaluée : on ne la bloque pas.
                  or (c.type_cible = 'quartier')
                  or (c.type_cible = 'rayon'
                      and p_lat is not null and p_lng is not null
                      and c.centre_lat is not null and c.centre_lng is not null
                      and c.rayon_km is not null
                      and public.distance_km(p_lat, p_lng, c.centre_lat, c.centre_lng)
                          <= c.rayon_km)
                )
           )
         )
       order by vues asc, p.created_at desc
       limit v_limite
    ) s;

  return v_liste;
end;
$$;

comment on function public.biashara_publicites_servir(double precision, double precision, uuid, text, integer) is
  'Module 19 — Publicités actives correspondant au contexte (ville, catégorie, rayon). Toujours renvoyées séparément des résultats organiques et marquées « PUBLICITÉ ».';


-- 10.h ÉVÉNEMENT ANALYTIQUE (aucune donnée personnelle).
create or replace function public.rpc_biashara_evenement(
  p_type_evenement text,
  p_entite_type    text default null,
  p_entite_id      text default null,
  p_publicite_id   uuid default null,
  p_ville_id       uuid default null,
  p_quartier       text default null,
  p_distance_km    double precision default null,
  p_recherche_id   bigint default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_type  text := lower(btrim(coalesce(p_type_evenement, '')));
  v_cat   text;
  v_owner uuid;
  v_espace uuid;
  v_entite_type text := nullif(btrim(coalesce(p_entite_type, '')), '');
begin
  -- Types autorisés : une chaîne inconnue est refusée (pas de pollution).
  if v_type not in (
    'impression_produit', 'impression_boutique', 'impression_publicite',
    'recherche', 'vue_produit', 'vue_boutique', 'partage', 'clic_publicite',
    'clic_itineraire', 'clic_telephone', 'clic_whatsapp', 'clic_site',
    'conversion'
  ) then
    raise exception 'TYPE_EVENEMENT_INCONNU|Événement inconnu : %.', v_type;
  end if;

  -- Si l'entité est une publication, on récupère la boutique propriétaire.
  if v_entite_type = 'produit' and p_entite_id is not null then
    select pb.owner_id, pb.espace_id
      into v_owner, v_espace
      from public.produits_publications pb
     where pb.id::text = p_entite_id or pb.produit_id::text = p_entite_id
     limit 1;
  elsif v_entite_type = 'boutique' and p_entite_id is not null then
    select (select u.id
              from public.utilisateurs u
             where u.entreprise_id = e.entreprise_id
               and u.parent_id is null
             order by u.created_at
             limit 1),
           e.id
      into v_owner, v_espace
      from public.espaces e
     where e.slug = p_entite_id or e.id::text = p_entite_id
     limit 1;
  end if;

  if p_publicite_id is not null then
    select p.owner_id, coalesce(v_espace, p.espace_id)
      into v_owner, v_espace
      from public.publicites p where p.id = p_publicite_id;
  end if;

  v_cat := public.biashara_categorie_evenement(v_type);

  -- La tranche remplace la distance exacte : le visiteur reste anonyme.
  insert into public.biashara_evenements (
    categorie, type_evenement, entite_type, entite_id, owner_id, espace_id,
    publicite_id, recherche_id, ville_id, quartier, tranche_distance
  ) values (
    v_cat, v_type, v_entite_type, p_entite_id, v_owner, v_espace,
    p_publicite_id, p_recherche_id, p_ville_id,
    nullif(btrim(coalesce(p_quartier, '')), ''),
    public.biashara_tranche_distance(p_distance_km)
  );

  if p_publicite_id is not null then
    if v_type = 'impression_publicite' then
      update public.publicites set impressions = impressions + 1
       where id = p_publicite_id;
      insert into public.publicite_evenements (publicite_id, owner_id, type_evenement,
                                               ville_id, quartier, tranche_distance)
      values (p_publicite_id, v_owner, 'impression', p_ville_id,
              nullif(btrim(coalesce(p_quartier, '')), ''),
              public.biashara_tranche_distance(p_distance_km));
    elsif v_type = 'clic_publicite' then
      update public.publicites set clics = clics + 1
       where id = p_publicite_id;
      insert into public.publicite_evenements (publicite_id, owner_id, type_evenement,
                                               ville_id, quartier, tranche_distance)
      values (p_publicite_id, v_owner, 'clic', p_ville_id,
              nullif(btrim(coalesce(p_quartier, '')), ''),
              public.biashara_tranche_distance(p_distance_km));
    elsif v_type = 'conversion' then
      update public.publicites set conversions = conversions + 1
       where id = p_publicite_id;
      insert into public.publicite_evenements (publicite_id, owner_id, type_evenement,
                                               ville_id, quartier, tranche_distance)
      values (p_publicite_id, v_owner, 'conversion', p_ville_id,
              nullif(btrim(coalesce(p_quartier, '')), ''),
              public.biashara_tranche_distance(p_distance_km));
    end if;
  end if;

  return jsonb_build_object('ok', true, 'categorie', v_cat);
end;
$$;

comment on function public.rpc_biashara_evenement(text, text, text, uuid, uuid, text, double precision, bigint) is
  'Module 19 — Enregistre un événement de visibilité (impression, vue, recherche, itinéraire, appel, WhatsApp, partage, conversion). Aucune donnée personnelle : la distance est stockée en tranche.';


-- ============================================================================
--  11. RPC — ESPACE COMMERÇANT (authentifié, contrôlé par la propriété)
-- ============================================================================

-- 11.a État de la vitrine d'une des MES boutiques (pré-remplissage du
--      formulaire de localisation / présentation).
create or replace function public.rpc_biashara_boutique_etat(
  p_espace_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_moi  uuid := public.mon_proprietaire();
  v_espace uuid := coalesce(p_espace_id, v_moi);
  e      public.espaces;
  v_nb_publies integer := 0;
  v_nb_total   integer := 0;
begin
  if auth.uid() is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour gérer votre vitrine.';
  end if;

  select * into e from public.espaces where id = v_espace;
  if e.id is null then
    raise exception 'ESPACE_INCONNU|Cette boutique est introuvable.';
  end if;

  -- Contrôle d'accès : uniquement le propriétaire de l'espace ou la plateforme.
  if not public.est_plateforme()
     and e.entreprise_id is distinct from (
       select u.entreprise_id from public.utilisateurs u where u.id = auth.uid()
     ) then
    raise exception 'ACCES_REFUSE|Vous n''êtes pas autorisé à gérer cette boutique.';
  end if;

  select count(*) filter (where pb.publie), count(*)
    into v_nb_publies, v_nb_total
    from public.produits_publications pb
   where pb.espace_id = e.id;

  return jsonb_build_object(
    'ok', true,
    'espace_id', e.id,
    'nom', e.nom,
    'type', e.type,
    'visible_publiquement', e.visible_publiquement,
    'slug', e.slug,
    'description_publique', e.description_publique,
    'telephone_public', e.telephone_public,
    'whatsapp', e.whatsapp,
    'horaires', e.horaires,
    'logo_url', e.logo_url,
    'photo_url', e.photo_url,
    'adresse', e.adresse,
    'quartier', e.quartier,
    'avenue', e.avenue,
    'numero', e.numero,
    'point_repere', e.point_repere,
    'latitude', e.latitude,
    'longitude', e.longitude,
    'precision_localisation', e.precision_localisation,
    'statut_localisation', e.statut_localisation,
    'localisation_maj_le', e.localisation_maj_le,
    'ville_id', e.ville_id,
    'ville', (select v.nom from public.villes v where v.id = e.ville_id),
    'nb_produits_publies', v_nb_publies,
    'nb_produits', v_nb_total,
    -- Le patron comprend immédiatement si sa vitrine est visible du public.
    'compte_operationnel', public.biashara_compte_operationnel(e.entreprise_id),
    'visible_effectivement',
      e.visible_publiquement and public.biashara_compte_operationnel(e.entreprise_id),
    'activation_etape',
      (select coalesce(t.activation_etape, 'actif')
         from public.entreprises t where t.id = e.entreprise_id)
  );
end;
$$;

comment on function public.rpc_biashara_boutique_etat(uuid) is
  'Module 19 — État de la vitrine publique d''une boutique du compte (patron uniquement) : localisation, contacts, horaires, nombre d''articles publiés.';


-- 11.b ENREGISTRER LA VITRINE PUBLIQUE + LA LOCALISATION.
--
--  Le commerçant confirme (« Cette position correspond-elle bien à votre
--  boutique ? ») : la confirmation passe `statut_localisation` à 'verifiee'.
--  Sans confirmation, la position reste 'a_verifier' — elle est affichée comme
--  telle et n'améliore pas le score de pertinence.
create or replace function public.rpc_biashara_boutique_enregistrer(
  p_espace_id      uuid default null,
  p_adresse        text default null,
  p_quartier       text default null,
  p_avenue         text default null,
  p_numero         text default null,
  p_point_repere   text default null,
  p_ville_id       uuid default null,
  p_latitude       double precision default null,
  p_longitude      double precision default null,
  p_precision      text default null,
  p_confirmee      boolean default false,
  p_telephone      text default null,
  p_whatsapp       text default null,
  p_horaires       jsonb default null,
  p_description    text default null,
  p_logo_url       text default null,
  p_photo_url      text default null,
  p_visible        boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_moi    uuid := public.mon_proprietaire();
  v_espace uuid := coalesce(p_espace_id, v_moi);
  e        public.espaces;
  v_publier boolean := coalesce(p_visible, false);
  v_statut text;
begin
  if auth.uid() is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour enregistrer votre boutique.';
  end if;

  select * into e from public.espaces where id = v_espace;
  if e.id is null then
    raise exception 'ESPACE_INCONNU|Cette boutique est introuvable.';
  end if;

  if not public.est_plateforme()
     and e.entreprise_id is distinct from (
       select u.entreprise_id from public.utilisateurs u where u.id = auth.uid()
     ) then
    raise exception 'ACCES_REFUSE|Vous n''êtes pas autorisé à modifier cette boutique.';
  end if;

  if p_precision is not null
     and p_precision not in ('gps', 'carte', 'adresse', 'manuelle') then
    raise exception 'POSITION_INVALIDE|Origine de la position inconnue.';
  end if;

  if (p_latitude is null) <> (p_longitude is null) then
    raise exception 'POSITION_INVALIDE|Indiquez la latitude ET la longitude.';
  end if;

  -- Sans position ET sans ville, une boutique ne peut pas être trouvée.
  if v_publier
     and ((p_latitude is null or p_longitude is null)
          and coalesce(p_ville_id, e.ville_id) is null) then
    raise exception 'POSITION_MANQUANTE|Indiquez la position de votre boutique ou choisissez au moins une ville avant de la publier.';
  end if;

  v_statut := case
    when coalesce(p_latitude, e.latitude) is null then 'non_renseignee'
    when coalesce(p_confirmee, false) then 'verifiee'
    else 'a_verifier'
  end;

  update public.espaces
     set adresse              = nullif(btrim(coalesce(p_adresse, adresse)), ''),
         quartier             = nullif(btrim(coalesce(p_quartier, quartier)), ''),
         avenue               = nullif(btrim(coalesce(p_avenue, avenue)), ''),
         numero               = nullif(btrim(coalesce(p_numero, numero)), ''),
         point_repere         = nullif(btrim(coalesce(p_point_repere, point_repere)), ''),
         ville_id             = coalesce(p_ville_id, ville_id),
         -- `coalesce` : un enregistrement partiel (ex. on ne touche qu'aux
         -- horaires) ne doit JAMAIS effacer une position déjà confirmée.
         latitude             = coalesce(p_latitude, latitude),
         longitude            = coalesce(p_longitude, longitude),
         precision_localisation = coalesce(p_precision, precision_localisation),
         statut_localisation  = v_statut,
         telephone_public     = nullif(btrim(coalesce(p_telephone, telephone_public)), ''),
         whatsapp             = nullif(btrim(coalesce(p_whatsapp, whatsapp)), ''),
         horaires             = coalesce(p_horaires, horaires),
         description_publique = nullif(btrim(coalesce(p_description, description_publique)), ''),
         logo_url             = nullif(btrim(coalesce(p_logo_url, logo_url)), ''),
         photo_url            = nullif(btrim(coalesce(p_photo_url, photo_url)), ''),
         visible_publiquement = v_publier,
         updated_at           = now()
   where id = v_espace
   returning * into e;

  -- Journal d'audit (best-effort : jamais bloquant).
  begin
    insert into public.journal_audit (entreprise_id, action, utilisateur_id, details)
    values (
      null, 'BIASHARA_VITRINE', auth.uid(),
      jsonb_build_object(
        'espace_id', v_espace,
        'visible', e.visible_publiquement,
        'statut_localisation', e.statut_localisation,
        'a_position', e.latitude is not null
      )
    );
  exception when others then null;
  end;

  return jsonb_build_object(
    'ok', true,
    'espace_id', e.id,
    'slug', e.slug,
    'visible_publiquement', e.visible_publiquement,
    'statut_localisation', e.statut_localisation,
    'localisation_maj_le', e.localisation_maj_le,
    'url_publique', case when e.slug is not null
                         then '/biashara/boutique/' || e.slug else null end
  );
end;
$$;

comment on function public.rpc_biashara_boutique_enregistrer(uuid, text, text, text, text, text, uuid, double precision, double precision, text, boolean, text, text, jsonb, text, text, text, boolean) is
  'Module 19 — Enregistre la vitrine publique et la localisation d''une boutique (patron). `p_confirmee` = le commerçant a confirmé que la position correspond bien à sa boutique.';


-- 11.c LISTER LES ARTICLES AVEC LEUR ÉTAT DE PUBLICATION.
create or replace function public.rpc_biashara_publications_lister(
  p_espace_id uuid default null,
  p_recherche text default null,
  p_filtre    text default 'tous',
  p_limite    integer default 100,
  p_decalage  integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_moi    uuid := public.mon_proprietaire();
  v_espace uuid := coalesce(p_espace_id, v_moi);
  v_q      text := public.biashara_normaliser(p_recherche);
  v_filtre text := lower(btrim(coalesce(p_filtre, 'tous')));
  v_limite integer := least(greatest(coalesce(p_limite, 100), 1), 300);
  v_decalage integer := greatest(coalesce(p_decalage, 0), 0);
  v_liste  jsonb := '[]'::jsonb;
  v_total  integer := 0;
  v_publies integer := 0;
begin
  if auth.uid() is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour gérer vos publications.';
  end if;

  if v_filtre not in ('tous', 'publies', 'non_publies', 'indisponibles') then
    v_filtre := 'tous';
  end if;

  select count(*),
         count(*) filter (where coalesce(pb.publie, false))
    into v_total, v_publies
    from public.produits p
    left join public.produits_publications pb on pb.produit_id = p.id
   where p.owner_id = v_espace
     and (v_q = '' or public.biashara_normaliser(
            p.nom || ' ' || coalesce(p.categorie, '')) like '%' || v_q || '%')
     and (
       v_filtre = 'tous'
       or (v_filtre = 'publies' and coalesce(pb.publie, false))
       or (v_filtre = 'non_publies' and not coalesce(pb.publie, false))
       or (v_filtre = 'indisponibles' and pb.publie and not pb.disponible)
     );

  select coalesce(jsonb_agg(jsonb_build_object(
           'publication_id', pb.id,
           'produit_id',     p.id,
           'nom',            p.nom,
           'categorie',      nullif(btrim(p.categorie), ''),
           'photo',          coalesce(pb.photo_url, p.photo),
           'prix_vente',     p.prix_vente,
           'prix_public',    pb.prix_public,
           'unite',          coalesce(nullif(btrim(pb.unite), ''), p.unite_mesure),
           'description_courte', pb.description_courte,
           'mots_cles',      pb.mots_cles,
           'publie',         coalesce(pb.publie, false),
           'disponible',     coalesce(pb.disponible, false),
           'stock',          p.quantite,
           'mis_a_jour_le',  pb.updated_at
         ) order by coalesce(pb.publie, false) desc, p.nom), '[]'::jsonb)
    into v_liste
    from public.produits p
    left join public.produits_publications pb on pb.produit_id = p.id
   where p.owner_id = v_espace
     and (v_q = '' or public.biashara_normaliser(
            p.nom || ' ' || coalesce(p.categorie, '')) like '%' || v_q || '%')
     and (
       v_filtre = 'tous'
       or (v_filtre = 'publies' and coalesce(pb.publie, false))
       or (v_filtre = 'non_publies' and not coalesce(pb.publie, false))
       or (v_filtre = 'indisponibles' and pb.publie and not pb.disponible)
     )
   order by coalesce(pb.publie, false) desc, p.nom
   limit v_limite offset v_decalage;

  return jsonb_build_object(
    'ok', true,
    'espace_id', v_espace,
    'total', v_total,
    'nb_publies', v_publies,
    'articles', v_liste
  );
end;
$$;

comment on function public.rpc_biashara_publications_lister(uuid, text, text, integer, integer) is
  'Module 19 — Articles du catalogue d''une boutique du compte avec leur état de publication (publié / non publié / indisponible).';


-- 11.d PUBLIER / DÉPUBLIER UN ARTICLE (avec prix public et texte d'accroche).
create or replace function public.rpc_biashara_publication_enregistrer(
  p_produit_id bigint,
  p_publie     boolean default true,
  p_prix_public double precision default null,
  p_unite      text default null,
  p_description text default null,
  p_photo      text default null,
  p_mots_cles  text default null,
  p_disponible boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_moi    uuid := public.mon_proprietaire();
  v_prod   public.produits;
  v_espace uuid;
  v_id     uuid;
begin
  if auth.uid() is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour publier vos articles.';
  end if;

  select * into v_prod from public.produits where id = p_produit_id;
  if v_prod.id is null then
    raise exception 'PRODUIT_INCONNU|Article introuvable.';
  end if;

  -- Un article n'est publiable que par le propriétaire de son catalogue.
  if v_prod.owner_id is distinct from v_moi then
    raise exception 'ACCES_REFUSE|Cet article n''appartient pas à votre boutique.';
  end if;

  if p_prix_public is not null and p_prix_public <= 0 then
    raise exception 'PRIX_INVALIDE|Le prix public doit être supérieur à zéro.';
  end if;

  v_espace := v_moi;

  insert into public.produits_publications (
    produit_id, owner_id, espace_id, publie, disponible, prix_public, unite,
    description_courte, photo_url, mots_cles
  ) values (
    p_produit_id, v_moi, v_espace, coalesce(p_publie, true),
    coalesce(p_disponible, true), p_prix_public,
    nullif(btrim(coalesce(p_unite, '')), ''),
    nullif(btrim(coalesce(p_description, '')), ''),
    nullif(btrim(coalesce(p_photo, '')), ''),
    nullif(btrim(coalesce(p_mots_cles, '')), '')
  )
  on conflict (produit_id) do update
    set publie             = coalesce(p_publie, public.produits_publications.publie),
        disponible         = coalesce(p_disponible, public.produits_publications.disponible),
        prix_public        = p_prix_public,
        unite              = nullif(btrim(coalesce(p_unite, '')), ''),
        description_courte = nullif(btrim(coalesce(p_description, '')), ''),
        photo_url          = nullif(btrim(coalesce(p_photo, '')), ''),
        mots_cles          = nullif(btrim(coalesce(p_mots_cles, '')), ''),
        espace_id          = v_espace,
        updated_at         = now()
  returning id into v_id;

  return jsonb_build_object(
    'ok', true,
    'publication_id', v_id,
    'produit_id', p_produit_id,
    'publie', coalesce(p_publie, true)
  );
end;
$$;

comment on function public.rpc_biashara_publication_enregistrer(bigint, boolean, double precision, text, text, text, text, boolean) is
  'Module 19 — Publie (ou retire) un article du catalogue public et fixe son prix public, son unité, sa photo et son texte d''accroche.';


-- 11.e PUBLICATION EN LOT (le commerçant prépare plusieurs articles d'un coup).
create or replace function public.rpc_biashara_publication_lot(
  p_produits jsonb,
  p_publie   boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_moi   uuid := public.mon_proprietaire();
  v_item  jsonb;
  v_id    bigint;
  v_ok    integer := 0;
  v_erreurs jsonb := '[]'::jsonb;
begin
  if auth.uid() is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour publier vos articles.';
  end if;

  if p_produits is null or jsonb_typeof(p_produits) <> 'array' then
    raise exception 'DONNEES_INVALIDES|Liste d''articles invalide.';
  end if;

  for v_item in select * from jsonb_array_elements(p_produits) loop
    begin
      v_id := nullif(v_item ->> 'produit_id', '')::bigint;
      if v_id is null then
        v_erreurs := v_erreurs || to_jsonb('Article sans identifiant.'::text);
        continue;
      end if;

      perform public.rpc_biashara_publication_enregistrer(
        v_id,
        p_publie,
        nullif(v_item ->> 'prix_public', '')::double precision,
        v_item ->> 'unite',
        v_item ->> 'description',
        v_item ->> 'photo',
        v_item ->> 'mots_cles',
        coalesce((v_item ->> 'disponible')::boolean, true)
      );
      v_ok := v_ok + 1;
    exception when others then
      v_erreurs := v_erreurs || to_jsonb(sqlerrm);
    end;
  end loop;

  return jsonb_build_object('ok', true, 'nb_traites', v_ok, 'erreurs', v_erreurs);
end;
$$;

comment on function public.rpc_biashara_publication_lot(jsonb, boolean) is
  'Module 19 — Publie ou retire plusieurs articles en une seule opération (les erreurs n''annulent pas le lot).';


-- 11.f « MA VISIBILITÉ BIASHARA » — TABLEAU DE BORD COMPARABLE.
--
--  Quatre niveaux bien DISTINCTS (le cahier des charges l'exige) :
--    VISIBILITÉ = impressions / affichages ;
--    INTÉRÊT     = consultations de fiche et clics ;
--    INTENTION   = itinéraire, appel, WhatsApp, site ;
--    CONVERSION  = achat réellement attribué (jamais déduit d'une visite).
create or replace function public.rpc_biashara_visibilite(
  p_debut  date default null,
  p_fin    date default null,
  p_espace_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_moi    uuid := public.mon_proprietaire();
  v_espace uuid := coalesce(p_espace_id, v_moi);
  v_debut  timestamptz;
  v_fin    timestamptz;
  v_resume jsonb;
  v_types  jsonb := '[]'::jsonb;
  v_jours  jsonb := '[]'::jsonb;
  v_top    jsonb := '[]'::jsonb;
  v_recherches integer := 0;
  v_pub    jsonb := '[]'::jsonb;
begin
  if auth.uid() is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour consulter votre visibilité.';
  end if;

  -- Accès : le patron de l'espace (ou la plateforme).
  if not public.est_plateforme()
     and not exists (
       select 1 from public.espaces e
        where e.id = v_espace
          and e.entreprise_id = (
            select u.entreprise_id from public.utilisateurs u where u.id = auth.uid()
          )
     ) then
    raise exception 'ACCES_REFUSE|Vous n''êtes pas autorisé à consulter cette visibilité.';
  end if;

  v_fin   := coalesce(p_fin, current_date)::timestamptz + interval '1 day';
  v_debut := coalesce(p_debut, current_date - 29)::timestamptz;

  if v_debut >= v_fin then
    v_debut := v_fin - interval '30 days';
  end if;

  select jsonb_build_object(
           'visibilite', count(*) filter (where categorie = 'visibilite'),
           'interet',    count(*) filter (where categorie = 'interet'),
           'intention',  count(*) filter (where categorie = 'intention'),
           'conversion', count(*) filter (where categorie = 'conversion'),
           'total',      count(*)
         )
    into v_resume
    from public.biashara_evenements ev
   where ev.espace_id = v_espace
     and ev.le >= v_debut and ev.le < v_fin;

  select coalesce(jsonb_agg(jsonb_build_object(
           'type_evenement', t.type_evenement,
           'categorie',      t.categorie,
           'nb',             t.nb
         ) order by t.nb desc), '[]'::jsonb)
    into v_types
    from (
      select ev.type_evenement, ev.categorie, count(*) as nb
        from public.biashara_evenements ev
       where ev.espace_id = v_espace
         and ev.le >= v_debut and ev.le < v_fin
       group by 1, 2
    ) t;

  select coalesce(jsonb_agg(jsonb_build_object(
           'jour',       j.jour,
           'visibilite', j.visibilite,
           'interet',    j.interet,
           'intention',  j.intention,
           'conversion', j.conversion
         ) order by j.jour), '[]'::jsonb)
    into v_jours
    from (
      select d.jour::date as jour,
             count(ev.id) filter (where ev.categorie = 'visibilite') as visibilite,
             count(ev.id) filter (where ev.categorie = 'interet')    as interet,
             count(ev.id) filter (where ev.categorie = 'intention')  as intention,
             count(ev.id) filter (where ev.categorie = 'conversion') as conversion
        from generate_series(v_debut::date, (v_fin - interval '1 day')::date,
                             interval '1 day') as d(jour)
        left join public.biashara_evenements ev
               on ev.le >= d.jour and ev.le < d.jour + interval '1 day'
              and ev.espace_id = v_espace
       group by 1
    ) j;

  -- Produits les plus consultés (vues, intentions).
  select coalesce(jsonb_agg(jsonb_build_object(
           'entite_id', t.entite_id,
           'nom',       coalesce(p.nom, 'Article supprimé'),
           'vues',      t.vues,
           'itineraire', t.itineraire,
           'telephone', t.telephone,
           'whatsapp',  t.whatsapp,
           'total',     t.total
         ) order by t.total desc, t.vues desc), '[]'::jsonb)
    into v_top
    from (
      select ev.entite_id,
             count(*) filter (where ev.type_evenement in ('vue_produit', 'impression_produit')) as vues,
             count(*) filter (where ev.type_evenement = 'clic_itineraire') as itineraire,
             count(*) filter (where ev.type_evenement = 'clic_telephone')  as telephone,
             count(*) filter (where ev.type_evenement = 'clic_whatsapp')   as whatsapp,
             count(*) as total
        from public.biashara_evenements ev
       where ev.espace_id = v_espace
         and ev.entite_type = 'produit'
         and ev.le >= v_debut and ev.le < v_fin
       group by 1
       order by count(*) desc
       limit 10
    ) t
    left join public.produits_publications pb
           on pb.id::text = t.entite_id
    left join public.produits p on p.id = pb.produit_id;

  -- Recherches qui ont fait apparaître des articles de la boutique.
  select count(distinct ev.recherche_id)
    into v_recherches
    from public.biashara_evenements ev
   where ev.espace_id = v_espace
     and ev.recherche_id is not null
     and ev.le >= v_debut and ev.le < v_fin;

  -- Publicités de la boutique (préparation commerciale).
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', s.id, 'titre', s.titre, 'statut', s.statut,
           'impressions', s.impressions, 'clics', s.clics,
           'conversions', s.conversions,
           'debut', s.date_debut, 'fin', s.date_fin
         ) order by s.created_at desc), '[]'::jsonb)
    into v_pub
    from (
      select p.id, p.titre, p.statut, p.impressions, p.clics, p.conversions,
             p.date_debut, p.date_fin, p.created_at
        from public.publicites p
       where p.owner_id = v_espace or p.owner_id = auth.uid()
    ) s;

  return jsonb_build_object(
    'ok', true,
    'espace_id', v_espace,
    'debut', v_debut::date,
    'fin', (v_fin - interval '1 day')::date,
    'resume', coalesce(v_resume, jsonb_build_object(
      'visibilite', 0, 'interet', 0, 'intention', 0, 'conversion', 0, 'total', 0)),
    'par_type', v_types,
    'par_jour', v_jours,
    'top_produits', v_top,
    'nb_recherches', v_recherches,
    'publicites', v_pub,
    'note_conversion',
      'La conversion n''est comptée que lorsqu''un achat est réellement attribué à Biashara (code/QR/lien). Une simple consultation n''est jamais considérée comme un achat.'
  );
end;
$$;

comment on function public.rpc_biashara_visibilite(date, date, uuid) is
  'Module 19 — Tableau de bord « Ma visibilité Biashara » : visibilité, intérêt, intention, conversion, série journalière, produits les plus consultés et campagnes.';


-- 11.g LIENS D'ATTRIBUTION (QR / lien / code promotionnel).
create or replace function public.rpc_biashara_attribution_lister(
  p_espace_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_moi uuid := public.mon_proprietaire();
  v_liste jsonb := '[]'::jsonb;
begin
  if auth.uid() is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour gérer vos codes.';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', l.id, 'code', l.code, 'type_lien', l.type_lien,
           'libelle', l.libelle, 'cible_url', l.cible_url,
           'produit_id', l.produit_id, 'actif', l.actif,
           'utilisations', l.utilisations, 'created_at', l.created_at
         ) order by l.created_at desc), '[]'::jsonb)
    into v_liste
    from public.liens_attribution l
   where (l.owner_id = v_moi or l.owner_id = auth.uid())
     and (p_espace_id is null or l.espace_id = p_espace_id);

  return jsonb_build_object('ok', true, 'liens', v_liste);
end;
$$;

create or replace function public.rpc_biashara_attribution_creer(
  p_libelle   text default null,
  p_type_lien text default 'qr',
  p_produit_id bigint default null,
  p_espace_id uuid default null,
  p_cible_url text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_moi  uuid := public.mon_proprietaire();
  v_type text := lower(btrim(coalesce(p_type_lien, 'qr')));
  v_code text;
  v_id   uuid;
  v_i    integer := 0;
begin
  if auth.uid() is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour créer un code.';
  end if;

  if v_type not in ('qr', 'lien', 'code') then
    raise exception 'TYPE_LIEN_INCONNU|Type de lien inconnu.';
  end if;

  if p_produit_id is not null then
    if not exists (
      select 1 from public.produits p
       where p.id = p_produit_id and p.owner_id = v_moi
    ) then
      raise exception 'ACCES_REFUSE|Cet article n''appartient pas à votre boutique.';
    end if;
  end if;

  loop
    v_code := 'BIA-' || upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
    exit when not exists (select 1 from public.liens_attribution l where upper(l.code) = v_code);
    v_i := v_i + 1;
    exit when v_i > 20;
  end loop;

  insert into public.liens_attribution (
    code, owner_id, espace_id, produit_id, type_lien, libelle, cible_url
  ) values (
    v_code, v_moi, coalesce(p_espace_id, v_moi), p_produit_id, v_type,
    nullif(btrim(coalesce(p_libelle, '')), ''),
    nullif(btrim(coalesce(p_cible_url, '')), '')
  )
  returning id into v_id;

  return jsonb_build_object('ok', true, 'id', v_id, 'code', v_code);
end;
$$;

create or replace function public.rpc_biashara_attribution_supprimer(
  p_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_moi uuid := public.mon_proprietaire();
begin
  if auth.uid() is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;

  delete from public.liens_attribution l
   where l.id = p_id
     and (l.owner_id = v_moi or l.owner_id = auth.uid());

  return jsonb_build_object('ok', true);
end;
$$;

comment on function public.rpc_biashara_attribution_creer(text, text, bigint, uuid, text) is
  'Module 19 — Crée un code d''attribution (BIA-XXXXXX) : QR de vitrine, lien de suivi ou code promotionnel.';


-- 11.h CAMPAGNES PUBLICITAIRES (préparation commerciale).
create or replace function public.rpc_biashara_publicite_enregistrer(
  p_id           uuid default null,
  p_titre        text default null,
  p_message      text default null,
  p_type_contenu text default 'produit',
  p_produit_id   bigint default null,
  p_image_url    text default null,
  p_prix_promo   double precision default null,
  p_date_debut   timestamptz default null,
  p_date_fin     timestamptz default null,
  p_budget       double precision default null,
  p_plafond_impressions integer default null,
  p_espace_id    uuid default null,
  p_cibles       jsonb default '[]'::jsonb,
  p_soumettre    boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_moi    uuid := public.mon_proprietaire();
  v_espace uuid := coalesce(p_espace_id, v_moi);
  v_type   text := lower(btrim(coalesce(p_type_contenu, 'produit')));
  v_titre  text := nullif(btrim(coalesce(p_titre, '')), '');
  v_id     uuid;
  v_cible  jsonb;
  v_st     text;
begin
  if auth.uid() is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour gérer vos publicités.';
  end if;

  if v_type not in ('produit', 'boutique', 'promotion', 'offre') then
    raise exception 'TYPE_PUBLICITE_INCONNU|Type de contenu publicitaire inconnu.';
  end if;

  if p_id is null then
    if v_titre is null then
      raise exception 'TITRE_MANQUANT|Donnez un titre à votre annonce.';
    end if;

    insert into public.publicites (
      owner_id, espace_id, titre, message, type_contenu, produit_id, image_url,
      prix_promo, date_debut, date_fin, budget, plafond_impressions, statut
    ) values (
      v_moi, v_espace, v_titre, nullif(btrim(coalesce(p_message, '')), ''),
      v_type, p_produit_id, nullif(btrim(coalesce(p_image_url, '')), ''),
      p_prix_promo, p_date_debut, p_date_fin, p_budget, p_plafond_impressions,
      case when coalesce(p_soumettre, false) then 'soumise' else 'brouillon' end
    )
    returning id, statut into v_id, v_st;

    -- Remplacement complet du ciblage.
    delete from public.publicite_cibles where publicite_id = v_id;
  else
    select p.statut into v_st from public.publicites p
     where p.id = p_id and (p.owner_id = v_moi or p.owner_id = auth.uid());

    if v_st is null then
      raise exception 'PUBLICITE_INCONNUE|Campagne introuvable.';
    end if;

    update public.publicites
       set titre       = coalesce(v_titre, titre),
           message     = nullif(btrim(coalesce(p_message, '')), ''),
           type_contenu = v_type,
           produit_id  = p_produit_id,
           image_url   = nullif(btrim(coalesce(p_image_url, '')), ''),
           prix_promo  = p_prix_promo,
           date_debut  = p_date_debut,
           date_fin    = p_date_fin,
           budget      = p_budget,
           plafond_impressions = p_plafond_impressions,
           espace_id   = v_espace,
           statut      = case when coalesce(p_soumettre, false)
                              then 'soumise' else statut end,
           updated_at  = now()
     where id = p_id
     returning id, statut into v_id, v_st;

    delete from public.publicite_cibles where publicite_id = v_id;
  end if;

  -- Ciblage : ville, quartier, rayon, catégorie.
  if p_cibles is not null and jsonb_typeof(p_cibles) = 'array' then
    for v_cible in select * from jsonb_array_elements(p_cibles) loop
      declare
        v_tc text := lower(btrim(coalesce(v_cible ->> 'type_cible', '')));
      begin
        if v_tc not in ('ville', 'quartier', 'rayon', 'categorie') then
          continue;
        end if;

        insert into public.publicite_cibles (
          publicite_id, type_cible, ville_id, quartier, categorie,
          rayon_km, centre_lat, centre_lng
        ) values (
          v_id, v_tc,
          nullif(v_cible ->> 'ville_id', '')::uuid,
          nullif(btrim(coalesce(v_cible ->> 'quartier', '')), ''),
          nullif(btrim(coalesce(v_cible ->> 'categorie', '')), ''),
          nullif(v_cible ->> 'rayon_km', '')::double precision,
          nullif(v_cible ->> 'centre_lat', '')::double precision,
          nullif(v_cible ->> 'centre_lng', '')::double precision
        );
      end;
    end loop;
  end if;

  return jsonb_build_object('ok', true, 'id', v_id, 'statut', v_st);
end;
$$;

comment on function public.rpc_biashara_publicite_enregistrer(uuid, text, text, text, bigint, text, double precision, timestamptz, timestamptz, double precision, integer, uuid, jsonb, boolean) is
  'Module 19 — Crée ou met à jour une campagne publicitaire (brouillon ou soumise pour validation). Ciblage : ville, quartier, rayon, catégorie.';


create or replace function public.rpc_biashara_publicites_lister(
  p_espace_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_moi uuid := public.mon_proprietaire();
  v_liste jsonb := '[]'::jsonb;
begin
  if auth.uid() is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour gérer vos publicités.';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', s.id, 'titre', s.titre, 'message', s.message,
           'mention', s.mention, 'type_contenu', s.type_contenu,
           'produit_id', s.produit_id, 'image_url', s.image_url,
           'prix_promo', s.prix_promo, 'date_debut', s.date_debut,
           'date_fin', s.date_fin, 'budget', s.budget,
           'plafond_impressions', s.plafond_impressions,
           'statut', s.statut, 'impressions', s.impressions,
           'clics', s.clics, 'conversions', s.conversions,
           'note_moderation', s.note_moderation,
           'created_at', s.created_at,
           'cibles', coalesce((
             select jsonb_agg(jsonb_build_object(
                      'type_cible', c.type_cible, 'ville_id', c.ville_id,
                      'quartier', c.quartier, 'categorie', c.categorie,
                      'rayon_km', c.rayon_km,
                      'centre_lat', c.centre_lat, 'centre_lng', c.centre_lng))
               from public.publicite_cibles c where c.publicite_id = s.id
           ), '[]'::jsonb)
         ) order by s.created_at desc), '[]'::jsonb)
    into v_liste
    from (
      select p.* from public.publicites p
       where p.owner_id = v_moi or p.owner_id = auth.uid()
    ) s;

  return jsonb_build_object(
    'ok', true, 'publicites', v_liste,
    'note', 'Une publicité n''est jamais mélangée aux résultats organiques : elle apparaît dans un emplacement dédié, toujours marquée « PUBLICITÉ ».'
  );
end;
$$;


create or replace function public.rpc_biashara_publicite_statut(
  p_id     uuid,
  p_statut text,
  p_note   text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_moi    uuid := public.mon_proprietaire();
  v_statut text := lower(btrim(coalesce(p_statut, '')));
  v_owner  uuid;
  v_plateforme boolean := public.est_plateforme();
begin
  if auth.uid() is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;

  select p.owner_id into v_owner from public.publicites p where p.id = p_id;
  if v_owner is null then
    raise exception 'PUBLICITE_INCONNUE|Campagne introuvable.';
  end if;

  if not v_plateforme and v_owner is distinct from v_moi and v_owner is distinct from auth.uid() then
    raise exception 'ACCES_REFUSE|Cette campagne ne vous appartient pas.';
  end if;

  -- Le commerçant peut mettre en pause / terminer / soumettre SA campagne.
  -- La plateforme seule active ou refuse une campagne.
  if not v_plateforme and v_statut not in ('brouillon', 'soumise', 'pause', 'terminee') then
    raise exception 'STATUT_REFUSE|Seule la plateforme peut activer ou refuser une campagne.';
  elsif v_plateforme and v_statut not in
        ('brouillon', 'soumise', 'active', 'pause', 'terminee', 'refusee') then
    raise exception 'STATUT_INCONNU|Statut de campagne inconnu.';
  end if;

  update public.publicites
     set statut = v_statut,
         note_moderation = nullif(btrim(coalesce(p_note, '')), ''),
         updated_at = now()
   where id = p_id;

  begin
    insert into public.journal_audit (entreprise_id, action, utilisateur_id, details)
    values (null, 'BIASHARA_PUBLICITE', auth.uid(),
            jsonb_build_object('publicite_id', p_id, 'statut', v_statut));
  exception when others then null;
  end;

  return jsonb_build_object('ok', true, 'statut', v_statut);
end;
$$;

comment on function public.rpc_biashara_publicite_statut(uuid, text, text) is
  'Module 19 — Change le statut d''une campagne : le commerçant soumet / met en pause / termine ; la plateforme active ou refuse.';


-- 11.i MODÉRATION (plateforme) : liste des campagnes soumises.
create or replace function public.rpc_biashara_publicites_moderation(
  p_statut text default 'soumise'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_st text := nullif(lower(btrim(coalesce(p_statut, ''))), '');
  v_liste jsonb := '[]'::jsonb;
begin
  if not public.est_plateforme() then
    raise exception 'ACCES_REFUSE|Réservé à l''administration de la plateforme.';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', s.id, 'titre', s.titre, 'message', s.message,
           'type_contenu', s.type_contenu, 'statut', s.statut,
           'ville', s.ville, 'boutique', s.boutique,
           'impressions', s.impressions, 'clics', s.clics,
           'conversions', s.conversions,
           'created_at', s.created_at
         ) order by s.created_at desc), '[]'::jsonb)
    into v_liste
    from (
      select p.id, p.titre, p.message, p.type_contenu, p.statut,
             p.impressions, p.clics, p.conversions, p.created_at,
             (select v.nom from public.villes v where v.id = e.ville_id) as ville,
             e.nom as boutique
        from public.publicites p
        left join public.espaces e on e.id = p.espace_id
       where v_st is null or p.statut = v_st
    ) s;

  return jsonb_build_object('ok', true, 'publicites', v_liste);
end;
$$;

comment on function public.rpc_biashara_publicites_moderation(text) is
  'Module 19 — Modération des campagnes publicitaires (personnel plateforme uniquement).';


-- ============================================================================
--  12. PERMISSIONS — PAGES `publications`, `visibilite`, `publicites`
-- ============================================================================
--  La matrice Dart reste l'autorité pour l'interface ; on tient la matrice SQL
--  à jour pour rester cohérent avec `public.a_permission(...)`.
--  Ces trois pages concernent le PROPRIÉTAIRE (le patron seul gère sa vitrine,
--  ses publications et ses campagnes). Les RPC vérifient de toute façon la
--  PROPRIÉTÉ de la boutique, jamais le seul rôle.

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
    'publications', 'visibilite', 'publicites'
  ];
$$;

comment on function public.pages_permissions() is
  'Liste officielle des pages de permission (Module 4, + securite M12, + assistant_ia M13, + hôtel C2, + restaurant C3, + salle des fêtes C4, + boulangerie C5, + marketplace M19).';

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
  -- SUPER_ADMIN : toutes les pages, toutes les actions.
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
                         'notifications'];
      v_actions := array['voir', 'creer', 'modifier'];

    when 'FINANCE_LAPERLE' then
      v_pages   := array['dashboard', 'abonnements', 'paiements', 'finance',
                         'rapports', 'audit', 'notifications'];
      v_actions := array['voir', 'creer', 'valider'];

    when 'SUPPORT' then
      v_pages   := array['dashboard', 'assistance', 'entreprises', 'utilisateurs',
                         'abonnements', 'notifications'];
      v_actions := array['voir'];

    when 'PROPRIETAIRE' then
      v_pages   := array['dashboard', 'ventes', 'caisse', 'scanner', 'panier',
                         'articles', 'qr_codes', 'stock', 'clients', 'fournisseurs',
                         'finance', 'depenses', 'collaborateurs', 'rapports',
                         'abonnements', 'audit', 'assistant_ia', 'parametres',
                         -- 🏨 MODULE 16 C2 — hôtel (tout).
                         'chambres', 'reservations', 'reception',
                         -- 🍽️ MODULE 16 C3 — restaurant (tout).
                         'tables', 'commandes', 'cuisine',
                         -- 🎉 MODULE 16 C4 — salle des fêtes (tout).
                         'salles', 'evenements',
                         -- 🥖 MODULE 16 C5 — boulangerie (tout).
                         'production',
                         -- 🛒 MODULE 19 — marketplace (le patron gère sa vitrine).
                         'publications', 'visibilite', 'publicites'];
      v_actions := public.actions_permissions();

    when 'VENDEUR' then
      v_pages   := array['ventes', 'caisse', 'scanner', 'panier', 'assistant_ia',
                         'chambres', 'reservations', 'reception',
                         'tables', 'commandes', 'cuisine',
                         'salles', 'evenements',
                         'production'];
      v_actions := array['voir', 'creer'];

    when 'MAGASINIER' then
      v_pages   := array['stock', 'articles', 'qr_codes', 'rapports',
                         'assistant_ia', 'production'];
      v_actions := array['voir'];

    when 'COMPTABLE_ENTREPRISE' then
      v_pages   := array['dashboard', 'ventes', 'caisse', 'depenses', 'rapports',
                         'finance', 'assistant_ia', 'parametres'];
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
    when 'COMPTABLE_ENTREPRISE' then v_result
      || jsonb_build_object('depenses',     to_jsonb(array['voir', 'creer', 'valider']))
      || jsonb_build_object('rapports',     to_jsonb(array['voir', 'valider']))
      || jsonb_build_object('assistant_ia', to_jsonb(array['voir', 'creer']))
    when 'VENDEUR' then v_result
      || jsonb_build_object('chambres', to_jsonb(array['voir']))
      || jsonb_build_object('tables',   to_jsonb(array['voir']))
      || jsonb_build_object('salles',   to_jsonb(array['voir']))
    else v_result
  end;

  return v_result;
end;
$$;

comment on function public.permissions_defaut(text) is
  'Matrice des permissions par défaut (Module 4, + M12, + M13, + hôtel C2, + restaurant C3, + salle des fêtes C4, + boulangerie C5, + marketplace M19 pour le PROPRIÉTAIRE).';


-- ============================================================================
--  13. DROITS & SÉCURITÉ
-- ============================================================================

-- 13.a Aucun accès DIRECT aux tables du module pour les visiteurs. Tout ce qui
--      est public passe par les RPC `security definer` ci-dessus.
revoke all on public.produits_publications from public;
revoke all on public.produits_publications from anon;
revoke insert, update, delete, truncate on public.produits_publications from authenticated;
grant select on public.produits_publications to authenticated;

revoke all on public.recherches_publiques from public;
revoke all on public.recherches_publiques from anon;
revoke all on public.recherches_publiques from authenticated;

revoke all on public.biashara_evenements from public;
revoke all on public.biashara_evenements from anon;
revoke insert, update, delete, truncate on public.biashara_evenements from authenticated;
grant select on public.biashara_evenements to authenticated;

revoke all on public.publicites from public;
revoke all on public.publicites from anon;
revoke insert, update, delete, truncate on public.publicites from authenticated;
grant select on public.publicites to authenticated;

revoke all on public.publicite_cibles from public;
revoke all on public.publicite_cibles from anon;
revoke insert, update, delete, truncate on public.publicite_cibles from authenticated;
grant select on public.publicite_cibles to authenticated;

revoke all on public.publicite_evenements from public;
revoke all on public.publicite_evenements from anon;
revoke insert, update, delete, truncate on public.publicite_evenements from authenticated;
grant select on public.publicite_evenements to authenticated;

revoke all on public.liens_attribution from public;
revoke all on public.liens_attribution from anon;
revoke insert, update, delete, truncate on public.liens_attribution from authenticated;
grant select on public.liens_attribution to authenticated;

revoke all on public.v_biashara_boutiques from public;
revoke all on public.v_biashara_boutiques from anon;
revoke all on public.v_biashara_boutiques from authenticated;

-- 13.b RPC PUBLIQUES — sans compte (anon) comme avec compte.
revoke all on function public.distance_km(double precision, double precision, double precision, double precision) from public;
grant execute on function public.distance_km(double precision, double precision, double precision, double precision) to anon, authenticated;

revoke all on function public.biashara_tranche_distance(double precision) from public;
grant execute on function public.biashara_tranche_distance(double precision) to anon, authenticated;

revoke all on function public.biashara_normaliser(text) from public;
grant execute on function public.biashara_normaliser(text) to anon, authenticated;

revoke all on function public.biashara_slugifier(text) from public;
grant execute on function public.biashara_slugifier(text) to anon, authenticated;

revoke all on function public.biashara_categorie_evenement(text) from public;
grant execute on function public.biashara_categorie_evenement(text) to anon, authenticated;

revoke all on function public.biashara_compte_operationnel(uuid) from public;
grant execute on function public.biashara_compte_operationnel(uuid) to authenticated;

revoke all on function public.rpc_biashara_rechercher(text, double precision, double precision, uuid, text, text, integer, integer, boolean) from public;
grant execute on function public.rpc_biashara_rechercher(text, double precision, double precision, uuid, text, text, integer, integer, boolean) to anon, authenticated;

revoke all on function public.rpc_biashara_boutique(text, double precision, double precision, integer) from public;
grant execute on function public.rpc_biashara_boutique(text, double precision, double precision, integer) to anon, authenticated;

revoke all on function public.rpc_biashara_produit(uuid, double precision, double precision, integer) from public;
grant execute on function public.rpc_biashara_produit(uuid, double precision, double precision, integer) to anon, authenticated;

revoke all on function public.rpc_biashara_boutiques_proches(double precision, double precision, uuid, integer, double precision) from public;
grant execute on function public.rpc_biashara_boutiques_proches(double precision, double precision, uuid, integer, double precision) to anon, authenticated;

revoke all on function public.rpc_biashara_categories(uuid, integer) from public;
grant execute on function public.rpc_biashara_categories(uuid, integer) to anon, authenticated;

revoke all on function public.rpc_biashara_villes() from public;
grant execute on function public.rpc_biashara_villes() to anon, authenticated;

revoke all on function public.rpc_biashara_accueil(double precision, double precision, uuid, integer) from public;
grant execute on function public.rpc_biashara_accueil(double precision, double precision, uuid, integer) to anon, authenticated;

revoke all on function public.biashara_publicites_servir(double precision, double precision, uuid, text, integer) from public;
grant execute on function public.biashara_publicites_servir(double precision, double precision, uuid, text, integer) to anon, authenticated;

revoke all on function public.rpc_biashara_evenement(text, text, text, uuid, uuid, text, double precision, bigint) from public;
grant execute on function public.rpc_biashara_evenement(text, text, text, uuid, uuid, text, double precision, bigint) to anon, authenticated;

-- 13.c RPC COMMERÇANT — compte obligatoire (le `auth.uid()` est revérifié
--      DANS chaque fonction ; on n'accorde jamais `anon`).
revoke all on function public.rpc_biashara_boutique_etat(uuid) from public;
revoke all on function public.rpc_biashara_boutique_etat(uuid) from anon;
grant execute on function public.rpc_biashara_boutique_etat(uuid) to authenticated;

revoke all on function public.rpc_biashara_boutique_enregistrer(uuid, text, text, text, text, text, uuid, double precision, double precision, text, boolean, text, text, jsonb, text, text, text, boolean) from public;
revoke all on function public.rpc_biashara_boutique_enregistrer(uuid, text, text, text, text, text, uuid, double precision, double precision, text, boolean, text, text, jsonb, text, text, text, boolean) from anon;
grant execute on function public.rpc_biashara_boutique_enregistrer(uuid, text, text, text, text, text, uuid, double precision, double precision, text, boolean, text, text, jsonb, text, text, text, boolean) to authenticated;

revoke all on function public.rpc_biashara_publications_lister(uuid, text, text, integer, integer) from public;
revoke all on function public.rpc_biashara_publications_lister(uuid, text, text, integer, integer) from anon;
grant execute on function public.rpc_biashara_publications_lister(uuid, text, text, integer, integer) to authenticated;

revoke all on function public.rpc_biashara_publication_enregistrer(bigint, boolean, double precision, text, text, text, text, boolean) from public;
revoke all on function public.rpc_biashara_publication_enregistrer(bigint, boolean, double precision, text, text, text, text, boolean) from anon;
grant execute on function public.rpc_biashara_publication_enregistrer(bigint, boolean, double precision, text, text, text, text, boolean) to authenticated;

revoke all on function public.rpc_biashara_publication_lot(jsonb, boolean) from public;
revoke all on function public.rpc_biashara_publication_lot(jsonb, boolean) from anon;
grant execute on function public.rpc_biashara_publication_lot(jsonb, boolean) to authenticated;

revoke all on function public.rpc_biashara_visibilite(date, date, uuid) from public;
revoke all on function public.rpc_biashara_visibilite(date, date, uuid) from anon;
grant execute on function public.rpc_biashara_visibilite(date, date, uuid) to authenticated;

revoke all on function public.rpc_biashara_attribution_lister(uuid) from public;
revoke all on function public.rpc_biashara_attribution_lister(uuid) from anon;
grant execute on function public.rpc_biashara_attribution_lister(uuid) to authenticated;

revoke all on function public.rpc_biashara_attribution_creer(text, text, bigint, uuid, text) from public;
revoke all on function public.rpc_biashara_attribution_creer(text, text, bigint, uuid, text) from anon;
grant execute on function public.rpc_biashara_attribution_creer(text, text, bigint, uuid, text) to authenticated;

revoke all on function public.rpc_biashara_attribution_supprimer(uuid) from public;
revoke all on function public.rpc_biashara_attribution_supprimer(uuid) from anon;
grant execute on function public.rpc_biashara_attribution_supprimer(uuid) to authenticated;

revoke all on function public.rpc_biashara_publicite_enregistrer(uuid, text, text, text, bigint, text, double precision, timestamptz, timestamptz, double precision, integer, uuid, jsonb, boolean) from public;
revoke all on function public.rpc_biashara_publicite_enregistrer(uuid, text, text, text, bigint, text, double precision, timestamptz, timestamptz, double precision, integer, uuid, jsonb, boolean) from anon;
grant execute on function public.rpc_biashara_publicite_enregistrer(uuid, text, text, text, bigint, text, double precision, timestamptz, timestamptz, double precision, integer, uuid, jsonb, boolean) to authenticated;

revoke all on function public.rpc_biashara_publicites_lister(uuid) from public;
revoke all on function public.rpc_biashara_publicites_lister(uuid) from anon;
grant execute on function public.rpc_biashara_publicites_lister(uuid) to authenticated;

revoke all on function public.rpc_biashara_publicite_statut(uuid, text, text) from public;
revoke all on function public.rpc_biashara_publicite_statut(uuid, text, text) from anon;
grant execute on function public.rpc_biashara_publicite_statut(uuid, text, text) to authenticated;

revoke all on function public.rpc_biashara_publicites_moderation(text) from public;
revoke all on function public.rpc_biashara_publicites_moderation(text) from anon;
grant execute on function public.rpc_biashara_publicites_moderation(text) to authenticated;


-- ============================================================================
--  14. BUCKET « boutiques » — LOGOS & PHOTOS DE DEVANTURE
-- ============================================================================
--  Mêmes règles que le bucket « articles » (module 5) : lecture publique,
--  écriture réservée au dossier de l'utilisateur connecté.

insert into storage.buckets (id, name, public)
values ('boutiques', 'boutiques', true)
on conflict (id) do nothing;

drop policy if exists "boutiques_storage_lecture" on storage.objects;
create policy "boutiques_storage_lecture" on storage.objects
  for select to public
  using (bucket_id = 'boutiques');

drop policy if exists "boutiques_storage_ajout" on storage.objects;
create policy "boutiques_storage_ajout" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'boutiques'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "boutiques_storage_maj" on storage.objects;
create policy "boutiques_storage_maj" on storage.objects
  for update to authenticated
  using (
    bucket_id = 'boutiques'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'boutiques'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "boutiques_storage_suppression" on storage.objects;
create policy "boutiques_storage_suppression" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'boutiques'
    and (storage.foldername(name))[1] = auth.uid()::text
  );


-- ============================================================================
--  15. VÉRIFICATIONS (résultats visibles dans le SQL Editor)
-- ============================================================================

-- 15.a Les 7 tables du module existent (attendu : 7).
select count(*) as tables_marketplace
  from information_schema.tables
 where table_schema = 'public'
   and table_name in (
     'produits_publications', 'recherches_publiques', 'biashara_evenements',
     'publicites', 'publicite_cibles', 'publicite_evenements',
     'liens_attribution'
   );

-- 15.b Colonnes de géolocalisation présentes (attendu : 6).
select count(*) as colonnes_geo
  from information_schema.columns
 where table_schema = 'public' and table_name = 'espaces'
   and column_name in ('latitude', 'longitude', 'adresse', 'quartier',
                       'point_repere', 'statut_localisation');

-- 15.c Les nouvelles pages de permission sont déclarées (attendu : true).
select position('publications' in array_to_string(public.pages_permissions(), ',')) > 0
       as page_publications;

-- 15.d Matrice PROPRIÉTAIRE (attendu : true).
select (public.permissions_defaut('PROPRIETAIRE') ? 'visibilite') as proprio_visibilite,
       (public.permissions_defaut('VENDEUR') ? 'publications')       as vendeur_publications;

-- 15.e Distance entre Lubumbashi (-11.6609, 27.4794) et le centre (0 km) ;
--      test de la fonction Haversine (attendu ≈ 0).
select round(public.distance_km(-11.6609, 27.4794, -11.6609, 27.4794)::numeric, 3) as distance_zero;

-- 15.f Exemples d'appel (à exécuter une fois la vitrine d'une boutique remplie) :
--     select public.rpc_biashara_accueil(-11.6609, 27.4794, null, 8);
--     select public.rpc_biashara_rechercher('riz', -11.6609, 27.4794, null, 'pertinence', null, 20, 0, true);
--     select public.rpc_biashara_rechercher('riz', null, null, (select id from public.villes limit 1), 'prix', null, 20, 0, false);
--     select public.rpc_biashara_boutique('<slug>', -11.6609, 27.4794);
--     select public.rpc_biashara_boutique_etat();          -- compte connecté
--     select public.rpc_biashara_publications_lister(null, null, 'tous', 50, 0);
--     select public.rpc_biashara_visibilite(null, null, null);
--     select public.rpc_biashara_evenement('vue_boutique', 'boutique', '<slug>', null, null, 'Katuba', 1.4, null);

-- ============================================================================
--  FIN — Module 19 (marketplace local géolocalisé).
--
--  L'application (version suivante) apporte :
--    • la page publique « Biashara — Trouvez ce dont vous avez besoin près de
--      vous » (accessible SANS compte) ;
--    • la recherche publique (produit → prix → boutique → distance) ;
--    • la comparaison des prix entre boutiques ;
--    • la fiche boutique partageable et la fiche produit ;
--    • la carte interactive des boutiques proches ;
--    • l'espace commerçant : localisation guidée (ma position / carte /
--      adresse + confirmation), publications du catalogue, tableau de bord
--      « Ma visibilité Biashara » et préparation des campagnes publicitaires.
-- ============================================================================
