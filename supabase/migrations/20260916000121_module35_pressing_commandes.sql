-- ============================================================================
--  biashara_yangu — MODULE 35 : PRESSING & BLANCHISSERIE
--  ÉTAPE 2/4 — DÉPÔTS, VÊTEMENTS ET SUIVI DU TRAITEMENT
--  ---------------------------------------------------------------------------
--  PRINCIPE MÉTIER (il guide TOUTE la conception ci-dessous)
--    Un pressing ne vend pas : il REÇOIT des biens qui appartiennent à ses
--    clients, en prend la responsabilité, les traite, et doit pouvoir
--    PROUVER leur restitution. Un vêtement n'est donc PAS une marchandise :
--    c'est une ligne de dossier, suivie individuellement, avec son état au
--    dépôt, ses défauts constatés, son étape de traitement et sa remise.
--
--  CE QUE CE SCRIPT AJOUTE
--    1. pressing_etapes        → les étapes de traitement (personnalisables)
--    2. pressing_compteurs     → numérotation atomique PR-AAAA-NNNNNN
--    3. pressing_commandes     → le dossier de dépôt (client, dates, totaux,
--                                jeton QR non devinable, statut calculé)
--    4. pressing_lignes        → UNE ligne = UN vêtement (ou un lot identique)
--                                avec catégorie, prestation, état, défauts,
--                                prix figé à la date du dépôt
--    5. pressing_ligne_etapes  → historique chronologique (qui, quand, quoi)
--    6. pressing_paiements     → encaissements (créés ici, enrichis en 0122)
--    7. Les RPC :
--         pressing_depot_creer, pressing_commandes_lister,
--         pressing_commande_fiche, pressing_commande_par_qr,
--         pressing_etapes_lister/enregistrer,
--         pressing_ligne_avancer, pressing_lignes_avancer_lot,
--         pressing_controle_qualite, pressing_commande_annuler,
--         pressing_qr_regenerer, pressing_amorcer_etapes
--
--  RÈGLES APPLIQUÉES
--    • Le PRIX est figé au dépôt (copie dans la ligne) : modifier le
--      catalogue demain ne change JAMAIS une commande passée.
--    • Un avoir/annulation ne supprime rien : la commande passe ANNULEE.
--    • Le statut de la commande est CALCULÉ à partir des lignes
--      (3 prêts / 2 en repassage ≠ commande terminée).
--    • Le QR contient un JETON ALÉATOIRE (64 hex), jamais un identifiant
--      de la base ; il est régénérable et chaque régénération est tracée.
--    • Tout est isolé par entreprise (RLS + contrôle dans chaque RPC).
--
--  ⚠️ IDEMPOTENT — peut être rejoué. Aucune table existante modifiée.
--  📌 OÙ L'EXÉCUTER : éditeur SQL de Supabase.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);


-- ============================================================================
--  1. LES ÉTAPES DE TRAITEMENT (personnalisables par le propriétaire)
-- ============================================================================

create table if not exists public.pressing_etapes (
  id            uuid primary key default gen_random_uuid(),
  entreprise_id uuid not null,
  code          text not null,
  libelle       text not null,
  ordre         integer not null default 100,
  -- `est_finale` = l'étape qui rend le vêtement remis­able (PRÊT).
  est_finale    boolean not null default false,
  actif         boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create unique index if not exists idx_pressing_etapes_code
  on public.pressing_etapes (entreprise_id, code);

comment on table public.pressing_etapes is
  'Module 35 — étapes de traitement d''un pressing (déposé, lavage, repassage, contrôle…). Le propriétaire peut les renommer, les réordonner ou en ajouter.';


-- 1.1 Le pipeline par défaut.
--     ⚠️ Aucune étape n'est IMPOSÉE : on ne les crée que si le pressing
--        n'en a encore aucune.
create or replace function public.pressing_amorcer_etapes()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ent uuid := public.pressing_entreprise();
  v_nb  integer;
begin
  if auth.uid() is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;
  if not (public.peut('pressing_atelier', 'modifier')
          or public.peut('pressing_depots', 'modifier')
          or public.est_plateforme()) then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de configurer l''atelier.';
  end if;

  select count(*) into v_nb
    from public.pressing_etapes where entreprise_id = v_ent;

  if v_nb = 0 then
    insert into public.pressing_etapes
      (entreprise_id, code, libelle, ordre, est_finale)
    values
      (v_ent, 'DEPOSE',          'Déposé',              10, false),
      (v_ent, 'PRETRAITEMENT',   'Pré-traitement',      20, false),
      (v_ent, 'LAVAGE',          'Lavage',              30, false),
      (v_ent, 'SECHAGE',         'Séchage',             40, false),
      (v_ent, 'NETTOYAGE_SEC',   'Nettoyage à sec',     50, false),
      (v_ent, 'DETACHAGE',       'Détachage',           60, false),
      (v_ent, 'REPASSAGE',       'Repassage',           70, false),
      (v_ent, 'CONTROLE_QUALITE','Contrôle qualité',    80, false),
      (v_ent, 'PRET',            'Prêt à récupérer',    90, true),
      (v_ent, 'RETRAITEMENT',    'À retraiter',        100, false)
    on conflict do nothing;
  end if;

  return public.pressing_etapes_lister();
end;
$$;

comment on function public.pressing_amorcer_etapes() is
  'Module 35 — crée le pipeline de traitement par défaut si le pressing n''a encore aucune étape.';

revoke all on function public.pressing_amorcer_etapes() from public, anon;
grant execute on function public.pressing_amorcer_etapes() to authenticated;


create or replace function public.pressing_etapes_lister()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_ent uuid := public.pressing_entreprise();
  v_res jsonb;
begin
  if auth.uid() is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', e.id,
           'code', e.code,
           'libelle', e.libelle,
           'ordre', e.ordre,
           'est_finale', e.est_finale,
           'actif', e.actif
         ) order by e.ordre, e.code), '[]'::jsonb)
    into v_res
    from public.pressing_etapes e
   where e.entreprise_id = v_ent;

  return v_res;
end;
$$;

comment on function public.pressing_etapes_lister() is
  'Module 35 — étapes de traitement du pressing, dans l''ordre.';

revoke all on function public.pressing_etapes_lister() from public, anon;
grant execute on function public.pressing_etapes_lister() to authenticated;


