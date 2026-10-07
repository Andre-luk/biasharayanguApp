-- ============================================================================
--  MODULE 21 ter — CLOISONNEMENT DE L'AGENT TERRAIN
--  Migration 20260916000047_agent_terrain_cloisonnement.sql
-- ============================================================================
--
--  À exécuter APRÈS les migrations 40, 41, 43, 44, 45 et 46.
--  IDEMPOTENTE : rejouable sans effet de bord.
--
--  LE PROBLÈME QUE CORRIGE CETTE MIGRATION
--  ---------------------------------------
--  Le rôle AGENT_TERRAIN (migration 43) ouvre au terrain le workflow
--  d'activation, mais SANS CLOISONNEMENT :
--
--    • l'agent lit TOUS les utilisateurs   (`select` direct non filtré) ;
--    • l'agent lit TOUS les dossiers       (`rpc_activation_lister` global) ;
--    • l'agent ne voit AUCUNE de ses boutiques
--      (`rpc_admin_espaces_lister` lui répond ACCES_REFUSE) ;
--    • il peut vérifier/activer un dossier qui n'est pas le sien ;
--    • rien ne relie une entreprise à l'agent qui l'a prise en charge.
--
--  LE MODÈLE RETENU (validé par l'utilisateur)
--  ------------------------------------------
--  Une boutique n'est PAS toujours créée par un agent : l'agent est un
--  ACCÉLÉRATEUR (« secours pour aller vite »). On ajoute donc une colonne
--  `agent_id` NULLABLE :
--
--    agent_id IS NULL  → dossier « plateforme » (créé par le commerçant ou
--                        le bureau) : visible du personnel plateforme ;
--    agent_id = X      → dossier suivi par l'agent X : visible de X (et de
--                        la plateforme), invisible des autres agents.
--
--  Attribution : le premier agent qui AGIT sur un dossier (vérifie, fixe le
--  montant dû, encaisse) le PREND EN CHARGE automatiquement. Un dossier déjà
--  suivi par un autre agent est refusé (`DROIT_REFUSE`).
--
--  CE QUE CETTE MIGRATION CONTIENT
--  -------------------------------
--  1. Les colonnes `agent_id` (entreprises, utilisateurs) + index.
--  2. Les helpers `est_agent_terrain`, `agent_detient_entreprise`,
--     `agent_detient_espace`, `peut_gerer_espace`, `peut_gerer_produit`.
--  3. La fonction d'attribution `m47_agent_revendiquer` (prise en charge).
--  4. Le patinage des RPC du workflow d'activation : prise en charge
--     automatique + refus des dossiers d'un autre agent + liste filtrée.
--  5. `rpc_admin_espaces_lister` ouverte à l'agent, mais CLÔTURÉE sur ses
--     boutiques et ses compteurs.
--  6. Les nouvelles RPC de pilotage de l'agent : `rpc_agent_fiche`,
--     `rpc_agent_utilisateurs_lister`, `rpc_agent_abonnements_lister`,
--     `rpc_agent_rattacher_entreprise`.
--  7. Les policies RLS RESTRICTIVES : un agent ne lit que ses lignes
--     (`utilisateurs`, `entreprises`, `espaces`).
--  8. La délégation vitrine : l'agent gère la vitrine et les publications
--     des SEULES entreprises qu'il a prises en charge.
--
--  Aucune donnée existante n'est modifiée : les entreprises déjà présentes
--  gardent `agent_id = NULL` (dossiers plateforme).
-- ============================================================================


-- ============================================================================
--  1. ATTRIBUTION — LES COLONNES
-- ============================================================================

alter table public.entreprises  add column if not exists agent_id uuid;
alter table public.utilisateurs add column if not exists agent_id uuid;

comment on column public.entreprises.agent_id is
  'Module 21 ter — Agent terrain qui a pris en charge cette entreprise. NULL = dossier plateforme (commerçant autonome ou bureau).';
comment on column public.utilisateurs.agent_id is
  'Module 21 ter — Agent terrain référent du compte. NULL = compte hors périmètre d''un agent.';

create index if not exists idx_entreprises_agent_id
  on public.entreprises (agent_id) where agent_id is not null;
create index if not exists idx_utilisateurs_agent_id
  on public.utilisateurs (agent_id) where agent_id is not null;


-- ============================================================================
--  2. HELPERS
-- ============================================================================

create or replace function public.est_agent_terrain()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public.mon_role() = 'AGENT_TERRAIN', false);
$$;

comment on function public.est_agent_terrain() is
  'Module 21 ter — Vrai si le compte connecté est un AGENT TERRAIN.';

create or replace function public.agent_detient_entreprise(p_entreprise_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.entreprises e
     where e.id = p_entreprise_id
       and e.agent_id is not null
       and e.agent_id = auth.uid()
  );
$$;

comment on function public.agent_detient_entreprise(uuid) is
  'Module 21 ter — Vrai si l''entreprise est prise en charge par l''agent connecté.';

