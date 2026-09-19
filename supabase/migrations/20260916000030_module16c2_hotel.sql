-- ============================================================================
--  biashara_yangu — MODULE 16 (PHASE C2) : HÔTEL — CHAMBRES & SÉJOURS
--
--  OBJECTIF (roadmap multi-activités, module C2) :
--    Le type d'activité « Hôtel » active les modules `chambres`,
--    `reservations` et `checkin` :
--      • chambres : numéro, type, capacité, prix par nuit, statut
--        (libre → réservée → occupée → à nettoyer) ;
--      • réservations : client (fiche ou nom libre), dates, personnes,
--        prix négocié par nuit, avance et suivi du solde ;
--      • check-in / check-out (arrivées & départs du jour) ;
--      • facture de séjour reconstruite côté application ;
--      • tableau de bord « occupation » + arrivées/départs du jour.
--
--  CONTENU :
--    1. tables `chambres` + `reservations` (+ index + RLS) ;
--    2. RPC : enregistrer une chambre, changer son statut, créer /
--       check-in / check-out / encaisser / annuler une réservation ;
--    3. RPC tableau de bord hôtel (occupation, arrivées/départs) ;
--    4. permissions : pages `chambres`, `reservations`, `reception`
--       (PROPRIÉTAIRE : tout ; VENDEUR : réceptionniste) ;
--    5. journal d'audit : niveaux des nouvelles actions.
--
--  OÙ : Supabase → SQL Editor → coller → Run
--  IDEMPOTENT : peut être relancé sans effet de bord.
-- ============================================================================


-- ============================================================================
--  1.a TABLE `public.chambres`
-- ============================================================================
--  Une chambre appartient à une boutique (owner_id = patron, comme les
--  articles). Le statut suit le cycle de vie réel :
--    libre → reservee (une réservation existe) → occupee (check-in) →
--    a_nettoyer (check-out) → libre (remise en service).

create table if not exists public.chambres (
  id           uuid primary key default gen_random_uuid(),
  owner_id     uuid not null,
  numero       text not null,
  type_chambre text default '',
  capacite     integer not null default 1,
  prix_nuit    real not null default 0,
  statut       text not null default 'libre',
  equipements  text,
  actif        boolean not null default true,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  constraint chambres_statut_check
    check (statut in ('libre', 'reservee', 'occupee', 'a_nettoyer')),
  constraint chambres_capacite_check check (capacite >= 1 and capacite <= 50),
  constraint chambres_prix_check check (prix_nuit >= 0)
);

create unique index if not exists idx_chambres_owner_numero
  on public.chambres (owner_id, numero);
create index if not exists idx_chambres_owner_statut
  on public.chambres (owner_id, statut);

comment on table public.chambres is
  'Module 16 C2 (hôtel) — chambres d''une boutique : numéro, type, capacité, prix par nuit et statut (libre/reservee/occupee/a_nettoyer).';
comment on column public.chambres.statut is
  'libre → reservee (réservation) → occupee (check-in) → a_nettoyer (check-out) → libre.';


-- ============================================================================
--  1.b TABLE `public.reservations`
-- ============================================================================
--  Le client est soit une fiche existante (`client_id`), soit un simple nom
--  saisi à la réception (`client_nom`). Les montants sont des SNAPSHOTS :
--  modifier le prix de la chambre plus tard ne change pas un séjour passé.

create table if not exists public.reservations (
  id               uuid primary key default gen_random_uuid(),
  owner_id         uuid not null,
  chambre_id       uuid not null references public.chambres (id),
  client_id        bigint references public.clients (id),
  client_nom       text not null,
  date_arrivee     date not null,
  date_depart      date not null,
  nb_personnes     integer not null default 1,
  prix_nuit        real not null default 0,
  montant_total    real not null default 0,
  montant_paye     real not null default 0,
  statut           text not null default 'reservee',
  note             text,
  motif_annulation text,
  cree_par         uuid,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  constraint reservations_dates_check check (date_depart > date_arrivee),
  constraint reservations_personnes_check check (nb_personnes >= 1),
  constraint reservations_montants_check
    check (montant_total >= 0 and montant_paye >= 0),
  constraint reservations_statut_check
    check (statut in ('reservee', 'en_cours', 'terminee', 'annulee'))
);

create index if not exists idx_reservations_owner_arrivee
  on public.reservations (owner_id, date_arrivee);
create index if not exists idx_reservations_chambre
  on public.reservations (chambre_id, date_arrivee);
create index if not exists idx_reservations_owner_statut
  on public.reservations (owner_id, statut);

comment on table public.reservations is
  'Module 16 C2 (hôtel) — séjours : réservation (dates, personnes, avance) puis check-in (en_cours) et check-out (terminee).';
comment on column public.reservations.montant_paye is
  'Total encaissé sur le séjour (avances + soldes), toujours ≤ montant_total.';


-- ============================================================================
--  2. RLS — LECTURE PAR LA BOUTIQUE, ÉCRITURE CONTRÔLÉE
-- ============================================================================
--  Chambres  : lecture + écritures directes encadrées par RLS (même modèle
--              que les articles) ; les droits fins passent par `peut(...)`.
--  Réservations : lecture seule en direct — les écritures passent
--              UNIQUEMENT par les RPC (statuts, chevauchements, montants).

alter table public.chambres     enable row level security;
alter table public.reservations enable row level security;

