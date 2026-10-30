-- ============================================================================
--  biashara_yangu — PHASE 4 : ESPACE AGENT, COMMISSIONS, CONTRÔLE SERVEUR
--
--  Objectif métier
--  ---------------
--  1. Le patron fixe un OBJECTIF de montant et une COMMISSION (%) par tournée.
--     La commission n'est PAS saisie : elle est CALCULÉE en base à la clôture,
--     sur le chiffre d'affaires réellement encaissé de la tournée.
--  2. L'agent ne peut vendre QUE ce qui lui a été confié, et il ne peut
--     jamais toucher à la tournée d'un autre agent (contrôle serveur, pas
--     seulement masquage d'écran).
--  3. Les écarts d'une tournée sont NOMMÉS, jamais noyés : casse déclarée et
--     marchandise offerte en bonus sont des quantités distinctes, tracées
--     séparément du vendu et du retourné.
--  4. La marge par tournée est estimée avec le prix d'achat FIGÉ au moment de
--     la dotation (`prix_achat_snapshot`) : un changement de tarif d'achat
--     plus tard ne réécrit pas l'histoire des tournées passées.
--
--  DÉCISIONS (à ne pas casser)
--  ---------------------------
--   • `commission_montant` et `ecart` sont TOUJOURS calculés, jamais saisis.
--   • Les quantités casse/bonus font partie de l'invariant de dotation :
--       vendue + retournee + bonus + casse <= attribuee
--     (tolérance 0.0001 pour les arrondis de quantités réelles).
--   • Le contrôle d'accès reste dans les RPC (`security definer`), les
--     écritures directes restent révoquées.
--   • Aucune écriture de vente n'est ajoutée ici : `rpc_vente_valider` reste
--     la seule porte d'entrée du chiffre d'affaires.
--
--  PRÉ-REQUIS : 20260916000080_module23_distribution_terrain.sql exécuté.
--  ⚠️ IDEMPOTENT : peut être relancé sans effet de bord.
--  ⚠️ À exécuter dans le SQL Editor Supabase (DDL impossible via PostgREST).
-- ============================================================================

select set_config('search_path', 'public, extensions', true);

-- Contrôle préalable ---------------------------------------------------------
do $$
begin
  if not exists (
    select 1 from information_schema.tables
     where table_schema = 'public' and table_name = 'tournees'
  ) then
    raise exception 'Module 23 absent : exécutez 20260916000080_module23_distribution_terrain.sql.';
  end if;
end $$;


-- ============================================================================
--  1. COLONNES — OBJECTIF, COMMISSION, ZONE, TRACABILITÉ
-- ============================================================================

alter table public.tournees
  add column if not exists zone_couverte     text,
  add column if not exists objectif_montant  numeric,
  add column if not exists commission_taux   numeric,
  add column if not exists commission_montant numeric not null default 0,
  add column if not exists cloturee_par      uuid;

-- Les bornes sont posées par contraintes nommées : un taux de 150 % ou un
-- objectif négatif est une erreur de saisie, pas une opinion.
do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.tournees'::regclass
       and conname = 'tournees_objectif_positif'
  ) then
    alter table public.tournees
      add constraint tournees_objectif_positif
      check (objectif_montant is null or objectif_montant >= 0);
  end if;

  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.tournees'::regclass
       and conname = 'tournees_commission_taux_valide'
  ) then
    alter table public.tournees
      add constraint tournees_commission_taux_valide
      check (commission_taux is null or (commission_taux >= 0 and commission_taux <= 100));
  end if;
end $$;

alter table public.tournee_lignes
  add column if not exists quantite_bonus       real not null default 0,
  add column if not exists quantite_casse       real not null default 0,
  add column if not exists prix_achat_snapshot  real;

comment on column public.tournees.objectif_montant is
  'Objectif de chiffre d''affaires fixé par le patron pour cette tournée.';
comment on column public.tournees.commission_taux is
  'Taux de commission de l''agent en pourcentage (0-100), fixé à la préparation.';
comment on column public.tournees.commission_montant is
  'Commission CALCULÉE à la clôture : chiffre d''affaires × taux. Jamais saisie.';
comment on column public.tournees.cloturee_par is
  'Qui a clôturé : l''agent (retour de marchandise) ou le patron.';
comment on column public.tournee_lignes.quantite_bonus is
  'Quantité offerte en bonus : sort de la dotation SANS créer de chiffre d''affaires.';
