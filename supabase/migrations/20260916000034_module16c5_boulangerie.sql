-- ============================================================================
--  biashara_yangu — MODULE 16 (PHASE C5) : BOULANGERIE — MATIÈRES & PRODUCTIONS
--
--  OBJECTIF (roadmap multi-activités, module C5) :
--    Le type d'activité « Boulangerie » active le module `production` :
--      • matières premières (farine, levure, sucre…) suivies en stock,
--        avec seuil d'alerte et coût unitaire ;
--      • productions : un produit fini du catalogue, une quantité prévue,
--        les MATIÈRES CONSOMMÉES (déduites du stock au fur et à mesure),
--        la quantité réellement produite et les PERTES ;
--      • à la clôture, le produit fini ENTRE EN STOCK via un ajustement
--        officiel (trigger du Module 9) et le COÛT DE REVIENT unitaire
--        est calculé (coût matières ÷ quantité produite) ;
--      • tableau de bord production du jour (alertes matières, quantité,
--        pertes, coût).
--
--  CONTENU :
--    1. tables `matieres_premieres`, `productions`,
--       `consommations_production` (+ index + RLS) ;
--    2. RPC matières (enregistrer / approvisionner / ajuster) ;
--    3. RPC productions (créer / consommer / retirer / terminer / annuler) ;
--    4. RPC tableau de bord production ;
--    5. permissions : page `production` ;
--    6. journal d'audit : niveaux des nouvelles actions ;
--    7. profil « Boulangerie » du référentiel des activités.
--
--  OÙ : Supabase → SQL Editor → coller → Run
--  IDEMPOTENT : peut être relancé sans effet de bord.
-- ============================================================================


-- ============================================================================
--  1.a TABLE `public.matieres_premieres`
-- ============================================================================
--  Chaque matière appartient à une boutique (owner_id = patron). Le stock
--  est un simple compteur (les matières premières ne passent PAS par le
--  stock des articles : elles ne se vendent pas). `prix_unitaire` = dernier
--  prix payé (sert au coût de revient des productions).

create table if not exists public.matieres_premieres (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid not null,
  nom           text not null,
  unite         text not null default 'kg',
  stock         real not null default 0,
  seuil_alerte  real not null default 0,
  prix_unitaire real not null default 0,
  actif         boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  constraint matieres_premieres_stock_check check (stock >= 0),
  constraint matieres_premieres_seuil_check check (seuil_alerte >= 0),
  constraint matieres_premieres_prix_check check (prix_unitaire >= 0)
);

create unique index if not exists idx_matieres_premieres_owner_nom
  on public.matieres_premieres (owner_id, nom);
create index if not exists idx_matieres_premieres_owner_actif
  on public.matieres_premieres (owner_id, actif);

comment on table public.matieres_premieres is
  'Module 16 C5 (boulangerie) — matières premières : stock, seuil d''alerte et prix unitaire (coût de revient).';
comment on column public.matieres_premieres.prix_unitaire is
  'Dernier prix payé par unité — sert au calcul du coût de revient des productions.';


-- ============================================================================
--  1.b TABLE `public.productions`
-- ============================================================================
--  Une production fabrique UN produit fini du catalogue. Cycle :
--    en_cours (on saisit les matières consommées) → terminee (le produit
--    fini entre en stock, le coût de revient est calculé) ; ou annulee
--    (les matières déjà consommées sont rendues au stock).

create table if not exists public.productions (
  id              uuid primary key default gen_random_uuid(),
  owner_id        uuid not null,
  produit_id      bigint not null references public.produits (id),
  numero          text,
  quantite_prevue numeric not null default 0,
  quantite_reelle numeric not null default 0,
  pertes          numeric not null default 0,
  cout_matieres   real not null default 0,
  cout_unitaire   real not null default 0,
  statut          text not null default 'en_cours',
  note            text,
  motif_annulation text,
  cree_par        uuid,
  terminee_le     timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  constraint productions_quantites_check
    check (quantite_prevue >= 0 and quantite_reelle >= 0),
  constraint productions_couts_check
    check (cout_matieres >= 0 and cout_unitaire >= 0),
  constraint productions_statut_check
    check (statut in ('en_cours', 'terminee', 'annulee'))
);

create index if not exists idx_productions_owner_statut
  on public.productions (owner_id, statut);
create index if not exists idx_productions_owner_date
  on public.productions (owner_id, created_at desc);
create index if not exists idx_productions_produit
  on public.productions (produit_id, created_at desc);

comment on table public.productions is
  'Module 16 C5 (boulangerie) — productions : quantités prévue/réelle, pertes, coût de revient et statut (en_cours → terminee / annulee).';
comment on column public.productions.pertes is
  'Quantité prévue − quantité réellement produite (peut être négative en cas de surplus).';


-- ============================================================================
--  1.c TABLE `public.consommations_production`
-- ============================================================================
--  Matières premières utilisées par une production. Chaque ligne fige le
--  coût unitaire au moment de la consommation.

