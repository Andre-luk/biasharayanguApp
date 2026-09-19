-- ============================================================================
--  biashara_yangu — MODULE 16 (PHASE C3) : RESTAURANT — TABLES & COMMANDES
--
--  OBJECTIF (roadmap multi-activités, module C3) :
--    Le type d'activité « Restaurant » active les modules `tables`,
--    `commandes` et `cuisine` :
--      • tables de salle : numéro, zone, places, statut
--        (libre → occupée → libre) ;
--      • commandes : table, client, lignes d'articles du catalogue ;
--      • circuit cuisine : ouverte → envoyée → en préparation → prête →
--        servie ;
--      • encaissement via la CAISSE EXISTANTE (`rpc_vente_valider` :
--        décrémente le stock, crée la vente, le reçu et le journal) ;
--      • tableau de bord restaurant (occupation des tables, commandes
--        actives, en cuisine, prêtes).
--
--  CONTENU :
--    1. tables `tables_salle`, `commandes`, `lignes_commande` (+ index + RLS) ;
--    2. RPC table (enregistrer / statut) ;
--    3. RPC commandes (créer / lignes / envoyer / avancer / annuler /
--       encaisser via la caisse) ;
--    4. RPC tableau de bord restaurant ;
--    5. permissions : pages `tables`, `commandes`, `cuisine` ;
--    6. journal d'audit : niveaux des nouvelles actions.
--
--  OÙ : Supabase → SQL Editor → coller → Run
--  IDEMPOTENT : peut être relancé sans effet de bord.
-- ============================================================================


-- ============================================================================
--  1.a TABLE `public.tables_salle`
-- ============================================================================
create table if not exists public.tables_salle (
  id         uuid primary key default gen_random_uuid(),
  owner_id   uuid not null,
  numero     text not null,
  zone       text default '',
  places     integer not null default 2,
  statut     text not null default 'libre',
  actif      boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint tables_salle_statut_check
    check (statut in ('libre', 'occupee', 'reservee')),
  constraint tables_salle_places_check check (places >= 1 and places <= 50)
);

create unique index if not exists idx_tables_salle_owner_numero
  on public.tables_salle (owner_id, numero);
create index if not exists idx_tables_salle_owner_statut
  on public.tables_salle (owner_id, statut);

comment on table public.tables_salle is
  'Module 16 C3 (restaurant) — tables de salle : numéro, zone, places et statut (libre / occupee / reservee).';


-- ============================================================================
--  1.b TABLE `public.commandes`
-- ============================================================================
--  Une commande vit sur UNE table. Cycle :
--    ouverte (en saisie) → envoyee (en cuisine) → en_preparation → prete →
--    servie → encaissee (vente enregistrée en caisse) ; ou annulee.

create table if not exists public.commandes (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid not null,
  table_id      uuid not null references public.tables_salle (id),
  numero        text,
  client_nom    text,
  nb_personnes  integer not null default 1,
  statut        text not null default 'ouverte',
  note          text,
  montant_total real not null default 0,
  numero_vente  text,
  vente_uuid    uuid,
  cree_par      uuid,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  constraint commandes_statut_check check (statut in
    ('ouverte', 'envoyee', 'en_preparation', 'prete', 'servie',
     'encaissee', 'annulee')),
  constraint commandes_personnes_check check (nb_personnes >= 1),
  constraint commandes_montant_check check (montant_total >= 0)
);

create index if not exists idx_commandes_owner_statut
  on public.commandes (owner_id, statut);
create index if not exists idx_commandes_table
  on public.commandes (table_id, created_at desc);
create index if not exists idx_commandes_owner_date
  on public.commandes (owner_id, created_at desc);

comment on table public.commandes is
  'Module 16 C3 (restaurant) — commandes par table : statut ouverte → envoyee → en_preparation → prete → servie → encaissee (vente en caisse).';


-- ============================================================================
--  1.c TABLE `public.lignes_commande`
-- ============================================================================
--  Chaque ligne fige son PRIX et son LIBELLÉ (snapshot) : modifier le
--  catalogue plus tard ne change pas les commandes déjà prises.

create table if not exists public.lignes_commande (
  id             uuid primary key default gen_random_uuid(),
  commande_id    uuid not null references public.commandes (id) on delete cascade,
  produit_id     bigint not null references public.produits (id),
  libelle        text not null,
  quantite       numeric not null default 1,
  quantite_vendue numeric not null default 1,
  prix_unitaire  real not null default 0,
  total          real not null default 0,
  created_at     timestamptz not null default now(),
  constraint lignes_commande_quantite_check check (quantite > 0 and quantite_vendue > 0),
  constraint lignes_commande_prix_check check (prix_unitaire >= 0)
);

create index if not exists idx_lignes_commande_commande
  on public.lignes_commande (commande_id, created_at);