drop policy if exists chambres_lecture      on public.chambres;
drop policy if exists chambres_creation     on public.chambres;
drop policy if exists chambres_modification on public.chambres;
drop policy if exists chambres_suppression  on public.chambres;
drop policy if exists reservations_lecture  on public.reservations;

create policy chambres_lecture on public.chambres
  for select to authenticated
  using (
    owner_id = auth.uid()
    or owner_id = public.mon_proprietaire()
    or public.est_plateforme()
  );

create policy chambres_creation on public.chambres
  for insert to authenticated
  with check (
    (owner_id = auth.uid() or owner_id = public.mon_proprietaire())
    and public.peut('chambres', 'creer')
  );

create policy chambres_modification on public.chambres
  for update to authenticated
  using (
    (owner_id = auth.uid() or owner_id = public.mon_proprietaire())
    and public.peut('chambres', 'modifier')
  )
  with check (
    (owner_id = auth.uid() or owner_id = public.mon_proprietaire())
    and public.peut('chambres', 'modifier')
  );

create policy chambres_suppression on public.chambres
  for delete to authenticated
  using (
    (owner_id = auth.uid() or owner_id = public.mon_proprietaire())
    and public.peut('chambres', 'supprimer')
  );

create policy reservations_lecture on public.reservations
  for select to authenticated
  using (
    owner_id = auth.uid()
    or owner_id = public.mon_proprietaire()
    or public.est_plateforme()
  );