create or replace function public.agent_detient_espace(p_espace_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
      from public.espaces s
      join public.entreprises e on e.id = s.entreprise_id
     where s.id = p_espace_id
       and e.agent_id is not null
       and e.agent_id = auth.uid()
  );
$$;

comment on function public.agent_detient_espace(uuid) is
  'Module 21 ter — Vrai si l''espace appartient à une entreprise prise en charge par l''agent connecté.';

--  Un espace est gérable par : la plateforme, son entreprise propriétaire, ou
--  l'agent qui a pris en charge cette entreprise. Utilisé par les RPC vitrine.
create or replace function public.peut_gerer_espace(p_espace_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.est_plateforme()
      or public.agent_detient_espace(p_espace_id)
      or exists (
           select 1 from public.espaces s
            where s.id = p_espace_id
              and s.entreprise_id = (
                select u.entreprise_id from public.utilisateurs u where u.id = auth.uid()
              )
         );
$$;

comment on function public.peut_gerer_espace(uuid) is
  'Module 21 ter — Droit de gérer la vitrine/publications d''une boutique (plateforme, entreprise propriétaire ou agent référent).';

create or replace function public.peut_gerer_produit(p_produit_id bigint)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.produits p
     where p.id = p_produit_id
       and (
         public.est_plateforme()
         or p.owner_id = public.mon_proprietaire()
         or (public.est_agent_terrain() and p.owner_id in (
               select u.id
                 from public.utilisateurs u
                 join public.entreprises e on e.id = u.entreprise_id
                where e.agent_id = auth.uid()
             ))
       )
  );
$$;

comment on function public.peut_gerer_produit(bigint) is
  'Module 21 ter — Droit de publier/retirer un article (plateforme, propriétaire ou agent référent de l''entreprise).';


-- ============================================================================
--  3. PRISE EN CHARGE D'UN DOSSIER PAR L'AGENT
-- ============================================================================
--  Appelée automatiquement par les RPC du workflow d'activation. Si
--  l'appelant est un agent terrain :
--    • dossier libre (agent_id NULL) → il le prend en charge ;
--    • dossier déjà à lui            → rien à faire ;
--    • dossier d'un AUTRE agent      → DROIT_REFUSE (le serveur tranche).
--  Le rattachement est journalisé (traçabilité Super Admin).

