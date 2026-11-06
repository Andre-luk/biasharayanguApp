-- ============================================================================
--  biashara_yangu — MODULE 25 : FLEXIBILITÉ COMMERCIALE DE LA BOUTIQUE
--  ---------------------------------------------------------------------------
--  CE QUE LE COMMERÇANT DEMANDE (05/11/2026)
--    « Le prix enregistré n'est pas forcément le prix auquel je vends. »
--      • négocier le prix d'une ligne pendant la vente ;
--      • accorder une réduction sur le total du panier ;
--      • offrir un ou plusieurs produits (cadeau commercial) ;
--      • cumuler les trois, et tout retrouver sur la facture et dans les
--        rapports — sans jamais modifier le prix du catalogue.
--
--  CE QUE CE SCRIPT AJOUTE (aucune table existante n'est remplacée)
--    1. `public.parametres_vente`      — les réglages du propriétaire ;
--    2. `public.ventes`                — prix catalogue, prix négocié,
--                                        cadeau, référence hors ligne ;
--    3. `public.caisse`                — montant initial, réduction ;
--    4. `public.ventes_flexibilite`    — la TRACE d'une vente flexible ;
--    5. `rpc_vente_valider`            — LA MÊME transaction, enrichie ;
--    6. `boutique_parametres_vente_*`  — lire / enregistrer les réglages ;
--    7. `boutique_ventes_flexibilite_resume` — les rapports.
--
--  ⚠️ RÈGLES RESPECTÉES
--    • le prix du catalogue (`produits.prix_vente`) n'est JAMAIS modifié ;
--    • le stock reste décrémenté par le trigger existant de `ventes` : un
--      cadeau est une ligne de vente à 0, donc une sortie de stock réelle ;
--    • un cadeau n'entre jamais dans la caisse (montant 0) ni dans le
--      chiffre d'affaires (somme des `prix` = 0) ;
--    • une vente sans négociation, réduction ni cadeau se comporte
--      EXACTEMENT comme avant (mêmes paramètres par défaut) ;
--    • idempotence hors ligne : `ventes.reference_locale` unique par
--      boutique — une vente rejouée renvoie la vente déjà enregistrée.
--
--  OÙ L'EXÉCUTER
--    Supabase Dashboard → SQL Editor → New query → coller → Run
--
--  PRÉ-REQUIS : modules 4, 5, 8 (déjà en place).
--  ⚠️ IDEMPOTENT : peut être relancé sans dupliquer ni détruire de données.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);

do $$
begin
  if not exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where p.proname = 'peut' and n.nspname = 'public'
  ) then
    raise exception
      'Module 4 absent : exécutez d''abord 20260916000006_module4_permissions.sql.';
  end if;
  if not exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where p.proname = 'rpc_vente_valider' and n.nspname = 'public'
  ) then
    raise exception
      'Module 8 absent : exécutez d''abord 20260916000009_module8_ventes.sql.';
  end if;
end $$;


-- ============================================================================
--  1. `public.parametres_vente` — LE CONTRÔLE DU PROPRIÉTAIRE
-- ============================================================================
--  Une ligne par boutique. Tant qu'elle n'existe pas, TOUT est désactivé :
--  le comportement de la boutique reste celui d'avant ce module.

create table if not exists public.parametres_vente (
  owner_id                    uuid primary key,
  negociation_activee         boolean not null default false,
  -- Réduction maximale consentie sur une ligne, en % du prix catalogue.
  negociation_max_pct         numeric not null default 10,
  -- Plancher absolu facultatif (prix unitaire le plus bas accepté).
  negociation_prix_min        numeric,
  -- Liste blanche : vide = tous les collaborateurs autorisés à encaisser.
  negociation_collaborateurs  uuid[] not null default '{}'::uuid[],
  reduction_activee           boolean not null default false,
  reduction_max_pct           numeric not null default 10,
  reduction_max_montant       numeric,
  reduction_collaborateurs    uuid[] not null default '{}'::uuid[],
  cadeaux_actifs              boolean not null default false,
  cadeau_collaborateurs       uuid[] not null default '{}'::uuid[],
  -- Règles de bonus AUTOMATIQUE :
  --   [{"seuil_montant": 10000, "produit_id": 12, "quantite": 1, "actif": true}]
  --  Un achat d'au moins `seuil_montant` déclenche le cadeau, une seule fois
  --  par vente (jamais deux attributions de la même règle).
  bonus_auto                  jsonb not null default '[]'::jsonb,
  -- Au-delà de ce montant (réduction + négociation), le responsable doit
  -- valider : la vente est refusée au collaborateur.
  validation_seuil            numeric,
  updated_at                  timestamptz not null default now()
);

comment on table public.parametres_vente is
  'Module 25 — réglages du propriétaire pour la négociation, les réductions et les cadeaux. Aucune ligne = tout est désactivé.';

-- Si le script a déjà été exécuté dans une version antérieure : on complète.
alter table public.parametres_vente
  add column if not exists bonus_auto jsonb not null default '[]'::jsonb;

alter table public.parametres_vente enable row level security;

drop policy if exists parametres_vente_lecture on public.parametres_vente;
create policy parametres_vente_lecture on public.parametres_vente
  for select to authenticated
  using (
    owner_id = auth.uid()
    or owner_id = public.mon_proprietaire()
    or public.est_plateforme()
  );

-- Aucune policy d'écriture : les réglages s'écrivent via
-- `boutique_parametres_vente_enregistrer` (security definer, propriétaire).


-- ============================================================================
--  2. `public.ventes` — CE QUI A ÉTÉ VENDU, ET À QUEL PRIX
-- ============================================================================
--  • `prix`            : ce que le client a RÉELLEMENT payé pour la ligne ;
--  • `prix_catalogue`  : ce que la ligne aurait coûté au prix du catalogue ;
--  • `prix_negocie`    : prix unitaire négocié (NULL si aucun accord) ;
--  • `est_cadeau`      : ligne offerte (prix = 0, sortie de stock réelle) ;
--  • `reference_locale`: clé d'idempotence du téléphone (hors ligne).

alter table public.ventes add column if not exists prix_catalogue   numeric;
alter table public.ventes add column if not exists prix_negocie     numeric;
alter table public.ventes add column if not exists est_cadeau       boolean not null default false;
alter table public.ventes add column if not exists reference_locale text;

create index if not exists idx_ventes_cadeau
  on public.ventes (owner_id, est_cadeau) where est_cadeau;

create unique index if not exists idx_ventes_reference_locale_unique
  on public.ventes (owner_id, reference_locale)
  where reference_locale is not null;

comment on column public.ventes.prix_catalogue is
  'Prix de la ligne au tarif du catalogue (avant négociation). Le catalogue lui-même n''est jamais modifié.';
comment on column public.ventes.prix_negocie is
  'Prix unitaire négocié accepté par le vendeur (NULL = prix catalogue).';
comment on column public.ventes.est_cadeau is
  'Ligne offerte au client : sortie de stock réelle, montant facturé 0.';