comment on column public.tournee_lignes.quantite_casse is
  'Quantité cassée / perdue : sort de la dotation, tracée séparément.';
comment on column public.tournee_lignes.prix_achat_snapshot is
  'Prix d''achat figé au moment de la dotation : sert à la marge, jamais réécrit.';

-- Invariant de dotation : casse et bonus consomment aussi la dotation.
alter table public.tournee_lignes
  drop constraint if exists tournee_lignes_coherence;
alter table public.tournee_lignes
  add constraint tournee_lignes_coherence
  check (quantite_vendue + quantite_retournee + quantite_bonus + quantite_casse
         <= quantite_attribuee + 0.0001);

create index if not exists idx_tournees_statut_agent
  on public.tournees (agent_id, statut, date_tournee desc);


-- ============================================================================
--  2. INSTANTANÉ DU PRIX D'ACHAT (trigger, pour ne pas réécrire rpc_tournee_creer)
-- ============================================================================

create or replace function public.tournee_ligne_snapshot()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.prix_achat_snapshot is null then
    select p.prix_achat into new.prix_achat_snapshot
      from public.produits p
     where p.id = new.produit_id;
  end if;
  return new;
end;
$$;

comment on function public.tournee_ligne_snapshot() is
  'Fige le prix d''achat du produit sur la ligne de dotation (marge historique juste).';

drop trigger if exists trg_tournee_ligne_snapshot on public.tournee_lignes;
create trigger trg_tournee_ligne_snapshot
  before insert on public.tournee_lignes
  for each row execute function public.tournee_ligne_snapshot();

-- Rattrapage des tournées déjà préparées (une seule fois, sans effet si nul).
update public.tournee_lignes l
   set prix_achat_snapshot = p.prix_achat
  from public.produits p
 where p.id = l.produit_id
   and l.prix_achat_snapshot is null;


-- ============================================================================
--  3. RPC — PARAMÉTRER UNE TOURNÉE (OBJECTIF, COMMISSION, ZONE)
-- ============================================================================

-- Pourquoi une RPC séparée : `rpc_tournee_creer` a déjà 5 paramètres et est
-- appelée par l'application en production. On ne change pas sa signature
-- (cela créerait une surcharge), on ajoute le réglage APRÈS la création.
create or replace function public.rpc_tournee_parametrer(
  p_tournee       uuid,
  p_objectif      numeric default null,
  p_commission    numeric default null,
  p_zone_couverte text    default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_t    public.tournees%rowtype;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour paramétrer une tournée.';
  end if;

  select * into v_t from public.tournees where id = p_tournee for update;
  if not found then
    raise exception 'TOURNEE_INTROUVABLE|Cette tournée n''existe plus.';
  end if;

  -- L'objectif et la commission engagent l'argent du patron : lui seul (ou la
  -- plateforme) les fixe. L'agent ne peut pas s'auto-attribuer une commission.
  if not (v_user = v_t.owner_id or public.est_plateforme()) then
    raise exception 'DROIT_REFUSE|Seul le propriétaire fixe l''objectif et la commission.';
  end if;

  if v_t.statut = 'cloturee' then
    raise exception 'STATUT_INVALIDE|Tournée clôturée : la commission est figée.';
  end if;

  if p_commission is not null and (p_commission < 0 or p_commission > 100) then
    raise exception 'TAUX_INVALIDE|La commission doit être comprise entre 0 et 100 %%.';
  end if;

  if p_objectif is not null and p_objectif < 0 then
    raise exception 'OBJECTIF_INVALIDE|L''objectif ne peut pas être négatif.';
  end if;

  update public.tournees
     set objectif_montant = coalesce(p_objectif, objectif_montant),
         commission_taux  = coalesce(p_commission, commission_taux),
         zone_couverte    = coalesce(nullif(p_zone_couverte, ''), zone_couverte)
   where id = p_tournee;

  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(), null, 'TOURNEE_PARAMETREE', v_user,
    jsonb_build_object(
      'tournee', p_tournee, 'reference', v_t.reference,
      'objectif', p_objectif, 'commission_taux', p_commission
    ),
    now()
  );

  return jsonb_build_object(
    'ok', true,
    'id', p_tournee,
    'objectif_montant', (select objectif_montant from public.tournees where id = p_tournee),
    'commission_taux', (select commission_taux from public.tournees where id = p_tournee),
    'zone_couverte', (select zone_couverte from public.tournees where id = p_tournee)
  );
