-- ============================================================================
--  BIASHARA YANGU — MIGRATION 0084
--  RÉCIPIENTS, ÉCHANGES, FARDES ET BONUS (distribution professionnelle)
--  ---------------------------------------------------------------------------
--  OBJECTIF
--  --------
--  Donner à une entreprise de DISTRIBUTION les moyens de suivre ce qu'elle
--  confie, ce qu'elle récupère et ce qu'elle offre, sans jamais confondre :
--    • un récipient VENDU (il ne revient pas),
--    • un récipient PRÊTÉ/CONSIGNÉ (il doit revenir),
--    • un récipient ÉCHANGÉ (vide repris ↔ plein livré),
--    • un récipient PERDU ou CASSÉ (perte sèche, à imputer).
--
--  PRINCIPE DE CONCEPTION (important)
--  ----------------------------------
--  Cette migration N'ÉCRIT AUCUNE VENTE : elle enregistre uniquement les
--  MOUVEMENTS DE RÉCIPIENTS et les BONUS. L'encaissement reste du ressort de
--  la caisse / des tournées existantes (`rpc_tournee_vente`). Aucun montant
--  n'est donc compté deux fois et le chiffre d'affaires reste exact.
--
--  ⚠️ Aucune table existante n'est modifiée ou supprimée.
--  ⚠️ Écritures directes révoquées : tout passe par les RPC (security definer).
-- ============================================================================

begin;

-- ===========================================================================
-- 1. TYPES DE RÉCIPIENTS (bidon 20 L, casier 12 bouteilles, farde…)
-- ===========================================================================
create table if not exists public.recipients_types (
  id                  uuid primary key default gen_random_uuid(),
  owner_id            uuid not null,
  libelle             text not null,
  contenance_litres   numeric(10,2),
  prix_consigne       numeric(12,2) not null default 0,
  actif               boolean not null default true,
  ordre               integer not null default 50,
  created_at          timestamptz not null default now(),
  constraint recipients_types_prix_positif check (prix_consigne >= 0)
);

create index if not exists idx_recipients_types_owner
  on public.recipients_types (owner_id, actif);

-- ===========================================================================
-- 2. MOUVEMENTS DE RÉCIPIENTS (le grand livre)
-- ===========================================================================
create table if not exists public.recipients_mouvements (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null,
  agent_id    uuid,
  client_id   uuid,
  client_nom  text,
  tournee_id  uuid,
  type_id     uuid references public.recipients_types (id) on delete set null,
  -- livre    : sortie d'un récipient PLEIN confié au client (il le doit)
  -- vendu    : récipient NEUF facturé (il appartient au client)
  -- recupere : récipient VIDE rendu par le client
  -- casse    : récipient détruit (perte)
  -- perdu    : récipient non rendu (perte)
  sens        text not null,
  quantite    integer not null,
  montant     numeric(12,2) not null default 0,
  note        text,
  created_at  timestamptz not null default now(),
  annule_le   timestamptz,
  constraint recipients_mouvements_sens check (
    sens in ('livre', 'vendu', 'recupere', 'casse', 'perdu')
  ),
  constraint recipients_mouvements_quantite check (quantite > 0)
);

create index if not exists idx_recipients_mv_owner
  on public.recipients_mouvements (owner_id, created_at desc);
create index if not exists idx_recipients_mv_client
  on public.recipients_mouvements (client_id, created_at desc);
create index if not exists idx_recipients_mv_tournee
  on public.recipients_mouvements (tournee_id);

-- ===========================================================================
-- 3. RÈGLES DE BONUS (5 fardes achetées = 1 offerte…)
-- ===========================================================================
create table if not exists public.regles_bonus (
  id                    uuid primary key default gen_random_uuid(),
  owner_id              uuid not null,
  libelle               text not null,
  produit_id            uuid,
  type_declencheur      text not null default 'farde',
  quantite_declencheur  integer not null,
  type_offert           text not null default 'farde',
  quantite_offerte      integer not null,
  actif                 boolean not null default true,
  created_at            timestamptz not null default now(),
  constraint regles_bonus_declencheur check (
    type_declencheur in ('farde', 'recipient', 'unite')
  ),
  constraint regles_bonus_offert check (
    type_offert in ('farde', 'recipient', 'unite')
  ),
  constraint regles_bonus_quantites check (
    quantite_declencheur > 0 and quantite_offerte > 0
  )
);

