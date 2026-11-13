-- ============================================================================
--  biashara_yangu — MIGRATION 0163 : LOTS DE MÉDICAMENTS (PHARMACIE)
--
--  PROBLÈME MÉTIER
--    Un médicament n'a pas UNE date de péremption : il a AUTANT de dates que
--    de réceptions. Le Paracétamol peut arriver en trois lots :
--        Lot A — 100 boîtes — décembre 2026
--        Lot B — 150 boîtes — juin 2027
--        Lot C —  80 boîtes — septembre 2027
--    Une seule date sur la fiche de l'article est donc fausse dès la
--    deuxième réception : on ne sait plus quel stock périme quand, ni ce qui
--    reste réellement vendable.
--
--  CE QUE FAIT CE SCRIPT (idempotent, aucune donnée supprimée)
--    1. `produits_lots` : un lot = une réception (numéro, péremption,
--       quantité reçue, quantité RESTANTE, prix d'achat, fournisseur).
--    2. `produits_lots_mouvements` : historique de chaque entrée, vente et
--       retrait de lot (rien n'est jamais effacé).
--    3. Une réception de lot augmente `produits.quantite` (via le lot, jamais
--       à la main), et la fiche article affiche la péremption la PLUS PROCHE
--       des lots encore valides.
--    4. La vente :
--         • refuse un article dont la péremption de fiche est passée
--           (règle du module 16 C1, perdue depuis la réécriture 0116) ;
--         • refuse de vendre plus que le stock VALIDE des lots (les lots
--           périmés ne sont jamais vendables) ;
--         • consomme les lots en FEFO : la péremption la plus proche d'abord,
--           puis la suivante (verrou `for update` : deux caisses simultanées
--           ne peuvent pas vendre deux fois le même lot).
--    5. Un lot retiré (casse, rappel, péremption) sort du stock par un
--       `ajustements` tracé — jamais par une écriture silencieuse.
--
--  ⚠️ COMPATIBILITÉ
--    • Les articles SANS aucun lot gardent le comportement historique : le
--      stock de la fiche fait foi, aucun blocage nouveau.
--    • `produits.date_expiration` / `produits.lot_numero` restent renseignés
--      (résumé du lot le plus proche) : l'écran Expirations et le rapport
--      `expirations` continuent de fonctionner sans modification.
--
--  PRÉ-REQUIS : modules 4 (peut/est_plateforme), 5 (mon_proprietaire),
--  9 (ajustements) et 16 C1 (date_expiration) exécutés.
--  À exécuter dans le SQL Editor Supabase (DDL + triggers).
-- ============================================================================

select set_config('search_path', 'public, extensions', true);


-- ============================================================================
--  0. CONTRÔLES PRÉALABLES
-- ============================================================================

do $$
begin
  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where p.proname = 'mon_proprietaire' and n.nspname = 'public'
  ) then
    raise exception
      'Module 5 absent : exécutez 20260916000008_module5_articles.sql avant 0163.';
  end if;

  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where p.proname = 'peut' and n.nspname = 'public'
  ) then
    raise exception
      'Module 4 absent : exécutez 20260916000006_module4_permissions.sql avant 0163.';
  end if;

  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'produits'
      and column_name = 'date_expiration'
  ) then
    raise exception
      'Colonne produits.date_expiration absente : exécutez 20260916000029_module16c1_pharmacie.sql.';
  end if;
end $$;


-- ============================================================================
--  1. LES LOTS
-- ============================================================================

create table if not exists public.produits_lots (
  id                   uuid primary key default gen_random_uuid(),
  owner_id             uuid not null,
  produit_id           bigint not null references public.produits(id) on delete cascade,
  numero_lot           text not null,
  date_fabrication     date,
  date_peremption      date not null,
  quantite_recue       numeric not null check (quantite_recue > 0),
  quantite_restante    numeric not null check (quantite_restante >= 0),
  prix_achat_unitaire  numeric,
  fournisseur          text,
  observations         text,
  recu_le              timestamptz not null default now(),
  recu_par             uuid,
  retire_le            timestamptz,
  motif_retrait        text,
  constraint produits_lots_quantite_coherente
    check (quantite_restante <= quantite_recue),
  constraint produits_lots_unique
    unique (produit_id, numero_lot, date_peremption)
);