end;
$$;

comment on function public.rpc_tournee_parametrer(uuid, numeric, numeric, text) is
  'Fixe l''objectif de CA et le taux de commission d''une tournée (propriétaire uniquement, avant clôture).';


-- ============================================================================
--  4. RPC — DÉCLARER UNE CASSE OU UN BONUS SUR UNE LIGNE DE DOTATION
-- ============================================================================

create or replace function public.rpc_tournee_declarer_ecart(
  p_tournee    uuid,
  p_produit_id bigint,
  p_type       text,
  p_quantite   numeric,
  p_note       text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_t    public.tournees%rowtype;
  v_l    public.tournee_lignes%rowtype;
  v_type text := lower(coalesce(p_type, ''));
  v_qte  numeric := coalesce(p_quantite, 0);
  v_dispo numeric;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour déclarer un écart.';
  end if;

  if v_type not in ('casse', 'bonus') then
    raise exception 'TYPE_INVALIDE|Type d''écart inconnu (casse ou bonus).';
  end if;

  if v_qte < 0 then
    raise exception 'QUANTITE_INVALIDE|La quantité ne peut pas être négative.';
  end if;

  select * into v_t from public.tournees where id = p_tournee for update;
  if not found then
    raise exception 'TOURNEE_INTROUVABLE|Cette tournée n''existe plus.';
  end if;

  -- Contrôle serveur : le patron, l'agent CONCERNÉ, ou la plateforme.
  -- Un autre agent obtient un refus explicite, même en appelant la RPC.
  if not (v_user = v_t.owner_id or v_user = v_t.agent_id or public.est_plateforme()) then
    raise exception 'DROIT_REFUSE|Vous n''êtes pas l''agent de cette tournée.';
  end if;

  if v_t.statut not in ('preparee', 'en_cours') then
    raise exception 'STATUT_INVALIDE|Cette tournée est clôturée : l''écart ne peut plus bouger.';
  end if;

  select * into v_l
    from public.tournee_lignes l
   where l.tournee_id = p_tournee
     and l.produit_id = p_produit_id
     for update;

  if not found then
    raise exception 'PRODUIT_NON_ATTRIBUE|Cet article ne fait pas partie de la dotation.';
  end if;

  v_dispo := v_l.quantite_attribuee - v_l.quantite_vendue
             - v_l.quantite_retournee - v_l.quantite_casse - v_l.quantite_bonus;

  if v_qte > v_dispo + 0.0001 then
    raise exception 'ECART_SUPERIEUR|Il ne reste que % de « % » : écart refusé.',
      v_dispo, v_l.nom_produit;
  end if;

  if v_type = 'casse' then
    update public.tournee_lignes
       set quantite_casse = v_qte
     where id = v_l.id;
  else
    update public.tournee_lignes
       set quantite_bonus = v_qte
     where id = v_l.id;
  end if;

  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(), null, 'TOURNEE_ECART', v_user,
    jsonb_build_object(
      'tournee', p_tournee, 'reference', v_t.reference,
      'produit_id', p_produit_id, 'nom', v_l.nom_produit,
      'type', v_type, 'quantite', v_qte, 'note', p_note
    ),
    now()
  );

  return jsonb_build_object(
    'ok', true,
    'tournee_id', p_tournee,
    'produit_id', p_produit_id,
    'type', v_type,
    'quantite', v_qte,
    'casse', (select quantite_casse from public.tournee_lignes where id = v_l.id),
    'bonus', (select quantite_bonus from public.tournee_lignes where id = v_l.id)
  );
end;
$$;

comment on function public.rpc_tournee_declarer_ecart(uuid, bigint, text, numeric, text) is
  'Déclare une casse ou un bonus sur une ligne de dotation ; consomme la dotation sans créer de CA.';


-- ============================================================================
--  5. RPC — VENTE DE L'AGENT (dotation complète : casse et bonus inclus)
-- ============================================================================

