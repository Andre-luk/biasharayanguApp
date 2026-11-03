-- =============================================================================
-- MODULE 24 — COMPLÉMENTS 2 : TARIFS BIDONS, BONUS/DOMMAGES, MARGES
-- =============================================================================
-- Répond aux points restants du cahier des charges du module Distribution :
--   §9  Grille multi-tarifs des bidons (configurable par entreprise).
--   §10 Bonus et produits endommagés par commercial (déclaration + validation).
--   §11 Coût de revient réel et marges (par produit, par commercial, période).
--
-- PRINCIPES
--  • Aucun écrasement d'historique : les factures gardent les prix figés dans
--    `dist_vente_lignes`. Modifier un tarif ne change AUCUNE vente passée.
--  • Les bonus / dommages ne touchent le stock qu'à la VALIDATION du gérant.
--  • Une marge n'est calculée que si les coûts existent ; sinon le serveur le
--    dit (`cout_complet = false`) au lieu d'inventer un chiffre.
--  • Lecture = tous les membres de la distribution ; écriture = rôles dédiés ;
--    aucune policy d'écriture (RPC `security definer` uniquement).
--
-- Idempotent : `create table if not exists`, `create or replace`,
-- `drop ... if exists` avant chaque trigger.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. GRILLE MULTI-TARIFS DES BIDONS
-- -----------------------------------------------------------------------------
create table if not exists public.dist_tarifs (
  id             uuid primary key default gen_random_uuid(),
  owner_id       uuid not null,
  produit_id     uuid not null
                 references public.dist_produits (id) on delete cascade,
  -- Nature commerciale de l'opération (voir `lib/models/distribution_gestion.dart`).
  type_operation text not null
                 check (type_operation in (
                   'standard',            -- prix normal (repli)
                   'bidon_neuf',          -- bidon neuf rempli
                   'eau_avec_echange',    -- eau + reprise d'un bidon vide
                   'remplissage',         -- remplissage du bidon du client
                   'bidon_vide',          -- vente d'un bidon vide
                   'remplacement_endommage'
                 )),
  libelle        text,
  prix           numeric(16,2) not null check (prix >= 0),
  actif          boolean not null default true,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

create unique index if not exists dist_tarifs_unique
  on public.dist_tarifs (owner_id, produit_id, type_operation);
create index if not exists idx_dist_tarifs_owner
  on public.dist_tarifs (owner_id, produit_id);

alter table public.dist_tarifs enable row level security;

drop policy if exists dist_tarifs_lecture on public.dist_tarifs;
create policy dist_tarifs_lecture on public.dist_tarifs
  for select using (public.dist_est_membre(owner_id));

comment on table public.dist_tarifs is
  'Module 24 §9 — grille de prix par type d''opération (bidon neuf, échange, remplissage…). Les ventes passées ne sont jamais recalculées.';

-- Enregistrer / mettre à jour un tarif (gérant ou propriétaire).
create or replace function public.dist_tarif_enregistrer(
  p_produit        uuid,
  p_type_operation text,
  p_prix           numeric,
  p_libelle        text default null,
  p_actif          boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid := public.dist_owner_requis();
  v_type  text := lower(btrim(coalesce(p_type_operation, '')));
  v_prod  record;
  v_id    uuid;
begin
  perform public.dist_exige(array['gerant', 'proprietaire']);

  if v_type not in ('standard', 'bidon_neuf', 'eau_avec_echange',
                    'remplissage', 'bidon_vide', 'remplacement_endommage') then
    raise exception 'TYPE_OPERATION_INVALIDE|Type d''opération inconnu.';
  end if;

  if p_prix is null or p_prix < 0 then
    raise exception 'MONTANT_INVALIDE|Le prix ne peut pas être négatif.';
  end if;

  select * into v_prod from public.dist_produits
   where id = p_produit and owner_id = v_owner;
  if v_prod.id is null then
    raise exception 'PRODUIT_INCONNU|Ce produit fini n''existe pas.';
  end if;

  insert into public.dist_tarifs (owner_id, produit_id, type_operation,
                                  libelle, prix, actif)
  values (v_owner, p_produit, v_type,
          nullif(btrim(coalesce(p_libelle, '')), ''), p_prix, coalesce(p_actif, true))
  on conflict (owner_id, produit_id, type_operation)
  do update set prix       = excluded.prix,
                libelle    = coalesce(excluded.libelle, public.dist_tarifs.libelle),
                actif      = excluded.actif,
                updated_at = now()
  returning id into v_id;

  perform public.dist_journaliser(v_owner, 'TARIF_ENREGISTRE', 'dist_tarifs', v_id,
    jsonb_build_object('produit', v_prod.nom, 'type', v_type, 'prix', p_prix));

  return jsonb_build_object('ok', true, 'id', v_id, 'type_operation', v_type,
                            'prix', p_prix);
end;
$$;

comment on function public.dist_tarif_enregistrer(uuid, text, numeric, text, boolean)
  is 'Module 24 §9 — crée ou met à jour un tarif (sans toucher aux ventes passées).';

-- Tarifs d'un produit, ou de toute la grille.
create or replace function public.dist_tarifs_lister(p_produit uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_owner uuid := public.dist_owner_requis();
  v_items jsonb;
begin
  if public.dist_role() = 'aucun' then
    raise exception 'ACCES_REFUSE|Vous n''êtes pas membre de cette distribution.';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id',             t.id,
           'produit_id',     t.produit_id,
           'produit',        p.nom,
           'type_operation', t.type_operation,
           'libelle',        t.libelle,
           'prix',           t.prix,
           'actif',          t.actif
         ) order by p.nom, t.type_operation), '[]'::jsonb)
    into v_items
    from public.dist_tarifs t
    join public.dist_produits p on p.id = t.produit_id
   where t.owner_id = v_owner
     and (p_produit is null or t.produit_id = p_produit);

  return jsonb_build_object('ok', true, 'items', v_items);
