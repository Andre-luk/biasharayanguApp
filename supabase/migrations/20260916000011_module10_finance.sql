-- ============================================================================
--  biashara_yangu — MODULE 10 : FINANCE DE L'ENTREPRISE (caisse, dépenses,
--  dettes clients, rapports)
--
--  ⚠️ À NE PAS CONFONDRE avec la finance de la PLATEFORME La Perle
--     (`abonnements`, `paiements_abonnements_laperle`) : ce module ne touche
--     à AUCUNE table de la plateforme. Il outille uniquement la boutique :
--
--    1. `public.depenses`        — + `categorie` (rapport « dépenses par
--       catégorie ») ; les dépenses sont des SORTIES de caisse.
--    2. `public.dettes`          — + `vente_uuid` (lien avec les ventes du
--       Module 8) et `date_echeance` (suivi des relances).
--    3. `public.paiements_dette` — + `mode_paiement` ; `date_paiement` est
--       NORMALISÉE en `timestamptz` (les autres dates du projet le sont).
--    4. TRIGGER de statut : à chaque paiement (insert/update/delete, y
--       compris ceux de l'ancienne caisse synchronisée), `montant_paye` et
--       `statut` de la dette sont RECALCULÉS depuis les paiements.
--    5. `public.clotures_caisse` — snapshots de clôture de caisse (fond
--       initial, théorique, compté, écart, commentaire).
--    6. 12 RPC `security definer` : dépenses, caisse (résumé/journal/clôture),
--       dettes (liste/creation/paiement/relance), rapports financiers.
--    7. RLS : la finance d'une entreprise n'est visible QUE par ses membres.
--       Le personnel de la plateforme (Super Admin, Gestionnaire des comptes,
--       Finance La Perle, Support) n'y a AUCUN accès — sauf le Super Admin
--       explicitement autorisé par le réglage `app_settings`
--       `finance_entreprise_plateforme` = {"super_admin_autorise": true}
--       (défaut : false = refus).
--
--  ⚠️ LA CAISSE EST CALCULÉE EN TEMPS RÉEL (pas de doublons) :
--     encaissements = `caisse` (ventes Modules 8) ∪ ventes historiques
--     (ancienne caisse, `numero_vente` NULL, mode ≠ « dette ») ∪
--     `paiements_dette` ; décaissements = `depenses`.
--     Le solde est donc SUM(entrées) − SUM(sorties), recalculé à chaque appel.
--     Les ventes à crédit (mode « dette ») ne sont PAS des encaissements :
--     l'argent entre lors des paiements de dette.
--
--  ÉTAT DE LA BASE (sondé le 2026-09-16) :
--    • `depenses`(owner_id, motif, montant real, date timestamptz, is_synced,
--      supabase_id), `dettes`(client_id bigint, vente_id bigint, statut text,
--      date_creation timestamptz…), `paiements_dette`(dette_id bigint,
--      date_paiement timestamp SANS fuseau …) existent déjà (legacy) ;
--    • `caisse` a été créée par le Module 8 (encaissements seuls) ;
--    • `produits.prix_achat` existe → le coût des marchandises est calculable ;
--    • l'ancienne caisse synchronisera ENCORE directement ces tables : les
--      policies gardent l'écriture de ses lignes (chacun chez soi).
--
--  OÙ L'EXÉCUTER
--    Supabase Dashboard → SQL Editor → New query → coller → Run
--
--  PRÉ-REQUIS
--    Modules 4 (peut/est_plateforme/mon_role), 5 (mon_proprietaire) et
--    8 (`caisse`) exécutés.
--
--  ⚠️ IDEMPOTENT : peut être relancé sans dupliquer ni détruire de données.
--     Les policies des tables finance sont REMPLACÉES (retirées une à une,
--     quel que soit leur nom) : plus rien de perméable ne subsiste.
-- ============================================================================


select set_config('search_path', 'public, extensions', true);

-- Contrôle préalable : Modules 4, 5 et 8 en place.
do $$
begin
  if not exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where p.proname = 'peut' and n.nspname = 'public'
  ) or not exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where p.proname = 'est_plateforme' and n.nspname = 'public'
  ) then
    raise exception
      'Module 4 absent : exécutez d''abord 20260916000006_module4_permissions.sql.';
  end if;

  if not exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where p.proname = 'mon_proprietaire' and n.nspname = 'public'
  ) then
    raise exception
      'Module 5 absent : exécutez d''abord 20260916000008_module5_articles.sql.';
  end if;

  if not exists (
    select 1 from information_schema.tables
     where table_schema = 'public' and table_name = 'caisse'
  ) then
    raise exception
      'Module 8 absent : exécutez d''abord 20260916000009_module8_ventes.sql.';
  end if;
end $$;


-- ============================================================================
--  1. COLONNES COMPLÉMENTAIRES & INDEX
-- ============================================================================

-- 1.a Catégorie de dépense (rapport « Dépenses par catégorie ») --------------
alter table public.depenses
  add column if not exists categorie text not null default 'autre';

comment on column public.depenses.categorie is
  'Catégorie de la dépense (loyer, transport, salaires…). « autre » par défaut.';

-- 1.b Lien dette ↔ vente du Module 8 + échéance ------------------------------
alter table public.dettes
  add column if not exists vente_uuid uuid;
alter table public.dettes
  add column if not exists date_echeance date;

comment on column public.dettes.vente_uuid is
  'Vente (Module 8) à l''origine de la dette, si elle a été créée lors d''une vente à crédit.';
comment on column public.dettes.date_echeance is
  'Date d''échéance souhaitée du règlement (facultative, pour les relances).';

-- 1.c Mode de paiement du règlement de dette --------------------------------
alter table public.paiements_dette
  add column if not exists mode_paiement text not null default 'especes';

comment on column public.paiements_dette.mode_paiement is
  'Mode de paiement du règlement : especes / mobile_money / carte / virement / autre.';

-- 1.d Index d'historique -------------------------------------------------------
create index if not exists idx_m10_depenses_owner_date
  on public.depenses (owner_id, date desc);
create index if not exists idx_m10_dettes_owner_date
  on public.dettes (owner_id, date_creation desc);
create index if not exists idx_m10_dettes_owner_statut
  on public.dettes (owner_id, statut);
create index if not exists idx_m10_paiements_dette_dette
  on public.paiements_dette (dette_id);
create index if not exists idx_m10_paiements_dette_owner_date
  on public.paiements_dette (owner_id, date_paiement desc);


-- ============================================================================
--  2. NORMALISATION DES TYPES DE DATES (idempotent)
-- ============================================================================
--  `paiements_dette.date_paiement` est un `timestamp` SANS fuseau (legacy).
--  On l'aligne sur le reste du projet (`timestamptz`) : l'heure stockée est
--  supposée en UTC. Le bloc ne fait rien si la colonne est déjà correcte.

do $$
declare
  v_type text;
begin
  select c.data_type into v_type
    from information_schema.columns c
   where c.table_schema = 'public'
     and c.table_name = 'paiements_dette'
     and c.column_name = 'date_paiement';

  if v_type in ('timestamp without time zone', 'text') then
    execute 'alter table public.paiements_dette '
         || 'alter column date_paiement type timestamptz '
         || 'using (date_paiement::text)::timestamptz';
    raise notice 'paiements_dette.date_paiement converti en timestamptz (hypothèse UTC).';
  end if;
end $$;


-- ============================================================================
--  3. `public.clotures_caisse` — SNAPSHOTS DE CLÔTURE
-- ============================================================================
--  Une clôture par boutique et par jour (ré-exécutable le même jour : la
--  ligne est mise à jour). Les montants sont FIGÉS au moment de la clôture :
--  c'est la trace « comptable » qui permet de comparer plus tard.

create table if not exists public.clotures_caisse (
  id                  bigint generated by default as identity primary key,
  owner_id            uuid not null,
  date_cloture        date not null default current_date,
  fond_initial        numeric not null default 0,
  espece_comptee      numeric,
  encaissements_total numeric not null default 0,
  decaissements_total numeric not null default 0,
  solde_theorique     numeric not null default 0,
  ecart               numeric,
  details             jsonb not null default '{}'::jsonb,
  commentaire         text,
  clos_par            uuid,
  created_at          timestamptz not null default now(),
  constraint clotures_caisse_owner_jour unique (owner_id, date_cloture)
);

comment on table public.clotures_caisse is
  'Clôtures de caisse quotidiennes : montants théoriques figés, espèce comptée et écart.';

alter table public.clotures_caisse enable row level security;


-- ============================================================================
--  4. CONTRÔLE D'ACCÈS — LA FINANCE APPARTIENT À L'ENTREPRISE
-- ============================================================================

-- 4.a Réglage : Super Admin explicitement autorisé ? (défaut : NON) ----------
--  GESTIONNAIRE_COMPTES, FINANCE_LAPERLE et SUPPORT restent bloqués quoi
--  qu'il arrive : ce réglage ne concerne que le SUPER_ADMIN.
create or replace function public.finance_super_admin_autorise()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
      from public.app_settings s
     where s.key = 'finance_entreprise_plateforme'
       and s.value @> jsonb_build_object('super_admin_autorise', true)
  );
$$;

comment on function public.finance_super_admin_autorise() is
  'Vrai si le Super Admin est explicitement autorisé à voir la finance des entreprises (app_settings).';

-- Création du réglage s'il n'existe pas (refus par défaut).
do $$
begin
  if exists (
    select 1 from information_schema.tables
     where table_schema = 'public' and table_name = 'app_settings'
  ) then
    insert into public.app_settings (key, value)
    select 'finance_entreprise_plateforme',
           jsonb_build_object('super_admin_autorise', false)
     where not exists (
       select 1 from public.app_settings where key = 'finance_entreprise_plateforme'
     );
  else
    raise notice 'app_settings absente : le réglage finance_entreprise_plateforme ne sera pas créé.';
  end if;
end $$;

-- 4.b Le personnel plateforme (sauf Super Admin autorisé) est-il bloqué ? ----
create or replace function public.finance_role_plateforme_bloque()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.est_plateforme()
     and not (
       public.mon_role() = 'SUPER_ADMIN'
       and public.finance_super_admin_autorise()
     );
$$;

comment on function public.finance_role_plateforme_bloque() is
  'Vrai pour les rôles plateforme sans droit sur la finance entreprise (tous sauf Super Admin autorisé).';