create or replace function public.rpc_tournee_vente(
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
  v_user    uuid := auth.uid();
  v_t       public.tournees%rowtype;
  v_l       public.tournee_lignes%rowtype;
  v_ligne   jsonb;
  v_pid     bigint;
  v_qte     numeric;
  v_dispo   numeric;
  v_payload jsonb := '[]'::jsonb;
  v_res     jsonb;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour vendre.';
  end if;

  -- La tournée EN COURS de l'agent connecté (une seule possible).
  -- ⚠️ Le filtre est sur `agent_id = v_user` : un agent ne peut pas vendre
  --    sur la tournée d'un autre, même en fabriquant l'appel.
  select * into v_t
    from public.tournees
   where agent_id = v_user
     and statut = 'en_cours'
   order by date_tournee desc, cree_le desc
   limit 1
     for update;

  if not found then
    raise exception 'AUCUNE_TOURNEE|Aucune tournée en cours : demandez au patron de démarrer votre tournée.';
  end if;

  if p_lignes is null
     or jsonb_typeof(p_lignes) <> 'array'
     or jsonb_array_length(p_lignes) = 0 then
    raise exception 'PANIER_VIDE|Ajoutez au moins un article à la vente.';
  end if;

  for v_ligne in select * from jsonb_array_elements(p_lignes)
  loop
    v_pid := nullif(v_ligne->>'produit_id', '')::bigint;
    v_qte := coalesce((v_ligne->>'quantite')::numeric, 0);

    if v_pid is null or v_qte <= 0 then
      raise exception 'LIGNE_INVALIDE|Ligne de vente invalide.';
    end if;

    select * into v_l
      from public.tournee_lignes l
     where l.tournee_id = v_t.id
       and l.produit_id = v_pid
       for update;

    if not found then
      raise exception 'PRODUIT_NON_ATTRIBUE|Cet article ne fait pas partie de votre dotation du jour.';
    end if;

    -- On ne vend pas ce qui n'a pas été confié, ni ce qui est déjà casse/offert.
    v_dispo := v_l.quantite_attribuee - v_l.quantite_vendue
               - v_l.quantite_retournee - v_l.quantite_casse - v_l.quantite_bonus;
    if v_dispo < v_qte then
      raise exception 'ATTRIBUTION_EPUISEE|Il ne vous reste que % de « % » : vente refusée.',
        v_dispo, v_l.nom_produit;
    end if;

    v_payload := v_payload || jsonb_build_object(
      'produit_id', v_pid,
      'quantite', v_qte,
      'quantite_vendue', v_qte
    );
  end loop;

  -- Vente RÉELLE : stock, prix relus en base, caisse, numéro, journal.
  v_res := public.rpc_vente_valider(
    v_payload,
    coalesce(p_mode_paiement, 'especes'),
    p_montant_recu,
    p_numero_transaction,
    p_client_id
  );

  -- Rattachement de la vente à la tournée (CA par agent).
  update public.ventes
     set tournee_id = v_t.id
   where vente_uuid = (v_res->>'vente_uuid')::uuid;

  -- Consommation de la dotation.
  for v_ligne in select * from jsonb_array_elements(p_lignes)
  loop
    v_pid := (v_ligne->>'produit_id')::bigint;
    v_qte := coalesce((v_ligne->>'quantite')::numeric, 0);
    update public.tournee_lignes
       set quantite_vendue = quantite_vendue + v_qte
     where tournee_id = v_t.id
       and produit_id = v_pid;
  end loop;

  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(), null, 'TOURNEE_VENTE', v_user,
    jsonb_build_object(
      'tournee', v_t.id, 'reference_tournee', v_t.reference,
      'numero_vente', v_res->>'numero_vente',
      'total', v_res->>'total'
    ),
    now()
  );

  return v_res || jsonb_build_object(
    'tournee_id', v_t.id,
    'reference_tournee', v_t.reference
  );
end;
$$;

comment on function public.rpc_tournee_vente(jsonb, text, numeric, text, bigint) is
  'Vente d''un agent, plafonnée par sa dotation (casse et bonus déduits) ; délègue à rpc_vente_valider.';


-- ============================================================================
--  6. RPC — CLÔTURE : ÉCARTS NOMMÉS + COMMISSION CALCULÉE
-- ============================================================================