end;
$$;

-- -----------------------------------------------------------------------------
-- 2. BONUS ET PRODUITS ENDOMMAGÉS (par commercial)
-- -----------------------------------------------------------------------------
create table if not exists public.dist_bonus_dommages (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid not null,
  commercial_id uuid not null,
  produit_id    uuid references public.dist_produits (id) on delete set null,
  nom_produit   text not null,
  /** bonus | endommage | casse | perdu */
  nature        text not null
                check (nature in ('bonus', 'endommage', 'casse', 'perdu')),
  quantite      numeric(16,3) not null check (quantite > 0),
  prix_unitaire numeric(16,2) not null default 0,
  valeur        numeric(16,2) not null default 0,
  motif         text not null,
  justificatif  text,
  statut        text not null default 'en_attente'
                check (statut in ('en_attente', 'valide', 'refuse')),
  declare_par   uuid,
  valide_par    uuid,
  valide_le     timestamptz,
  motif_refus   text,
  created_at    timestamptz not null default now()
);

create index if not exists idx_dist_bonus_owner
  on public.dist_bonus_dommages (owner_id, created_at desc);
create index if not exists idx_dist_bonus_commercial
  on public.dist_bonus_dommages (owner_id, commercial_id, created_at desc);

alter table public.dist_bonus_dommages enable row level security;

-- Le commercial ne voit QUE ses déclarations ; la direction voit tout.
drop policy if exists dist_bonus_lecture on public.dist_bonus_dommages;
create policy dist_bonus_lecture on public.dist_bonus_dommages
  for select using (
    public.dist_est_membre(owner_id)
    and (
      public.dist_role() in ('proprietaire', 'gerant', 'comptable', 'stock')
      or commercial_id = auth.uid()
    )
  );

comment on table public.dist_bonus_dommages is
  'Module 24 §10 — bonus offerts, produits endommagés, cassés ou perdus par commercial. Le stock n''est retiré qu''à la validation du gérant.';

