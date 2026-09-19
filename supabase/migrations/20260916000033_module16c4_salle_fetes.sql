-- ============================================================================
--  biashara_yangu — MODULE 16 (PHASE C4) : SALLE DES FÊTES — SALLES & ÉVÉNEMENTS
--
--  OBJECTIF (roadmap multi-activités, module C4) :
--    Le type d'activité « Salle des fêtes » active les modules `salles`
--    et `evenements` :
--      • salles : nom, capacité, prix par jour, équipements, actif ;
--      • événements : titre, type (mariage, anniversaire, réunion…),
--        client (fiche ou nom libre), dates + heures, invités,
--        prix négocié par jour, avance / solde ;
--      • prestations : lignes libres ajoutées au dossier (traiteur,
--        décoration, sonorisation…) qui s'AJOUTENT au prix de la salle ;
--      • cycle : réservé → confirmé → en cours → terminé (ou annulé) ;
--      • tableau de bord événementiel (salles, événements du jour,
--        à venir, encaissé et solde).
--
--  CONTENU :
--    1. tables `salles`, `evenements`, `lignes_evenement` (+ index + RLS) ;
--    2. RPC salle (enregistrer) ;
--    3. RPC événement (enregistrer / prestations / statut / encaisser) ;
--    4. RPC tableau de bord salle des fêtes ;
--    5. permissions : pages `salles` et `evenements` ;
--    6. journal d'audit : niveaux des nouvelles actions ;
--    7. profil « Salle des fêtes » du référentiel des activités.
--
--  OÙ : Supabase → SQL Editor → coller → Run
--  IDEMPOTENT : peut être relancé sans effet de bord.
-- ============================================================================


-- ============================================================================
--  1.a TABLE `public.salles`
-- ============================================================================
--  Une salle appartient à une boutique (owner_id = patron, comme les
--  articles et les chambres). Pas de « statut » figé : l'occupation se
--  déduit des événements actifs de son calendrier.

create table if not exists public.salles (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null,
  nom         text not null,
  capacite    integer not null default 50,
  prix_jour   real not null default 0,
  description text,
  equipements text,
  actif       boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  constraint salles_capacite_check check (capacite >= 1 and capacite <= 10000),
  constraint salles_prix_check check (prix_jour >= 0)
);

create unique index if not exists idx_salles_owner_nom
  on public.salles (owner_id, nom);
create index if not exists idx_salles_owner_actif
  on public.salles (owner_id, actif);

comment on table public.salles is
  'Module 16 C4 (salle des fêtes) — salles : nom, capacité, prix par jour, équipements et état actif.';


-- ============================================================================
--  1.b TABLE `public.evenements`
-- ============================================================================
--  Le client est soit une fiche existante (`client_id`), soit un simple nom
--  saisi (`client_nom`). Les montants sont des SNAPSHOTS : modifier le prix
--  de la salle plus tard ne change pas un événement déjà enregistré.
--  `montant_salle` = prix négocié × nombre de jours ; `montant_total` =
--  montant_salle + prestations (lignes_evenement).

create table if not exists public.evenements (
  id               uuid primary key default gen_random_uuid(),
  owner_id         uuid not null,
  salle_id         uuid not null references public.salles (id),
  numero           text,
  titre            text not null,
  type_evenement   text default '',
  client_id        bigint references public.clients (id),
  client_nom       text not null,
  telephone        text,
  date_debut       date not null,
  date_fin         date not null,
  heure_debut      text,
  heure_fin        text,
  nb_invites       integer not null default 0,
  prix_jour        real not null default 0,
  montant_salle    real not null default 0,
  montant_total    real not null default 0,
  montant_paye     real not null default 0,
  statut           text not null default 'reserve',
  note             text,
  motif_annulation text,
  cree_par         uuid,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  constraint evenements_dates_check check (date_fin >= date_debut),
  constraint evenements_invites_check check (nb_invites >= 0),
  constraint evenements_montants_check check (
    prix_jour >= 0 and montant_salle >= 0 and montant_total >= 0
    and montant_paye >= 0
  ),
  constraint evenements_statut_check check (statut in
    ('reserve', 'confirme', 'en_cours', 'termine', 'annule'))
);

create index if not exists idx_evenements_owner_debut
  on public.evenements (owner_id, date_debut);
create index if not exists idx_evenements_salle
  on public.evenements (salle_id, date_debut);
create index if not exists idx_evenements_owner_statut
  on public.evenements (owner_id, statut);

comment on table public.evenements is
  'Module 16 C4 (salle des fêtes) — événements : réservé → confirmé → en cours → terminé (ou annulé), avec avance et solde.';
comment on column public.evenements.montant_total is
  'Montant de la salle (prix/jour × jours) + prestations (lignes_evenement), figé au moment de la saisie.';
comment on column public.evenements.montant_paye is
  'Total encaissé sur l''événement (avances + soldes), toujours ≤ montant_total.';


-- ============================================================================
--  1.c TABLE `public.lignes_evenement`
-- ============================================================================
--  Prestations libres du dossier : traiteur, décoration, sonorisation…
--  Le libellé et le prix sont saisis (aucun lien au catalogue) : ces
--  services n'entrent pas dans le stock.

create table if not exists public.lignes_evenement (
  id           uuid primary key default gen_random_uuid(),
  evenement_id uuid not null references public.evenements (id) on delete cascade,
  libelle      text not null,
  quantite     numeric not null default 1,
  prix_unitaire real not null default 0,
  total        real not null default 0,
  created_at   timestamptz not null default now(),
  constraint lignes_evenement_quantite_check check (quantite > 0),
  constraint lignes_evenement_prix_check check (prix_unitaire >= 0)
);

create index if not exists idx_lignes_evenement_evenement
  on public.lignes_evenement (evenement_id, created_at);