create or replace function public.rpc_tournee_cloturer(
  p_tournee uuid,
  p_retours jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user     uuid := auth.uid();
  v_t        public.tournees%rowtype;
  v_l        public.tournee_lignes%rowtype;
  v_ligne    jsonb;
  v_pid      bigint;
  v_qte      numeric;
  v_ecart    numeric := 0;
  v_ca       numeric := 0;
  v_commission numeric := 0;
  v_lignes   jsonb := '[]'::jsonb;
  v_ecarts   jsonb := '[]'::jsonb;
  v_ligne_ecart numeric;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour clôturer une tournée.';
  end if;

  select * into v_t from public.tournees where id = p_tournee for update;
  if not found then
    raise exception 'TOURNEE_INTROUVABLE|Cette tournée n''existe plus.';
  end if;

  if not (v_user = v_t.owner_id or v_user = v_t.agent_id or public.est_plateforme()) then
    raise exception 'DROIT_REFUSE|Vous n''avez pas accès à cette tournée.';
  end if;

  if v_t.statut <> 'en_cours' then
    raise exception 'STATUT_INVALIDE|Seule une tournée EN COURS peut être clôturée.';
  end if;

  -- Les retours déclarés remplacent la valeur précédente (reprise possible).
  for v_ligne in select * from jsonb_array_elements(coalesce(p_retours, '[]'::jsonb))
  loop
    v_pid := nullif(v_ligne->>'produit_id', '')::bigint;
    v_qte := coalesce((v_ligne->>'quantite')::numeric, 0);

    if v_pid is null or v_qte < 0 then
      raise exception 'LIGNE_INVALIDE|Retour invalide.';
    end if;

    select * into v_l from public.tournee_lignes l
     where l.tournee_id = p_tournee and l.produit_id = v_pid
       for update;

    if not found then
      raise exception 'PRODUIT_NON_ATTRIBUE|Cet article ne fait pas partie de la tournée.';
    end if;

    if v_l.quantite_vendue + v_l.quantite_bonus + v_l.quantite_casse + v_qte
         > v_l.quantite_attribuee + 0.0001 then
      raise exception 'RETOUR_SUPERIEUR|Le retour dépasse ce qui restait pour « % ».', v_l.nom_produit;
    end if;

    update public.tournee_lignes
       set quantite_retournee = v_qte
     where id = v_l.id;
  end loop;

  -- Consolidation ligne par ligne : chaque écart est NOMMÉ.
  for v_l in
    select * from public.tournee_lignes where tournee_id = p_tournee order by nom_produit
  loop
    v_ligne_ecart := v_l.quantite_attribuee - v_l.quantite_vendue
                     - v_l.quantite_retournee - v_l.quantite_bonus - v_l.quantite_casse;
    v_ecart := v_ecart + v_ligne_ecart;

    v_lignes := v_lignes || jsonb_build_object(
      'produit_id', v_l.produit_id,
      'nom', v_l.nom_produit,
      'unite', v_l.unite,
      'attribuee', v_l.quantite_attribuee,
      'vendue', v_l.quantite_vendue,
      'retournee', v_l.quantite_retournee,
      'bonus', v_l.quantite_bonus,
      'casse', v_l.quantite_casse,
      'ecart', v_ligne_ecart
    );

    if v_ligne_ecart <> 0 then
      v_ecarts := v_ecarts || jsonb_build_object(
        'produit_id', v_l.produit_id,
        'nom', v_l.nom_produit,
        'unite', v_l.unite,
        'ecart', v_ligne_ecart
      );
    end if;
  end loop;

  select coalesce(sum(v.prix), 0) into v_ca
    from public.ventes v
   where v.tournee_id = p_tournee;

  -- La commission est CALCULÉE : jamais saisie, jamais devinée.
  v_commission := round(
    v_ca * coalesce(v_t.commission_taux, 0) / 100.0, 2
  );

  update public.tournees
     set statut = 'cloturee',
         cloturee_le = now(),
         cloturee_par = v_user,
         commission_montant = v_commission
   where id = p_tournee;

  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(), null, 'TOURNEE_CLOTUREE', v_user,
    jsonb_build_object(
      'tournee', p_tournee, 'reference', v_t.reference,
      'ca', v_ca, 'ecart', v_ecart, 'commission', v_commission
    ),
    now()
  );

  return jsonb_build_object(
    'ok', true,
    'id', p_tournee,
    'reference', v_t.reference,
    'statut', 'cloturee',
    'chiffre_affaires', v_ca,
    'commission_taux', coalesce(v_t.commission_taux, 0),
    'commission_montant', v_commission,
    'ecart_total', v_ecart,
    'ecarts', v_ecarts,
    'lignes', v_lignes
  );
end;
$$;

comment on function public.rpc_tournee_cloturer(uuid, jsonb) is
  'Clôture une tournée : retours, écarts nommés (casse/bonus séparés) et commission calculée sur le CA réel.';