-- Déclaration (commercial pour lui-même, gérant/propriétaire pour un autre).
create or replace function public.dist_bonus_declarer(
  p_produit      uuid,
  p_nature       text,
  p_quantite     numeric,
  p_motif        text,
  p_justificatif text default null,
  p_commercial   uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner  uuid := public.dist_owner_requis();
  v_role   text := public.dist_role();
  v_nat    text := lower(btrim(coalesce(p_nature, '')));
  v_motif  text := btrim(coalesce(p_motif, ''));
  v_comm   uuid := coalesce(p_commercial, auth.uid());
  v_prod   record;
  v_id     uuid;
begin
  if v_role = 'aucun' then
    raise exception 'ACCES_REFUSE|Vous n''êtes pas membre de cette distribution.';
  end if;

  -- Un commercial ne déclare que pour lui-même ; la direction pour autrui.
  if v_comm <> auth.uid()
     and v_role not in ('proprietaire', 'gerant') then
    raise exception 'DROIT_REFUSE|Vous ne pouvez déclarer que pour vous-même.';
  end if;

  if v_nat not in ('bonus', 'endommage', 'casse', 'perdu') then
    raise exception 'NATURE_INVALIDE|Précisez : bonus, endommagé, cassé ou perdu.';
  end if;

  if p_quantite is null or p_quantite <= 0 then
    raise exception 'QUANTITE_INVALIDE|La quantité doit être supérieure à zéro.';
  end if;

  if length(v_motif) < 3 then
    raise exception 'MOTIF_REQUIS|Indiquez le motif (3 caractères minimum).';
  end if;

  select * into v_prod from public.dist_produits
   where id = p_produit and owner_id = v_owner;
  if v_prod.id is null then
    raise exception 'PRODUIT_INCONNU|Ce produit fini n''existe pas.';
  end if;

  -- Valeur = prix de vente connu au moment de la déclaration (historique figé).
  insert into public.dist_bonus_dommages (
    owner_id, commercial_id, produit_id, nom_produit, nature,
    quantite, prix_unitaire, valeur, motif, justificatif, declare_par
  ) values (
    v_owner, v_comm, v_prod.id, v_prod.nom, v_nat,
    p_quantite, coalesce(v_prod.prix_vente, 0),
    round(p_quantite * coalesce(v_prod.prix_vente, 0), 2),
    v_motif, nullif(btrim(coalesce(p_justificatif, '')), ''), auth.uid()
  )
  returning id into v_id;

  perform public.dist_journaliser(v_owner, 'BONUS_DECLARE', 'dist_bonus_dommages', v_id,
    jsonb_build_object('nature', v_nat, 'produit', v_prod.nom,
                       'quantite', p_quantite, 'commercial', v_comm));

  return jsonb_build_object('ok', true, 'id', v_id, 'statut', 'en_attente');
end;
$$;

comment on function public.dist_bonus_declarer(uuid, text, numeric, text, text, uuid)
  is 'Module 24 §10 — déclare un bonus / dommage ; aucun stock n''est touché avant validation.';

-- Validation (gérant ou propriétaire) : c'est ICI que le stock baisse.
create or replace function public.dist_bonus_valider(
  p_id      uuid,
  p_valider boolean default true,
  p_motif   text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid := public.dist_owner_requis();
  v_l     record;
  v_motif text := nullif(btrim(coalesce(p_motif, '')), '');
begin
  perform public.dist_exige(array['gerant', 'proprietaire']);

  select * into v_l
    from public.dist_bonus_dommages
   where id = p_id and owner_id = v_owner
   for update;

  if v_l.id is null then
    raise exception 'LIGNE_INTROUVABLE|Cette déclaration n''existe pas.';
  end if;
  if v_l.statut <> 'en_attente' then
    raise exception 'STATUT_INVALIDE|Cette déclaration a déjà été traitée.';
  end if;

  if coalesce(p_valider, true) then
    -- Sortie du stock DU COMMERCIAL (le produit était chez lui).
    if v_l.produit_id is not null then
      perform public.dist_bouger_commercial(
        v_owner, v_l.commercial_id, v_l.produit_id, -v_l.quantite,
        case when v_l.nature = 'bonus' then 'bonus_commercial'
             else 'perte_commercial' end,
        'dist_bonus_dommages', v_l.id, v_l.motif);
    end if;

    update public.dist_bonus_dommages
       set statut = 'valide', valide_par = auth.uid(), valide_le = now()
     where id = p_id;

    perform public.dist_journaliser(v_owner, 'BONUS_VALIDE', 'dist_bonus_dommages', p_id,
      jsonb_build_object('nature', v_l.nature, 'quantite', v_l.quantite,
                         'valeur', v_l.valeur));

    return jsonb_build_object('ok', true, 'statut', 'valide');
  end if;

  update public.dist_bonus_dommages
     set statut = 'refuse', valide_par = auth.uid(), valide_le = now(),
         motif_refus = v_motif
   where id = p_id;

  perform public.dist_journaliser(v_owner, 'BONUS_REFUSE', 'dist_bonus_dommages', p_id,
    jsonb_build_object('motif', coalesce(v_motif, 'non précisé')));

  return jsonb_build_object('ok', true, 'statut', 'refuse');
end;
$$;

-- Liste filtrable (commercial, statut, nature).
create or replace function public.dist_bonus_lister(
  p_commercial uuid default null,
  p_statut     text default null,
  p_limite     integer default 200
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_owner  uuid := public.dist_owner_requis();
  v_role   text := public.dist_role();
  v_limite integer := least(greatest(coalesce(p_limite, 200), 1), 500);
  v_items  jsonb;
begin
  if v_role = 'aucun' then
    raise exception 'ACCES_REFUSE|Vous n''êtes pas membre de cette distribution.';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id',            b.id,
           'commercial_id', b.commercial_id,
           'commercial',    nullif(btrim(coalesce(u.prenom, '') || ' ' ||
                                         coalesce(u.nom, '')), ''),
           'produit_id',    b.produit_id,
           'nom_produit',   b.nom_produit,
           'nature',        b.nature,
           'quantite',      b.quantite,
           'prix_unitaire', b.prix_unitaire,
           'valeur',        b.valeur,
           'motif',         b.motif,
           'justificatif',  b.justificatif,
           'statut',        b.statut,
           'motif_refus',   b.motif_refus,
           'created_at',    b.created_at
         ) order by b.created_at desc), '[]'::jsonb)
    into v_items
    from (
      select * from public.dist_bonus_dommages b0
       where b0.owner_id = v_owner
         and (p_commercial is null or b0.commercial_id = p_commercial)
         and (nullif(btrim(coalesce(p_statut, '')), '') is null
              or b0.statut = p_statut)
         -- Un commercial ne voit toujours que ses lignes.
         and (v_role <> 'commercial' or b0.commercial_id = auth.uid())
       order by b0.created_at desc
       limit v_limite
    ) b
    left join public.utilisateurs u on u.id = b.commercial_id;

  return jsonb_build_object('ok', true, 'items', v_items);