comment on table public.produits_lots is
  'Module 36 (0163) — un lot reçu pour un article : quantité restante, prix d''achat et date de péremption PROPRES au lot. Un médicament reçu trois fois = trois lignes.';
comment on column public.produits_lots.quantite_restante is
  'Quantité encore en rayon pour ce lot (décrémentée FEFO par les ventes, mise à 0 par un retrait).';
comment on column public.produits_lots.retire_le is
  'Lot retiré du stock (casse, rappel, péremption) : il n''est plus vendable et ne compte plus dans la péremption affichée.';

create index if not exists idx_produits_lots_produit_fefo
  on public.produits_lots (produit_id, date_peremption)
  where retire_le is null;

create index if not exists idx_produits_lots_owner_perm
  on public.produits_lots (owner_id, date_peremption)
  where retire_le is null;


-- ============================================================================
--  2. L'HISTORIQUE DES MOUVEMENTS DE LOT
-- ============================================================================

create table if not exists public.produits_lots_mouvements (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null,
  produit_id  bigint not null references public.produits(id) on delete cascade,
  lot_id      uuid references public.produits_lots(id) on delete cascade,
  type        text not null check (type in ('entree', 'vente', 'retrait')),
  quantite    numeric not null,          -- signée : + reçu, − vendu/retiré
  motif       text,
  vente_id    bigint,
  date        timestamptz not null default now(),
  fait_par    uuid default auth.uid()
);

comment on table public.produits_lots_mouvements is
  'Module 36 (0163) — historique APPEND-ONLY des lots : chaque entrée, chaque consommation FEFO par une vente, chaque retrait. Sert aux rapports de pertes.';

create index if not exists idx_lots_mouvements_owner_date
  on public.produits_lots_mouvements (owner_id, date desc);
create index if not exists idx_lots_mouvements_lot
  on public.produits_lots_mouvements (lot_id, date desc);


-- ============================================================================
--  3. RLS — LECTURE SEULE CÔTÉ CLIENT, ÉCRITURES PAR RPC/TRIGGERS
-- ============================================================================

alter table public.produits_lots enable row level security;
alter table public.produits_lots_mouvements enable row level security;

drop policy if exists m36_lots_lecture on public.produits_lots;
create policy m36_lots_lecture on public.produits_lots
  for select
  using (owner_id = public.mon_proprietaire() or public.est_plateforme());

drop policy if exists m36_lots_mouvements_lecture
  on public.produits_lots_mouvements;
create policy m36_lots_mouvements_lecture
  on public.produits_lots_mouvements
  for select
  using (owner_id = public.mon_proprietaire() or public.est_plateforme());

-- ⚠️ AUCUNE policy d'INSERT/UPDATE/DELETE : les écritures passent
--    exclusivement par les RPC `security definer` ci-dessous, qui vérifient
--    les droits ET l'appartenance de l'article à l'entreprise active.


-- ============================================================================
--  4. GARDE-FOUS DE LA TABLE (propriétaire, cohérence, immuabilité)
-- ============================================================================

create or replace function public.trg_lots_avant_insertion()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_produit public.produits%rowtype;
begin
  select p.* into v_produit
    from public.produits p
   where p.id = new.produit_id;

  if v_produit.id is null then
    raise exception 'ARTICLE_INTROUVABLE|Article introuvable : impossible d''enregistrer un lot.';
  end if;

  -- Le lot appartient TOUJOURS au propriétaire de l'article (jamais à celui
  -- qui saisit : un collaborateur ne crée pas un lot pour une autre boutique).
  new.owner_id := v_produit.owner_id;
  new.numero_lot := btrim(coalesce(new.numero_lot, ''));

  if new.numero_lot = '' then
    raise exception 'LOT_OBLIGATOIRE|Le numéro de lot est obligatoire.';
  end if;

  if new.date_peremption is null then
    raise exception 'PEREMPTION_OBLIGATOIRE|La date de péremption est obligatoire.';
  end if;

  if new.date_fabrication is not null
     and new.date_fabrication > new.date_peremption then
    raise exception 'DATES_INCOHERENTES|La date de fabrication ne peut pas être postérieure à la péremption.';
  end if;

  if new.quantite_restante is null then
    new.quantite_restante := new.quantite_recue;
  end if;

  if new.quantite_restante > new.quantite_recue then
    raise exception 'QUANTITE_INCOHERENTE|La quantité restante ne peut pas dépasser la quantité reçue.';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_lots_avant_insertion on public.produits_lots;
