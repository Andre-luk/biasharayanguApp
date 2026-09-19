-- ============================================================================
--  biashara_yangu — MODULE 16 (PHASE C1) : PHARMACIE — LOTS & PÉREMPTION
--
--  OBJECTIF (roadmap multi-activités, module C1) :
--    Le type d'activité « Pharmacie » active le module `lots_expiration` :
--      • lots et dates de péremption sur chaque article (`produits`) ;
--      • alerte « Expirations » sur le tableau de bord + rapport dédié ;
--      • notification de fin de journée : produits expirés / bientôt périmés ;
--      • VENTE BLOQUÉE pour un produit dont la date est dépassée
--        (réglage `app_settings['ventes'].bloquer_produits_expires`,
--        défaut : true ; un produit SANS date n'est jamais bloqué).
--
--  CONTENU :
--    1. colonnes `lot_numero` + `date_expiration` (+ index partiel) ;
--    2. réglage du blocage (app_settings) ;
--    3. `rpc_vente_valider` patchée (version migration 24 + contrôle expire) ;
--    4. `rpc_rapport_entreprise` patchée (version migration 26 + nouveau type
--       « expirations » : lot, expiration, jours restants, statut, valeur).
--
--  OÙ : Supabase → SQL Editor → coller → Run
--  IDEMPOTENT : peut être relancé sans effet de bord.
-- ============================================================================


-- ============================================================================
--  1. COLONNES LOTS & PÉREMPTION (produits)
-- ============================================================================

alter table public.produits add column if not exists lot_numero text;
alter table public.produits add column if not exists date_expiration date;

comment on column public.produits.lot_numero is
  'Module 16 C1 (pharmacie) — Numéro de lot du produit (facultatif).';
comment on column public.produits.date_expiration is
  'Module 16 C1 — Date de péremption (facultatif). Une fois dépassée, la vente est bloquée (réglage app_settings ventes.bloquer_produits_expires, défaut actif).';

create index if not exists idx_produits_expiration
  on public.produits (owner_id, date_expiration)
  where date_expiration is not null;


-- ============================================================================
--  2. RÉGLAGE — VENTES : BLOCAGE DES PRODUITS EXPIRÉS (défaut : actif)
-- ============================================================================
--  `true` (défaut) = la caisse refuse de vendre un produit dont la date de
--  péremption est dépassée. Passez la valeur à false pour l'autoriser :
--    update public.app_settings
--       set value = value || '{"bloquer_produits_expires": false}'::jsonb
--     where key = 'ventes';
do $$
begin
  if exists (select 1 from information_schema.tables
              where table_schema = 'public' and table_name = 'app_settings') then
    insert into public.app_settings (key, value)
    select 'ventes', jsonb_build_object('bloquer_produits_expires', true)
     where not exists (select 1 from public.app_settings where key = 'ventes');
  else
    raise notice 'app_settings absente : le réglage ventes.bloquer_produits_expires ne sera pas créé (le code applique le blocage par défaut).';
  end if;
end $$;


-- ============================================================================
--  3. `rpc_vente_valider` — BLOCAGE DES PRODUITS EXPIRÉS
-- ============================================================================
--  Version de la migration 24 (ventes sans conditionnement) + contrôle
--  d'expiration inséré après le contrôle du stock. Le SELECT du produit
--  charge désormais `date_expiration`.

create or replace function public.rpc_vente_valider(
  p_lignes             jsonb,
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
  v_mode        text := coalesce(nullif(btrim(lower(coalesce(p_mode_paiement, ''))), ''), 'especes');
  v_numero      text;
  v_vente_uuid  uuid := gen_random_uuid();
  v_ligne       jsonb;
  v_produit_id  bigint;
  v_produit     record;
  v_cond_id     uuid;
  v_cond        public.conditionnements%rowtype;
  v_qte_base    numeric;
  v_qte_vendue  numeric;
  v_prix_unit   numeric;
  v_prix_ligne  numeric;
  v_total       numeric := 0;
  v_lignes_retour jsonb := '[]'::jsonb;
begin
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

  -- 2 et 3. Vérification du stock (sous verrou) et relecture des prix ----
  --  D'abord : verrouillage de TOUS les articles du panier, dans un ordre
  --  stable (ids croissants). Deux encaissements simultanés ne peuvent donc
  --  jamais s'interbloquer, et le stock lu reste figé jusqu'au commit.
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
      raise exception 'LIGNE_INVALIDE|Une ligne du panier n''a pas d''article.';
    end if;

    v_qte_base := coalesce((v_ligne->>'quantite')::numeric, 0);
    if v_qte_base <= 0 then
      raise exception 'LIGNE_INVALIDE|Quantité invalide pour l''article %.', v_produit_id;
    end if;

    v_qte_vendue := coalesce((v_ligne->>'quantite_vendue')::numeric, v_qte_base);

    -- Verrou : toute vente concurrente sur le même article attend ici.
    select p.id, p.nom, p.owner_id, p.quantite, p.prix_vente,
           p.unite_mesure, p.date_expiration
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

    -- 🧩 MODULE 16 (C1) — PHARMACIE : blocage des produits EXPIRÉS.
    --  Un produit SANS date d'expiration n'est jamais bloqué : aucun impact
    --  pour les commerces qui n'utilisent pas les dates. Le réglage
    --  `app_settings['ventes'].bloquer_produits_expires` (défaut : true)
    --  permet de désactiver ce blocage.
    if v_produit.date_expiration is not null
       and v_produit.date_expiration < current_date
       and coalesce(
             (select (s.value->>'bloquer_produits_expires')::boolean
                from public.app_settings s
               where s.key = 'ventes'),
             true
           ) then
      raise exception 'PRODUIT_EXPIRE|% est expiré depuis le % : vente bloquée.',
        v_produit.nom, to_char(v_produit.date_expiration, 'DD/MM/YYYY');
    end if;

    -- Prix de référence : conditionnement (Module 5) ou unité de base.
    v_cond_id := nullif(v_ligne->>'conditionnement_id', '')::uuid;
    v_prix_unit := v_produit.prix_vente;

    if v_cond_id is not null then
      select c.*
        into v_cond
        from public.conditionnements c
       where c.id = v_cond_id
         and c.produit_id = v_produit_id;

      if not found then
        raise exception 'CONDITIONNEMENT_INVALIDE|Le conditionnement choisi pour % n''existe plus.', v_produit.nom;
      end if;

      v_prix_unit := v_cond.prix_vente;
    end if;

    v_prix_ligne := round(v_prix_unit * v_qte_vendue, 2);
    v_total := v_total + v_prix_ligne;

    -- Ligne insérée dans `ventes` : le trigger du stock retire `v_qte_base`.
    insert into public.ventes (
      produit_id, quantite, prix, mode_paiement, date,
      owner_id, seller_id, client_id, conditionnement_id,
      numero_vente, vente_uuid
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
      v_vente_uuid
    );

    v_lignes_retour := v_lignes_retour || jsonb_build_object(
      'produit_id',      v_produit_id,
      'nom',             v_produit.nom,
      'conditionnement', case when v_cond_id is null then null else v_cond.libelle end,
      'unite',           case when v_cond_id is null then v_produit.unite_mesure else v_cond.libelle end,
      'quantite_vendue', v_qte_vendue,
      'quantite_base',   v_qte_base,
      'prix_unitaire',   v_prix_unit,
      'total',           v_prix_ligne
    );
  end loop;

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
    montant_total, mode_paiement, montant_recu, rendu, numero_transaction
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
    p_numero_transaction
  );

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

revoke all on function public.rpc_vente_valider(jsonb, text, numeric, text, bigint) from public;
revoke all on function public.rpc_vente_valider(jsonb, text, numeric, text, bigint) from anon;
grant execute on function public.rpc_vente_valider(jsonb, text, numeric, text, bigint) to authenticated;


-- ============================================================================
--  4. `rpc_rapport_entreprise` — NOUVEAU TYPE « expirations »
-- ============================================================================
--  Version de la migration 26 (date_trunc corrigé) + branche `expirations` :
--  articles avec date de péremption ≤ aujourd'hui + N jours (filtre `jours`,
--  défaut 90, max 365), triés par urgence, avec lot, statut et valeur.