end;
$$;

-- Comparaison entre commerciaux (gérant / propriétaire / comptable).
create or replace function public.dist_bonus_resume(
  p_debut timestamptz default null,
  p_fin   timestamptz default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_owner  uuid := public.dist_owner_requis();
  v_role   text := public.dist_role();
  v_debut  timestamptz := coalesce(p_debut, date_trunc('month', now()));
  v_fin    timestamptz := coalesce(p_fin, now());
  v_items  jsonb;
begin
  if v_role not in ('proprietaire', 'gerant', 'comptable') then
    raise exception 'DROIT_REFUSE|Résumé réservé à la direction et au comptable.';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'commercial_id', x.commercial_id,
           'commercial',    x.commercial,
           'bonus_valeur',  x.bonus_valeur,
           'dommage_valeur', x.dommage_valeur,
           'total_valeur',  x.total_valeur,
           'nb_lignes',     x.nb_lignes
         ) order by x.total_valeur desc), '[]'::jsonb)
    into v_items
    from (
      select b.commercial_id,
             nullif(btrim(coalesce(u.prenom, '') || ' ' || coalesce(u.nom, '')), '') as commercial,
             coalesce(sum(case when b.nature = 'bonus' then b.valeur end), 0) as bonus_valeur,
             coalesce(sum(case when b.nature <> 'bonus' then b.valeur end), 0) as dommage_valeur,
             coalesce(sum(b.valeur), 0) as total_valeur,
             count(*) as nb_lignes
        from public.dist_bonus_dommages b
        left join public.utilisateurs u on u.id = b.commercial_id
       where b.owner_id = v_owner
         and b.statut = 'valide'
         and b.created_at between v_debut and v_fin
       group by b.commercial_id, u.prenom, u.nom
    ) x;

  return jsonb_build_object('ok', true, 'debut', v_debut, 'fin', v_fin,
                            'items', v_items);
end;
$$;