create table if not exists public.consommations_production (
  id            uuid primary key default gen_random_uuid(),
  production_id uuid not null references public.productions (id) on delete cascade,
  matiere_id    uuid not null references public.matieres_premieres (id),
  quantite      numeric not null default 0,
  cout_unitaire real not null default 0,
  total         real not null default 0,
  created_at    timestamptz not null default now(),
  constraint consommations_production_quantite_check check (quantite > 0),
  constraint consommations_production_couts_check
    check (cout_unitaire >= 0 and total >= 0)
);

create index if not exists idx_consommations_production_production
  on public.consommations_production (production_id, created_at);
create index if not exists idx_consommations_production_matiere
  on public.consommations_production (matiere_id);

comment on table public.consommations_production is
  'Module 16 C5 (boulangerie) — matières premières consommées par une production (coût unitaire figé).';


-- ============================================================================
--  2. RLS — LECTURE PAR LA BOUTIQUE, ÉCRITURE CONTRÔLÉE
-- ============================================================================
--  Matières premières : lecture + écritures directes encadrées par RLS
--  (même modèle que les chambres) ; productions et consommations : lecture
--  seule en direct, écritures UNIQUEMENT via les RPC (stock, coûts).

alter table public.matieres_premieres       enable row level security;
alter table public.productions              enable row level security;
alter table public.consommations_production enable row level security;

drop policy if exists matieres_premieres_lecture      on public.matieres_premieres;
drop policy if exists matieres_premieres_creation     on public.matieres_premieres;
drop policy if exists matieres_premieres_modification on public.matieres_premieres;
drop policy if exists matieres_premieres_suppression  on public.matieres_premieres;
drop policy if exists productions_lecture             on public.productions;
drop policy if exists consommations_production_lecture on public.consommations_production;

create policy matieres_premieres_lecture on public.matieres_premieres
  for select to authenticated
  using (
    owner_id = auth.uid()
    or owner_id = public.mon_proprietaire()
    or public.est_plateforme()
  );

create policy matieres_premieres_creation on public.matieres_premieres
  for insert to authenticated
  with check (
    (owner_id = auth.uid() or owner_id = public.mon_proprietaire())
    and public.peut('production', 'creer')
  );

create policy matieres_premieres_modification on public.matieres_premieres
  for update to authenticated
  using (
    (owner_id = auth.uid() or owner_id = public.mon_proprietaire())
    and public.peut('production', 'modifier')
  )
  with check (
    (owner_id = auth.uid() or owner_id = public.mon_proprietaire())
    and public.peut('production', 'modifier')
  );

create policy matieres_premieres_suppression on public.matieres_premieres
  for delete to authenticated
  using (
    (owner_id = auth.uid() or owner_id = public.mon_proprietaire())
    and public.peut('production', 'supprimer')
  );

create policy productions_lecture on public.productions
  for select to authenticated
  using (
    owner_id = auth.uid()
    or owner_id = public.mon_proprietaire()
    or public.est_plateforme()
  );

create policy consommations_production_lecture on public.consommations_production
  for select to authenticated
  using (
    exists (
      select 1
        from public.productions p
       where p.id = consommations_production.production_id
         and (p.owner_id = auth.uid()
              or p.owner_id = public.mon_proprietaire()
              or public.est_plateforme())
    )
  );