-- 4.c Un utilisateur a-t-il accès à la finance de `p_owner` ? ----------------
--  • le propriétaire lui-même ;
--  • les membres de son entreprise (`mon_proprietaire()` = son patron) ;
--  • le Super Admin UNIQUEMENT si le réglage l'autorise explicitement.
--  Les RPC vérifient EN PLUS l'action précise (`peut(page, action)`).
create or replace function public.acces_finance_entreprise(p_owner uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select p_owner is not null
     and (
       auth.uid() = p_owner
       or public.mon_proprietaire() = p_owner
       or (
         public.mon_role() = 'SUPER_ADMIN'
         and public.finance_super_admin_autorise()
       )
     );
$$;

comment on function public.acces_finance_entreprise(uuid) is
  'Vrai si la session courante peut accéder à la finance de la boutique p_owner (membres uniquement).';


-- ============================================================================
--  5. STATUT DES DETTES — RECALCULÉ PAR LA BASE À CHAQUE PAIEMENT
-- ============================================================================
--  `montant_paye` et `statut` ne sont PLUS saisis : ils découlent des
--  paiements enregistrés (`non_paye` → `partiel` → `paye`). Le recalcul est
--  un REMPLACEMENT (SUM des paiements), pas une addition : il reste correct
--  même si l'ancienne caisse a écrit un `montant_paye` de son côté.

create or replace function public.recalculer_dette_paiement(p_dette_id bigint)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_total  numeric;
  v_paye   numeric;
  v_statut text;
begin
  if p_dette_id is null then
    return;
  end if;

  select d.montant_total
    into v_total
    from public.dettes d
   where d.id = p_dette_id
     for update;

  if not found then
    return; -- dette supprimée : rien à recalculer.
  end if;

  select coalesce(sum(p.montant), 0)
    into v_paye
    from public.paiements_dette p
   where p.dette_id = p_dette_id;

  v_statut := case
    when coalesce(v_total, 0) <= 0 then 'paye'
    when v_paye >= v_total        then 'paye'
    when v_paye > 0               then 'partiel'
    else 'non_paye'
  end;

  update public.dettes
     set montant_paye = v_paye,
         statut       = v_statut
   where id = p_dette_id;
end;
$$;

comment on function public.recalculer_dette_paiement(bigint) is
  'Recalcule montant_paye et statut d''une dette à partir de ses paiements (idempotent).';

create or replace function public.trg_paiements_dette_recalcul()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    perform public.recalculer_dette_paiement(old.dette_id);
    return old;
  end if;
  perform public.recalculer_dette_paiement(new.dette_id);
  return new;
end;
$$;

drop trigger if exists trg_paiements_dette_recalcul on public.paiements_dette;
create trigger trg_paiements_dette_recalcul
  after insert or update or delete on public.paiements_dette
  for each row
  execute function public.trg_paiements_dette_recalcul();


-- ============================================================================
--  6. OUTIL INTERNE — STATISTIQUES D'UNE PÉRIODE
-- ============================================================================
--  Chiffre d'affaires / coût marchandises / dépenses / bénéfice net d'une
--  boutique entre deux dates (bornes incluses, en UTC comme le Module 8).
--  Utilisé par le tableau de bord et les rapports ; jamais appelé par l'app.

create or replace function public.finance_stats_periode(
  p_owner uuid,
  p_debut date,
  p_fin   date
)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with bornes as (
    select p_debut::timestamptz as d0, (p_fin + 1)::timestamptz as d1
  ),
  ventes_agg as (
    select coalesce(sum(v.prix), 0) as ca,
           coalesce(sum(v.quantite * coalesce(pr.prix_achat, 0)), 0) as cout,
           count(distinct coalesce(v.vente_uuid::text, 'L' || v.id)) as nb_ventes
      from public.ventes v
      left join public.produits pr on pr.id = v.produit_id
     where v.owner_id = p_owner
       and v.date >= (select d0 from bornes)
       and v.date <  (select d1 from bornes)
  ),
  depenses_agg as (
    select coalesce(sum(dp.montant), 0) as total,
           count(*) as nb
      from public.depenses dp
     where dp.owner_id = p_owner
       and dp.date >= (select d0 from bornes)
       and dp.date <  (select d1 from bornes)
  )
  select jsonb_build_object(
    'debut',            p_debut,
    'fin',              p_fin,
    'chiffre_affaires', va.ca,
    'cout_marchandises', va.cout,
    'marge_brute',      va.ca - va.cout,
    'depenses',         da.total,
    'benefice_net',     va.ca - va.cout - da.total,
    'nb_ventes',        va.nb_ventes,
    'nb_depenses',      da.nb
  )
  from ventes_agg va, depenses_agg da;
$$;

comment on function public.finance_stats_periode(uuid, date, date) is
  'Statistiques financières d''une boutique sur une période : CA, coût, dépenses, bénéfice net.';


-- ============================================================================
--  7. RPC DÉPENSES
-- ============================================================================

-- 7.a `rpc_depense_creer` ------------------------------------------------------
--  Droit `depenses/creer`. La dépense est une SORTIE de caisse (mode espèces :
--  le justificatif est le motif ; les modes de sortie ne sont pas gérés).
--  Codes : SESSION_ABSENTE | ACCES_REFUSE | DROIT_REFUSE | MOTIF_OBLIGATOIRE |
--          MONTANT_INVALIDE | DATE_INVALIDE

create or replace function public.rpc_depense_creer(
  p_motif     text,
  p_montant   numeric,
  p_date      timestamptz default null,
  p_categorie text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user   uuid := auth.uid();
  v_owner  uuid;
  v_motif  text := btrim(coalesce(p_motif, ''));
  v_cat    text := lower(btrim(coalesce(p_categorie, '')));
  v_date   timestamptz;
  v_depense record;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour enregistrer une dépense.';
  end if;

  if public.finance_role_plateforme_bloque() then
    raise exception 'ACCES_REFUSE|La finance d''une entreprise est privée : le personnel de la plateforme n''y a pas accès.';
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  if not public.acces_finance_entreprise(v_owner) then
    raise exception 'ACCES_REFUSE|Vous n''êtes pas membre de cette entreprise.';
  end if;

  if not public.peut('depenses', 'creer') then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas d''enregistrer une dépense.';
  end if;

  if length(v_motif) < 2 then
    raise exception 'MOTIF_OBLIGATOIRE|Indiquez le motif de la dépense (2 caractères minimum).';
  end if;

  if p_montant is null or p_montant <= 0 then
    raise exception 'MONTANT_INVALIDE|Le montant de la dépense doit être supérieur à zéro.';
  end if;

  v_date := coalesce(p_date, now());
  if v_date > now() + interval '1 day' then
    raise exception 'DATE_INVALIDE|La date de la dépense ne peut pas être dans le futur.';
  end if;

  if v_cat = '' then
    v_cat := 'autre';
  end if;

  insert into public.depenses (
    owner_id, motif, montant, date, categorie, is_synced
  ) values (
    v_owner, v_motif, p_montant, v_date, v_cat, 1
  )
  returning id, motif, montant, date, categorie into v_depense;

  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(), null, 'DEPENSE', v_user,
    jsonb_build_object(
      'depense_id', v_depense.id,
      'motif',      v_motif,
      'montant',    p_montant,
      'categorie',  v_cat,
      'date',       v_date,
      'boutique',   v_owner
    ),
    now()
  );

  return jsonb_build_object(
    'depense_id', v_depense.id,
    'motif',      v_depense.motif,
    'montant',    v_depense.montant,
    'categorie',  v_depense.categorie,
    'date',       v_depense.date
  );
end;
$$;

comment on function public.rpc_depense_creer(text, numeric, timestamptz, text) is
  'Enregistre une dépense (sortie de caisse), tracée dans journal_audit.';

-- 7.b `rpc_depense_supprimer` --------------------------------------------------
--  Droit `depenses/supprimer`. Suppression réservée aux erreurs de saisie :
--  l''opération est journalisée.
--  Codes : SESSION_ABSENTE | ACCES_REFUSE | DROIT_REFUSE | DEPENSE_INTROUVABLE

create or replace function public.rpc_depense_supprimer(p_depense_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user    uuid := auth.uid();
  v_owner   uuid;
  v_depense record;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour supprimer une dépense.';
  end if;

  if public.finance_role_plateforme_bloque() then
    raise exception 'ACCES_REFUSE|La finance d''une entreprise est privée : le personnel de la plateforme n''y a pas accès.';
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  if not public.acces_finance_entreprise(v_owner) then
    raise exception 'ACCES_REFUSE|Vous n''êtes pas membre de cette entreprise.';
  end if;

  if not public.peut('depenses', 'supprimer') then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de supprimer une dépense.';
  end if;

  select d.id, d.owner_id, d.motif, d.montant, d.date, d.categorie
    into v_depense
    from public.depenses d
   where d.id = p_depense_id
     for update;

  if not found then
    raise exception 'DEPENSE_INTROUVABLE|Dépense n° % introuvable : elle a peut-être déjà été supprimée.', p_depense_id;
  end if;

  if v_depense.owner_id is distinct from v_owner then
    raise exception 'ACCES_REFUSE|Cette dépense n''appartient pas à votre entreprise.';
  end if;

  delete from public.depenses where id = p_depense_id;

  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(), null, 'DEPENSE', v_user,
    jsonb_build_object(
      'depense_id', v_depense.id,
      'motif',      v_depense.motif,
      'montant',    v_depense.montant,
      'categorie',  v_depense.categorie,
      'suppression', true,
      'boutique',   v_owner
    ),
    now()
  );

  return jsonb_build_object(
    'depense_id', v_depense.id,
    'motif',      v_depense.motif,
    'montant',    v_depense.montant,
    'supprimee',  true
  );
end;
$$;

comment on function public.rpc_depense_supprimer(bigint) is
  'Supprime une dépense (erreur de saisie), tracée dans journal_audit.';

-- 7.c `rpc_depenses_liste` -----------------------------------------------------
--  Droit `depenses/voir`. Liste filtrable + totaux + catégories connues
--  (pour le filtre de l'écran).
--  Codes : SESSION_ABSENTE | ACCES_REFUSE | DROIT_REFUSE | PERIODE_INVALIDE

create or replace function public.rpc_depenses_liste(
  p_debut     date default null,
  p_fin       date default null,
  p_categorie text default null,
  p_limit     integer default 200
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user    uuid := auth.uid();
  v_owner   uuid;
  v_cat     text := nullif(lower(btrim(coalesce(p_categorie, ''))), '');
  v_limit   integer := least(greatest(coalesce(p_limit, 200), 1), 500);
  v_lignes  jsonb := '[]'::jsonb;
  v_totaux  jsonb := '{}'::jsonb;
  v_cats    jsonb := '[]'::jsonb;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour consulter les dépenses.';
  end if;

  if public.finance_role_plateforme_bloque() then
    raise exception 'ACCES_REFUSE|La finance d''une entreprise est privée : le personnel de la plateforme n''y a pas accès.';
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  if not public.acces_finance_entreprise(v_owner) then
    raise exception 'ACCES_REFUSE|Vous n''êtes pas membre de cette entreprise.';
  end if;

  if not public.peut('depenses', 'voir') then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de consulter les dépenses.';
  end if;

  if p_debut is not null and p_fin is not null and p_debut > p_fin then
    raise exception 'PERIODE_INVALIDE|La date de début doit précéder la date de fin.';
  end if;

  select coalesce(jsonb_agg(x order by x->>'date' desc), '[]'::jsonb)
    into v_lignes
    from (
      select jsonb_build_object(
               'depense_id', d.id,
               'motif',      d.motif,
               'montant',    d.montant,
               'categorie',  d.categorie,
               'date',       d.date
             ) as x
        from public.depenses d
       where d.owner_id = v_owner
         and (p_debut is null or d.date >= p_debut::timestamptz)
         and (p_fin   is null or d.date <  (p_fin + 1)::timestamptz)
         and (v_cat   is null or lower(coalesce(d.categorie, 'autre')) = v_cat)
       order by d.date desc
       limit v_limit
    ) s;

  select jsonb_build_object(
           'nb',    count(*),
           'total', coalesce(sum(d.montant), 0)
         )
    into v_totaux
    from public.depenses d
   where d.owner_id = v_owner
     and (p_debut is null or d.date >= p_debut::timestamptz)
     and (p_fin   is null or d.date <  (p_fin + 1)::timestamptz)
     and (v_cat   is null or lower(coalesce(d.categorie, 'autre')) = v_cat);

  select coalesce(jsonb_agg(distinct lower(coalesce(d.categorie, 'autre'))), '[]'::jsonb)
    into v_cats
    from public.depenses d
   where d.owner_id = v_owner;

  return jsonb_build_object(
    'debut',      p_debut,
    'fin',        p_fin,
    'categorie',  v_cat,
    'lignes',     v_lignes,
    'totaux',     v_totaux,
    'categories', v_cats
  );
end;
$$;

comment on function public.rpc_depenses_liste(date, date, text, integer) is
  'Liste les dépenses d''une période avec totaux et catégories (écran Dépenses).';


-- ============================================================================
--  8. RPC CAISSE
-- ============================================================================

-- 8.a `rpc_caisse_resume` ------------------------------------------------------
--  Droit `caisse/voir` (ou `finance/voir`). Renvoie, recalculés en temps réel :
--    • le solde global de la caisse (entrées − sorties, tout l'historique) ;
--    • les encaissements / décaissements / le net du JOUR demandé ;
--    • le détail par mode de paiement du jour ;
--    • la dernière clôture de caisse enregistrée.
--  ⚠️ Les DÉPENSES (donc le solde et les décaissements) ne sont visibles que
--     si le rôle possède `depenses/voir` : un vendeur ne voit que ses
--     encaissements du jour (`depenses_visibles` = false, solde = null).
--  Codes : SESSION_ABSENTE | ACCES_REFUSE | DROIT_REFUSE | DATE_INVALIDE

create or replace function public.rpc_caisse_resume(p_date date default current_date)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user      uuid := auth.uid();
  v_owner     uuid;
  v_jour      date := coalesce(p_date, current_date);
  v_d0        timestamptz;
  v_d1        timestamptz;
  v_visibles  boolean;
  v_enc_ventes numeric := 0;
  v_enc_dettes numeric := 0;
  v_dec_jour   numeric := 0;
  v_nb_ventes  integer := 0;
  v_nb_pm      integer := 0;
  v_nb_dep     integer := 0;
  v_solde      numeric;
  v_enc_tot    numeric;
  v_leg_tot    numeric;
  v_pm_tot     numeric;
  v_dec_tot    numeric;
  v_par_mode   jsonb := '{}'::jsonb;
  v_derniere   jsonb;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour consulter la caisse.';
  end if;

  if public.finance_role_plateforme_bloque() then
    raise exception 'ACCES_REFUSE|La finance d''une entreprise est privée : le personnel de la plateforme n''y a pas accès.';
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  if not public.acces_finance_entreprise(v_owner) then
    raise exception 'ACCES_REFUSE|Vous n''êtes pas membre de cette entreprise.';
  end if;

  if not (public.peut('caisse', 'voir') or public.peut('finance', 'voir')) then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de consulter la caisse.';
  end if;

  if v_jour > current_date + 1 then
    raise exception 'DATE_INVALIDE|La date demandée ne peut pas être dans un futur lointain.';
  end if;

  v_d0 := v_jour::timestamptz;
  v_d1 := (v_jour + 1)::timestamptz;
  v_visibles := public.peut('depenses', 'voir');

  -- Encaissements du jour : ventes encaissées (Module 8) --------------------
  select coalesce(sum(c.montant_total), 0), count(*)
    into v_enc_ventes, v_nb_ventes
    from public.caisse c
   where c.owner_id = v_owner
     and c.date >= v_d0 and c.date < v_d1;

  -- + ventes historiques de l'ancienne caisse (sans numéro, hors crédit) ----
  select v_enc_ventes + coalesce(sum(v.prix), 0),
         v_nb_ventes + count(*)
    into v_enc_ventes, v_nb_ventes
    from public.ventes v
   where v.owner_id = v_owner
     and v.numero_vente is null
     and lower(btrim(coalesce(v.mode_paiement, 'especes'))) <> 'dette'
     and v.date >= v_d0 and v.date < v_d1;

  -- + règlements de dettes du jour ------------------------------------------
  select coalesce(sum(p.montant), 0), count(*)
    into v_enc_dettes, v_nb_pm
    from public.paiements_dette p
    join public.dettes d on d.id = p.dette_id
   where coalesce(p.owner_id, d.owner_id) = v_owner
     and p.date_paiement >= v_d0 and p.date_paiement < v_d1;

  -- Décaissements du jour (visibles seulement avec depenses/voir) -----------
  if v_visibles then
    select coalesce(sum(dp.montant), 0), count(*)
      into v_dec_jour, v_nb_dep
      from public.depenses dp
     where dp.owner_id = v_owner
       and dp.date >= v_d0 and dp.date < v_d1;
  end if;

  -- Détail du jour par mode de paiement --------------------------------------
  select coalesce(jsonb_object_agg(mode, jsonb_build_object(
           'encaissements', ent,
           'decaissements', sor
         )), '{}'::jsonb)
    into v_par_mode
    from (
      select mode,
             coalesce(sum(case when sens = 'entree' then m end), 0) as ent,
             coalesce(sum(case when sens = 'sortie' then m end), 0) as sor
        from (
          select lower(btrim(coalesce(c.mode_paiement, 'especes'))) as mode,
                 'entree'::text as sens, c.montant_total as m
            from public.caisse c
           where c.owner_id = v_owner
             and c.date >= v_d0 and c.date < v_d1
          union all
          select lower(btrim(coalesce(v.mode_paiement, 'especes'))),
                 'entree', v.prix
            from public.ventes v
           where v.owner_id = v_owner
             and v.numero_vente is null
             and lower(btrim(coalesce(v.mode_paiement, 'especes'))) <> 'dette'
             and v.date >= v_d0 and v.date < v_d1
          union all
          select lower(btrim(coalesce(p.mode_paiement, 'especes'))),
                 'entree', p.montant
            from public.paiements_dette p
            join public.dettes d on d.id = p.dette_id
           where coalesce(p.owner_id, d.owner_id) = v_owner
             and p.date_paiement >= v_d0 and p.date_paiement < v_d1
          union all
          select 'especes', 'sortie', dp.montant
            from public.depenses dp
           where v_visibles
             and dp.owner_id = v_owner
             and dp.date >= v_d0 and dp.date < v_d1
        ) u
       group by mode
    ) g;

  -- Solde global (tout l'historique) -----------------------------------------
  select coalesce(sum(c.montant_total), 0)
    into v_enc_tot
    from public.caisse c
   where c.owner_id = v_owner;

  select coalesce(sum(v.prix), 0)
    into v_leg_tot
    from public.ventes v
   where v.owner_id = v_owner
     and v.numero_vente is null
     and lower(btrim(coalesce(v.mode_paiement, 'especes'))) <> 'dette';

  select coalesce(sum(p.montant), 0)
    into v_pm_tot
    from public.paiements_dette p
    join public.dettes d on d.id = p.dette_id
   where coalesce(p.owner_id, d.owner_id) = v_owner;

  select coalesce(sum(dp.montant), 0)
    into v_dec_tot
    from public.depenses dp
   where dp.owner_id = v_owner;

  v_solde := v_enc_tot + v_leg_tot + v_pm_tot - v_dec_tot;

  -- Dernière clôture -----------------------------------------------------------
  select jsonb_build_object(
           'date_cloture',    cc.date_cloture,
           'solde_theorique', cc.solde_theorique,
           'espece_comptee',  cc.espece_comptee,
           'ecart',           cc.ecart,
           'commentaire',     cc.commentaire,
           'created_at',      cc.created_at
         )
    into v_derniere
    from public.clotures_caisse cc
   where cc.owner_id = v_owner
   order by cc.date_cloture desc
   limit 1;

  return jsonb_build_object(
    'date',               v_jour,
    'solde',              case when v_visibles then v_solde else null end,
    'depenses_visibles',  v_visibles,
    'jour', jsonb_build_object(
      'encaissements_ventes', v_enc_ventes,
      'encaissements_dettes', v_enc_dettes,
      'encaissements',        v_enc_ventes + v_enc_dettes,
      'decaissements',        case when v_visibles then v_dec_jour else null end,
      'net',                  v_enc_ventes + v_enc_dettes - case when v_visibles then v_dec_jour else 0 end,
      'nb_ventes',            v_nb_ventes,
      'nb_paiements_dettes',  v_nb_pm,
      'nb_depenses',          v_nb_dep
    ),
    'par_mode',           v_par_mode,
    'derniere_cloture',   coalesce(v_derniere, 'null'::jsonb)
  );
end;
$$;

comment on function public.rpc_caisse_resume(date) is
  'Résumé de caisse du jour (encaissements, décaissements, par mode, solde global) recalculé en temps réel.';

-- 8.b `rpc_caisse_journal` -----------------------------------------------------
--  Droit `caisse/voir` (ou `finance/voir`). Historique unifié :
--    ventes encaissées (Module 8) · ventes anciennes · règlements de dettes ·
--    dépenses (seulement si `depenses/voir`).
--  Filtres : période, sens (entree/sortie), mode de paiement.
--  Codes : SESSION_ABSENTE | ACCES_REFUSE | DROIT_REFUSE | PERIODE_INVALIDE |
--          SENS_INVALIDE

create or replace function public.rpc_caisse_journal(
  p_debut date default current_date,
  p_fin   date default current_date,
  p_sens  text default null,
  p_mode  text default null,
  p_limit integer default 200
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user    uuid := auth.uid();
  v_owner   uuid;
  v_debut   date := coalesce(p_debut, current_date);
  v_fin     date := coalesce(p_fin, current_date);
  v_sens    text := nullif(lower(btrim(coalesce(p_sens, ''))), '');
  v_mode    text := nullif(lower(btrim(coalesce(p_mode, ''))), '');
  v_limit   integer := least(greatest(coalesce(p_limit, 200), 1), 500);
  v_visibles boolean;
  v_lignes  jsonb := '[]'::jsonb;
  v_totaux  jsonb := '{}'::jsonb;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour consulter la caisse.';
  end if;

  if public.finance_role_plateforme_bloque() then
    raise exception 'ACCES_REFUSE|La finance d''une entreprise est privée : le personnel de la plateforme n''y a pas accès.';
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  if not public.acces_finance_entreprise(v_owner) then
    raise exception 'ACCES_REFUSE|Vous n''êtes pas membre de cette entreprise.';
  end if;

  if not (public.peut('caisse', 'voir') or public.peut('finance', 'voir')) then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de consulter la caisse.';
  end if;

  if v_debut > v_fin then
    raise exception 'PERIODE_INVALIDE|La date de début doit précéder la date de fin.';
  end if;

  if v_sens is not null and v_sens not in ('entree', 'sortie') then
    raise exception 'SENS_INVALIDE|Le filtre de sens doit être « entree » ou « sortie ».';
  end if;

  v_visibles := public.peut('depenses', 'voir');

  with u as (
    select 'vente'::text as type,
           c.numero_vente as reference,
           coalesce(nullif(btrim(cl.nom), ''), 'Vente ' || c.numero_vente) as libelle,
           'entree'::text as sens,
           lower(btrim(coalesce(c.mode_paiement, 'especes'))) as mode,
           c.montant_total as montant,
           c.date as date_op
      from public.caisse c
      left join public.clients cl on cl.id = c.client_id
     where c.owner_id = v_owner
       and c.date >= v_debut::timestamptz and c.date < (v_fin + 1)::timestamptz

    union all

    select 'vente_ancienne',
           null,
           coalesce(pr.nom, 'Vente sans numéro'),
           'entree',
           lower(btrim(coalesce(v.mode_paiement, 'especes'))),
           v.prix,
           v.date
      from public.ventes v
      left join public.produits pr on pr.id = v.produit_id
     where v.owner_id = v_owner
       and v.numero_vente is null
       and lower(btrim(coalesce(v.mode_paiement, 'especes'))) <> 'dette'
       and v.date >= v_debut::timestamptz and v.date < (v_fin + 1)::timestamptz

    union all

    select 'dette',
           'DET-' || p.dette_id,
           'Règlement — ' || coalesce(nullif(btrim(cl2.nom), ''), 'client inconnu'),
           'entree',
           lower(btrim(coalesce(p.mode_paiement, 'especes'))),
           p.montant,
           p.date_paiement
      from public.paiements_dette p
      join public.dettes d2 on d2.id = p.dette_id
      left join public.clients cl2 on cl2.id = d2.client_id
     where coalesce(p.owner_id, d2.owner_id) = v_owner
       and p.date_paiement >= v_debut::timestamptz and p.date_paiement < (v_fin + 1)::timestamptz

    union all

    select 'depense',
           'DEP-' || dp.id,
           dp.motif,
           'sortie',
           'especes',
           dp.montant,
           dp.date
      from public.depenses dp
     where v_visibles
       and dp.owner_id = v_owner
       and dp.date >= v_debut::timestamptz and dp.date < (v_fin + 1)::timestamptz
  )
  select
    (
      select coalesce(jsonb_agg(jsonb_build_object(
               'type',      l.type,
               'reference', l.reference,
               'libelle',   l.libelle,
               'sens',      l.sens,
               'mode',      l.mode,
               'montant',   l.montant,
               'date',      l.date_op
             ) order by l.date_op desc), '[]'::jsonb)
        from (select * from u
               where (v_sens is null or sens = v_sens)
                 and (v_mode is null or mode = v_mode)
               order by date_op desc
               limit v_limit) l
    ),
    (
      select jsonb_build_object(
               'entrees', coalesce(sum(montant) filter (where sens = 'entree'), 0),
               'sorties', coalesce(sum(montant) filter (where sens = 'sortie'), 0),
               'nb',      count(*)
             )
        from u
       where (v_sens is null or sens = v_sens)
         and (v_mode is null or mode = v_mode)
    )
    into v_lignes, v_totaux;

  return jsonb_build_object(
    'debut',  v_debut,
    'fin',    v_fin,
    'sens',   v_sens,
    'mode',   v_mode,
    'lignes', v_lignes,
    'totaux', v_totaux
  );
end;
$$;

comment on function public.rpc_caisse_journal(date, date, text, text, integer) is
  'Historique unifié de la caisse (ventes, règlements de dettes, dépenses) avec filtres et totaux.';

-- 8.c `rpc_caisse_cloturer` ----------------------------------------------------
--  Droit `caisse/modifier` ou `caisse/valider`. Fige la journée dans
--  `clotures_caisse` (ré-exécutable : remplace la clôture du même jour) et
--  journalise l'opération. L'écart se calcule sur l'ESPÈCE :
--    espèce attendue = fond initial + encaissements espèces − dépenses
--    (toutes les dépenses sont supposées payées en espèces).
--  Codes : SESSION_ABSENTE | ACCES_REFUSE | DROIT_REFUSE | DATE_INVALIDE |
--          MONTANT_INVALIDE

create or replace function public.rpc_caisse_cloturer(
  p_date         date default current_date,
  p_fond_initial numeric default 0,
  p_espece_comptee numeric default null,
  p_commentaire  text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user      uuid := auth.uid();
  v_owner     uuid;
  v_jour      date := coalesce(p_date, current_date);
  v_fond      numeric := coalesce(p_fond_initial, 0);
  v_d0        timestamptz;
  v_d1        timestamptz;
  v_enc_ventes numeric := 0;
  v_enc_dettes numeric := 0;
  v_dec        numeric := 0;
  v_enc_especes numeric := 0;
  v_pm_especes  numeric := 0;
  v_nb_ventes  integer := 0;
  v_nb_pm      integer := 0;
  v_nb_dep     integer := 0;
  v_solde      numeric;
  v_attendu    numeric;
  v_ecart      numeric;
  v_details    jsonb;
  v_cloture    record;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour clôturer la caisse.';
  end if;

  if public.finance_role_plateforme_bloque() then
    raise exception 'ACCES_REFUSE|La finance d''une entreprise est privée : le personnel de la plateforme n''y a pas accès.';
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  if not public.acces_finance_entreprise(v_owner) then
    raise exception 'ACCES_REFUSE|Vous n''êtes pas membre de cette entreprise.';
  end if;

  if not (public.peut('caisse', 'modifier') or public.peut('caisse', 'valider')) then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de clôturer la caisse.';
  end if;

  if v_jour > current_date then
    raise exception 'DATE_INVALIDE|Impossible de clôturer une journée future.';
  end if;

  if v_fond < 0 then
    raise exception 'MONTANT_INVALIDE|Le fond de caisse ne peut pas être négatif.';
  end if;

  if p_espece_comptee is not null and p_espece_comptee < 0 then
    raise exception 'MONTANT_INVALIDE|L''espèce comptée ne peut pas être négative.';
  end if;

  v_d0 := v_jour::timestamptz;
  v_d1 := (v_jour + 1)::timestamptz;

  -- Encaissements et décaissements de la journée -----------------------------
  select coalesce(sum(c.montant_total), 0), count(*)
    into v_enc_ventes, v_nb_ventes
    from public.caisse c
   where c.owner_id = v_owner
     and c.date >= v_d0 and c.date < v_d1;

  select v_enc_ventes + coalesce(sum(v.prix), 0),
         v_nb_ventes + count(*)
    into v_enc_ventes, v_nb_ventes
    from public.ventes v
   where v.owner_id = v_owner
     and v.numero_vente is null
     and lower(btrim(coalesce(v.mode_paiement, 'especes'))) <> 'dette'
     and v.date >= v_d0 and v.date < v_d1;

  select coalesce(sum(p.montant), 0), count(*)
    into v_enc_dettes, v_nb_pm
    from public.paiements_dette p
    join public.dettes d on d.id = p.dette_id
   where coalesce(p.owner_id, d.owner_id) = v_owner
     and p.date_paiement >= v_d0 and p.date_paiement < v_d1;

  select coalesce(sum(dp.montant), 0), count(*)
    into v_dec, v_nb_dep
    from public.depenses dp
   where dp.owner_id = v_owner
     and dp.date >= v_d0 and dp.date < v_d1;

  -- Espèces uniquement (pour l'écart) ------------------------------------------
  select coalesce(sum(c.montant_total), 0)
    into v_enc_especes
    from public.caisse c
   where c.owner_id = v_owner
     and lower(btrim(coalesce(c.mode_paiement, 'especes'))) = 'especes'
     and c.date >= v_d0 and c.date < v_d1;

  select v_enc_especes + coalesce(sum(v.prix), 0)
    into v_enc_especes
    from public.ventes v
   where v.owner_id = v_owner
     and v.numero_vente is null
     and lower(btrim(coalesce(v.mode_paiement, 'especes'))) = 'especes'
     and v.date >= v_d0 and v.date < v_d1;

  select coalesce(sum(p.montant), 0)
    into v_pm_especes
    from public.paiements_dette p
    join public.dettes d on d.id = p.dette_id
   where coalesce(p.owner_id, d.owner_id) = v_owner
     and lower(btrim(coalesce(p.mode_paiement, 'especes'))) = 'especes'
     and p.date_paiement >= v_d0 and p.date_paiement < v_d1;

  v_solde   := v_enc_ventes + v_enc_dettes - v_dec;
  v_attendu := v_fond + v_enc_especes + v_pm_especes - v_dec;
  v_ecart   := case when p_espece_comptee is null then null
                    else p_espece_comptee - v_attendu end;

  v_details := jsonb_build_object(
    'nb_ventes',           v_nb_ventes,
    'nb_paiements_dettes', v_nb_pm,
    'nb_depenses',         v_nb_dep,
    'encaissements_ventes', v_enc_ventes,
    'encaissements_dettes', v_enc_dettes,
    'depenses',             v_dec,
    'especes', jsonb_build_object(
      'fond_initial',    v_fond,
      'enc_ventes',      v_enc_especes,
      'enc_dettes',      v_pm_especes,
      'depenses',        v_dec,
      'attendu',         v_attendu,
      'compte',          p_espece_comptee
    )
  );

  insert into public.clotures_caisse (
    owner_id, date_cloture, fond_initial, espece_comptee,
    encaissements_total, decaissements_total, solde_theorique,
    ecart, details, commentaire, clos_par, created_at
  ) values (
    v_owner, v_jour, v_fond, p_espece_comptee,
    v_enc_ventes + v_enc_dettes, v_dec, v_fond + v_solde,
    v_ecart, v_details, nullif(btrim(coalesce(p_commentaire, '')), ''), v_user, now()
  )
  on conflict (owner_id, date_cloture) do update
     set fond_initial        = excluded.fond_initial,
         espece_comptee      = excluded.espece_comptee,
         encaissements_total = excluded.encaissements_total,
         decaissements_total = excluded.decaissements_total,
         solde_theorique     = excluded.solde_theorique,
         ecart               = excluded.ecart,
         details             = excluded.details,
         commentaire         = excluded.commentaire,
         clos_par            = excluded.clos_par,
         created_at          = now()
  returning id, date_cloture, fond_initial, espece_comptee,
            encaissements_total, decaissements_total, solde_theorique,
            ecart, details, commentaire, created_at
       into v_cloture;

  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(), null, 'CLOTURE_CAISSE', v_user,
    jsonb_build_object(
      'cloture_id',          v_cloture.id,
      'date_cloture',        v_jour,
      'encaissements_total', v_cloture.encaissements_total,
      'decaissements_total', v_cloture.decaissements_total,
      'solde_theorique',     v_cloture.solde_theorique,
      'espece_comptee',      p_espece_comptee,
      'ecart',               v_ecart,
      'commentaire',         v_cloture.commentaire,
      'boutique',            v_owner
    ),
    now()
  );

  return jsonb_build_object(
    'cloture_id',          v_cloture.id,
    'date_cloture',        v_cloture.date_cloture,
    'fond_initial',        v_cloture.fond_initial,
    'encaissements_total', v_cloture.encaissements_total,
    'decaissements_total', v_cloture.decaissements_total,
    'solde_theorique',     v_cloture.solde_theorique,
    'espece_comptee',      v_cloture.espece_comptee,
    'ecart',               v_cloture.ecart,
    'commentaire',         v_cloture.commentaire,
    'details',             v_cloture.details,
    'created_at',          v_cloture.created_at
  );
end;
$$;

comment on function public.rpc_caisse_cloturer(date, numeric, numeric, text) is
  'Clôture la caisse d''une journée : figée dans clotures_caisse, écart espèces calculé, journalisée.';


-- ============================================================================
--  9. RPC DETTES CLIENTS
-- ============================================================================

-- 9.a `rpc_dettes_liste` -------------------------------------------------------
--  Droit `caisse/voir` (ou `finance/voir`). Liste les dettes avec le nom du
--  client, le restant dû, l'ancienneté et le dernier paiement + un résumé.
--  Filtres : statut (non_paye / partiel / paye), recherche nom/téléphone.
--  Codes : SESSION_ABSENTE | ACCES_REFUSE | DROIT_REFUSE | STATUT_INVALIDE

create or replace function public.rpc_dettes_liste(
  p_statut    text default null,
  p_recherche text default null,
  p_limit     integer default 200
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user     uuid := auth.uid();
  v_owner    uuid;
  v_statut   text := nullif(lower(btrim(coalesce(p_statut, ''))), '');
  v_recherche text := nullif(btrim(coalesce(p_recherche, '')), '');
  v_limit    integer := least(greatest(coalesce(p_limit, 200), 1), 500);
  v_lignes   jsonb := '[]'::jsonb;
  v_resume   jsonb := '{}'::jsonb;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour consulter les dettes.';
  end if;

  if public.finance_role_plateforme_bloque() then
    raise exception 'ACCES_REFUSE|La finance d''une entreprise est privée : le personnel de la plateforme n''y a pas accès.';
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  if not public.acces_finance_entreprise(v_owner) then
    raise exception 'ACCES_REFUSE|Vous n''êtes pas membre de cette entreprise.';
  end if;

  if not (public.peut('caisse', 'voir') or public.peut('finance', 'voir')) then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de consulter les dettes.';
  end if;

  if v_statut is not null and v_statut not in ('non_paye', 'partiel', 'paye') then
    raise exception 'STATUT_INVALIDE|Statut inconnu : « non_paye », « partiel » ou « paye ».';
  end if;

  select coalesce(jsonb_agg(x order by (x->>'statut') = 'paye', x->>'date_creation'), '[]'::jsonb)
    into v_lignes
    from (
      select jsonb_build_object(
               'dette_id',        d.id,
               'client_id',       d.client_id,
               'client',          coalesce(nullif(btrim(c.nom), ''), 'Client ' || d.client_id),
               'telephone',       c.telephone,
               'email',           c.email,
               'vente_uuid',      d.vente_uuid,
               'montant_total',   d.montant_total,
               'montant_paye',    d.montant_paye,
               'restant',         greatest(d.montant_total - d.montant_paye, 0),
               'statut',          lower(coalesce(d.statut, 'non_paye')),
               'date_creation',   d.date_creation,
               'date_echeance',   d.date_echeance,
               'jours',           greatest(current_date - d.date_creation::date, 0),
               'dernier_paiement', (
                 select max(p.date_paiement)
                   from public.paiements_dette p
                  where p.dette_id = d.id
               ),
               'nb_paiements', (
                 select count(*)
                   from public.paiements_dette p
                  where p.dette_id = d.id
               )
             ) as x,
             d.date_creation
        from public.dettes d
        left join public.clients c on c.id = d.client_id
       where d.owner_id = v_owner
         and (v_statut is null or lower(coalesce(d.statut, 'non_paye')) = v_statut)
         and (
           v_recherche is null
           or c.nom ilike '%' || v_recherche || '%'
           or coalesce(c.telephone, '') ilike '%' || v_recherche || '%'
         )
       order by (lower(coalesce(d.statut, 'non_paye')) = 'paye'), d.date_creation asc
       limit v_limit
    ) s;

  select jsonb_build_object(
           'nb',            count(*),
           'nb_non_paye',   count(*) filter (where lower(coalesce(d.statut, 'non_paye')) = 'non_paye'),
           'nb_partiel',    count(*) filter (where lower(coalesce(d.statut, 'non_paye')) = 'partiel'),
           'nb_paye',       count(*) filter (where lower(coalesce(d.statut, 'non_paye')) = 'paye'),
           'total_dettes',  coalesce(sum(d.montant_total), 0),
           'total_restant', coalesce(sum(greatest(d.montant_total - d.montant_paye, 0)), 0)
         )
    into v_resume
    from public.dettes d
    left join public.clients c on c.id = d.client_id
   where d.owner_id = v_owner
     and (v_statut is null or lower(coalesce(d.statut, 'non_paye')) = v_statut)
     and (
       v_recherche is null
       or c.nom ilike '%' || v_recherche || '%'
       or coalesce(c.telephone, '') ilike '%' || v_recherche || '%'
     );

  return jsonb_build_object(
    'statut',    v_statut,
    'recherche', v_recherche,
    'lignes',    v_lignes,
    'resume',    v_resume
  );
end;
$$;

comment on function public.rpc_dettes_liste(text, text, integer) is
  'Liste les dettes clients (restant dû, ancienneté, dernier paiement) avec filtres et résumé.';

-- 9.b `rpc_dette_creer` --------------------------------------------------------
--  Droit `caisse/creer`. Crée une dette pour un client de la boutique
--  (éventuellement liée à une vente à crédit du Module 8).
--  Codes : SESSION_ABSENTE | ACCES_REFUSE | DROIT_REFUSE | CLIENT_INTROUVABLE |
--          HORS_ENTREPRISE | MONTANT_INVALIDE

create or replace function public.rpc_dette_creer(
  p_client_id     bigint,
  p_montant_total numeric,
  p_vente_uuid    uuid default null,
  p_date_echeance date default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user   uuid := auth.uid();
  v_owner  uuid;
  v_client record;
  v_dette  record;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour enregistrer une dette.';
  end if;

  if public.finance_role_plateforme_bloque() then
    raise exception 'ACCES_REFUSE|La finance d''une entreprise est privée : le personnel de la plateforme n''y a pas accès.';
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  if not public.acces_finance_entreprise(v_owner) then
    raise exception 'ACCES_REFUSE|Vous n''êtes pas membre de cette entreprise.';
  end if;

  if not public.peut('caisse', 'creer') then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de créer une dette.';
  end if;

  if p_montant_total is null or p_montant_total <= 0 then
    raise exception 'MONTANT_INVALIDE|Le montant de la dette doit être supérieur à zéro.';
  end if;

  select c.id, c.owner_id, c.nom
    into v_client
    from public.clients c
   where c.id = p_client_id;

  if not found then
    raise exception 'CLIENT_INTROUVABLE|Client n° % introuvable.', p_client_id;
  end if;

  if v_client.owner_id is distinct from v_owner then
    raise exception 'HORS_ENTREPRISE|Le client % n''appartient pas à votre entreprise.', v_client.nom;
  end if;

  insert into public.dettes (
    owner_id, client_id, vente_id, vente_uuid, montant_total, montant_paye,
    statut, date_creation, date_echeance, is_synced
  ) values (
    v_owner, p_client_id, null, p_vente_uuid, p_montant_total, 0,
    'non_paye', now(), p_date_echeance, 1
  )
  returning id, client_id, montant_total, montant_paye, statut,
            date_creation, date_echeance into v_dette;

  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(), null, 'DETTE', v_user,
    jsonb_build_object(
      'dette_id',      v_dette.id,
      'client_id',     p_client_id,
      'client',        v_client.nom,
      'montant_total', p_montant_total,
      'vente_uuid',    p_vente_uuid,
      'boutique',      v_owner
    ),
    now()
  );

  return jsonb_build_object(
    'dette_id',      v_dette.id,
    'client_id',     v_dette.client_id,
    'client',        v_client.nom,
    'montant_total', v_dette.montant_total,
    'montant_paye',  v_dette.montant_paye,
    'statut',        v_dette.statut,
    'date_creation', v_dette.date_creation,
    'date_echeance', v_dette.date_echeance
  );
end;
$$;

comment on function public.rpc_dette_creer(bigint, numeric, uuid, date) is
  'Crée une dette client (éventuellement liée à une vente du Module 8).';

-- 9.c `rpc_dette_paiement` -----------------------------------------------------
--  Droit `caisse/creer`. Enregistre un règlement PARTIEL (ou soldant).
--  Le trigger `trg_paiements_dette_recalcul` met à jour montant_paye/statut.
--  Codes : SESSION_ABSENTE | ACCES_REFUSE | DROIT_REFUSE | DETTE_INTROUVABLE |
--          HORS_ENTREPRISE | MONTANT_INVALIDE | MONTANT_EXCESSIF | MODE_INVALIDE

create or replace function public.rpc_dette_paiement(
  p_dette_id      bigint,
  p_montant       numeric,
  p_mode_paiement text default 'especes',
  p_date_paiement timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user    uuid := auth.uid();
  v_owner   uuid;
  v_mode    text := coalesce(nullif(lower(btrim(coalesce(p_mode_paiement, ''))), ''), 'especes');
  v_date    timestamptz := coalesce(p_date_paiement, now());
  v_dette   record;
  v_restant numeric;
  v_client  text;
  v_paye    numeric;
  v_statut  text;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour encaisser un règlement.';
  end if;

  if public.finance_role_plateforme_bloque() then
    raise exception 'ACCES_REFUSE|La finance d''une entreprise est privée : le personnel de la plateforme n''y a pas accès.';
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  if not public.acces_finance_entreprise(v_owner) then
    raise exception 'ACCES_REFUSE|Vous n''êtes pas membre de cette entreprise.';
  end if;

  if not public.peut('caisse', 'creer') then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas d''encaisser un règlement de dette.';
  end if;

  if v_mode not in ('especes', 'mobile_money', 'carte', 'virement', 'autre') then
    raise exception 'MODE_INVALIDE|Mode de paiement inconnu : espèces, mobile money, carte, virement ou autre.';
  end if;

  if p_montant is null or p_montant <= 0 then
    raise exception 'MONTANT_INVALIDE|Le montant du règlement doit être supérieur à zéro.';
  end if;

  select d.id, d.owner_id, d.client_id, d.montant_total, d.montant_paye, d.statut,
         coalesce(nullif(btrim(c.nom), ''), 'Client ' || d.client_id) as client_nom
    into v_dette
    from public.dettes d
    left join public.clients c on c.id = d.client_id
   where d.id = p_dette_id
     for update of d;

  if not found then
    raise exception 'DETTE_INTROUVABLE|Dette n° % introuvable.', p_dette_id;
  end if;

  if v_dette.owner_id is distinct from v_owner then
    raise exception 'HORS_ENTREPRISE|Cette dette n''appartient pas à votre entreprise.';
  end if;

  v_client := v_dette.client_nom;

  v_restant := greatest(coalesce(v_dette.montant_total, 0) - coalesce(v_dette.montant_paye, 0), 0);

  if v_restant <= 0 then
    raise exception 'MONTANT_EXCESSIF|Dette déjà soldée : aucun montant à encaisser.';
  end if;

  if p_montant > v_restant + 0.005 then
    raise exception 'MONTANT_EXCESSIF|Le montant dépasse le restant dû (% restant).', round(v_restant);
  end if;

  -- Le trigger recalcule montant_paye et statut.
  insert into public.paiements_dette (
    dette_id, montant, date_paiement, owner_id, mode_paiement, is_synced
  ) values (
    p_dette_id, p_montant, v_date, v_owner, v_mode, 1
  );

  select d.montant_paye, d.statut
    into v_paye, v_statut
    from public.dettes d
   where d.id = p_dette_id;

  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(), null, 'PAIEMENT_DETTE', v_user,
    jsonb_build_object(
      'dette_id',      p_dette_id,
      'client',        v_client,
      'montant',       p_montant,
      'mode_paiement', v_mode,
      'montant_paye',  v_paye,
      'statut',        v_statut,
      'boutique',      v_owner
    ),
    now()
  );

  return jsonb_build_object(
    'dette_id',      p_dette_id,
    'client',        v_client,
    'montant',       p_montant,
    'mode_paiement', v_mode,
    'date_paiement', v_date,
    'montant_paye',  v_paye,
    'restant',       greatest(coalesce(v_dette.montant_total, 0) - coalesce(v_paye, 0), 0),
    'statut',        v_statut
  );
end;
$$;

comment on function public.rpc_dette_paiement(bigint, numeric, text, timestamptz) is
  'Enregistre un règlement (partiel) de dette ; le trigger met à jour montant_paye et statut.';

-- 9.d `rpc_dette_relancer` -----------------------------------------------------
--  Droit `caisse/voir`. Prépare un message de relance (WhatsApp / SMS /
--  appel — l'application ouvre le lien) et TRACE la relance dans le journal.
--  Codes : SESSION_ABSENTE | ACCES_REFUSE | DROIT_REFUSE | DETTE_INTROUVABLE |
--          HORS_ENTREPRISE | DEJA_SOLDEE | CANAL_INVALIDE | SANS_TELEPHONE

create or replace function public.rpc_dette_relancer(
  p_dette_id bigint,
  p_canal    text default 'whatsapp'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user      uuid := auth.uid();
  v_owner     uuid;
  v_canal     text := coalesce(nullif(lower(btrim(coalesce(p_canal, ''))), ''), 'whatsapp');
  v_dette     record;
  v_restant   numeric;
  v_jours     integer;
  v_signature text;
  v_message   text;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour relancer un client.';
  end if;

  if public.finance_role_plateforme_bloque() then
    raise exception 'ACCES_REFUSE|La finance d''une entreprise est privée : le personnel de la plateforme n''y a pas accès.';
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  if not public.acces_finance_entreprise(v_owner) then
    raise exception 'ACCES_REFUSE|Vous n''êtes pas membre de cette entreprise.';
  end if;

  if not (public.peut('caisse', 'voir') or public.peut('finance', 'voir')) then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de relancer un client.';
  end if;

  if v_canal not in ('whatsapp', 'sms', 'appel') then
    raise exception 'CANAL_INVALIDE|Canal inconnu : « whatsapp », « sms » ou « appel ».';
  end if;

  select d.id, d.owner_id, d.client_id, d.montant_total, d.montant_paye,
         d.statut, d.date_creation,
         c.nom as client_nom, c.telephone as client_tel
    into v_dette
    from public.dettes d
    left join public.clients c on c.id = d.client_id
   where d.id = p_dette_id;

  if not found then
    raise exception 'DETTE_INTROUVABLE|Dette n° % introuvable.', p_dette_id;
  end if;

  if v_dette.owner_id is distinct from v_owner then
    raise exception 'HORS_ENTREPRISE|Cette dette n''appartient pas à votre entreprise.';
  end if;

  v_restant := greatest(coalesce(v_dette.montant_total, 0) - coalesce(v_dette.montant_paye, 0), 0);

  if v_restant <= 0 then
    raise exception 'DEJA_SOLDEE|Cette dette est déjà soldée : aucune relance à envoyer.';
  end if;

  if coalesce(btrim(v_dette.client_tel), '') = '' then
    raise exception 'SANS_TELEPHONE|Ce client n''a pas de numéro de téléphone : renseignez-le d''abord.';
  end if;

  v_jours := greatest(current_date - v_dette.date_creation::date, 0);

  select coalesce(nullif(btrim(u.nom), ''), u.email, '')
    into v_signature
    from public.utilisateurs u
   where u.id = v_owner;

  v_message := 'Bonjour ' || coalesce(nullif(btrim(v_dette.client_nom), ''), 'client')
            || ', votre dette de ' || round(v_restant)::bigint::text || ' CDF'
            || ' (enregistrée le ' || to_char(v_dette.date_creation, 'DD/MM/YYYY')
            || ') reste à régler. Merci de passer régler votre solde.'
            || case when coalesce(v_signature, '') = '' then ''
                    else ' — ' || v_signature end;

  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(), null, 'RELANCE_DETTE', v_user,
    jsonb_build_object(
      'dette_id',  p_dette_id,
      'client',    v_dette.client_nom,
      'telephone', v_dette.client_tel,
      'canal',     v_canal,
      'restant',   v_restant,
      'jours',     v_jours,
      'boutique',  v_owner
    ),
    now()
  );

  return jsonb_build_object(
    'dette_id',  p_dette_id,
    'client',    v_dette.client_nom,
    'telephone', v_dette.client_tel,
    'canal',     v_canal,
    'restant',   v_restant,
    'jours',     v_jours,
    'message',   v_message
  );
end;
$$;

comment on function public.rpc_dette_relancer(bigint, text) is
  'Prépare un message de relance client (WhatsApp/SMS/appel) et trace l''action dans journal_audit.';


-- ============================================================================
--  10. RPC RAPPORTS FINANCIERS
-- ============================================================================

-- 10.a `rpc_finance_tableau_bord` ----------------------------------------------
--  Droit `finance/voir`. Tableau de bord : CA / coût / marge / dépenses /
--  bénéfice net pour le jour, la semaine (ISO) et le mois en cours, séries
--  de 7 et 30 jours (graphiques) et top 5 articles des 30 derniers jours.
--  Codes : SESSION_ABSENTE | ACCES_REFUSE | DROIT_REFUSE | DATE_INVALIDE

create or replace function public.rpc_finance_tableau_bord(p_ref date default current_date)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user    uuid := auth.uid();
  v_owner   uuid;
  v_ref     date := coalesce(p_ref, current_date);
  v_serie7  jsonb := '[]'::jsonb;
  v_serie30 jsonb := '[]'::jsonb;
  v_stats   jsonb;
  v_top     jsonb := '[]'::jsonb;
  i         integer;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour consulter la finance.';
  end if;

  if public.finance_role_plateforme_bloque() then
    raise exception 'ACCES_REFUSE|La finance d''une entreprise est privée : le personnel de la plateforme n''y a pas accès.';
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  if not public.acces_finance_entreprise(v_owner) then
    raise exception 'ACCES_REFUSE|Vous n''êtes pas membre de cette entreprise.';
  end if;

  if not public.peut('finance', 'voir') then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de consulter la finance.';
  end if;

  if v_ref > current_date then
    raise exception 'DATE_INVALIDE|La date de référence ne peut pas être dans le futur.';
  end if;

  -- Séries pour graphiques ------------------------------------------------------
  for i in reverse 6..0 loop
    v_stats := public.finance_stats_periode(v_owner, v_ref - i, v_ref - i);
    v_serie7 := v_serie7 || jsonb_build_object(
      'jour',              v_ref - i,
      'chiffre_affaires',  (v_stats->>'chiffre_affaires')::numeric,
      'cout_marchandises', (v_stats->>'cout_marchandises')::numeric,
      'depenses',          (v_stats->>'depenses')::numeric,
      'benefice_net',      (v_stats->>'benefice_net')::numeric,
      'nb_ventes',         (v_stats->>'nb_ventes')::numeric
    );
  end loop;

  for i in reverse 29..0 loop
    v_stats := public.finance_stats_periode(v_owner, v_ref - i, v_ref - i);
    v_serie30 := v_serie30 || jsonb_build_object(
      'jour',              v_ref - i,
      'chiffre_affaires',  (v_stats->>'chiffre_affaires')::numeric,
      'cout_marchandises', (v_stats->>'cout_marchandises')::numeric,
      'depenses',          (v_stats->>'depenses')::numeric,
      'benefice_net',      (v_stats->>'benefice_net')::numeric,
      'nb_ventes',         (v_stats->>'nb_ventes')::numeric
    );
  end loop;

  -- Top 5 articles (30 jours) ----------------------------------------------------
  select coalesce(jsonb_agg(x), '[]'::jsonb)
    into v_top
    from (
      select jsonb_build_object(
               'produit_id', v.produit_id,
               'nom',        coalesce(pr.nom, 'Article supprimé'),
               'quantite',   sum(v.quantite),
               'ca',         sum(v.prix),
               'marge',      sum(v.prix) - sum(v.quantite * coalesce(pr.prix_achat, 0))
             ) as x
        from public.ventes v
        left join public.produits pr on pr.id = v.produit_id
       where v.owner_id = v_owner
         and v.date >= (v_ref - 29)::timestamptz
         and v.date <  (v_ref + 1)::timestamptz
       group by v.produit_id, pr.nom
       order by sum(v.prix) desc
       limit 5
    ) s;

  return jsonb_build_object(
    'ref',          v_ref,
    'jour',         public.finance_stats_periode(v_owner, v_ref, v_ref),
    'semaine',      public.finance_stats_periode(v_owner, date_trunc('week', v_ref)::date, v_ref),
    'mois',         public.finance_stats_periode(v_owner, date_trunc('month', v_ref)::date, v_ref),
    'series_7',     v_serie7,
    'series_30',    v_serie30,
    'top_articles', v_top
  );
end;
$$;

comment on function public.rpc_finance_tableau_bord(date) is
  'Tableau de bord finance : CA/dépenses/bénéfice du jour, semaine, mois + séries graphiques + top articles.';

-- 10.b `rpc_finance_rapport` -----------------------------------------------------
--  Droits `rapports/voir` ou `finance/voir`. Rapport détaillé par axe :
--    'article'            — revenus et marge par article ;
--    'vendeur'            — chiffre d'affaires par vendeur ;
--    'mode'               — chiffre d'affaires par mode de paiement ;
--    'categorie_depense'  — dépenses par catégorie ;
--    'jour'               — CA / coût / dépenses / bénéfice net par jour.
--  Codes : SESSION_ABSENTE | ACCES_REFUSE | DROIT_REFUSE | GROUPE_INVALIDE |
--          PERIODE_INVALIDE

create or replace function public.rpc_finance_rapport(
  p_groupe text,
  p_debut  date default null,
  p_fin    date default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user   uuid := auth.uid();
  v_owner  uuid;
  v_groupe text := lower(btrim(coalesce(p_groupe, '')));
  v_debut  date := coalesce(p_debut, current_date - 29);
  v_fin    date := coalesce(p_fin, current_date);
  v_lignes jsonb := '[]'::jsonb;
  v_stats  jsonb;
  v_jour   date;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour consulter les rapports.';
  end if;

  if public.finance_role_plateforme_bloque() then
    raise exception 'ACCES_REFUSE|La finance d''une entreprise est privée : le personnel de la plateforme n''y a pas accès.';
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  if not public.acces_finance_entreprise(v_owner) then
    raise exception 'ACCES_REFUSE|Vous n''êtes pas membre de cette entreprise.';
  end if;

  if not (public.peut('rapports', 'voir') or public.peut('finance', 'voir')) then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de consulter les rapports financiers.';
  end if;

  if v_debut > v_fin then
    raise exception 'PERIODE_INVALIDE|La date de début doit précéder la date de fin.';
  end if;

  if (v_fin - v_debut) > 366 then
    raise exception 'PERIODE_INVALIDE|Période trop longue : 366 jours maximum.';
  end if;

  v_stats := public.finance_stats_periode(v_owner, v_debut, v_fin);

  case v_groupe
    -- ------------------------------------------------------------------ articles
    when 'article' then
      select coalesce(jsonb_agg(x), '[]'::jsonb)
        into v_lignes
        from (
          select jsonb_build_object(
                   'produit_id', v.produit_id,
                   'nom',        coalesce(pr.nom, 'Article supprimé'),
                   'quantite',   sum(v.quantite),
                   'ca',         sum(v.prix),
                   'cout',       sum(v.quantite * coalesce(pr.prix_achat, 0)),
                   'marge',      sum(v.prix) - sum(v.quantite * coalesce(pr.prix_achat, 0))
                 ) as x
            from public.ventes v
            left join public.produits pr on pr.id = v.produit_id
           where v.owner_id = v_owner
             and v.date >= v_debut::timestamptz
             and v.date <  (v_fin + 1)::timestamptz
           group by v.produit_id, pr.nom
           order by sum(v.prix) desc
        ) s;

    -- ------------------------------------------------------------------ vendeurs
    when 'vendeur' then
      select coalesce(jsonb_agg(x), '[]'::jsonb)
        into v_lignes
        from (
          select jsonb_build_object(
                   'seller_id', v.seller_id,
                   'nom',       coalesce(nullif(btrim(u.nom), ''), u.email, 'Vendeur non attribué'),
                   'nb_ventes', count(distinct coalesce(v.vente_uuid::text, 'L' || v.id)),
                   'ca',        sum(v.prix)
                 ) as x
            from public.ventes v
            left join public.utilisateurs u on u.id = v.seller_id
           where v.owner_id = v_owner
             and v.date >= v_debut::timestamptz
             and v.date <  (v_fin + 1)::timestamptz
           group by v.seller_id, u.nom, u.email
           order by sum(v.prix) desc
        ) s;

    -- -------------------------------------------------------------------- modes
    when 'mode' then
      select coalesce(jsonb_agg(x), '[]'::jsonb)
        into v_lignes
        from (
          select jsonb_build_object(
                   'mode',      lower(btrim(coalesce(v.mode_paiement, 'especes'))),
                   'nb_ventes', count(distinct coalesce(v.vente_uuid::text, 'L' || v.id)),
                   'ca',        sum(v.prix)
                 ) as x
            from public.ventes v
           where v.owner_id = v_owner
             and v.date >= v_debut::timestamptz
             and v.date <  (v_fin + 1)::timestamptz
           group by 1
           order by sum(v.prix) desc
        ) s;

    -- ----------------------------------------------------- dépenses par catégorie
    when 'categorie_depense' then
      select coalesce(jsonb_agg(x), '[]'::jsonb)
        into v_lignes
        from (
          select jsonb_build_object(
                   'categorie', lower(coalesce(dp.categorie, 'autre')),
                   'nb',        count(*),
                   'montant',   sum(dp.montant)
                 ) as x
            from public.depenses dp
           where dp.owner_id = v_owner
             and dp.date >= v_debut::timestamptz
             and dp.date <  (v_fin + 1)::timestamptz
           group by 1
           order by sum(dp.montant) desc
        ) s;

    -- --------------------------------------------------------------- par jour
    when 'jour' then
      v_jour := v_debut;
      while v_jour <= v_fin loop
        v_lignes := v_lignes || (
          (select public.finance_stats_periode(v_owner, v_jour, v_jour)
                  - 'debut' - 'fin')
          || jsonb_build_object('jour', v_jour)
        );
        v_jour := v_jour + 1;
      end loop;

    else
      raise exception 'GROUPE_INVALIDE|Groupe inconnu : « article », « vendeur », « mode », « categorie_depense » ou « jour ».';
  end case;

  return jsonb_build_object(
    'groupe', v_groupe,
    'debut',  v_debut,
    'fin',    v_fin,
    'lignes', v_lignes,
    'totaux', v_stats
  );
end;
$$;

comment on function public.rpc_finance_rapport(text, date, date) is
  'Rapport financier par article, vendeur, mode de paiement, catégorie de dépense ou jour.';


-- ============================================================================
--  11. DROITS D'EXÉCUTION DES RPC
-- ============================================================================

revoke all on function public.finance_super_admin_autorise() from public;
grant execute on function public.finance_super_admin_autorise() to authenticated;

revoke all on function public.finance_role_plateforme_bloque() from public;
grant execute on function public.finance_role_plateforme_bloque() to authenticated;

revoke all on function public.acces_finance_entreprise(uuid) from public;
grant execute on function public.acces_finance_entreprise(uuid) to authenticated;

revoke all on function public.recalculer_dette_paiement(bigint) from public;

revoke all on function public.finance_stats_periode(uuid, date, date) from public;

revoke all on function public.rpc_depense_creer(text, numeric, timestamptz, text) from public;
grant execute on function public.rpc_depense_creer(text, numeric, timestamptz, text) to authenticated;

revoke all on function public.rpc_depense_supprimer(bigint) from public;
grant execute on function public.rpc_depense_supprimer(bigint) to authenticated;

revoke all on function public.rpc_depenses_liste(date, date, text, integer) from public;
grant execute on function public.rpc_depenses_liste(date, date, text, integer) to authenticated;

revoke all on function public.rpc_caisse_resume(date) from public;
grant execute on function public.rpc_caisse_resume(date) to authenticated;

revoke all on function public.rpc_caisse_journal(date, date, text, text, integer) from public;
grant execute on function public.rpc_caisse_journal(date, date, text, text, integer) to authenticated;

revoke all on function public.rpc_caisse_cloturer(date, numeric, numeric, text) from public;
grant execute on function public.rpc_caisse_cloturer(date, numeric, numeric, text) to authenticated;

revoke all on function public.rpc_dettes_liste(text, text, integer) from public;
grant execute on function public.rpc_dettes_liste(text, text, integer) to authenticated;

revoke all on function public.rpc_dette_creer(bigint, numeric, uuid, date) from public;
grant execute on function public.rpc_dette_creer(bigint, numeric, uuid, date) to authenticated;

revoke all on function public.rpc_dette_paiement(bigint, numeric, text, timestamptz) from public;
grant execute on function public.rpc_dette_paiement(bigint, numeric, text, timestamptz) to authenticated;

revoke all on function public.rpc_dette_relancer(bigint, text) from public;
grant execute on function public.rpc_dette_relancer(bigint, text) to authenticated;

revoke all on function public.rpc_finance_tableau_bord(date) from public;
grant execute on function public.rpc_finance_tableau_bord(date) to authenticated;

revoke all on function public.rpc_finance_rapport(text, date, date) from public;
grant execute on function public.rpc_finance_rapport(text, date, date) to authenticated;


-- ============================================================================
--  12. RLS — LA FINANCE RESTE DANS L'ENTREPRISE (politiques REMPLACÉES)
-- ============================================================================
--  Toutes les policies existantes des cinq tables finance sont retirées
--  (quel que soit leur nom — legacy compris), puis remplacées :
--
--    • lecture   : membre de l'entreprise (`acces_finance_entreprise`)
--                  + droit de la page correspondante (`peut`) ;
--    • écriture  : réservée aux membres ayant le droit adapté — c'est ce qui
--                  permet à l'ANCIENNE CAISSE de continuer à synchroniser ses
--                  lignes (chacun chez soi) sans rien voir des autres ;
--    • `caisse`  : LECTURE SEULE côté client (écritures par RPC uniquement) ;
--    • `clotures_caisse` : lecture seule côté client (RPC uniquement).
--
--  ⚠️ AUCUNE policy n'accorde quoi que ce soit au personnel plateforme :
--     `acces_finance_entreprise` ne rend vrai pour lui que si le Super Admin
--     est explicitement autorisé par le réglage (défaut : non).

do $$
declare
  r record;
begin
  for r in
    select policyname, tablename
      from pg_policies
     where schemaname = 'public'
       and tablename in ('caisse', 'depenses', 'dettes',
                         'paiements_dette', 'clotures_caisse')
  loop
    execute format('drop policy if exists %I on public.%I', r.policyname, r.tablename);
  end loop;
end $$;

alter table public.caisse             enable row level security;
alter table public.depenses           enable row level security;
alter table public.dettes             enable row level security;
alter table public.paiements_dette    enable row level security;
alter table public.clotures_caisse    enable row level security;

-- ---------------------------------------------------------------- caisse
create policy m10_caisse_lecture on public.caisse
  for select to authenticated
  using (
    public.acces_finance_entreprise(owner_id)
    and (public.peut('caisse', 'voir') or public.peut('finance', 'voir'))
  );

-- -------------------------------------------------------------- depenses
create policy m10_depenses_lecture on public.depenses
  for select to authenticated
  using (
    public.acces_finance_entreprise(owner_id)
    and public.peut('depenses', 'voir')
  );

create policy m10_depenses_creation on public.depenses
  for insert to authenticated
  with check (
    public.acces_finance_entreprise(owner_id)
    and (public.peut('depenses', 'creer') or public.peut('depenses', 'modifier'))
  );

create policy m10_depenses_modification on public.depenses
  for update to authenticated
  using (
    public.acces_finance_entreprise(owner_id)
    and public.peut('depenses', 'modifier')
  )
  with check (
    public.acces_finance_entreprise(owner_id)
    and public.peut('depenses', 'modifier')
  );

create policy m10_depenses_suppression on public.depenses
  for delete to authenticated
  using (
    public.acces_finance_entreprise(owner_id)
    and public.peut('depenses', 'supprimer')
  );

-- ---------------------------------------------------------------- dettes
create policy m10_dettes_lecture on public.dettes
  for select to authenticated
  using (
    public.acces_finance_entreprise(owner_id)
    and (public.peut('caisse', 'voir') or public.peut('finance', 'voir'))
  );

create policy m10_dettes_creation on public.dettes
  for insert to authenticated
  with check (
    public.acces_finance_entreprise(owner_id)
    and public.peut('caisse', 'creer')
  );

create policy m10_dettes_modification on public.dettes
  for update to authenticated
  using (
    public.acces_finance_entreprise(owner_id)
    and (public.peut('caisse', 'creer') or public.peut('caisse', 'modifier'))
  )
  with check (
    public.acces_finance_entreprise(owner_id)
    and (public.peut('caisse', 'creer') or public.peut('caisse', 'modifier'))
  );

-- ------------------------------------------------------- paiements_dette
create policy m10_paiements_dette_lecture on public.paiements_dette
  for select to authenticated
  using (
    public.acces_finance_entreprise(owner_id)
    and (public.peut('caisse', 'voir') or public.peut('finance', 'voir'))
  );

create policy m10_paiements_dette_creation on public.paiements_dette
  for insert to authenticated
  with check (
    public.acces_finance_entreprise(owner_id)
    and public.peut('caisse', 'creer')
  );

-- ------------------------------------------------------- clotures_caisse
create policy m10_clotures_caisse_lecture on public.clotures_caisse
  for select to authenticated
  using (
    public.acces_finance_entreprise(owner_id)
    and (public.peut('caisse', 'voir') or public.peut('finance', 'voir'))
  );


-- ============================================================================
--  13. VÉRIFICATIONS
-- ============================================================================

-- 13.a Nouvelles colonnes
select table_name, column_name, data_type, is_nullable
  from information_schema.columns
 where table_schema = 'public'
   and (
     (table_name = 'depenses'        and column_name = 'categorie')
     or (table_name = 'dettes'       and column_name in ('vente_uuid', 'date_echeance'))
     or (table_name = 'paiements_dette' and column_name = 'mode_paiement')
   )
 order by table_name, column_name;

-- 13.b Type de `paiements_dette.date_paiement` (attendu : timestamptz)
select column_name, data_type
  from information_schema.columns
 where table_schema = 'public'
   and table_name = 'paiements_dette'
   and column_name = 'date_paiement';

-- 13.c Fonctions du module
select p.proname, pg_get_function_arguments(p.oid) as arguments
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname in (
     'rpc_depense_creer', 'rpc_depense_supprimer', 'rpc_depenses_liste',
     'rpc_caisse_resume', 'rpc_caisse_journal', 'rpc_caisse_cloturer',
     'rpc_dettes_liste', 'rpc_dette_creer', 'rpc_dette_paiement', 'rpc_dette_relancer',
     'rpc_finance_tableau_bord', 'rpc_finance_rapport'
   )
 order by p.proname;

-- 13.d Policies finance (doivent toutes commencer par `m10_`)
select tablename, policyname, cmd
  from pg_policies
 where schemaname = 'public'
   and tablename in ('caisse', 'depenses', 'dettes',
                     'paiements_dette', 'clotures_caisse')
 order by tablename, policyname;

-- 13.e Trigger de recalcul des dettes
select tgname
  from pg_trigger
 where tgrelid = 'public.paiements_dette'::regclass
   and not tgisinternal;

-- 13.f Réglage d'accès plateforme (attendu : false par défaut)
select key, value from public.app_settings
 where key = 'finance_entreprise_plateforme';


-- ============================================================================
--  14. CONTRÔLES MANUELS UTILES (à exécuter au besoin, compte connecté)
-- ============================================================================

-- Enregistrer une dépense (30 000 CDF de transport) :
--
-- select public.rpc_depense_creer('Transport marchandises', 30000, now(), 'transport');
--
-- Lister les dépenses de la semaine :
--
-- select public.rpc_depenses_liste(current_date - 7, current_date, null, 100);
--
-- Résumé de caisse du jour :
--
-- select public.rpc_caisse_resume(current_date);
--
-- Journal de caisse du mois, encaissements seulement :
--
-- select public.rpc_caisse_journal(date_trunc('month', current_date)::date, current_date, 'entree', null, 100);
--
-- Clôture du jour : fond de caisse 10 000, 52 500 CDF comptés en espèces :
--
-- select public.rpc_caisse_cloturer(current_date, 10000, 52500, 'Clôture du soir');
--
-- Créer une dette pour le client n° <ID_CLIENT> :
--
-- select public.rpc_dette_creer(<ID_CLIENT>, 25000, null, current_date + 14);
--
-- Encaisser un règlement partiel de 10 000 CDF en mobile money :
--
-- select public.rpc_dette_paiement(<ID_DETTE>, 10000, 'mobile_money', now());
--
-- Préparer une relance WhatsApp :
--
-- select public.rpc_dette_relancer(<ID_DETTE>, 'whatsapp');
--
-- Tableau de bord finance :
--
-- select public.rpc_finance_tableau_bord(current_date);
--
-- Rapport par vendeur sur 30 jours :
--
-- select public.rpc_finance_rapport('vendeur', current_date - 29, current_date);
--
-- Détail des dettes encore ouvertes :
--
-- select public.rpc_dettes_liste('non_paye', null, 100);
--
-- ⚠️ Pour AUTORISER le Super Admin à voir la finance (déconseillé) :
--
-- update public.app_settings
--    set value = jsonb_build_object('super_admin_autorise', true),
--        updated_at = now()
--  where key = 'finance_entreprise_plateforme';
--
-- Vérifier la trace des opérations :
--
--   select action, details from public.journal_audit
--    where action in ('DEPENSE', 'DETTE', 'PAIEMENT_DETTE', 'RELANCE_DETTE', 'CLOTURE_CAISSE')
--    order by created_at desc limit 10;