-- ============================================================================
--  7. RPC — MA TOURNÉE (AGENT) : objectif, commission, casse et bonus visibles
-- ============================================================================

create or replace function public.rpc_ma_tournee()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_t    public.tournees%rowtype;
  v_ca   numeric := 0;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour voir votre tournée.';
  end if;

  select * into v_t
    from public.tournees
   where agent_id = v_user
     and statut in ('preparee', 'en_cours')
   order by date_tournee desc, cree_le desc
   limit 1;

  if not found then
    return jsonb_build_object('ok', false, 'motif', 'AUCUNE_TOURNEE');
  end if;

  select coalesce(sum(v.prix), 0) into v_ca
    from public.ventes v
   where v.tournee_id = v_t.id;

  return jsonb_build_object(
    'ok', true,
    'tournee', jsonb_build_object(
      'id', v_t.id,
      'reference', v_t.reference,
      'date_tournee', v_t.date_tournee,
      'zone', coalesce(v_t.zone_couverte, v_t.zone),
      'statut', v_t.statut,
      'note', v_t.note,
      'objectif_montant', v_t.objectif_montant,
      'commission_taux', v_t.commission_taux,
      -- Estimation en direct : l'agent voit sa commission grossir au fil
      -- des ventes. Elle sera FIGÉE en base à la clôture.
      'commission_estimee', round(v_ca * coalesce(v_t.commission_taux, 0) / 100.0, 2),
      'chiffre_affaires', v_ca
    ),
    'lignes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'produit_id', l.produit_id,
        'nom', l.nom_produit,
        'unite', l.unite,
        'attribuee', l.quantite_attribuee,
        'vendue', l.quantite_vendue,
        'retournee', l.quantite_retournee,
        'bonus', l.quantite_bonus,
        'casse', l.quantite_casse,
        'restante', l.quantite_attribuee - l.quantite_vendue - l.quantite_retournee
                    - l.quantite_bonus - l.quantite_casse,
        'prix_vente', l.prix_vente
      ) order by l.nom_produit)
      from public.tournee_lignes l
      where l.tournee_id = v_t.id
    ), '[]'::jsonb),
    'consignes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', c.id,
        'client_id', c.client_id,
        'client_nom', c.client_nom,
        'zone', c.zone,
        'libelle', c.libelle_contenant,
        'quantite', c.quantite,
        'recuperee', c.quantite_recuperee,
        'restante', c.quantite - c.quantite_recuperee,
        'statut', c.statut,
        'date', c.date_consigne
      ) order by c.date_consigne desc)
      from public.consignes c
      where c.owner_id = v_t.owner_id
        and c.statut in ('chez_client', 'partielle')
    ), '[]'::jsonb),
    'bonus', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', b.id,
        'client_nom', b.client_nom,
        'nature', b.nature,
        'montant', b.montant,
        'description', b.description,
        'date', b.date_bonus
      ) order by b.date_bonus desc)
      from public.bonus_clients b
      where b.agent_id = v_user
        and b.date_bonus::date = current_date
    ), '[]'::jsonb)
  );
end;
$$;


-- ============================================================================
--  8. RPC — RAPPORT PAR AGENT : commission, objectif, casse et bonus
-- ============================================================================