comment on column public.ventes.reference_locale is
  'Clé d''idempotence créée par le téléphone : une vente rejouée ne crée pas de doublon.';


-- ============================================================================
--  3. `public.caisse` — LE MONTANT AVANT / APRÈS RÉDUCTION
-- ============================================================================

alter table public.caisse add column if not exists montant_initial numeric;
alter table public.caisse add column if not exists remise_montant  numeric not null default 0;
alter table public.caisse add column if not exists remise_type     text;
alter table public.caisse add column if not exists remise_taux     numeric;

comment on column public.caisse.montant_initial is
  'Total du panier avant réduction (égal à montant_total quand il n''y a pas de réduction).';
comment on column public.caisse.remise_montant is
  'Réduction accordée sur l''ensemble du panier, en valeur.';


-- ============================================================================
--  4. `public.ventes_flexibilite` — LA TRACE DÉTAILLÉE
-- ============================================================================
--  Une ligne par vente ayant fait l'objet d'une négociation, d'une réduction
--  ou d'un cadeau. Les ventes ordinaires n'y figurent pas : la table reste
--  petite et lisible par le propriétaire.

create table if not exists public.ventes_flexibilite (
  vente_uuid         uuid primary key,
  owner_id           uuid not null,
  seller_id          uuid,
  numero_vente       text,
  total_initial      numeric not null default 0,
  montant_negociation numeric not null default 0,
  remise_montant     numeric not null default 0,
  remise_type        text,
  remise_taux        numeric,
  valeur_cadeaux     numeric not null default 0,
  cout_cadeaux       numeric,
  cout_complet       boolean not null default true,
  cadeaux            jsonb not null default '[]'::jsonb,
  total_final        numeric not null default 0,
  validation_requise boolean not null default false,
  valide_par         uuid,
  valide_le          timestamptz,
  date               timestamptz not null default now()
);

create index if not exists idx_ventes_flex_owner_date
  on public.ventes_flexibilite (owner_id, date desc);
create index if not exists idx_ventes_flex_vendeur
  on public.ventes_flexibilite (seller_id, date desc);

comment on table public.ventes_flexibilite is
  'Module 25 — trace des ventes négociées, réduites ou accompagnées d''un cadeau : qui, quand, combien accordé.';

alter table public.ventes_flexibilite enable row level security;

drop policy if exists ventes_flexibilite_lecture on public.ventes_flexibilite;
create policy ventes_flexibilite_lecture on public.ventes_flexibilite
  for select to authenticated
  using (
    owner_id = auth.uid()
    or owner_id = public.mon_proprietaire()
    or public.est_plateforme()
  );


-- ============================================================================
--  5. PARAMÈTRES — LECTURE ET ENREGISTREMENT
-- ============================================================================

-- 5.a Lecture : renvoie les réglages ET les droits du demandeur. ------------
--     L'application n'a donc jamais à recopier la règle : elle affiche ou
--     masque le champ « négocier » selon ce que le serveur vient de dire.
create or replace function public.boutique_parametres_vente_lire()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_user      uuid := auth.uid();
  v_owner     uuid;
  v_param     jsonb;
  v_est_patron boolean;
  v_neg_collabs jsonb;
  v_red_collabs jsonb;
  v_cad_collabs jsonb;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour vendre.';
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  select to_jsonb(p) into v_param
    from public.parametres_vente p
   where p.owner_id = v_owner;

  if v_param is null then
    v_param := jsonb_build_object(
      'negociation_activee', false,
      'negociation_max_pct', 10,
      'negociation_prix_min', null,
      'negociation_collaborateurs', '[]'::jsonb,
      'reduction_activee', false,
      'reduction_max_pct', 10,
      'reduction_max_montant', null,
      'reduction_collaborateurs', '[]'::jsonb,
      'cadeaux_actifs', false,
      'cadeau_collaborateurs', '[]'::jsonb,
      'validation_seuil', null
    );
  end if;

  v_neg_collabs := coalesce(v_param->'negociation_collaborateurs', '[]'::jsonb);
  v_red_collabs := coalesce(v_param->'reduction_collaborateurs', '[]'::jsonb);
  v_cad_collabs := coalesce(v_param->'cadeau_collaborateurs', '[]'::jsonb);
  v_est_patron := (v_user = v_owner) or public.est_plateforme();

  return v_param || jsonb_build_object(
    'owner_id',         v_owner,
    'est_proprietaire', v_est_patron,
    -- Droits EFFECTIFS du demandeur, calculés une seule fois ici :
    'peut_negocier', coalesce((v_param->>'negociation_activee')::boolean, false) and (
      v_est_patron
      or jsonb_array_length(v_neg_collabs) = 0
      or v_neg_collabs ? (v_user::text)
    ),
    'peut_reduire', coalesce((v_param->>'reduction_activee')::boolean, false) and (
      v_est_patron
      or jsonb_array_length(v_red_collabs) = 0
      or v_red_collabs ? (v_user::text)
    ),
    'peut_offrir', coalesce((v_param->>'cadeaux_actifs')::boolean, false) and (
      v_est_patron
      or jsonb_array_length(v_cad_collabs) = 0
      or v_cad_collabs ? (v_user::text)
    )
  );
end;
$$;

comment on function public.boutique_parametres_vente_lire() is
  'Module 25 — réglages de vente flexible + droits effectifs du demandeur.';

revoke all on function public.boutique_parametres_vente_lire() from public, anon;
grant execute on function public.boutique_parametres_vente_lire() to authenticated;


-- 5.b Enregistrement : PROPRIÉTAIRE uniquement. ------------------------------
--  La version à 11 paramètres (sans `p_bonus_auto`) est supprimée pour éviter
--  une surcharge ambiguë si le script est relancé après une première version.
drop function if exists public.boutique_parametres_vente_enregistrer(
  boolean, numeric, numeric, uuid[], boolean, numeric, numeric, uuid[],
  boolean, uuid[], numeric
);