comment on table public.lignes_commande is
  'Module 16 C3 (restaurant) — lignes d''une commande (produit du catalogue, prix et libellé figés).';


-- ============================================================================
--  2. RLS — LECTURE PAR LA BOUTIQUE, ÉCRITURE CONTRÔLÉE
-- ============================================================================
--  Tables de salle : lecture + écritures directes encadrées par RLS (même
--  modèle que les chambres) ; commandes et lignes : lecture seule en direct,
--  écritures UNIQUEMENT via les RPC.

alter table public.tables_salle    enable row level security;
alter table public.commandes       enable row level security;
alter table public.lignes_commande enable row level security;

drop policy if exists tables_salle_lecture      on public.tables_salle;
drop policy if exists tables_salle_creation     on public.tables_salle;
drop policy if exists tables_salle_modification on public.tables_salle;
drop policy if exists tables_salle_suppression  on public.tables_salle;
drop policy if exists commandes_lecture         on public.commandes;
drop policy if exists lignes_commande_lecture   on public.lignes_commande;

create policy tables_salle_lecture on public.tables_salle
  for select to authenticated
  using (
    owner_id = auth.uid()
    or owner_id = public.mon_proprietaire()
    or public.est_plateforme()
  );

create policy tables_salle_creation on public.tables_salle
  for insert to authenticated
  with check (
    (owner_id = auth.uid() or owner_id = public.mon_proprietaire())
    and public.peut('tables', 'creer')
  );

create policy tables_salle_modification on public.tables_salle
  for update to authenticated
  using (
    (owner_id = auth.uid() or owner_id = public.mon_proprietaire())
    and public.peut('tables', 'modifier')
  )
  with check (
    (owner_id = auth.uid() or owner_id = public.mon_proprietaire())
    and public.peut('tables', 'modifier')
  );

create policy tables_salle_suppression on public.tables_salle
  for delete to authenticated
  using (
    (owner_id = auth.uid() or owner_id = public.mon_proprietaire())
    and public.peut('tables', 'supprimer')
  );

create policy commandes_lecture on public.commandes
  for select to authenticated
  using (
    owner_id = auth.uid()
    or owner_id = public.mon_proprietaire()
    or public.est_plateforme()
  );

create policy lignes_commande_lecture on public.lignes_commande
  for select to authenticated
  using (
    exists (
      select 1
        from public.commandes c
       where c.id = lignes_commande.commande_id
         and (c.owner_id = auth.uid()
              or c.owner_id = public.mon_proprietaire()
              or public.est_plateforme())
    )
  );