-- ============================================================================
--  3. RPC `rpc_chambre_enregistrer` — CRÉATION / MODIFICATION
-- ============================================================================
create or replace function public.rpc_chambre_enregistrer(
  p_id           uuid    default null,
  p_numero       text    default '',
  p_type_chambre text    default '',
  p_capacite     integer default 1,
  p_prix_nuit    real    default 0,
  p_equipements  text    default null,
  p_actif        boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user    uuid := auth.uid();
  v_owner   uuid;
  v_numero  text := btrim(coalesce(p_numero, ''));
  v_id      uuid := p_id;
  v_chambre public.chambres%rowtype;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour gérer les chambres.';
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  if v_numero = '' then
    raise exception 'NUMERO_OBLIGATOIRE|Le numéro de la chambre est obligatoire.';
  end if;
  if length(v_numero) > 20 then
    raise exception 'NUMERO_INVALIDE|Numéro trop long (20 caractères maximum).';
  end if;
  if p_capacite is null or p_capacite < 1 or p_capacite > 50 then
    raise exception 'CAPACITE_INVALIDE|La capacité doit être comprise entre 1 et 50 personnes.';
  end if;
  if coalesce(p_prix_nuit, 0) < 0 then
    raise exception 'PRIX_INVALIDE|Le prix par nuit ne peut pas être négatif.';
  end if;

  if v_id is null then
    -- Création.
    if not public.peut('chambres', 'creer') then
      raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de créer une chambre.';
    end if;

    begin
      insert into public.chambres (
        owner_id, numero, type_chambre, capacite, prix_nuit, equipements, actif
      ) values (
        v_owner,
        v_numero,
        nullif(btrim(coalesce(p_type_chambre, '')), ''),
        p_capacite,
        coalesce(p_prix_nuit, 0),
        nullif(btrim(coalesce(p_equipements, '')), ''),
        coalesce(p_actif, true)
      )
      returning * into v_chambre;
    exception when unique_violation then
      raise exception 'NUMERO_EXISTE|Une chambre porte déjà le numéro « % ».', v_numero;
    end;

    insert into public.journal_audit (
      id, entreprise_id, action, utilisateur_id, details, created_at
    ) values (
      gen_random_uuid(),
      null,
      'CHAMBRE_ENREGISTREE',
      v_user,
      jsonb_build_object(
        'chambre_id', v_chambre.id,
        'numero',     v_chambre.numero,
        'creation',   true
      ),
      now()
    );
  else
    -- Modification.
    if not public.peut('chambres', 'modifier') then
      raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de modifier une chambre.';
    end if;

    select * into v_chambre
      from public.chambres c
     where c.id = v_id
       for update;

    if not found then
      raise exception 'CHAMBRE_INTROUVABLE|Chambre introuvable : elle a peut-être été supprimée.';
    end if;

    if v_chambre.owner_id is distinct from v_owner and not public.est_plateforme() then
      raise exception 'HORS_BOUTIQUE|Cette chambre n''appartient pas à votre boutique.';
    end if;

    begin
      update public.chambres
         set numero       = v_numero,
             type_chambre = nullif(btrim(coalesce(p_type_chambre, '')), ''),
             capacite     = p_capacite,
             prix_nuit    = coalesce(p_prix_nuit, 0),
             equipements  = nullif(btrim(coalesce(p_equipements, '')), ''),
             actif        = coalesce(p_actif, true),
             updated_at   = now()
       where id = v_id
       returning * into v_chambre;
    exception when unique_violation then
      raise exception 'NUMERO_EXISTE|Une chambre porte déjà le numéro « % ».', v_numero;
    end;

    insert into public.journal_audit (
      id, entreprise_id, action, utilisateur_id, details, created_at
    ) values (
      gen_random_uuid(),
      null,
      'CHAMBRE_MODIFIEE',
      v_user,
      jsonb_build_object(
        'chambre_id', v_chambre.id,
        'numero',     v_chambre.numero
      ),
      now()
    );
  end if;

  return jsonb_build_object('ok', true, 'chambre', to_jsonb(v_chambre));
end;
$$;

revoke all on function public.rpc_chambre_enregistrer(uuid, text, text, integer, real, text, boolean) from public;
revoke all on function public.rpc_chambre_enregistrer(uuid, text, text, integer, real, text, boolean) from anon;
grant execute on function public.rpc_chambre_enregistrer(uuid, text, text, integer, real, text, boolean) to authenticated;


-- ============================================================================
--  4. RPC `rpc_chambre_statut` — CHANGEMENT DE STATUT (ménage, remise en
--     service…)
-- ============================================================================
--  Le STATUT d'une chambre est le travail de la réception : ouvert aux
--  titulaires de `chambres/modifier` (patron) ET de `reception/creer`
--  (réceptionniste). La CONFIGURATION de la chambre reste au patron.

create or replace function public.rpc_chambre_statut(
  p_id     uuid,
  p_statut text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user    uuid := auth.uid();
  v_owner   uuid;
  v_statut  text := lower(btrim(coalesce(p_statut, '')));
  v_chambre public.chambres%rowtype;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour gérer les chambres.';
  end if;

  if v_statut not in ('libre', 'reservee', 'occupee', 'a_nettoyer') then
    raise exception 'STATUT_INVALIDE|Statut de chambre inconnu : « % ».', p_statut;
  end if;

  if not (public.peut('chambres', 'modifier') or public.peut('reception', 'creer')) then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de changer le statut d''une chambre.';
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  select * into v_chambre
    from public.chambres c
   where c.id = p_id
     for update;

  if not found then
    raise exception 'CHAMBRE_INTROUVABLE|Chambre introuvable : elle a peut-être été supprimée.';
  end if;

  if v_chambre.owner_id is distinct from v_owner and not public.est_plateforme() then
    raise exception 'HORS_BOUTIQUE|Cette chambre n''appartient pas à votre boutique.';
  end if;

  -- Un séjour en cours interdit de libérer ou de remettre au nettoyage
  -- « à la main » : on passe d'abord par le check-out.
  if v_statut in ('libre', 'a_nettoyer')
     and exists (
       select 1
         from public.reservations r
        where r.chambre_id = v_chambre.id
          and r.statut = 'en_cours'
     ) then
    raise exception 'SEJOUR_EN_COURS|Un client occupe encore la chambre % (séjour en cours).',
      v_chambre.numero;
  end if;

  -- « réservée » n''a de sens que si une réservation attend réellement.
  if v_statut = 'reservee'
     and not exists (
       select 1
         from public.reservations r
        where r.chambre_id = v_chambre.id
          and r.statut = 'reservee'
     ) then
    raise exception 'AUCUNE_RESERVATION|Aucune réservation en attente pour la chambre %.',
      v_chambre.numero;
  end if;

  update public.chambres
     set statut = v_statut, updated_at = now()
   where id = v_chambre.id
   returning * into v_chambre;

  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(),
    null,
    'CHAMBRE_STATUT',
    v_user,
    jsonb_build_object(
      'chambre_id', v_chambre.id,
      'numero',     v_chambre.numero,
      'statut',     v_chambre.statut
    ),
    now()
  );

  return jsonb_build_object('ok', true, 'chambre', to_jsonb(v_chambre));
end;
$$;

revoke all on function public.rpc_chambre_statut(uuid, text) from public;
revoke all on function public.rpc_chambre_statut(uuid, text) from anon;
grant execute on function public.rpc_chambre_statut(uuid, text) to authenticated;


-- ============================================================================
--  5. RPC `rpc_reservation_creer` — NOUVELLE RÉSERVATION
-- ============================================================================
create or replace function public.rpc_reservation_creer(
  p_chambre_id   uuid,
  p_date_arrivee date,
  p_date_depart  date,
  p_nb_personnes integer default 1,
  p_client_id    bigint default null,
  p_client_nom   text default null,
  p_prix_nuit    real default null,
  p_avance       real default 0,
  p_note         text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user       uuid := auth.uid();
  v_owner      uuid;
  v_chambre    public.chambres%rowtype;
  v_client     record;
  v_client_nom text := nullif(btrim(coalesce(p_client_nom, '')), '');
  v_nuits      integer;
  v_prix       real;
  v_total      real;
  v_avance     real := coalesce(p_avance, 0);
  v_res        public.reservations%rowtype;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour enregistrer une réservation.';
  end if;

  if not public.peut('reservations', 'creer') then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de créer une réservation.';
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  if p_chambre_id is null then
    raise exception 'CHAMBRE_OBLIGATOIRE|Choisissez une chambre.';
  end if;

  select * into v_chambre
    from public.chambres c
   where c.id = p_chambre_id
     for update;

  if not found then
    raise exception 'CHAMBRE_INTROUVABLE|Chambre introuvable : elle a peut-être été supprimée.';
  end if;

  if v_chambre.owner_id is distinct from v_owner and not public.est_plateforme() then
    raise exception 'HORS_BOUTIQUE|Cette chambre n''appartient pas à votre boutique.';
  end if;

  if not v_chambre.actif then
    raise exception 'CHAMBRE_INACTIVE|La chambre % est désactivée.', v_chambre.numero;
  end if;

  if p_date_arrivee is null or p_date_depart is null then
    raise exception 'DATES_OBLIGATOIRES|Indiquez la date d''arrivée et la date de départ.';
  end if;

  if p_date_depart <= p_date_arrivee then
    raise exception 'DATES_INVALIDES|La date de départ doit être postérieure à la date d''arrivée.';
  end if;

  if p_date_arrivee < current_date then
    raise exception 'ARRIVEE_PASSEE|La date d''arrivée (%) est déjà passée.',
      to_char(p_date_arrivee, 'DD/MM/YYYY');
  end if;

  v_nuits := (p_date_depart - p_date_arrivee);
  if v_nuits > 365 then
    raise exception 'DATES_INVALIDES|Séjour trop long : 365 nuits maximum.';
  end if;

  if p_nb_personnes is null or p_nb_personnes < 1 then
    raise exception 'PERSONNES_INVALIDE|Indiquez au moins une personne.';
  end if;

  if p_nb_personnes > v_chambre.capacite then
    raise exception 'CAPACITE_DEPASSEE|La chambre % accueille % personne(s) au maximum.',
      v_chambre.numero, v_chambre.capacite;
  end if;

  -- Deux séjours actifs ne peuvent pas se chevaucher sur la même chambre.
  if exists (
    select 1
      from public.reservations r
     where r.chambre_id = p_chambre_id
       and r.statut in ('reservee', 'en_cours')
       and r.date_arrivee < p_date_depart
       and r.date_depart > p_date_arrivee
  ) then
    raise exception 'CHAMBRE_OCCUPEE|La chambre % est déjà réservée sur cette période.',
      v_chambre.numero;
  end if;

  -- Client : fiche existante (même boutique) ou nom saisi à la réception.
  if p_client_id is not null then
    select c.id, c.owner_id, c.nom
      into v_client
      from public.clients c
     where c.id = p_client_id;

    if not found then
      raise exception 'CLIENT_INTROUVABLE|Client n° % introuvable.', p_client_id;
    end if;

    if v_client.owner_id is distinct from v_owner then
      raise exception 'HORS_ENTREPRISE|Le client % n''appartient pas à votre entreprise.',
        v_client.nom;
    end if;

    v_client_nom := coalesce(v_client_nom, v_client.nom);
  end if;

  if v_client_nom is null then
    raise exception 'CLIENT_OBLIGATOIRE|Indiquez le client (fiche ou nom).';
  end if;

  v_prix := round(coalesce(p_prix_nuit, v_chambre.prix_nuit, 0)::numeric, 2);
  if v_prix < 0 then
    raise exception 'PRIX_INVALIDE|Le prix par nuit ne peut pas être négatif.';
  end if;

  v_total := round((v_nuits * v_prix)::numeric, 2);

  if v_avance < 0 then
    raise exception 'AVANCE_INVALIDE|L''avance ne peut pas être négative.';
  end if;

  if v_avance > v_total then
    raise exception 'AVANCE_EXCESSIVE|L''avance (%) dépasse le montant total du séjour (%).',
      v_avance, v_total;
  end if;

  insert into public.reservations (
    owner_id, chambre_id, client_id, client_nom,
    date_arrivee, date_depart, nb_personnes, prix_nuit,
    montant_total, montant_paye, statut, note, cree_par
  ) values (
    v_owner, p_chambre_id, p_client_id, v_client_nom,
    p_date_arrivee, p_date_depart, p_nb_personnes, v_prix,
    v_total, v_avance, 'reservee',
    nullif(btrim(coalesce(p_note, '')), ''), v_user
  )
  returning * into v_res;

  -- La chambre qui était libre devient « réservée ».
  if v_chambre.statut = 'libre' then
    update public.chambres
       set statut = 'reservee', updated_at = now()
     where id = v_chambre.id;
  end if;

  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(),
    null,
    'RESERVATION',
    v_user,
    jsonb_build_object(
      'reservation_id', v_res.id,
      'chambre',        v_chambre.numero,
      'client',         v_res.client_nom,
      'arrivee',        to_char(v_res.date_arrivee, 'DD/MM/YYYY'),
      'depart',         to_char(v_res.date_depart, 'DD/MM/YYYY'),
      'nuits',          v_nuits,
      'total',          v_total,
      'avance',         v_avance
    ),
    now()
  );

  return jsonb_build_object('ok', true, 'reservation', to_jsonb(v_res));
end;
$$;

revoke all on function public.rpc_reservation_creer(uuid, date, date, integer, bigint, text, real, real, text) from public;
revoke all on function public.rpc_reservation_creer(uuid, date, date, integer, bigint, text, real, real, text) from anon;
grant execute on function public.rpc_reservation_creer(uuid, date, date, integer, bigint, text, real, real, text) to authenticated;


-- ============================================================================
--  6. RPC `rpc_reservation_checkin` — ARRIVÉE DU CLIENT
-- ============================================================================
create or replace function public.rpc_reservation_checkin(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user    uuid := auth.uid();
  v_owner   uuid;
  v_res     public.reservations%rowtype;
  v_chambre public.chambres%rowtype;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour enregistrer une arrivée.';
  end if;

  if not (public.peut('reception', 'creer') or public.peut('reception', 'modifier')) then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas d''enregistrer une arrivée.';
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  select * into v_res
    from public.reservations r
   where r.id = p_id
     for update;

  if not found then
    raise exception 'RESERVATION_INTROUVABLE|Réservation introuvable.';
  end if;

  if v_res.owner_id is distinct from v_owner and not public.est_plateforme() then
    raise exception 'HORS_BOUTIQUE|Cette réservation n''appartient pas à votre boutique.';
  end if;

  if v_res.statut = 'terminee' then
    raise exception 'STATUT_INVALIDE|Ce séjour est déjà terminé.';
  end if;

  if v_res.statut = 'annulee' then
    raise exception 'STATUT_INVALIDE|Cette réservation a été annulée.';
  end if;

  if v_res.statut = 'en_cours' then
    raise exception 'STATUT_INVALIDE|L''arrivée de ce client est déjà enregistrée.';
  end if;

  if v_res.date_arrivee > current_date then
    raise exception 'TROP_TOT|Arrivée prévue le % : le check-in n''est pas encore possible.',
      to_char(v_res.date_arrivee, 'DD/MM/YYYY');
  end if;

  if exists (
    select 1
      from public.reservations r
     where r.chambre_id = v_res.chambre_id
       and r.statut = 'en_cours'
       and r.id <> v_res.id
  ) then
    raise exception 'CHAMBRE_OCCUPEE|Un autre séjour est en cours dans cette chambre.';
  end if;

  select * into v_chambre
    from public.chambres c
   where c.id = v_res.chambre_id
     for update;

  if not found then
    raise exception 'CHAMBRE_INTROUVABLE|La chambre de cette réservation n''existe plus.';
  end if;

  update public.reservations
     set statut = 'en_cours', updated_at = now()
   where id = v_res.id
   returning * into v_res;

  update public.chambres
     set statut = 'occupee', updated_at = now()
   where id = v_chambre.id;

  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(),
    null,
    'CHECKIN_SEJOUR',
    v_user,
    jsonb_build_object(
      'reservation_id', v_res.id,
      'chambre',        v_chambre.numero,
      'client',         v_res.client_nom
    ),
    now()
  );

  return jsonb_build_object('ok', true, 'reservation', to_jsonb(v_res));
end;
$$;

revoke all on function public.rpc_reservation_checkin(uuid) from public;
revoke all on function public.rpc_reservation_checkin(uuid) from anon;
grant execute on function public.rpc_reservation_checkin(uuid) to authenticated;


-- ============================================================================
--  7. RPC `rpc_reservation_checkout` — DÉPART + ENCAISSEMENT DU SOLDE
-- ============================================================================
--  [p_montant_paye] (facultatif) = somme encaissée AU DÉPART (solde réglé
--  à la réception). La chambre repasse en « à nettoyer ».

create or replace function public.rpc_reservation_checkout(
  p_id            uuid,
  p_montant_paye  real default null,
  p_mode_paiement text default 'especes'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user    uuid := auth.uid();
  v_owner   uuid;
  v_res     public.reservations%rowtype;
  v_chambre public.chambres%rowtype;
  v_paye    real := coalesce(p_montant_paye, 0);
  v_solde   real;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour enregistrer un départ.';
  end if;

  if not (public.peut('reception', 'creer') or public.peut('reception', 'modifier')) then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas d''enregistrer un départ.';
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  if v_paye < 0 then
    raise exception 'MONTANT_INVALIDE|Le montant encaissé ne peut pas être négatif.';
  end if;

  select * into v_res
    from public.reservations r
   where r.id = p_id
     for update;

  if not found then
    raise exception 'RESERVATION_INTROUVABLE|Réservation introuvable.';
  end if;

  if v_res.owner_id is distinct from v_owner and not public.est_plateforme() then
    raise exception 'HORS_BOUTIQUE|Cette réservation n''appartient pas à votre boutique.';
  end if;

  if v_res.statut <> 'en_cours' then
    raise exception 'STATUT_INVALIDE|Le check-out ne concerne qu''un séjour en cours.';
  end if;

  if v_paye > 0 and (v_res.montant_paye + v_paye) > v_res.montant_total then
    raise exception 'MONTANT_EXCEDENT|Le total encaissé dépasserait le montant du séjour (reste à payer : %).',
      greatest(v_res.montant_total - v_res.montant_paye, 0);
  end if;

  update public.reservations
     set statut        = 'terminee',
         montant_paye  = v_res.montant_paye + v_paye,
         updated_at    = now()
   where id = v_res.id
   returning * into v_res;

  select * into v_chambre
    from public.chambres c
   where c.id = v_res.chambre_id;

  if found then
    update public.chambres
       set statut = 'a_nettoyer', updated_at = now()
     where id = v_chambre.id;
  end if;

  v_solde := greatest(v_res.montant_total - v_res.montant_paye, 0);

  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(),
    null,
    'CHECKOUT_SEJOUR',
    v_user,
    jsonb_build_object(
      'reservation_id', v_res.id,
      'chambre',        case when v_chambre.id is null then null else v_chambre.numero end,
      'client',         v_res.client_nom,
      'encaisse',       v_paye,
      'solde_restant',  v_solde,
      'mode_paiement',  nullif(btrim(lower(coalesce(p_mode_paiement, ''))), '')
    ),
    now()
  );

  return jsonb_build_object(
    'ok', true,
    'reservation', to_jsonb(v_res),
    'solde', v_solde
  );
end;
$$;

revoke all on function public.rpc_reservation_checkout(uuid, real, text) from public;
revoke all on function public.rpc_reservation_checkout(uuid, real, text) from anon;
grant execute on function public.rpc_reservation_checkout(uuid, real, text) to authenticated;


-- ============================================================================
--  8. RPC `rpc_reservation_encaisser` — AVANCE OU ACOMPTE
-- ============================================================================
create or replace function public.rpc_reservation_encaisser(
  p_id       uuid,
  p_montant  real,
  p_mode     text default 'especes'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user  uuid := auth.uid();
  v_owner uuid;
  v_res   public.reservations%rowtype;
  v_solde real;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour encaisser un séjour.';
  end if;

  if not (public.peut('reception', 'creer')
          or public.peut('reservations', 'modifier')) then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas d''encaisser un séjour.';
  end if;

  if p_montant is null or p_montant <= 0 then
    raise exception 'MONTANT_INVALIDE|Le montant encaissé doit être supérieur à zéro.';
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  select * into v_res
    from public.reservations r
   where r.id = p_id
     for update;

  if not found then
    raise exception 'RESERVATION_INTROUVABLE|Réservation introuvable.';
  end if;

  if v_res.owner_id is distinct from v_owner and not public.est_plateforme() then
    raise exception 'HORS_BOUTIQUE|Cette réservation n''appartient pas à votre boutique.';
  end if;

  if v_res.statut not in ('reservee', 'en_cours') then
    raise exception 'STATUT_INVALIDE|Ce séjour est clos : plus aucun encaissement possible.';
  end if;

  if (v_res.montant_paye + p_montant) > v_res.montant_total then
    raise exception 'MONTANT_EXCEDENT|Le total encaissé dépasserait le montant du séjour (reste à payer : %).',
      greatest(v_res.montant_total - v_res.montant_paye, 0);
  end if;

  update public.reservations
     set montant_paye = v_res.montant_paye + p_montant,
         updated_at   = now()
   where id = v_res.id
   returning * into v_res;

  v_solde := greatest(v_res.montant_total - v_res.montant_paye, 0);

  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(),
    null,
    'SEJOUR_ENCAISSE',
    v_user,
    jsonb_build_object(
      'reservation_id', v_res.id,
      'client',         v_res.client_nom,
      'montant',        p_montant,
      'mode_paiement',  nullif(btrim(lower(coalesce(p_mode, ''))), ''),
      'solde_restant',  v_solde
    ),
    now()
  );

  return jsonb_build_object(
    'ok', true,
    'reservation', to_jsonb(v_res),
    'solde', v_solde
  );
end;
$$;

revoke all on function public.rpc_reservation_encaisser(uuid, real, text) from public;
revoke all on function public.rpc_reservation_encaisser(uuid, real, text) from anon;
grant execute on function public.rpc_reservation_encaisser(uuid, real, text) to authenticated;


-- ============================================================================
--  9. RPC `rpc_reservation_annuler`
-- ============================================================================
--  Seule une réservation EN ATTENTE peut être annulée : un client déjà
--  arrivé se clôture par le check-out (même le jour même).

create or replace function public.rpc_reservation_annuler(
  p_id    uuid,
  p_motif text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user    uuid := auth.uid();
  v_owner   uuid;
  v_res     public.reservations%rowtype;
  v_chambre public.chambres%rowtype;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour annuler une réservation.';
  end if;

  if not (public.peut('reservations', 'creer')
          or public.peut('reception', 'creer')
          or public.peut('reservations', 'modifier')) then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas d''annuler une réservation.';
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  select * into v_res
    from public.reservations r
   where r.id = p_id
     for update;

  if not found then
    raise exception 'RESERVATION_INTROUVABLE|Réservation introuvable.';
  end if;

  if v_res.owner_id is distinct from v_owner and not public.est_plateforme() then
    raise exception 'HORS_BOUTIQUE|Cette réservation n''appartient pas à votre boutique.';
  end if;

  if v_res.statut <> 'reservee' then
    raise exception 'STATUT_INVALIDE|Seule une réservation en attente peut être annulée.';
  end if;

  update public.reservations
     set statut           = 'annulee',
         motif_annulation = nullif(btrim(coalesce(p_motif, '')), ''),
         updated_at       = now()
   where id = v_res.id
   returning * into v_res;

  -- La chambre redevient libre si plus rien ne l''attend.
  select * into v_chambre
    from public.chambres c
   where c.id = v_res.chambre_id;

  if found and v_chambre.statut = 'reservee'
     and not exists (
       select 1
         from public.reservations r
        where r.chambre_id = v_chambre.id
          and r.statut in ('reservee', 'en_cours')
     ) then
    update public.chambres
       set statut = 'libre', updated_at = now()
     where id = v_chambre.id;
  end if;

  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(),
    null,
    'RESERVATION_ANNULEE',
    v_user,
    jsonb_build_object(
      'reservation_id', v_res.id,
      'client',         v_res.client_nom,
      'motif',          v_res.motif_annulation
    ),
    now()
  );

  return jsonb_build_object('ok', true, 'reservation', to_jsonb(v_res));
end;
$$;

revoke all on function public.rpc_reservation_annuler(uuid, text) from public;
revoke all on function public.rpc_reservation_annuler(uuid, text) from anon;
grant execute on function public.rpc_reservation_annuler(uuid, text) to authenticated;


-- ============================================================================
-- 10. RPC `rpc_hotel_tableau_bord` — OCCUPATION & MOUVEMENTS DU JOUR
-- ============================================================================
create or replace function public.rpc_hotel_tableau_bord()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user        uuid := auth.uid();
  v_owner       uuid;
  v_total       integer := 0;
  v_libres      integer := 0;
  v_reservees   integer := 0;
  v_occupees    integer := 0;
  v_a_nettoyer  integer := 0;
  v_actives     integer := 0;
  v_arrivees    integer := 0;
  v_departs     integer := 0;
  v_occupation  numeric := 0;
  v_liste_arrivees jsonb := '[]'::jsonb;
  v_liste_departs  jsonb := '[]'::jsonb;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour consulter l''hôtel.';
  end if;

  if not (public.peut('chambres', 'voir')
          or public.peut('reservations', 'voir')
          or public.peut('reception', 'voir')
          or public.est_plateforme()) then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de consulter l''hôtel.';
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  -- Occupation par statut.
  select count(*),
         count(*) filter (where statut = 'libre'),
         count(*) filter (where statut = 'reservee'),
         count(*) filter (where statut = 'occupee'),
         count(*) filter (where statut = 'a_nettoyer')
    into v_total, v_libres, v_reservees, v_occupees, v_a_nettoyer
    from public.chambres c
   where c.owner_id = v_owner
     and c.actif;

  v_occupation := case when v_total > 0
                       then round((100.0 * v_occupees / v_total)::numeric, 1)
                       else 0 end;

  select count(*)
    into v_actives
    from public.reservations r
   where r.owner_id = v_owner
     and r.statut in ('reservee', 'en_cours');

  -- Arrivées attendues : réservations dont la date d''arrivée est atteinte.
  select count(*),
         coalesce(jsonb_agg(jsonb_build_object(
           'id',            r.id,
           'chambre',       c.numero,
           'client',        r.client_nom,
           'date_arrivee',  to_char(r.date_arrivee, 'DD/MM/YYYY'),
           'date_depart',   to_char(r.date_depart, 'DD/MM/YYYY'),
           'nb_personnes',  r.nb_personnes,
           'montant_total', r.montant_total,
           'montant_paye',  r.montant_paye,
           'solde',         greatest(r.montant_total - r.montant_paye, 0),
           'retard',        (r.date_arrivee < current_date)
         ) order by c.numero), '[]'::jsonb)
    into v_arrivees, v_liste_arrivees
    from public.reservations r
    join public.chambres c on c.id = r.chambre_id
   where r.owner_id = v_owner
     and r.statut = 'reservee'
     and r.date_arrivee <= current_date;

  -- Départs attendus : séjours en cours dont la date de départ est atteinte.
  select count(*),
         coalesce(jsonb_agg(jsonb_build_object(
           'id',            r.id,
           'chambre',       c.numero,
           'client',        r.client_nom,
           'date_arrivee',  to_char(r.date_arrivee, 'DD/MM/YYYY'),
           'date_depart',   to_char(r.date_depart, 'DD/MM/YYYY'),
           'nb_personnes',  r.nb_personnes,
           'montant_total', r.montant_total,
           'montant_paye',  r.montant_paye,
           'solde',         greatest(r.montant_total - r.montant_paye, 0),
           'retard',        (r.date_depart < current_date)
         ) order by c.numero), '[]'::jsonb)
    into v_departs, v_liste_departs
    from public.reservations r
    join public.chambres c on c.id = r.chambre_id
   where r.owner_id = v_owner
     and r.statut = 'en_cours'
     and r.date_depart <= current_date;

  return jsonb_build_object(
    'ok', true,
    'chambres', jsonb_build_object(
      'total',      v_total,
      'libres',     v_libres,
      'reservees',  v_reservees,
      'occupees',   v_occupees,
      'a_nettoyer', v_a_nettoyer
    ),
    'occupation',           v_occupation,
    'reservations_actives', v_actives,
    'arrivees_count',       v_arrivees,
    'departs_count',        v_departs,
    'arrivees',             v_liste_arrivees,
    'departs',              v_liste_departs
  );
end;
$$;

revoke all on function public.rpc_hotel_tableau_bord() from public;
revoke all on function public.rpc_hotel_tableau_bord() from anon;
grant execute on function public.rpc_hotel_tableau_bord() to authenticated;


-- ============================================================================
-- 11. JOURNAL D'AUDIT — NIVEAUX DES ACTIONS HÔTEL
-- ============================================================================
--  Copie de la fonction du Module 12 + nouvelles actions :
--    • CHECKOUT_SEJOUR et SEJOUR_ENCAISSE touchent l'argent → HAUT ;
--    • le reste de la gestion hôtelière → MOYEN.

create or replace function public.audit_niveau(p_action text)
returns text
language sql
immutable
as $$
  select case upper(btrim(coalesce(p_action, '')))
    -- CRITIQUE : argent, droits, cycle de vie des comptes.
    when 'CREATION_ENTREPRISE'        then 'CRITIQUE'
    when 'CHANGEMENT_STATUT'          then 'CRITIQUE'
    when 'REACTIVATION'               then 'CRITIQUE'
    when 'CHANGEMENT_ROLE'            then 'CRITIQUE'
    when 'PERMISSIONS_MODIFIEES'      then 'CRITIQUE'
    when 'PERMISSIONS_REINITIALISEES' then 'CRITIQUE'
    when 'PRIX_MODIFIE'               then 'CRITIQUE'
    when 'ANNULATION_VENTE'           then 'CRITIQUE'
    when 'VENTE_SUPPRIMEE'            then 'CRITIQUE'
    when 'UTILISATEUR_SUPPRIME'       then 'CRITIQUE'
    when 'ENTREPRISE_SUPPRIMEE'       then 'CRITIQUE'
    -- HAUT : opérations financières et mouvements de stock.
    when 'VENTE'                      then 'HAUT'
    when 'PAIEMENT_ENREGISTRE'        then 'HAUT'
    when 'PAIEMENT_DETTE'             then 'HAUT'
    when 'DETTE'                      then 'HAUT'
    when 'DEPENSE'                    then 'HAUT'
    when 'CLOTURE_CAISSE'             then 'HAUT'
    when 'APPROVISIONNEMENT'          then 'HAUT'
    when 'AJUSTEMENT'                 then 'HAUT'
    when 'INVENTAIRE'                 then 'HAUT'
    when 'STOCK_MODIFIE'              then 'HAUT'
    when 'ARTICLE_SUPPRIME'           then 'HAUT'
    when 'CHANGEMENT_ACTIVATION'      then 'HAUT'
    when 'IMPORT_PRODUITS'            then 'HAUT'
    -- 🏨 MODULE 16 C2 — hôtel : départs et encaissements de séjour.
    when 'CHECKOUT_SEJOUR'            then 'HAUT'
    when 'SEJOUR_ENCAISSE'            then 'HAUT'
    -- MOYEN : administration courante et sessions.
    when 'CONNEXION'                  then 'MOYEN'
    when 'DECONNEXION'                then 'MOYEN'
    when 'CONNEXION_ECHEC'            then 'MOYEN'
    when 'ARTICLE_CREE'               then 'MOYEN'
    when 'ARTICLE_MODIFIE'            then 'MOYEN'
    when 'CONDITIONNEMENT_AJOUTE'     then 'MOYEN'
    when 'CONDITIONNEMENT_MODIFIE'    then 'MOYEN'
    when 'CONDITIONNEMENT_SUPPRIME'   then 'MOYEN'
    when 'UTILISATEUR_CREE'           then 'MOYEN'
    when 'UTILISATEUR_MODIFIE'        then 'MOYEN'
    when 'ENTREPRISE_MODIFIEE'        then 'MOYEN'
    when 'RELANCE_DETTE'              then 'MOYEN'
    -- 🏨 MODULE 16 C2 — hôtel : gestion courante des chambres & séjours.
    when 'CHAMBRE_ENREGISTREE'        then 'MOYEN'
    when 'CHAMBRE_MODIFIEE'           then 'MOYEN'
    when 'CHAMBRE_STATUT'             then 'MOYEN'
    when 'RESERVATION'                then 'MOYEN'
    when 'RESERVATION_ANNULEE'        then 'MOYEN'
    when 'CHECKIN_SEJOUR'             then 'MOYEN'
    when 'RAPPORT'                    then 'INFO'
    else 'INFO'
  end;
$$;

comment on function public.audit_niveau(text) is
  'Niveau de gravité d''une action du journal d''audit (CRITIQUE/HAUT/MOYEN/INFO).';


-- ============================================================================
-- 12. PERMISSIONS — PAGES `chambres`, `reservations`, `reception`
-- ============================================================================
--  • PROPRIÉTAIRE : toutes les actions sur les trois pages ;
--  • VENDEUR (réceptionniste) : consulte les chambres, gère le planning
--    (voir + créer) et les arrivées/départs (voir + créer) — jamais la
--    configuration des chambres, la modification ni la suppression.

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
    'chambres', 'reservations', 'reception'
  ];