create or replace function public.rpc_rapport_entreprise(
  p_type    text,
  p_debut   date default null,
  p_fin     date default null,
  p_filtres jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user         uuid := auth.uid();
  v_owner        uuid;
  v_type         text := lower(btrim(coalesce(p_type, '')));
  v_filtres      jsonb := coalesce(p_filtres, '{}'::jsonb);
  v_debut        date;
  v_fin          date;
  v_d0           timestamptz;
  v_d1           timestamptz;
  v_groupe       text;
  v_unite        text;
  v_limite       integer;
  v_categorie    text;
  v_statut       text;
  v_detail       boolean;
  v_alerte       boolean;
  v_finance      boolean;
  v_depenses_ok  boolean;
  v_titre        text := 'Rapport';
  v_colonnes     jsonb := '[]'::jsonb;
  v_lignes       jsonb := '[]'::jsonb;
  v_totaux       jsonb := '{}'::jsonb;
  v_resume       jsonb := '[]'::jsonb;
  v_parametres   jsonb := '{}'::jsonb;
  v_ca           numeric := 0;
  v_cout         numeric := 0;
  v_nb           integer := 0;
  v_total        numeric := 0;
  v_reste        numeric := 0;
  v_solde        numeric := 0;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour générer un rapport.';
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

  -- Période (30 derniers jours par défaut, bornes incluses, UTC).
  v_debut := coalesce(p_debut, current_date - 29);
  v_fin   := coalesce(p_fin, current_date);

  if v_debut > v_fin then
    raise exception 'PERIODE_INVALIDE|La date de début doit précéder la date de fin.';
  end if;
  if (v_fin - v_debut) > 366 then
    raise exception 'PERIODE_INVALIDE|Période trop longue : 366 jours maximum.';
  end if;

  v_d0 := v_debut::timestamptz;
  v_d1 := (v_fin + 1)::timestamptz;

  v_finance     := public.peut('finance', 'voir') or public.peut('depenses', 'voir');
  v_depenses_ok := public.peut('depenses', 'voir');

  case v_type

  -- ===================================================================== ventes
  when 'ventes' then
    if not public.peut('rapports', 'voir') then
      raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de consulter les rapports.';
    end if;

    v_groupe := coalesce(nullif(lower(btrim(coalesce(v_filtres->>'groupe', ''))), ''), 'jour');
    if v_groupe not in ('jour', 'semaine', 'mois') then
      raise exception 'GROUPE_INVALIDE|Regroupement inconnu : « jour », « semaine » ou « mois ».';
    end if;

    -- Correctif 26 — `date_trunc` n'accepte QUE les unités anglaises
    -- ('day', 'week', 'month') : l'unité française faisait échouer le
    -- rapport dès qu'il contenait AU MOINS UNE ligne de données
    -- (« unit "jour" not recognized »), alors qu'un rapport vide passait.
    v_unite := case v_groupe
                 when 'jour'    then 'day'
                 when 'semaine' then 'week'
                 else 'month'
               end;

    v_titre := case v_groupe
                 when 'jour'    then 'Ventes par jour'
                 when 'semaine' then 'Ventes par semaine'
                 else 'Ventes par mois'
               end;
    v_parametres := jsonb_build_object('groupe', v_groupe);

    with agg as (
      select date_trunc(v_unite, v.date)::date as periode,
             count(distinct coalesce(v.vente_uuid::text, 'L' || v.id)) as nb_ventes,
             coalesce(sum(v.quantite), 0) as quantite,
             coalesce(sum(v.prix), 0) as ca,
             coalesce(sum(v.quantite * coalesce(pr.prix_achat, 0)), 0) as cout
        from public.ventes v
        left join public.produits pr on pr.id = v.produit_id
       where v.owner_id = v_owner
         and v.date >= v_d0 and v.date < v_d1
       group by 1
    )
    select coalesce(jsonb_agg(jsonb_build_object(
             'periode',    case when v_groupe = 'mois'
                                then to_char(a.periode, 'MM/YYYY')
                                else to_char(a.periode, 'DD/MM/YYYY') end,
             'nb_ventes',  a.nb_ventes,
             'quantite',   a.quantite,
             'ca',         a.ca,
             'cout',       a.cout,
             'marge',      a.ca - a.cout
           ) order by a.periode), '[]'::jsonb)
      into v_lignes
      from agg a;

    select coalesce(sum(v.prix), 0),
           coalesce(sum(v.quantite * coalesce(pr.prix_achat, 0)), 0),
           count(distinct coalesce(v.vente_uuid::text, 'L' || v.id)),
           coalesce(sum(v.quantite), 0)
      into v_ca, v_cout, v_nb, v_total
      from public.ventes v
      left join public.produits pr on pr.id = v.produit_id
     where v.owner_id = v_owner
       and v.date >= v_d0 and v.date < v_d1;

    v_colonnes := jsonb_build_array(
      jsonb_build_object('cle', 'periode',   'libelle', case when v_groupe = 'mois' then 'Mois' when v_groupe = 'semaine' then 'Semaine (début)' else 'Jour' end, 'type', 'texte'),
      jsonb_build_object('cle', 'nb_ventes', 'libelle', 'Ventes',            'type', 'nombre'),
      jsonb_build_object('cle', 'quantite',  'libelle', 'Quantité',          'type', 'nombre'),
      jsonb_build_object('cle', 'ca',        'libelle', 'Chiffre d''affaires', 'type', 'montant')
    );
    if v_finance then
      v_colonnes := v_colonnes || jsonb_build_array(
        jsonb_build_object('cle', 'cout',  'libelle', 'Coût',  'type', 'montant'),
        jsonb_build_object('cle', 'marge', 'libelle', 'Marge', 'type', 'montant')
      );
    end if;

    v_totaux := jsonb_build_object(
      'nb_ventes', v_nb,
      'quantite',  v_total,
      'ca',        v_ca
    );
    if v_finance then
      v_totaux := v_totaux
        || jsonb_build_object('cout', v_cout, 'marge', v_ca - v_cout);
    end if;

    v_resume := jsonb_build_array(
      jsonb_build_object('libelle', 'Chiffre d''affaires', 'valeur', v_ca, 'type', 'montant'),
      jsonb_build_object('libelle', 'Ventes', 'valeur', v_nb, 'type', 'nombre'),
      jsonb_build_object('libelle', 'Panier moyen',
                         'valeur', case when v_nb > 0 then round((v_ca / v_nb)::numeric, 0) else 0 end,
                         'type', 'montant')
    );
    if v_finance then
      v_resume := v_resume || jsonb_build_array(
        jsonb_build_object('libelle', 'Marge brute', 'valeur', v_ca - v_cout, 'type', 'montant')
      );
    end if;

  -- =========================================================== ventes_article
  when 'ventes_article' then
    if not public.peut('rapports', 'voir') then
      raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de consulter les rapports.';
    end if;

    v_titre := 'Ventes par article';

    with tot as (
      select coalesce(sum(v.prix), 0) as t
        from public.ventes v
       where v.owner_id = v_owner and v.date >= v_d0 and v.date < v_d1
    ),
    agg as (
      select coalesce(pr.nom, 'Article supprimé') as libelle,
             coalesce(sum(v.quantite), 0) as quantite,
             coalesce(sum(v.prix), 0) as ca,
             coalesce(sum(v.quantite * coalesce(pr.prix_achat, 0)), 0) as cout
        from public.ventes v
        left join public.produits pr on pr.id = v.produit_id
       where v.owner_id = v_owner and v.date >= v_d0 and v.date < v_d1
       group by 1
    )
    select coalesce(jsonb_agg(jsonb_build_object(
             'article',  a.libelle,
             'quantite', a.quantite,
             'ca',       a.ca,
             'part',     coalesce(round((100.0 * a.ca / nullif(t.t, 0))::numeric, 1), 0),
             'cout',     a.cout,
             'marge',    a.ca - a.cout
           ) order by a.ca desc, a.libelle), '[]'::jsonb)
      into v_lignes
      from agg a, tot t;

    v_colonnes := jsonb_build_array(
      jsonb_build_object('cle', 'article',  'libelle', 'Article',             'type', 'texte'),
      jsonb_build_object('cle', 'quantite', 'libelle', 'Quantité',            'type', 'nombre'),
      jsonb_build_object('cle', 'ca',       'libelle', 'Chiffre d''affaires', 'type', 'montant'),
      jsonb_build_object('cle', 'part',     'libelle', 'Part',                'type', 'pourcentage')
    );
    if v_finance then
      v_colonnes := v_colonnes || jsonb_build_array(
        jsonb_build_object('cle', 'cout',  'libelle', 'Coût',  'type', 'montant'),
        jsonb_build_object('cle', 'marge', 'libelle', 'Marge', 'type', 'montant')
      );
    end if;

    select coalesce(sum(v.prix), 0),
           coalesce(sum(v.quantite * coalesce(pr.prix_achat, 0)), 0),
           count(distinct v.produit_id),
           coalesce(sum(v.quantite), 0)
      into v_ca, v_cout, v_nb, v_total
      from public.ventes v
      left join public.produits pr on pr.id = v.produit_id
     where v.owner_id = v_owner and v.date >= v_d0 and v.date < v_d1;

    v_totaux := jsonb_build_object('ca', v_ca, 'quantite', v_total, 'nb_articles', v_nb);
    v_resume := jsonb_build_array(
      jsonb_build_object('libelle', 'Chiffre d''affaires', 'valeur', v_ca,   'type', 'montant'),
      jsonb_build_object('libelle', 'Articles vendus',     'valeur', v_nb,   'type', 'nombre'),
      jsonb_build_object('libelle', 'Quantité totale',     'valeur', v_total, 'type', 'nombre')
    );
    if v_finance then
      v_totaux := v_totaux || jsonb_build_object('cout', v_cout, 'marge', v_ca - v_cout);
      v_resume := v_resume || jsonb_build_array(
        jsonb_build_object('libelle', 'Marge brute', 'valeur', v_ca - v_cout, 'type', 'montant')
      );
    end if;

  -- ========================================================= ventes_categorie
  when 'ventes_categorie' then
    if not public.peut('rapports', 'voir') then
      raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de consulter les rapports.';
    end if;

    v_titre := 'Ventes par catégorie';

    with tot as (
      select coalesce(sum(v.prix), 0) as t
        from public.ventes v
       where v.owner_id = v_owner and v.date >= v_d0 and v.date < v_d1
    ),
    agg as (
      select coalesce(nullif(btrim(pr.categorie), ''), 'Non classé') as libelle,
             coalesce(sum(v.quantite), 0) as quantite,
             coalesce(sum(v.prix), 0) as ca,
             coalesce(sum(v.quantite * coalesce(pr.prix_achat, 0)), 0) as cout
        from public.ventes v
        left join public.produits pr on pr.id = v.produit_id
       where v.owner_id = v_owner and v.date >= v_d0 and v.date < v_d1
       group by 1
    )
    select coalesce(jsonb_agg(jsonb_build_object(
             'categorie', a.libelle,
             'quantite',  a.quantite,
             'ca',        a.ca,
             'part',      coalesce(round((100.0 * a.ca / nullif(t.t, 0))::numeric, 1), 0),
             'cout',      a.cout,
             'marge',     a.ca - a.cout
           ) order by a.ca desc, a.libelle), '[]'::jsonb)
      into v_lignes
      from agg a, tot t;

    v_colonnes := jsonb_build_array(
      jsonb_build_object('cle', 'categorie', 'libelle', 'Catégorie',           'type', 'texte'),
      jsonb_build_object('cle', 'quantite',  'libelle', 'Quantité',            'type', 'nombre'),
      jsonb_build_object('cle', 'ca',        'libelle', 'Chiffre d''affaires', 'type', 'montant'),
      jsonb_build_object('cle', 'part',      'libelle', 'Part',                'type', 'pourcentage')
    );
    if v_finance then
      v_colonnes := v_colonnes || jsonb_build_array(
        jsonb_build_object('cle', 'cout',  'libelle', 'Coût',  'type', 'montant'),
        jsonb_build_object('cle', 'marge', 'libelle', 'Marge', 'type', 'montant')
      );
    end if;

    select coalesce(sum(v.prix), 0),
           coalesce(sum(v.quantite * coalesce(pr.prix_achat, 0)), 0),
           count(distinct coalesce(nullif(btrim(pr.categorie), ''), 'Non classé')),
           coalesce(sum(v.quantite), 0)
      into v_ca, v_cout, v_nb, v_total
      from public.ventes v
      left join public.produits pr on pr.id = v.produit_id
     where v.owner_id = v_owner and v.date >= v_d0 and v.date < v_d1;

    v_totaux := jsonb_build_object('ca', v_ca, 'quantite', v_total, 'nb_categories', v_nb);
    v_resume := jsonb_build_array(
      jsonb_build_object('libelle', 'Chiffre d''affaires', 'valeur', v_ca,    'type', 'montant'),
      jsonb_build_object('libelle', 'Catégories',          'valeur', v_nb,    'type', 'nombre'),
      jsonb_build_object('libelle', 'Quantité totale',     'valeur', v_total, 'type', 'nombre')
    );
    if v_finance then
      v_totaux := v_totaux || jsonb_build_object('cout', v_cout, 'marge', v_ca - v_cout);
      v_resume := v_resume || jsonb_build_array(
        jsonb_build_object('libelle', 'Marge brute', 'valeur', v_ca - v_cout, 'type', 'montant')
      );
    end if;

  -- =========================================================== ventes_vendeur
  when 'ventes_vendeur' then
    if not public.peut('rapports', 'voir') then
      raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de consulter les rapports.';
    end if;

    v_titre := 'Ventes par vendeur';

    with tot as (
      select coalesce(sum(v.prix), 0) as t
        from public.ventes v
       where v.owner_id = v_owner and v.date >= v_d0 and v.date < v_d1
    ),
    agg as (
      select coalesce(nullif(btrim(u.nom), ''), nullif(btrim(u.email), ''), 'Vendeur non attribué') as libelle,
             count(distinct coalesce(v.vente_uuid::text, 'L' || v.id)) as nb_ventes,
             coalesce(sum(v.prix), 0) as ca,
             coalesce(sum(v.quantite * coalesce(pr.prix_achat, 0)), 0) as cout
        from public.ventes v
        left join public.utilisateurs u on u.id = v.seller_id
        left join public.produits pr on pr.id = v.produit_id
       where v.owner_id = v_owner and v.date >= v_d0 and v.date < v_d1
       group by 1
    )
    select coalesce(jsonb_agg(jsonb_build_object(
             'vendeur',   a.libelle,
             'nb_ventes', a.nb_ventes,
             'ca',        a.ca,
             'part',      coalesce(round((100.0 * a.ca / nullif(t.t, 0))::numeric, 1), 0),
             'cout',      a.cout,
             'marge',     a.ca - a.cout
           ) order by a.ca desc, a.libelle), '[]'::jsonb)
      into v_lignes
      from agg a, tot t;

    v_colonnes := jsonb_build_array(
      jsonb_build_object('cle', 'vendeur',   'libelle', 'Vendeur',             'type', 'texte'),
      jsonb_build_object('cle', 'nb_ventes', 'libelle', 'Ventes',              'type', 'nombre'),
      jsonb_build_object('cle', 'ca',        'libelle', 'Chiffre d''affaires', 'type', 'montant'),
      jsonb_build_object('cle', 'part',      'libelle', 'Part',                'type', 'pourcentage')
    );
    if v_finance then
      v_colonnes := v_colonnes || jsonb_build_array(
        jsonb_build_object('cle', 'cout',  'libelle', 'Coût',  'type', 'montant'),
        jsonb_build_object('cle', 'marge', 'libelle', 'Marge', 'type', 'montant')
      );
    end if;

    select coalesce(sum(v.prix), 0),
           coalesce(sum(v.quantite * coalesce(pr.prix_achat, 0)), 0),
           count(distinct v.seller_id)
      into v_ca, v_cout, v_nb
      from public.ventes v
      left join public.produits pr on pr.id = v.produit_id
     where v.owner_id = v_owner and v.date >= v_d0 and v.date < v_d1;

    v_totaux := jsonb_build_object('ca', v_ca, 'nb_vendeurs', v_nb);
    v_resume := jsonb_build_array(
      jsonb_build_object('libelle', 'Chiffre d''affaires', 'valeur', v_ca, 'type', 'montant'),
      jsonb_build_object('libelle', 'Vendeurs actifs',     'valeur', v_nb, 'type', 'nombre')
    );
    if v_finance then
      v_totaux := v_totaux || jsonb_build_object('cout', v_cout, 'marge', v_ca - v_cout);
      v_resume := v_resume || jsonb_build_array(
        jsonb_build_object('libelle', 'Marge brute', 'valeur', v_ca - v_cout, 'type', 'montant')
      );
    end if;

  -- ============================================================= top_produits
  when 'top_produits' then
    if not public.peut('rapports', 'voir') then
      raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de consulter les rapports.';
    end if;

    v_limite := case when coalesce(v_filtres->>'limite', '') ~ '^[0-9]+$'
                     then (v_filtres->>'limite')::int else 10 end;
    v_limite := least(greatest(v_limite, 1), 50);

    v_titre := 'Articles les plus vendus';
    v_parametres := jsonb_build_object('limite', v_limite);

    with agg as (
      select coalesce(pr.nom, 'Article supprimé') as libelle,
             coalesce(sum(v.quantite), 0) as quantite,
             coalesce(sum(v.prix), 0) as ca,
             coalesce(sum(v.quantite * coalesce(pr.prix_achat, 0)), 0) as cout
        from public.ventes v
        left join public.produits pr on pr.id = v.produit_id
       where v.owner_id = v_owner and v.date >= v_d0 and v.date < v_d1
       group by 1
       order by quantite desc, ca desc
       limit v_limite
    ),
    classe as (
      -- Correctif 22 — le rang est calculé AVANT l'agrégation jsonb
      -- (corrige « aggregate function calls cannot contain window function calls »).
      select a.*,
             row_number() over (order by a.quantite desc, a.ca desc) as rang
        from agg a
    )
    select coalesce(jsonb_agg(jsonb_build_object(
             'rang',     c.rang,
             'article',  c.libelle,
             'quantite', c.quantite,
             'ca',       c.ca,
             'cout',     c.cout,
             'marge',    c.ca - c.cout
           ) order by c.rang), '[]'::jsonb)
      into v_lignes
      from classe c;

    v_colonnes := jsonb_build_array(
      jsonb_build_object('cle', 'rang',     'libelle', 'N°',                  'type', 'nombre'),
      jsonb_build_object('cle', 'article',  'libelle', 'Article',             'type', 'texte'),
      jsonb_build_object('cle', 'quantite', 'libelle', 'Quantité vendue',     'type', 'nombre'),
      jsonb_build_object('cle', 'ca',       'libelle', 'Chiffre d''affaires', 'type', 'montant')
    );
    if v_finance then
      v_colonnes := v_colonnes || jsonb_build_array(
        jsonb_build_object('cle', 'cout',  'libelle', 'Coût',  'type', 'montant'),
        jsonb_build_object('cle', 'marge', 'libelle', 'Marge', 'type', 'montant')
      );
    end if;

    select coalesce(sum(v.prix), 0),
           coalesce(sum(v.quantite * coalesce(pr.prix_achat, 0)), 0),
           count(distinct v.produit_id)
      into v_ca, v_cout, v_nb
      from public.ventes v
      left join public.produits pr on pr.id = v.produit_id
     where v.owner_id = v_owner and v.date >= v_d0 and v.date < v_d1;

    v_totaux := jsonb_build_object('ca', v_ca, 'nb_articles', v_nb);
    v_resume := jsonb_build_array(
      jsonb_build_object('libelle', 'Chiffre d''affaires', 'valeur', v_ca, 'type', 'montant'),
      jsonb_build_object('libelle', 'Articles vendus',     'valeur', v_nb, 'type', 'nombre')
    );
    if v_finance then
      v_totaux := v_totaux || jsonb_build_object('cout', v_cout, 'marge', v_ca - v_cout);
      v_resume := v_resume || jsonb_build_array(
        jsonb_build_object('libelle', 'Marge brute', 'valeur', v_ca - v_cout, 'type', 'montant')
      );
    end if;

  -- ==================================================================== finance
  when 'finance' then
    if not public.peut('finance', 'voir') then
      raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de consulter la finance.';
    end if;

    v_titre := 'Chiffre d''affaires, dépenses et bénéfice';

    with jours as (
      select generate_series(v_debut, v_fin, interval '1 day')::date as jour
    ),
    v_agg as (
      select date(v.date) as jour,
             count(distinct coalesce(v.vente_uuid::text, 'L' || v.id)) as nb_ventes,
             coalesce(sum(v.prix), 0) as ca,
             coalesce(sum(v.quantite * coalesce(pr.prix_achat, 0)), 0) as cout
        from public.ventes v
        left join public.produits pr on pr.id = v.produit_id
       where v.owner_id = v_owner and v.date >= v_d0 and v.date < v_d1
       group by 1
    ),
    d_agg as (
      select date(dp.date) as jour,
             coalesce(sum(dp.montant), 0) as montant,
             count(*) as nb
        from public.depenses dp
       where dp.owner_id = v_owner and dp.date >= v_d0 and dp.date < v_d1
       group by 1
    )
    select coalesce(jsonb_agg(jsonb_build_object(
             'periode',           to_char(j.jour, 'DD/MM/YYYY'),
             'chiffre_affaires',  coalesce(va.ca, 0),
             'cout_marchandises', coalesce(va.cout, 0),
             'marge_brute',       coalesce(va.ca, 0) - coalesce(va.cout, 0),
             'depenses',          coalesce(da.montant, 0),
             'benefice_net',      coalesce(va.ca, 0) - coalesce(va.cout, 0) - coalesce(da.montant, 0),
             'nb_ventes',         coalesce(va.nb_ventes, 0)
           ) order by j.jour), '[]'::jsonb)
      into v_lignes
      from jours j
      left join v_agg va on va.jour = j.jour
      left join d_agg da on da.jour = j.jour;

    v_colonnes := jsonb_build_array(
      jsonb_build_object('cle', 'periode',           'libelle', 'Jour',                'type', 'texte'),
      jsonb_build_object('cle', 'chiffre_affaires',  'libelle', 'Chiffre d''affaires', 'type', 'montant'),
      jsonb_build_object('cle', 'cout_marchandises', 'libelle', 'Coût marchandises',   'type', 'montant'),
      jsonb_build_object('cle', 'marge_brute',       'libelle', 'Marge brute',         'type', 'montant'),
      jsonb_build_object('cle', 'depenses',          'libelle', 'Dépenses',            'type', 'montant'),
      jsonb_build_object('cle', 'benefice_net',      'libelle', 'Bénéfice net',        'type', 'montant'),
      jsonb_build_object('cle', 'nb_ventes',         'libelle', 'Ventes',              'type', 'nombre')
    );

    select coalesce(sum(v.prix), 0),
           coalesce(sum(v.quantite * coalesce(pr.prix_achat, 0)), 0)
      into v_ca, v_cout
      from public.ventes v
      left join public.produits pr on pr.id = v.produit_id
     where v.owner_id = v_owner and v.date >= v_d0 and v.date < v_d1;

    select coalesce(sum(dp.montant), 0), count(*)
      into v_total, v_nb
      from public.depenses dp
     where dp.owner_id = v_owner and dp.date >= v_d0 and dp.date < v_d1;

    v_totaux := jsonb_build_object(
      'chiffre_affaires',  v_ca,
      'cout_marchandises', v_cout,
      'marge_brute',       v_ca - v_cout,
      'depenses',          v_total,
      'benefice_net',      v_ca - v_cout - v_total
    );
    v_resume := jsonb_build_array(
      jsonb_build_object('libelle', 'Chiffre d''affaires', 'valeur', v_ca,                 'type', 'montant'),
      jsonb_build_object('libelle', 'Marge brute',         'valeur', v_ca - v_cout,        'type', 'montant'),
      jsonb_build_object('libelle', 'Dépenses',            'valeur', v_total,              'type', 'montant'),
      jsonb_build_object('libelle', 'Bénéfice net',        'valeur', v_ca - v_cout - v_total, 'type', 'montant')
    );

  -- ====================================================================== stock
  when 'stock' then
    if not (public.peut('rapports', 'voir') or public.peut('stock', 'voir')) then
      raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de consulter le stock.';
    end if;

    v_categorie := nullif(btrim(coalesce(v_filtres->>'categorie', '')), '');
    v_alerte    := lower(coalesce(v_filtres->>'alerte_seulement', 'false')) in ('true', '1', 'oui', 'vrai');

    v_titre := 'État du stock';
    v_parametres := jsonb_build_object(
      'categorie', coalesce(v_categorie, ''),
      'alerte_seulement', v_alerte
    );

    with agg as (
      select pr.id,
             pr.nom as libelle,
             coalesce(nullif(btrim(pr.categorie), ''), 'Non classé') as categorie,
             coalesce(pr.quantite, 0) as quantite,
             coalesce(pr.seuil_alerte, 0) as seuil,
             case when coalesce(pr.quantite, 0) <= 0 then 'rupture'
                  when coalesce(pr.quantite, 0) <= coalesce(pr.seuil_alerte, 0) then 'faible'
                  else 'ok' end as statut,
             coalesce(pr.prix_achat, 0) as prix_achat,
             coalesce(pr.prix_vente, 0) as prix_vente,
             coalesce(pr.quantite, 0) * coalesce(pr.prix_achat, 0) as valeur_achat,
             coalesce(pr.quantite, 0) * coalesce(pr.prix_vente, 0) as valeur_vente
        from public.produits pr
       where pr.owner_id = v_owner
         and (v_categorie is null or lower(coalesce(pr.categorie, '')) = lower(v_categorie))
         and (not v_alerte or coalesce(pr.quantite, 0) <= coalesce(pr.seuil_alerte, 0))
    )
    select coalesce(jsonb_agg(jsonb_build_object(
             'article',      a.libelle,
             'categorie',    a.categorie,
             'quantite',     a.quantite,
             'seuil',        a.seuil,
             'statut',       a.statut,
             'prix_achat',   a.prix_achat,
             'prix_vente',   a.prix_vente,
             'valeur_achat', a.valeur_achat,
             'valeur_vente', a.valeur_vente
           ) order by case a.statut when 'rupture' then 0 when 'faible' then 1 else 2 end,
                      a.libelle), '[]'::jsonb)
      into v_lignes
      from agg a;

    v_colonnes := jsonb_build_array(
      jsonb_build_object('cle', 'article',      'libelle', 'Article',         'type', 'texte'),
      jsonb_build_object('cle', 'categorie',    'libelle', 'Catégorie',       'type', 'texte'),
      jsonb_build_object('cle', 'quantite',     'libelle', 'Stock (base)',    'type', 'nombre'),
      jsonb_build_object('cle', 'seuil',        'libelle', 'Seuil alerte',    'type', 'nombre'),
      jsonb_build_object('cle', 'statut',       'libelle', 'Statut',          'type', 'texte'),
      jsonb_build_object('cle', 'valeur_achat', 'libelle', 'Valeur d''achat', 'type', 'montant')
    );
    if v_finance then
      v_colonnes := v_colonnes || jsonb_build_array(
        jsonb_build_object('cle', 'prix_achat', 'libelle', 'Prix d''achat', 'type', 'montant'),
        jsonb_build_object('cle', 'prix_vente', 'libelle', 'Prix de vente', 'type', 'montant'),
        jsonb_build_object('cle', 'valeur_vente', 'libelle', 'Valeur de vente', 'type', 'montant')
      );
    end if;

    select count(*),
           count(*) filter (where a.statut <> 'ok'),
           count(*) filter (where a.statut = 'rupture'),
           coalesce(sum(a.valeur_achat), 0),
           coalesce(sum(a.valeur_vente), 0)
      into v_nb, v_total, v_ca, v_cout, v_reste
      from (
        select case when coalesce(pr.quantite, 0) <= 0 then 'rupture'
                    when coalesce(pr.quantite, 0) <= coalesce(pr.seuil_alerte, 0) then 'faible'
                    else 'ok' end as statut,
               coalesce(pr.quantite, 0) * coalesce(pr.prix_achat, 0) as valeur_achat,
               coalesce(pr.quantite, 0) * coalesce(pr.prix_vente, 0) as valeur_vente
          from public.produits pr
         where pr.owner_id = v_owner
           and (v_categorie is null or lower(coalesce(pr.categorie, '')) = lower(v_categorie))
           and (not v_alerte or coalesce(pr.quantite, 0) <= coalesce(pr.seuil_alerte, 0))
      ) a;

    -- v_total = nb alertes, v_ca = nb ruptures, v_cout = valeur achat,
    -- v_reste = valeur vente (réutilisation volontaire des variables).
    v_totaux := jsonb_build_object(
      'nb_articles',  v_nb,
      'nb_alerte',    v_total,
      'nb_rupture',   v_ca,
      'valeur_achat', v_cout,
      'valeur_vente', v_reste
    );
    v_resume := jsonb_build_array(
      jsonb_build_object('libelle', 'Articles',        'valeur', v_nb,     'type', 'nombre'),
      jsonb_build_object('libelle', 'En alerte',       'valeur', v_total,  'type', 'nombre'),
      jsonb_build_object('libelle', 'En rupture',      'valeur', v_ca,     'type', 'nombre'),
      jsonb_build_object('libelle', 'Valeur du stock', 'valeur', v_cout,   'type', 'montant')
    );

  -- ===================================================================== caisse
  when 'caisse' then
    if not (public.peut('caisse', 'voir') or public.peut('finance', 'voir')) then
      raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de consulter la caisse.';
    end if;

    v_titre := 'Caisse — entrées et sorties';

    with jours as (
      select generate_series(v_debut, v_fin, interval '1 day')::date as jour
    ),
    ent as (
      select date(c.date) as jour, c.montant_total as montant
        from public.caisse c
       where c.owner_id = v_owner and c.date >= v_d0 and c.date < v_d1
      union all
      select date(v.date), v.prix
        from public.ventes v
       where v.owner_id = v_owner
         and v.numero_vente is null
         and lower(btrim(coalesce(v.mode_paiement, 'especes'))) <> 'dette'
         and v.date >= v_d0 and v.date < v_d1
      union all
      select date(p.date_paiement), p.montant
        from public.paiements_dette p
        join public.dettes d on d.id = p.dette_id
       where coalesce(p.owner_id, d.owner_id) = v_owner
         and p.date_paiement >= v_d0 and p.date_paiement < v_d1
    ),
    ent_agg as (
      select jour, coalesce(sum(montant), 0) as entrees, count(*) as nb
        from ent group by 1
    ),
    sor_agg as (
      select date(dp.date) as jour, coalesce(sum(dp.montant), 0) as sorties, count(*) as nb
        from public.depenses dp
       where dp.owner_id = v_owner and dp.date >= v_d0 and dp.date < v_d1
       group by 1
    )
    select coalesce(jsonb_agg(jsonb_build_object(
             'periode',  to_char(j.jour, 'DD/MM/YYYY'),
             'entrees',  coalesce(e.entrees, 0),
             'sorties',  case when v_depenses_ok then coalesce(s.sorties, 0) else null end,
             'net',      coalesce(e.entrees, 0)
                         - case when v_depenses_ok then coalesce(s.sorties, 0) else 0 end,
             'nb_operations', coalesce(e.nb, 0)
                              + case when v_depenses_ok then coalesce(s.nb, 0) else 0 end
           ) order by j.jour), '[]'::jsonb)
      into v_lignes
      from jours j
      left join ent_agg e on e.jour = j.jour
      left join sor_agg s on s.jour = j.jour;

    v_colonnes := jsonb_build_array(
      jsonb_build_object('cle', 'periode',  'libelle', 'Jour',       'type', 'texte'),
      jsonb_build_object('cle', 'entrees',  'libelle', 'Entrées',    'type', 'montant')
    );
    if v_depenses_ok then
      v_colonnes := v_colonnes || jsonb_build_array(
        jsonb_build_object('cle', 'sorties', 'libelle', 'Sorties', 'type', 'montant')
      );
    end if;
    v_colonnes := v_colonnes || jsonb_build_array(
      jsonb_build_object('cle', 'net', 'libelle', 'Net', 'type', 'montant'),
      jsonb_build_object('cle', 'nb_operations', 'libelle', 'Opérations', 'type', 'nombre')
    );

    -- Totaux de la période.
    with ent as (
      select c.montant_total as montant
        from public.caisse c
       where c.owner_id = v_owner and c.date >= v_d0 and c.date < v_d1
      union all
      select v.prix
        from public.ventes v
       where v.owner_id = v_owner
         and v.numero_vente is null
         and lower(btrim(coalesce(v.mode_paiement, 'especes'))) <> 'dette'
         and v.date >= v_d0 and v.date < v_d1
      union all
      select p.montant
        from public.paiements_dette p
        join public.dettes d on d.id = p.dette_id
       where coalesce(p.owner_id, d.owner_id) = v_owner
         and p.date_paiement >= v_d0 and p.date_paiement < v_d1
    )
    select coalesce(sum(montant), 0), count(*) into v_ca, v_nb from ent;

    select coalesce(sum(dp.montant), 0) into v_total
      from public.depenses dp
     where dp.owner_id = v_owner and dp.date >= v_d0 and dp.date < v_d1;

    v_totaux := jsonb_build_object(
      'entrees', coalesce(v_ca, 0),
      'sorties', case when v_depenses_ok then coalesce(v_total, 0) else null end,
      'net',     coalesce(v_ca, 0) - case when v_depenses_ok then coalesce(v_total, 0) else 0 end,
      'nb_operations', coalesce(v_nb, 0)
    );

    -- Solde global (tout l'historique), comme le Module 10.
    select
      (select coalesce(sum(c.montant_total), 0)
         from public.caisse c where c.owner_id = v_owner)
      + (select coalesce(sum(v.prix), 0)
           from public.ventes v
          where v.owner_id = v_owner
            and v.numero_vente is null
            and lower(btrim(coalesce(v.mode_paiement, 'especes'))) <> 'dette')
      + (select coalesce(sum(p.montant), 0)
           from public.paiements_dette p
           join public.dettes d on d.id = p.dette_id
          where coalesce(p.owner_id, d.owner_id) = v_owner)
      - (select coalesce(sum(dp.montant), 0)
           from public.depenses dp where dp.owner_id = v_owner)
      into v_solde;

    v_resume := jsonb_build_array(
      jsonb_build_object('libelle', 'Entrées de la période', 'valeur', coalesce(v_ca, 0), 'type', 'montant'),
      jsonb_build_object('libelle', 'Net de la période',
                         'valeur', coalesce(v_ca, 0) - case when v_depenses_ok then coalesce(v_total, 0) else 0 end,
                         'type', 'montant'),
      jsonb_build_object('libelle', 'Solde global de caisse', 'valeur', coalesce(v_solde, 0), 'type', 'montant')
    );
    if v_depenses_ok then
      -- Correctif 22 — « jsonb subscript does not support slices » :
      -- reconstruction explicite (Entrées, Sorties, Net, Solde global).
      v_resume := jsonb_build_array(
        v_resume->0,
        jsonb_build_object('libelle', 'Sorties de la période', 'valeur', coalesce(v_total, 0), 'type', 'montant'),
        v_resume->1,
        v_resume->2
      );
    end if;

  -- =================================================================== depenses
  when 'depenses' then
    if not public.peut('depenses', 'voir') then
      raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de consulter les dépenses.';
    end if;

    v_detail := lower(coalesce(v_filtres->>'detail', 'false')) in ('true', '1', 'oui', 'vrai');
    v_parametres := jsonb_build_object('detail', v_detail);

    if v_detail then
      v_titre := 'Détail des dépenses';

      with base as (
        select dp.date, dp.motif, lower(coalesce(dp.categorie, 'autre')) as categorie, dp.montant
          from public.depenses dp
         where dp.owner_id = v_owner and dp.date >= v_d0 and dp.date < v_d1
         order by dp.date desc
         limit 500
      )
      select coalesce(jsonb_agg(jsonb_build_object(
               'date',      to_char(b.date, 'DD/MM/YYYY'),
               'motif',     b.motif,
               'categorie', b.categorie,
               'montant',   b.montant
             )), '[]'::jsonb)
        into v_lignes
        from base b;

      v_colonnes := jsonb_build_array(
        jsonb_build_object('cle', 'date',      'libelle', 'Date',      'type', 'texte'),
        jsonb_build_object('cle', 'motif',     'libelle', 'Motif',     'type', 'texte'),
        jsonb_build_object('cle', 'categorie', 'libelle', 'Catégorie', 'type', 'texte'),
        jsonb_build_object('cle', 'montant',   'libelle', 'Montant',   'type', 'montant')
      );
    else
      v_titre := 'Dépenses par catégorie';

      with tot as (
        select coalesce(sum(dp.montant), 0) as t
          from public.depenses dp
         where dp.owner_id = v_owner and dp.date >= v_d0 and dp.date < v_d1
      ),
      agg as (
        select lower(coalesce(dp.categorie, 'autre')) as libelle,
               count(*) as nb,
               coalesce(sum(dp.montant), 0) as montant
          from public.depenses dp
         where dp.owner_id = v_owner and dp.date >= v_d0 and dp.date < v_d1
         group by 1
      )
      select coalesce(jsonb_agg(jsonb_build_object(
               'categorie', a.libelle,
               'nb',        a.nb,
               'montant',   a.montant,
               'part',      coalesce(round((100.0 * a.montant / nullif(t.t, 0))::numeric, 1), 0)
             ) order by a.montant desc, a.libelle), '[]'::jsonb)
        into v_lignes
        from agg a, tot t;

      v_colonnes := jsonb_build_array(
        jsonb_build_object('cle', 'categorie', 'libelle', 'Catégorie', 'type', 'texte'),
        jsonb_build_object('cle', 'nb',        'libelle', 'Nombre',    'type', 'nombre'),
        jsonb_build_object('cle', 'montant',   'libelle', 'Montant',   'type', 'montant'),
        jsonb_build_object('cle', 'part',      'libelle', 'Part',      'type', 'pourcentage')
      );
    end if;

    select coalesce(sum(dp.montant), 0), count(*)
      into v_total, v_nb
      from public.depenses dp
     where dp.owner_id = v_owner and dp.date >= v_d0 and dp.date < v_d1;

    select lower(coalesce(dp.categorie, 'autre')), coalesce(sum(dp.montant), 0)
      into v_categorie, v_ca
      from public.depenses dp
     where dp.owner_id = v_owner and dp.date >= v_d0 and dp.date < v_d1
     group by 1
     order by 2 desc
     limit 1;

    v_totaux := jsonb_build_object('montant', coalesce(v_total, 0), 'nb', coalesce(v_nb, 0));
    v_resume := jsonb_build_array(
      jsonb_build_object('libelle', 'Total des dépenses', 'valeur', coalesce(v_total, 0), 'type', 'montant'),
      jsonb_build_object('libelle', 'Nombre',             'valeur', coalesce(v_nb, 0),    'type', 'nombre')
    );
    if v_categorie is not null then
      v_resume := v_resume || jsonb_build_array(
        jsonb_build_object('libelle', 'Principale catégorie', 'valeur', v_categorie, 'type', 'texte'),
        jsonb_build_object('libelle', 'Montant catégorie',    'valeur', coalesce(v_ca, 0), 'type', 'montant')
      );
    end if;

  -- ====================================================================== dettes
  when 'dettes' then
    if not (public.peut('caisse', 'voir') or public.peut('finance', 'voir')) then
      raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de consulter les dettes.';
    end if;

    v_statut := nullif(lower(btrim(coalesce(v_filtres->>'statut', ''))), '');
    if v_statut is not null and v_statut not in ('non_paye', 'partiel', 'paye') then
      raise exception 'STATUT_INVALIDE|Statut inconnu : « non_paye », « partiel » ou « paye ».';
    end if;

    v_titre := 'Dettes clients';
    v_parametres := jsonb_build_object('statut', coalesce(v_statut, ''));

    with base as (
      select d.id, d.client_id, d.montant_total, d.montant_paye, d.statut,
             d.date_creation, d.date_echeance,
             greatest(coalesce(d.montant_total, 0) - coalesce(d.montant_paye, 0), 0) as restant,
             c.nom as client_nom, c.telephone as client_tel
        from public.dettes d
        left join public.clients c on c.id = d.client_id
       where d.owner_id = v_owner
         and (v_statut is null or lower(coalesce(d.statut, 'non_paye')) = v_statut)
       order by (lower(coalesce(d.statut, 'non_paye')) = 'paye'), d.date_creation asc
       limit 500
    )
    select coalesce(jsonb_agg(jsonb_build_object(
             'client',        coalesce(nullif(btrim(b.client_nom), ''), 'Client ' || b.client_id),
             'telephone',     b.client_tel,
             'montant_total', b.montant_total,
             'montant_paye',  b.montant_paye,
             'restant',       b.restant,
             'statut',        lower(coalesce(b.statut, 'non_paye')),
             'jours',         greatest(current_date - b.date_creation::date, 0),
             'echeance',      case when b.date_echeance is null then null
                                   else to_char(b.date_echeance, 'DD/MM/YYYY') end
           )), '[]'::jsonb)
      into v_lignes
      from base b;

    v_colonnes := jsonb_build_array(
      jsonb_build_object('cle', 'client',        'libelle', 'Client',        'type', 'texte'),
      jsonb_build_object('cle', 'telephone',     'libelle', 'Téléphone',     'type', 'texte'),
      jsonb_build_object('cle', 'montant_total', 'libelle', 'Montant total', 'type', 'montant'),
      jsonb_build_object('cle', 'montant_paye',  'libelle', 'Déjà payé',     'type', 'montant'),
      jsonb_build_object('cle', 'restant',       'libelle', 'Restant dû',    'type', 'montant'),
      jsonb_build_object('cle', 'statut',        'libelle', 'Statut',        'type', 'texte'),
      jsonb_build_object('cle', 'jours',         'libelle', 'Ancienneté (j)', 'type', 'nombre'),
      jsonb_build_object('cle', 'echeance',      'libelle', 'Échéance',      'type', 'texte')
    );

    select count(*),
           count(*) filter (where lower(coalesce(d.statut, 'non_paye')) <> 'paye'),
           coalesce(sum(d.montant_total), 0),
           coalesce(sum(d.montant_paye), 0),
           coalesce(sum(greatest(coalesce(d.montant_total, 0) - coalesce(d.montant_paye, 0), 0)), 0),
           count(*) filter (
             where d.date_echeance is not null
               and d.date_echeance < current_date
               and lower(coalesce(d.statut, 'non_paye')) <> 'paye'
           )
      into v_nb, v_total, v_ca, v_cout, v_reste, v_limite
      from public.dettes d
     where d.owner_id = v_owner
       and (v_statut is null or lower(coalesce(d.statut, 'non_paye')) = v_statut);

    -- v_nb lignes, v_total non soldées, v_ca total dû, v_cout payé,
    -- v_reste restant, v_limite en retard (réutilisation volontaire).
    v_totaux := jsonb_build_object(
      'nb',            v_nb,
      'nb_non_soldees', v_total,
      'total_du',      v_ca,
      'total_paye',    v_cout,
      'total_restant', v_reste,
      'nb_en_retard',  v_limite
    );
    v_resume := jsonb_build_array(
      jsonb_build_object('libelle', 'Dettes ouvertes', 'valeur', v_total,  'type', 'nombre'),
      jsonb_build_object('libelle', 'Restant dû',      'valeur', v_reste,  'type', 'montant'),
      jsonb_build_object('libelle', 'En retard',       'valeur', v_limite, 'type', 'nombre')
    );

  -- ================================================================ expirations
  when 'expirations' then
    -- 🧩 MODULE 16 (C1) — PHARMACIE : lots & dates de péremption.
    if not public.peut('articles', 'voir') then
      raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de consulter les articles.';
    end if;

    v_limite := case when coalesce(v_filtres->>'jours', '') ~ '^[0-9]+$'
                     then (v_filtres->>'jours')::int else 90 end;
    v_limite := least(greatest(v_limite, 1), 365);

    v_titre := 'Produits expirés ou proches de la péremption';
    v_parametres := jsonb_build_object('jours', v_limite);

    with base as (
      select pr.nom as libelle,
             coalesce(nullif(btrim(pr.categorie), ''), 'Non classé') as categorie,
             pr.lot_numero,
             pr.date_expiration,
             coalesce(pr.quantite, 0) as quantite,
             coalesce(pr.prix_achat, 0) * coalesce(pr.quantite, 0) as valeur,
             (pr.date_expiration < current_date) as expire,
             (pr.date_expiration - current_date) as jours_restants
        from public.produits pr
       where pr.owner_id = v_owner
         and pr.date_expiration is not null
         and pr.date_expiration <= (current_date + v_limite)
       order by pr.date_expiration asc, pr.nom
       limit 500
    )
    select coalesce(jsonb_agg(jsonb_build_object(
             'article',        b.libelle,
             'categorie',      b.categorie,
             'lot',            b.lot_numero,
             'expiration',     to_char(b.date_expiration, 'DD/MM/YYYY'),
             'jours_restants', b.jours_restants,
             'statut',         case when b.expire then 'expire' else 'proche' end,
             'quantite',       b.quantite,
             'valeur',         b.valeur
           )), '[]'::jsonb)
      into v_lignes
      from base b;

    v_colonnes := jsonb_build_array(
      jsonb_build_object('cle', 'article',        'libelle', 'Article',         'type', 'texte'),
      jsonb_build_object('cle', 'categorie',      'libelle', 'Catégorie',       'type', 'texte'),
      jsonb_build_object('cle', 'lot',            'libelle', 'Lot',             'type', 'texte'),
      jsonb_build_object('cle', 'expiration',     'libelle', 'Expiration',      'type', 'texte'),
      jsonb_build_object('cle', 'jours_restants', 'libelle', 'Jours restants',  'type', 'nombre'),
      jsonb_build_object('cle', 'statut',         'libelle', 'Statut',          'type', 'texte'),
      jsonb_build_object('cle', 'quantite',       'libelle', 'Quantité',        'type', 'nombre'),
      jsonb_build_object('cle', 'valeur',         'libelle', 'Valeur d''achat', 'type', 'montant')
    );

    select count(*),
           count(*) filter (where pr.date_expiration < current_date),
           coalesce(sum(coalesce(pr.prix_achat, 0) * coalesce(pr.quantite, 0)), 0)
      into v_nb, v_total, v_ca
      from public.produits pr
     where pr.owner_id = v_owner
       and pr.date_expiration is not null
       and pr.date_expiration <= (current_date + v_limite);

    -- v_nb = produits suivis, v_total = déjà expirés, v_ca = valeur d'achat.
    v_totaux := jsonb_build_object(
      'nb_produits', v_nb,
      'nb_expires',  v_total,
      'valeur',      v_ca
    );
    v_resume := jsonb_build_array(
      jsonb_build_object('libelle', 'Produits suivis',  'valeur', v_nb,    'type', 'nombre'),
      jsonb_build_object('libelle', 'Déjà expirés',     'valeur', v_total, 'type', 'nombre'),
      jsonb_build_object('libelle', 'Valeur concernée', 'valeur', v_ca,    'type', 'montant')
    );

  else
    raise exception 'TYPE_INVALIDE|Type de rapport inconnu : « % ».', v_type;
  end case;

  return public.rapport_enveloppe(
    v_type, v_titre, 'entreprise',
    v_debut, v_fin,
    v_colonnes, v_lignes, v_totaux, v_resume, v_parametres
  );
end;
$$;

revoke all on function public.rpc_rapport_entreprise(text, date, date, jsonb) from public;
revoke all on function public.rpc_rapport_entreprise(text, date, date, jsonb) from anon;
grant execute on function public.rpc_rapport_entreprise(text, date, date, jsonb) to authenticated;


-- ============================================================================
--  5. VÉRIFICATIONS
-- ============================================================================

-- 5.a Les deux colonnes présentes (lot_numero text, date_expiration date).
select column_name, data_type
  from information_schema.columns
 where table_schema = 'public'
   and table_name = 'produits'
   and column_name in ('lot_numero', 'date_expiration')
 order by column_name;

-- 5.b Réglage du blocage créé (attendu : {"bloquer_produits_expires": true}).
select key, value
  from public.app_settings
 where key = 'ventes';

-- 5.c Exemple d'appel du nouveau rapport (à exécuter avec un vrai compte
--     d'entreprise ; renvoie le rapport vide si aucune date n'existe) :
--     select public.rpc_rapport_entreprise('expirations', null, null, '{"jours": 90}'::jsonb);

-- ============================================================================
--  FIN — Module 16 C1 (pharmacie). L'application (v1.6.0) affiche la carte
--  « Expirations », le rapport dédié, les champs lot/date sur les articles et
--  la ligne « expirations » dans la notification du soir.
-- ============================================================================