-- -----------------------------------------------------------------------------
-- 3. COÛT DE REVIENT RÉEL
-- -----------------------------------------------------------------------------
-- Coût unitaire observé par produit : somme des intrants CONSommés ET PERDUS
-- (valorisés au prix unitaire de l'intrant) divisée par les quantités reçues
-- au stock. `cout_complet = false` dès qu'un intrant n'a pas de prix : on ne
-- fabrique jamais une marge.
create or replace function public.dist_cout_revient(
  p_produit uuid default null,
  p_limite  integer default 50
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_owner  uuid := public.dist_owner_requis();
  v_limite integer := least(greatest(coalesce(p_limite, 50), 1), 200);
  v_items  jsonb;
begin
  if public.dist_role() = 'aucun' then
    raise exception 'ACCES_REFUSE|Vous n''êtes pas membre de cette distribution.';
  end if;

  with prod as (
    select pr.id, pr.owner_id, pr.cree_le
      from public.dist_productions pr
     where pr.owner_id = v_owner
  ),
  cout_intrants as (
    select pi.production_id,
           sum((pi.quantite_consommee + pi.quantite_perdue) * coalesce(i.prix_unitaire, 0)) as cout,
           bool_and(coalesce(i.prix_unitaire, 0) > 0) as complet
      from public.dist_production_intrants pi
      join public.dist_intrants i on i.id = pi.intrant_id
     group by pi.production_id
  ),
  sorties as (
    select s.production_id, s.produit_id,
           coalesce(nullif(s.quantite_recue, 0), s.quantite_produite) as qte
      from public.dist_production_sorties s
  ),
  par_produit as (
    select s.produit_id,
           sum(c.cout)              as cout_total,
           sum(s.qte)               as qte_totale,
           bool_and(coalesce(c.complet, false)) as complet,
           min(p.cree_le)           as premier,
           max(p.cree_le)           as dernier
      from sorties s
      join prod p on p.id = s.production_id
      left join cout_intrants c on c.production_id = s.production_id
     where s.qte > 0
     group by s.produit_id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'produit_id',   pp.produit_id,
           'produit',      pd.nom,
           'format',       pd.format,
           'unite',        pd.unite,
           'quantite',     pp.qte_totale,
           'cout_total',   pp.cout_total,
           'cout_unitaire', case when pp.qte_totale > 0
                                 then round(pp.cout_total / pp.qte_totale, 4)
                                 else null end,
           'prix_vente',   pd.prix_vente,
           'marge_unitaire', case
              when pp.qte_totale > 0 and coalesce(pp.complet, false)
              then round(pd.prix_vente - (pp.cout_total / pp.qte_totale), 2)
              else null end,
           'marge_pct',    case
              when pp.qte_totale > 0 and coalesce(pp.complet, false)
                   and pd.prix_vente > 0
              then round(100 * (pd.prix_vente - (pp.cout_total / pp.qte_totale))
                         / pd.prix_vente, 1)
              else null end,
           'cout_complet', coalesce(pp.complet, false),
           'derniere_production', pp.dernier
         ) order by pd.nom), '[]'::jsonb)
    into v_items
    from (
      select * from par_produit
       where (p_produit is null or produit_id = p_produit)
       order by dernier desc
       limit v_limite
    ) pp
    join public.dist_produits pd on pd.id = pp.produit_id;

  return jsonb_build_object('ok', true, 'items', v_items);
end;
$$;

comment on function public.dist_cout_revient(uuid, integer) is
  'Module 24 §11 — coût de revient unitaire observé (intrants consommés + perdus) et marge ; cout_complet=false si un prix manque.';