-- ============================================================================
--  3. RPC `rpc_table_enregistrer` — CRÉATION / MODIFICATION
-- ============================================================================
create or replace function public.rpc_table_enregistrer(
  p_id     uuid    default null,
  p_numero text    default '',
  p_zone   text    default '',
  p_places integer default 2,
  p_actif  boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user   uuid := auth.uid();
  v_owner  uuid;
  v_numero text := btrim(coalesce(p_numero, ''));
  v_id     uuid := p_id;
  v_table  public.tables_salle%rowtype;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour gérer les tables.';
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  if v_numero = '' then
    raise exception 'NUMERO_OBLIGATOIRE|Le numéro de la table est obligatoire.';
  end if;
  if length(v_numero) > 20 then
    raise exception 'NUMERO_INVALIDE|Numéro trop long (20 caractères maximum).';
  end if;
  if p_places is null or p_places < 1 or p_places > 50 then
    raise exception 'PLACES_INVALIDES|Le nombre de places doit être compris entre 1 et 50.';
  end if;

  if v_id is null then
    if not public.peut('tables', 'creer') then
      raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de créer une table.';
    end if;

    begin
      insert into public.tables_salle (owner_id, numero, zone, places, actif)
      values (v_owner, v_numero, nullif(btrim(coalesce(p_zone, '')), ''),
              p_places, coalesce(p_actif, true))
      returning * into v_table;
    exception when unique_violation then
      raise exception 'NUMERO_EXISTE|Une table porte déjà le numéro « % ».', v_numero;
    end;

    insert into public.journal_audit (
      id, entreprise_id, action, utilisateur_id, details, created_at
    ) values (
      gen_random_uuid(), null, 'TABLE_ENREGISTREE', v_user,
      jsonb_build_object('table_id', v_table.id, 'numero', v_table.numero, 'creation', true),
      now()
    );
  else
    if not public.peut('tables', 'modifier') then
      raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de modifier une table.';
    end if;

    select * into v_table
      from public.tables_salle t
     where t.id = v_id
       for update;

    if not found then
      raise exception 'TABLE_INTROUVABLE|Table introuvable : elle a peut-être été supprimée.';
    end if;

    if v_table.owner_id is distinct from v_owner and not public.est_plateforme() then
      raise exception 'HORS_BOUTIQUE|Cette table n''appartient pas à votre boutique.';
    end if;

    begin
      update public.tables_salle
         set numero = v_numero,
             zone   = nullif(btrim(coalesce(p_zone, '')), ''),
             places = p_places,
             actif  = coalesce(p_actif, true),
             updated_at = now()
       where id = v_id
       returning * into v_table;
    exception when unique_violation then
      raise exception 'NUMERO_EXISTE|Une table porte déjà le numéro « % ».', v_numero;
    end;

    insert into public.journal_audit (
      id, entreprise_id, action, utilisateur_id, details, created_at
    ) values (
      gen_random_uuid(), null, 'TABLE_MODIFIEE', v_user,
      jsonb_build_object('table_id', v_table.id, 'numero', v_table.numero),
      now()
    );
  end if;

  return jsonb_build_object('ok', true, 'table', to_jsonb(v_table));
end;
$$;

revoke all on function public.rpc_table_enregistrer(uuid, text, text, integer, boolean) from public;
revoke all on function public.rpc_table_enregistrer(uuid, text, text, integer, boolean) from anon;
grant execute on function public.rpc_table_enregistrer(uuid, text, text, integer, boolean) to authenticated;


-- ============================================================================
--  4. RPC `rpc_table_statut` — CHANGEMENT DE STATUT (réservation, libération)
-- ============================================================================
create or replace function public.rpc_table_statut(
  p_id     uuid,
  p_statut text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user   uuid := auth.uid();
  v_owner  uuid;
  v_statut text := lower(btrim(coalesce(p_statut, '')));
  v_table  public.tables_salle%rowtype;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour gérer les tables.';
  end if;

  if v_statut not in ('libre', 'occupee', 'reservee') then
    raise exception 'STATUT_INVALIDE|Statut de table inconnu : « % ».', p_statut;
  end if;

  if not (public.peut('tables', 'modifier') or public.peut('commandes', 'creer')) then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de changer le statut d''une table.';
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  select * into v_table
    from public.tables_salle t
   where t.id = p_id
     for update;

  if not found then
    raise exception 'TABLE_INTROUVABLE|Table introuvable : elle a peut-être été supprimée.';
  end if;

  if v_table.owner_id is distinct from v_owner and not public.est_plateforme() then
    raise exception 'HORS_BOUTIQUE|Cette table n''appartient pas à votre boutique.';
  end if;

  -- Une commande active interdit de libérer « à la main » : on encaisse ou
  -- on annule d'abord.
  if v_statut = 'libre'
     and exists (
       select 1
         from public.commandes c
        where c.table_id = v_table.id
          and c.statut not in ('encaissee', 'annulee')
     ) then
    raise exception 'COMMANDE_EN_COURS|La table % a encore une commande en cours.',
      v_table.numero;
  end if;

  update public.tables_salle
     set statut = v_statut, updated_at = now()
   where id = v_table.id
   returning * into v_table;

  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(), null, 'TABLE_STATUT', v_user,
    jsonb_build_object('table_id', v_table.id, 'numero', v_table.numero, 'statut', v_table.statut),
    now()
  );

  return jsonb_build_object('ok', true, 'table', to_jsonb(v_table));
end;
$$;

revoke all on function public.rpc_table_statut(uuid, text) from public;
revoke all on function public.rpc_table_statut(uuid, text) from anon;
grant execute on function public.rpc_table_statut(uuid, text) to authenticated;


-- ============================================================================
--  5. RPC `rpc_commande_creer` — OUVRIR UNE COMMANDE SUR UNE TABLE
-- ============================================================================
create or replace function public.rpc_commande_creer(
  p_table_id     uuid,
  p_client_nom   text    default null,
  p_nb_personnes integer default 1,
  p_note         text    default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user    uuid := auth.uid();
  v_owner   uuid;
  v_table   public.tables_salle%rowtype;
  v_seq     integer := 0;
  v_numero  text;
  v_commande public.commandes%rowtype;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour prendre une commande.';
  end if;

  if not public.peut('commandes', 'creer') then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de créer une commande.';
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  if p_table_id is null then
    raise exception 'TABLE_OBLIGATOIRE|Choisissez une table.';
  end if;

  select * into v_table
    from public.tables_salle t
   where t.id = p_table_id
     for update;

  if not found then
    raise exception 'TABLE_INTROUVABLE|Table introuvable : elle a peut-être été supprimée.';
  end if;

  if v_table.owner_id is distinct from v_owner and not public.est_plateforme() then
    raise exception 'HORS_BOUTIQUE|Cette table n''appartient pas à votre boutique.';
  end if;

  if not v_table.actif then
    raise exception 'TABLE_INACTIVE|La table % est désactivée.', v_table.numero;
  end if;

  if exists (
    select 1
      from public.commandes c
     where c.table_id = p_table_id
       and c.statut not in ('encaissee', 'annulee')
  ) then
    raise exception 'TABLE_OCCUPEE|La table % a déjà une commande en cours.',
      v_table.numero;
  end if;

  -- Numéro journalier : CMD-AAAAMMJJ-0001…
  select count(*) into v_seq
    from public.commandes c
   where c.owner_id = v_owner
     and c.created_at >= current_date;

  v_numero := 'CMD-' || to_char(current_date, 'YYYYMMDD') || '-'
              || lpad((v_seq + 1)::text, 4, '0');

  insert into public.commandes (
    owner_id, table_id, numero, client_nom, nb_personnes, statut, note, cree_par
  ) values (
    v_owner, p_table_id, v_numero,
    nullif(btrim(coalesce(p_client_nom, '')), ''),
    coalesce(p_nb_personnes, 1),
    'ouverte',
    nullif(btrim(coalesce(p_note, '')), ''),
    v_user
  )
  returning * into v_commande;

  update public.tables_salle
     set statut = 'occupee', updated_at = now()
   where id = v_table.id;

  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(), null, 'COMMANDE', v_user,
    jsonb_build_object(
      'commande_id', v_commande.id,
      'numero',      v_commande.numero,
      'table',       v_table.numero
    ),
    now()
  );

  return jsonb_build_object('ok', true, 'commande', to_jsonb(v_commande));
end;
$$;

revoke all on function public.rpc_commande_creer(uuid, text, integer, text) from public;
revoke all on function public.rpc_commande_creer(uuid, text, integer, text) from anon;
grant execute on function public.rpc_commande_creer(uuid, text, integer, text) to authenticated;


-- ============================================================================
--  6. RPC `rpc_commande_ligne_ajouter` — AJOUTER UN ARTICLE
-- ============================================================================
--  Le prix vient du catalogue (prix_vente) ; la ligne fige libellé + prix.
--  Ajouter un article à une commande déjà envoyée la repasse en « ouverte »
--  (le nouvel article doit repartir en cuisine).

create or replace function public.rpc_commande_ligne_ajouter(
  p_commande_id uuid,
  p_produit_id  bigint,
  p_quantite    numeric default 1
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user    uuid := auth.uid();
  v_owner   uuid;
  v_commande public.commandes%rowtype;
  v_produit public.produits%rowtype;
  v_quantite numeric := coalesce(p_quantite, 0);
  v_total_ligne real;
  v_ligne   public.lignes_commande%rowtype;
  v_total   real := 0;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour prendre une commande.';
  end if;

  if not public.peut('commandes', 'creer') then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de modifier une commande.';
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  if p_produit_id is null then
    raise exception 'PRODUIT_OBLIGATOIRE|Choisissez un article.';
  end if;

  if v_quantite <= 0 then
    raise exception 'QUANTITE_INVALIDE|La quantité doit être supérieure à zéro.';
  end if;

  select * into v_commande
    from public.commandes c
   where c.id = p_commande_id
     for update;

  if not found then
    raise exception 'COMMANDE_INTROUVABLE|Commande introuvable.';
  end if;

  if v_commande.owner_id is distinct from v_owner and not public.est_plateforme() then
    raise exception 'HORS_BOUTIQUE|Cette commande n''appartient pas à votre boutique.';
  end if;

  if v_commande.statut in ('encaissee', 'annulee') then
    raise exception 'STATUT_INVALIDE|Cette commande est close : impossible d''y ajouter un article.';
  end if;

  select * into v_produit
    from public.produits p
   where p.id = p_produit_id;

  if not found then
    raise exception 'PRODUIT_INTROUVABLE|Article n° % introuvable.', p_produit_id;
  end if;

  if v_produit.owner_id is distinct from v_owner and not public.est_plateforme() then
    raise exception 'HORS_BOUTIQUE|L''article % n''appartient pas à votre boutique.',
      v_produit.nom;
  end if;

  v_total_ligne := round((v_quantite * coalesce(v_produit.prix_vente, 0))::numeric, 2);

  insert into public.lignes_commande (
    commande_id, produit_id, libelle, quantite, quantite_vendue,
    prix_unitaire, total
  ) values (
    p_commande_id, p_produit_id, v_produit.nom, v_quantite, v_quantite,
    coalesce(v_produit.prix_vente, 0), v_total_ligne
  )
  returning * into v_ligne;

  select coalesce(sum(l.total), 0)
    into v_total
    from public.lignes_commande l
   where l.commande_id = p_commande_id;

  -- Un nouvel article doit repartir en cuisine.
  update public.commandes
     set montant_total = v_total,
         statut = case when statut = 'ouverte' then statut else 'ouverte' end,
         updated_at = now()
   where id = p_commande_id
   returning * into v_commande;

  return jsonb_build_object(
    'ok', true,
    'ligne', to_jsonb(v_ligne),
    'commande', to_jsonb(v_commande)
  );
end;
$$;

revoke all on function public.rpc_commande_ligne_ajouter(uuid, bigint, numeric) from public;
revoke all on function public.rpc_commande_ligne_ajouter(uuid, bigint, numeric) from anon;
grant execute on function public.rpc_commande_ligne_ajouter(uuid, bigint, numeric) to authenticated;


-- ============================================================================
--  7. RPC `rpc_commande_ligne_supprimer` — RETIRER UN ARTICLE (saisie)
-- ============================================================================
create or replace function public.rpc_commande_ligne_supprimer(p_ligne_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user     uuid := auth.uid();
  v_owner    uuid;
  v_ligne    public.lignes_commande%rowtype;
  v_commande public.commandes%rowtype;
  v_total    real := 0;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour modifier une commande.';
  end if;

  if not public.peut('commandes', 'creer') then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de modifier une commande.';
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  select * into v_ligne
    from public.lignes_commande l
   where l.id = p_ligne_id
     for update;

  if not found then
    raise exception 'LIGNE_INTROUVABLE|Ligne introuvable.';
  end if;

  select * into v_commande
    from public.commandes c
   where c.id = v_ligne.commande_id
     for update;

  if v_commande.owner_id is distinct from v_owner and not public.est_plateforme() then
    raise exception 'HORS_BOUTIQUE|Cette commande n''appartient pas à votre boutique.';
  end if;

  if v_commande.statut <> 'ouverte' then
    raise exception 'STATUT_INVALIDE|Un article ne peut être retiré que tant que la commande est en saisie (ouverte).';
  end if;

  delete from public.lignes_commande where id = p_ligne_id;

  select coalesce(sum(l.total), 0)
    into v_total
    from public.lignes_commande l
   where l.commande_id = v_commande.id;

  update public.commandes
     set montant_total = v_total, updated_at = now()
   where id = v_commande.id
   returning * into v_commande;

  return jsonb_build_object('ok', true, 'commande', to_jsonb(v_commande));
end;
$$;

revoke all on function public.rpc_commande_ligne_supprimer(uuid) from public;
revoke all on function public.rpc_commande_ligne_supprimer(uuid) from anon;
grant execute on function public.rpc_commande_ligne_supprimer(uuid) to authenticated;


-- ============================================================================
--  8. RPC `rpc_commande_envoyer` / `rpc_commande_avancer`
-- ============================================================================
--  Circuit cuisine : ouverte → envoyee → en_preparation → prete → servie.
--    • envoi (« envoyee ») et « servie »  : droits `commandes/creer` ;
--    • cuisine (« en_preparation », « prete ») : droits `cuisine/creer`.

create or replace function public.rpc_commande_envoyer(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user     uuid := auth.uid();
  v_owner    uuid;
  v_commande public.commandes%rowtype;
  v_nb       integer := 0;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour envoyer une commande.';
  end if;

  if not public.peut('commandes', 'creer') then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas d''envoyer une commande en cuisine.';
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  select * into v_commande
    from public.commandes c
   where c.id = p_id
     for update;

  if not found then
    raise exception 'COMMANDE_INTROUVABLE|Commande introuvable.';
  end if;

  if v_commande.owner_id is distinct from v_owner and not public.est_plateforme() then
    raise exception 'HORS_BOUTIQUE|Cette commande n''appartient pas à votre boutique.';
  end if;

  if v_commande.statut <> 'ouverte' then
    raise exception 'STATUT_INVALIDE|Seule une commande en saisie peut être envoyée en cuisine.';
  end if;

  select count(*) into v_nb
    from public.lignes_commande l
   where l.commande_id = p_id;

  if v_nb = 0 then
    raise exception 'COMMANDE_VIDE|Ajoutez au moins un article avant d''envoyer la commande.';
  end if;

  update public.commandes
     set statut = 'envoyee', updated_at = now()
   where id = p_id
   returning * into v_commande;

  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(), null, 'COMMANDE_ENVOYEE', v_user,
    jsonb_build_object('commande_id', v_commande.id, 'numero', v_commande.numero),
    now()
  );

  return jsonb_build_object('ok', true, 'commande', to_jsonb(v_commande));
end;
$$;

revoke all on function public.rpc_commande_envoyer(uuid) from public;
revoke all on function public.rpc_commande_envoyer(uuid) from anon;
grant execute on function public.rpc_commande_envoyer(uuid) to authenticated;


create or replace function public.rpc_commande_avancer(
  p_id     uuid,
  p_statut text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user     uuid := auth.uid();
  v_owner    uuid;
  v_statut   text := lower(btrim(coalesce(p_statut, '')));
  v_commande public.commandes%rowtype;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour faire avancer une commande.';
  end if;

  if v_statut not in ('en_preparation', 'prete', 'servie') then
    raise exception 'STATUT_INVALIDE|Étape inconnue : « % ».', p_statut;
  end if;

  -- Droits : la cuisine avance ses étapes, le service marque « servie ».
  if v_statut in ('en_preparation', 'prete') then
    if not (public.peut('cuisine', 'creer') or public.peut('cuisine', 'modifier')) then
      raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de faire avancer la cuisine.';
    end if;
  else
    if not (public.peut('commandes', 'creer') or public.peut('commandes', 'modifier')) then
      raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de marquer une commande servie.';
    end if;
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  select * into v_commande
    from public.commandes c
   where c.id = p_id
     for update;

  if not found then
    raise exception 'COMMANDE_INTROUVABLE|Commande introuvable.';
  end if;

  if v_commande.owner_id is distinct from v_owner and not public.est_plateforme() then
    raise exception 'HORS_BOUTIQUE|Cette commande n''appartient pas à votre boutique.';
  end if;

  if v_statut = 'en_preparation' and v_commande.statut <> 'envoyee' then
    raise exception 'STATUT_INVALIDE|La préparation ne démarre que sur une commande envoyée en cuisine.';
  end if;
  if v_statut = 'prete' and v_commande.statut <> 'en_preparation' then
    raise exception 'STATUT_INVALIDE|Le plat ne peut être prêt que depuis « en préparation ».';
  end if;
  if v_statut = 'servie' and v_commande.statut <> 'prete' then
    raise exception 'STATUT_INVALIDE|Une commande ne peut être servie que lorsqu''elle est prête.';
  end if;

  update public.commandes
     set statut = v_statut, updated_at = now()
   where id = p_id
   returning * into v_commande;

  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(), null, 'COMMANDE_STATUT', v_user,
    jsonb_build_object(
      'commande_id', v_commande.id,
      'numero',      v_commande.numero,
      'statut',      v_commande.statut
    ),
    now()
  );

  return jsonb_build_object('ok', true, 'commande', to_jsonb(v_commande));
end;
$$;

revoke all on function public.rpc_commande_avancer(uuid, text) from public;
revoke all on function public.rpc_commande_avancer(uuid, text) from anon;
grant execute on function public.rpc_commande_avancer(uuid, text) to authenticated;


-- ============================================================================
--  9. RPC `rpc_commande_annuler`
-- ============================================================================
create or replace function public.rpc_commande_annuler(
  p_id    uuid,
  p_motif text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user     uuid := auth.uid();
  v_owner    uuid;
  v_commande public.commandes%rowtype;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour annuler une commande.';
  end if;

  if not (public.peut('commandes', 'creer') or public.peut('commandes', 'modifier')) then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas d''annuler une commande.';
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  select * into v_commande
    from public.commandes c
   where c.id = p_id
     for update;

  if not found then
    raise exception 'COMMANDE_INTROUVABLE|Commande introuvable.';
  end if;

  if v_commande.owner_id is distinct from v_owner and not public.est_plateforme() then
    raise exception 'HORS_BOUTIQUE|Cette commande n''appartient pas à votre boutique.';
  end if;

  if v_commande.statut in ('encaissee', 'annulee') then
    raise exception 'STATUT_INVALIDE|Cette commande est déjà close.';
  end if;

  update public.commandes
     set statut = 'annulee',
         note = coalesce(nullif(btrim(coalesce(p_motif, '')), ''),
                         note),
         updated_at = now()
   where id = p_id
   returning * into v_commande;

  -- La table redevient libre si plus aucune commande n'y est active.
  if not exists (
    select 1
      from public.commandes c
     where c.table_id = v_commande.table_id
       and c.statut not in ('encaissee', 'annulee')
  ) then
    update public.tables_salle
       set statut = 'libre', updated_at = now()
     where id = v_commande.table_id;
  end if;

  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(), null, 'COMMANDE_ANNULEE', v_user,
    jsonb_build_object(
      'commande_id', v_commande.id,
      'numero',      v_commande.numero,
      'motif',       nullif(btrim(coalesce(p_motif, '')), '')
    ),
    now()
  );

  return jsonb_build_object('ok', true, 'commande', to_jsonb(v_commande));
end;
$$;

revoke all on function public.rpc_commande_annuler(uuid, text) from public;
revoke all on function public.rpc_commande_annuler(uuid, text) from anon;
grant execute on function public.rpc_commande_annuler(uuid, text) to authenticated;


-- ============================================================================
-- 10. RPC `rpc_commande_encaisser` — PAIEMENT VIA LA CAISSE EXISTANTE
-- ============================================================================
--  Rejoue les lignes de la commande dans `rpc_vente_valider` : contrôle du
--  stock, blocage des produits expirés, vente + reçu + journal + caisse.
--  Puis la commande passe « encaissee » et la table redevient libre.

create or replace function public.rpc_commande_encaisser(
  p_id                 uuid,
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
  v_user        uuid := auth.uid();
  v_owner       uuid;
  v_commande    public.commandes%rowtype;
  v_lignes      jsonb := '[]'::jsonb;
  v_vente       jsonb;
  v_numero      text;
  v_vente_uuid  uuid;
  v_total       real;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour encaisser une commande.';
  end if;

  if not (public.peut('caisse', 'creer') or public.est_plateforme()) then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas d''encaisser une commande.';
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  select * into v_commande
    from public.commandes c
   where c.id = p_id
     for update;

  if not found then
    raise exception 'COMMANDE_INTROUVABLE|Commande introuvable.';
  end if;

  if v_commande.owner_id is distinct from v_owner and not public.est_plateforme() then
    raise exception 'HORS_BOUTIQUE|Cette commande n''appartient pas à votre boutique.';
  end if;

  if v_commande.statut in ('encaissee', 'annulee') then
    raise exception 'STATUT_INVALIDE|Cette commande est déjà close.';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'produit_id',      l.produit_id,
           'quantite',        l.quantite,
           'quantite_vendue', l.quantite_vendue
         ) order by l.created_at, l.id), '[]'::jsonb)
    into v_lignes
    from public.lignes_commande l
   where l.commande_id = p_id;

  if v_lignes = '[]'::jsonb then
    raise exception 'COMMANDE_VIDE|La commande ne contient aucun article à encaisser.';
  end if;

  -- 🧾 CAISSE EXISTANTE : la vente réelle (stock, reçu, journal) est
  -- enregistrée par la transaction officielle du Module 8.
  v_vente := public.rpc_vente_valider(
    v_lignes,
    coalesce(nullif(btrim(lower(coalesce(p_mode_paiement, ''))), ''), 'especes'),
    p_montant_recu,
    p_numero_transaction,
    p_client_id
  );

  v_numero := v_vente->>'numero_vente';
  v_vente_uuid := (v_vente->>'vente_uuid')::uuid;
  v_total := (v_vente->>'total')::real;

  update public.commandes
     set statut        = 'encaissee',
         numero_vente  = v_numero,
         vente_uuid    = v_vente_uuid,
         montant_total = coalesce(v_total, montant_total),
         updated_at    = now()
   where id = p_id
   returning * into v_commande;

  -- La table redevient libre si plus aucune commande n'y est active.
  if not exists (
    select 1
      from public.commandes c
     where c.table_id = v_commande.table_id
       and c.statut not in ('encaissee', 'annulee')
  ) then
    update public.tables_salle
       set statut = 'libre', updated_at = now()
     where id = v_commande.table_id;
  end if;

  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(), null, 'COMMANDE_ENCAISSEE', v_user,
    jsonb_build_object(
      'commande_id', v_commande.id,
      'numero',      v_commande.numero,
      'numero_vente', v_numero,
      'total',       v_commande.montant_total
    ),
    now()
  );

  return jsonb_build_object(
    'ok', true,
    'commande', to_jsonb(v_commande),
    'vente', v_vente
  );