create index if not exists idx_regles_bonus_owner
  on public.regles_bonus (owner_id, actif);

-- Historique des bonus accordés (anti double attribution).
create table if not exists public.bonus_attribues (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null,
  client_id   uuid,
  regle_id    uuid references public.regles_bonus (id) on delete set null,
  tournee_id  uuid,
  produit_id  uuid,
  quantite    integer not null,
  created_at  timestamptz not null default now(),
  annule_le   timestamptz,
  constraint bonus_attribues_quantite check (quantite > 0),
  -- Même règle, même client, même tournée → UNE seule attribution.
  constraint bonus_attribues_unique unique (client_id, regle_id, tournee_id)
);

create index if not exists idx_bonus_attribues_owner
  on public.bonus_attribues (owner_id, created_at desc);

-- ===========================================================================
-- 4. RLS — lecture seule pour le propriétaire (écritures = RPC)
-- ===========================================================================
alter table public.recipients_types      enable row level security;
alter table public.recipients_mouvements enable row level security;
alter table public.regles_bonus          enable row level security;
alter table public.bonus_attribues       enable row level security;

drop policy if exists m84_recipients_types_lecture on public.recipients_types;
create policy m84_recipients_types_lecture on public.recipients_types
  for select using (
    owner_id = auth.uid() or owner_id = public.mon_proprietaire()
  );

drop policy if exists m84_recipients_mv_lecture on public.recipients_mouvements;
create policy m84_recipients_mv_lecture on public.recipients_mouvements
  for select using (
    owner_id = auth.uid() or owner_id = public.mon_proprietaire()
  );

drop policy if exists m84_regles_bonus_lecture on public.regles_bonus;
create policy m84_regles_bonus_lecture on public.regles_bonus
  for select using (
    owner_id = auth.uid() or owner_id = public.mon_proprietaire()
  );

drop policy if exists m84_bonus_attribues_lecture on public.bonus_attribues;
create policy m84_bonus_attribues_lecture on public.bonus_attribues
  for select using (
    owner_id = auth.uid() or owner_id = public.mon_proprietaire()
  );

-- Aucune policy d'écriture : tout passe par les RPC ci-dessous.
revoke insert, update, delete on public.recipients_types      from authenticated, anon;
revoke insert, update, delete on public.recipients_mouvements from authenticated, anon;
revoke insert, update, delete on public.regles_bonus          from authenticated, anon;
revoke insert, update, delete on public.bonus_attribues       from authenticated, anon;