create or replace function public.pressing_etape_enregistrer(
  p_id      uuid,
  p_code    text,
  p_libelle text,
  p_ordre   integer default 100,
  p_finale  boolean default false,
  p_actif   boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ent  uuid := public.pressing_entreprise();
  v_id   uuid;
  v_code text := upper(regexp_replace(btrim(coalesce(p_code, '')), '[^A-Za-z0-9_]', '_', 'g'));
begin
  if auth.uid() is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;
  if not (public.peut('pressing_atelier', 'modifier')
          or public.peut('pressing_depots', 'modifier')
          or public.est_plateforme()) then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de configurer l''atelier.';
  end if;
  if v_code = '' then
    raise exception 'CODE_VIDE|Indiquez un code d''étape.';
  end if;
  if btrim(coalesce(p_libelle, '')) = '' then
    raise exception 'LIBELLE_VIDE|Indiquez le nom de l''étape.';
  end if;

  if p_id is null then
    insert into public.pressing_etapes
      (entreprise_id, code, libelle, ordre, est_finale, actif)
    values
      (v_ent, v_code, btrim(p_libelle), coalesce(p_ordre, 100),
       coalesce(p_finale, false), coalesce(p_actif, true))
    returning id into v_id;
  else
    update public.pressing_etapes
       set code = v_code,
           libelle = btrim(p_libelle),
           ordre = coalesce(p_ordre, ordre),
           est_finale = coalesce(p_finale, est_finale),
           actif = coalesce(p_actif, actif),
           updated_at = now()
     where id = p_id and entreprise_id = v_ent
     returning id into v_id;

    if v_id is null then
      raise exception 'INTROUVABLE|Cette étape n''existe pas.';
    end if;
  end if;

  return jsonb_build_object('ok', true, 'id', v_id, 'code', v_code);
exception
  when unique_violation then
    raise exception 'DOUBLON|Une étape porte déjà ce code.';
end;
$$;

comment on function public.pressing_etape_enregistrer(uuid, text, text, integer, boolean, boolean) is
  'Module 35 — crée ou modifie une étape de traitement.';

revoke all on function public.pressing_etape_enregistrer(uuid, text, text, integer, boolean, boolean)
  from public, anon;
grant execute on function public.pressing_etape_enregistrer(uuid, text, text, integer, boolean, boolean)
  to authenticated;


-- ============================================================================
--  2. NUMÉROTATION DES COMMANDES — PR-AAAA-NNNNNN
-- ============================================================================

create table if not exists public.pressing_compteurs (
  entreprise_id uuid not null,
  annee         integer not null,
  dernier       integer not null default 0,
  primary key (entreprise_id, annee)
);

comment on table public.pressing_compteurs is
  'Module 35 — compteur annuel des numéros de commande de pressing (PR-AAAA-NNNNNN).';

revoke all on public.pressing_compteurs from authenticated, anon;


create or replace function public.pressing_prochain_numero(
  p_entreprise uuid,
  p_annee      integer default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_annee   integer := coalesce(p_annee, extract(year from now())::integer);
  v_dernier integer;
begin
  insert into public.pressing_compteurs (entreprise_id, annee, dernier)
  values (p_entreprise, v_annee, 1)
  on conflict (entreprise_id, annee)
  do update set dernier = public.pressing_compteurs.dernier + 1
  returning dernier into v_dernier;

  return 'PR-' || v_annee::text || '-' || lpad(v_dernier::text, 6, '0');
end;
$$;

comment on function public.pressing_prochain_numero(uuid, integer) is
  'Module 35 — renvoie le prochain numéro « PR-AAAA-NNNNNN » du pressing (atomique).';

revoke all on function public.pressing_prochain_numero(uuid, integer) from public, anon;
grant execute on function public.pressing_prochain_numero(uuid, integer) to authenticated;


-- ============================================================================
--  3. LES COMMANDES (DOSSIERS DE DÉPÔT)
-- ============================================================================

create table if not exists public.pressing_commandes (
  id                 uuid primary key default gen_random_uuid(),
  entreprise_id      uuid not null,
  numero             text not null,
  client_id          uuid references public.pressing_clients (id) on delete set null,
  -- Copie du client au moment du dépôt (une fiche modifiée ou supprimée ne
  -- doit pas réécrire l'histoire).
  client_nom         text,
  client_telephone   text,
  statut             text not null default 'EN_TRAITEMENT',
  urgence            boolean not null default false,
  date_depot         timestamptz not null default now(),
  date_prevue        timestamptz,
  devise             text not null default 'CDF',
  -- Montants figés au dépôt.
  total              numeric(14, 2) not null default 0,
  remise             numeric(14, 2) not null default 0,
  supplement         numeric(14, 2) not null default 0,
  montant_paye       numeric(14, 2) not null default 0,
  observations       text,
  -- 🔐 Jeton du QR code : aléatoire, non devinable, jamais un identifiant.
  qr_token           text not null,
  qr_version         integer not null default 1,
  qr_regenere_le     timestamptz,
  qr_regenere_par    uuid,
  -- Clé d'idempotence du mode hors ligne : rejouer un dépôt ne le duplique pas.
  reference_locale   text,
  cree_par           uuid,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  annule_le          timestamptz,
  annule_par         uuid,
  motif_annulation   text,
  constraint chk_pressing_commande_statut check (statut in (
    'EN_TRAITEMENT', 'PRETE', 'PARTIELLEMENT_REMISE', 'REMISE', 'ANNULEE'
  ))
);

create unique index if not exists idx_pressing_commandes_numero
  on public.pressing_commandes (entreprise_id, numero);

create unique index if not exists idx_pressing_commandes_qr
  on public.pressing_commandes (qr_token);

create unique index if not exists idx_pressing_commandes_ref_locale
  on public.pressing_commandes (entreprise_id, reference_locale)
  where reference_locale is not null;

create index if not exists idx_pressing_commandes_date
  on public.pressing_commandes (entreprise_id, date_depot desc);

create index if not exists idx_pressing_commandes_client
  on public.pressing_commandes (client_id)
  where client_id is not null;

comment on table public.pressing_commandes is
  'Module 35 — dossier de dépôt d''un client (numero PR-AAAA-NNNNNN, totaux figés, jeton QR, statut calculé à partir des lignes).';


-- ============================================================================
--  4. LES VÊTEMENTS DÉPOSÉS (une ligne = un vêtement identifiable)
-- ============================================================================

create table if not exists public.pressing_lignes (
  id                uuid primary key default gen_random_uuid(),
  entreprise_id     uuid not null,
  commande_id       uuid not null
    references public.pressing_commandes (id) on delete cascade,
  -- Position dans le dossier (1, 2, 3…) : « le 3ᵉ vêtement du dépôt ».
  position          integer not null default 1,
  -- Catalogue (référence) ET copie du libellé (histoire figée).
  categorie_id      uuid references public.pressing_categories (id) on delete set null,
  categorie_nom     text,
  prestation_id     uuid references public.pressing_prestations (id) on delete set null,
  prestation_nom    text,
  -- Description individuelle du vêtement.
  designation       text,
  marque            text,
  couleur           text,
  matiere           text,
  taille            text,
  -- État constaté AU DÉPÔT (protection contre les litiges).
  etat_depot        text,
  defauts           text,
  accessoires       text,
  observations      text,
  photos            jsonb not null default '[]'::jsonb,
  quantite          numeric(10, 2) not null default 1,
  -- 💰 Prix FIGÉ au dépôt (le catalogue peut changer demain).
  prix_unitaire     numeric(14, 2) not null default 0,
  prix              numeric(14, 2) not null default 0,
  -- Suivi individuel.
  etape_code        text not null default 'DEPOSE',
  agent_id          uuid,
  debut_traitement  timestamptz,
  fin_traitement    timestamptz,
  controle_ok       boolean,
  controle_par      uuid,
  controle_le       timestamptz,
  controle_note     text,
  remis_le          timestamptz,
  remis_par         uuid,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  constraint chk_pressing_ligne_qte check (quantite > 0),
  constraint chk_pressing_ligne_prix check (prix_unitaire >= 0 and prix >= 0)
);

create index if not exists idx_pressing_lignes_commande
  on public.pressing_lignes (commande_id, position);

create index if not exists idx_pressing_lignes_etape
  on public.pressing_lignes (entreprise_id, etape_code)
  where remis_le is null;

comment on table public.pressing_lignes is
  'Module 35 — un vêtement déposé (ou un lot identique) : description, état au dépôt, prestation, prix figé, étape de traitement, remise.';


-- 4.1 Historique chronologique des changements d'étape.
create table if not exists public.pressing_ligne_etapes (
  id            uuid primary key default gen_random_uuid(),
  entreprise_id uuid not null,
  commande_id   uuid not null
    references public.pressing_commandes (id) on delete cascade,
  ligne_id      uuid not null
    references public.pressing_lignes (id) on delete cascade,
  etape_code    text not null,
  etape_avant   text,
  agent_id      uuid,
  note          text,
  created_at    timestamptz not null default now()
);

create index if not exists idx_pressing_ligne_etapes_ligne
  on public.pressing_ligne_etapes (ligne_id, created_at desc);

comment on table public.pressing_ligne_etapes is
  'Module 35 — historique : qui a fait passer ce vêtement d''une étape à une autre, quand, avec quelle note.';


-- ============================================================================
--  5. LES PAIEMENTS (chaque versement est une ligne, jamais un cumul écrasé)
-- ============================================================================

create table if not exists public.pressing_paiements (
  id            uuid primary key default gen_random_uuid(),
  entreprise_id uuid not null,
  commande_id   uuid not null
    references public.pressing_commandes (id) on delete cascade,
  montant       numeric(14, 2) not null check (montant > 0),
  mode          text not null default 'especes',
  reference     text,
  encaisse_le   timestamptz not null default now(),
  agent_id      uuid,
  -- Annulation douce : un encaissement ne disparaît jamais.
  annule_le     timestamptz,
  annule_par    uuid,
  motif_annulation text,
  created_at    timestamptz not null default now()
);

create index if not exists idx_pressing_paiements_commande
  on public.pressing_paiements (commande_id, created_at);

create index if not exists idx_pressing_paiements_date
  on public.pressing_paiements (entreprise_id, encaisse_le desc)
  where annule_le is null;

comment on table public.pressing_paiements is
  'Module 35 — versements encaissés sur une commande (espèces, mobile money, carte…). Jamais cumulés, jamais supprimés : annulation douce.';


-- ============================================================================
--  6. SÉCURITÉ (RLS)
-- ============================================================================

alter table public.pressing_etapes        enable row level security;
alter table public.pressing_commandes     enable row level security;
alter table public.pressing_lignes        enable row level security;
alter table public.pressing_ligne_etapes  enable row level security;
alter table public.pressing_paiements     enable row level security;

drop policy if exists pressing_etapes_lecture on public.pressing_etapes;
create policy pressing_etapes_lecture on public.pressing_etapes
  for select to authenticated
  using (entreprise_id = public.pressing_entreprise() or public.est_plateforme());

drop policy if exists pressing_commandes_lecture on public.pressing_commandes;
create policy pressing_commandes_lecture on public.pressing_commandes
  for select to authenticated
  using (entreprise_id = public.pressing_entreprise() or public.est_plateforme());

drop policy if exists pressing_lignes_lecture on public.pressing_lignes;
create policy pressing_lignes_lecture on public.pressing_lignes
  for select to authenticated
  using (entreprise_id = public.pressing_entreprise() or public.est_plateforme());

drop policy if exists pressing_ligne_etapes_lecture on public.pressing_ligne_etapes;
create policy pressing_ligne_etapes_lecture on public.pressing_ligne_etapes
  for select to authenticated
  using (entreprise_id = public.pressing_entreprise() or public.est_plateforme());

drop policy if exists pressing_paiements_lecture on public.pressing_paiements;
create policy pressing_paiements_lecture on public.pressing_paiements
  for select to authenticated
  using (entreprise_id = public.pressing_entreprise() or public.est_plateforme());

revoke insert, update, delete on public.pressing_etapes       from authenticated, anon;
revoke insert, update, delete on public.pressing_commandes    from authenticated, anon;
revoke insert, update, delete on public.pressing_lignes       from authenticated, anon;
revoke insert, update, delete on public.pressing_ligne_etapes from authenticated, anon;
revoke insert, update, delete on public.pressing_paiements    from authenticated, anon;


-- ============================================================================
--  7. OUTILS INTERNES
-- ============================================================================

-- 7.1 Statut de la commande recalculé À PARTIR DES LIGNES.
--     C'est ce qui permet « 3 prêts, 2 en repassage » sans mentir.
create or replace function public.pressing_recalc_statut(p_commande_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nb       integer;
  v_remis    integer;
  v_prets    integer;
  v_statut   text;
begin
  select count(*),
         count(*) filter (where l.remis_le is not null),
         count(*) filter (where l.remis_le is null
                            and coalesce(e.est_finale, l.etape_code = 'PRET'))
    into v_nb, v_remis, v_prets
    from public.pressing_lignes l
    left join public.pressing_etapes e
      on e.entreprise_id = l.entreprise_id and e.code = l.etape_code
   where l.commande_id = p_commande_id;

  if coalesce(v_nb, 0) = 0 then
    v_statut := 'EN_TRAITEMENT';
  elsif v_remis = v_nb then
    v_statut := 'REMISE';
  elsif v_remis > 0 then
    v_statut := 'PARTIELLEMENT_REMISE';
  elsif v_prets = v_nb then
    v_statut := 'PRETE';
  else
    v_statut := 'EN_TRAITEMENT';
  end if;

  update public.pressing_commandes
     set statut = v_statut, updated_at = now()
   where id = p_commande_id and statut <> 'ANNULEE';

  return v_statut;
end;
$$;

comment on function public.pressing_recalc_statut(uuid) is
  'Module 35 — recalcule le statut d''une commande à partir de ses lignes (remise, prête, en traitement).';

revoke all on function public.pressing_recalc_statut(uuid) from public, anon;
grant execute on function public.pressing_recalc_statut(uuid) to authenticated;


-- 7.2 Jeton QR : 64 caractères hexadécimaux, sans lien avec la base.
create or replace function public.pressing_nouveau_token()
returns text
language sql
volatile
as $$
  select replace(gen_random_uuid()::text, '-', '')
      || replace(gen_random_uuid()::text, '-', '');
$$;

comment on function public.pressing_nouveau_token() is
  'Module 35 — jeton aléatoire non devinable pour le QR code d''une commande.';

revoke all on function public.pressing_nouveau_token() from public, anon;
grant execute on function public.pressing_nouveau_token() to authenticated;


-- 7.3 Prix d'une prestation pour un type de vêtement (le plus précis gagne).
create or replace function public.pressing_prix_pour(
  p_entreprise   uuid,
  p_prestation   uuid,
  p_categorie    uuid
)
returns numeric
language sql
stable
security definer
set search_path = public
as $$
  select t.prix
    from public.pressing_tarifs t
   where t.entreprise_id = p_entreprise
     and t.prestation_id = p_prestation
     and t.actif
     and (t.categorie_id = p_categorie or t.categorie_id is null)
   order by (t.categorie_id is not null) desc
   limit 1;
$$;

comment on function public.pressing_prix_pour(uuid, uuid, uuid) is
  'Module 35 — prix applicable d''une prestation pour un type de vêtement (tarif spécifique prioritaire, sinon tarif par défaut).';

revoke all on function public.pressing_prix_pour(uuid, uuid, uuid) from public, anon;
grant execute on function public.pressing_prix_pour(uuid, uuid, uuid) to authenticated;


-- ============================================================================
--  8. RPC — CRÉER UN DÉPÔT
-- ============================================================================
--  p_lignes = [
--    { "categorie_id": "…", "prestation_id": "…",
--      "designation": "Chemise blanche", "marque": "…", "couleur": "…",
--      "matiere": "…", "taille": "L", "quantite": 1,
--      "etat_depot": "Bon", "defauts": "tache col", "accessoires": "ceinture",
--      "observations": "…", "photos": ["…"], "prix_unitaire": 3500 }
--  ]
--  `prix_unitaire` absent ⇒ le tarif du catalogue est appliqué.
--  `p_paiement` = { "montant": 2000, "mode": "especes", "reference": "…" }

create or replace function public.pressing_depot_creer(
  p_client_id      uuid,
  p_lignes         jsonb,
  p_date_prevue    timestamptz default null,
  p_remise         numeric default 0,
  p_supplement     numeric default 0,
  p_urgence        boolean default false,
  p_observations   text default null,
  p_paiement       jsonb default null,
  p_reference_locale text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ent      uuid := public.pressing_entreprise();
  v_cmd      public.pressing_commandes%rowtype;
  v_ligne    jsonb;
  v_pos      integer := 0;
  v_cat      uuid;
  v_pres     uuid;
  v_qte      numeric;
  v_pu       numeric;
  v_prix     numeric;
  v_total    numeric := 0;
  v_ids      uuid[] := '{}';
  v_ligne_id uuid;
  v_numero   text;
  v_token    text;
  v_client   public.pressing_clients%rowtype;
  v_paie     numeric := 0;
  v_existant uuid;
  v_cfg      public.pressing_config%rowtype;
  v_devise   text := 'CDF';
  v_delai    integer := 3;
begin
  if auth.uid() is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;
  if not (public.peut('pressing_depots', 'creer') or public.est_plateforme()) then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas d''enregistrer un dépôt.';
  end if;
  if p_lignes is null or jsonb_typeof(p_lignes) <> 'array'
     or jsonb_array_length(p_lignes) = 0 then
    raise exception 'LIGNE_INVALIDE|Ajoutez au moins un vêtement au dépôt.';
  end if;

  -- 🔁 Idempotence hors ligne : le même dépôt rejoué renvoie l'existant.
  if p_reference_locale is not null and btrim(p_reference_locale) <> '' then
    select id into v_existant
      from public.pressing_commandes
     where entreprise_id = v_ent and reference_locale = btrim(p_reference_locale);

    if v_existant is not null then
      return public.pressing_commande_fiche(v_existant)
             || jsonb_build_object('deja_enregistre', true);
    end if;
  end if;

  select * into v_cfg from public.pressing_config where entreprise_id = v_ent;
  if found then
    v_devise := v_cfg.devise;
    v_delai  := greatest(coalesce(v_cfg.delai_standard_jours, 3), 0);
  end if;

  if p_client_id is not null then
    select * into v_client
      from public.pressing_clients
     where id = p_client_id and entreprise_id = v_ent;
    if not found then
      raise exception 'CLIENT_INTROUVABLE|Ce client n''existe pas dans ce pressing.';
    end if;
  end if;

  v_numero := public.pressing_prochain_numero(v_ent);
  v_token  := public.pressing_nouveau_token();

  insert into public.pressing_commandes (
    entreprise_id, numero, client_id, client_nom, client_telephone,
    statut, urgence, date_prevue, devise, remise, supplement, observations,
    qr_token, reference_locale, cree_par
  ) values (
    v_ent, v_numero, p_client_id, v_client.nom, v_client.telephone,
    'EN_TRAITEMENT', coalesce(p_urgence, false),
    coalesce(p_date_prevue, now() + (v_delai || ' jours')::interval),
    v_devise, greatest(coalesce(p_remise, 0), 0),
    greatest(coalesce(p_supplement, 0), 0),
    nullif(btrim(coalesce(p_observations, '')), ''),
    v_token, nullif(btrim(coalesce(p_reference_locale, '')), ''), auth.uid()
  )
  returning * into v_cmd;

  -- --- Les vêtements -------------------------------------------------------
  for v_ligne in select * from jsonb_array_elements(p_lignes)
  loop
    v_pos := v_pos + 1;

    v_cat  := nullif(v_ligne->>'categorie_id', '')::uuid;
    v_pres := nullif(v_ligne->>'prestation_id', '')::uuid;
    v_qte  := coalesce(nullif(v_ligne->>'quantite', '')::numeric, 1);

    if v_qte <= 0 then
      raise exception 'LIGNE_INVALIDE|Quantité invalide pour le vêtement n° %.', v_pos;
    end if;

    if v_cat is not null and not exists (
      select 1 from public.pressing_categories
       where id = v_cat and entreprise_id = v_ent
    ) then
      raise exception 'INTROUVABLE|Type de vêtement inconnu (ligne %).', v_pos;
    end if;

    if v_pres is not null and not exists (
      select 1 from public.pressing_prestations
       where id = v_pres and entreprise_id = v_ent
    ) then
      raise exception 'INTROUVABLE|Prestation inconnue (ligne %).', v_pos;
    end if;

    -- Prix : celui saisi, sinon celui du catalogue.
    v_pu := nullif(v_ligne->>'prix_unitaire', '')::numeric;
    if v_pu is null and v_pres is not null then
      v_pu := public.pressing_prix_pour(v_ent, v_pres, v_cat);
    end if;
    if v_pu is null then
      raise exception 'PRIX_MANQUANT|Aucun prix pour le vêtement n° % : renseignez le tarif ou saisissez le montant.', v_pos;
    end if;
    if v_pu < 0 then
      raise exception 'MONTANT_INVALIDE|Le prix ne peut pas être négatif (ligne %).', v_pos;
    end if;

    v_prix := round(v_pu * v_qte, 2);
    v_total := v_total + v_prix;

    insert into public.pressing_lignes (
      entreprise_id, commande_id, position, categorie_id, categorie_nom,
      prestation_id, prestation_nom, designation, marque, couleur, matiere,
      taille, etat_depot, defauts, accessoires, observations, photos,
      quantite, prix_unitaire, prix, etape_code
    ) values (
      v_ent, v_cmd.id, v_pos, v_cat,
      (select nom from public.pressing_categories where id = v_cat),
      v_pres,
      (select nom from public.pressing_prestations where id = v_pres),
      nullif(btrim(coalesce(v_ligne->>'designation', '')), ''),
      nullif(btrim(coalesce(v_ligne->>'marque', '')), ''),
      nullif(btrim(coalesce(v_ligne->>'couleur', '')), ''),
      nullif(btrim(coalesce(v_ligne->>'matiere', '')), ''),
      nullif(btrim(coalesce(v_ligne->>'taille', '')), ''),
      nullif(btrim(coalesce(v_ligne->>'etat_depot', '')), ''),
      nullif(btrim(coalesce(v_ligne->>'defauts', '')), ''),
      nullif(btrim(coalesce(v_ligne->>'accessoires', '')), ''),
      nullif(btrim(coalesce(v_ligne->>'observations', '')), ''),
      coalesce(v_ligne->'photos', '[]'::jsonb),
      v_qte, v_pu, v_prix, 'DEPOSE'
    )
    returning id into v_ligne_id;

    v_ids := v_ids || v_ligne_id;

    insert into public.pressing_ligne_etapes (
      entreprise_id, commande_id, ligne_id, etape_code, etape_avant, agent_id, note
    ) values (
      v_ent, v_cmd.id, v_ligne_id, 'DEPOSE', null, auth.uid(), 'Dépôt enregistré'
    );
  end loop;

  -- --- Totaux --------------------------------------------------------------
  update public.pressing_commandes
     set total = v_total,
         montant_paye = 0,
         updated_at = now()
   where id = v_cmd.id;

  -- --- Paiement immédiat (facultatif) --------------------------------------
  if p_paiement is not null and jsonb_typeof(p_paiement) = 'object' then
    v_paie := coalesce(nullif(p_paiement->>'montant', '')::numeric, 0);
    if v_paie > 0 and v_paie > v_total then
      raise exception 'MONTANT_INVALIDE|Le paiement (%) dépasse le montant du dépôt (%).',
        v_paie, v_total;
    end if;
    if v_paie > 0 then
      insert into public.pressing_paiements (
        entreprise_id, commande_id, montant, mode, reference, agent_id
      ) values (
        v_ent, v_cmd.id, v_paie,
        coalesce(nullif(p_paiement->>'mode', ''), 'especes'),
        nullif(btrim(coalesce(p_paiement->>'reference', '')), ''),
        auth.uid()
      );

      update public.pressing_commandes
         set montant_paye = (select coalesce(sum(montant), 0)
                               from public.pressing_paiements
                              where commande_id = v_cmd.id and annule_le is null),
             updated_at = now()
       where id = v_cmd.id;
    end if;
  end if;

  perform public.pressing_recalc_statut(v_cmd.id);

  if v_client.id is not null then
    update public.pressing_clients
       set derniere_activite = now(), updated_at = now()
     where id = v_client.id;
  end if;

  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(), v_ent, 'PRESSING_DEPOT', auth.uid(),
    jsonb_build_object(
      'commande', v_numero,
      'client', v_client.nom,
      'nb_lignes', v_pos,
      'total', v_total,
      'lignes', v_ids
    ),
    now()
  );

  return public.pressing_commande_fiche(v_cmd.id);
end;
$$;

comment on function public.pressing_depot_creer(uuid, jsonb, timestamptz, numeric, numeric, boolean, text, jsonb, text) is
  'Module 35 — enregistre un dépôt complet (vêtements, prix figés, QR, paiement éventuel) et renvoie le dossier.';

revoke all on function public.pressing_depot_creer(uuid, jsonb, timestamptz, numeric, numeric, boolean, text, jsonb, text)
  from public, anon;
grant execute on function public.pressing_depot_creer(uuid, jsonb, timestamptz, numeric, numeric, boolean, text, jsonb, text)
  to authenticated;


-- ============================================================================
--  9. RPC — LIRE UNE COMMANDE (fiche complète)
-- ============================================================================

create or replace function public.pressing_commande_fiche(p_commande_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_ent  uuid := public.pressing_entreprise();
  v_cmd  public.pressing_commandes%rowtype;
  v_lignes  jsonb;
  v_paies   jsonb;
  v_hist    jsonb;
begin
  if auth.uid() is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;

  select * into v_cmd
    from public.pressing_commandes
   where id = p_commande_id and entreprise_id = v_ent;

  if not found then
    raise exception 'COMMANDE_INTROUVABLE|Cette commande n''existe pas dans ce pressing.';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', l.id,
           'position', l.position,
           'categorie_id', l.categorie_id,
           'categorie_nom', l.categorie_nom,
           'prestation_id', l.prestation_id,
           'prestation_nom', l.prestation_nom,
           'designation', l.designation,
           'marque', l.marque,
           'couleur', l.couleur,
           'matiere', l.matiere,
           'taille', l.taille,
           'etat_depot', l.etat_depot,
           'defauts', l.defauts,
           'accessoires', l.accessoires,
           'observations', l.observations,
           'photos', l.photos,
           'quantite', l.quantite,
           'prix_unitaire', l.prix_unitaire,
           'prix', l.prix,
           'etape_code', l.etape_code,
           'etape_libelle', (select e.libelle from public.pressing_etapes e
                              where e.entreprise_id = l.entreprise_id
                                and e.code = l.etape_code),
           'est_prete', coalesce(
             (select e.est_finale
                from public.pressing_etapes e
               where e.entreprise_id = l.entreprise_id
                 and e.code = l.etape_code),
             l.etape_code = 'PRET'),
           'agent_id', l.agent_id,
           'debut_traitement', l.debut_traitement,
           'fin_traitement', l.fin_traitement,
           'controle_ok', l.controle_ok,
           'controle_le', l.controle_le,
           'controle_note', l.controle_note,
           'remis_le', l.remis_le,
           'remis_par', l.remis_par
         ) order by l.position), '[]'::jsonb)
    into v_lignes
    from public.pressing_lignes l
   where l.commande_id = v_cmd.id;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', p.id,
           'montant', p.montant,
           'mode', p.mode,
           'reference', p.reference,
           'encaisse_le', p.encaisse_le,
           'agent_id', p.agent_id,
           'annule_le', p.annule_le,
           'motif_annulation', p.motif_annulation
         ) order by p.created_at), '[]'::jsonb)
    into v_paies
    from public.pressing_paiements p
   where p.commande_id = v_cmd.id;

  select coalesce(jsonb_agg(jsonb_build_object(
           'ligne_id', h.ligne_id,
           'etape_code', h.etape_code,
           'etape_avant', h.etape_avant,
           'agent_id', h.agent_id,
           'note', h.note,
           'created_at', h.created_at
         ) order by h.created_at), '[]'::jsonb)
    into v_hist
    from public.pressing_ligne_etapes h
   where h.commande_id = v_cmd.id;

  return jsonb_build_object(
    'id', v_cmd.id,
    'numero', v_cmd.numero,
    'client_id', v_cmd.client_id,
    'client_nom', v_cmd.client_nom,
    'client_telephone', v_cmd.client_telephone,
    'statut', v_cmd.statut,
    'urgence', v_cmd.urgence,
    'date_depot', v_cmd.date_depot,
    'date_prevue', v_cmd.date_prevue,
    'devise', v_cmd.devise,
    'total', v_cmd.total,
    'remise', v_cmd.remise,
    'supplement', v_cmd.supplement,
    'montant_paye', v_cmd.montant_paye,
    'solde', greatest(v_cmd.total - v_cmd.montant_paye, 0),
    'observations', v_cmd.observations,
    'qr_token', v_cmd.qr_token,
    'qr_version', v_cmd.qr_version,
    'annule_le', v_cmd.annule_le,
    'motif_annulation', v_cmd.motif_annulation,
    'created_at', v_cmd.created_at,
    'lignes', v_lignes,
    'paiements', v_paies,
    'historique', v_hist
  );
