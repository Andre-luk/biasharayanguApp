-- ============================================================================
--  biashara_yangu — MODULE 9 : GESTION DU STOCK (conversions multi-unités)
--
--  Ce script complète les tables de stock existantes :
--
--    1. `public.produits.seuil_alerte`  — seuil d'alerte PAR ARTICLE (défaut 5),
--       utilisé par l'écran Stock (statut OK / Faible / Rupture) ;
--    2. `public.approvisionnements.fournisseur` — le fournisseur de l'entrée ;
--    3. `public.inventaires_quotidiens.ecart`   — écart calculé AUTOMATIQUEMENT
--       (quantité physique − quantité théorique) par la base ;
--    4. `rpc_stock_definir_seuil`      — modifier le seuil d'un article ;
--    5. `rpc_stock_approvisionner`     — ENTRÉE de stock tracée ;
--    6. `rpc_stock_ajuster`            — AJUSTEMENT d'inventaire, raison OBLIGATOIRE ;
--    7. `rpc_inventaire_cloturer`      — CLÔTURE quotidienne : enregistre les
--       comptages dans `inventaires_quotidiens` et corrige les écarts.
--
--  ⚠️ LE STOCK EST TOUJOURS DÉCRÉMENTÉ / INCRÉMENTÉ PAR LES TRIGGERS EXISTANTS
--     DES TABLES DE MOUVEMENTS (vérifié le 2026-09-16 par sonde réelle) :
--
--       • insert `ventes`            -> `produits.quantite` −= quantite ;
--       • insert `approvisionnements`-> `produits.quantite` += quantite_ajoutee ;
--       • insert `ajustements`       -> `produits.quantite` += quantite (delta) ;
--       • DELETE d'un mouvement      -> AUCUN recalcul (l'historique est figé).
--
--     Les fonctions ci-dessous n'écrivent donc JAMAIS `produits.quantite`
--     directement : elles insèrent le mouvement, le trigger fait le reste.
--     Un décrément/incrément « à la main » doublerait le mouvement.
--
--  OÙ L'EXÉCUTER
--    Supabase Dashboard → SQL Editor → New query → coller → Run
--
--  PRÉ-REQUIS
--    Modules 4 et 5 exécutés : ce script réutilise `public.peut(...)`,
--    `public.est_plateforme()` (Module 4) et `public.mon_proprietaire()`
--    (Module 5). Module 8 recommandé (mêmes conventions, ventes historisées).
--
--  ⚠️ IDEMPOTENT : peut être relancé sans dupliquer ni détruire de données.
--     Les policies existantes des tables de mouvements sont CONSERVÉES :
--     ce script ajoute les siennes (préfixe `m9_`) sans rien supprimer.
-- ============================================================================


select set_config('search_path', 'public, extensions', true);

-- Contrôle préalable : Modules 4 et 5 en place.
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
end $$;


-- ============================================================================
--  1. NOUVELLES COLONNES
-- ============================================================================

-- 1.a Seuil d'alerte par article --------------------------------------------
--  Un article passe en « Faible » dès que son stock atteint ce seuil, et en
--  « Rupture » à zéro. La valeur par défaut (5) correspond au comportement
--  historique de l'application.
alter table public.produits
  add column if not exists seuil_alerte real not null default 5;

comment on column public.produits.seuil_alerte is
  'Seuil d''alerte du stock (unités de base) : en dessous ou égal, l''article est « Faible » ; à 0, « Rupture ».';

-- 1.b Fournisseur de l'approvisionnement -------------------------------------
alter table public.approvisionnements
  add column if not exists fournisseur text;

comment on column public.approvisionnements.fournisseur is
  'Nom du fournisseur de l''entrée de stock (facultatif).';

-- 1.c Écart d'inventaire — CALCULÉ PAR LA BASE --------------------------------
--  Colonne générée : la base recalcule l'écart à chaque écriture, quelle que
--  soit la source (application, synchronisation de l'ancienne caisse, SQL
--  manuel). Un écart non saisi (physique NULL) vaut 0.
alter table public.inventaires_quotidiens
  add column if not exists ecart real
    generated always as (
      coalesce(quantite_physique, quantite_theorique) - quantite_theorique
    ) stored;