create or replace function public.m47_agent_revendiquer(p_entreprise_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_agent uuid := auth.uid();
  v_agent_id uuid;
begin
  if not public.est_agent_terrain() then
    return jsonb_build_object('ok', true, 'pris_en_charge', false);
  end if;

  select e.agent_id into v_agent_id
    from public.entreprises e
   where e.id = p_entreprise_id;

  if not found then
    return jsonb_build_object('ok', true, 'pris_en_charge', false);
  end if;

  if v_agent_id is not null and v_agent_id <> v_agent then
    raise exception 'DROIT_REFUSE|Ce dossier est déjà suivi par un autre agent.';
  end if;

  if v_agent_id is null then
    update public.entreprises
       set agent_id = v_agent, updated_at = now()
     where id = p_entreprise_id;

    -- Le client du dossier suit son agent référent.
    update public.utilisateurs
       set agent_id = v_agent
     where entreprise_id = p_entreprise_id
       and agent_id is null;

    begin
      insert into public.journal_audit (entreprise_id, action, utilisateur_id, details)
      values (
        p_entreprise_id, 'AGENT_TERRAIN_RATTACHEMENT', v_agent,
        jsonb_build_object('entreprise_id', p_entreprise_id, 'agent_id', v_agent)
      );
    exception when others then null;
    end;

    return jsonb_build_object('ok', true, 'pris_en_charge', true);
  end if;

  return jsonb_build_object('ok', true, 'pris_en_charge', false);
end;
$$;

comment on function public.m47_agent_revendiquer(uuid) is
  'Module 21 ter — Un agent terrain prend en charge un dossier libre ; refuse le dossier d''un autre agent. Journalisé.';

revoke all on function public.m47_agent_revendiquer(uuid) from public, anon;


--  Rattachement MANUEL explicite (écran agent : « prendre en charge »).
create or replace function public.rpc_agent_rattacher_entreprise(p_entreprise_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;
  if not public.est_agent_terrain() then
    raise exception 'DROIT_REFUSE|Réservé à un agent terrain.';
  end if;

  return public.m47_agent_revendiquer(p_entreprise_id);
end;
$$;

comment on function public.rpc_agent_rattacher_entreprise(uuid) is
  'Module 21 ter — L''agent terrain prend explicitement en charge une entreprise libre.';

revoke all on function public.rpc_agent_rattacher_entreprise(uuid) from public, anon;
grant execute on function public.rpc_agent_rattacher_entreprise(uuid) to authenticated;


-- ============================================================================
--  4. WORKFLOW D'ACTIVATION — PRISE EN CHARGE + REFUS DES DOSSIERS D'AUTRUI
-- ============================================================================
--  Les fonctions sont LONGUES et déjà installées : on patche leur corps à un
--  endroit précis (motif obligatoire, marqueur d'idempotence), comme le fait
--  la migration 43 — une correction future en amont n'est pas écrasée.

--  4.a Prise en charge dans `rpc_activation_verifier` et
--      `rpc_activation_valider_finance` (même forme de sélection).
do $m47_claim$
declare
  v_noms text[] := array['rpc_activation_verifier', 'rpc_activation_valider_finance'];
  v_nom  text;
  v_def  text;
  v_new  text;
begin
  foreach v_nom in array v_noms loop
    select pg_get_functiondef(p.oid) into v_def
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = v_nom
     limit 1;

    if v_def is null then
      raise warning 'm47 : % introuvable — étape ignorée.', v_nom;
      continue;
    end if;

    if position('m47_agent_revendiquer' in v_def) > 0 then
      raise notice 'm47 : % déjà patché.', v_nom;
      continue;
    end if;

    v_new := regexp_replace(
      v_def,
      $motif$select \* into v_e
    from public\.entreprises
   where id = p_entreprise_id
   for update;$motif$,
      $repl$select * into v_e
    from public.entreprises
   where id = p_entreprise_id
   for update;

  -- 🔒 MODULE 21 ter — un dossier ne peut être traité que par son agent.
  perform public.m47_agent_revendiquer(p_entreprise_id);$repl$,
      'g');

    if v_new = v_def then
      raise warning 'm47 : motif absent de % — prise en charge NON appliquée (exécutez d''abord les migrations 14, 18, 23 et 43).', v_nom;
    else
      execute v_new;
      raise notice 'm47 : % patché (prise en charge agent).', v_nom;
    end if;
  end loop;
end $m47_claim$;

--  4.b Même chose dans `rpc_activation_definir_montant_total` (forme sur une
--      seule ligne).
do $m47_claim2$
declare
  v_def text;
  v_new text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'rpc_activation_definir_montant_total'
   limit 1;

  if v_def is null then
    raise warning 'm47 : rpc_activation_definir_montant_total introuvable — étape ignorée.';
    return;
  end if;

  if position('m47_agent_revendiquer' in v_def) > 0 then
    raise notice 'm47 : rpc_activation_definir_montant_total déjà patché.';
    return;
  end if;

  v_new := regexp_replace(
    v_def,
    $motif$select \* into v_e from public\.entreprises
   where id = p_entreprise_id for update;$motif$,
    $repl$select * into v_e from public.entreprises
   where id = p_entreprise_id for update;

  perform public.m47_agent_revendiquer(p_entreprise_id);$repl$,
    'g');

  if v_new = v_def then
    raise warning 'm47 : motif absent de rpc_activation_definir_montant_total — étape ignorée.';
  else
    execute v_new;
    raise notice 'm47 : rpc_activation_definir_montant_total patché.';
  end if;
end $m47_claim2$;

--  4.c La liste des dossiers est CLÔTURÉE pour l'agent :
--      ses dossiers + les dossiers LIBRES (à prendre en charge).
--      Le personnel plateforme garde la vue complète.
do $m47_lister$
declare
  v_def text;
  v_new text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'rpc_activation_lister'
   limit 1;

  if v_def is null then
    raise warning 'm47 : rpc_activation_lister introuvable — étape ignorée.';
    return;
  end if;

  if position('m47_cloison' in v_def) > 0 then
    raise notice 'm47 : rpc_activation_lister déjà cloisonné.';
    return;
  end if;

  -- On ajoute le champ agent_id au JSON (l'écran distingue « à prendre »).
  v_new := regexp_replace(
    v_def,
    $motif$'id', e\.id,$motif$,
    $repl$'id', e.id,
          'agent_id', e.agent_id,
          'mon_dossier', (e.agent_id = auth.uid()),$repl$,
    'g');

  -- Puis le filtre de cloisonnement.
  v_new := regexp_replace(
    v_new,
    $motif$where p_etape is null or e\.activation_etape = btrim\(p_etape\)$motif$,
    $repl$where (p_etape is null or e.activation_etape = btrim(p_etape))
           -- m47_cloison : l'agent ne voit que SES dossiers + les dossiers libres.
           and (not public.est_agent_terrain()
                or e.agent_id = auth.uid()
                or e.agent_id is null)$repl$,
    'g');

  if v_new = v_def then
    raise warning 'm47 : motifs absents de rpc_activation_lister — cloisonnement NON appliqué.';
  else
    execute v_new;
    raise notice 'm47 : rpc_activation_lister cloisonné.';
  end if;
end $m47_lister$;


-- ============================================================================
--  5. PARC DES BOUTIQUES — OUVERT À L'AGENT, CLÔTURÉ SUR SES BOUTIQUES
-- ============================================================================
--  Recopie de la version corrigée par la migration 43 (tri/pagination dans la
--  sous-requête), augmentée du cloisonnement agent.

create or replace function public.rpc_admin_espaces_lister(
  p_recherche text default null,
  p_filtre    text default 'tous',
  p_limite    integer default 100,
  p_decalage  integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_q        text := public.biashara_normaliser(p_recherche);
  v_filtre   text := lower(btrim(coalesce(p_filtre, 'tous')));
  v_limite   integer := least(greatest(coalesce(p_limite, 100), 1), 300);
  v_decalage integer := greatest(coalesce(p_decalage, 0), 0);
  v_liste    jsonb := '[]'::jsonb;
  v_total    integer := 0;
  v_actifs   integer := 0;
  v_visibles integer := 0;
  v_agent    boolean := public.est_agent_terrain();
begin
  if not public.est_plateforme() and not v_agent then
    raise exception 'ACCES_REFUSE|Cette action est réservée à l''équipe plateforme ou à un agent terrain.';
  end if;

  if v_filtre not in ('tous', 'actifs', 'inactifs', 'visibles', 'non_visibles') then
    v_filtre := 'tous';
  end if;

  -- Compteurs : clôturés sur les boutiques de l'agent quand il en est un.
  select count(*),
         count(*) filter (where e.actif),
         count(*) filter (where e.visible_publiquement)
    into v_total, v_actifs, v_visibles
    from public.espaces e
    left join public.entreprises ent on ent.id = e.entreprise_id
   where not v_agent or ent.agent_id = auth.uid();

  select coalesce(jsonb_agg(jsonb_build_object(
           'espace_id',  s.id,
           'nom',        s.nom,
           'type',       s.type,
           'actif',      s.actif,
           'visible_publiquement', s.visible_publiquement,
           'statut_localisation',  s.statut_localisation,
           'ville',      s.ville,
           'quartier',   s.quartier,
           'entreprises_id', s.entreprise_id,
           'entreprise', s.entreprise,
           'entreprise_statut', s.entreprise_statut,
           'activation_etape',  s.activation_etape,
           'nb_produits',        s.nb_produits,
           'nb_produits_publies', s.nb_produits_publies,
           'latitude',   s.latitude,
           'longitude',  s.longitude,
           'created_at', s.created_at
         ) order by s.entreprise nulls last, s.nom), '[]'::jsonb)
    into v_liste
    from (
      select e.id, e.nom, e.type, e.actif, e.visible_publiquement,
             e.statut_localisation, e.quartier, e.latitude, e.longitude,
             e.created_at, e.entreprise_id,
             ent.nom as entreprise,
             coalesce(ent.statut::text, '') as entreprise_statut,
             coalesce(ent.activation_etape, 'actif') as activation_etape,
             (select v.nom from public.villes v where v.id = e.ville_id) as ville,
             (select count(*) from public.produits_publications pb
               where pb.espace_id = e.id) as nb_produits,
             (select count(*) from public.produits_publications pb
               where pb.espace_id = e.id and pb.publie) as nb_produits_publies
        from public.espaces e
        left join public.entreprises ent on ent.id = e.entreprise_id
       where (v_q = '' or public.biashara_normaliser(
                coalesce(e.nom, '') || ' ' || coalesce(ent.nom, '') || ' '
                || coalesce((select v.nom from public.villes v where v.id = e.ville_id), '')
                || ' ' || coalesce(e.quartier, ''))
              like '%' || v_q || '%')
         and (
           v_filtre = 'tous'
           or (v_filtre = 'actifs' and e.actif)
           or (v_filtre = 'inactifs' and not e.actif)
           or (v_filtre = 'visibles' and e.visible_publiquement)
           or (v_filtre = 'non_visibles' and not e.visible_publiquement)
         )
         -- 🔒 m47 : l'agent ne voit QUE les boutiques de ses entreprises.
         and (not v_agent or ent.agent_id = auth.uid())
       order by ent.nom nulls last, e.nom
       limit v_limite offset v_decalage
    ) s;

  return jsonb_build_object(
    'ok', true,
    'total', jsonb_build_object(
      'espaces', v_total, 'actifs', v_actifs, 'visibles', v_visibles),
    'espaces', v_liste
  );
end;
$$;

comment on function public.rpc_admin_espaces_lister(text, text, integer, integer) is
  'Module 20/21 — Parc des boutiques. Cloisonné : un agent terrain ne voit que les boutiques de ses entreprises (migration 47).';


-- ============================================================================
--  6. RPC DE PILOTAGE DE L'AGENT
-- ============================================================================

--  6.a FICHE DE L'AGENT — ce qu'il a fait, ses boutiques, ses QR, ses revenus.
--      Un agent ne peut consulter que SA fiche ; le personnel plateforme peut
--      consulter celle de n'importe quel agent (traçabilité Super Admin).
create or replace function public.rpc_agent_fiche(p_agent_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_moi      uuid := auth.uid();
  v_agent    uuid := coalesce(p_agent_id, auth.uid());
  v_prof     public.utilisateurs;
  v_nb_users integer := 0;
  v_nb_ent   integer := 0;
  v_nb_esp   integer := 0;
  v_nb_prod  integer := 0;
  v_nb_cond  integer := 0;
  v_nb_pub   integer := 0;
  v_nb_act   integer := 0;
  v_nb_att   integer := 0;
  v_encaisse numeric := 0;
  v_solde    numeric := 0;
  v_ent      jsonb := '[]'::jsonb;
  v_users    jsonb := '[]'::jsonb;
  v_journal  jsonb := '[]'::jsonb;
begin
  if v_moi is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;

  if not public.est_plateforme() and not public.est_agent_terrain() then
    raise exception 'DROIT_REFUSE|Réservé au personnel plateforme ou à un agent terrain.';
  end if;

  if public.est_agent_terrain() and v_agent <> v_moi then
    raise exception 'DROIT_REFUSE|Un agent ne consulte que sa propre fiche.';
  end if;

  select * into v_prof from public.utilisateurs u where u.id = v_agent;

  -- Compteurs du périmètre de l'agent.
  select count(*) into v_nb_users
    from public.utilisateurs u where u.agent_id = v_agent;

  select count(*),
         count(*) filter (where e.activation_etape = 'actif'),
         count(*) filter (where e.activation_etape in ('en_attente_verification', 'verifie')),
         coalesce(sum(coalesce(e.solde_restant, 0)), 0)
    into v_nb_ent, v_nb_act, v_nb_att, v_solde
    from public.entreprises e where e.agent_id = v_agent;

  select count(*) into v_nb_esp
    from public.espaces s
    join public.entreprises e on e.id = s.entreprise_id
   where e.agent_id = v_agent;

  select count(*) into v_nb_prod
    from public.produits p
   where p.owner_id in (
     select u.id from public.utilisateurs u
      join public.entreprises e on e.id = u.entreprise_id
     where e.agent_id = v_agent);

  select count(*) into v_nb_cond
    from public.conditionnements c
   where c.produit_id in (
     select p.id from public.produits p
      where p.owner_id in (
        select u.id from public.utilisateurs u
         join public.entreprises e on e.id = u.entreprise_id
        where e.agent_id = v_agent));

  select count(*) into v_nb_pub
    from public.produits_publications pb
   where pb.publie
     and pb.espace_id in (
       select s.id from public.espaces s
        join public.entreprises e on e.id = s.entreprise_id
       where e.agent_id = v_agent);

  -- Revenus : ce que SES abonnements ont généré (paiements validés en finance).
  begin
    select coalesce(sum(a.montant), 0) into v_encaisse
      from public.activations_entreprise a
     where a.etape = 'paiement_finance'
       and a.montant is not null
       and a.entreprise_id in (
         select e.id from public.entreprises e where e.agent_id = v_agent);
  exception when others then v_encaisse := 0;
  end;

  -- Ses entreprises (suivi d'abonnement).
  select coalesce(jsonb_agg(jsonb_build_object(
           'entreprise_id', e.id,
           'nom', e.nom,
           'statut', e.statut::text,
           'activation_etape', coalesce(e.activation_etape, 'actif'),
           'solde_restant', coalesce(e.solde_restant, 0),
           'montant_total_du', e.montant_total_du,
           'montant_deja_paye', e.montant_deja_paye,
           'date_expiration', e.date_expiration,
           'created_at', e.created_at
         ) order by e.created_at desc), '[]'::jsonb)
    into v_ent
    from public.entreprises e where e.agent_id = v_agent;

  -- Ses clients (comptes qu'il a onboardés).
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', u.id,
           'nom', u.nom,
           'email', u.email,
           'etelephone', to_jsonb(u) ->> 'telephone',
           'role', coalesce(u.new_role::text, u.role),
           'created_at', u.created_at
         ) order by u.created_at desc), '[]'::jsonb)
    into v_users
    from public.utilisateurs u where u.agent_id = v_agent;

  -- Ses dernières actions (traçabilité).
  begin
    select coalesce(jsonb_agg(jsonb_build_object(
             'action', j.action,
             'created_at', j.created_at,
             'niveau', j.niveau,
             'details', j.details
           ) order by j.created_at desc), '[]'::jsonb)
      into v_journal
      from (
        select a.action, a.created_at, to_jsonb(a) ->> 'niveau' as niveau, a.details
          from public.journal_audit a
         where a.utilisateur_id = v_agent
         order by a.created_at desc
         limit 20
      ) j;
  exception when others then v_journal := '[]'::jsonb;
  end;

  return jsonb_build_object(
    'ok', true,
    'agent_id', v_agent,
    'nom', coalesce(v_prof.nom, ''),
    'email', coalesce(v_prof.email, ''),
    'role', public.mon_role(v_agent),
    'nb_utilisateurs', v_nb_users,
    'nb_entreprises', v_nb_ent,
    'nb_boutiques', v_nb_esp,
    'nb_abonnements_actifs', v_nb_act,
    'nb_en_attente', v_nb_att,
    'nb_produits', v_nb_prod,
    'nb_conditionnements', v_nb_cond,
    'nb_qr_codes', v_nb_prod + v_nb_cond,
    'nb_produits_publies', v_nb_pub,
    'montant_encaisse', v_encaisse,
    'solde_du', v_solde,
    'entreprises', v_ent,
    'utilisateurs', v_users,
    'journal', v_journal
  );
end;
$$;

comment on function public.rpc_agent_fiche(uuid) is
  'Module 21 ter — Fiche d''activité d''un agent terrain : utilisateurs, entreprises/boutiques, produits, QR codes, abonnements et revenus encaissés. Un agent ne voit que la sienne ; la plateforme voit celle de tout agent.';

revoke all on function public.rpc_agent_fiche(uuid) from public, anon;
grant execute on function public.rpc_agent_fiche(uuid) to authenticated;


--  6.b SES UTILISATEURS (clients/patrons qu'il a onboardés).
create or replace function public.rpc_agent_utilisateurs_lister(
  p_agent_id  uuid default null,
  p_recherche text default null,
  p_limite    integer default 200,
  p_decalage  integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_moi    uuid := auth.uid();
  v_agent  uuid := coalesce(p_agent_id, auth.uid());
  v_q      text := public.biashara_normaliser(p_recherche);
  v_limite integer := least(greatest(coalesce(p_limite, 200), 1), 500);
  v_decalage integer := greatest(coalesce(p_decalage, 0), 0);
  v_total  integer := 0;
  v_liste  jsonb := '[]'::jsonb;
begin
  if v_moi is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;
  if not public.est_plateforme() and not public.est_agent_terrain() then
    raise exception 'DROIT_REFUSE|Réservé au personnel plateforme ou à un agent terrain.';
  end if;
  if public.est_agent_terrain() and v_agent <> v_moi then
    raise exception 'DROIT_REFUSE|Un agent ne consulte que ses propres utilisateurs.';
  end if;

  select count(*) into v_total
    from public.utilisateurs u
   where u.agent_id = v_agent
     and (v_q = '' or public.biashara_normaliser(
            coalesce(u.nom, '') || ' ' || coalesce(u.email, '')) like '%' || v_q || '%');

  select coalesce(jsonb_agg(t order by t.created_at desc), '[]'::jsonb)
    into v_liste
    from (
      select jsonb_build_object(
               'id', u.id,
               'nom', u.nom,
               'email', u.email,
               'telephone', to_jsonb(u) ->> 'telephone',
               'role', coalesce(u.new_role::text, u.role),
               'entreprise_id', u.entreprise_id,
               'entreprise', (select e.nom from public.entreprises e where e.id = u.entreprise_id),
               'activation_etape',
                 (select coalesce(e.activation_etape, 'actif')
                    from public.entreprises e where e.id = u.entreprise_id),
               'created_at', u.created_at
             ) as t,
             u.created_at
        from public.utilisateurs u
       where u.agent_id = v_agent
         and (v_q = '' or public.biashara_normaliser(
                coalesce(u.nom, '') || ' ' || coalesce(u.email, '')) like '%' || v_q || '%')
       order by u.created_at desc
       limit v_limite offset v_decalage
    ) s;

  return jsonb_build_object('ok', true, 'total', v_total, 'utilisateurs', v_liste);
end;
$$;

comment on function public.rpc_agent_utilisateurs_lister(uuid, text, integer, integer) is
  'Module 21 ter — Utilisateurs rattachés à un agent terrain (les siens uniquement pour un agent).';

revoke all on function public.rpc_agent_utilisateurs_lister(uuid, text, integer, integer) from public, anon;
grant execute on function public.rpc_agent_utilisateurs_lister(uuid, text, integer, integer) to authenticated;


--  6.c SES ABONNEMENTS (suivi de ce que ses dossiers génèrent).
create or replace function public.rpc_agent_abonnements_lister(
  p_agent_id uuid default null,
  p_filtre   text default 'tous',
  p_limite   integer default 200,
  p_decalage integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_moi    uuid := auth.uid();
  v_agent  uuid := coalesce(p_agent_id, auth.uid());
  v_filtre text := lower(btrim(coalesce(p_filtre, 'tous')));
  v_limite integer := least(greatest(coalesce(p_limite, 200), 1), 500);
  v_decalage integer := greatest(coalesce(p_decalage, 0), 0);
  v_total  integer := 0;
  v_liste  jsonb := '[]'::jsonb;
  v_encaisse numeric := 0;
  v_solde  numeric := 0;
begin
  if v_moi is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;
  if not public.est_plateforme() and not public.est_agent_terrain() then
    raise exception 'DROIT_REFUSE|Réservé au personnel plateforme ou à un agent terrain.';
  end if;
  if public.est_agent_terrain() and v_agent <> v_moi then
    raise exception 'DROIT_REFUSE|Un agent ne consulte que ses propres abonnements.';
  end if;

  if v_filtre not in ('tous', 'actifs', 'en_attente', 'impayes') then
    v_filtre := 'tous';
  end if;

  select count(*),
         coalesce(sum(coalesce(e.solde_restant, 0)), 0)
    into v_total, v_solde
    from public.entreprises e
   where e.agent_id = v_agent
     and (
       v_filtre = 'tous'
       or (v_filtre = 'actifs' and e.activation_etape = 'actif')
       or (v_filtre = 'en_attente' and e.activation_etape in ('en_attente_verification', 'verifie'))
       or (v_filtre = 'impayes' and coalesce(e.solde_restant, 0) > 0)
     );

  begin
    select coalesce(sum(a.montant), 0) into v_encaisse
      from public.activations_entreprise a
     where a.etape = 'paiement_finance'
       and a.montant is not null
       and a.entreprise_id in (select e.id from public.entreprises e where e.agent_id = v_agent);
  exception when others then v_encaisse := 0;
  end;

  select coalesce(jsonb_agg(t order by t.created_at desc), '[]'::jsonb)
    into v_liste
    from (
      select jsonb_build_object(
               'entreprise_id', e.id,
               'nom', e.nom,
               'statut', e.statut::text,
               'activation_etape', coalesce(e.activation_etape, 'actif'),
               'montant_total_du', e.montant_total_du,
               'montant_deja_paye', e.montant_deja_paye,
               'solde_restant', coalesce(e.solde_restant, 0),
               'date_activation', e.date_activation,
               'date_expiration', e.date_expiration,
               'responsable', (
                 select coalesce(nullif(btrim(u.nom), ''), u.email)
                   from public.utilisateurs u
                  where u.entreprise_id = e.id and u.parent_id is null
                  order by u.created_at limit 1),
               'contact', (
                 select u.email from public.utilisateurs u
                  where u.entreprise_id = e.id and u.parent_id is null
                  order by u.created_at limit 1),
               'telephone', (
                 select to_jsonb(u) ->> 'telephone' from public.utilisateurs u
                  where u.entreprise_id = e.id and u.parent_id is null
                  order by u.created_at limit 1),
               'nb_publies', (
                 select count(*) from public.produits_publications pb
                  where pb.publie
                    and pb.espace_id in (select s.id from public.espaces s where s.entreprise_id = e.id))
             ) as t,
             e.created_at
        from public.entreprises e
       where e.agent_id = v_agent
         and (
           v_filtre = 'tous'
           or (v_filtre = 'actifs' and e.activation_etape = 'actif')
           or (v_filtre = 'en_attente' and e.activation_etape in ('en_attente_verification', 'verifie'))
           or (v_filtre = 'impayes' and coalesce(e.solde_restant, 0) > 0)
         )
       order by e.created_at desc
       limit v_limite offset v_decalage
    ) s;

  return jsonb_build_object(
    'ok', true,
    'total', v_total,
    'montant_encaisse', v_encaisse,
    'solde_du', v_solde,
    'abonnements', v_liste
  );
end;
$$;

comment on function public.rpc_agent_abonnements_lister(uuid, text, integer, integer) is
  'Module 21 ter — Suivi des abonnements d''un agent terrain (les siens pour un agent) : montants, soldes, encaissements générés.';

revoke all on function public.rpc_agent_abonnements_lister(uuid, text, integer, integer) from public, anon;
grant execute on function public.rpc_agent_abonnements_lister(uuid, text, integer, integer) to authenticated;


-- ============================================================================
--  7. RLS — L'AGENT NE LIT QUE SON PÉRIMÈTRE
-- ============================================================================
--  Policies RESTRICTIVES (elles se COMBINENT aux policies permissives
--  existantes par un ET) : tout le monde garde ses droits, mais un agent est
--  en plus borné à ses lignes. Un rôle qui n'est pas agent n'est PAS affecté.

alter table public.utilisateurs enable row level security;
alter table public.entreprises  enable row level security;
alter table public.espaces      enable row level security;

drop policy if exists m47_agent_utilisateurs_restrict on public.utilisateurs;
create policy m47_agent_utilisateurs_restrict on public.utilisateurs
  as restrictive for select to authenticated
  using (
    public.mon_role() <> 'AGENT_TERRAIN'
    or id = auth.uid()
    or agent_id = auth.uid()
  );

drop policy if exists m47_agent_entreprises_restrict on public.entreprises;
create policy m47_agent_entreprises_restrict on public.entreprises
  as restrictive for select to authenticated
  using (
    public.mon_role() <> 'AGENT_TERRAIN'
    or agent_id = auth.uid()
  );

drop policy if exists m47_agent_espaces_restrict on public.espaces;
create policy m47_agent_espaces_restrict on public.espaces
  as restrictive for select to authenticated
  using (
    public.mon_role() <> 'AGENT_TERRAIN'
    or public.agent_detient_espace(id)
  );

--  Les articles des boutiques de l'agent sont lisibles par lui (écran QR).
drop policy if exists m47_agent_produits_lecture on public.produits;
create policy m47_agent_produits_lecture on public.produits
  for select to authenticated
  using (
    public.est_agent_terrain()
    and owner_id in (
      select u.id
        from public.utilisateurs u
        join public.entreprises e on e.id = u.entreprise_id
       where e.agent_id = auth.uid()
    )
  );

drop policy if exists m47_agent_conditionnements_lecture on public.conditionnements;
create policy m47_agent_conditionnements_lecture on public.conditionnements
  for select to authenticated
  using (
    public.est_agent_terrain()
    and produit_id in (
      select p.id from public.produits p
       where p.owner_id in (
         select u.id
           from public.utilisateurs u
           join public.entreprises e on e.id = u.entreprise_id
          where e.agent_id = auth.uid()
       )
    )
  );


-- ============================================================================
--  8. DÉLÉGATION VITRINE — L'AGENT GÈRE LES ENTREPRISES QU'IL A PRISES
-- ============================================================================
--  Les RPC vitrine vérifiaient `e.entreprise_id = (entreprise de l'appelant)` :
--  un agent (sans entreprise) était donc refusé. On remplace ce contrôle par
--  `peut_gerer_espace`, qui inclut l'agent référent.

do $m47_vitrine$
declare
  v_noms text[] := array['rpc_biashara_boutique_etat', 'rpc_biashara_boutique_enregistrer'];
  v_nom  text;
  v_def  text;
  v_new  text;
  v_ok   integer := 0;
begin
  foreach v_nom in array v_noms loop
    select pg_get_functiondef(p.oid) into v_def
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = v_nom
     limit 1;

    if v_def is null then
      raise warning 'm47 : % introuvable — délégation vitrine ignorée pour cette fonction.', v_nom;
      continue;
    end if;

    if position('m47_vitrine' in v_def) > 0 then
      raise notice 'm47 : % déjà délégué.', v_nom;
      continue;
    end if;

    v_new := regexp_replace(
      v_def,
      $motif$if not public\.est_plateforme\(\)
     and e\.entreprise_id is distinct from \(\n?\s*select u\.entreprise_id from public\.utilisateurs u where u\.id = auth\.uid\(\)\n?\s*\) then$motif$,
      $repl$-- m47_vitrine : plateforme, entreprise propriétaire OU agent référent.
  if not public.peut_gerer_espace(v_espace) then$repl$,
      'g');

    if v_new = v_def then
      raise warning 'm47 : motif vitrine absent de % — délégation NON appliquée.', v_nom;
    else
      execute v_new;
      v_ok := v_ok + 1;
      raise notice 'm47 : % délégué (agent gérant la vitrine).', v_nom;
    end if;
  end loop;

  if v_ok = 0 then
    raise warning 'm47 : aucune RPC vitrine déléguée (migration 40 absente ?).';
  end if;
end $m47_vitrine$;


--  Publication/dépublication : `peut_gerer_produit` remplace le contrôle de
--  propriété, et l'espace de publication est celui du produit (pas celui de
--  l'appelant, qui n'a pas d'entreprise).
do $m47_publi$
declare
  v_def text;
  v_new text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'rpc_biashara_publication_enregistrer'
   limit 1;

  if v_def is null then
    raise warning 'm47 : rpc_biashara_publication_enregistrer introuvable — étape ignorée.';
    return;
  end if;

  if position('m47_publi' in v_def) > 0 then
    raise notice 'm47 : publication déjà déléguée.';
    return;
  end if;

  v_new := regexp_replace(
    v_def,
    $motif$if v_prod\.owner_id is distinct from v_moi then$motif$,
    $repl$-- m47_publi : le propriétaire OU l'agent référent de l'entreprise.
  if not public.peut_gerer_produit(p_produit_id) then$repl$,
    'g');

  v_new := regexp_replace(
    v_new,
    $motif$v_espace := v_moi;$motif$,
    $repl$v_espace := coalesce(
    (select p.owner_id from public.produits p where p.id = p_produit_id), v_moi);$repl$,
    'g');

  v_new := regexp_replace(
    v_new,
    $motif$p_produit_id, v_moi, v_espace,$motif$,
    $repl$p_produit_id, v_espace, v_espace,$repl$,
    'g');

  if v_new = v_def then
    raise warning 'm47 : motifs absents de la publication — délégation NON appliquée.';
  else
    execute v_new;
    raise notice 'm47 : publication déléguée (agent).';
  end if;
end $m47_publi$;


-- ============================================================================
--  9. VÉRIFICATION — À LANCER SÉPARÉMENT
-- ============================================================================
--  ⚠️ Le SQL Editor exécute tout le texte collé dans UNE transaction : une
--  requête de contrôle qui échoue annulerait le DDL. Ces contrôles sont donc
--  COMMENTÉS. Décommentez-les dans un RUN SÉPARÉ.
--
--  -- 1. Colonnes installées ?
--  select
--    (select count(*) from information_schema.columns
--      where table_schema='public' and table_name='entreprises'  and column_name='agent_id') as ent_col,
--    (select count(*) from information_schema.columns
--      where table_schema='public' and table_name='utilisateurs' and column_name='agent_id') as user_col;
--
--  -- 2. Le workflow est-il patché ?
--  select p.proname,
--         (pg_get_functiondef(p.oid) like '%m47_agent_revendiquer%') as prise_en_charge,
--         (pg_get_functiondef(p.oid) like '%m47_cloison%')          as cloisonnement
--    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--   where n.nspname='public'
--     and p.proname in ('rpc_activation_verifier','rpc_activation_valider_finance',
--                       'rpc_activation_definir_montant_total','rpc_activation_lister');
--
--  -- 3. Fiche de l'agent de démonstration (session agent requise — run séparé) :
--  --    select public.rpc_agent_fiche();
--
-- ============================================================================
--  FIN — module 21 ter.
-- ============================================================================