create or replace function public.boutique_parametres_vente_enregistrer(
  p_negociation_activee        boolean default false,
  p_negociation_max_pct        numeric default 10,
  p_negociation_prix_min       numeric default null,
  p_negociation_collaborateurs uuid[]  default '{}'::uuid[],
  p_reduction_activee          boolean default false,
  p_reduction_max_pct          numeric default 10,
  p_reduction_max_montant      numeric default null,
  p_reduction_collaborateurs   uuid[]  default '{}'::uuid[],
  p_cadeaux_actifs             boolean default false,
  p_cadeau_collaborateurs      uuid[]  default '{}'::uuid[],
  p_validation_seuil           numeric default null,
  p_bonus_auto                 jsonb   default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user  uuid := auth.uid();
  v_owner uuid := public.mon_proprietaire();
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour modifier les paramètres.';
  end if;
  if v_owner is null then
    v_owner := v_user;
  end if;

  if v_user <> v_owner and not public.est_plateforme() then
    raise exception 'DROIT_REFUSE|Seul le propriétaire règle la négociation, les réductions et les cadeaux.';
  end if;

  if coalesce(p_negociation_max_pct, 0) < 0 or coalesce(p_negociation_max_pct, 0) > 100 then
    raise exception 'VALEUR_INVALIDE|La limite de négociation doit être comprise entre 0 et 100 %%.';
  end if;
  if coalesce(p_reduction_max_pct, 0) < 0 or coalesce(p_reduction_max_pct, 0) > 100 then
    raise exception 'VALEUR_INVALIDE|La limite de réduction doit être comprise entre 0 et 100 %%.';
  end if;
  if p_reduction_max_montant is not null and p_reduction_max_montant < 0 then
    raise exception 'VALEUR_INVALIDE|La réduction maximale ne peut pas être négative.';
  end if;
  if p_negociation_prix_min is not null and p_negociation_prix_min < 0 then
    raise exception 'VALEUR_INVALIDE|Le prix minimum ne peut pas être négatif.';
  end if;
  if p_bonus_auto is not null and jsonb_typeof(p_bonus_auto) <> 'array' then
    raise exception 'VALEUR_INVALIDE|Les règles de bonus doivent être une liste.';
  end if;

  insert into public.parametres_vente as p (
    owner_id, negociation_activee, negociation_max_pct, negociation_prix_min,
    negociation_collaborateurs, reduction_activee, reduction_max_pct,
    reduction_max_montant, reduction_collaborateurs, cadeaux_actifs,
    cadeau_collaborateurs, validation_seuil, bonus_auto, updated_at
  ) values (
    v_owner,
    coalesce(p_negociation_activee, false),
    coalesce(p_negociation_max_pct, 10),
    p_negociation_prix_min,
    coalesce(p_negociation_collaborateurs, '{}'::uuid[]),
    coalesce(p_reduction_activee, false),
    coalesce(p_reduction_max_pct, 10),
    p_reduction_max_montant,
    coalesce(p_reduction_collaborateurs, '{}'::uuid[]),
    coalesce(p_cadeaux_actifs, false),
    coalesce(p_cadeau_collaborateurs, '{}'::uuid[]),
    p_validation_seuil,
    coalesce(p_bonus_auto, '[]'::jsonb),
    now()
  )
  on conflict (owner_id) do update set
    negociation_activee        = excluded.negociation_activee,
    negociation_max_pct        = excluded.negociation_max_pct,
    negociation_prix_min       = excluded.negociation_prix_min,
    negociation_collaborateurs = excluded.negociation_collaborateurs,
    reduction_activee          = excluded.reduction_activee,
    reduction_max_pct          = excluded.reduction_max_pct,
    reduction_max_montant      = excluded.reduction_max_montant,
    reduction_collaborateurs   = excluded.reduction_collaborateurs,
    cadeaux_actifs             = excluded.cadeaux_actifs,
    cadeau_collaborateurs      = excluded.cadeau_collaborateurs,
    validation_seuil           = excluded.validation_seuil,
    bonus_auto                 = excluded.bonus_auto,
    updated_at                 = now();

  -- Trace du réglage : qui a autorisé quoi, et quand.
  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(), null, 'PARAMETRES_VENTE', v_user,
    jsonb_build_object(
      'boutique', v_owner,
      'negociation', coalesce(p_negociation_activee, false),
      'reduction',   coalesce(p_reduction_activee, false),
      'cadeaux',     coalesce(p_cadeaux_actifs, false)
    ),
    now()
  );

  return public.boutique_parametres_vente_lire();
end;
$$;

comment on function public.boutique_parametres_vente_enregistrer(
  boolean, numeric, numeric, uuid[], boolean, numeric, numeric, uuid[],
  boolean, uuid[], numeric, jsonb
) is
  'Module 25 — enregistre les réglages de vente flexible (propriétaire).';

revoke all on function public.boutique_parametres_vente_enregistrer(
  boolean, numeric, numeric, uuid[], boolean, numeric, numeric, uuid[],
  boolean, uuid[], numeric, jsonb
) from public, anon;
grant execute on function public.boutique_parametres_vente_enregistrer(
  boolean, numeric, numeric, uuid[], boolean, numeric, numeric, uuid[],
  boolean, uuid[], numeric, jsonb
) to authenticated;