create trigger trg_lots_avant_insertion
  before insert on public.produits_lots
  for each row
  execute function public.trg_lots_avant_insertion();


-- La date de péremption d'un lot ne change JAMAIS après coup : une nouvelle
-- réception crée un NOUVEAU lot. Pour corriger une saisie erronée, on retire le
-- lot (RPC rpc_lot_retirer, motif tracé) puis on enregistre le bon.
create or replace function public.trg_lots_date_immuable()
returns trigger
language plpgsql
as $$
begin
  if new.date_peremption is distinct from old.date_peremption then
    raise exception 'LOT_DATE_IMMUABLE|La date de péremption d''un lot ne peut pas être modifiée. Créez un nouveau lot.';
  end if;
  if new.quantite_recue is distinct from old.quantite_recue then
    raise exception 'LOT_QUANTITE_IMMUABLE|La quantité reçue d''un lot ne peut pas être modifiée. Enregistrez une nouvelle réception.';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_lots_date_immuable on public.produits_lots;
create trigger trg_lots_date_immuable
  before update on public.produits_lots
  for each row
  execute function public.trg_lots_date_immuable();


-- ============================================================================
--  5. RÉSUMÉ DE PÉREMPTION SUR LA FICHE ARTICLE
-- ============================================================================
--  La fiche ne remplace pas les lots : elle en affiche le RÉSUMÉ (la
--  péremption la plus proche encore valide). Les écrans existants
--  (Expirations, rapport `expirations`) continuent donc de fonctionner.

create or replace function public.lots_rafraichir_peremption(p_produit_id bigint)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_date date;
  v_lot  text;
begin
  select l.date_peremption, l.numero_lot
    into v_date, v_lot
    from public.produits_lots l
   where l.produit_id = p_produit_id
     and l.retire_le is null
     and l.quantite_restante > 0
     and l.date_peremption >= current_date
   order by l.date_peremption asc, l.recu_le asc
   limit 1;

  update public.produits p
     set date_expiration = v_date,
         lot_numero      = v_lot
   where p.id = p_produit_id;
end;
$$;

comment on function public.lots_rafraichir_peremption(bigint) is
  'Module 36 (0163) — reporte sur la fiche article la péremption du lot valide le plus proche (résumé, jamais un remplacement des lots).';


-- ============================================================================
--  6. RÉCEPTION D'UN LOT
-- ============================================================================

create or replace function public.trg_lots_apres_entree()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Le stock de l'article augmente PAR LE LOT : une seule écriture, celle du
  -- trigger, exactement comme `approvisionnements`.
  update public.produits p
     set quantite = coalesce(p.quantite, 0) + new.quantite_recue
   where p.id = new.produit_id;

  insert into public.produits_lots_mouvements (
    owner_id, produit_id, lot_id, type, quantite, motif, fait_par
  ) values (
    new.owner_id, new.produit_id, new.id, 'entree', new.quantite_recue,
    'Réception lot ' || new.numero_lot, coalesce(new.recu_par, auth.uid())
  );

  perform public.lots_rafraichir_peremption(new.produit_id);
  return new;
end;
$$;

drop trigger if exists trg_lots_apres_entree on public.produits_lots;
create trigger trg_lots_apres_entree
  after insert on public.produits_lots
  for each row
  execute function public.trg_lots_apres_entree();