comment on column public.inventaires_quotidiens.ecart is
  'Écart d''inventaire calculé : quantité physique − quantité théorique (colonne générée).';

-- 1.d Index d'historique -------------------------------------------------------
create index if not exists idx_approvisionnements_owner_date
  on public.approvisionnements (owner_id, date_approvisionnement desc);
create index if not exists idx_ajustements_owner_date
  on public.ajustements (owner_id, date desc);
create index if not exists idx_inventaires_owner_date
  on public.inventaires_quotidiens (owner_id, date_cloture desc);


-- ============================================================================
--  2. `rpc_stock_definir_seuil` — SEUIL D'ALERTE CONFIGURABLE
-- ============================================================================
--  Le seuil appartient au catalogue : l'écran « Détail stock article » peut
--  le modifier à tout moment. Écriture par RPC (security definer) pour que
--  le contrôle des droits `stock/modifier` soit fait côté serveur, même si
--  les policies de `produits` évoluent.

create or replace function public.rpc_stock_definir_seuil(
  p_produit_id bigint,
  p_seuil      numeric
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user    uuid := auth.uid();
  v_owner   uuid;
  v_produit record;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour modifier le stock.';
  end if;

  if not (public.peut('stock', 'modifier') or public.est_plateforme()) then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de modifier le stock.';
  end if;

  if p_seuil is null or p_seuil < 0 then
    raise exception 'SEUIL_INVALIDE|Le seuil d''alerte doit être un nombre positif ou nul.';
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  select p.id, p.nom, p.owner_id
    into v_produit
    from public.produits p
   where p.id = p_produit_id
     for update;

  if not found then
    raise exception 'PRODUIT_INTROUVABLE|Article n° % introuvable : il a peut-être été supprimé.', p_produit_id;
  end if;

  if v_produit.owner_id is distinct from v_owner
     and not public.est_plateforme() then
    raise exception 'HORS_BOUTIQUE|L''article % n''appartient pas à votre boutique.', v_produit.nom;
  end if;

  update public.produits
     set seuil_alerte = p_seuil
   where id = p_produit_id;

  return jsonb_build_object(
    'produit_id',    p_produit_id,
    'nom',           v_produit.nom,
    'seuil_alerte',  p_seuil
  );
end;
$$;

comment on function public.rpc_stock_definir_seuil(bigint, numeric) is
  'Définit le seuil d''alerte d''un article (droit stock/modifier).';


-- ============================================================================
--  3. `rpc_stock_approvisionner` — ENTRÉE DE STOCK TRACÉE
-- ============================================================================
--  Signature :
--    p_produit_id   bigint  — article approvisionné ;
--    p_quantite     numeric — quantité AJOUTÉE, en UNITÉS DE BASE
--                             (l'application convertit les conditionnements
--                              avant l'appel : 10 fardes de 12 → 120) ;
--    p_prix_achat_unitaire numeric — prix d'achat de l'unité de base ;
--    p_fournisseur  text    — facultatif ;
--    p_date_approvisionnement timestamptz — facultatif (défaut : maintenant).
--
--  Déroulé (une transaction) :
--    1. session + droit `stock/creer` ;
--    2. verrou de l'article, contrôle boutique, quantités ;
--    3. insert `approvisionnements` → le trigger ajoute les unités de base ;
--    4. journal d'audit `APPROVISIONNEMENT` ;
--    5. retour jsonb : stock avant / après, fournisseur…
--
--  Codes d'erreur : SESSION_ABSENTE | DROIT_REFUSE | PRODUIT_INTROUVABLE |
--                   HORS_BOUTIQUE | QUANTITE_INVALIDE | PRIX_INVALIDE

create or replace function public.rpc_stock_approvisionner(
  p_produit_id          bigint,
  p_quantite            numeric,
  p_prix_achat_unitaire numeric default 0,
  p_fournisseur         text default null,
  p_date_approvisionnement timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user        uuid := auth.uid();
  v_owner       uuid;
  v_produit     record;
  v_fournisseur text := nullif(btrim(coalesce(p_fournisseur, '')), '');
  v_prix        numeric := coalesce(p_prix_achat_unitaire, 0);
  v_date        timestamptz := coalesce(p_date_approvisionnement, now());
  v_avant       numeric;
  v_apres       numeric;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour gérer le stock.';
  end if;

  if not (public.peut('stock', 'creer') or public.est_plateforme()) then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas d''enregistrer une entrée de stock.';
  end if;

  if p_quantite is null or p_quantite <= 0 then
    raise exception 'QUANTITE_INVALIDE|La quantité ajoutée doit être supérieure à zéro.';
  end if;

  if v_prix < 0 then
    raise exception 'PRIX_INVALIDE|Le prix d''achat ne peut pas être négatif.';
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  select p.id, p.nom, p.owner_id, coalesce(p.quantite, 0) as quantite
    into v_produit
    from public.produits p
   where p.id = p_produit_id
     for update;

  if not found then
    raise exception 'PRODUIT_INTROUVABLE|Article n° % introuvable : il a peut-être été supprimé.', p_produit_id;
  end if;

  if v_produit.owner_id is distinct from v_owner
     and not public.est_plateforme() then
    raise exception 'HORS_BOUTIQUE|L''article % n''appartient pas à votre boutique.', v_produit.nom;
  end if;

  v_avant := v_produit.quantite;

  -- Le trigger de `approvisionnements` ajoute `p_quantite` unités de base.
  insert into public.approvisionnements (
    produit_id, quantite_ajoutee, prix_achat_unitaire,
    fournisseur, date_approvisionnement, owner_id
  ) values (
    p_produit_id, p_quantite, v_prix,
    v_fournisseur, v_date, v_owner
  );

  select coalesce(p.quantite, 0)
    into v_apres
    from public.produits p
   where p.id = p_produit_id;

  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(),
    null,
    'APPROVISIONNEMENT',
    v_user,
    jsonb_build_object(
      'produit_id',   p_produit_id,
      'produit',      v_produit.nom,
      'quantite',     p_quantite,
      'prix_achat',   v_prix,
      'fournisseur',  v_fournisseur,
      'stock_avant',  v_avant,
      'stock_apres',  v_apres,
      'boutique',     v_owner
    ),
    now()
  );

  return jsonb_build_object(
    'produit_id',      p_produit_id,
    'nom',             v_produit.nom,
    'quantite_ajoutee', p_quantite,
    'prix_achat_unitaire', v_prix,
    'fournisseur',     v_fournisseur,
    'date',            v_date,
    'stock_avant',     v_avant,
    'stock_apres',     v_apres
  );
end;
$$;

comment on function public.rpc_stock_approvisionner(bigint, numeric, numeric, text, timestamptz) is
  'Enregistre une entrée de stock (approvisionnement) : le trigger serveur ajoute la quantité, l''opération est journalisée.';


-- ============================================================================
--  4. `rpc_stock_ajuster` — AJUSTEMENT D'INVENTAIRE (RAISON OBLIGATOIRE)
-- ============================================================================
--  L'application envoie la QUANTITÉ PHYSIQUE comptée (pas le delta) : le
--  serveur calcule l'écart « physique − théorique » et l'insère dans
--  `public.ajustements` (le trigger applique le delta au stock).
--
--  La raison est OBLIGATOIRE (exigence du cahier des charges) : sans elle,
--  l'ajustement est refusé.
--
--  Codes d'erreur : SESSION_ABSENTE | DROIT_REFUSE | PRODUIT_INTROUVABLE |
--                   HORS_BOUTIQUE | QUANTITE_INVALIDE | RAISON_OBLIGATOIRE |
--                   AUCUN_ECART

create or replace function public.rpc_stock_ajuster(
  p_produit_id        bigint,
  p_quantite_physique numeric,
  p_raison            text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user      uuid := auth.uid();
  v_owner     uuid;
  v_produit   record;
  v_raison    text := btrim(coalesce(p_raison, ''));
  v_avant     numeric;
  v_delta     numeric;
  v_apres     numeric;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour gérer le stock.';
  end if;

  if not (public.peut('stock', 'modifier') or public.est_plateforme()) then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas d''ajuster le stock.';
  end if;

  if length(v_raison) < 3 then
    raise exception 'RAISON_OBLIGATOIRE|Indiquez la raison de l''ajustement (3 caractères minimum).';
  end if;

  if p_quantite_physique is null or p_quantite_physique < 0 then
    raise exception 'QUANTITE_INVALIDE|La quantité physique doit être un nombre positif ou nul.';
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  select p.id, p.nom, p.owner_id, coalesce(p.quantite, 0) as quantite
    into v_produit
    from public.produits p
   where p.id = p_produit_id
     for update;

  if not found then
    raise exception 'PRODUIT_INTROUVABLE|Article n° % introuvable : il a peut-être été supprimé.', p_produit_id;
  end if;

  if v_produit.owner_id is distinct from v_owner
     and not public.est_plateforme() then
    raise exception 'HORS_BOUTIQUE|L''article % n''appartient pas à votre boutique.', v_produit.nom;
  end if;

  v_avant := v_produit.quantite;
  v_delta := p_quantite_physique - v_avant;

  if v_delta = 0 then
    raise exception 'AUCUN_ECART|Aucun écart à corriger : la quantité saisie est identique au stock actuel.';
  end if;

  -- Le trigger de `ajustements` applique `v_delta` au stock (signé).
  insert into public.ajustements (
    produit_id, quantite, raison, date, owner_id
  ) values (
    p_produit_id, v_delta, v_raison, now(), v_owner
  );

  select coalesce(p.quantite, 0)
    into v_apres
    from public.produits p
   where p.id = p_produit_id;

  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(),
    null,
    'AJUSTEMENT',
    v_user,
    jsonb_build_object(
      'produit_id',  p_produit_id,
      'produit',     v_produit.nom,
      'delta',       v_delta,
      'raison',      v_raison,
      'stock_avant', v_avant,
      'stock_apres', v_apres,
      'boutique',    v_owner
    ),
    now()
  );

  return jsonb_build_object(
    'produit_id',  p_produit_id,
    'nom',         v_produit.nom,
    'delta',       v_delta,
    'raison',      v_raison,
    'stock_avant', v_avant,
    'stock_apres', v_apres
  );
end;
$$;

comment on function public.rpc_stock_ajuster(bigint, numeric, text) is
  'Corrige le stock d''un article vers la quantité physique comptée (raison obligatoire), mouvement tracé dans ajustements.';


-- ============================================================================
--  5. `rpc_inventaire_cloturer` — CLÔTURE QUOTIDIENNE
-- ============================================================================
--  Signature :
--    p_lignes      jsonb — [{produit_id, quantite_physique}] (articles COMPTÉS) ;
--    p_date_cloture date — défaut : aujourd'hui ;
--    p_ajuster     boolean — true (défaut) : les écarts sont corrigés par des
--                   ajustements « Inventaire quotidien du JJ/MM/AAAA ».
--
--  Déroulé (une transaction) :
--    1. session + droit `stock/modifier` ;
--    2. verrous ORDONNÉS des articles du comptage (anti-interblocage) ;
--    3. pour chaque ligne : lecture du stock théorique (SOUS VERROU),
--       insert `inventaires_quotidiens` (théorique, physique, écart généré),
--       et — si demandé — ajustement de l'écart ;
--    4. journal d'audit `INVENTAIRE` ;
--    5. retour jsonb détaillé (écarts par article + totaux).
--
--  Codes d'erreur : SESSION_ABSENTE | DROIT_REFUSE | PANIER_VIDE (aucune
--                   ligne) | LIGNE_INVALIDE | QUANTITE_INVALIDE |
--                   PRODUIT_INTROUVABLE | HORS_BOUTIQUE

create or replace function public.rpc_inventaire_cloturer(
  p_lignes       jsonb,
  p_date_cloture date default current_date,
  p_ajuster      boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user         uuid := auth.uid();
  v_owner        uuid;
  v_date         date := coalesce(p_date_cloture, current_date);
  v_raison       text;
  v_ligne        jsonb;
  v_produit_id   bigint;
  v_produit      record;
  v_physique     numeric;
  v_theorique    numeric;
  v_ecart        numeric;
  v_nb_lignes    integer := 0;
  v_nb_ecarts    integer := 0;
  v_ecart_net    numeric := 0;
  v_lignes_retour jsonb := '[]'::jsonb;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour clôturer l''inventaire.';
  end if;

  if not (public.peut('stock', 'modifier') or public.est_plateforme()) then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de clôturer un inventaire.';
  end if;

  if p_lignes is null
     or jsonb_typeof(p_lignes) <> 'array'
     or jsonb_array_length(p_lignes) = 0 then
    raise exception 'LIGNE_INVALIDE|Aucun article compté : saisissez au moins une quantité physique.';
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  v_raison := 'Inventaire quotidien du ' || to_char(v_date, 'DD/MM/YYYY');

  -- Verrouillage de TOUS les articles comptés, ids croissants : deux
  -- clôtures simultanées ne peuvent pas s'interbloquer.
  perform p.id
     from public.produits p
    where p.id in (
      select distinct (l->>'produit_id')::bigint
        from jsonb_array_elements(p_lignes) as l
    )
    order by p.id
      for update;

  for v_ligne in select * from jsonb_array_elements(p_lignes)
  loop
    v_produit_id := nullif(v_ligne->>'produit_id', '')::bigint;
    if v_produit_id is null then
      raise exception 'LIGNE_INVALIDE|Une ligne du comptage n''a pas d''article.';
    end if;

    v_physique := (v_ligne->>'quantite_physique')::numeric;
    if v_physique is null or v_physique < 0 then
      raise exception 'QUANTITE_INVALIDE|Quantité physique invalide pour l''article %.', v_produit_id;
    end if;

    select p.id, p.nom, p.owner_id, coalesce(p.quantite, 0) as quantite,
           p.unite_mesure
      into v_produit
      from public.produits p
     where p.id = v_produit_id;

    if not found then
      raise exception 'PRODUIT_INTROUVABLE|Article n° % introuvable : il a peut-être été supprimé.', v_produit_id;
    end if;

    if v_produit.owner_id is distinct from v_owner
       and not public.est_plateforme() then
      raise exception 'HORS_BOUTIQUE|L''article % n''appartient pas à votre boutique.', v_produit.nom;
    end if;

    v_theorique := v_produit.quantite;
    v_ecart     := v_physique - v_theorique;

    -- Traçabilité : chaque comptage est conservé (`ecart` est généré).
    insert into public.inventaires_quotidiens (
      owner_id, produit_id, quantite_theorique, quantite_physique,
      date_cloture, is_synced
    ) values (
      v_owner, v_produit_id, v_theorique, v_physique,
      v_date, 1
    );

    -- Correction de l'écart par un ajustement tracé (si demandé).
    if v_ecart <> 0 then
      v_nb_ecarts := v_nb_ecarts + 1;
      v_ecart_net := v_ecart_net + v_ecart;

      if p_ajuster then
        insert into public.ajustements (
          produit_id, quantite, raison, date, owner_id
        ) values (
          v_produit_id, v_ecart, v_raison, now(), v_owner
        );
      end if;
    end if;

    v_nb_lignes := v_nb_lignes + 1;

    v_lignes_retour := v_lignes_retour || jsonb_build_object(
      'produit_id', v_produit_id,
      'nom',        v_produit.nom,
      'unite',      v_produit.unite_mesure,
      'theorique',  v_theorique,
      'physique',   v_physique,
      'ecart',      v_ecart,
      'ajuste',     (p_ajuster and v_ecart <> 0)
    );
  end loop;

  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(),
    null,
    'INVENTAIRE',
    v_user,
    jsonb_build_object(
      'date_cloture', v_date,
      'nb_lignes',    v_nb_lignes,
      'nb_ecarts',    v_nb_ecarts,
      'ecart_net',    v_ecart_net,
      'ajustements',  p_ajuster,
      'boutique',     v_owner
    ),
    now()
  );

  return jsonb_build_object(
    'date_cloture',     v_date,
    'nb_lignes',        v_nb_lignes,
    'nb_ecarts',        v_nb_ecarts,
    'ecart_net',        v_ecart_net,
    'ajustements_crees', p_ajuster,
    'lignes',           v_lignes_retour
  );
end;
$$;

comment on function public.rpc_inventaire_cloturer(jsonb, date, boolean) is
  'Clôture l''inventaire quotidien : enregistre les comptages et corrige les écarts par des ajustements tracés.';


-- ============================================================================
--  6. DROITS D'EXÉCUTION DES RPC
-- ============================================================================

revoke all on function public.rpc_stock_definir_seuil(bigint, numeric) from public;
grant execute on function public.rpc_stock_definir_seuil(bigint, numeric) to authenticated;

revoke all on function public.rpc_stock_approvisionner(bigint, numeric, numeric, text, timestamptz) from public;
grant execute on function public.rpc_stock_approvisionner(bigint, numeric, numeric, text, timestamptz) to authenticated;

revoke all on function public.rpc_stock_ajuster(bigint, numeric, text) from public;
grant execute on function public.rpc_stock_ajuster(bigint, numeric, text) to authenticated;

revoke all on function public.rpc_inventaire_cloturer(jsonb, date, boolean) from public;
grant execute on function public.rpc_inventaire_cloturer(jsonb, date, boolean) to authenticated;


-- ============================================================================
--  7. RLS DES TABLES DE MOUVEMENTS (ajouts NON destructifs)
-- ============================================================================
--  Les policies existantes (ancienne application) sont CONSERVÉES : ce bloc
--  ajoute des policies préfixées `m9_` (rejouable sans erreur) qui :
--    • laissent chaque boutique LIRE ses mouvements (propriétaire, personnel,
--      plateforme) — nécessaire à l'historique du Module 9 ;
--    • laissent l'ancienne caisse INSÉRER ses mouvements hors ligne une fois
--      synchronisée (comportement historique conservé).
--  Les écritures du Module 9 passent, elles, par les RPC (security definer).

alter table public.approvisionnements enable row level security;
alter table public.ajustements enable row level security;
alter table public.inventaires_quotidiens enable row level security;

do $$
begin
  -- ---- approvisionnements -------------------------------------------------
  execute 'drop policy if exists m9_appro_lecture on public.approvisionnements';
  execute 'create policy m9_appro_lecture on public.approvisionnements
             for select to authenticated
             using (
               owner_id = auth.uid()
               or owner_id = public.mon_proprietaire()
               or public.est_plateforme()
             )';

  execute 'drop policy if exists m9_appro_insertion on public.approvisionnements';
  execute 'create policy m9_appro_insertion on public.approvisionnements
             for insert to authenticated
             with check (
               owner_id = auth.uid()
               or owner_id = public.mon_proprietaire()
               or public.est_plateforme()
             )';

  -- ---- ajustements ----------------------------------------------------------
  execute 'drop policy if exists m9_ajust_lecture on public.ajustements';
  execute 'create policy m9_ajust_lecture on public.ajustements
             for select to authenticated
             using (
               owner_id = auth.uid()
               or owner_id = public.mon_proprietaire()
               or public.est_plateforme()
             )';

  execute 'drop policy if exists m9_ajust_insertion on public.ajustements';
  execute 'create policy m9_ajust_insertion on public.ajustements
             for insert to authenticated
             with check (
               owner_id = auth.uid()
               or owner_id = public.mon_proprietaire()
               or public.est_plateforme()
             )';

  -- ---- inventaires_quotidiens ------------------------------------------------
  execute 'drop policy if exists m9_inventaire_lecture on public.inventaires_quotidiens';
  execute 'create policy m9_inventaire_lecture on public.inventaires_quotidiens
             for select to authenticated
             using (
               owner_id = auth.uid()
               or owner_id = public.mon_proprietaire()
               or public.est_plateforme()
             )';

  execute 'drop policy if exists m9_inventaire_insertion on public.inventaires_quotidiens';
  execute 'create policy m9_inventaire_insertion on public.inventaires_quotidiens
             for insert to authenticated
             with check (
               owner_id = auth.uid()
               or owner_id = public.mon_proprietaire()
               or public.est_plateforme()
             )';

  execute 'drop policy if exists m9_inventaire_mise_a_jour on public.inventaires_quotidiens';
  execute 'create policy m9_inventaire_mise_a_jour on public.inventaires_quotidiens
             for update to authenticated
             using (
               owner_id = auth.uid()
               or owner_id = public.mon_proprietaire()
               or public.est_plateforme()
             )
             with check (
               owner_id = auth.uid()
               or owner_id = public.mon_proprietaire()
               or public.est_plateforme()
             )';
end $$;


-- ============================================================================
--  8. VÉRIFICATIONS
-- ============================================================================

-- 8.a Nouvelles colonnes
select table_name, column_name, data_type, is_nullable
  from information_schema.columns
 where table_schema = 'public'
   and (
     (table_name = 'produits' and column_name = 'seuil_alerte')
     or (table_name = 'approvisionnements' and column_name = 'fournisseur')
     or (table_name = 'inventaires_quotidiens' and column_name = 'ecart')
   )
 order by table_name;

-- 8.b Fonctions du module
select p.proname, pg_get_function_arguments(p.oid) as arguments
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname in (
     'rpc_stock_definir_seuil',
     'rpc_stock_approvisionner',
     'rpc_stock_ajuster',
     'rpc_inventaire_cloturer'
   )
 order by p.proname;

-- 8.c Policies du module (doivent commencer par `m9_`)
select tablename, policyname, cmd
  from pg_policies
 where schemaname = 'public'
   and tablename in ('approvisionnements', 'ajustements', 'inventaires_quotidiens')
 order by tablename, policyname;


-- ============================================================================
--  9. CONTRÔLES MANUELS UTILES (à exécuter au besoin, compte connecté)
-- ============================================================================

-- Seuil d'alerte (remplacer <ID_ARTICLE>) :
--
-- select public.rpc_stock_definir_seuil(<ID_ARTICLE>, 10);
--
-- Entrée de stock : +10 unités de base à 100 CDF/unité, fournisseur « Éts Kabila » :
--
-- select public.rpc_stock_approvisionner(<ID_ARTICLE>, 10, 100, 'Éts Kabila');
--
-- Ajustement : le stock physique compte 8 unités (raison obligatoire) :
--
-- select public.rpc_stock_ajuster(<ID_ARTICLE>, 8, 'Casse pendant manutention');
--
-- Clôture d'inventaire (2 articles comptés, écarts corrigés) :
--
-- select public.rpc_inventaire_cloturer(
--   jsonb_build_array(
--     jsonb_build_object('produit_id', <ID_ARTICLE>, 'quantite_physique', 8),
--     jsonb_build_object('produit_id', <ID_ARTICLE_2>, 'quantite_physique', 3)
--   ),
--   current_date,
--   true
-- );
--
-- Vérifier les mouvements et le journal :
--
--   select * from public.approvisionnements order by id desc limit 5;
--   select * from public.ajustements order by id desc limit 5;
--   select * from public.inventaires_quotidiens order by id desc limit 5;
--   select action, details from public.journal_audit
--    where action in ('APPROVISIONNEMENT', 'AJUSTEMENT', 'INVENTAIRE')
--    order by created_at desc limit 5;