$$;

comment on function public.pages_permissions() is
  'Liste officielle des pages de permission (Module 4, + securite Module 12, + assistant_ia Module 13, + hôtel Module 16 C2).';

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
                         'chambres', 'reservations', 'reception'];
      v_actions := public.actions_permissions();

    when 'VENDEUR' then
      v_pages   := array['ventes', 'caisse', 'scanner', 'panier', 'assistant_ia',
                         -- 🏨 MODULE 16 C2 — réceptionniste d'hôtel.
                         'chambres', 'reservations', 'reception'];
      v_actions := array['voir', 'creer'];

    when 'MAGASINIER' then
      v_pages   := array['stock', 'articles', 'qr_codes', 'rapports',
                         'assistant_ia'];
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
    when 'COMPTABLE_ENTREPRISE' then v_result
      || jsonb_build_object('depenses',     to_jsonb(array['voir', 'creer', 'valider']))
      || jsonb_build_object('rapports',     to_jsonb(array['voir', 'valider']))
      || jsonb_build_object('assistant_ia', to_jsonb(array['voir', 'creer']))
    when 'VENDEUR' then v_result
      -- 🏨 MODULE 16 C2 — les chambres se CONSULTENT (configuration = patron).
      || jsonb_build_object('chambres', to_jsonb(array['voir']))
    else v_result
  end;

  return v_result;