-- ============================================================================
--  6. `rpc_vente_valider` — LA MÊME TRANSACTION, ENRICHIE
-- ============================================================================
--  Nouveaux paramètres (tous facultatifs — un appel à 5 paramètres continue
--  de fonctionner exactement comme avant) :
--    p_remise           — réduction sur le total du panier ;
--    p_remise_type      — 'montant' (défaut) ou 'pourcentage' ;
--    p_cadeaux          — [{produit_id, quantite, conditionnement_id}] ;
--    p_reference_locale — clé d'idempotence du téléphone.
--
--  Chaque ligne de `p_lignes` accepte en plus `prix_negocie` (prix unitaire
--  négocié, dans l'unité vendue).
--
--  Codes d'erreur ajoutés :
--    NEGOCIATION_INTERDITE | NEGOCIATION_HORS_LIMITE | REMISE_INTERDITE |
--    REMISE_HORS_LIMITE | CADEAU_INTERDIT | CADEAU_STOCK |
--    VALIDATION_REQUISE | REFERENCE_INVALIDE

drop function if exists public.rpc_vente_valider(jsonb, text, numeric, text, bigint);

create or replace function public.rpc_vente_valider(
  p_lignes             jsonb,
  p_mode_paiement      text default 'especes',
  p_montant_recu       numeric default null,
  p_numero_transaction text default null,
  p_client_id          bigint default null,
  p_remise             numeric default 0,
  p_remise_type        text default null,
  p_cadeaux            jsonb default null,
  p_reference_locale   text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user        uuid := auth.uid();
  v_owner       uuid;
  v_mode        text := coalesce(nullif(btrim(lower(coalesce(p_mode_paiement, ''))), ''), 'especes');
  v_numero      text;
  v_vente_uuid  uuid := gen_random_uuid();
  v_ligne       jsonb;
  v_produit_id  bigint;
  v_produit     record;
  v_cond_id     uuid;
  -- ⚠️ `v_cond` est un `record` : on ne le LIT JAMAIS directement dans une
  -- expression (plpgsql lie ses champs AVANT d'exécuter l'expression, même
  -- dans une branche `case` non prise → « record "v_cond" is not assigned
  -- yet »). On recopie donc son libellé dans un texte, systématiquement.
  v_cond        record;
  v_cond_libelle text;
  v_qte_base    numeric;
  v_qte_vendue  numeric;
  v_prix_unit   numeric;
  v_prix_ligne  numeric;
  v_total       numeric := 0;
  v_total_cat   numeric := 0;
  v_negociation numeric := 0;
  v_lignes_retour jsonb := '[]'::jsonb;

  -- Module 25
  v_param       jsonb;
  v_neg_activee boolean := false;
  v_neg_max_pct numeric := 0;
  v_neg_prix_min numeric;
  v_neg_collabs jsonb := '[]'::jsonb;
  v_red_activee boolean := false;
  v_red_max_pct numeric := 0;
  v_red_max_montant numeric;
  v_red_collabs jsonb := '[]'::jsonb;
  v_cad_actifs  boolean := false;
  v_cad_collabs jsonb := '[]'::jsonb;
  v_bonus_auto  jsonb := '[]'::jsonb;
  v_auto        jsonb := '[]'::jsonb;
  v_regle       jsonb;
  v_valid_seuil numeric;
  v_est_patron  boolean;
  v_prix_nego   numeric;
  v_prix_cat    numeric;
  v_ecart       numeric;
  v_remise      numeric := 0;
  v_remise_type text;
  v_remise_taux numeric;
  v_cadeaux_in  jsonb := coalesce(p_cadeaux, '[]'::jsonb);
  v_cadeau      jsonb;
  v_cadeau_qte  numeric;
  v_cadeau_base numeric;
  v_cadeau_prix numeric;
  v_cadeau_val  numeric := 0;
  v_cadeau_cout numeric := 0;
  v_cadeau_cout_ligne numeric;
  v_cadeaux_retour jsonb := '[]'::jsonb;
  v_cout_cadeaux_complet boolean := true;
  v_reference   text := nullif(btrim(coalesce(p_reference_locale, '')), '');
  v_deja        record;
  v_validation  boolean := false;
begin
  -- 0. IDEMPOTENCE HORS LIGNE -------------------------------------------
  --  Une vente rejouée (réponse perdue, synchronisation relancée) ne doit
  --  jamais créer une deuxième vente, ni une deuxième sortie de stock.
  if v_reference is not null then
    select v2.numero_vente, v2.vente_uuid into v_deja
      from public.ventes v2
     where v2.reference_locale = v_reference
       and v2.owner_id = coalesce(public.mon_proprietaire(), auth.uid())
     limit 1;
    if found then
      return jsonb_build_object(
        'numero_vente',  v_deja.numero_vente,
        'vente_uuid',    v_deja.vente_uuid,
        'deja_enregistree', true,
        'total', (select coalesce(sum(x.prix), 0) from public.ventes x
                   where x.vente_uuid = v_deja.vente_uuid),
        'mode_paiement', v_mode,
        'date', now(),
        'lignes', coalesce((
          select jsonb_agg(jsonb_build_object(
                   'produit_id',    x.produit_id,
                   'nom',           p.nom,
                   'quantite_vendue', x.quantite,
                   'quantite_base', x.quantite,
                   'prix_unitaire', case when x.quantite > 0
                                         then round(x.prix / x.quantite, 2)
                                         else x.prix end,
                   'prix_catalogue', x.prix_catalogue,
                   'prix_negocie',  x.prix_negocie,
                   'total',         x.prix
                 ))
            from public.ventes x
            left join public.produits p on p.id = x.produit_id
           where x.vente_uuid = v_deja.vente_uuid
        ), '[]'::jsonb)
      );
    end if;
  end if;

  -- 1.a Session et rôle ------------------------------------------------
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour encaisser.';
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  if not (public.peut('caisse', 'creer') or public.est_plateforme()) then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas d''encaisser une vente.';
  end if;

  -- 1.b Panier -----------------------------------------------------------
  if p_lignes is null
     or jsonb_typeof(p_lignes) <> 'array'
     or jsonb_array_length(p_lignes) = 0 then
    raise exception 'PANIER_VIDE|Le panier est vide : ajoutez au moins un article.';
  end if;

  -- 1.c Réglages de la boutique -----------------------------------------
  select to_jsonb(p) into v_param
    from public.parametres_vente p
   where p.owner_id = v_owner;

  if v_param is null then
    -- Aucun réglage : négociation, réduction et cadeaux sont DÉSACTIVÉS.
    v_param := '{}'::jsonb;
  end if;

  v_neg_activee := coalesce((v_param->>'negociation_activee')::boolean, false);
  v_neg_max_pct := coalesce((v_param->>'negociation_max_pct')::numeric, 0);
  v_neg_prix_min := nullif(v_param->>'negociation_prix_min', '')::numeric;
  v_neg_collabs := coalesce(v_param->'negociation_collaborateurs', '[]'::jsonb);
  v_red_activee := coalesce((v_param->>'reduction_activee')::boolean, false);
  v_red_max_pct := coalesce((v_param->>'reduction_max_pct')::numeric, 0);
  v_red_max_montant := nullif(v_param->>'reduction_max_montant', '')::numeric;
  v_red_collabs := coalesce(v_param->'reduction_collaborateurs', '[]'::jsonb);
  v_cad_actifs := coalesce((v_param->>'cadeaux_actifs')::boolean, false);
  v_cad_collabs := coalesce(v_param->'cadeau_collaborateurs', '[]'::jsonb);
  v_bonus_auto := coalesce(v_param->'bonus_auto', '[]'::jsonb);
  v_valid_seuil := nullif(v_param->>'validation_seuil', '')::numeric;
  v_est_patron := (v_user = v_owner) or public.est_plateforme();

  -- 2 et 3. Vérification du stock (sous verrou) et relecture des prix ----
  --  On verrouille AUSSI les produits offerts : un cadeau consomme du stock.
  perform p.id
     from public.produits p
    where p.id in (
      select distinct (l->>'produit_id')::bigint
        from jsonb_array_elements(p_lignes) as l
      union
      select distinct (c->>'produit_id')::bigint
        from jsonb_array_elements(
               case when jsonb_typeof(v_cadeaux_in) = 'array'
                    then v_cadeaux_in else '[]'::jsonb end
             ) as c
    )
    order by p.id
      for update;

  for v_ligne in select * from jsonb_array_elements(p_lignes)
  loop
    v_produit_id := nullif(v_ligne->>'produit_id', '')::bigint;
    if v_produit_id is null then
      raise exception 'LIGNE_INVALIDE|Une ligne du panier n''a pas d''article.';
    end if;

    v_qte_base := coalesce((v_ligne->>'quantite')::numeric, 0);
    if v_qte_base <= 0 then
      raise exception 'LIGNE_INVALIDE|Quantité invalide pour l''article %.', v_produit_id;
    end if;

    v_qte_vendue := coalesce((v_ligne->>'quantite_vendue')::numeric, v_qte_base);

    -- Verrou : toute vente concurrente sur le même article attend ici.
    select p.id, p.nom, p.owner_id, p.quantite, p.prix_vente,
           p.unite_mesure, p.prix_achat
      into v_produit
      from public.produits p
     where p.id = v_produit_id
       for update;

    if not found then
      raise exception 'PRODUIT_INTROUVABLE|Article n° % introuvable : il a peut-être été supprimé.', v_produit_id;
    end if;

    if v_produit.owner_id is distinct from v_owner
       and not public.est_plateforme() then
      raise exception 'HORS_BOUTIQUE|L''article % n''appartient pas à votre boutique.', v_produit.nom;
    end if;

    if coalesce(v_produit.quantite, 0) < v_qte_base then
      raise exception 'STOCK_INSUFFISANT|Stock insuffisant pour % : % disponible(s), % demandé(s).',
        v_produit.nom, v_produit.quantite, v_qte_base;
    end if;

    -- Prix de référence : conditionnement (Module 5) ou unité de base.
    v_cond_id := nullif(v_ligne->>'conditionnement_id', '')::uuid;
    v_prix_unit := v_produit.prix_vente;
    v_cond_libelle := null;

    if v_cond_id is not null then
      select c.id, c.libelle, c.quantite_unites_base, c.prix_vente
        into v_cond
        from public.conditionnements c
       where c.id = v_cond_id
         and c.produit_id = v_produit_id;

      if not found then
        raise exception 'CONDITIONNEMENT_INVALIDE|Le conditionnement choisi pour % n''existe plus.', v_produit.nom;
      end if;

      v_cond_libelle := v_cond.libelle;
      v_prix_unit := v_cond.prix_vente;
    end if;

    v_prix_cat := round(v_prix_unit * v_qte_vendue, 2);

    -- 🔻 MODULE 25 — NÉGOCIATION DU PRIX DE LA LIGNE ---------------------
    --  Le prix catalogue reste intact : on n'écrit que le prix accepté.
    v_prix_nego := null;
    if v_ligne ? 'prix_negocie'
       and nullif(v_ligne->>'prix_negocie', '') is not null then
      v_prix_nego := (v_ligne->>'prix_negocie')::numeric;

      if v_prix_nego <= 0 then
        raise exception 'NEGOCIATION_HORS_LIMITE|Le prix négocié de % doit être supérieur à zéro.', v_produit.nom;
      end if;

      -- Prix identique au catalogue = pas une négociation (on ignore).
      if round(v_prix_nego, 2) = round(v_prix_unit, 2) then
        v_prix_nego := null;
      else
        -- Négociation vers le haut : jamais acceptée (c'est une erreur).
        if v_prix_nego > v_prix_unit then
          raise exception 'NEGOCIATION_HORS_LIMITE|Le prix négocié de % (%) dépasse le prix catalogue (%).',
            v_produit.nom, v_prix_nego, v_prix_unit;
        end if;

        if not v_neg_activee then
          raise exception 'NEGOCIATION_INTERDITE|La négociation des prix est désactivée pour votre boutique.';
        end if;

        if not v_est_patron
           and jsonb_array_length(v_neg_collabs) > 0
           and not (v_neg_collabs ? (v_user::text)) then
          raise exception 'NEGOCIATION_INTERDITE|Votre compte n''est pas autorisé à négocier les prix.';
        end if;

        v_ecart := round(((v_prix_unit - v_prix_nego) / nullif(v_prix_unit, 0)) * 100, 2);
        if not v_est_patron
           and v_ecart > v_neg_max_pct + 0.001 then
          raise exception 'NEGOCIATION_HORS_LIMITE|Remise négociée de % %% sur % : la limite est de % %%.',
            v_ecart, v_produit.nom, coalesce(v_neg_max_pct, 0);
        end if;

        if v_neg_prix_min is not null
           and v_prix_nego < v_neg_prix_min - 0.001
           and not v_est_patron then
          raise exception 'NEGOCIATION_HORS_LIMITE|Prix minimum autorisé pour % : %.',
            v_produit.nom, v_neg_prix_min;
        end if;

        v_prix_ligne := round(v_prix_nego * v_qte_vendue, 2);
        v_negociation := v_negociation + (v_prix_cat - v_prix_ligne);
      end if;
    end if;

    if v_prix_nego is null then
      v_prix_ligne := v_prix_cat;
    end if;

    v_total := v_total + v_prix_ligne;
    v_total_cat := v_total_cat + v_prix_cat;

    -- Ligne insérée dans `ventes` : le trigger du stock retire `v_qte_base`.
    insert into public.ventes (
      produit_id, quantite, prix, mode_paiement, date,
      owner_id, seller_id, client_id, conditionnement_id,
      numero_vente, vente_uuid,
      prix_catalogue, prix_negocie, est_cadeau, reference_locale
    ) values (
      v_produit_id,
      v_qte_base,
      v_prix_ligne,
      v_mode,
      now(),
      v_owner,
      v_user,
      p_client_id,
      v_cond_id,
      null,          -- numéro attribué juste après (une seule fois)
      v_vente_uuid,
      v_prix_cat,
      v_prix_nego,
      false,
      v_reference
    );

    -- La clé d'idempotence n'est écrite qu'une fois, sur la première ligne.
    if v_reference is not null then
      v_reference := null;
    end if;

    v_lignes_retour := v_lignes_retour || jsonb_build_object(
      'produit_id',      v_produit_id,
      'nom',             v_produit.nom,
      'conditionnement', v_cond_libelle,
      'unite',           coalesce(v_cond_libelle, v_produit.unite_mesure),
      'quantite_vendue', v_qte_vendue,
      'quantite_base',   v_qte_base,
      'prix_unitaire',   coalesce(v_prix_nego, v_prix_unit),
      'prix_catalogue',  v_prix_cat,
      'prix_negocie',    v_prix_nego,
      'total',           v_prix_ligne
    );
  end loop;

  -- 🎁 MODULE 25 — CADEAUX COMMERCIAUX ------------------------------------
  --  Un cadeau est une ligne de vente à 0 : le stock sort réellement, la
  --  caisse n'encaisse rien et le chiffre d'affaires ne bouge pas.

  --  BONUS AUTOMATIQUES : le propriétaire peut attacher un cadeau à un seuil
  --  d'achat. Chaque règle ne s'applique qu'UNE fois par vente — un client ne
  --  peut donc pas recevoir deux fois le même bonus.
  if v_cad_actifs and jsonb_typeof(v_bonus_auto) = 'array' then
    for v_regle in select * from jsonb_array_elements(v_bonus_auto)
    loop
      if coalesce((v_regle->>'actif')::boolean, true)
         and coalesce((v_regle->>'produit_id')::bigint, 0) > 0
         and v_total >= coalesce((v_regle->>'seuil_montant')::numeric, 0) then
        v_auto := v_auto || jsonb_build_object(
          'produit_id', coalesce((v_regle->>'produit_id')::bigint, 0),
          'quantite', greatest(coalesce((v_regle->>'quantite')::numeric, 1), 1),
          'source', 'auto',
          'regle_seuil', coalesce((v_regle->>'seuil_montant')::numeric, 0)
        );
      end if;
    end loop;

    if jsonb_array_length(v_auto) > 0 then
      v_cadeaux_in := coalesce(v_cadeaux_in, '[]'::jsonb) || v_auto;
    end if;
  end if;

  if jsonb_typeof(v_cadeaux_in) = 'array'
     and jsonb_array_length(v_cadeaux_in) > 0 then

    -- Les contrôles d'autorisation ne concernent que les cadeaux CHOISIS par
    -- le vendeur : un bonus automatique est décidé par le propriétaire, il
    -- s'applique donc sans liste blanche.
    if jsonb_typeof(coalesce(p_cadeaux, '[]'::jsonb)) = 'array'
       and jsonb_array_length(coalesce(p_cadeaux, '[]'::jsonb)) > 0 then

      if not v_cad_actifs then
        raise exception 'CADEAU_INTERDIT|Les cadeaux commerciaux sont désactivés pour votre boutique.';
      end if;

      if not v_est_patron
         and jsonb_array_length(v_cad_collabs) > 0
         and not (v_cad_collabs ? (v_user::text)) then
        raise exception 'CADEAU_INTERDIT|Votre compte n''est pas autorisé à offrir un produit.';
      end if;
    end if;

    for v_cadeau in select * from jsonb_array_elements(v_cadeaux_in)
    loop
      v_produit_id := nullif(v_cadeau->>'produit_id', '')::bigint;
      v_cadeau_qte := coalesce((v_cadeau->>'quantite')::numeric, 1);
      if v_produit_id is null or v_cadeau_qte <= 0 then
        raise exception 'LIGNE_INVALIDE|Un cadeau a une quantité invalide.';
      end if;

      select p.id, p.nom, p.owner_id, p.quantite, p.prix_vente,
             p.unite_mesure, p.prix_achat
        into v_produit
        from public.produits p
       where p.id = v_produit_id
         for update;

      if not found then
        raise exception 'PRODUIT_INTROUVABLE|Article offert n° % introuvable.', v_produit_id;
      end if;

      if v_produit.owner_id is distinct from v_owner and not public.est_plateforme() then
        raise exception 'HORS_BOUTIQUE|L''article offert % n''appartient pas à votre boutique.', v_produit.nom;
      end if;

      v_cond_id := nullif(v_cadeau->>'conditionnement_id', '')::uuid;
      v_cadeau_base := v_cadeau_qte;
      v_cadeau_prix := coalesce(v_produit.prix_vente, 0);
      v_cond_libelle := null;

      if v_cond_id is not null then
        select c.id, c.libelle, c.quantite_unites_base, c.prix_vente
          into v_cond
          from public.conditionnements c
         where c.id = v_cond_id and c.produit_id = v_produit_id;
        if not found then
          raise exception 'CONDITIONNEMENT_INVALIDE|Le conditionnement offert pour % n''existe plus.', v_produit.nom;
        end if;
        v_cond_libelle := v_cond.libelle;
        v_cadeau_base := v_cadeau_qte * coalesce(v_cond.quantite_unites_base, 1);
        v_cadeau_prix := coalesce(v_cond.prix_vente, v_cadeau_prix);
      else
        v_cadeau_base := coalesce((v_cadeau->>'quantite_base')::numeric, v_cadeau_qte);
      end if;

      if coalesce(v_produit.quantite, 0) < v_cadeau_base then
        raise exception 'CADEAU_STOCK|Impossible d''offrir % : % en stock, % demandé(s).',
          v_produit.nom, v_produit.quantite, v_cadeau_base;
      end if;

      -- Valeur au prix catalogue (ce que le cadeau aurait coûté au client).
      v_cadeau_val := v_cadeau_val + round(v_cadeau_prix * v_cadeau_qte, 2);
      -- Coût réel, seulement s'il est connu : sinon on ne l'invente pas.
      v_cadeau_cout_ligne := null;
      if coalesce(v_produit.prix_achat, 0) > 0 then
        v_cadeau_cout_ligne := round(v_produit.prix_achat * v_cadeau_base, 2);
        v_cadeau_cout := coalesce(v_cadeau_cout, 0) + v_cadeau_cout_ligne;
      else
        -- Un seul cadeau sans prix d'achat suffit à rendre le coût inconnu.
        v_cout_cadeaux_complet := false;
      end if;

      insert into public.ventes (
        produit_id, quantite, prix, mode_paiement, date,
        owner_id, seller_id, client_id, conditionnement_id,
        numero_vente, vente_uuid,
        prix_catalogue, prix_negocie, est_cadeau, reference_locale
      ) values (
        v_produit_id,
        v_cadeau_base,
        0,
        v_mode,
        now(),
        v_owner,
        v_user,
        p_client_id,
        v_cond_id,
        null,
        v_vente_uuid,
        round(v_cadeau_prix * v_cadeau_qte, 2),
        null,
        true,
        null
      );

      v_cadeaux_retour := v_cadeaux_retour || jsonb_build_object(
        'produit_id',     v_produit_id,
        'nom',            v_produit.nom,
        'conditionnement', v_cond_libelle,
        'quantite',       v_cadeau_qte,
        'quantite_base',  v_cadeau_base,
        'valeur',         round(v_cadeau_prix * v_cadeau_qte, 2),
        'cout',           v_cadeau_cout_ligne,
        'source',         coalesce(v_cadeau->>'source', 'manuel')
      );
    end loop;
  end if;

  -- 🔻 MODULE 25 — RÉDUCTION SUR LE TOTAL DU PANIER -----------------------
  v_remise_type := lower(btrim(coalesce(p_remise_type, 'montant')));
  if v_remise_type not in ('montant', 'pourcentage') then
    raise exception 'VALEUR_INVALIDE|Type de réduction inconnu : utilisez « montant » ou « pourcentage ».';
  end if;

  if coalesce(p_remise, 0) < 0 then
    raise exception 'REMISE_HORS_LIMITE|Une réduction ne peut pas être négative.';
  end if;

  if coalesce(p_remise, 0) > 0 then
    if not v_red_activee then
      raise exception 'REMISE_INTERDITE|Les réductions sont désactivées pour votre boutique.';
    end if;

    if not v_est_patron
       and jsonb_array_length(v_red_collabs) > 0
       and not (v_red_collabs ? (v_user::text)) then
      raise exception 'REMISE_INTERDITE|Votre compte n''est pas autorisé à accorder une réduction.';
    end if;

    if v_remise_type = 'pourcentage' then
      if p_remise > 100 then
        raise exception 'REMISE_HORS_LIMITE|Une réduction en pourcentage ne peut pas dépasser 100 %%.';
      end if;
      if not v_est_patron
         and p_remise > v_red_max_pct + 0.001 then
        raise exception 'REMISE_HORS_LIMITE|Réduction de % %% : la limite est de % %%.',
          p_remise, coalesce(v_red_max_pct, 0);
      end if;
      v_remise_taux := p_remise;
      v_remise := round(v_total * p_remise / 100, 2);
    else
      v_remise := round(p_remise, 2);
      v_remise_taux := case when v_total > 0
                            then round(v_remise / v_total * 100, 2)
                            else 0 end;
      if not v_est_patron
         and v_remise_taux > v_red_max_pct + 0.001 then
        raise exception 'REMISE_HORS_LIMITE|Réduction de % %% : la limite est de % %%.',
          v_remise_taux, coalesce(v_red_max_pct, 0);
      end if;
    end if;

    if v_red_max_montant is not null
       and not v_est_patron
       and v_remise > v_red_max_montant + 0.001 then
      raise exception 'REMISE_HORS_LIMITE|Réduction de % : le plafond est de %.',
        v_remise, v_red_max_montant;
    end if;

    if v_remise > v_total + 0.001 then
      raise exception 'REMISE_HORS_LIMITE|La réduction (%) dépasse le total du panier (%).',
        v_remise, v_total;
    end if;
  end if;

  -- Seuil de validation du responsable : au-delà, le collaborateur ne peut
  -- pas conclure seul la vente.
  if v_valid_seuil is not null
     and v_valid_seuil > 0
     and (v_remise + v_negociation) > v_valid_seuil + 0.001 then
    v_validation := true;
    if not v_est_patron then
      raise exception 'VALIDATION_REQUISE|Remise totale de % (négociation + réduction) : au-delà de % le responsable doit valider.',
        round(v_remise + v_negociation, 2), v_valid_seuil;
    end if;
  end if;

  v_total := greatest(round(v_total - v_remise, 2), 0);

  -- 4. Numéro de vente unique (compteur journalier par boutique) ---------
  v_numero := public.prochain_numero_vente(v_owner);

  -- Le numéro n'est écrit qu'une fois toutes les lignes validées.
  update public.ventes
     set numero_vente = v_numero
   where vente_uuid = v_vente_uuid
     and numero_vente is null;

  -- 4.b Contrôle du montant reçu (espèces) AVANT l'encaissement.
  if v_mode = 'especes'
     and p_montant_recu is not null
     and p_montant_recu < v_total then
    raise exception 'MONTANT_INSUFFISANT|Montant reçu insuffisant : % attendu, % reçu.',
      v_total, p_montant_recu;
  end if;

  -- 5. Encaissement (caisse) ---------------------------------------------
  insert into public.caisse (
    vente_uuid, numero_vente, owner_id, seller_id, client_id,
    montant_total, mode_paiement, montant_recu, rendu, numero_transaction,
    montant_initial, remise_montant, remise_type, remise_taux
  ) values (
    v_vente_uuid,
    v_numero,
    v_owner,
    v_user,
    p_client_id,
    v_total,
    v_mode,
    p_montant_recu,
    case
      when p_montant_recu is null then null
      else greatest(round(p_montant_recu - v_total, 2), 0)
    end,
    p_numero_transaction,
    v_total_cat,
    v_remise,
    case when v_remise > 0 then v_remise_type else null end,
    case when v_remise > 0 then v_remise_taux else null end
  );

  -- 5.b Trace de la flexibilité commerciale ------------------------------
  if v_negociation > 0 or v_remise > 0
     or jsonb_array_length(v_cadeaux_retour) > 0 then
    insert into public.ventes_flexibilite (
      vente_uuid, owner_id, seller_id, numero_vente,
      total_initial, montant_negociation, remise_montant, remise_type,
      remise_taux, valeur_cadeaux, cout_cadeaux, cout_complet, cadeaux,
      total_final, validation_requise, date
    ) values (
      v_vente_uuid, v_owner, v_user, v_numero,
      v_total_cat, round(v_negociation, 2), v_remise,
      case when v_remise > 0 then v_remise_type else null end,
      case when v_remise > 0 then v_remise_taux else null end,
      round(v_cadeau_val, 2), v_cadeau_cout, v_cout_cadeaux_complet,
      v_cadeaux_retour,
      v_total, v_validation, now()
    )
    on conflict (vente_uuid) do nothing;
  end if;

  -- 6. Journal d'audit -----------------------------------------------------
  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(),
    null,
    'VENTE',
    v_user,
    jsonb_build_object(
      'numero_vente',  v_numero,
      'vente_uuid',    v_vente_uuid,
      'boutique',      v_owner,
      'total',         v_total,
      'total_catalogue', v_total_cat,
      'negociation',   round(v_negociation, 2),
      'remise',        v_remise,
      'cadeaux',       jsonb_array_length(v_cadeaux_retour),
      'mode_paiement', v_mode,
      'nb_lignes',     jsonb_array_length(p_lignes)
    ),
    now()
  );

  -- 7. Récapitulatif renvoyé à l'application -------------------------------
  return jsonb_build_object(
    'numero_vente',  v_numero,
    'vente_uuid',    v_vente_uuid,
    'total',         v_total,
    'total_initial', v_total_cat,
    'negociation',   round(v_negociation, 2),
    'remise',        v_remise,
    'remise_type',   case when v_remise > 0 then v_remise_type else null end,
    'valeur_cadeaux', round(v_cadeau_val, 2),
    'cadeaux',       v_cadeaux_retour,
    'mode_paiement', v_mode,
    'montant_recu',  p_montant_recu,
    'rendu', case
      when p_montant_recu is null then null
      else greatest(round(p_montant_recu - v_total, 2), 0)
    end,
    'date',   now(),
    'lignes', v_lignes_retour
  );
end;
$$;

comment on function public.rpc_vente_valider(
  jsonb, text, numeric, text, bigint, numeric, text, jsonb, text
) is
  'Module 25 — valide une vente complète (lignes, négociation, réduction, cadeaux, stock, encaissement, numéro, trace) en une seule transaction.';

revoke all on function public.rpc_vente_valider(
  jsonb, text, numeric, text, bigint, numeric, text, jsonb, text
) from public;
grant execute on function public.rpc_vente_valider(
  jsonb, text, numeric, text, bigint, numeric, text, jsonb, text
) to authenticated;


-- ============================================================================
--  7. RAPPORTS — CE QUE LA FLEXIBILITÉ A COÛTÉ
-- ============================================================================
--  Renvoie un JSON prêt à afficher. `marge` reste NULL quand les prix
--  d'achat manquent : on ne calcule jamais une marge inventée.

create or replace function public.boutique_ventes_flexibilite_resume(
  p_debut date default null,
  p_fin   date default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_user   uuid := auth.uid();
  v_owner  uuid;
  v_debut  timestamptz;
  v_fin    timestamptz;
  v_ca        numeric := 0;
  v_cat       numeric := 0;
  v_negoc     numeric := 0;
  v_remise    numeric := 0;
  v_cadeaux   integer := 0;
  v_val_cad   numeric := 0;
  v_cout_cad  numeric := 0;
  v_cout_cad_complet boolean := true;
  v_nb_negoc  integer := 0;
  v_nb_ventes integer := 0;
  v_sous_cout integer := 0;
  v_cout_ventes numeric := 0;
  v_cout_connu  boolean := true;
  v_detail    jsonb := '[]'::jsonb;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour consulter les rapports.';
  end if;

  if not (public.peut('rapports', 'voir') or public.peut('caisse', 'voir')
          or public.est_plateforme()) then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de consulter les rapports.';
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  v_debut := coalesce(p_debut, current_date - 30)::timestamptz;
  v_fin   := (coalesce(p_fin, current_date) + 1)::timestamptz;

  -- Chiffre d'affaires réellement facturé (les cadeaux comptent 0).
  select coalesce(sum(v.prix), 0),
         coalesce(sum(coalesce(v.prix_catalogue, v.prix)), 0),
         count(distinct v.vente_uuid)
    into v_ca, v_cat, v_nb_ventes
    from public.ventes v
   where v.owner_id = v_owner
     and v.date >= v_debut and v.date < v_fin
     and coalesce(v.est_cadeau, false) = false;

  -- Coût des marchandises vendues (NULL si un prix d'achat manque).
  select coalesce(sum(coalesce(p.prix_achat, 0) * v.quantite), 0),
         coalesce(bool_and(coalesce(p.prix_achat, 0) > 0), true)
    into v_cout_ventes, v_cout_connu
    from public.ventes v
    join public.produits p on p.id = v.produit_id
   where v.owner_id = v_owner
     and v.date >= v_debut and v.date < v_fin
     and coalesce(v.est_cadeau, false) = false;

  select coalesce(sum(f.montant_negociation), 0),
         coalesce(sum(f.remise_montant), 0),
         coalesce(sum(f.valeur_cadeaux), 0),
         coalesce(sum(f.cout_cadeaux), 0),
         coalesce(count(*) filter (where f.montant_negociation > 0), 0),
         coalesce(bool_and(f.cout_complet), true)
    into v_negoc, v_remise, v_val_cad, v_cout_cad, v_nb_negoc,
         v_cout_cad_complet
    from public.ventes_flexibilite f
   where f.owner_id = v_owner
     and f.date >= v_debut and f.date < v_fin;

  -- Nombre de lignes offertes (pas de ventes : un cadeau n'est pas une vente).
  select count(*)
    into v_cadeaux
    from public.ventes v
   where v.owner_id = v_owner
     and v.est_cadeau
     and v.date >= v_debut and v.date < v_fin;

  -- ⚠️ ALERTE : lignes vendues SOUS le prix d'achat connu. C'est le signal
  -- qu'une négociation ou une réduction a mangé la marge — le propriétaire
  -- doit le voir, même quand la marge globale reste positive.
  select count(*)
    into v_sous_cout
    from public.ventes v
    join public.produits p on p.id = v.produit_id
   where v.owner_id = v_owner
     and v.date >= v_debut and v.date < v_fin
     and coalesce(v.est_cadeau, false) = false
     and coalesce(p.prix_achat, 0) > 0
     and coalesce(v.quantite, 0) > 0
     and (v.prix / v.quantite) < p.prix_achat - 0.01;

  -- Ventes par collaborateur (CA, négociations, réductions, cadeaux).
  select coalesce(jsonb_agg(x order by x->>'nom'), '[]'::jsonb)
    into v_detail
    from (
      select jsonb_build_object(
               'vendeur_id', coalesce(v.seller_id, v.owner_id),
               'nom', coalesce(
                        nullif(btrim(u.prenom || ' ' || u.nom), ''),
                        'Boutique'),
               'ca', coalesce(sum(v.prix), 0),
               'nb_ventes', count(distinct v.vente_uuid),
               'negociations', coalesce(sum(coalesce(v.prix_catalogue, v.prix) - v.prix), 0)
             ) as x
        from public.ventes v
        left join public.utilisateurs u on u.id = v.seller_id
       where v.owner_id = v_owner
         and v.date >= v_debut and v.date < v_fin
         and coalesce(v.est_cadeau, false) = false
       group by v.seller_id, v.owner_id, u.prenom, u.nom
    ) s;

  return jsonb_build_object(
    'debut',            v_debut::date,
    'fin',              (v_fin - interval '1 day')::date,
    'ca_brut',          round(v_cat, 2),
    'montant_negociation', round(v_negoc, 2),
    'reductions',       round(v_remise, 2),
    'montant_facture',  round(v_ca, 2),
    'nb_ventes',        v_nb_ventes,
    'ventes_negociees', v_nb_negoc,
    'ventes_au_prix_normal', greatest(v_nb_ventes - v_nb_negoc, 0),
    'nb_cadeaux',       v_cadeaux,
    'valeur_cadeaux',   round(v_val_cad, 2),
    'nb_ventes_sous_cout', v_sous_cout,
    'cout_cadeaux',     case when v_cout_cad_complet then round(v_cout_cad, 2) else null end,
    'cout_marchandises', case when v_cout_connu then round(v_cout_ventes, 2) else null end,
    'marge', case
               when v_cout_connu
                 then round(v_ca - v_cout_ventes - coalesce(v_cout_cad, 0), 2)
               else null
             end,
    'marge_incomplete', (not v_cout_connu) or (not v_cout_cad_complet),
    'par_vendeur',      v_detail
  );
end;
$$;

comment on function public.boutique_ventes_flexibilite_resume(date, date) is
  'Module 25 — CA brut, négociations, réductions, cadeaux, marges et ventes par collaborateur.';

revoke all on function public.boutique_ventes_flexibilite_resume(date, date) from public, anon;
grant execute on function public.boutique_ventes_flexibilite_resume(date, date) to authenticated;


-- ============================================================================
--  8. HISTORIQUE DES OPÉRATIONS COMMERCIALES
-- ============================================================================

create or replace function public.boutique_ventes_flexibilite_lister(
  p_limite integer default 50
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
  v_rows  jsonb;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour consulter l''historique.';
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  if v_user <> v_owner and not public.est_plateforme() then
    raise exception 'DROIT_REFUSE|Seul le propriétaire consulte l''historique des négociations.';
  end if;

  select coalesce(jsonb_agg(x order by x->>'date' desc), '[]'::jsonb)
    into v_rows
    from (
      select jsonb_build_object(
               'vente_uuid',   f.vente_uuid,
               'numero_vente', f.numero_vente,
               'date',         f.date,
               'vendeur',      coalesce(nullif(btrim(u.prenom || ' ' || u.nom), ''),
                                        'Boutique'),
               'total_initial',  f.total_initial,
               'negociation',    f.montant_negociation,
               'remise',         f.remise_montant,
               'valeur_cadeaux', f.valeur_cadeaux,
               'total_final',    f.total_final,
               'cadeaux',        f.cadeaux
             ) as x
        from public.ventes_flexibilite f
        left join public.utilisateurs u on u.id = f.seller_id
       where f.owner_id = v_owner
       order by f.date desc
       limit greatest(coalesce(p_limite, 50), 1)
    ) s;

  return v_rows;
end;
$$;

comment on function public.boutique_ventes_flexibilite_lister(integer) is
  'Module 25 — historique des ventes négociées / réduites / avec cadeau.';

revoke all on function public.boutique_ventes_flexibilite_lister(integer) from public, anon;
grant execute on function public.boutique_ventes_flexibilite_lister(integer) to authenticated;


-- ============================================================================
--  9. VÉRIFICATIONS
-- ============================================================================

select table_name
  from information_schema.tables
 where table_schema = 'public'
   and table_name in ('parametres_vente', 'ventes_flexibilite')
 order by table_name;

select column_name, data_type
  from information_schema.columns
 where table_schema = 'public' and table_name = 'ventes'
   and column_name in ('prix_catalogue', 'prix_negocie', 'est_cadeau', 'reference_locale')
 order by column_name;

select p.proname, pg_get_function_arguments(p.oid) as arguments
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname in ('rpc_vente_valider', 'boutique_parametres_vente_lire',
                     'boutique_parametres_vente_enregistrer',
                     'boutique_ventes_flexibilite_resume',
                     'boutique_ventes_flexibilite_lister')
 order by p.proname;