comment on table public.lignes_evenement is
  'Module 16 C4 (salle des fêtes) — prestations d''un événement (traiteur, décoration…) ajoutées au prix de la salle.';


-- ============================================================================
--  2. RLS — LECTURE PAR LA BOUTIQUE, ÉCRITURE CONTRÔLÉE
-- ============================================================================
--  Salles : lecture + écritures directes encadrées par RLS (même modèle que
--  les chambres) ; événements et prestations : lecture seule en direct,
--  écritures UNIQUEMENT via les RPC (chevauchements, montants, statuts).

alter table public.salles          enable row level security;
alter table public.evenements      enable row level security;
alter table public.lignes_evenement enable row level security;

drop policy if exists salles_lecture            on public.salles;
drop policy if exists salles_creation           on public.salles;
drop policy if exists salles_modification       on public.salles;
drop policy if exists salles_suppression        on public.salles;
drop policy if exists evenements_lecture        on public.evenements;
drop policy if exists lignes_evenement_lecture  on public.lignes_evenement;

create policy salles_lecture on public.salles
  for select to authenticated
  using (
    owner_id = auth.uid()
    or owner_id = public.mon_proprietaire()
    or public.est_plateforme()
  );

create policy salles_creation on public.salles
  for insert to authenticated
  with check (
    (owner_id = auth.uid() or owner_id = public.mon_proprietaire())
    and public.peut('salles', 'creer')
  );

create policy salles_modification on public.salles
  for update to authenticated
  using (
    (owner_id = auth.uid() or owner_id = public.mon_proprietaire())
    and public.peut('salles', 'modifier')
  )
  with check (
    (owner_id = auth.uid() or owner_id = public.mon_proprietaire())
    and public.peut('salles', 'modifier')
  );

create policy salles_suppression on public.salles
  for delete to authenticated
  using (
    (owner_id = auth.uid() or owner_id = public.mon_proprietaire())
    and public.peut('salles', 'supprimer')
  );

create policy evenements_lecture on public.evenements
  for select to authenticated
  using (
    owner_id = auth.uid()
    or owner_id = public.mon_proprietaire()
    or public.est_plateforme()
  );

create policy lignes_evenement_lecture on public.lignes_evenement
  for select to authenticated
  using (
    exists (
      select 1
        from public.evenements e
       where e.id = lignes_evenement.evenement_id
         and (e.owner_id = auth.uid()
              or e.owner_id = public.mon_proprietaire()
              or public.est_plateforme())
    )
  );