-- ============================================================================
--  7. LA VENTE RESPECTE LES LOTS
-- ============================================================================
--  ⚠️ RAPPEL CRITIQUE
--    Le stock de `produits.quantite` est décrémenté par un trigger LEGACY
--    présent en base (hors migrations). On ne le touche pas : ce script ne
--    modifie QUE `produits_lots.quantite_restante` et l'historique des lots.

-- 7.a Blocage AVANT insertion : produit expiré / lots périmés / stock valide
create or replace function public.trg_vente_lots_controle()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_produit record;
  v_dispo   numeric;
  v_a_lots  boolean;
begin
  select p.id, p.nom, p.date_expiration
    into v_produit
    from public.produits p
   where p.id = new.produit_id;

  if v_produit.id is null then
    return new;
  end if;

  -- (1) Règle du module 16 C1, restaurée : un article expiré ne se vend pas.
  if v_produit.date_expiration is not null
     and v_produit.date_expiration < current_date then
    raise exception 'PRODUIT_EXPIRE|% est expiré depuis le % : vente bloquée.',
      v_produit.nom, to_char(v_produit.date_expiration, 'DD/MM/YYYY');
  end if;

  -- (2) Article suivi par lots : seul le stock VALIDE (non périmé, non
  --     retiré) est vendable. Un lot périmé ne « sauve » jamais une vente.
  select exists (
           select 1 from public.produits_lots l
            where l.produit_id = new.produit_id
              and l.retire_le is null
         )
    into v_a_lots;

  if v_a_lots then
    select coalesce(sum(l.quantite_restante), 0)
      into v_dispo
      from public.produits_lots l
     where l.produit_id = new.produit_id
       and l.retire_le is null
       and l.date_peremption >= current_date;

    if v_dispo < new.quantite then
      raise exception
        'STOCK_LOT_INSUFFISANT|Stock valide insuffisant pour % : % vendable(s) hors lots périmés.',
        v_produit.nom, trim(to_char(v_dispo, 'FM999999990.###'));
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_vente_lots_controle on public.ventes;
create trigger trg_vente_lots_controle
  before insert on public.ventes
  for each row
  execute function public.trg_vente_lots_controle();


-- 7.b Consommation FEFO APRÈS insertion (la vente est déjà acceptée)
create or replace function public.trg_vente_lots_fefo()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_lot   record;
  v_reste numeric := new.quantite;
  v_prise numeric;
begin
  if not exists (
    select 1 from public.produits_lots l
     where l.produit_id = new.produit_id
       and l.retire_le is null
  ) then
    return new;
  end if;

  -- FEFO : First Expired, First Out. Verrou par lot : deux ventes simultanées
  -- ne peuvent pas consommer deux fois la même quantité.
  for v_lot in
    select l.id, l.numero_lot, l.quantite_restante
      from public.produits_lots l
     where l.produit_id = new.produit_id
       and l.retire_le is null
       and l.date_peremption >= current_date
       and l.quantite_restante > 0
     order by l.date_peremption asc, l.recu_le asc
     for update
  loop
    exit when v_reste <= 0;

    v_prise := least(v_lot.quantite_restante, v_reste);

    update public.produits_lots l
       set quantite_restante = l.quantite_restante - v_prise
     where l.id = v_lot.id;

    insert into public.produits_lots_mouvements (
      owner_id, produit_id, lot_id, type, quantite, motif, vente_id, fait_par
    ) values (
      new.owner_id, new.produit_id, v_lot.id, 'vente', -v_prise,
      'Vente FEFO lot ' || v_lot.numero_lot, new.id, coalesce(new.seller_id, auth.uid())
    );

    v_reste := v_reste - v_prise;
  end loop;

  perform public.lots_rafraichir_peremption(new.produit_id);
  return new;
end;
$$;

drop trigger if exists trg_vente_lots_fefo on public.ventes;
create trigger trg_vente_lots_fefo
  after insert on public.ventes
  for each row
  execute function public.trg_vente_lots_fefo();


-- ============================================================================
--  8. RPC — RÉCEPTION D'UN LOT
-- ============================================================================