-- ===========================================================================
-- 5. TYPES DE RÉCIPIENTS — RPC
-- ===========================================================================
create or replace function public.rpc_recipient_type_enregistrer(
  p_id             uuid default null,
  p_libelle        text default null,
  p_contenance     numeric default null,
  p_prix_consigne  numeric default 0,
  p_actif          boolean default true,
  p_ordre          integer default 50
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid := auth.uid();
  v_id    uuid;
begin
  if v_owner is null then
    raise exception 'SESSION_ABSENTE|Reconnectez-vous.';
  end if;
  if p_libelle is null or btrim(p_libelle) = '' then
    raise exception 'LIBELLE_REQUIS|Indiquez le nom du récipient.';
  end if;
  if coalesce(p_prix_consigne, 0) < 0 then
    raise exception 'PRIX_INVALIDE|Le prix de consigne ne peut pas être négatif.';
  end if;

  if p_id is null then
    insert into public.recipients_types
      (owner_id, libelle, contenance_litres, prix_consigne, actif, ordre)
    values
      (v_owner, btrim(p_libelle), p_contenance,
       coalesce(p_prix_consigne, 0), coalesce(p_actif, true),
       coalesce(p_ordre, 50))
    returning id into v_id;
  else
    update public.recipients_types
       set libelle           = btrim(p_libelle),
           contenance_litres = p_contenance,
           prix_consigne     = coalesce(p_prix_consigne, 0),
           actif             = coalesce(p_actif, true),
           ordre             = coalesce(p_ordre, 50)
     where id = p_id
       and (owner_id = v_owner or owner_id = public.mon_proprietaire())
    returning id into v_id;

    if v_id is null then
      raise exception 'RECIPIENT_INTROUVABLE|Ce type de récipient est introuvable.';
    end if;
  end if;

  return v_id;
end;
$$;

create or replace function public.rpc_recipients_types_lister()
returns table (
  id                uuid,
  libelle           text,
  contenance_litres numeric,
  prix_consigne     numeric,
  actif             boolean,
  ordre             integer
)
language sql
stable
security definer
set search_path = public
as $$
  select t.id, t.libelle, t.contenance_litres, t.prix_consigne, t.actif, t.ordre
    from public.recipients_types t
   where t.owner_id = auth.uid() or t.owner_id = public.mon_proprietaire()
   order by t.ordre, t.libelle;
$$;

-- ===========================================================================
-- 6. VENTE AVEC RÉCIPIENT — les TROIS cas du métier
-- ===========================================================================
--  p_mode :
--    'nouveau' : le client achète l'eau ET le récipient neuf
--    'echange' : le client rend un vide et reçoit un plein
--    'propre'  : le client utilise SON récipient (remplissage seul)
--
--  Ne crée AUCUNE vente : renvoie les montants à encaisser par l'appelant.
create or replace function public.rpc_vente_recipient(
  p_mode             text,
  p_quantite         integer default 1,
  p_type_id          uuid default null,
  p_client_id        uuid default null,
  p_client_nom       text default null,
  p_tournee_id       uuid default null,
  p_prix_eau         numeric default 0,
  p_prix_recipient   numeric default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner     uuid := auth.uid();
  v_mode      text := lower(btrim(coalesce(p_mode, '')));
  v_qte       integer := greatest(coalesce(p_quantite, 1), 1);
  v_prix_eau  numeric := coalesce(p_prix_eau, 0);
  v_prix_rec  numeric;
  v_eau       numeric;
  v_rec       numeric := 0;
  v_type_id   uuid;
  v_type_lib  text;
  v_type_prix numeric;
  v_mv        integer := 0;
begin
  if v_owner is null then
    raise exception 'SESSION_ABSENTE|Reconnectez-vous.';
  end if;
  if v_mode not in ('nouveau', 'echange', 'propre') then
    raise exception 'MODE_INVALIDE|Type d''opération inconnu : %', p_mode;
  end if;
  if v_prix_eau < 0 then
    raise exception 'PRIX_INVALIDE|Le prix de l''eau ne peut pas être négatif.';
  end if;

  if p_type_id is not null then
    select t.id, t.libelle, t.prix_consigne
      into v_type_id, v_type_lib, v_type_prix
      from public.recipients_types t
     where t.id = p_type_id
       and (t.owner_id = v_owner or t.owner_id = public.mon_proprietaire());
    if v_type_id is null then
      raise exception 'RECIPIENT_INTROUVABLE|Ce type de récipient est introuvable.';
    end if;
  end if;

  v_prix_rec := coalesce(p_prix_recipient, v_type_prix, 0);
  v_eau := v_prix_eau * v_qte;

  -- 1) Nouveau récipient facturé au client.
  if v_mode = 'nouveau' then
    v_rec := v_prix_rec * v_qte;
    insert into public.recipients_mouvements
      (owner_id, agent_id, client_id, client_nom, tournee_id, type_id,
       sens, quantite, montant)
    values
      (v_owner, v_owner, p_client_id, p_client_nom, p_tournee_id,
       v_type_id, 'vendu', v_qte, v_rec);
    v_mv := v_mv + 1;

  -- 2) Échange : un vide repris, un plein livré.
  elsif v_mode = 'echange' then
    insert into public.recipients_mouvements
      (owner_id, agent_id, client_id, client_nom, tournee_id, type_id,
       sens, quantite, montant)
    values
      (v_owner, v_owner, p_client_id, p_client_nom, p_tournee_id,
       v_type_id, 'recupere', v_qte, 0);
    insert into public.recipients_mouvements
      (owner_id, agent_id, client_id, client_nom, tournee_id, type_id,
       sens, quantite, montant)
    values
      (v_owner, v_owner, p_client_id, p_client_nom, p_tournee_id,
       v_type_id, 'livre', v_qte, 0);
    v_mv := v_mv + 2;

  -- 3) Récipient du client : AUCUN mouvement de récipient.
  else
    v_mv := 0;
  end if;

  return jsonb_build_object(
    'mode',              v_mode,
    'quantite',          v_qte,
    'montant_eau',       v_eau,
    'montant_recipient', v_rec,
    'montant_total',     v_eau + v_rec,
    'mouvements',        v_mv,
    'type_libelle',      v_type_lib
  );