end;
$$;

comment on function public.pressing_commande_fiche(uuid) is
  'Module 35 — fiche complète d''une commande : vêtements, paiements, historique des étapes.';

revoke all on function public.pressing_commande_fiche(uuid) from public, anon;
grant execute on function public.pressing_commande_fiche(uuid) to authenticated;


-- ============================================================================
-- 10. RPC — LISTER LES COMMANDES
-- ============================================================================

create or replace function public.pressing_commandes_lister(
  p_statut    text default null,
  p_recherche text default null,
  p_debut     date default null,
  p_fin       date default null,
  p_limite    integer default 100
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_ent  uuid := public.pressing_entreprise();
  v_like text;
  v_rows jsonb;
begin
  if auth.uid() is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;

  v_like := nullif(btrim(coalesce(p_recherche, '')), '');

  select coalesce(jsonb_agg(x order by x->>'date_depot' desc), '[]'::jsonb)
    into v_rows
    from (
      select jsonb_build_object(
               'id', c.id,
               'numero', c.numero,
               'client_id', c.client_id,
               'client_nom', c.client_nom,
               'client_telephone', c.client_telephone,
               'statut', c.statut,
               'urgence', c.urgence,
               'date_depot', c.date_depot,
               'date_prevue', c.date_prevue,
               'total', c.total,
               'montant_paye', c.montant_paye,
               'solde', greatest(c.total - c.montant_paye, 0),
               'devise', c.devise,
               'nb_lignes', (select count(*) from public.pressing_lignes l
                              where l.commande_id = c.id),
               'nb_prets', (select count(*) from public.pressing_lignes l
                              left join public.pressing_etapes e
                                     on e.entreprise_id = l.entreprise_id
                                    and e.code = l.etape_code
                             where l.commande_id = c.id
                               and l.remis_le is null
                               and coalesce(e.est_finale, l.etape_code = 'PRET')),
               'nb_remis', (select count(*) from public.pressing_lignes l
                             where l.commande_id = c.id and l.remis_le is not null),
               'en_retard', (c.date_prevue is not null
                             and c.date_prevue < now()
                             and c.statut not in ('REMISE', 'ANNULEE'))
             ) as x
        from public.pressing_commandes c
       where c.entreprise_id = v_ent
         and (p_statut is null or btrim(p_statut) = ''
              or c.statut = btrim(p_statut))
         and (p_debut is null or c.date_depot::date >= p_debut)
         and (p_fin is null or c.date_depot::date <= p_fin)
         and (v_like is null
              or coalesce(c.numero, '') ilike '%' || v_like || '%'
              or coalesce(c.client_nom, '') ilike '%' || v_like || '%'
              or coalesce(c.client_telephone, '') ilike '%' || v_like || '%')
       order by c.date_depot desc
       limit greatest(coalesce(p_limite, 100), 1)
    ) s;

  return v_rows;
end;
$$;

comment on function public.pressing_commandes_lister(text, text, date, date, integer) is
  'Module 35 — liste des commandes du pressing (statut, période, recherche par numéro/client/téléphone).';

revoke all on function public.pressing_commandes_lister(text, text, date, date, integer)
  from public, anon;
grant execute on function public.pressing_commandes_lister(text, text, date, date, integer)
  to authenticated;


-- ============================================================================
-- 11. RPC — RETROUVER UNE COMMANDE PAR SON QR (lecture sécurisée)
-- ============================================================================

create or replace function public.pressing_commande_par_qr(p_token text)
returns jsonb
language plpgsql
stable
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
  if not (public.peut('pressing_retraits', 'voir')
          or public.peut('pressing_depots', 'voir')
          or public.est_plateforme()) then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de lire une commande.';
  end if;
  if btrim(coalesce(p_token, '')) = '' then
    raise exception 'QR_INVALIDE|Code illisible.';
  end if;

  select id into v_id
    from public.pressing_commandes
   where qr_token = btrim(p_token)
     and entreprise_id = v_ent;

  if v_id is null then
    -- ⚠️ Message volontairement identique pour « inexistant » et « autre
    --    pressing » : on n'aide pas à deviner l'existence d'une commande.
    raise exception 'QR_INCONNU|Ce code ne correspond à aucune commande de ce pressing.';
  end if;

  return public.pressing_commande_fiche(v_id);
end;
$$;

comment on function public.pressing_commande_par_qr(text) is
  'Module 35 — vérifie un QR code scanné et renvoie la fiche complète (jeton non devinable, isolation par entreprise).';

revoke all on function public.pressing_commande_par_qr(text) from public, anon;
grant execute on function public.pressing_commande_par_qr(text) to authenticated;


-- ============================================================================
-- 12. RPC — FAIRE AVANCER UN VÊTEMENT DANS LE PIPELINE
-- ============================================================================

create or replace function public.pressing_ligne_avancer(
  p_ligne_id  uuid,
  p_etape     text,
  p_note      text default null,
  p_agent_id  uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ent    uuid := public.pressing_entreprise();
  v_ligne  public.pressing_lignes%rowtype;
  v_etape  text := upper(btrim(coalesce(p_etape, '')));
  v_finale boolean;
  v_agent  uuid := coalesce(p_agent_id, auth.uid());
begin
  if auth.uid() is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;
  if not (public.peut('pressing_atelier', 'modifier')
          or public.peut('pressing_depots', 'modifier')
          or public.est_plateforme()) then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de modifier le traitement.';
  end if;

  select * into v_ligne
    from public.pressing_lignes
   where id = p_ligne_id and entreprise_id = v_ent
   for update;

  if not found then
    raise exception 'INTROUVABLE|Ce vêtement n''existe pas dans ce pressing.';
  end if;
  if v_ligne.remis_le is not null then
    raise exception 'DEJA_REMIS|Ce vêtement a déjà été remis au client.';
  end if;

  select e.est_finale into v_finale
    from public.pressing_etapes e
   where e.entreprise_id = v_ent and e.code = v_etape and e.actif;

  if not found then
    raise exception 'ETAPE_INCONNUE|Cette étape de traitement n''existe pas.';
  end if;

  if v_ligne.etape_code = v_etape then
    -- Idempotent : rien à faire, on ne pollue pas l'historique.
    return jsonb_build_object('ok', true, 'deja', true,
                              'etape_code', v_ligne.etape_code);
  end if;

  update public.pressing_lignes
     set etape_code = v_etape,
         agent_id = v_agent,
         debut_traitement = coalesce(debut_traitement, now()),
         fin_traitement = case when coalesce(v_finale, false) then now()
                               else fin_traitement end,
         updated_at = now()
   where id = v_ligne.id;

  insert into public.pressing_ligne_etapes (
    entreprise_id, commande_id, ligne_id, etape_code, etape_avant, agent_id, note
  ) values (
    v_ent, v_ligne.commande_id, v_ligne.id, v_etape, v_ligne.etape_code,
    v_agent, nullif(btrim(coalesce(p_note, '')), '')
  );

  perform public.pressing_recalc_statut(v_ligne.commande_id);

  return jsonb_build_object('ok', true, 'etape_code', v_etape,
                            'commande_id', v_ligne.commande_id);
end;
$$;

comment on function public.pressing_ligne_avancer(uuid, text, text, uuid) is
  'Module 35 — fait passer un vêtement à une autre étape (historique + agent), sans jamais toucher à la remise.';

revoke all on function public.pressing_ligne_avancer(uuid, text, text, uuid) from public, anon;
grant execute on function public.pressing_ligne_avancer(uuid, text, text, uuid) to authenticated;


create or replace function public.pressing_lignes_avancer_lot(
  p_ligne_ids uuid[],
  p_etape     text,
  p_note      text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ent   uuid := public.pressing_entreprise();
  v_id    uuid;
  v_n     integer := 0;
  v_res   jsonb;
begin
  if auth.uid() is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;
  if p_ligne_ids is null or array_length(p_ligne_ids, 1) is null then
    raise exception 'LIGNE_INVALIDE|Sélectionnez au moins un vêtement.';
  end if;

  foreach v_id in array p_ligne_ids loop
    perform public.pressing_ligne_avancer(v_id, p_etape, p_note, auth.uid());
    v_n := v_n + 1;
  end loop;

  return jsonb_build_object('ok', true, 'nb', v_n);
end;
$$;

comment on function public.pressing_lignes_avancer_lot(uuid[], text, text) is
  'Module 35 — applique la même étape à plusieurs vêtements (traitement par lot).';

revoke all on function public.pressing_lignes_avancer_lot(uuid[], text, text)
  from public, anon;
grant execute on function public.pressing_lignes_avancer_lot(uuid[], text, text)
  to authenticated;


-- ============================================================================
-- 13. RPC — CONTRÔLE QUALITÉ
-- ============================================================================

create or replace function public.pressing_controle_qualite(
  p_ligne_id uuid,
  p_ok       boolean,
  p_note     text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ent    uuid := public.pressing_entreprise();
  v_ligne  public.pressing_lignes%rowtype;
  v_etape  text;
begin
  if auth.uid() is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;
  if not (public.peut('pressing_atelier', 'modifier')
          or public.peut('pressing_retraits', 'valider')
          or public.est_plateforme()) then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de valider la qualité.';
  end if;

  select * into v_ligne
    from public.pressing_lignes
   where id = p_ligne_id and entreprise_id = v_ent
   for update;

  if not found then
    raise exception 'INTROUVABLE|Ce vêtement n''existe pas dans ce pressing.';
  end if;
  if v_ligne.remis_le is not null then
    raise exception 'DEJA_REMIS|Ce vêtement a déjà été remis au client.';
  end if;

  -- Étape finale du pipeline (PRET par défaut, ou celle que le propriétaire
  -- a marquée « est_finale »).
  select e.code into v_etape
    from public.pressing_etapes e
   where e.entreprise_id = v_ent and e.est_finale and e.actif
   order by e.ordre
   limit 1;

  v_etape := coalesce(v_etape, 'PRET');

  update public.pressing_lignes
     set controle_ok   = coalesce(p_ok, false),
         controle_par  = auth.uid(),
         controle_le   = now(),
         controle_note = nullif(btrim(coalesce(p_note, '')), ''),
         etape_code    = case when coalesce(p_ok, false) then v_etape
                              else 'RETRAITEMENT' end,
         fin_traitement = case when coalesce(p_ok, false) then now()
                               else null end,
         updated_at    = now()
   where id = v_ligne.id;

  insert into public.pressing_ligne_etapes (
    entreprise_id, commande_id, ligne_id, etape_code, etape_avant, agent_id, note
  ) values (
    v_ent, v_ligne.commande_id, v_ligne.id,
    case when coalesce(p_ok, false) then v_etape else 'RETRAITEMENT' end,
    v_ligne.etape_code, auth.uid(),
    coalesce(nullif(btrim(coalesce(p_note, '')), ''),
             case when coalesce(p_ok, false) then 'Contrôle qualité : conforme'
                  else 'Contrôle qualité : à retraiter' end)
  );

  perform public.pressing_recalc_statut(v_ligne.commande_id);

  return jsonb_build_object('ok', true, 'etape_code',
                            case when coalesce(p_ok, false) then v_etape
                                 else 'RETRAITEMENT' end);
end;
$$;

comment on function public.pressing_controle_qualite(uuid, boolean, text) is
  'Module 35 — contrôle qualité avant remise : conforme ⇒ étape finale ; sinon ⇒ à retraiter.';

revoke all on function public.pressing_controle_qualite(uuid, boolean, text) from public, anon;
grant execute on function public.pressing_controle_qualite(uuid, boolean, text) to authenticated;


-- ============================================================================
-- 14. RPC — ANNULER UNE COMMANDE (jamais de suppression)
-- ============================================================================

create or replace function public.pressing_commande_annuler(
  p_commande_id uuid,
  p_motif       text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ent  uuid := public.pressing_entreprise();
  v_cmd  public.pressing_commandes%rowtype;
  v_remis integer;
begin
  if auth.uid() is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;
  if not (public.peut('pressing_depots', 'modifier') or public.est_plateforme()) then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas d''annuler une commande.';
  end if;
  if btrim(coalesce(p_motif, '')) = '' then
    raise exception 'MOTIF_VIDE|Indiquez le motif de l''annulation.';
  end if;

  select * into v_cmd
    from public.pressing_commandes
   where id = p_commande_id and entreprise_id = v_ent
   for update;

  if not found then
    raise exception 'COMMANDE_INTROUVABLE|Cette commande n''existe pas.';
  end if;
  if v_cmd.statut = 'ANNULEE' then
    return jsonb_build_object('ok', true, 'deja', true);
  end if;

  select count(*) into v_remis
    from public.pressing_lignes
   where commande_id = v_cmd.id and remis_le is not null;

  if v_remis > 0 then
    raise exception 'REMISE_DEJA_FAITE|Des vêtements ont déjà été remis : une annulation n''est plus possible.';
  end if;

  update public.pressing_commandes
     set statut = 'ANNULEE',
         annule_le = now(),
         annule_par = auth.uid(),
         motif_annulation = btrim(p_motif),
         updated_at = now()
   where id = v_cmd.id;

  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(), v_ent, 'PRESSING_COMMANDE_ANNULEE', auth.uid(),
    jsonb_build_object('commande', v_cmd.numero, 'motif', btrim(p_motif)),
    now()
  );

  return jsonb_build_object('ok', true, 'statut', 'ANNULEE');
end;
$$;

comment on function public.pressing_commande_annuler(uuid, text) is
  'Module 35 — annule une commande (jamais de suppression), sauf si des vêtements ont déjà été remis.';

revoke all on function public.pressing_commande_annuler(uuid, text) from public, anon;
grant execute on function public.pressing_commande_annuler(uuid, text) to authenticated;


-- ============================================================================
-- 15. RPC — RÉÉDITER UN QR CODE (perte / compromission)
-- ============================================================================

create or replace function public.pressing_qr_regenerer(p_commande_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ent   uuid := public.pressing_entreprise();
  v_cmd   public.pressing_commandes%rowtype;
  v_token text;
begin
  if auth.uid() is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;
  if not (public.peut('pressing_depots', 'modifier') or public.est_plateforme()) then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de rééditer un QR code.';
  end if;

  select * into v_cmd
    from public.pressing_commandes
   where id = p_commande_id and entreprise_id = v_ent
   for update;

  if not found then
    raise exception 'COMMANDE_INTROUVABLE|Cette commande n''existe pas.';
  end if;

  v_token := public.pressing_nouveau_token();

  update public.pressing_commandes
     set qr_token = v_token,
         qr_version = qr_version + 1,
         qr_regenere_le = now(),
         qr_regenere_par = auth.uid(),
         updated_at = now()
   where id = v_cmd.id;

  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(), v_ent, 'PRESSING_QR_REGENERE', auth.uid(),
    jsonb_build_object('commande', v_cmd.numero,
                       'version', v_cmd.qr_version + 1),
    now()
  );

  return jsonb_build_object('ok', true, 'qr_token', v_token,
                            'qr_version', v_cmd.qr_version + 1);
end;
$$;

comment on function public.pressing_qr_regenerer(uuid) is
  'Module 35 — réédite le jeton du QR code d''une commande ; l''ancien code devient inutilisable et l''opération est tracée.';

revoke all on function public.pressing_qr_regenerer(uuid) from public, anon;
grant execute on function public.pressing_qr_regenerer(uuid) to authenticated;


-- ============================================================================
--  VÉRIFICATIONS
-- ============================================================================

-- V1. Les tables de l'étape 2 (attendu : 5).
select count(*) as tables_etape2
  from information_schema.tables
 where table_schema = 'public'
   and table_name in ('pressing_etapes', 'pressing_compteurs',
                      'pressing_commandes', 'pressing_lignes',
                      'pressing_ligne_etapes', 'pressing_paiements');

-- V2. Les RPC de l'étape 2 (attendu : 13 lignes).
select proname
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and proname like 'pressing\_%'
 order by proname;

-- V3. Aucun prix inventé : le catalogue d'exemple reste sans tarif.
select count(*) as tarifs_imposes
  from public.pressing_tarifs;