create or replace function public.rpc_lot_recevoir(
  p_produit_id          bigint,
  p_numero_lot          text,
  p_date_peremption     date,
  p_quantite            numeric,
  p_prix_achat_unitaire numeric default null,
  p_fournisseur         text default null,
  p_date_fabrication    date default null,
  p_observations        text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user    uuid := auth.uid();
  v_owner   uuid;
  v_prod    public.produits%rowtype;
  v_lot_id  uuid;
  v_stock   numeric;
  v_date    date;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour enregistrer un lot.';
  end if;

  if not (public.peut('stock', 'creer') or public.est_plateforme()) then
    raise exception 'DROIT_REFUSE|Vous n''avez pas le droit d''enregistrer une entrée de stock.';
  end if;

  v_owner := coalesce(public.mon_proprietaire(), v_user);

  select p.* into v_prod from public.produits p where p.id = p_produit_id;

  if v_prod.id is null then
    raise exception 'ARTICLE_INTROUVABLE|Article introuvable.';
  end if;

  if v_prod.owner_id is distinct from v_owner
     and not public.est_plateforme() then
    raise exception 'HORS_BOUTIQUE|L''article % n''appartient pas à votre boutique.', v_prod.nom;
  end if;

  if p_quantite is null or p_quantite <= 0 then
    raise exception 'QUANTITE_INVALIDE|La quantité reçue doit être supérieure à zéro.';
  end if;

  if btrim(coalesce(p_numero_lot, '')) = '' then
    raise exception 'LOT_OBLIGATOIRE|Le numéro de lot est obligatoire.';
  end if;

  if p_date_peremption is null then
    raise exception 'PEREMPTION_OBLIGATOIRE|La date de péremption est obligatoire.';
  end if;

  if p_date_peremption < current_date then
    raise exception 'PEREMPTION_PASSEE|Ce lot est déjà périmé (%): refusez-le plutôt que de l''entrer en stock.',
      to_char(p_date_peremption, 'DD/MM/YYYY');
  end if;

  if p_date_fabrication is not null and p_date_fabrication > p_date_peremption then
    raise exception 'DATES_INCOHERENTES|La date de fabrication ne peut pas être postérieure à la péremption.';
  end if;

  begin
    insert into public.produits_lots (
      owner_id, produit_id, numero_lot, date_fabrication, date_peremption,
      quantite_recue, quantite_restante, prix_achat_unitaire, fournisseur,
      observations, recu_par
    ) values (
      v_owner, p_produit_id, btrim(p_numero_lot), p_date_fabrication,
      p_date_peremption, p_quantite, p_quantite, p_prix_achat_unitaire,
      nullif(btrim(coalesce(p_fournisseur, '')), ''),
      nullif(btrim(coalesce(p_observations, '')), ''),
      v_user
    )
    returning id into v_lot_id;
  exception
    when unique_violation then
      raise exception 'LOT_DOUBLON|Ce numéro de lot existe déjà pour cet article avec cette date de péremption.';
  end;

  select coalesce(p.quantite, 0), p.date_expiration
    into v_stock, v_date
    from public.produits p
   where p.id = p_produit_id;

  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(), null, 'LOT_RECU', v_user,
    jsonb_build_object(
      'produit_id', p_produit_id,
      'produit', v_prod.nom,
      'lot_id', v_lot_id,
      'numero_lot', btrim(p_numero_lot),
      'quantite', p_quantite,
      'date_peremption', p_date_peremption
    ),
    now()
  );

  return jsonb_build_object(
    'ok', true,
    'lot_id', v_lot_id,
    'stock', v_stock,
    'date_expiration', v_date,
    'quantite_recue', p_quantite
  );
end;
$$;

comment on function public.rpc_lot_recevoir(bigint, text, date, numeric, numeric, text, date, text) is
  'Module 36 (0163) — réception d''un lot : augmente le stock par le lot, horodate et trace. Aucune date de lot existant n''est modifiée.';

revoke all on function public.rpc_lot_recevoir(bigint, text, date, numeric, numeric, text, date, text) from public, anon;
grant execute on function public.rpc_lot_recevoir(bigint, text, date, numeric, numeric, text, date, text) to authenticated;