-- ============================================================================
--  3. RPC `rpc_matiere_enregistrer` — CRÉATION / MODIFICATION
-- ============================================================================
create or replace function public.rpc_matiere_enregistrer(
  p_id          uuid    default null,
  p_nom         text    default '',
  p_unite       text    default 'kg',
  p_seuil_alerte real   default 0,
  p_prix_unitaire real  default 0,
  p_actif       boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user    uuid := auth.uid();
  v_owner   uuid;
  v_nom     text := btrim(coalesce(p_nom, ''));
  v_id      uuid := p_id;
  v_matiere public.matieres_premieres%rowtype;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour gérer les matières premières.';
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  if v_nom = '' then
    raise exception 'NOM_OBLIGATOIRE|Le nom de la matière première est obligatoire.';
  end if;
  if length(v_nom) > 80 then
    raise exception 'NOM_INVALIDE|Nom trop long (80 caractères maximum).';
  end if;
  if coalesce(p_seuil_alerte, 0) < 0 then
    raise exception 'SEUIL_INVALIDE|Le seuil d''alerte ne peut pas être négatif.';
  end if;
  if coalesce(p_prix_unitaire, 0) < 0 then
    raise exception 'PRIX_INVALIDE|Le prix unitaire ne peut pas être négatif.';
  end if;

  if v_id is null then
    -- Création.
    if not public.peut('production', 'creer') then
      raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de créer une matière première.';
    end if;

    begin
      insert into public.matieres_premieres (
        owner_id, nom, unite, seuil_alerte, prix_unitaire, actif
      ) values (
        v_owner, v_nom,
        coalesce(nullif(btrim(lower(coalesce(p_unite, ''))), ''), 'kg'),
        coalesce(p_seuil_alerte, 0),
        coalesce(p_prix_unitaire, 0),
        coalesce(p_actif, true)
      )
      returning * into v_matiere;
    exception when unique_violation then
      raise exception 'NOM_EXISTE|Une matière première porte déjà le nom « % ».', v_nom;
    end;

    insert into public.journal_audit (
      id, entreprise_id, action, utilisateur_id, details, created_at
    ) values (
      gen_random_uuid(), null, 'MATIERE_ENREGISTREE', v_user,
      jsonb_build_object('matiere_id', v_matiere.id, 'nom', v_matiere.nom, 'creation', true),
      now()
    );
  else
    -- Modification.
    if not public.peut('production', 'modifier') then
      raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de modifier une matière première.';
    end if;

    select * into v_matiere
      from public.matieres_premieres m
     where m.id = v_id
       for update;

    if not found then
      raise exception 'MATIERE_INTROUVABLE|Matière première introuvable : elle a peut-être été supprimée.';
    end if;

    if v_matiere.owner_id is distinct from v_owner and not public.est_plateforme() then
      raise exception 'HORS_BOUTIQUE|Cette matière première n''appartient pas à votre boutique.';
    end if;

    begin
      update public.matieres_premieres
         set nom           = v_nom,
             unite         = coalesce(nullif(btrim(lower(coalesce(p_unite, ''))), ''), 'kg'),
             seuil_alerte  = coalesce(p_seuil_alerte, 0),
             prix_unitaire = coalesce(p_prix_unitaire, 0),
             actif         = coalesce(p_actif, true),
             updated_at    = now()
       where id = v_id
       returning * into v_matiere;
    exception when unique_violation then
      raise exception 'NOM_EXISTE|Une matière première porte déjà le nom « % ».', v_nom;
    end;

    insert into public.journal_audit (
      id, entreprise_id, action, utilisateur_id, details, created_at
    ) values (
      gen_random_uuid(), null, 'MATIERE_MODIFIEE', v_user,
      jsonb_build_object('matiere_id', v_matiere.id, 'nom', v_matiere.nom),
      now()
    );
  end if;

  return jsonb_build_object('ok', true, 'matiere', to_jsonb(v_matiere));
end;
$$;

revoke all on function public.rpc_matiere_enregistrer(uuid, text, text, real, real, boolean) from public;
revoke all on function public.rpc_matiere_enregistrer(uuid, text, text, real, real, boolean) from anon;
grant execute on function public.rpc_matiere_enregistrer(uuid, text, text, real, real, boolean) to authenticated;


-- ============================================================================
--  4. RPC `rpc_matiere_approvisionner` — ENTRÉE DE STOCK
-- ============================================================================
--  Ajoute `p_quantite` au stock ; si un prix unitaire est fourni, il
--  remplace le dernier prix payé (base du coût de revient).

create or replace function public.rpc_matiere_approvisionner(
  p_id            uuid,
  p_quantite      numeric,
  p_prix_unitaire real    default null,
  p_note          text    default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user    uuid := auth.uid();
  v_owner   uuid;
  v_quantite numeric := round(coalesce(p_quantite, 0), 3);
  v_matiere public.matieres_premieres%rowtype;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour approvisionner les matières premières.';
  end if;

  if not (public.peut('production', 'creer') or public.peut('production', 'modifier')) then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas d''approvisionner les matières premières.';
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  if v_quantite <= 0 then
    raise exception 'QUANTITE_INVALIDE|La quantité approvisionnée doit être supérieure à zéro.';
  end if;
  if p_prix_unitaire is not null and p_prix_unitaire < 0 then
    raise exception 'PRIX_INVALIDE|Le prix unitaire ne peut pas être négatif.';
  end if;

  select * into v_matiere
    from public.matieres_premieres m
   where m.id = p_id
     for update;

  if not found then
    raise exception 'MATIERE_INTROUVABLE|Matière première introuvable : elle a peut-être été supprimée.';
  end if;

  if v_matiere.owner_id is distinct from v_owner and not public.est_plateforme() then
    raise exception 'HORS_BOUTIQUE|Cette matière première n''appartient pas à votre boutique.';
  end if;

  update public.matieres_premieres
     set stock = stock + v_quantite,
         prix_unitaire = coalesce(p_prix_unitaire, prix_unitaire),
         updated_at = now()
   where id = p_id
   returning * into v_matiere;

  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(), null, 'MATIERE_APPRO', v_user,
    jsonb_build_object(
      'matiere_id', v_matiere.id,
      'nom',        v_matiere.nom,
      'quantite',   v_quantite,
      'prix',       p_prix_unitaire,
      'stock',      v_matiere.stock,
      'note',       nullif(btrim(coalesce(p_note, '')), '')
    ),
    now()
  );

  return jsonb_build_object('ok', true, 'matiere', to_jsonb(v_matiere));
end;
$$;

revoke all on function public.rpc_matiere_approvisionner(uuid, numeric, real, text) from public;
revoke all on function public.rpc_matiere_approvisionner(uuid, numeric, real, text) from anon;
grant execute on function public.rpc_matiere_approvisionner(uuid, numeric, real, text) to authenticated;


-- ============================================================================
--  5. RPC `rpc_matiere_ajuster` — INVENTAIRE SIMPLE (stock réel constaté)
-- ============================================================================
create or replace function public.rpc_matiere_ajuster(
  p_id         uuid,
  p_stock_reel numeric,
  p_raison     text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user    uuid := auth.uid();
  v_owner   uuid;
  v_raison  text := btrim(coalesce(p_raison, ''));
  v_stock   numeric := round(coalesce(p_stock_reel, -1), 3);
  v_matiere public.matieres_premieres%rowtype;
  v_avant   numeric;
  v_delta   numeric;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour ajuster les matières premières.';
  end if;

  if not public.peut('production', 'modifier') then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas d''ajuster les matières premières.';
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  if v_stock < 0 then
    raise exception 'QUANTITE_INVALIDE|Le stock constaté ne peut pas être négatif.';
  end if;
  if length(v_raison) < 3 then
    raise exception 'RAISON_OBLIGATOIRE|Indiquez la raison de l''ajustement (3 caractères minimum).';
  end if;

  select * into v_matiere
    from public.matieres_premieres m
   where m.id = p_id
     for update;

  if not found then
    raise exception 'MATIERE_INTROUVABLE|Matière première introuvable : elle a peut-être été supprimée.';
  end if;

  if v_matiere.owner_id is distinct from v_owner and not public.est_plateforme() then
    raise exception 'HORS_BOUTIQUE|Cette matière première n''appartient pas à votre boutique.';
  end if;

  v_avant := v_matiere.stock;
  v_delta := v_stock - v_avant;

  if v_delta = 0 then
    raise exception 'AUCUN_ECART|Aucun écart : le stock constaté est identique.';
  end if;

  update public.matieres_premieres
     set stock = v_stock, updated_at = now()
   where id = p_id
   returning * into v_matiere;

  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(), null, 'MATIERE_AJUSTEMENT', v_user,
    jsonb_build_object(
      'matiere_id',  v_matiere.id,
      'nom',         v_matiere.nom,
      'delta',       v_delta,
      'raison',      v_raison,
      'stock_avant', v_avant,
      'stock_apres', v_matiere.stock
    ),
    now()
  );

  return jsonb_build_object('ok', true, 'matiere', to_jsonb(v_matiere));
end;
$$;

revoke all on function public.rpc_matiere_ajuster(uuid, numeric, text) from public;
revoke all on function public.rpc_matiere_ajuster(uuid, numeric, text) from anon;
grant execute on function public.rpc_matiere_ajuster(uuid, numeric, text) to authenticated;


-- ============================================================================
--  6. RPC `rpc_production_creer` — OUVRIR UNE PRODUCTION
-- ============================================================================
create or replace function public.rpc_production_creer(
  p_produit_id      bigint,
  p_quantite_prevue numeric,
  p_note            text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user     uuid := auth.uid();
  v_owner    uuid;
  v_produit  public.produits%rowtype;
  v_quantite numeric := round(coalesce(p_quantite_prevue, 0), 3);
  v_seq      integer := 0;
  v_numero   text;
  v_prod     public.productions%rowtype;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour lancer une production.';
  end if;

  if not public.peut('production', 'creer') then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de lancer une production.';
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  if p_produit_id is null then
    raise exception 'PRODUIT_OBLIGATOIRE|Choisissez le produit à fabriquer.';
  end if;
  if v_quantite <= 0 then
    raise exception 'QUANTITE_INVALIDE|La quantité prévue doit être supérieure à zéro.';
  end if;

  select * into v_produit
    from public.produits p
   where p.id = p_produit_id;

  if not found then
    raise exception 'PRODUIT_INTROUVABLE|Article n° % introuvable.', p_produit_id;
  end if;

  if v_produit.owner_id is distinct from v_owner and not public.est_plateforme() then
    raise exception 'HORS_BOUTIQUE|L''article % n''appartient pas à votre boutique.', v_produit.nom;
  end if;

  -- Numéro journalier : PROD-AAAAMMJJ-0001…
  select count(*) into v_seq
    from public.productions p
   where p.owner_id = v_owner
     and p.created_at >= current_date;

  v_numero := 'PROD-' || to_char(current_date, 'YYYYMMDD') || '-'
              || lpad((v_seq + 1)::text, 4, '0');

  insert into public.productions (
    owner_id, produit_id, numero, quantite_prevue, statut, note, cree_par
  ) values (
    v_owner, p_produit_id, v_numero, v_quantite, 'en_cours',
    nullif(btrim(coalesce(p_note, '')), ''), v_user
  )
  returning * into v_prod;

  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(), null, 'PRODUCTION', v_user,
    jsonb_build_object(
      'production_id', v_prod.id,
      'numero',        v_prod.numero,
      'produit',       v_produit.nom,
      'quantite_prevue', v_prod.quantite_prevue
    ),
    now()
  );

  return jsonb_build_object('ok', true, 'production', to_jsonb(v_prod));
end;
$$;

revoke all on function public.rpc_production_creer(bigint, numeric, text) from public;
revoke all on function public.rpc_production_creer(bigint, numeric, text) from anon;
grant execute on function public.rpc_production_creer(bigint, numeric, text) to authenticated;


-- ============================================================================
--  7. RPC `rpc_production_consommer` — MATIÈRE UTILISÉE
-- ============================================================================
--  Déduit la matière du stock et l'ajoute à la production (coût figé).

create or replace function public.rpc_production_consommer(
  p_production_id uuid,
  p_matiere_id    uuid,
  p_quantite      numeric
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user     uuid := auth.uid();
  v_owner    uuid;
  v_quantite numeric := round(coalesce(p_quantite, 0), 3);
  v_prod     public.productions%rowtype;
  v_matiere  public.matieres_premieres%rowtype;
  v_total    real;
  v_ligne    public.consommations_production%rowtype;
  v_cout     real := 0;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour modifier une production.';
  end if;

  if not (public.peut('production', 'creer') or public.peut('production', 'modifier')) then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de modifier une production.';
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  if v_quantite <= 0 then
    raise exception 'QUANTITE_INVALIDE|La quantité consommée doit être supérieure à zéro.';
  end if;

  select * into v_prod
    from public.productions p
   where p.id = p_production_id
     for update;

  if not found then
    raise exception 'PRODUCTION_INTROUVABLE|Production introuvable.';
  end if;

  if v_prod.owner_id is distinct from v_owner and not public.est_plateforme() then
    raise exception 'HORS_BOUTIQUE|Cette production n''appartient pas à votre boutique.';
  end if;

  if v_prod.statut <> 'en_cours' then
    raise exception 'STATUT_INVALIDE|Cette production est close : impossible d''y ajouter une matière.';
  end if;

  select * into v_matiere
    from public.matieres_premieres m
   where m.id = p_matiere_id
     for update;

  if not found then
    raise exception 'MATIERE_INTROUVABLE|Matière première introuvable : elle a peut-être été supprimée.';
  end if;

  if v_matiere.owner_id is distinct from v_owner and not public.est_plateforme() then
    raise exception 'HORS_BOUTIQUE|La matière « % » n''appartient pas à votre boutique.', v_matiere.nom;
  end if;

  if v_matiere.stock < v_quantite then
    raise exception 'STOCK_MATIERE_INSUFFISANT|Stock insuffisant pour « % » : il reste % (demandé : %).',
      v_matiere.nom,
      trim(to_char(v_matiere.stock, 'FM999999990.###')),
      trim(to_char(v_quantite, 'FM999999990.###'));
  end if;

  update public.matieres_premieres
     set stock = stock - v_quantite, updated_at = now()
   where id = p_matiere_id;

  v_total := round((v_quantite * v_matiere.prix_unitaire)::numeric, 2);

  insert into public.consommations_production (
    production_id, matiere_id, quantite, cout_unitaire, total
  ) values (
    p_production_id, p_matiere_id, v_quantite, v_matiere.prix_unitaire, v_total
  )
  returning * into v_ligne;

  select coalesce(sum(c.total), 0)
    into v_cout
    from public.consommations_production c
   where c.production_id = p_production_id;

  update public.productions
     set cout_matieres = v_cout, updated_at = now()
   where id = p_production_id
   returning * into v_prod;

  return jsonb_build_object(
    'ok', true,
    'ligne', to_jsonb(v_ligne),
    'production', to_jsonb(v_prod)
  );
end;
$$;

revoke all on function public.rpc_production_consommer(uuid, uuid, numeric) from public;
revoke all on function public.rpc_production_consommer(uuid, uuid, numeric) from anon;
grant execute on function public.rpc_production_consommer(uuid, uuid, numeric) to authenticated;


-- ============================================================================
--  8. RPC `rpc_production_consommation_supprimer` — RETIRER UNE MATIÈRE
-- ============================================================================
create or replace function public.rpc_production_consommation_supprimer(p_ligne_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user  uuid := auth.uid();
  v_owner uuid;
  v_ligne public.consommations_production%rowtype;
  v_prod  public.productions%rowtype;
  v_cout  real := 0;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour modifier une production.';
  end if;

  if not (public.peut('production', 'creer') or public.peut('production', 'modifier')) then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de modifier une production.';
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  select * into v_ligne
    from public.consommations_production c
   where c.id = p_ligne_id
     for update;

  if not found then
    raise exception 'LIGNE_INTROUVABLE|Consommation introuvable.';
  end if;

  select * into v_prod
    from public.productions p
   where p.id = v_ligne.production_id
     for update;

  if v_prod.owner_id is distinct from v_owner and not public.est_plateforme() then
    raise exception 'HORS_BOUTIQUE|Cette production n''appartient pas à votre boutique.';
  end if;

  if v_prod.statut <> 'en_cours' then
    raise exception 'STATUT_INVALIDE|Seule une production en cours peut être modifiée.';
  end if;

  -- La matière revient au stock.
  update public.matieres_premieres
     set stock = stock + v_ligne.quantite, updated_at = now()
   where id = v_ligne.matiere_id;

  delete from public.consommations_production where id = p_ligne_id;

  select coalesce(sum(c.total), 0)
    into v_cout
    from public.consommations_production c
   where c.production_id = v_prod.id;

  update public.productions
     set cout_matieres = v_cout, updated_at = now()
   where id = v_prod.id
   returning * into v_prod;

  return jsonb_build_object('ok', true, 'production', to_jsonb(v_prod));
end;
$$;

revoke all on function public.rpc_production_consommation_supprimer(uuid) from public;
revoke all on function public.rpc_production_consommation_supprimer(uuid) from anon;
grant execute on function public.rpc_production_consommation_supprimer(uuid) to authenticated;


-- ============================================================================
--  9. RPC `rpc_production_terminer` — CLÔTURE : STOCK + COÛT DE REVIENT
-- ============================================================================
--  Le produit fini ENTRE EN STOCK via un ajustement officiel (Module 9 :
--  le trigger applique le delta) et le coût de revient unitaire est
--  calculé (coût matières ÷ quantité réellement produite).

create or replace function public.rpc_production_terminer(
  p_id             uuid,
  p_quantite_reelle numeric
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user   uuid := auth.uid();
  v_owner  uuid;
  v_reelle numeric := round(coalesce(p_quantite_reelle, -1), 3);
  v_prod   public.productions%rowtype;
  v_produit public.produits%rowtype;
  v_pertes numeric;
  v_cout_u real;
  v_stock  real;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour clôturer une production.';
  end if;

  if not (public.peut('production', 'creer') or public.peut('production', 'modifier')) then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de clôturer une production.';
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  if v_reelle < 0 then
    raise exception 'QUANTITE_INVALIDE|La quantité réellement produite ne peut pas être négative.';
  end if;

  select * into v_prod
    from public.productions p
   where p.id = p_id
     for update;

  if not found then
    raise exception 'PRODUCTION_INTROUVABLE|Production introuvable.';
  end if;

  if v_prod.owner_id is distinct from v_owner and not public.est_plateforme() then
    raise exception 'HORS_BOUTIQUE|Cette production n''appartient pas à votre boutique.';
  end if;

  if v_prod.statut <> 'en_cours' then
    raise exception 'STATUT_INVALIDE|Cette production est déjà close.';
  end if;

  select * into v_produit
    from public.produits p
   where p.id = v_prod.produit_id;

  if not found then
    raise exception 'PRODUIT_INTROUVABLE|Le produit fini de cette production a été supprimé.';
  end if;

  v_pertes := v_prod.quantite_prevue - v_reelle;

  v_cout_u := case
    when v_reelle > 0 then round((v_prod.cout_matieres / v_reelle)::numeric, 2)::real
    else 0
  end;

  -- Le trigger de `ajustements` ajoute la production au stock du produit fini.
  if v_reelle > 0 then
    insert into public.ajustements (
      produit_id, quantite, raison, date, owner_id
    ) values (
      v_prod.produit_id,
      v_reelle,
      'Production ' || coalesce(v_prod.numero, '') || ' — ' || v_produit.nom,
      now(),
      v_owner
    );
  end if;

  update public.productions
     set statut = 'terminee',
         quantite_reelle = v_reelle,
         pertes = v_pertes,
         cout_unitaire = v_cout_u,
         terminee_le = now(),
         updated_at = now()
   where id = p_id
   returning * into v_prod;

  select coalesce(p.quantite, 0)
    into v_stock
    from public.produits p
   where p.id = v_prod.produit_id;

  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(), null, 'PRODUCTION_TERMINEE', v_user,
    jsonb_build_object(
      'production_id',   v_prod.id,
      'numero',          v_prod.numero,
      'produit',         v_produit.nom,
      'quantite_prevue', v_prod.quantite_prevue,
      'quantite_reelle', v_prod.quantite_reelle,
      'pertes',          v_prod.pertes,
      'cout_matieres',   v_prod.cout_matieres,
      'cout_unitaire',   v_prod.cout_unitaire,
      'stock_apres',     v_stock
    ),
    now()
  );

  return jsonb_build_object('ok', true, 'production', to_jsonb(v_prod));
end;
$$;

revoke all on function public.rpc_production_terminer(uuid, numeric) from public;
revoke all on function public.rpc_production_terminer(uuid, numeric) from anon;
grant execute on function public.rpc_production_terminer(uuid, numeric) to authenticated;


-- ============================================================================
-- 10. RPC `rpc_production_annuler` — MATIÈRES RENDUES AU STOCK
-- ============================================================================
create or replace function public.rpc_production_annuler(
  p_id    uuid,
  p_motif text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user  uuid := auth.uid();
  v_owner uuid;
  v_prod  public.productions%rowtype;
  v_ligne record;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour annuler une production.';
  end if;

  if not (public.peut('production', 'creer') or public.peut('production', 'modifier')) then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas d''annuler une production.';
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  select * into v_prod
    from public.productions p
   where p.id = p_id
     for update;

  if not found then
    raise exception 'PRODUCTION_INTROUVABLE|Production introuvable.';
  end if;

  if v_prod.owner_id is distinct from v_owner and not public.est_plateforme() then
    raise exception 'HORS_BOUTIQUE|Cette production n''appartient pas à votre boutique.';
  end if;

  if v_prod.statut <> 'en_cours' then
    raise exception 'STATUT_INVALIDE|Seule une production en cours peut être annulée.';
  end if;

  -- Les matières déjà consommées reviennent au stock (via des compteurs
  -- simples : ces mouvements ne passent pas par les articles).
  for v_ligne in
    select c.matiere_id, c.quantite
      from public.consommations_production c
     where c.production_id = p_id
  loop
    update public.matieres_premieres
       set stock = stock + v_ligne.quantite, updated_at = now()
     where id = v_ligne.matiere_id;
  end loop;

  delete from public.consommations_production where production_id = p_id;

  update public.productions
     set statut = 'annulee',
         motif_annulation = nullif(btrim(coalesce(p_motif, '')), ''),
         cout_matieres = 0,
         updated_at = now()
   where id = p_id
   returning * into v_prod;

  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(), null, 'PRODUCTION_ANNULEE', v_user,
    jsonb_build_object(
      'production_id', v_prod.id,
      'numero',        v_prod.numero,
      'motif',         v_prod.motif_annulation
    ),
    now()
  );

  return jsonb_build_object('ok', true, 'production', to_jsonb(v_prod));
end;
$$;

revoke all on function public.rpc_production_annuler(uuid, text) from public;
revoke all on function public.rpc_production_annuler(uuid, text) from anon;
grant execute on function public.rpc_production_annuler(uuid, text) to authenticated;


-- ============================================================================
-- 11. RPC `rpc_production_tableau_bord` — DASHBOARD DU JOUR
-- ============================================================================
create or replace function public.rpc_production_tableau_bord()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user        uuid := auth.uid();
  v_owner       uuid;
  v_matieres    integer := 0;
  v_alertes     integer := 0;
  v_jour        integer := 0;
  v_quantite    numeric := 0;
  v_pertes      numeric := 0;
  v_cout        real := 0;
  v_dernieres   jsonb := '[]'::jsonb;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour consulter la production.';
  end if;

  if not (public.peut('production', 'voir') or public.est_plateforme()) then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de consulter la production.';
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  select count(*),
         count(*) filter (where stock <= seuil_alerte)
    into v_matieres, v_alertes
    from public.matieres_premieres m
   where m.owner_id = v_owner
     and m.actif;

  select count(*),
         coalesce(sum(quantite_reelle), 0),
         coalesce(sum(pertes), 0),
         coalesce(sum(cout_matieres), 0)
    into v_jour, v_quantite, v_pertes, v_cout
    from public.productions p
   where p.owner_id = v_owner
     and p.statut = 'terminee'
     and p.terminee_le >= current_date;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id',              d.id,
           'numero',          d.numero,
           'produit',         d.produit,
           'statut',          d.statut,
           'quantite_prevue', d.quantite_prevue,
           'quantite_reelle', d.quantite_reelle,
           'pertes',          d.pertes,
           'cout_matieres',   d.cout_matieres,
           'cout_unitaire',   d.cout_unitaire,
           'date',            d.date
         ) order by d.created_at desc), '[]'::jsonb)
    into v_dernieres
    from (
      select p.id, p.numero, pr.nom as produit, p.statut,
             p.quantite_prevue, p.quantite_reelle, p.pertes,
             p.cout_matieres, p.cout_unitaire, p.created_at,
             to_char(p.created_at, 'DD/MM/YYYY HH24:MI') as date
        from public.productions p
        join public.produits pr on pr.id = p.produit_id
       where p.owner_id = v_owner
       order by p.created_at desc
       limit 5
    ) d;

  return jsonb_build_object(
    'ok', true,
    'matieres',          v_matieres,
    'matieres_alerte',   v_alertes,
    'productions_jour',  v_jour,
    'quantite_jour',     v_quantite,
    'pertes_jour',       v_pertes,
    'cout_jour',         v_cout,
    'dernieres',         v_dernieres
  );