create or replace function public.rpc_tournee_rapport(
  p_debut date default (current_date - 30),
  p_fin   date default current_date,
  p_agent uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user  uuid := auth.uid();
  v_owner uuid;
  v_lignes jsonb;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour consulter le rapport.';
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  if v_user <> v_owner and not public.est_plateforme() then
    raise exception 'DROIT_REFUSE|Seul le propriétaire consulte le rapport de distribution.';
  end if;

  select coalesce(jsonb_agg(x order by x.date_tournee desc, x.reference desc), '[]'::jsonb)
    into v_lignes
    from (
      select
        t.id,
        t.reference,
        t.date_tournee,
        coalesce(t.zone_couverte, t.zone) as zone,
        t.statut,
        coalesce(u.nom, 'Agent supprimé') as agent_nom,
        t.agent_id,
        t.objectif_montant,
        t.commission_taux,
        t.commission_montant,
        (select count(*) from public.tournee_lignes l where l.tournee_id = t.id) as nb_articles,
        coalesce((select sum(l.quantite_attribuee) from public.tournee_lignes l
                   where l.tournee_id = t.id), 0) as quantite_attribuee,
        coalesce((select sum(l.quantite_vendue) from public.tournee_lignes l
                   where l.tournee_id = t.id), 0) as quantite_vendue,
        coalesce((select sum(l.quantite_retournee) from public.tournee_lignes l
                   where l.tournee_id = t.id), 0) as quantite_retournee,
        coalesce((select sum(l.quantite_casse) from public.tournee_lignes l
                   where l.tournee_id = t.id), 0) as quantite_casse,
        coalesce((select sum(l.quantite_bonus) from public.tournee_lignes l
                   where l.tournee_id = t.id), 0) as quantite_bonus,
        -- Écart = confié − vendu − retourné − bonus − casse. Jamais saisi.
        coalesce((select sum(l.quantite_attribuee - l.quantite_vendue - l.quantite_retournee
                             - l.quantite_bonus - l.quantite_casse)
                    from public.tournee_lignes l where l.tournee_id = t.id), 0) as ecart,
        coalesce((select sum(v.prix) from public.ventes v where v.tournee_id = t.id), 0) as chiffre_affaires,
        -- Marge estimée : CA − coût d'achat des unités VENDUES (prix figé).
        coalesce((select sum(l.quantite_vendue * coalesce(l.prix_achat_snapshot, 0))
                    from public.tournee_lignes l where l.tournee_id = t.id), 0) as cout_achat,
        coalesce((select sum(c.quantite - c.quantite_recuperee)
                    from public.consignes c
                   where c.tournee_id = t.id and c.statut in ('chez_client', 'partielle')), 0) as consignes_ouvertes,
        coalesce((select sum(c.quantite) from public.consignes c where c.tournee_id = t.id), 0) as consignes_total,
        coalesce((select sum(b.montant) from public.bonus_clients b where b.tournee_id = t.id), 0) as bonus_total
      from public.tournees t
      left join public.utilisateurs u on u.id = t.agent_id
      where t.owner_id = v_owner
        and t.date_tournee between coalesce(p_debut, current_date - 30) and coalesce(p_fin, current_date)
        and (p_agent is null or t.agent_id = p_agent)
    ) x;

  return jsonb_build_object(
    'ok', true,
    'debut', coalesce(p_debut, current_date - 30),
    'fin', coalesce(p_fin, current_date),
    'lignes', v_lignes,
    'totaux', jsonb_build_object(
      'tournees', (select count(*) from jsonb_array_elements(v_lignes)),
      'chiffre_affaires', (select coalesce(sum((e->>'chiffre_affaires')::numeric), 0)
                             from jsonb_array_elements(v_lignes) e),
      'quantite_vendue', (select coalesce(sum((e->>'quantite_vendue')::numeric), 0)
                            from jsonb_array_elements(v_lignes) e),
      'ecart', (select coalesce(sum((e->>'ecart')::numeric), 0)
                  from jsonb_array_elements(v_lignes) e),
      'casse', (select coalesce(sum((e->>'quantite_casse')::numeric), 0)
                  from jsonb_array_elements(v_lignes) e),
      'quantite_bonus', (select coalesce(sum((e->>'quantite_bonus')::numeric), 0)
                           from jsonb_array_elements(v_lignes) e),
      'commission', (select coalesce(sum((e->>'commission_montant')::numeric), 0)
                       from jsonb_array_elements(v_lignes) e),
      'cout_achat', (select coalesce(sum((e->>'cout_achat')::numeric), 0)
                       from jsonb_array_elements(v_lignes) e),
      'consignes_ouvertes', (select coalesce(sum((e->>'consignes_ouvertes')::numeric), 0)
                               from jsonb_array_elements(v_lignes) e),
      'bonus', (select coalesce(sum((e->>'bonus_total')::numeric), 0)
                  from jsonb_array_elements(v_lignes) e)
    )
  );
end;
$$;


-- ============================================================================
--  9. PRIVILÈGES
-- ============================================================================

revoke all on function public.rpc_tournee_parametrer(uuid, numeric, numeric, text)
  from public;
grant execute on function public.rpc_tournee_parametrer(uuid, numeric, numeric, text)
  to authenticated;

revoke all on function public.rpc_tournee_declarer_ecart(uuid, bigint, text, numeric, text)
  from public;
grant execute on function public.rpc_tournee_declarer_ecart(uuid, bigint, text, numeric, text)
  to authenticated;

-- Les autres RPC remplacées conservent leurs privilèges (create or replace).

-- ============================================================================
--  FIN — PHASE 4
-- ============================================================================