-- -----------------------------------------------------------------------------
-- 4. RENTABILITÉ SUR UNE PÉRIODE (produits, commerciaux, pertes)
-- -----------------------------------------------------------------------------
create or replace function public.dist_rentabilite(
  p_debut timestamptz default null,
  p_fin   timestamptz default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_owner  uuid := public.dist_owner_requis();
  v_role   text := public.dist_role();
  v_debut  timestamptz := coalesce(p_debut, date_trunc('month', now()));
  v_fin    timestamptz := coalesce(p_fin, now());
  v_couts  jsonb;
  v_prod   jsonb;
  v_comm   jsonb;
  v_perd   jsonb;
  v_ca     numeric := 0;
  v_cout   numeric := 0;
  v_incomplet boolean := false;
begin
  if v_role not in ('proprietaire', 'gerant', 'comptable') then
    raise exception 'DROIT_REFUSE|Analyse réservée à la direction et au comptable.';
  end if;

  v_couts := public.dist_cout_revient(null, 200);

  -- Chiffre d'affaires par commercial.
  select coalesce(jsonb_agg(jsonb_build_object(
           'commercial_id', v.commercial_id,
           'commercial',    v.commercial,
           'ca',            v.ca,
           'nb_ventes',     v.nb
         ) order by v.ca desc), '[]'::jsonb),
         coalesce(sum(v.ca), 0)
    into v_comm, v_ca
    from (
      select s.commercial_id,
             nullif(btrim(coalesce(u.prenom, '') || ' ' || coalesce(u.nom, '')), '') as commercial,
             coalesce(sum(s.total), 0) as ca,
             count(*) as nb
        from public.dist_ventes s
        left join public.utilisateurs u on u.id = s.commercial_id
       where s.owner_id = v_owner
         and s.date_vente between v_debut and v_fin
       group by s.commercial_id, u.prenom, u.nom
    ) v;

  -- Coût des produits vendus (quantité × coût de revient du produit).
  with couts as (
    select (item->>'produit_id')::uuid as produit_id,
           (item->>'cout_unitaire')::numeric as cout_unitaire,
           (item->>'cout_complet')::boolean as complet
      from jsonb_array_elements(v_couts->'items') item
  ),
  ventes_lignes as (
    select l.produit_id, sum(l.quantite) as qte
      from public.dist_vente_lignes l
      join public.dist_ventes v on v.id = l.vente_id
     where v.owner_id = v_owner
       and v.date_vente between v_debut and v_fin
     group by l.produit_id
  )
  select coalesce(sum(vl.qte * coalesce(c.cout_unitaire, 0)), 0),
         coalesce(bool_or(c.produit_id is null or coalesce(c.complet, false) = false), false),
         coalesce(jsonb_agg(jsonb_build_object(
           'produit_id', vl.produit_id,
           'quantite',   vl.qte,
           'cout_unitaire', c.cout_unitaire
         )), '[]'::jsonb)
    into v_cout, v_incomplet, v_prod
    from ventes_lignes vl
    left join couts c on c.produit_id = vl.produit_id;

  -- Bonus et dommages validés (hors ventes, jamais additionnés au CA).
  select coalesce(sum(valeur), 0) into v_perd
    from public.dist_bonus_dommages
   where owner_id = v_owner
     and statut = 'valide'
     and created_at between v_debut and v_fin;

  return jsonb_build_object(
    'ok',            true,
    'debut',         v_debut,
    'fin',           v_fin,
    'ca',            v_ca,
    'cout_marchandises', round(v_cout, 2),
    'marge_brute',   round(v_ca - v_cout, 2),
    'marge_pct',     case when v_ca > 0
                          then round(100 * (v_ca - v_cout) / v_ca, 1)
                          else null end,
    'bonus_dommages', round(v_perd, 2),
    'cout_complet',  not v_incomplet,
    'par_commercial', v_comm,
    'produits',      v_couts->'items',
    'cout_marchandises_detail', v_prod
  );
end;
$$;

comment on function public.dist_rentabilite(timestamptz, timestamptz) is
  'Module 24 §11 — CA, coût des marchandises, marge, bonus/dommages et détail par commercial sur une période.';

-- -----------------------------------------------------------------------------
-- 5. PRIVILÈGES
-- -----------------------------------------------------------------------------
do $$
declare
  f text;
begin
  foreach f in array array[
    'dist_tarif_enregistrer(uuid, text, numeric, text, boolean)',
    'dist_tarifs_lister(uuid)',
    'dist_bonus_declarer(uuid, text, numeric, text, text, uuid)',
    'dist_bonus_valider(uuid, boolean, text)',
    'dist_bonus_lister(uuid, text, integer)',
    'dist_bonus_resume(timestamptz, timestamptz)',
    'dist_cout_revient(uuid, integer)',
    'dist_rentabilite(timestamptz, timestamptz)'
  ]
  loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;

-- =============================================================================
-- FIN — Module 24, compléments 2
-- =============================================================================