end;
$$;

revoke all on function public.rpc_production_tableau_bord() from public;
revoke all on function public.rpc_production_tableau_bord() from anon;
grant execute on function public.rpc_production_tableau_bord() to authenticated;


-- ============================================================================
-- 12. JOURNAL D'AUDIT — NIVEAUX DES ACTIONS PRODUCTION
-- ============================================================================
--  Copie de la fonction de la migration 33 + actions boulangerie :
--    • PRODUCTION_TERMINEE touche au stock → HAUT ;
--    • le reste de l'atelier → MOYEN.

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
    -- 🥖 MODULE 16 C5 — boulangerie.
    when 'PRODUCTION_TERMINEE'        then 'HAUT'
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
    -- 🥖 MODULE 16 C5 — boulangerie.
    when 'MATIERE_ENREGISTREE'        then 'MOYEN'
    when 'MATIERE_MODIFIEE'           then 'MOYEN'
    when 'MATIERE_APPRO'              then 'MOYEN'
    when 'MATIERE_AJUSTEMENT'         then 'MOYEN'
    when 'PRODUCTION'                 then 'MOYEN'
    when 'PRODUCTION_ANNULEE'         then 'MOYEN'
    when 'RAPPORT'                    then 'INFO'
    else 'INFO'
  end;