end;
$$;

comment on function public.permissions_defaut(text) is
  'Matrice des permissions par défaut (Module 4, + audit/securite Module 12, + assistant_ia Module 13, + hôtel Module 16 C2).';


-- ============================================================================
-- 13. VÉRIFICATIONS
-- ============================================================================

-- 13.a Les deux tables existent (attendu : 2).
select count(*) as tables_hotel
  from information_schema.tables
 where table_schema = 'public'
   and table_name in ('chambres', 'reservations');

-- 13.b La page `chambres` est déclarée (attendu : true).
select position('chambres' in array_to_string(public.pages_permissions(), ',')) > 0
       as page_chambres;

-- 13.c Matrices par défaut (attendu : true / ["voir","creer"]).
select (public.permissions_defaut('PROPRIETAIRE') ? 'reception') as proprio_reception,
       (public.permissions_defaut('VENDEUR') -> 'reservations') as vendeur_reservations;

-- 13.d Exemple d'appel (à exécuter avec un vrai compte) :
--     select public.rpc_hotel_tableau_bord();

-- ============================================================================
--  FIN — Module 16 C2 (hôtel). L'application (prochaine version) affiche les
--  cartes « Chambres », « Réservations » et « Réception », gère le check-in /
--  check-out et la facture de séjour.
-- ============================================================================