-- ============================================================================
--  3. RPC `rpc_salle_enregistrer` — CRÉATION / MODIFICATION D'UNE SALLE
-- ============================================================================
create or replace function public.rpc_salle_enregistrer(
  p_id          uuid    default null,
  p_nom         text    default '',
  p_capacite    integer default 50,
  p_prix_jour   real    default 0,
  p_description text    default null,
  p_equipements text    default null,
  p_actif       boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user  uuid := auth.uid();
  v_owner uuid;
  v_nom   text := btrim(coalesce(p_nom, ''));
  v_id    uuid := p_id;
  v_salle public.salles%rowtype;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour gérer les salles.';
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  if v_nom = '' then
    raise exception 'NOM_OBLIGATOIRE|Le nom de la salle est obligatoire.';
  end if;
  if length(v_nom) > 80 then
    raise exception 'NOM_INVALIDE|Nom trop long (80 caractères maximum).';
  end if;
  if p_capacite is null or p_capacite < 1 or p_capacite > 10000 then
    raise exception 'CAPACITE_INVALIDE|La capacité doit être comprise entre 1 et 10 000 personnes.';
  end if;
  if coalesce(p_prix_jour, 0) < 0 then
    raise exception 'PRIX_INVALIDE|Le prix par jour ne peut pas être négatif.';
  end if;

  if v_id is null then
    -- Création.
    if not public.peut('salles', 'creer') then
      raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de créer une salle.';
    end if;

    begin
      insert into public.salles (
        owner_id, nom, capacite, prix_jour, description, equipements, actif
      ) values (
        v_owner,
        v_nom,
        p_capacite,
        coalesce(p_prix_jour, 0),
        nullif(btrim(coalesce(p_description, '')), ''),
        nullif(btrim(coalesce(p_equipements, '')), ''),
        coalesce(p_actif, true)
      )
      returning * into v_salle;
    exception when unique_violation then
      raise exception 'NOM_EXISTE|Une salle porte déjà le nom « % ».', v_nom;
    end;

    insert into public.journal_audit (
      id, entreprise_id, action, utilisateur_id, details, created_at
    ) values (
      gen_random_uuid(), null, 'SALLE_ENREGISTREE', v_user,
      jsonb_build_object('salle_id', v_salle.id, 'nom', v_salle.nom, 'creation', true),
      now()
    );
  else
    -- Modification.
    if not public.peut('salles', 'modifier') then
      raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de modifier une salle.';
    end if;

    select * into v_salle
      from public.salles s
     where s.id = v_id
       for update;

    if not found then
      raise exception 'SALLE_INTROUVABLE|Salle introuvable : elle a peut-être été supprimée.';
    end if;

    if v_salle.owner_id is distinct from v_owner and not public.est_plateforme() then
      raise exception 'HORS_BOUTIQUE|Cette salle n''appartient pas à votre boutique.';
    end if;

    begin
      update public.salles
         set nom         = v_nom,
             capacite    = p_capacite,
             prix_jour   = coalesce(p_prix_jour, 0),
             description = nullif(btrim(coalesce(p_description, '')), ''),
             equipements = nullif(btrim(coalesce(p_equipements, '')), ''),
             actif       = coalesce(p_actif, true),
             updated_at  = now()
       where id = v_id
       returning * into v_salle;
    exception when unique_violation then
      raise exception 'NOM_EXISTE|Une salle porte déjà le nom « % ».', v_nom;
    end;

    insert into public.journal_audit (
      id, entreprise_id, action, utilisateur_id, details, created_at
    ) values (
      gen_random_uuid(), null, 'SALLE_MODIFIEE', v_user,
      jsonb_build_object('salle_id', v_salle.id, 'nom', v_salle.nom),
      now()
    );
  end if;

  return jsonb_build_object('ok', true, 'salle', to_jsonb(v_salle));
end;
$$;

revoke all on function public.rpc_salle_enregistrer(uuid, text, integer, real, text, text, boolean) from public;
revoke all on function public.rpc_salle_enregistrer(uuid, text, integer, real, text, text, boolean) from anon;
grant execute on function public.rpc_salle_enregistrer(uuid, text, integer, real, text, text, boolean) to authenticated;


-- ============================================================================
--  4. RPC `rpc_evenement_enregistrer` — CRÉATION / MODIFICATION
-- ============================================================================
--  • Vérifie que la salle est libre sur la période (chevauchement refusé) ;
--  • fige le prix du jour et calcule montant_salle = prix × jours ;
--  • l'avance éventuelle est encaissée à la création (≤ total) ;
--  • la modification ne touche JAMAIS aux montants déjà encaissés.

create or replace function public.rpc_evenement_enregistrer(
  p_id             uuid    default null,
  p_salle_id       uuid    default null,
  p_titre          text    default '',
  p_type_evenement text    default '',
  p_client_id      bigint  default null,
  p_client_nom     text    default '',
  p_telephone      text    default null,
  p_date_debut     date    default null,
  p_date_fin       date    default null,
  p_heure_debut    text    default null,
  p_heure_fin      text    default null,
  p_nb_invites     integer default 0,
  p_prix_jour      real    default null,
  p_avance         real    default 0,
  p_note           text    default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user       uuid := auth.uid();
  v_owner      uuid;
  v_id         uuid := p_id;
  v_titre      text := btrim(coalesce(p_titre, ''));
  v_client_nom text := btrim(coalesce(p_client_nom, ''));
  v_debut      date := p_date_debut;
  v_fin        date := coalesce(p_date_fin, p_date_debut);
  v_salle      public.salles%rowtype;
  v_evenement  public.evenements%rowtype;
  v_jours      integer;
  v_prix_jour  real;
  v_montant_salle real;
  v_prestations   real := 0;
  v_montant_total real;
  v_avance     real := coalesce(p_avance, 0);
  v_seq        integer := 0;
  v_numero     text;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour gérer les événements.';
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  -- ------------------------------------------------------------- validations
  if v_titre = '' then
    raise exception 'TITRE_OBLIGATOIRE|Donnez un titre à l''événement (mariage, anniversaire…).';
  end if;
  if length(v_titre) > 120 then
    raise exception 'TITRE_INVALIDE|Titre trop long (120 caractères maximum).';
  end if;
  if v_client_nom = '' then
    raise exception 'CLIENT_OBLIGATOIRE|Indiquez le nom du client.';
  end if;
  if v_debut is null then
    raise exception 'DATES_OBLIGATOIRES|La date de l''événement est obligatoire.';
  end if;
  if v_fin < v_debut then
    raise exception 'DATES_INVALIDES|La date de fin ne peut pas précéder la date de début.';
  end if;

  v_jours := (v_fin - v_debut) + 1;
  if v_jours > 366 then
    raise exception 'DATES_INVALIDES|Un événement ne peut pas dépasser 366 jours.';
  end if;

  if coalesce(p_nb_invites, 0) < 0 then
    raise exception 'INVITES_INVALIDE|Le nombre d''invités ne peut pas être négatif.';
  end if;

  if p_salle_id is null then
    raise exception 'SALLE_OBLIGATOIRE|Choisissez une salle.';
  end if;

  select * into v_salle
    from public.salles s
   where s.id = p_salle_id
     for update;

  if not found then
    raise exception 'SALLE_INTROUVABLE|Salle introuvable : elle a peut-être été supprimée.';
  end if;

  if v_salle.owner_id is distinct from v_owner and not public.est_plateforme() then
    raise exception 'HORS_BOUTIQUE|Cette salle n''appartient pas à votre boutique.';
  end if;

  if not v_salle.actif and v_id is null then
    raise exception 'SALLE_INACTIVE|La salle « % » est désactivée.', v_salle.nom;
  end if;

  if coalesce(p_nb_invites, 0) > v_salle.capacite then
    raise exception 'CAPACITE_DEPASSEE|La salle « % » accueille au maximum % personnes.',
      v_salle.nom, v_salle.capacite;
  end if;

  -- Chevauchement : une salle ne peut pas porter deux événements actifs
  -- sur des dates qui se recoupent (bornes incluses).
  if exists (
    select 1
      from public.evenements e
     where e.salle_id = p_salle_id
       and e.id is distinct from v_id
       and e.statut in ('reserve', 'confirme', 'en_cours')
       and e.date_debut <= v_fin
       and e.date_fin >= v_debut
  ) then
    raise exception 'SALLE_OCCUPEE|La salle « % » est déjà réservée sur ces dates.',
      v_salle.nom;
  end if;

  if v_id is null then
    -- =====================================================================
    --  CRÉATION
    -- =====================================================================
    if not public.peut('evenements', 'creer') then
      raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de créer un événement.';
    end if;

    v_prix_jour := coalesce(p_prix_jour, v_salle.prix_jour, 0);
    if v_prix_jour < 0 then
      raise exception 'PRIX_INVALIDE|Le prix par jour ne peut pas être négatif.';
    end if;

    v_montant_salle := round((v_jours * v_prix_jour)::numeric, 2);
    v_montant_total := v_montant_salle;

    if v_avance < 0 then
      raise exception 'AVANCE_INVALIDE|L''avance ne peut pas être négative.';
    end if;
    if v_avance > v_montant_total then
      raise exception 'AVANCE_EXCESSIVE|L''avance dépasse le montant total de l''événement.';
    end if;

    -- Numéro journalier : EVT-AAAAMMJJ-0001…
    select count(*) into v_seq
      from public.evenements e
     where e.owner_id = v_owner
       and e.created_at >= current_date;

    v_numero := 'EVT-' || to_char(current_date, 'YYYYMMDD') || '-'
                || lpad((v_seq + 1)::text, 4, '0');

    insert into public.evenements (
      owner_id, salle_id, numero, titre, type_evenement, client_id,
      client_nom, telephone, date_debut, date_fin, heure_debut, heure_fin,
      nb_invites, prix_jour, montant_salle, montant_total, montant_paye,
      statut, note, cree_par
    ) values (
      v_owner, p_salle_id, v_numero, v_titre,
      nullif(btrim(coalesce(p_type_evenement, '')), ''),
      p_client_id, v_client_nom,
      nullif(btrim(coalesce(p_telephone, '')), ''),
      v_debut, v_fin,
      nullif(btrim(coalesce(p_heure_debut, '')), ''),
      nullif(btrim(coalesce(p_heure_fin, '')), ''),
      coalesce(p_nb_invites, 0), v_prix_jour, v_montant_salle,
      v_montant_total, v_avance, 'reserve',
      nullif(btrim(coalesce(p_note, '')), ''), v_user
    )
    returning * into v_evenement;

    insert into public.journal_audit (
      id, entreprise_id, action, utilisateur_id, details, created_at
    ) values (
      gen_random_uuid(), null, 'EVENEMENT', v_user,
      jsonb_build_object(
        'evenement_id',  v_evenement.id,
        'numero',        v_evenement.numero,
        'titre',         v_evenement.titre,
        'salle',         v_salle.nom,
        'date_debut',    v_evenement.date_debut,
        'montant_total', v_evenement.montant_total,
        'avance',        v_evenement.montant_paye
      ),
      now()
    );
  else
    -- =====================================================================
    --  MODIFICATION
    -- =====================================================================
    if not public.peut('evenements', 'modifier') then
      raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de modifier un événement.';
    end if;

    select * into v_evenement
      from public.evenements e
     where e.id = v_id
       for update;

    if not found then
      raise exception 'EVENEMENT_INTROUVABLE|Événement introuvable : il a peut-être été supprimé.';
    end if;

    if v_evenement.owner_id is distinct from v_owner and not public.est_plateforme() then
      raise exception 'HORS_BOUTIQUE|Cet événement n''appartient pas à votre boutique.';
    end if;

    if v_evenement.statut in ('termine', 'annule') then
      raise exception 'STATUT_INVALIDE|Un événement terminé ou annulé ne se modifie plus.';
    end if;

    v_prix_jour := coalesce(p_prix_jour, v_evenement.prix_jour);
    if v_prix_jour < 0 then
      raise exception 'PRIX_INVALIDE|Le prix par jour ne peut pas être négatif.';
    end if;

    v_montant_salle := round((v_jours * v_prix_jour)::numeric, 2);

    select coalesce(sum(l.total), 0)
      into v_prestations
      from public.lignes_evenement l
     where l.evenement_id = v_id;

    v_montant_total := v_montant_salle + v_prestations;

    -- On ne recolle JAMAIS sous ce qui est déjà encaissé.
    if v_evenement.montant_paye > v_montant_total then
      raise exception 'PAIEMENTS_SUPERIEURS|Les paiements déjà reçus (%) dépassent le nouveau montant total (%).',
        to_char(v_evenement.montant_paye, 'FM999G999G999D99'),
        to_char(v_montant_total, 'FM999G999G999D99');
    end if;

    update public.evenements
       set salle_id         = p_salle_id,
           titre            = v_titre,
           type_evenement   = nullif(btrim(coalesce(p_type_evenement, '')), ''),
           client_id        = p_client_id,
           client_nom       = v_client_nom,
           telephone        = nullif(btrim(coalesce(p_telephone, '')), ''),
           date_debut       = v_debut,
           date_fin         = v_fin,
           heure_debut      = nullif(btrim(coalesce(p_heure_debut, '')), ''),
           heure_fin        = nullif(btrim(coalesce(p_heure_fin, '')), ''),
           nb_invites       = coalesce(p_nb_invites, 0),
           prix_jour        = v_prix_jour,
           montant_salle    = v_montant_salle,
           montant_total    = v_montant_total,
           note             = nullif(btrim(coalesce(p_note, '')), ''),
           updated_at       = now()
     where id = v_id
     returning * into v_evenement;

    insert into public.journal_audit (
      id, entreprise_id, action, utilisateur_id, details, created_at
    ) values (
      gen_random_uuid(), null, 'EVENEMENT_MODIFIE', v_user,
      jsonb_build_object(
        'evenement_id',  v_evenement.id,
        'numero',        v_evenement.numero,
        'date_debut',    v_evenement.date_debut,
        'date_fin',      v_evenement.date_fin,
        'montant_total', v_evenement.montant_total
      ),
      now()
    );
  end if;

  return jsonb_build_object('ok', true, 'evenement', to_jsonb(v_evenement));
end;
$$;

revoke all on function public.rpc_evenement_enregistrer(uuid, uuid, text, text, bigint, text, text, date, date, text, text, integer, real, real, text) from public;
revoke all on function public.rpc_evenement_enregistrer(uuid, uuid, text, text, bigint, text, text, date, date, text, text, integer, real, real, text) from anon;
grant execute on function public.rpc_evenement_enregistrer(uuid, uuid, text, text, bigint, text, text, date, date, text, text, integer, real, real, text) to authenticated;


-- ============================================================================
--  5. RPC `rpc_evenement_ligne_ajouter` — PRESTATION (traiteur, déco…)
-- ============================================================================
--  S'ajoute au montant total de l'événement. Libellé et prix libres :
--  ces services ne touchent PAS au stock (contrairement au restaurant).

create or replace function public.rpc_evenement_ligne_ajouter(
  p_evenement_id uuid,
  p_libelle      text,
  p_quantite     numeric default 1,
  p_prix_unitaire real   default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user      uuid := auth.uid();
  v_owner     uuid;
  v_libelle   text := btrim(coalesce(p_libelle, ''));
  v_quantite  numeric := coalesce(p_quantite, 0);
  v_evenement public.evenements%rowtype;
  v_total_ligne real;
  v_ligne     public.lignes_evenement%rowtype;
  v_prestations real := 0;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour modifier un événement.';
  end if;

  if not (public.peut('evenements', 'creer') or public.peut('evenements', 'modifier')) then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de modifier un événement.';
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  if v_libelle = '' then
    raise exception 'LIBELLE_OBLIGATOIRE|Indiquez la prestation (traiteur, décoration…).';
  end if;
  if length(v_libelle) > 120 then
    raise exception 'LIBELLE_INVALIDE|Libellé trop long (120 caractères maximum).';
  end if;
  if v_quantite <= 0 then
    raise exception 'QUANTITE_INVALIDE|La quantité doit être supérieure à zéro.';
  end if;
  if coalesce(p_prix_unitaire, 0) < 0 then
    raise exception 'PRIX_INVALIDE|Le prix ne peut pas être négatif.';
  end if;

  select * into v_evenement
    from public.evenements e
   where e.id = p_evenement_id
     for update;

  if not found then
    raise exception 'EVENEMENT_INTROUVABLE|Événement introuvable : il a peut-être été supprimé.';
  end if;

  if v_evenement.owner_id is distinct from v_owner and not public.est_plateforme() then
    raise exception 'HORS_BOUTIQUE|Cet événement n''appartient pas à votre boutique.';
  end if;

  if v_evenement.statut in ('termine', 'annule') then
    raise exception 'STATUT_INVALIDE|Un événement terminé ou annulé ne se modifie plus.';
  end if;

  v_total_ligne := round((v_quantite * coalesce(p_prix_unitaire, 0))::numeric, 2);

  insert into public.lignes_evenement (
    evenement_id, libelle, quantite, prix_unitaire, total
  ) values (
    p_evenement_id, v_libelle, v_quantite, coalesce(p_prix_unitaire, 0),
    v_total_ligne
  )
  returning * into v_ligne;

  select coalesce(sum(l.total), 0)
    into v_prestations
    from public.lignes_evenement l
   where l.evenement_id = p_evenement_id;

  update public.evenements
     set montant_total = montant_salle + v_prestations,
         updated_at    = now()
   where id = p_evenement_id
   returning * into v_evenement;

  return jsonb_build_object(
    'ok', true,
    'ligne', to_jsonb(v_ligne),
    'evenement', to_jsonb(v_evenement)
  );
end;
$$;

revoke all on function public.rpc_evenement_ligne_ajouter(uuid, text, numeric, real) from public;
revoke all on function public.rpc_evenement_ligne_ajouter(uuid, text, numeric, real) from anon;
grant execute on function public.rpc_evenement_ligne_ajouter(uuid, text, numeric, real) to authenticated;


-- ============================================================================
--  6. RPC `rpc_evenement_ligne_supprimer` — RETIRER UNE PRESTATION
-- ============================================================================
create or replace function public.rpc_evenement_ligne_supprimer(p_ligne_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user      uuid := auth.uid();
  v_owner     uuid;
  v_ligne     public.lignes_evenement%rowtype;
  v_evenement public.evenements%rowtype;
  v_prestations real := 0;
  v_montant_total real;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour modifier un événement.';
  end if;

  if not (public.peut('evenements', 'creer') or public.peut('evenements', 'modifier')) then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de modifier un événement.';
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  select * into v_ligne
    from public.lignes_evenement l
   where l.id = p_ligne_id
     for update;

  if not found then
    raise exception 'LIGNE_INTROUVABLE|Prestation introuvable.';
  end if;

  select * into v_evenement
    from public.evenements e
   where e.id = v_ligne.evenement_id
     for update;

  if v_evenement.owner_id is distinct from v_owner and not public.est_plateforme() then
    raise exception 'HORS_BOUTIQUE|Cet événement n''appartient pas à votre boutique.';
  end if;

  if v_evenement.statut in ('termine', 'annule') then
    raise exception 'STATUT_INVALIDE|Un événement terminé ou annulé ne se modifie plus.';
  end if;

  delete from public.lignes_evenement where id = p_ligne_id;

  -- Le montant restant ne peut pas passer sous ce qui est déjà encaissé.
  select coalesce(sum(l.total), 0)
    into v_prestations
    from public.lignes_evenement l
   where l.evenement_id = v_evenement.id;

  v_montant_total := v_evenement.montant_salle + v_prestations;

  if v_evenement.montant_paye > v_montant_total then
    raise exception 'PAIEMENTS_SUPERIEURS|Cette suppression ferait passer le total sous les paiements déjà reçus.';
  end if;

  update public.evenements
     set montant_total = v_montant_total,
         updated_at    = now()
   where id = v_evenement.id
   returning * into v_evenement;

  return jsonb_build_object('ok', true, 'evenement', to_jsonb(v_evenement));
end;
$$;

revoke all on function public.rpc_evenement_ligne_supprimer(uuid) from public;
revoke all on function public.rpc_evenement_ligne_supprimer(uuid) from anon;
grant execute on function public.rpc_evenement_ligne_supprimer(uuid) to authenticated;


-- ============================================================================
--  7. RPC `rpc_evenement_statut` — CYCLE DE VIE
-- ============================================================================
--  réservé → confirmé → en cours → terminé ; annulation possible tant que
--  l'événement n'est pas terminé (motif facultatif).

create or replace function public.rpc_evenement_statut(
  p_id    uuid,
  p_statut text,
  p_motif text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user      uuid := auth.uid();
  v_owner     uuid;
  v_statut    text := lower(btrim(coalesce(p_statut, '')));
  v_evenement public.evenements%rowtype;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour gérer un événement.';
  end if;

  if v_statut not in ('confirme', 'en_cours', 'termine', 'annule') then
    raise exception 'STATUT_INVALIDE|Étape inconnue : « % ».', p_statut;
  end if;

  -- L'annulation touche à l'organisation et à l'argent : elle reste au
  -- niveau du responsable ; les autres étapes sont accessibles aux
  -- personnes qui saisissent les événements.
  if v_statut = 'annule' then
    if not public.peut('evenements', 'modifier') then
      raise exception 'DROIT_REFUSE|Votre rôle ne permet pas d''annuler un événement.';
    end if;
  else
    if not (public.peut('evenements', 'creer') or public.peut('evenements', 'modifier')) then
      raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de faire avancer un événement.';
    end if;
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  select * into v_evenement
    from public.evenements e
   where e.id = p_id
     for update;

  if not found then
    raise exception 'EVENEMENT_INTROUVABLE|Événement introuvable : il a peut-être été supprimé.';
  end if;

  if v_evenement.owner_id is distinct from v_owner and not public.est_plateforme() then
    raise exception 'HORS_BOUTIQUE|Cet événement n''appartient pas à votre boutique.';
  end if;

  if v_evenement.statut = v_statut then
    return jsonb_build_object('ok', true, 'evenement', to_jsonb(v_evenement));
  end if;

  if v_statut = 'confirme' and v_evenement.statut <> 'reserve' then
    raise exception 'STATUT_INVALIDE|Seule une réservation (« réservé ») peut être confirmée.';
  end if;
  if v_statut = 'en_cours' and v_evenement.statut <> 'confirme' then
    raise exception 'STATUT_INVALIDE|L''événement doit d''abord être confirmé.';
  end if;
  if v_statut = 'termine' and v_evenement.statut not in ('confirme', 'en_cours') then
    raise exception 'STATUT_INVALIDE|Seul un événement confirmé ou en cours peut être terminé.';
  end if;
  if v_statut = 'annule' and v_evenement.statut in ('termine', 'annule') then
    raise exception 'STATUT_INVALIDE|Cet événement est déjà clos.';
  end if;

  update public.evenements
     set statut = v_statut,
         motif_annulation = case
           when v_statut = 'annule'
             then nullif(btrim(coalesce(p_motif, '')), '')
           else motif_annulation
         end,
         updated_at = now()
   where id = p_id
   returning * into v_evenement;

  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(), null,
    case when v_statut = 'annule' then 'EVENEMENT_ANNULE' else 'EVENEMENT_STATUT' end,
    v_user,
    jsonb_build_object(
      'evenement_id', v_evenement.id,
      'numero',       v_evenement.numero,
      'statut',       v_evenement.statut,
      'motif',        v_evenement.motif_annulation
    ),
    now()
  );

  return jsonb_build_object('ok', true, 'evenement', to_jsonb(v_evenement));
end;
$$;

revoke all on function public.rpc_evenement_statut(uuid, text, text) from public;
revoke all on function public.rpc_evenement_statut(uuid, text, text) from anon;
grant execute on function public.rpc_evenement_statut(uuid, text, text) to authenticated;


-- ============================================================================
--  8. RPC `rpc_evenement_encaisser` — AVANCE / ACOMPTE / SOLDE
-- ============================================================================
create or replace function public.rpc_evenement_encaisser(
  p_id      uuid,
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
  v_user      uuid := auth.uid();
  v_owner     uuid;
  v_montant   real := round(coalesce(p_montant, 0), 2);
  v_mode      text := lower(btrim(coalesce(p_mode, 'especes')));
  v_evenement public.evenements%rowtype;
  v_nouveau   real;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour encaisser un événement.';
  end if;

  if not (public.peut('caisse', 'creer')
          or public.peut('evenements', 'creer')
          or public.peut('evenements', 'modifier')) then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas d''encaisser un événement.';
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  if v_montant <= 0 then
    raise exception 'MONTANT_INVALIDE|Le montant encaissé doit être supérieur à zéro.';
  end if;

  select * into v_evenement
    from public.evenements e
   where e.id = p_id
     for update;

  if not found then
    raise exception 'EVENEMENT_INTROUVABLE|Événement introuvable : il a peut-être été supprimé.';
  end if;

  if v_evenement.owner_id is distinct from v_owner and not public.est_plateforme() then
    raise exception 'HORS_BOUTIQUE|Cet événement n''appartient pas à votre boutique.';
  end if;

  if v_evenement.statut = 'annule' then
    raise exception 'STATUT_INVALIDE|Cet événement est annulé : plus aucun encaissement.';
  end if;

  v_nouveau := round((v_evenement.montant_paye + v_montant)::numeric, 2);
  if v_nouveau > v_evenement.montant_total then
    raise exception 'MONTANT_EXCEDENT|Ce paiement dépasse le solde restant (%).',
      to_char(greatest(v_evenement.montant_total - v_evenement.montant_paye, 0),
              'FM999G999G999D99');
  end if;

  update public.evenements
     set montant_paye = v_nouveau,
         updated_at   = now()
   where id = p_id
   returning * into v_evenement;

  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(), null, 'EVENEMENT_ENCAISSE', v_user,
    jsonb_build_object(
      'evenement_id', v_evenement.id,
      'numero',       v_evenement.numero,
      'montant',      v_montant,
      'mode',         v_mode,
      'total_paye',   v_evenement.montant_paye,
      'solde',        v_evenement.montant_total - v_evenement.montant_paye,
      'note',         nullif(btrim(coalesce(p_note, '')), '')
    ),
    now()
  );

  return jsonb_build_object('ok', true, 'evenement', to_jsonb(v_evenement));
end;
$$;

revoke all on function public.rpc_evenement_encaisser(uuid, numeric, text, text) from public;
revoke all on function public.rpc_evenement_encaisser(uuid, numeric, text, text) from anon;
grant execute on function public.rpc_evenement_encaisser(uuid, numeric, text, text) to authenticated;


-- ============================================================================
--  9. RPC `rpc_salle_fetes_tableau_bord` — CALENDRIER & ENCAISSEMENTS
-- ============================================================================
create or replace function public.rpc_salle_fetes_tableau_bord()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user       uuid := auth.uid();
  v_owner      uuid;
  v_total      integer := 0;
  v_actives    integer := 0;
  v_en_cours   integer := 0;
  v_a_venir    integer := 0;
  v_encaisse   real := 0;
  v_solde      real := 0;
  v_prochains  jsonb := '[]'::jsonb;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour consulter les événements.';
  end if;

  if not (public.peut('salles', 'voir')
          or public.peut('evenements', 'voir')
          or public.est_plateforme()) then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de consulter les événements.';
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  select count(*),
         count(*) filter (where actif)
    into v_total, v_actives
    from public.salles s
   where s.owner_id = v_owner;

  select count(*) filter (where e.date_debut <= current_date and e.date_fin >= current_date),
         count(*) filter (where e.date_debut > current_date)
    into v_en_cours, v_a_venir
    from public.evenements e
   where e.owner_id = v_owner
     and e.statut in ('reserve', 'confirme', 'en_cours');

  select coalesce(sum(montant_paye), 0),
         coalesce(sum(greatest(montant_total - montant_paye, 0)), 0)
    into v_encaisse, v_solde
    from public.evenements e
   where e.owner_id = v_owner
     and e.statut <> 'annule';

  select coalesce(jsonb_agg(jsonb_build_object(
           'id',          p.id,
           'numero',      p.numero,
           'titre',       p.titre,
           'salle',       p.salle,
           'client',      p.client_nom,
           'date_debut',  to_char(p.date_debut, 'DD/MM/YYYY'),
           'date_fin',    to_char(p.date_fin, 'DD/MM/YYYY'),
           'statut',      p.statut,
           'montant_total', p.montant_total,
           'solde',       greatest(p.montant_total - p.montant_paye, 0)
         ) order by p.date_debut, p.heure_debut), '[]'::jsonb)
    into v_prochains
    from (
      select e.id, e.numero, e.titre, e.client_nom, e.date_debut, e.date_fin,
             e.statut, e.montant_total, e.montant_paye, e.heure_debut,
             s.nom as salle
        from public.evenements e
        join public.salles s on s.id = e.salle_id
       where e.owner_id = v_owner
         and e.statut in ('reserve', 'confirme')
         and e.date_fin >= current_date
       order by e.date_debut, e.heure_debut
       limit 5
    ) p;

  return jsonb_build_object(
    'ok', true,
    'salles', jsonb_build_object(
      'total',   v_total,
      'actives', v_actives
    ),
    'evenements_en_cours', v_en_cours,
    'evenements_a_venir',  v_a_venir,
    'encaisse',            v_encaisse,
    'solde',               v_solde,
    'prochains',           v_prochains
  );
end;
$$;

revoke all on function public.rpc_salle_fetes_tableau_bord() from public;
revoke all on function public.rpc_salle_fetes_tableau_bord() from anon;
grant execute on function public.rpc_salle_fetes_tableau_bord() to authenticated;


-- ============================================================================
-- 10. JOURNAL D'AUDIT — NIVEAUX DES ACTIONS SALLE DES FÊTES
-- ============================================================================
--  Copie de la fonction de la migration 31 + actions salle des fêtes :
--    • EVENEMENT_ENCAISSE / EVENEMENT_ANNULE touchent à l'argent → HAUT ;
--    • le reste de l'organisation → MOYEN.

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
    -- 🏨 MODULE 16 C2 — hôtel.
    when 'CHECKOUT_SEJOUR'            then 'HAUT'
    when 'SEJOUR_ENCAISSE'            then 'HAUT'
    -- 🍽️ MODULE 16 C3 — restaurant.
    when 'COMMANDE_ENCAISSEE'         then 'HAUT'
    -- 🎉 MODULE 16 C4 — salle des fêtes.
    when 'EVENEMENT_ENCAISSE'         then 'HAUT'
    when 'EVENEMENT_ANNULE'           then 'HAUT'
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
    -- 🏨 MODULE 16 C2 — hôtel.
    when 'CHAMBRE_ENREGISTREE'        then 'MOYEN'
    when 'CHAMBRE_MODIFIEE'           then 'MOYEN'
    when 'CHAMBRE_STATUT'             then 'MOYEN'
    when 'RESERVATION'                then 'MOYEN'
    when 'RESERVATION_ANNULEE'        then 'MOYEN'
    when 'CHECKIN_SEJOUR'             then 'MOYEN'
    -- 🍽️ MODULE 16 C3 — restaurant.
    when 'TABLE_ENREGISTREE'          then 'MOYEN'
    when 'TABLE_MODIFIEE'             then 'MOYEN'
    when 'TABLE_STATUT'               then 'MOYEN'
    when 'COMMANDE'                   then 'MOYEN'
    when 'COMMANDE_ENVOYEE'           then 'MOYEN'
    when 'COMMANDE_STATUT'            then 'MOYEN'
    when 'COMMANDE_ANNULEE'           then 'MOYEN'
    -- 🎉 MODULE 16 C4 — salle des fêtes.
    when 'SALLE_ENREGISTREE'          then 'MOYEN'
    when 'SALLE_MODIFIEE'             then 'MOYEN'
    when 'EVENEMENT'                  then 'MOYEN'
    when 'EVENEMENT_MODIFIE'          then 'MOYEN'
    when 'EVENEMENT_STATUT'           then 'MOYEN'
    when 'RAPPORT'                    then 'INFO'
    else 'INFO'
  end;
$$;

comment on function public.audit_niveau(text) is
  'Niveau de gravité d''une action du journal d''audit (CRITIQUE/HAUT/MOYEN/INFO).';


-- ============================================================================
-- 11. PERMISSIONS — PAGES `salles` ET `evenements`
-- ============================================================================
--  • PROPRIÉTAIRE : toutes les actions sur les deux pages ;
--  • VENDEUR (agent d'accueil) : salles en lecture (la configuration —
--    prix, équipements — reste au patron), événements voir + créer.

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
    'salles', 'evenements'
  ];
$$;

comment on function public.pages_permissions() is
  'Liste officielle des pages de permission (Module 4, + securite Module 12, + assistant_ia Module 13, + hôtel Module 16 C2, + restaurant Module 16 C3, + salle des fêtes Module 16 C4).';

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
                         'salles', 'evenements'];
      v_actions := public.actions_permissions();

    when 'VENDEUR' then
      v_pages   := array['ventes', 'caisse', 'scanner', 'panier', 'assistant_ia',
                         -- 🏨 MODULE 16 C2 — réceptionniste d'hôtel.
                         'chambres', 'reservations', 'reception',
                         -- 🍽️ MODULE 16 C3 — serveur / cuisine.
                         'tables', 'commandes', 'cuisine',
                         -- 🎉 MODULE 16 C4 — agent d'accueil événementiel.
                         'salles', 'evenements'];
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
      -- 🏨 C2 — les chambres se CONSULTENT (configuration = patron).
      || jsonb_build_object('chambres', to_jsonb(array['voir']))
      -- 🍽️ C3 — les tables se CONSULTENT (configuration = patron).
      || jsonb_build_object('tables', to_jsonb(array['voir']))
      -- 🎉 C4 — les salles se CONSULTENT (prix et configuration = patron).
      || jsonb_build_object('salles', to_jsonb(array['voir']))
    else v_result
  end;

  return v_result;
end;
$$;

comment on function public.permissions_defaut(text) is
  'Matrice des permissions par défaut (Module 4, + audit/securite Module 12, + assistant_ia Module 13, + hôtel Module 16 C2, + restaurant Module 16 C3, + salle des fêtes Module 16 C4).';


-- ============================================================================
-- 12. PROFIL « SALLE DES FÊTES » — RÉFÉRENTIEL DES ACTIVITÉS (Module 16 A)
-- ============================================================================
--  Le référentiel accepte des types ouverts : on déclare le profil complet
--  une fois pour toutes (`on conflict do nothing` : une personnalisation
--  de l'Expert n'est jamais écrasée).

insert into public.types_espaces_modules (type, libelle, modules) values
  ('salle_fetes', 'Salle des fêtes',
   '["ventes","produits","stock","qr","caisse","clients","finance","employes","rapports","assistant_ia","salles","evenements"]'::jsonb)
on conflict (type) do nothing;


-- ============================================================================
-- 13. VÉRIFICATIONS
-- ============================================================================

-- 13.a Les trois tables existent (attendu : 3).
select count(*) as tables_salle_fetes
  from information_schema.tables
 where table_schema = 'public'
   and table_name in ('salles', 'evenements', 'lignes_evenement');

-- 13.b Les pages sont déclarées (attendu : true).
select position('evenements' in array_to_string(public.pages_permissions(), ',')) > 0
       as page_evenements;

-- 13.c Matrices par défaut (attendu : true / ["voir"] / ["voir","creer"]).
select (public.permissions_defaut('PROPRIETAIRE') ? 'salles') as proprio_salles,
       (public.permissions_defaut('VENDEUR') -> 'salles') as vendeur_salles,
       (public.permissions_defaut('VENDEUR') -> 'evenements') as vendeur_evenements;

-- 13.d Le profil « Salle des fêtes » est enregistré (attendu : 1 ligne, 12 modules).
select type, libelle, jsonb_array_length(modules) as nb_modules
  from public.types_espaces_modules
 where type = 'salle_fetes';

-- 13.e Exemples d'appel (à exécuter avec un vrai compte) :
--     select public.rpc_salle_enregistrer(null, 'Salle principale', 200, 150000);
--     select public.rpc_evenement_enregistrer(
--              null, (select id from public.salles limit 1),
--              'Mariage Kabeya', 'mariage', null, 'Famille Kabeya',
--              '+243 970 000 000', current_date + 30, current_date + 31,
--              '14:00', '23:00', 180, null, 100000);
--     select public.rpc_salle_fetes_tableau_bord();

-- ============================================================================
--  FIN — Module 16 C4 (salle des fêtes). L'application (prochaine version)
--  affiche les cartes « Salles » et « Événements », le calendrier, les
--  prestations, l'encaissement des avances/soldes et le tableau de bord.
-- ============================================================================