$$;

comment on function public.audit_niveau(text) is
  'Niveau de gravité d''une action du journal d''audit (CRITIQUE/HAUT/MOYEN/INFO).';


-- ============================================================================
-- 13. PERMISSIONS — PAGE `production`
-- ============================================================================
--  • PROPRIÉTAIRE : tout ;
--  • VENDEUR (boulanger-vendeur) : voir + créer (productions et matières) ;
--  • MAGASINIER : voir + créer + modifier (matières = stock).

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
    'production'
  ];
$$;

comment on function public.pages_permissions() is
  'Liste officielle des pages de permission (Module 4, + securite Module 12, + assistant_ia Module 13, + hôtel C2, + restaurant C3, + salle des fêtes C4, + boulangerie C5).';

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
                         'production'];
      v_actions := public.actions_permissions();

    when 'VENDEUR' then
      v_pages   := array['ventes', 'caisse', 'scanner', 'panier', 'assistant_ia',
                         -- 🏨 MODULE 16 C2 — réceptionniste d'hôtel.
                         'chambres', 'reservations', 'reception',
                         -- 🍽️ MODULE 16 C3 — serveur / cuisine.
                         'tables', 'commandes', 'cuisine',
                         -- 🎉 MODULE 16 C4 — agent d'accueil événementiel.
                         'salles', 'evenements',
                         -- 🥖 MODULE 16 C5 — boulanger-vendeur.
                         'production'];
      v_actions := array['voir', 'creer'];

    when 'MAGASINIER' then
      v_pages   := array['stock', 'articles', 'qr_codes', 'rapports',
                         'assistant_ia',
                         -- 🥖 MODULE 16 C5 — atelier / réserve.
                         'production'];
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
      -- 🥖 C5 — l'atelier gère les matières et les productions.
      || jsonb_build_object('production',   to_jsonb(array['voir', 'creer', 'modifier']))
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
  'Matrice des permissions par défaut (Module 4, + audit/securite M12, + assistant_ia M13, + hôtel C2, + restaurant C3, + salle des fêtes C4, + boulangerie C5).';