end;
$$;

revoke all on function public.rpc_commande_encaisser(uuid, text, numeric, text, bigint) from public;
revoke all on function public.rpc_commande_encaisser(uuid, text, numeric, text, bigint) from anon;
grant execute on function public.rpc_commande_encaisser(uuid, text, numeric, text, bigint) to authenticated;


-- ============================================================================
-- 11. RPC `rpc_restaurant_tableau_bord` — TABLES & COMMANDES DU SERVICE
-- ============================================================================
create or replace function public.rpc_restaurant_tableau_bord()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user       uuid := auth.uid();
  v_owner      uuid;
  v_total      integer := 0;
  v_libres     integer := 0;
  v_occupees   integer := 0;
  v_reservees  integer := 0;
  v_actives    integer := 0;
  v_a_envoyer  integer := 0;
  v_en_cuisine integer := 0;
  v_pretes     integer := 0;
  v_servies    integer := 0;
  v_montant    real := 0;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour consulter le restaurant.';
  end if;

  if not (public.peut('tables', 'voir')
          or public.peut('commandes', 'voir')
          or public.peut('cuisine', 'voir')
          or public.est_plateforme()) then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de consulter le restaurant.';
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  select count(*),
         count(*) filter (where statut = 'libre'),
         count(*) filter (where statut = 'occupee'),
         count(*) filter (where statut = 'reservee')
    into v_total, v_libres, v_occupees, v_reservees
    from public.tables_salle t
   where t.owner_id = v_owner
     and t.actif;

  select count(*),
         count(*) filter (where statut = 'ouverte'),
         count(*) filter (where statut in ('envoyee', 'en_preparation')),
         count(*) filter (where statut = 'prete'),
         count(*) filter (where statut = 'servie'),
         coalesce(sum(montant_total), 0)
    into v_actives, v_a_envoyer, v_en_cuisine, v_pretes, v_servies, v_montant
    from public.commandes c
   where c.owner_id = v_owner
     and c.statut not in ('encaissee', 'annulee');

  return jsonb_build_object(
    'ok', true,
    'tables', jsonb_build_object(
      'total',     v_total,
      'libres',    v_libres,
      'occupees',  v_occupees,
      'reservees', v_reservees
    ),
    'commandes_actives', v_actives,
    'a_envoyer',         v_a_envoyer,
    'en_cuisine',        v_en_cuisine,
    'pretes',            v_pretes,
    'servies',           v_servies,
    'montant_actif',     v_montant,
    'cuisine_count',     v_en_cuisine + v_pretes
  );