-- ============================================================================
--  9. RPC — RETRAIT D'UN LOT (CASSE, RAPPEL, PÉREMPTION)
-- ============================================================================

create or replace function public.rpc_lot_retirer(
  p_lot_id uuid,
  p_motif  text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user    uuid := auth.uid();
  v_owner   uuid;
  v_lot     public.produits_lots%rowtype;
  v_nom     text;
  v_motif   text := btrim(coalesce(p_motif, ''));
  v_retire  numeric;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour retirer un lot.';
  end if;

  if not (public.peut('stock', 'modifier') or public.est_plateforme()) then
    raise exception 'DROIT_REFUSE|Vous n''avez pas le droit de retirer du stock.';
  end if;

  if length(v_motif) < 3 then
    raise exception 'MOTIF_OBLIGATOIRE|Indiquez la raison du retrait (casse, rappel, péremption…).';
  end if;

  select l.* into v_lot
    from public.produits_lots l
   where l.id = p_lot_id
   for update;

  if v_lot.id is null then
    raise exception 'LOT_INTROUVABLE|Ce lot est introuvable.';
  end if;

  v_owner := coalesce(public.mon_proprietaire(), v_user);
  if v_lot.owner_id is distinct from v_owner and not public.est_plateforme() then
    raise exception 'HORS_BOUTIQUE|Ce lot n''appartient pas à votre boutique.';
  end if;

  if v_lot.retire_le is not null then
    raise exception 'LOT_DEJA_RETIRE|Ce lot a déjà été retiré du stock.';
  end if;

  v_retire := v_lot.quantite_restante;

  -- Nom de l'article pour le journal d'audit (lecture seule, même portée).
  select p.nom into v_nom from public.produits p where p.id = v_lot.produit_id;

  -- La sortie physique passe par `ajustements` : le trigger du module 9
  -- décrémente le stock, l'opération reste tracée et auditable.
  if v_retire > 0 then
    insert into public.ajustements (
      produit_id, quantite, raison, date, owner_id
    ) values (
      v_lot.produit_id, -v_retire,
      'Retrait lot ' || v_lot.numero_lot || ' — ' || v_motif,
      now(), v_lot.owner_id
    );
  end if;

  update public.produits_lots l
     set quantite_restante = 0,
         retire_le         = now(),
         motif_retrait     = v_motif
   where l.id = p_lot_id;

  insert into public.produits_lots_mouvements (
    owner_id, produit_id, lot_id, type, quantite, motif, fait_par
  ) values (
    v_lot.owner_id, v_lot.produit_id, v_lot.id, 'retrait', -v_retire,
    v_motif, v_user
  );

  perform public.lots_rafraichir_peremption(v_lot.produit_id);

  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(), null, 'LOT_RETIRE', v_user,
    jsonb_build_object(
      'produit_id', v_lot.produit_id,
      'produit', v_nom,
      'lot_id', v_lot.id,
      'numero_lot', v_lot.numero_lot,
      'quantite_retiree', v_retire,
      'motif', v_motif
    ),
    now()
  );

  return jsonb_build_object(
    'ok', true,
    'quantite_retiree', v_retire,
    'stock', (select coalesce(quantite, 0) from public.produits where id = v_lot.produit_id)
  );
end;
$$;

comment on function public.rpc_lot_retirer(uuid, text) is
  'Module 36 (0163) — retire un lot du stock (quantité restante → 0), avec motif obligatoire, ajustement tracé et historique.';

revoke all on function public.rpc_lot_retirer(uuid, text) from public, anon;
grant execute on function public.rpc_lot_retirer(uuid, text) to authenticated;


-- ============================================================================
-- 10. RPC — LECTURE DES LOTS D'UN ARTICLE
-- ============================================================================