-- ============================================================================
-- 14. PROFIL « BOULANGERIE » — RÉFÉRENTIEL DES ACTIVITÉS (Module 16 A)
-- ============================================================================
insert into public.types_espaces_modules (type, libelle, modules) values
  ('boulangerie', 'Boulangerie',
   '["ventes","produits","stock","qr","caisse","clients","finance","employes","rapports","assistant_ia","production"]'::jsonb)
on conflict (type) do nothing;


-- ============================================================================
-- 15. VÉRIFICATIONS
-- ============================================================================

-- 15.a Les trois tables existent (attendu : 3).
select count(*) as tables_boulangerie
  from information_schema.tables
 where table_schema = 'public'
   and table_name in ('matieres_premieres', 'productions', 'consommations_production');

-- 15.b La page `production` est déclarée (attendu : true).
select position('production' in array_to_string(public.pages_permissions(), ',')) > 0
       as page_production;

-- 15.c Matrices par défaut (attendu : true / ["voir","creer"] / ["voir","creer","modifier"]).
select (public.permissions_defaut('PROPRIETAIRE') ? 'production') as proprio_production,
       (public.permissions_defaut('VENDEUR') -> 'production') as vendeur_production,
       (public.permissions_defaut('MAGASINIER') -> 'production') as magasinier_production;

-- 15.d Le profil « Boulangerie » est enregistré (attendu : 1 ligne, 11 modules).
select type, libelle, jsonb_array_length(modules) as nb_modules
  from public.types_espaces_modules
 where type = 'boulangerie';

-- 15.e Exemples d'appel (à exécuter avec un vrai compte) :
--     select public.rpc_matiere_enregistrer(null, 'Farine T55', 'kg', 20, 1500);
--     select public.rpc_matiere_approvisionner(
--              (select id from public.matieres_premieres limit 1), 50, 1500, 'Achat marché');
--     select public.rpc_production_creer(
--              (select id from public.produits limit 1), 100, 'Fournée du matin');
--     select public.rpc_production_tableau_bord();

-- ============================================================================
--  FIN — Module 16 C5 (boulangerie). L'application (prochaine version)
--  affiche la carte « Production », les matières premières, les productions
--  du jour (quantités, pertes, coût de revient) et alimente le stock du
--  produit fini à la clôture.
-- ============================================================================