end;
$$;

-- ===========================================================================
-- 7. CE QUE DÉTIENT UN CLIENT (récipients à récupérer)
-- ===========================================================================
create or replace function public.rpc_recipients_solde_client(
  p_client_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with mv as (
    select m.sens, sum(m.quantite)::int as q
      from public.recipients_mouvements m
     where (m.owner_id = auth.uid() or m.owner_id = public.mon_proprietaire())
       and m.annule_le is null
       and (p_client_id is null or m.client_id = p_client_id)
     group by m.sens
  )
  select jsonb_build_object(
    'livres',    coalesce((select q from mv where sens = 'livre'), 0),
    'vendus',    coalesce((select q from mv where sens = 'vendu'), 0),
    'recuperes', coalesce((select q from mv where sens = 'recupere'), 0),
    'casses',    coalesce((select q from mv where sens = 'casse'), 0),
    'perdus',    coalesce((select q from mv where sens = 'perdu'), 0),
    -- DÉTENUS = ce qui est sorti et qui doit revenir.
    'detenus',   greatest(
       coalesce((select q from mv where sens = 'livre'), 0)
       - coalesce((select q from mv where sens = 'recupere'), 0)
       - coalesce((select q from mv where sens = 'perdu'), 0)
       - coalesce((select q from mv where sens = 'casse'), 0),
       0)
  );
$$;

-- ===========================================================================
-- 8. TABLEAU DE BORD RÉCIPIENTS
-- ===========================================================================
create or replace function public.rpc_recipients_tableau_bord()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with mv as (
    select m.sens, sum(m.quantite)::int as q
      from public.recipients_mouvements m
     where (m.owner_id = auth.uid() or m.owner_id = public.mon_proprietaire())
       and m.annule_le is null
     group by m.sens
  ),
  clients as (
    select count(distinct m.client_id)::int as n
      from public.recipients_mouvements m
     where (m.owner_id = auth.uid() or m.owner_id = public.mon_proprietaire())
       and m.annule_le is null
       and m.client_id is not null
  )
  select jsonb_build_object(
    'livres',      coalesce((select q from mv where sens = 'livre'), 0),
    'vendus',      coalesce((select q from mv where sens = 'vendu'), 0),
    'recuperes',   coalesce((select q from mv where sens = 'recupere'), 0),
    'casses',      coalesce((select q from mv where sens = 'casse'), 0),
    'perdus',      coalesce((select q from mv where sens = 'perdu'), 0),
    'chez_clients', greatest(
       coalesce((select q from mv where sens = 'livre'), 0)
       - coalesce((select q from mv where sens = 'recupere'), 0)
       - coalesce((select q from mv where sens = 'perdu'), 0)
       - coalesce((select q from mv where sens = 'casse'), 0),
       0),
    'clients_concernes', coalesce((select n from clients), 0)
  );
$$;

-- ===========================================================================
-- 8 bis. PERTES (casse, perdu) — sortie définitive constatée
-- ===========================================================================
create or replace function public.rpc_recipient_perte(
  p_type_id   uuid,
  p_quantite  integer default 1,
  p_sens      text default 'perdu',
  p_client_id uuid default null,
  p_note      text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid := auth.uid();
  v_sens  text := lower(btrim(coalesce(p_sens, 'perdu')));
  v_qte   integer := greatest(coalesce(p_quantite, 1), 1);
  v_id    uuid;
begin
  if v_owner is null then
    raise exception 'SESSION_ABSENTE|Reconnectez-vous.';
  end if;
  if v_sens not in ('casse', 'perdu') then
    raise exception 'SENS_INVALIDE|Seules les pertes (casse/perdu) sont acceptées ici.';
  end if;

  insert into public.recipients_mouvements
    (owner_id, agent_id, client_id, tournee_id, type_id, sens, quantite,
     montant, note)
  values
    (v_owner, v_owner, p_client_id, null, p_type_id, v_sens, v_qte, 0, p_note)
  returning id into v_id;

  return v_id;
end;
$$;

-- ===========================================================================
-- 9. RÈGLES DE BONUS — RPC
-- ===========================================================================
create or replace function public.rpc_bonus_regle_enregistrer(
  p_id                   uuid default null,
  p_libelle              text default null,
  p_produit_id           uuid default null,
  p_type_declencheur     text default 'farde',
  p_quantite_declencheur integer default 5,
  p_type_offert          text default 'farde',
  p_quantite_offerte     integer default 1,
  p_actif                boolean default true
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid := auth.uid();
  v_id    uuid;
begin
  if v_owner is null then
    raise exception 'SESSION_ABSENTE|Reconnectez-vous.';
  end if;
  if p_libelle is null or btrim(p_libelle) = '' then
    raise exception 'LIBELLE_REQUIS|Donnez un nom à la règle de bonus.';
  end if;
  if coalesce(p_quantite_declencheur, 0) <= 0
     or coalesce(p_quantite_offerte, 0) <= 0 then
    raise exception 'QUANTITE_INVALIDE|Les quantités doivent être supérieures à zéro.';
  end if;

  if p_id is null then
    insert into public.regles_bonus
      (owner_id, libelle, produit_id, type_declencheur,
       quantite_declencheur, type_offert, quantite_offerte, actif)
    values
      (v_owner, btrim(p_libelle), p_produit_id,
       coalesce(p_type_declencheur, 'farde'),
       p_quantite_declencheur,
       coalesce(p_type_offert, 'farde'),
       p_quantite_offerte, coalesce(p_actif, true))
    returning id into v_id;
  else
    update public.regles_bonus
       set libelle              = btrim(p_libelle),
           produit_id           = p_produit_id,
           type_declencheur     = coalesce(p_type_declencheur, 'farde'),
           quantite_declencheur = p_quantite_declencheur,
           type_offert          = coalesce(p_type_offert, 'farde'),
           quantite_offerte     = p_quantite_offerte,
           actif                = coalesce(p_actif, true)
     where id = p_id
       and (owner_id = v_owner or owner_id = public.mon_proprietaire())
    returning id into v_id;

    if v_id is null then
      raise exception 'REGLE_INTROUVABLE|Règle de bonus introuvable.';
    end if;
  end if;

  return v_id;
end;
$$;

create or replace function public.rpc_regles_bonus_lister()
returns table (
  id                   uuid,
  libelle              text,
  produit_id           uuid,
  type_declencheur     text,
  quantite_declencheur integer,
  type_offert          text,
  quantite_offerte     integer,
  actif                boolean
)
language sql
stable
security definer
set search_path = public
as $$
  select r.id, r.libelle, r.produit_id, r.type_declencheur,
         r.quantite_declencheur, r.type_offert, r.quantite_offerte, r.actif
    from public.regles_bonus r
   where r.owner_id = auth.uid() or r.owner_id = public.mon_proprietaire()
   order by r.actif desc, r.libelle;
$$;

-- Applique les règles actives du produit pour une quantité achetée.
-- Idempotent : (client, règle, tournée) → une seule attribution.
create or replace function public.rpc_bonus_appliquer(
  p_produit_id       uuid,
  p_quantite_achetee integer,
  p_client_id        uuid default null,
  p_client_nom       text default null,
  p_tournee_id       uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner   uuid := auth.uid();
  v_regle   record;
  v_bonus   integer;
  v_total   integer := 0;
  v_details jsonb   := '[]'::jsonb;
begin
  if v_owner is null then
    raise exception 'SESSION_ABSENTE|Reconnectez-vous.';
  end if;
  if coalesce(p_quantite_achetee, 0) <= 0 then
    return jsonb_build_object('quantite_offerte', 0, 'details', v_details);
  end if;

  for v_regle in
    select *
      from public.regles_bonus r
     where (r.owner_id = v_owner or r.owner_id = public.mon_proprietaire())
       and r.actif
       and (r.produit_id is null or r.produit_id = p_produit_id)
     order by r.quantite_declencheur
  loop
    v_bonus := (p_quantite_achetee / v_regle.quantite_declencheur)
               * v_regle.quantite_offerte;
    if v_bonus > 0 then
      begin
        insert into public.bonus_attribues
          (owner_id, client_id, regle_id, tournee_id, produit_id, quantite)
        values
          (v_owner, p_client_id, v_regle.id, p_tournee_id, p_produit_id, v_bonus);
      exception
        when unique_violation then
          -- Déjà attribué pour cette tournée : on ne double pas.
          v_bonus := 0;
      end;

      if v_bonus > 0 then
        v_total := v_total + v_bonus;
        v_details := v_details || jsonb_build_object(
          'regle', v_regle.libelle,
          'quantite', v_bonus,
          'type_offert', v_regle.type_offert
        );
        -- Trace visible dans l'écran « Bonus » existant (module 23).
        insert into public.bonus_clients
          (owner_id, agent_id, client_id, client_nom, tournee_id,
           nature, montant, description, date_bonus)
        values
          (v_owner, v_owner, p_client_id, p_client_nom, p_tournee_id,
           'cadeau', 0,
           v_regle.libelle || ' : ' || v_bonus || ' offert(s)', now());
      end if;
    end if;
  end loop;

  return jsonb_build_object('quantite_offerte', v_total, 'details', v_details);
end;
$$;

-- ===========================================================================
-- 10. PERMISSIONS D'EXÉCUTION
-- ===========================================================================
revoke all on function public.rpc_recipient_type_enregistrer(uuid, text, numeric, numeric, boolean, integer) from public;
revoke all on function public.rpc_recipients_types_lister() from public;
revoke all on function public.rpc_vente_recipient(text, integer, uuid, uuid, text, uuid, numeric, numeric) from public;
revoke all on function public.rpc_recipients_solde_client(uuid) from public;
revoke all on function public.rpc_recipients_tableau_bord() from public;
revoke all on function public.rpc_bonus_regle_enregistrer(uuid, text, uuid, text, integer, text, integer, boolean) from public;
revoke all on function public.rpc_regles_bonus_lister() from public;
revoke all on function public.rpc_bonus_appliquer(uuid, integer, uuid, text, uuid) from public;
revoke all on function public.rpc_recipient_perte(uuid, integer, text, uuid, text) from public;

grant execute on function public.rpc_recipient_type_enregistrer(uuid, text, numeric, numeric, boolean, integer) to authenticated;
grant execute on function public.rpc_recipients_types_lister() to authenticated;
grant execute on function public.rpc_vente_recipient(text, integer, uuid, uuid, text, uuid, numeric, numeric) to authenticated;
grant execute on function public.rpc_recipients_solde_client(uuid) to authenticated;
grant execute on function public.rpc_recipients_tableau_bord() to authenticated;
grant execute on function public.rpc_bonus_regle_enregistrer(uuid, text, uuid, text, integer, text, integer, boolean) to authenticated;
grant execute on function public.rpc_regles_bonus_lister() to authenticated;
grant execute on function public.rpc_bonus_appliquer(uuid, integer, uuid, text, uuid) to authenticated;
grant execute on function public.rpc_recipient_perte(uuid, integer, text, uuid, text) to authenticated;

commit;

-- ============================================================================
--  CONTRÔLE (à exécuter séparément) :
--
--    select 'recipients_types' as objet, count(*) from public.recipients_types
--    union all select 'recipients_mouvements', count(*) from public.recipients_mouvements
--    union all select 'regles_bonus', count(*) from public.regles_bonus
--    union all select 'bonus_attribues', count(*) from public.bonus_attribues;
-- ============================================================================