create or replace function public.rpc_lots_lister(
  p_produit_id   bigint,
  p_jours_alarme integer default 30
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_user  uuid := auth.uid();
  v_owner uuid;
  v_prod  public.produits%rowtype;
  v_jours integer := greatest(1, least(coalesce(p_jours_alarme, 30), 365));
  v_lots  jsonb;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour consulter les lots.';
  end if;

  if not (public.peut('stock', 'voir') or public.est_plateforme()) then
    raise exception 'DROIT_REFUSE|Vous n''avez pas le droit de consulter le stock.';
  end if;

  v_owner := coalesce(public.mon_proprietaire(), v_user);

  select p.* into v_prod from public.produits p where p.id = p_produit_id;

  if v_prod.id is null then
    raise exception 'ARTICLE_INTROUVABLE|Article introuvable.';
  end if;

  if v_prod.owner_id is distinct from v_owner and not public.est_plateforme() then
    raise exception 'HORS_BOUTIQUE|Cet article n''appartient pas à votre boutique.';
  end if;

  select coalesce(jsonb_agg(ordre), '[]'::jsonb)
    into v_lots
    from (
      select jsonb_build_object(
               'id', l.id,
               'produit_id', l.produit_id,
               'numero_lot', l.numero_lot,
               'date_fabrication', l.date_fabrication,
               'date_peremption', l.date_peremption,
               'quantite_recue', l.quantite_recue,
               'quantite_restante', l.quantite_restante,
               'prix_achat_unitaire', l.prix_achat_unitaire,
               'fournisseur', l.fournisseur,
               'observations', l.observations,
               'recu_le', l.recu_le,
               'retire_le', l.retire_le,
               'motif_retrait', l.motif_retrait,
               'jours_restants', (l.date_peremption - current_date),
               'statut', case
                 when l.retire_le is not null then 'retire'
                 when l.date_peremption < current_date then 'perime'
                 when l.date_peremption <= current_date + v_jours then 'proche'
                 else 'valide'
               end,
               'vendable', (l.retire_le is null
                            and l.date_peremption >= current_date
                            and l.quantite_restante > 0)
             ) as ordre
        from public.produits_lots l
       where l.produit_id = p_produit_id
       order by l.date_peremption asc, l.recu_le asc
    ) s;

  return jsonb_build_object(
    'ok', true,
    'produit_id', p_produit_id,
    'produit', v_prod.nom,
    'stock', coalesce(v_prod.quantite, 0),
    'date_expiration', v_prod.date_expiration,
    'total_lots_restants',
      (select coalesce(sum(l.quantite_restante), 0)
         from public.produits_lots l
        where l.produit_id = p_produit_id
          and l.retire_le is null),
    'total_vendable',
      (select coalesce(sum(l.quantite_restante), 0)
         from public.produits_lots l
        where l.produit_id = p_produit_id
          and l.retire_le is null
          and l.date_peremption >= current_date),
    'lots', v_lots
  );
end;
$$;

comment on function public.rpc_lots_lister(bigint, integer) is
  'Module 36 (0163) — lots d''un article, ordonnés FEFO, avec statut (valide / proche / périmé / retiré) et total vendable.';

revoke all on function public.rpc_lots_lister(bigint, integer) from public, anon;
grant execute on function public.rpc_lots_lister(bigint, integer) to authenticated;


-- ============================================================================
-- 11. RPC — ALERTES DE PÉREMPTION PAR LOT
-- ============================================================================

create or replace function public.rpc_lots_alertes(
  p_jours integer default 30
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_user  uuid := auth.uid();
  v_owner uuid;
  v_jours integer := greatest(1, least(coalesce(p_jours, 30), 365));
  v_lignes jsonb;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour consulter les péremptions.';
  end if;

  if not (public.peut('stock', 'voir') or public.est_plateforme()) then
    raise exception 'DROIT_REFUSE|Vous n''avez pas le droit de consulter le stock.';
  end if;

  v_owner := coalesce(public.mon_proprietaire(), v_user);

  select coalesce(jsonb_agg(ordre), '[]'::jsonb)
    into v_lignes
    from (
      select jsonb_build_object(
               'lot_id', l.id,
               'produit_id', l.produit_id,
               'produit', p.nom,
               'numero_lot', l.numero_lot,
               'date_peremption', l.date_peremption,
               'quantite_restante', l.quantite_restante,
               'jours_restants', (l.date_peremption - current_date),
               'statut', case
                 when l.date_peremption < current_date then 'perime'
                 else 'proche'
               end,
               'valeur_achat',
                 round(coalesce(l.quantite_restante, 0)
                       * coalesce(l.prix_achat_unitaire, 0), 2)
             ) as ordre
        from public.produits_lots l
        join public.produits p on p.id = l.produit_id
       where l.owner_id = v_owner
         and l.retire_le is null
         and l.quantite_restante > 0
         and l.date_peremption <= current_date + v_jours
       order by l.date_peremption asc, p.nom asc
    ) s;

  return jsonb_build_object(
    'ok', true,
    'jours_alarme', v_jours,
    'alertes', v_lignes
  );
end;
$$;

comment on function public.rpc_lots_alertes(integer) is
  'Module 36 (0163) — lots périmés ou proches de la péremption (stock restant > 0), avec valeur d''achat perdue.';

revoke all on function public.rpc_lots_alertes(integer) from public, anon;
grant execute on function public.rpc_lots_alertes(integer) to authenticated;


-- ============================================================================
-- 12. RPC — CONTRÔLE DE COHÉRENCE (DIAGNOSTIC)
-- ============================================================================
--  Répond à la question : « le stock affiché de l'article correspond-il à la
--  somme de ses lots ? » Un écart apparaît si du stock a été saisi avant la
--  mise en place des lots.

create or replace function public.rpc_lots_ecarts()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_user  uuid := auth.uid();
  v_owner uuid;
  v_lignes jsonb;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour contrôler les lots.';
  end if;

  if not (public.peut('stock', 'voir') or public.est_plateforme()) then
    raise exception 'DROIT_REFUSE|Vous n''avez pas le droit de consulter le stock.';
  end if;

  v_owner := coalesce(public.mon_proprietaire(), v_user);

  select coalesce(jsonb_agg(ordre), '[]'::jsonb)
    into v_lignes
    from (
      select jsonb_build_object(
               'produit_id', p.id,
               'produit', p.nom,
               'stock_fiche', coalesce(p.quantite, 0),
               'stock_lots', coalesce(s.total, 0),
               -- ⚠️ `produits.quantite` est un REAL : sans ce cast, la
               -- soustraction est calculée en double précision et
               -- `round(double, int)` n'existe pas en PostgreSQL
               -- (« function round(double precision, integer) does not exist »).
               'ecart', round(
                 (coalesce(p.quantite, 0) - coalesce(s.total, 0))::numeric,
                 3)
             ) as ordre
        from public.produits p
        left join (
          select l.produit_id, sum(l.quantite_restante) as total
            from public.produits_lots l
           where l.retire_le is null
           group by l.produit_id
        ) s on s.produit_id = p.id
       where p.owner_id = v_owner
         and s.produit_id is not null
         and abs((coalesce(p.quantite, 0) - coalesce(s.total, 0))::numeric)
             > 0.0005
       order by p.nom asc
    ) s;

  return jsonb_build_object('ok', true, 'ecarts', v_lignes);
end;
$$;

comment on function public.rpc_lots_ecarts() is
  'Module 36 (0163) — diagnostic : articles dont le stock de la fiche diffère de la somme des lots.';

revoke all on function public.rpc_lots_ecarts() from public, anon;
grant execute on function public.rpc_lots_ecarts() to authenticated;


-- ============================================================================
-- 13. VERDICT (l'éditeur SQL n'affiche que le dernier résultat)
-- ============================================================================

select 'Module 36 lots — ' ||
       case
         when to_regclass('public.produits_lots') is not null
          and to_regclass('public.produits_lots_mouvements') is not null
          and exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                       where p.proname = 'rpc_lot_recevoir' and n.nspname = 'public')
          and exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                       where p.proname = 'trg_vente_lots_fefo' and n.nspname = 'public')
          and exists (select 1 from pg_trigger t join pg_class c on c.oid = t.tgrelid
                       where t.tgname = 'trg_vente_lots_fefo' and c.relname = 'ventes')
         then 'OK (tables, RPC et triggers en place)'
         else 'INCOMPLET — relisez les messages d''erreur ci-dessus'
       end as verdict;