end;
$$;

revoke all on function public.rpc_restaurant_tableau_bord() from public;
revoke all on function public.rpc_restaurant_tableau_bord() from anon;
grant execute on function public.rpc_restaurant_tableau_bord() to authenticated;


-- ============================================================================
-- 12. JOURNAL D'AUDIT — NIVEAUX DES ACTIONS RESTAURANT
-- ============================================================================
--  Copie de la fonction de la migration 30 + actions restaurant :
--    • COMMANDE_ENCAISSEE touche l'argent → HAUT ;
--    • le reste du service → MOYEN.

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
    when 'RAPPORT'                    then 'INFO'
    else 'INFO'
  end;
$$;

comment on function public.audit_niveau(text) is
  'Niveau de gravité d''une action du journal d''audit (CRITIQUE/HAUT/MOYEN/INFO).';


-- ============================================================================
-- 13. PERMISSIONS — PAGES `tables`, `commandes`, `cuisine`
-- ============================================================================
--  • PROPRIÉTAIRE : toutes les actions sur les trois pages ;
--  • VENDEUR (serveur / cuisine) : tables en lecture, commandes
--    (voir + créer : prendre, envoyer, servir, encaisser) et cuisine
--    (voir + créer : en préparation, prête) — jamais la configuration.

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
    'tables', 'commandes', 'cuisine'
  ];
$$;

comment on function public.pages_permissions() is
  'Liste officielle des pages de permission (Module 4, + securite Module 12, + assistant_ia Module 13, + hôtel Module 16 C2, + restaurant Module 16 C3).';

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
                         'tables', 'commandes', 'cuisine'];
      v_actions := public.actions_permissions();

    when 'VENDEUR' then
      v_pages   := array['ventes', 'caisse', 'scanner', 'panier', 'assistant_ia',
                         -- 🏨 MODULE 16 C2 — réceptionniste d'hôtel.
                         'chambres', 'reservations', 'reception',
                         -- 🍽️ MODULE 16 C3 — serveur / cuisine.
                         'tables', 'commandes', 'cuisine'];
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
    else v_result
  end;

  return v_result;
end;
$$;

comment on function public.permissions_defaut(text) is
  'Matrice des permissions par défaut (Module 4, + audit/securite Module 12, + assistant_ia Module 13, + hôtel Module 16 C2, + restaurant Module 16 C3).';


-- ============================================================================
-- 14. VÉRIFICATIONS
-- ============================================================================

-- 14.a Les trois tables existent (attendu : 3).
select count(*) as tables_restaurant
  from information_schema.tables
 where table_schema = 'public'
   and table_name in ('tables_salle', 'commandes', 'lignes_commande');

-- 14.b La page `commandes` est déclarée (attendu : true).
select position('commandes' in array_to_string(public.pages_permissions(), ',')) > 0
       as page_commandes;

-- 14.c Matrices par défaut (attendu : true / ["voir","creer"]).
select (public.permissions_defaut('PROPRIETAIRE') ? 'cuisine') as proprio_cuisine,
       (public.permissions_defaut('VENDEUR') -> 'commandes') as vendeur_commandes;

-- 14.d Exemple d'appel (à exécuter avec un vrai compte) :
--     select public.rpc_restaurant_tableau_bord();

-- ============================================================================
--  FIN — Module 16 C3 (restaurant). L'application (prochaine version) affiche
--  les cartes « Tables », « Commandes » et « Cuisine », le plan de salle, le
--  suivi des commandes et l'encaissement via la caisse existante.
-- ============================================================================
