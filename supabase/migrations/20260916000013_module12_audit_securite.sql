-- ============================================================================
--  biashara_yangu — MODULE 12 : AUDIT & SÉCURITÉ
--
--  Ce module FINALISE la traçabilité et renforce la sécurité de la plateforme :
--
--    1. `public.journal_audit` — durcissement d'une table DÉJÀ existante :
--         • nouvelles colonnes `niveau`, `seq`, `empreinte`, `user_agent` ;
--         • niveau (CRITIQUE/HAUT/MOYEN/INFO) déduit AUTOMATIQUEMENT de
--           l'action par `audit_niveau()` — les RPC des Modules 3→11 en
--           bénéficient sans modification ;
--         • IP relevée côté serveur (en-têtes de la requête) et posée en
--           DÉFAUT : toutes les écritures la récupèrent automatiquement ;
--         • table APPEND-ONLY : UPDATE/DELETE interdits par trigger,
--           policies RLS sans écriture, droits révoqués ;
--         • empreinte SHA-256 CHAÎNÉE (chaque ligne signe la précédente)
--           vérifiable par `rpc_audit_verifier()`.
--
--    2. JOURNALISATION AUTOMATIQUE (triggers serveur — filet de sécurité :
--       même une écriture hors application est tracée) :
--         • `produits`         → ARTICLE_CREE / ARTICLE_MODIFIE /
--                                PRIX_MODIFIE (CRITIQUE) / STOCK_MODIFIE /
--                                ARTICLE_SUPPRIME ;
--         • `conditionnements` → CONDITIONNEMENT_AJOUTE / MODIFIE /
--                                SUPPRIME (+ PRIX_MODIFIE si le prix change) ;
--         • `utilisateurs`     → UTILISATEUR_CREE / MODIFIE / SUPPRIME /
--                                CHANGEMENT_ACTIVATION ;
--         • `entreprises`      → ENTREPRISE_MODIFIEE / ENTREPRISE_SUPPRIMEE
--                                (statut et création déjà tracés Module 3).
--
--    3. RPC APPLICATIVES :
--         • `rpc_audit_logger(...)`      — journaliser une action de l'app
--           (CONNEXION, DECONNEXION, CONNEXION_ECHEC autorisé SANS session) ;
--         • `rpc_audit_lister(...)`      — liste filtrée + pagination
--           (utilisateur, action, dates, entreprise, niveau, recherche) ;
--         • `rpc_audit_verifier(...)`    — contrôle d'intégrité de la chaîne ;
--         • `rpc_securite_connexions()`  — dernières connexions ;
--         • `rpc_securite_alertes()`     — tentatives échouées, IPs suspectes ;
--         • `rpc_securite_reset_permissions()` — réinitialise les permissions
--           (un rôle ou TOUS les rôles).
--
--    4. VERROUS DE SÉCURITÉ :
--         • PRIX : seul le PROPRIÉTAIRE (+ SUPER_ADMIN si réglage finance
--           autorisé) modifie `prix_achat`/`prix_vente` — produit ET
--           conditionnement ; tout changement est tracé (ancien/nouveau) ;
--         • STOCK : la quantité d'un article ne peut être modifiée
--           DIRECTEMENT que par MAGASINIER / PROPRIÉTAIRE / SUPER_ADMIN.
--           Les mouvements légitimes (ventes, approvisionnements, ajustements)
--           passent par des triggers imbriqués : ils ne sont PAS bloqués ;
--         • ABONNEMENT : `verifier_action_sensible()` bloque toute écriture
--           sensible d'une boutique suspendue ou échue (miroir serveur du
--           middleware Dart `SecuriteService`).
--
--    5. ANNULATION DE VENTE : `rpc_vente_annuler(...)` — action CRITIQUE :
--         • réservée au PROPRIÉTAIRE (ou SUPER_ADMIN autorisé) ;
--         • trace AVANT modification (même transaction) ;
--         • restitue le stock via un ajustement, retire l'encaissement de
--           la caisse, puis supprime les lignes de vente ;
--         • toute suppression DIRECTE de `ventes` est bloquée (trigger).
--
--    6. IMPORT RAPIDE D'ARTICLES : `rpc_produits_importer(...)` — jusqu'à
--       500 lignes, création en masse (doublons ignorés) ou mise à jour des
--       fiches existantes ; journalisé en UNE entrée IMPORT_PRODUITS.
--
--  OÙ L'EXÉCUTER
--    Supabase Dashboard → SQL Editor → New query → coller → Run
--
--  PRÉ-REQUIS
--    Modules 3 (journal_audit), 4 (peut/est_plateforme/mon_role), 5
--    (produits/conditionnements), 8 (ventes/caisse), 9 (ajustements),
--    10 (finance_super_admin_autorise) exécutés.
--
--  ⚠️ IDEMPOTENT : peut être relancé sans dupliquer ni détruire de données
--     (les triggers/droits sont recréés, les colonnes vérifiées).
-- ============================================================================


select set_config('search_path', 'public, extensions', true);

-- Contrôle préalable : les objets indispensables.
do $$
declare
  v_table text;
  v_fonction text;
begin
  foreach v_table in array array[
    'journal_audit', 'produits', 'conditionnements', 'ventes', 'caisse',
    'ajustements', 'utilisateurs', 'entreprises', 'app_settings', 'dettes'
  ] loop
    if not exists (
      select 1 from information_schema.tables
       where table_schema = 'public' and table_name = v_table
    ) then
      raise exception
        'Table public.% absente : exécutez d''abord les migrations des modules précédents.', v_table;
    end if;
  end loop;

  foreach v_fonction in array array['peut', 'est_plateforme', 'mon_role', 'mon_proprietaire'] loop
    if not exists (
      select 1 from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      where p.proname = v_fonction and n.nspname = 'public'
    ) then
      raise exception
        'Fonction public.% absente : exécutez d''abord les migrations des modules 4 et 5.', v_fonction;
    end if;
  end loop;
end $$;


-- ============================================================================
--  1. DURCISSEMENT DE `public.journal_audit`
-- ============================================================================

-- 1.a Colonnes manquantes -----------------------------------------------------
alter table public.journal_audit add column if not exists niveau      text;
alter table public.journal_audit add column if not exists user_agent  text;
alter table public.journal_audit add column if not exists empreinte   text;
alter table public.journal_audit add column if not exists ip_address  text;

-- `seq` : ordre total fiable (indépendant de `created_at`, qui peut avoir des
-- ex æquo). Colonne IDENTITY ajoutée de façon idempotente.
do $$
begin
  if not exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'journal_audit'
       and column_name = 'seq'
  ) then
    execute 'alter table public.journal_audit '
         || 'add column seq bigint generated by default as identity';
    raise notice 'journal_audit.seq ajoutée (ordre total).';
  end if;
end $$;

-- Défauts : identifiant, date, IP, agent — les écritures existantes (RPC des
-- modules 3→11) récupèrent ces valeurs SANS être modifiées.
alter table public.journal_audit alter column id        set default gen_random_uuid();
alter table public.journal_audit alter column created_at set default now();

-- Enregistre un en-tête HTTP utile au journal (jamais fourni par le client).
create or replace function public.audit_en_tete(p_nom text)
returns text
language plpgsql
stable
as $$
declare
  v_entetes jsonb;
  v_valeur  text;
begin
  begin
    v_entetes := current_setting('request.headers', true)::jsonb;
  exception
    when others then
      return null;
  end;

  if v_entetes is null then
    return null;
  end if;

  return nullif(btrim(coalesce(v_entetes ->> lower(p_nom), '')), '');
end;
$$;

comment on function public.audit_en_tete(text) is
  'Lit un en-tête de la requête PostgREST (NULL si absent) — jamais fourni par le client.';

-- IP de l'appelant : première valeur de x-forwarded-for, sinon cf-connecting-ip,
-- sinon x-real-ip. Best-effort (NULL hors PostgREST).
create or replace function public.audit_ip()
returns text
language plpgsql
stable
as $$
declare
  v_brut   text;
  v_agents text;
begin
  v_brut := public.audit_en_tete('x-forwarded-for');
  if v_brut is null then
    v_brut := public.audit_en_tete('cf-connecting-ip');
  end if;
  if v_brut is null then
    v_brut := public.audit_en_tete('x-real-ip');
  end if;

  if v_brut is null then
    -- Certaines passerelles n'exposent que le User-Agent : on ne l'utilise
    -- pas comme IP, on renvoie NULL.
    v_agents := public.audit_en_tete('user-agent');
    if v_agents is null then
      return null;
    end if;
    return null;
  end if;

  return nullif(btrim(split_part(v_brut, ',', 1)), '');
end;
$$;

comment on function public.audit_ip() is
  'IP de l''appelant d''après les en-têtes de la requête (best-effort, jamais cliente).';

create or replace function public.audit_user_agent()
returns text
language plpgsql
stable
as $$
declare
  v text;
begin
  v := public.audit_en_tete('user-agent');
  if v is null then
    return null;
  end if;
  return left(v, 300);
end;
$$;

comment on function public.audit_user_agent() is
  'User-Agent de l''appelant (tronqué à 300 caractères).';

-- Posés en DÉFAUT : tout insert (même des RPC des modules précédents)
-- récupère l'IP et l'agent de la requête.
alter table public.journal_audit alter column ip_address set default public.audit_ip();
alter table public.journal_audit alter column user_agent set default public.audit_user_agent();

comment on column public.journal_audit.niveau is
  'Gravité de l''action : CRITIQUE, HAUT, MOYEN ou INFO (déduite de l''action).';
comment on column public.journal_audit.seq is
  'Ordre total des entrées (identity) — sert à la chaîne d''intégrité.';
comment on column public.journal_audit.empreinte is
  'Empreinte SHA-256 chaînée : la ligne signe la précédente (inaltérabilité vérifiable).';
comment on column public.journal_audit.ip_address is
  'IP de l''appelant relevée côté serveur (en-têtes), jamais fournie par le client.';
comment on column public.journal_audit.user_agent is
  'User-Agent de l''appelant (best-effort).';

-- 1.b Index d'exploitation ----------------------------------------------------
create unique index if not exists idx_m12_journal_seq
  on public.journal_audit (seq);
create index if not exists idx_m12_journal_utilisateur_date
  on public.journal_audit (utilisateur_id, created_at desc);
create index if not exists idx_m12_journal_action_date
  on public.journal_audit (action, created_at desc);
create index if not exists idx_m12_journal_niveau_date
  on public.journal_audit (niveau, created_at desc);
create index if not exists idx_m12_journal_boutique
  on public.journal_audit ((details ->> 'boutique'));

-- 1.c Catalogue des niveaux ---------------------------------------------------
--  Mapping OFFICIEL action → niveau (voir docs/module12_analyse_actions.md).
--  Les actions inconnues retombent sur INFO : jamais d'erreur.
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
    when 'RAPPORT'                    then 'INFO'
    else 'INFO'
  end;
$$;

comment on function public.audit_niveau(text) is
  'Niveau de gravité d''une action du journal d''audit (CRITIQUE/HAUT/MOYEN/INFO).';

-- Retro-remplissage des lignes existantes (best-effort : ignoré si le journal
-- est déjà passé append-only lors d'une ré-exécution du script).
do $$
begin
  begin
    update public.journal_audit
       set niveau = public.audit_niveau(action)
     where niveau is null;
  exception
    when others then
      null;
  end;
end $$;

-- 1.d Empreinte chaînée -------------------------------------------------------
--  empreinte(n) = sha256( empreinte(n-1) | seq | id | utilisateur | entreprise
--                        | action | niveau | details | created_at )
--  Un seul verrou d'avis sérialise la chaîne (volume faible, coût négligeable).
create or replace function public.audit_empreinte_ligne(
  p_prec        text,
  p_seq         bigint,
  p_id          uuid,
  p_utilisateur uuid,
  p_entreprise  uuid,
  p_action      text,
  p_niveau      text,
  p_details     jsonb,
  p_created_at  timestamptz
)
returns text
language plpgsql
stable
as $$
declare
  v_texte text;
  v_hash  text;
begin
  v_texte := coalesce(p_prec, '')
          || '|' || coalesce(p_seq::text, '')
          || '|' || coalesce(p_id::text, '')
          || '|' || coalesce(p_utilisateur::text, '')
          || '|' || coalesce(p_entreprise::text, '')
          || '|' || coalesce(p_action, '')
          || '|' || coalesce(p_niveau, '')
          || '|' || coalesce(p_details, '{}'::jsonb)::text
          || '|' || to_char(p_created_at at time zone 'UTC',
                            'YYYY-MM-DD"T"HH24:MI:SS.US');

  -- pgcrypto (schéma extensions sur Supabase) ; repli MD5 si indisponible.
  begin
    execute 'select encode(extensions.digest($1, ''sha256''), ''hex'')'
       into v_hash
        using v_texte;
  exception
    when others then
      v_hash := md5(v_texte);
  end;

  return v_hash;
end;
$$;

comment on function public.audit_empreinte_ligne(text, bigint, uuid, uuid, uuid, text, text, jsonb, timestamptz) is
  'Calcule l''empreinte chaînée d''une ligne du journal (SHA-256, repli MD5).';

-- Trigger BEFORE INSERT : niveau + empreinte, sur la dernière ligne.
create or replace function public.trg_audit_preparer()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_prec text;
begin
  -- Ordre total : sérialise les insertions concurrentes (libéré en fin de
  -- transaction) pour que la chaîne n'ait jamais deux têtes.
  perform pg_advisory_xact_lock(83829112);

  new.niveau := coalesce(
    nullif(upper(btrim(coalesce(new.niveau, ''))), ''),
    public.audit_niveau(new.action)
  );

  new.created_at := coalesce(new.created_at, now());
  new.details    := coalesce(new.details, '{}'::jsonb);

  select a.empreinte
    into v_prec
    from public.journal_audit a
   order by a.seq desc
   limit 1;

  new.empreinte := public.audit_empreinte_ligne(
    v_prec,
    new.seq,
    coalesce(new.id, gen_random_uuid()),
    new.utilisateur_id,
    new.entreprise_id,
    new.action,
    new.niveau,
    new.details,
    new.created_at
  );

  if new.id is null then
    new.id := gen_random_uuid();
  end if;

  return new;
end;
$$;

drop trigger if exists trg_journal_audit_preparer on public.journal_audit;
create trigger trg_journal_audit_preparer
  before insert on public.journal_audit
  for each row
  execute function public.trg_audit_preparer();

-- 1.e APPEND-ONLY : aucune modification, aucune suppression -------------------
create or replace function public.trg_audit_append_only()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  raise exception
    'AUDIT_INALTERABLE|Le journal d''audit est inaltérable : % est interdit sur public.journal_audit.',
    lower(tg_op);
end;
$$;

comment on function public.trg_audit_append_only() is
  'Interdit toute modification/suppression dans journal_audit (append-only).';

drop trigger if exists trg_journal_audit_append_only on public.journal_audit;
create trigger trg_journal_audit_append_only
  before update or delete on public.journal_audit
  for each row
  execute function public.trg_audit_append_only();


-- ============================================================================
--  2. RPC APPLICATIVE — `rpc_audit_logger`, `rpc_audit_lister`,
--     `rpc_audit_verifier`
-- ============================================================================
--  Codes d'erreur : SESSION_ABSENTE | DROIT_REFUSE | ACCES_REFUSE |
--                   AUDIT_ACTION_INVALIDE | HORS_BOUTIQUE | ROLE_INCONNU

-- 2.a `rpc_audit_logger` ------------------------------------------------------
--  Journalise une action pilotée par l'application (AuditService).
--  • CONNEXION / DECONNEXION / CONNEXION_ECHEC : sessions (l'échec est le
--    SEUL cas autorisé SANS session — un utilisateur qui rate son mot de
--    passe n'en a pas). Dans ce cas seuls `email` et `message` sont acceptés
--    dans les détails (anti-spam).
--  • toute autre action : au moins une session ; la portée est déduite du
--    rôle (boutique : entreprise_id = la sienne ; plateforme : libre).
create or replace function public.rpc_audit_logger(
  p_action       text,
  p_details      jsonb default '{}'::jsonb,
  p_entreprise_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user    uuid := auth.uid();
  v_action  text := upper(btrim(coalesce(p_action, '')));
  v_details jsonb := coalesce(p_details, '{}'::jsonb);
  v_owner   uuid;
  v_scope   text;
  v_ligne   record;
begin
  if length(v_action) < 4 then
    raise exception 'AUDIT_ACTION_INVALIDE|Code d''action manquant (4 caractères minimum).';
  end if;

  if jsonb_typeof(v_details) <> 'object' then
    v_details := jsonb_build_object('valeur', v_details);
  end if;

  -- Sans session : seul l'échec de connexion est journalisable.
  if v_user is null then
    if v_action <> 'CONNEXION_ECHEC' then
      raise exception 'SESSION_ABSENTE|Connectez-vous pour journaliser cette action.';
    end if;

    v_details := jsonb_build_object(
      'email',   left(coalesce(v_details ->> 'email', ''), 200),
      'message', left(coalesce(v_details ->> 'message', ''), 300),
      'anonyme', true
    );
    v_scope := 'public';

    insert into public.journal_audit (entreprise_id, action, utilisateur_id, details)
    values (null, v_action, null, v_details)
    returning id, seq, niveau, created_at into v_ligne;

    return jsonb_build_object(
      'id', v_ligne.id, 'seq', v_ligne.seq, 'action', v_action,
      'niveau', v_ligne.niveau, 'created_at', v_ligne.created_at
    );
  end if;

  if public.est_plateforme() then
    v_scope := 'plateforme';
    if p_entreprise_id is not null then
      v_owner := p_entreprise_id;
    end if;
  else
    v_scope := 'entreprise';
    v_owner := public.mon_proprietaire();
    if v_owner is null then
      v_owner := v_user;
    end if;

    if p_entreprise_id is not null and p_entreprise_id <> v_owner then
      raise exception 'HORS_BOUTIQUE|Vous ne pouvez journaliser que pour votre propre entreprise.';
    end if;
  end if;

  if v_action in ('CONNEXION', 'DECONNEXION', 'CONNEXION_ECHEC') then
    v_details := v_details || jsonb_build_object(
      'plateforme', public.est_plateforme()
    );
  end if;

  v_details := v_details || jsonb_build_object(
    'boutique', v_owner,
    'portee',   v_scope
  );

  insert into public.journal_audit (entreprise_id, action, utilisateur_id, details)
  values (v_owner, v_action, v_user, v_details)
  returning id, seq, niveau, created_at into v_ligne;

  return jsonb_build_object(
    'id', v_ligne.id, 'seq', v_ligne.seq, 'action', v_action,
    'niveau', v_ligne.niveau, 'created_at', v_ligne.created_at
  );
end;
$$;

comment on function public.rpc_audit_logger(text, jsonb, uuid) is
  'Journalise une action applicative (connexion, déconnexion, export…) ; CONNEXION_ECHEC accepté sans session.';

-- 2.b `rpc_audit_lister` ------------------------------------------------------
--  Liste filtrée et paginée du journal :
--    • plateforme (audit/voir)  → toutes les lignes (filtre entreprise) ;
--    • entreprise (audit/voir)  → uniquement les lignes de SA boutique
--      (entreprise_id direct OU details.boutique pour les modules 8→10).
--  Filtres : utilisateur, action, niveau, période, entreprise, recherche
--  libre (action, détails, IP).
create or replace function public.rpc_audit_lister(
  p_utilisateur uuid    default null,
  p_action      text    default null,
  p_debut       date    default null,
  p_fin         date    default null,
  p_entreprise  uuid    default null,
  p_recherche   text    default null,
  p_niveau      text    default null,
  p_limit       integer default 50,
  p_offset      integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user      uuid := auth.uid();
  v_owner     uuid;
  v_plan      boolean := false;
  v_limit     integer := least(greatest(coalesce(p_limit, 50), 1), 200);
  v_offset    integer := greatest(coalesce(p_offset, 0), 0);
  v_action    text := nullif(upper(btrim(coalesce(p_action, ''))), '');
  v_niveau    text := nullif(upper(btrim(coalesce(p_niveau, ''))), '');
  v_recherche text := nullif(btrim(coalesce(p_recherche, '')), '');
  v_debut     timestamptz;
  v_fin       timestamptz;
  v_lignes    jsonb := '[]'::jsonb;
  v_total     bigint := 0;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour consulter le journal d''audit.';
  end if;

  v_plan := public.est_plateforme() and public.peut('audit', 'voir');

  if not v_plan then
    if not public.peut('audit', 'voir') then
      raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de consulter le journal d''audit.';
    end if;
    v_owner := public.mon_proprietaire();
    if v_owner is null then
      v_owner := v_user;
    end if;
  end if;

  if p_debut is not null then
    v_debut := p_debut::timestamptz;
  end if;
  if p_fin is not null then
    v_fin := (p_fin + 1)::timestamptz;
  end if;

  select count(*)
    into v_total
    from public.journal_audit ja
   where (case
            when v_plan then
              (p_entreprise is null
               or ja.entreprise_id = p_entreprise
               or (ja.entreprise_id is null
                   and ja.details ->> 'boutique' = p_entreprise::text))
            else
              (ja.entreprise_id = v_owner
               or (ja.entreprise_id is null
                   and ja.details ->> 'boutique' = v_owner::text))
          end)
     and (p_utilisateur is null or ja.utilisateur_id = p_utilisateur)
     and (v_action is null or ja.action = v_action)
     and (v_niveau is null or ja.niveau = v_niveau)
     and (v_debut is null or ja.created_at >= v_debut)
     and (v_fin is null or ja.created_at < v_fin)
     and (v_recherche is null
          or ja.action ilike '%' || v_recherche || '%'
          or ja.details::text ilike '%' || v_recherche || '%'
          or coalesce(ja.ip_address, '') ilike '%' || v_recherche || '%');

  select coalesce(jsonb_agg(ligne order by ordre desc, ordre_seq desc), '[]'::jsonb)
    into v_lignes
    from (
      select jsonb_build_object(
               'id',             ja.id,
               'seq',            ja.seq,
               'utilisateur_id', ja.utilisateur_id,
               'utilisateur',    coalesce(nullif(btrim(u.nom), ''), u.email, ''),
               'email',          u.email,
               'entreprise_id',  ja.entreprise_id,
               'action',         ja.action,
               'niveau',         ja.niveau,
               'details',        ja.details,
               'ip_address',     ja.ip_address,
               'user_agent',     ja.user_agent,
               'created_at',     ja.created_at
             ) as ligne,
             ja.created_at as ordre,
             ja.seq        as ordre_seq
        from public.journal_audit ja
        left join public.utilisateurs u on u.id = ja.utilisateur_id
       where (case
                when v_plan then
                  (p_entreprise is null
                   or ja.entreprise_id = p_entreprise
                   or (ja.entreprise_id is null
                       and ja.details ->> 'boutique' = p_entreprise::text))
                else
                  (ja.entreprise_id = v_owner
                   or (ja.entreprise_id is null
                       and ja.details ->> 'boutique' = v_owner::text))
              end)
         and (p_utilisateur is null or ja.utilisateur_id = p_utilisateur)
         and (v_action is null or ja.action = v_action)
         and (v_niveau is null or ja.niveau = v_niveau)
         and (v_debut is null or ja.created_at >= v_debut)
         and (v_fin is null or ja.created_at < v_fin)
         and (v_recherche is null
              or ja.action ilike '%' || v_recherche || '%'
              or ja.details::text ilike '%' || v_recherche || '%'
              or coalesce(ja.ip_address, '') ilike '%' || v_recherche || '%')
       order by ja.created_at desc, ja.seq desc
       limit v_limit
      offset v_offset
    ) s;

  return jsonb_build_object(
    'lignes',  v_lignes,
    'total',   v_total,
    'limite',  v_limit,
    'offset',  v_offset,
    'portee',  case when v_plan then 'plateforme' else 'entreprise' end,
    'filtres', jsonb_build_object(
      'utilisateur', p_utilisateur,
      'action',      v_action,
      'debut',       p_debut,
      'fin',         p_fin,
      'entreprise',  p_entreprise,
      'recherche',   v_recherche,
      'niveau',      v_niveau
    )
  );
end;
$$;

comment on function public.rpc_audit_lister(uuid, text, date, date, uuid, text, text, integer, integer) is
  'Liste filtrée et paginée du journal d''audit (boutique ou plateforme selon le rôle).';

-- 2.c `rpc_audit_verifier` ----------------------------------------------------
--  Recalcule la chaîne d'empreintes des dernières lignes et signale toute
--  anomalie (ligne altérée, chaîne rompue). Lecture seule, plateforme.
create or replace function public.rpc_audit_verifier(p_limit integer default 200)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user      uuid := auth.uid();
  v_limit     integer := least(greatest(coalesce(p_limit, 200), 1), 1000);
  v_prec      text;
  v_min_seq   bigint;
  v_ligne     record;
  v_hash      text;
  v_nb        integer := 0;
  v_anomalies jsonb := '[]'::jsonb;
  v_premier   bigint;
  v_dernier   bigint;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour vérifier le journal.';
  end if;

  if not (public.est_plateforme() and public.peut('audit', 'voir')) then
    raise exception 'ACCES_REFUSE|Seul le personnel de la plateforme peut vérifier l''intégrité du journal.';
  end if;

  select min(seq) into v_min_seq
    from (
      select seq
        from public.journal_audit
       where empreinte is not null
       order by seq desc
       limit v_limit
    ) s;

  if v_min_seq is null then
    return jsonb_build_object(
      'verifie', true, 'nb_controle', 0, 'nb_anomalies', 0,
      'anomalies', '[]'::jsonb
    );
  end if;

  select empreinte
    into v_prec
    from public.journal_audit
   where seq < v_min_seq
     and empreinte is not null
   order by seq desc
   limit 1;

  for v_ligne in
    select seq, id, utilisateur_id, entreprise_id, action, niveau, details, created_at, empreinte
      from public.journal_audit
     where seq >= v_min_seq
     order by seq asc
  loop
    v_nb := v_nb + 1;
    if v_premier is null then
      v_premier := v_ligne.seq;
    end if;
    v_dernier := v_ligne.seq;

    v_hash := public.audit_empreinte_ligne(
      v_prec,
      v_ligne.seq,
      v_ligne.id,
      v_ligne.utilisateur_id,
      v_ligne.entreprise_id,
      v_ligne.action,
      v_ligne.niveau,
      v_ligne.details,
      v_ligne.created_at
    );

    if v_hash is distinct from v_ligne.empreinte then
      v_anomalies := v_anomalies || jsonb_build_array(jsonb_build_object(
        'seq',        v_ligne.seq,
        'id',         v_ligne.id,
        'action',     v_ligne.action,
        'created_at', v_ligne.created_at,
        'attendu',    v_hash,
        'trouve',     v_ligne.empreinte
      ));
    end if;

    v_prec := v_ligne.empreinte;
  end loop;

  return jsonb_build_object(
    'verifie',      jsonb_array_length(v_anomalies) = 0,
    'nb_controle',  v_nb,
    'nb_anomalies', jsonb_array_length(v_anomalies),
    'premier_seq',  v_premier,
    'dernier_seq',  v_dernier,
    'anomalies',    v_anomalies
  );
end;
$$;

comment on function public.rpc_audit_verifier(integer) is
  'Vérifie l''intégrité de la chaîne d''empreintes du journal (plateforme).';


-- ============================================================================
--  3. VERROUS DE SÉCURITÉ — PRIX, STOCK
-- ============================================================================

-- 3.a PRIX DES ARTICLES : seul le PROPRIÉTAIRE (ou Super Admin autorisé) -----
--  Remplace la règle du Module 4 (qui ne bloquait que le VENDEUR). Message
--  VENDEUR conservé à l'identique pour l'application.
create or replace function public.empecher_modification_prix()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role     text := public.mon_role();
  v_change   boolean;
begin
  v_change := (to_jsonb(new) ->> 'prix_vente') is distinct from (to_jsonb(old) ->> 'prix_vente')
           or (to_jsonb(new) ->> 'prix_achat') is distinct from (to_jsonb(old) ->> 'prix_achat')
           or (to_jsonb(new) ->> 'prix')      is distinct from (to_jsonb(old) ->> 'prix');

  if not v_change then
    return new;
  end if;

  -- Canaux administrateur (SQL Editor, service_role) : toutes les clés sont
  -- déjà entre les mains de l'opérateur — on laisse passer (tracé ailleurs).
  if auth.uid() is null then
    return new;
  end if;

  if v_role = 'PROPRIETAIRE' then
    return new;
  end if;

  if v_role = 'SUPER_ADMIN' and public.finance_super_admin_autorise() then
    return new;
  end if;

  if v_role = 'VENDEUR' then
    raise exception 'PRIX_INTERDIT_VENDEUR|Un vendeur ne modifie jamais un prix.';
  end if;

  raise exception 'PRIX_INTERDIT|Seul le propriétaire peut modifier les prix.';
end;
$$;

comment on function public.empecher_modification_prix() is
  'Module 12 : seul le PROPRIÉTAIRE (ou Super Admin autorisé) modifie un prix produit.';

do $$
begin
  execute 'drop trigger if exists trg_produits_prix_vendeur on public.produits';
  execute 'drop trigger if exists trg_produits_prix on public.produits';
  execute 'create trigger trg_produits_prix
             before update on public.produits
             for each row execute function public.empecher_modification_prix()';
  raise notice 'Verrou prix actif sur public.produits (Module 12).';
end $$;

-- 3.b PRIX DES CONDITIONNEMENTS : même règle --------------------------------
create or replace function public.empecher_modification_prix_conditionnement()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text := public.mon_role();
begin
  if (to_jsonb(new) ->> 'prix_vente') is not distinct from (to_jsonb(old) ->> 'prix_vente') then
    return new;
  end if;

  if auth.uid() is null then
    return new;
  end if;

  if v_role = 'PROPRIETAIRE' then
    return new;
  end if;

  if v_role = 'SUPER_ADMIN' and public.finance_super_admin_autorise() then
    return new;
  end if;

  if v_role = 'VENDEUR' then
    raise exception 'PRIX_INTERDIT_VENDEUR|Un vendeur ne modifie jamais un prix.';
  end if;

  raise exception 'PRIX_INTERDIT|Seul le propriétaire peut modifier les prix.';
end;
$$;

comment on function public.empecher_modification_prix_conditionnement() is
  'Module 12 : seul le PROPRIÉTAIRE (ou Super Admin autorisé) modifie le prix d''un conditionnement.';

drop trigger if exists trg_conditionnements_prix on public.conditionnements;
create trigger trg_conditionnements_prix
  before update on public.conditionnements
  for each row
  execute function public.empecher_modification_prix_conditionnement();

-- 3.c STOCK : modification directe réservée MAGASINIER / PROPRIÉTAIRE --------
--  Les mouvements légitimes (insert `ventes` → décrément, `approvisionnements`
--  → incrément, `ajustements` → delta) passent par des triggers imbriqués :
--  `pg_trigger_depth() > 1`. Ils ne sont donc JAMAIS bloqués par ce verrou.
create or replace function public.empecher_stock_non_autorise()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text;
begin
  if (to_jsonb(new) ->> 'quantite') is not distinct from (to_jsonb(old) ->> 'quantite') then
    return new;
  end if;

  -- Écriture imbriquée (mouvement de vente / appro / ajustement) : légitime.
  if pg_trigger_depth() > 1 then
    return new;
  end if;

  -- Canaux administrateur.
  if auth.uid() is null then
    return new;
  end if;

  v_role := public.mon_role();
  if v_role in ('MAGASINIER', 'PROPRIETAIRE', 'SUPER_ADMIN') then
    return new;
  end if;

  raise exception
    'STOCK_INTERDIT|Seuls le magasinier et le propriétaire peuvent modifier le stock directement.';
end;
$$;

comment on function public.empecher_stock_non_autorise() is
  'Module 12 : update direct de produits.quantite réservé MAGASINIER/PROPRIÉTAIRE (mouvements internes non concernés).';

drop trigger if exists trg_produits_stock on public.produits;
create trigger trg_produits_stock
  before update on public.produits
  for each row
  execute function public.empecher_stock_non_autorise();


-- ============================================================================
--  4. JOURNALISATION AUTOMATIQUE (TRIGGERS SERVEUR)
-- ============================================================================
--  Tous best-effort : une écriture métier ne doit jamais échouer parce que le
--  journal est indisponible (pattern Module 4). Sauf mention, l'auteur
--  (auth.uid()) et l'IP (défaut de colonne) sont relevés automatiquement.

-- 4.a ARTICLES -----------------------------------------------------------------
create or replace function public.trg_produits_audit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner       uuid;
  v_changes     jsonb := '{}'::jsonb;
  v_prix_change boolean := false;
  v_stock_change boolean := false;
  v_direct      boolean := pg_trigger_depth() <= 1;
  v_import      boolean := coalesce(current_setting('app.import_produits', true), '') = '1';
begin
  begin
    if tg_op = 'INSERT' then
      -- Un import en masse écrit SA propre entrée IMPORT_PRODUITS : pas de
      -- 500 lignes de bruit en plus.
      if v_import then
        return new;
      end if;

      insert into public.journal_audit (entreprise_id, action, utilisateur_id, details)
      values (
        null, 'ARTICLE_CREE', auth.uid(),
        jsonb_build_object(
          'produit_id',  new.id,
          'nom',         new.nom,
          'categorie',   new.categorie,
          'prix_achat',  new.prix_achat,
          'prix_vente',  new.prix_vente,
          'quantite',    new.quantite,
          'unite_mesure', new.unite_mesure,
          'boutique',    new.owner_id
        )
      );
      return new;
    end if;

    if tg_op = 'UPDATE' then
      v_owner := coalesce(new.owner_id, old.owner_id);

      v_prix_change := (new.prix_vente is distinct from old.prix_vente)
                    or (new.prix_achat is distinct from old.prix_achat);
      v_stock_change := new.quantite is distinct from old.quantite;

      -- Mouvement interne (vente, appro, ajustement) : déjà tracé par la RPC
      -- du mouvement — aucune écriture de bruit.
      if not v_direct then
        return new;
      end if;

      v_changes := jsonb_strip_nulls(jsonb_build_object(
        'nom',         case when new.nom         is distinct from old.nom
                            then jsonb_build_object('ancien', old.nom, 'nouveau', new.nom) end,
        'categorie',   case when new.categorie   is distinct from old.categorie
                            then jsonb_build_object('ancien', old.categorie, 'nouveau', new.categorie) end,
        'unite_mesure', case when new.unite_mesure is distinct from old.unite_mesure
                            then jsonb_build_object('ancien', old.unite_mesure, 'nouveau', new.unite_mesure) end,
        'description', case when new.description is distinct from old.description
                            then jsonb_build_object('ancien', old.description, 'nouveau', new.description) end,
        'seuil_alerte', case when new.seuil_alerte is distinct from old.seuil_alerte
                            then jsonb_build_object('ancien', old.seuil_alerte, 'nouveau', new.seuil_alerte) end
      ));

      -- Les prix restent tracés MÊME pendant un import (exigence CRITIQUE) ;
      -- le reste est résumé par l'entrée IMPORT_PRODUITS.
      if v_prix_change then
        insert into public.journal_audit (entreprise_id, action, utilisateur_id, details)
        values (
          null, 'PRIX_MODIFIE', auth.uid(),
          jsonb_build_object(
            'produit_id', new.id,
            'article',    new.nom,
            'ancien',     jsonb_build_object('prix_achat', old.prix_achat, 'prix_vente', old.prix_vente),
            'nouveau',    jsonb_build_object('prix_achat', new.prix_achat, 'prix_vente', new.prix_vente),
            'import',     v_import,
            'boutique',   v_owner
          )
        );
      end if;

      if v_import then
        return new;
      end if;

      if v_changes <> '{}'::jsonb then
        insert into public.journal_audit (entreprise_id, action, utilisateur_id, details)
        values (
          null, 'ARTICLE_MODIFIE', auth.uid(),
          jsonb_build_object(
            'produit_id', new.id,
            'article',    new.nom,
            'changements', v_changes,
            'boutique',   v_owner
          )
        );
      end if;

      if v_stock_change then
        insert into public.journal_audit (entreprise_id, action, utilisateur_id, details)
        values (
          null, 'STOCK_MODIFIE', auth.uid(),
          jsonb_build_object(
            'produit_id',  new.id,
            'article',     new.nom,
            'stock_avant', old.quantite,
            'stock_apres', new.quantite,
            'delta',       coalesce(new.quantite, 0) - coalesce(old.quantite, 0),
            'boutique',    v_owner
          )
        );
      end if;

      return new;
    end if;

    if tg_op = 'DELETE' then
      insert into public.journal_audit (entreprise_id, action, utilisateur_id, details)
      values (
        null, 'ARTICLE_SUPPRIME', auth.uid(),
        jsonb_build_object(
          'produit_id',  old.id,
          'nom',         old.nom,
          'categorie',   old.categorie,
          'prix_vente',  old.prix_vente,
          'stock_restant', old.quantite,
          'boutique',    old.owner_id
        )
      );
      return old;
    end if;
  exception
    when others then
      null; -- journal best-effort
  end;

  return coalesce(new, old);
end;
$$;

comment on function public.trg_produits_audit() is
  'Module 12 : trace création/modification/prix/stock/suppression des articles (best-effort).';

drop trigger if exists trg_produits_audit on public.produits;
create trigger trg_produits_audit
  after insert or update or delete on public.produits
  for each row
  execute function public.trg_produits_audit();

-- 4.b CONDITIONNEMENTS ---------------------------------------------------------
create or replace function public.trg_conditionnements_audit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_import boolean := coalesce(current_setting('app.import_produits', true), '') = '1';
  v_owner  uuid;
begin
  if v_import then
    return coalesce(new, old);
  end if;

  begin
    if tg_op = 'INSERT' then
      insert into public.journal_audit (entreprise_id, action, utilisateur_id, details)
      select null, 'CONDITIONNEMENT_AJOUTE', auth.uid(),
             jsonb_build_object(
               'conditionnement_id', new.id,
               'produit_id',         new.produit_id,
               'article',            p.nom,
               'libelle',            new.libelle,
               'quantite_unites_base', new.quantite_unites_base,
               'prix_vente',         new.prix_vente,
               'boutique',           p.owner_id
             )
        from public.produits p
       where p.id = new.produit_id;
      return new;
    end if;

    if tg_op = 'UPDATE' then
      select p.owner_id into v_owner
        from public.produits p
       where p.id = coalesce(new.produit_id, old.produit_id);

      if new.prix_vente is distinct from old.prix_vente then
        insert into public.journal_audit (entreprise_id, action, utilisateur_id, details)
        values (
          null, 'PRIX_MODIFIE', auth.uid(),
          jsonb_build_object(
            'conditionnement_id', new.id,
            'produit_id',         new.produit_id,
            'libelle',            new.libelle,
            'ancien',             jsonb_build_object('prix_vente', old.prix_vente),
            'nouveau',            jsonb_build_object('prix_vente', new.prix_vente),
            'boutique',           v_owner
          )
        );
      end if;

      if new.libelle              is distinct from old.libelle
         or new.quantite_unites_base is distinct from old.quantite_unites_base
         or new.prix_vente        is distinct from old.prix_vente then
        insert into public.journal_audit (entreprise_id, action, utilisateur_id, details)
        values (
          null, 'CONDITIONNEMENT_MODIFIE', auth.uid(),
          jsonb_build_object(
            'conditionnement_id', new.id,
            'produit_id',         new.produit_id,
            'ancien',             jsonb_build_object(
                                    'libelle', old.libelle,
                                    'quantite_unites_base', old.quantite_unites_base,
                                    'prix_vente', old.prix_vente),
            'nouveau',            jsonb_build_object(
                                    'libelle', new.libelle,
                                    'quantite_unites_base', new.quantite_unites_base,
                                    'prix_vente', new.prix_vente),
            'boutique',           v_owner
          )
        );
      end if;

      return new;
    end if;

    if tg_op = 'DELETE' then
      insert into public.journal_audit (entreprise_id, action, utilisateur_id, details)
      select null, 'CONDITIONNEMENT_SUPPRIME', auth.uid(),
             jsonb_build_object(
               'conditionnement_id', old.id,
               'produit_id',         old.produit_id,
               'article',            p.nom,
               'libelle',            old.libelle,
               'prix_vente',         old.prix_vente,
               'boutique',           p.owner_id
             )
        from public.produits p
       where p.id = old.produit_id;
      return old;
    end if;
  exception
    when others then
      null;
  end;

  return coalesce(new, old);
end;
$$;

comment on function public.trg_conditionnements_audit() is
  'Module 12 : trace les modifications de conditionnements (dont les prix).';

drop trigger if exists trg_conditionnements_audit on public.conditionnements;
create trigger trg_conditionnements_audit
  after insert or update or delete on public.conditionnements
  for each row
  execute function public.trg_conditionnements_audit();

-- 4.c UTILISATEURS -------------------------------------------------------------
--  (le changement de rôle reste tracé par le trigger du Module 4)
create or replace function public.trg_utilisateurs_audit_global()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_changes jsonb := '{}'::jsonb;
begin
  begin
    if tg_op = 'INSERT' then
      insert into public.journal_audit (entreprise_id, action, utilisateur_id, details)
      values (
        new.entreprise_id, 'UTILISATEUR_CREE', auth.uid(),
        jsonb_build_object(
          'utilisateur', new.id,
          'nom',         coalesce(nullif(btrim(new.nom), ''), new.email),
          'email',       new.email,
          'role',        coalesce(new.new_role::text, new.role),
          'parent_id',   new.parent_id,
          'boutique',    coalesce(new.entreprise_id, new.parent_id, new.id)
        )
      );
      return new;
    end if;

    if tg_op = 'UPDATE' then
      if new.valide is distinct from old.valide then
        insert into public.journal_audit (entreprise_id, action, utilisateur_id, details)
        values (
          old.entreprise_id, 'CHANGEMENT_ACTIVATION', auth.uid(),
          jsonb_build_object(
            'utilisateur', old.id,
            'nom',         coalesce(nullif(btrim(new.nom), ''), new.email),
            'actif_avant', old.valide,
            'actif_apres', new.valide,
            'boutique',    coalesce(new.entreprise_id, new.parent_id, new.id)
          )
        );
      end if;

      v_changes := jsonb_strip_nulls(jsonb_build_object(
        'nom',       case when new.nom  is distinct from old.nom
                          then jsonb_build_object('ancien', old.nom, 'nouveau', new.nom) end,
        'prenom',    case when new.prenom is distinct from old.prenom
                          then jsonb_build_object('ancien', old.prenom, 'nouveau', new.prenom) end,
        'email',     case when new.email is distinct from old.email
                          then jsonb_build_object('ancien', old.email, 'nouveau', new.email) end,
        'valide',    case when new.valide is distinct from old.valide
                          then jsonb_build_object('ancien', old.valide, 'nouveau', new.valide) end,
        'parent_id', case when new.parent_id is distinct from old.parent_id
                          then jsonb_build_object('ancien', old.parent_id, 'nouveau', new.parent_id) end,
        'entreprise_id', case when new.entreprise_id is distinct from old.entreprise_id
                          then jsonb_build_object('ancien', old.entreprise_id, 'nouveau', new.entreprise_id) end
      ));

      if v_changes <> '{}'::jsonb then
        insert into public.journal_audit (entreprise_id, action, utilisateur_id, details)
        values (
          old.entreprise_id, 'UTILISATEUR_MODIFIE', auth.uid(),
          jsonb_build_object(
            'utilisateur', old.id,
            'nom',         coalesce(nullif(btrim(new.nom), ''), new.email),
            'changements', v_changes,
            'boutique',    coalesce(new.entreprise_id, new.parent_id, new.id)
          )
        );
      end if;

      return new;
    end if;

    if tg_op = 'DELETE' then
      insert into public.journal_audit (entreprise_id, action, utilisateur_id, details)
      values (
        old.entreprise_id, 'UTILISATEUR_SUPPRIME', auth.uid(),
        jsonb_build_object(
          'utilisateur', old.id,
          'nom',         coalesce(nullif(btrim(old.nom), ''), old.email),
          'email',       old.email,
          'role',        coalesce(old.new_role::text, old.role),
          'boutique',    coalesce(old.entreprise_id, old.parent_id, old.id)
        )
      );
      return old;
    end if;
  exception
    when others then
      null;
  end;

  return coalesce(new, old);
end;
$$;

comment on function public.trg_utilisateurs_audit_global() is
  'Module 12 : trace création, modification, activation et suppression des utilisateurs.';

drop trigger if exists trg_utilisateurs_audit_global on public.utilisateurs;
create trigger trg_utilisateurs_audit_global
  after insert or update or delete on public.utilisateurs
  for each row
  execute function public.trg_utilisateurs_audit_global();

-- 4.d ENTREPRISES (création et statut déjà tracés par le Module 3) -------------
create or replace function public.trg_entreprises_audit_global()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_changes jsonb := '{}'::jsonb;
begin
  begin
    if tg_op = 'UPDATE' then
      v_changes := jsonb_strip_nulls(jsonb_build_object(
        'nom',        case when new.nom is distinct from old.nom
                           then jsonb_build_object('ancien', old.nom, 'nouveau', new.nom) end,
        'ville_id',   case when new.ville_id is distinct from old.ville_id
                           then jsonb_build_object('ancien', old.ville_id, 'nouveau', new.ville_id) end,
        'activite_id', case when new.activite_id is distinct from old.activite_id
                           then jsonb_build_object('ancien', old.activite_id, 'nouveau', new.activite_id) end,
        'groupe_tarifaire_id', case when new.groupe_tarifaire_id is distinct from old.groupe_tarifaire_id
                           then jsonb_build_object('ancien', old.groupe_tarifaire_id, 'nouveau', new.groupe_tarifaire_id) end
      ));

      if v_changes <> '{}'::jsonb then
        insert into public.journal_audit (entreprise_id, action, utilisateur_id, details)
        values (
          new.id, 'ENTREPRISE_MODIFIEE', auth.uid(),
          jsonb_build_object(
            'entreprise', new.id,
            'nom',        new.nom,
            'changements', v_changes
          )
        );
      end if;

      return new;
    end if;

    if tg_op = 'DELETE' then
      insert into public.journal_audit (entreprise_id, action, utilisateur_id, details)
      values (
        old.id, 'ENTREPRISE_SUPPRIMEE', auth.uid(),
        jsonb_build_object(
          'entreprise', old.id,
          'nom',        old.nom,
          'statut',     old.statut::text
        )
      );
      return old;
    end if;
  exception
    when others then
      null;
  end;

  return coalesce(new, old);
end;
$$;

comment on function public.trg_entreprises_audit_global() is
  'Module 12 : trace modification et suppression d''entreprise (statut/création : Module 3).';

drop trigger if exists trg_entreprises_audit_global on public.entreprises;
create trigger trg_entreprises_audit_global
  after update or delete on public.entreprises
  for each row
  execute function public.trg_entreprises_audit_global();

-- 4.e VENTES : suppression directe INTERDITE -----------------------------------
--  Une vente ne se supprime jamais « à la main » : elle s'ANNULE via
--  `rpc_vente_annuler` (qui pose le drapeau `app.annulation_vente`).
create or replace function public.trg_ventes_suppression_interdite()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if coalesce(current_setting('app.annulation_vente', true), '') = '1' then
    return old;
  end if;

  raise exception
    'VENTE_INALTERABLE|Suppression interdite : utilisez l''annulation tracée (rpc_vente_annuler).';
end;
$$;

comment on function public.trg_ventes_suppression_interdite() is
  'Module 12 : bloque toute suppression de vente hors annulation tracée.';

drop trigger if exists trg_ventes_suppression_interdite on public.ventes;
create trigger trg_ventes_suppression_interdite
  before delete on public.ventes
  for each row
  execute function public.trg_ventes_suppression_interdite();


-- ============================================================================
--  5. ABONNEMENT — MIROIR SERVEUR DU MIDDLEWARE
-- ============================================================================

-- 5.a État d'abonnement d'une boutique ----------------------------------------
--  FAIL-OPEN : boutique inconnue ou statut illisible → 'OK' (on ne bloque
--  jamais l'activité sur un incident de lecture).
create or replace function public.abonnement_etat(p_owner uuid)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_statut text;
  v_exp    timestamptz;
begin
  if p_owner is null then
    return 'OK';
  end if;

  select upper(coalesce(e.statut::text, '')), e.date_expiration
    into v_statut, v_exp
    from public.entreprises e
   where e.id = p_owner;

  if not found then
    return 'OK';
  end if;

  if v_statut = 'SUSPENDU' then
    return 'BLOQUE';
  end if;

  if v_statut in ('EXPIRE', 'EN_ATTENTE_COMPLEMENT') then
    return 'LECTURE_SEULE';
  end if;

  if v_exp is not null and v_exp < now() then
    return 'LECTURE_SEULE';
  end if;

  return 'OK';
end;
$$;

comment on function public.abonnement_etat(uuid) is
  'État d''accès d''une boutique : OK, LECTURE_SEULE ou BLOQUE (fail-open).';

-- 5.b Garde des actions sensibles ---------------------------------------------
--  À appeler en tête de toute RPC d'écriture sensible :
--      perform public.verifier_action_sensible('vente');
--  • personnel plateforme → toujours OK (jamais bloqué par l'abonnement) ;
--  • boutique suspendue    → ABONNEMENT_BLOQUE ;
--  • boutique échue        → ABONNEMENT_EXPIRE (lecture seule).
create or replace function public.verifier_action_sensible(p_nature text default 'action')
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_owner  uuid;
  v_etat   text;
  v_nature text := coalesce(nullif(btrim(coalesce(p_nature, '')), ''), 'action');
begin
  if public.est_plateforme() then
    return true;
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := auth.uid();
  end if;

  if v_owner is null then
    return true;
  end if;

  v_etat := public.abonnement_etat(v_owner);

  if v_etat = 'BLOQUE' then
    raise exception
      'ABONNEMENT_BLOQUE|Abonnement suspendu : impossible de réaliser « % ». Régularisez votre abonnement.',
      v_nature;
  end if;

  if v_etat = 'LECTURE_SEULE' then
    raise exception
      'ABONNEMENT_EXPIRE|Abonnement échu (lecture seule) : impossible de réaliser « % ».',
      v_nature;
  end if;

  return true;
end;
$$;

comment on function public.verifier_action_sensible(text) is
  'Module 12 : bloque une action sensible si l''abonnement de la boutique est suspendu ou échu.';


-- ============================================================================
--  6. ANNULATION DE VENTE — `rpc_vente_annuler`
-- ============================================================================
--  Action CRITIQUE, réservée au PROPRIÉTAIRE (ou Super Admin autorisé) :
--    1. contrôle session / rôle / raison obligatoire / abonnement ;
--    2. vérifie qu'aucune dette NON SOLDÉE n'est liée à la vente ;
--    3. TRACE AVANT MODIFICATION (même transaction) ;
--    4. retire l'encaissement lié de `caisse` ;
--    5. restitue le stock par un ajustement (le trigger ajoute les unités) ;
--    6. supprime les lignes de `ventes` (drapeau d'annulation tracée).
--
--  Codes d'erreur : SESSION_ABSENTE | DROIT_REFUSE | ACCES_REFUSE |
--                   VENTE_INVALIDE | VENTE_INTROUVABLE | HORS_BOUTIQUE |
--                   RAISON_OBLIGATOIRE | DETTE_LIEE | ABONNEMENT_*.

create or replace function public.rpc_vente_annuler(
  p_vente_uuid uuid   default null,
  p_vente_id   bigint default null,
  p_raison     text   default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user        uuid := auth.uid();
  v_role        text := public.mon_role();
  v_raison      text := nullif(btrim(coalesce(p_raison, '')), '');
  v_owner       uuid;
  v_boutique    uuid;
  v_uuid        uuid;
  v_lignes      jsonb := '[]'::jsonb;
  v_total       numeric := 0;
  v_numero      text;
  v_nb          int := 0;
  v_mode        text;
  v_date        timestamptz;
  v_vendeur     uuid;
  v_client      bigint;
  v_dette       integer := 0;
begin
  -- 1. Session + autorisation (seul le propriétaire annule) -------------------
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour annuler une vente.';
  end if;

  if v_role <> 'PROPRIETAIRE'
     and not (v_role = 'SUPER_ADMIN' and public.finance_super_admin_autorise()) then
    raise exception 'DROIT_REFUSE|Seul le propriétaire peut annuler une vente.';
  end if;

  if (p_vente_uuid is null) = (p_vente_id is null) then
    raise exception 'VENTE_INVALIDE|Indiquez la vente (uuid) OU la ligne (id) — pas les deux.';
  end if;

  if v_raison is null or length(v_raison) < 3 then
    raise exception 'RAISON_OBLIGATOIRE|Indiquez la raison de l''annulation (3 caractères minimum).';
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  -- 2. Lecture des lignes (verrouillées) --------------------------------------
  perform 1
     from public.ventes v
    where (p_vente_uuid is not null and v.vente_uuid = p_vente_uuid)
       or (p_vente_id is not null and v.id = p_vente_id)
      for update;

  select coalesce(jsonb_agg(jsonb_build_object(
           'produit_id', v.produit_id,
           'article',    coalesce(p.nom, 'Article supprimé'),
           'quantite',   v.quantite,
           'prix',       v.prix
         )), '[]'::jsonb),
         coalesce(sum(v.prix), 0),
         max(v.numero_vente),
         count(*),
         max(v.mode_paiement),
         max(v.date),
         (array_agg(v.seller_id))[1],
         max(v.client_id)
    into v_lignes, v_total, v_numero, v_nb, v_mode, v_date,
         v_vendeur, v_client
    from public.ventes v
    left join public.produits p on p.id = v.produit_id
   where (p_vente_uuid is not null and v.vente_uuid = p_vente_uuid)
      or (p_vente_id is not null and v.id = p_vente_id);

  if v_nb = 0 then
    raise exception 'VENTE_INTROUVABLE|Vente introuvable (déjà annulée ou numéro inconnu).';
  end if;

  -- Boutique et uuid de la vente (postgresql n'a pas max() sur uuid).
  select v.owner_id, v.vente_uuid
    into v_boutique, v_uuid
    from public.ventes v
   where (p_vente_uuid is not null and v.vente_uuid = p_vente_uuid)
      or (p_vente_id is not null and v.id = p_vente_id)
   limit 1;

  if v_role = 'PROPRIETAIRE' and v_boutique is distinct from v_owner then
    raise exception 'HORS_BOUTIQUE|Cette vente n''appartient pas à votre boutique.';
  end if;

  -- 3. Dette non soldée liée à la vente : à régler d'abord --------------------
  if v_uuid is not null then
    select count(*)
      into v_dette
      from public.dettes d
     where d.vente_uuid = v_uuid
       and lower(coalesce(d.statut, 'non_paye')) <> 'paye';

    if v_dette > 0 then
      raise exception
        'DETTE_LIEE|Cette vente porte une dette client non soldée : encaissez ou régularisez la dette avant l''annulation.';
    end if;
  end if;

  -- 4. ABONNEMENT : une annulation reste une écriture ------------------------
  perform public.verifier_action_sensible('annulation de vente');

  -- 5. TRACE AVANT MODIFICATION (exigence CRITIQUE — même transaction) -------
  insert into public.journal_audit (entreprise_id, action, utilisateur_id, details)
  values (
    null, 'ANNULATION_VENTE', v_user,
    jsonb_build_object(
      'vente_uuid',   v_uuid,
      'vente_id',     p_vente_id,
      'numero_vente', v_numero,
      'total',        v_total,
      'mode_paiement', v_mode,
      'date_vente',   v_date,
      'vendeur',      v_vendeur,
      'client_id',    v_client,
      'nb_lignes',    v_nb,
      'lignes',       v_lignes,
      'raison',       v_raison,
      'boutique',     v_boutique
    )
  );

  -- 6. Retirer l'encaissement de la caisse ------------------------------------
  if v_uuid is not null then
    delete from public.caisse c
     where c.vente_uuid = v_uuid
       and (v_role <> 'PROPRIETAIRE' or c.owner_id = v_boutique);
  end if;

  -- 7. Restituer le stock (un ajustement par article — le trigger ajoute) ----
  insert into public.ajustements (produit_id, quantite, raison, date, owner_id)
  select v.produit_id,
         sum(v.quantite),
         'Annulation vente ' || coalesce(v_numero, 'sans numéro') || ' — ' || v_raison,
         now(),
         v_boutique
    from public.ventes v
   where (p_vente_uuid is not null and v.vente_uuid = p_vente_uuid)
      or (p_vente_id is not null and v.id = p_vente_id)
   group by v.produit_id;

  -- 8. Supprimer les lignes (annulation tracée : drapeau pour le trigger) -----
  perform set_config('app.annulation_vente', '1', true);
  delete from public.ventes v
   where (p_vente_uuid is not null and v.vente_uuid = p_vente_uuid)
      or (p_vente_id is not null and v.id = p_vente_id);
  perform set_config('app.annulation_vente', '0', true);

  return jsonb_build_object(
    'vente_uuid',    v_uuid,
    'numero_vente',  v_numero,
    'total',         v_total,
    'nb_lignes',     v_nb,
    'stock_restaure', true,
    'raison',        v_raison
  );
end;
$$;

comment on function public.rpc_vente_annuler(uuid, bigint, text) is
  'Annule une vente (propriétaire) : trace CRITIQUE, caisse retirée, stock restitué, lignes supprimées.';


-- ============================================================================
--  7. IMPORT RAPIDE D'ARTICLES — `rpc_produits_importer`
-- ============================================================================
--  Jusqu'à 500 lignes par appel. Chaque ligne (objet JSON) accepte :
--    { nom*, categorie, prix_achat, prix_vente, quantite, unite_mesure,
--      description }
--  • `p_mettre_a_jour = false` (défaut) : un article du même nom est IGNORÉ ;
--  • `p_mettre_a_jour = true`            : sa fiche est mise à jour (prix,
--    catégorie, unité, description) — JAMAIS la quantité (le stock passe
--    exclusivement par les mouvements tracés).
--  Le tout est journalisé en UNE entrée `IMPORT_PRODUITS` (HAUT).
--
--  Codes d'erreur : SESSION_ABSENTE | DROIT_REFUSE | RESERVE_ENTREPRISE |
--                   LIGNES_VIDES | TROP_DE_LIGNES | ABONNEMENT_*.

create or replace function public.rpc_produits_importer(
  p_lignes          jsonb,
  p_mettre_a_jour   boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user      uuid := auth.uid();
  v_owner     uuid;
  v_ligne     jsonb;
  v_i         integer := 0;
  v_nom       text;
  v_categorie text;
  v_unite     text;
  v_desc      text;
  v_prix_achat numeric;
  v_prix_vente numeric;
  v_quantite   numeric;
  v_existant  bigint;
  v_id        bigint;
  v_crees     integer := 0;
  v_maj       integer := 0;
  v_ignores   integer := 0;
  v_erreurs   jsonb := '[]'::jsonb;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour importer des articles.';
  end if;

  if public.est_plateforme() then
    raise exception 'RESERVE_ENTREPRISE|L''import d''articles est réservé aux boutiques.';
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  if not public.peut('articles', 'creer') then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de créer des articles.';
  end if;

  if p_mettre_a_jour and not (public.peut('articles', 'modifier') or public.peut('articles', 'creer')) then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de mettre à jour les articles.';
  end if;

  if p_lignes is null
     or jsonb_typeof(p_lignes) <> 'array'
     or jsonb_array_length(p_lignes) = 0 then
    raise exception 'LIGNES_VIDES|Aucune ligne à importer.';
  end if;

  if jsonb_array_length(p_lignes) > 500 then
    raise exception 'TROP_DE_LIGNES|500 lignes maximum par import (% reçues).', jsonb_array_length(p_lignes);
  end if;

  perform public.verifier_action_sensible('import des articles');

  -- Coupe le bruit : les triggers ARTICLE_CREE/MODIFIE sont suspendus,
  -- l'entrée IMPORT_PRODUITS résume tout.
  perform set_config('app.import_produits', '1', true);

  for v_ligne in select value from jsonb_array_elements(p_lignes) loop
    v_i := v_i + 1;
    begin
      if jsonb_typeof(v_ligne) <> 'object' then
        raise exception 'La ligne doit être un objet JSON.';
      end if;

      v_nom := nullif(btrim(coalesce(v_ligne ->> 'nom', '')), '');
      if v_nom is null then
        raise exception 'Le nom de l''article est obligatoire.';
      end if;

      v_categorie := nullif(btrim(coalesce(v_ligne ->> 'categorie', '')), '');
      v_unite     := nullif(btrim(coalesce(v_ligne ->> 'unite_mesure', '')), '');
      v_desc      := nullif(btrim(coalesce(v_ligne ->> 'description', '')), '');

      v_prix_achat := coalesce(nullif(v_ligne ->> 'prix_achat', '')::numeric, 0);
      v_prix_vente := coalesce(nullif(v_ligne ->> 'prix_vente', '')::numeric, 0);
      v_quantite   := coalesce(nullif(v_ligne ->> 'quantite', '')::numeric, 0);

      if v_prix_achat < 0 or v_prix_vente < 0 or v_quantite < 0 then
        raise exception 'Les prix et la quantité doivent être positifs ou nuls.';
      end if;

      select p.id into v_existant
        from public.produits p
       where p.owner_id = v_owner
         and lower(btrim(p.nom)) = lower(v_nom)
       limit 1;

      if v_existant is not null then
        if p_mettre_a_jour then
          update public.produits p
             set categorie    = coalesce(v_categorie, p.categorie),
                 unite_mesure = coalesce(v_unite, p.unite_mesure),
                 description  = coalesce(v_desc, p.description),
                 prix_achat   = v_prix_achat,
                 prix_vente   = v_prix_vente,
                 updated_at   = now()
           where p.id = v_existant;

          v_maj := v_maj + 1;
        else
          v_ignores := v_ignores + 1;
        end if;
      else
        insert into public.produits (
          nom, categorie, prix_achat, prix_vente, quantite,
          unite_mesure, description, owner_id
        ) values (
          v_nom, coalesce(v_categorie, ''), v_prix_achat, v_prix_vente, v_quantite,
          coalesce(v_unite, 'unité'), v_desc, v_owner
        )
        returning id into v_id;

        v_crees := v_crees + 1;
      end if;
    exception
      when others then
        v_erreurs := v_erreurs || jsonb_build_array(jsonb_build_object(
          'ligne',   v_i,
          'nom',     coalesce(v_nom, ''),
          'message', sqlerrm
        ));
    end;
  end loop;

  perform set_config('app.import_produits', '0', true);

  -- Journal AVANT retour (l'entrée fait partie de la transaction).
  insert into public.journal_audit (entreprise_id, action, utilisateur_id, details)
  values (
    null, 'IMPORT_PRODUITS', v_user,
    jsonb_build_object(
      'nb_lignes',    v_i,
      'crees',        v_crees,
      'mis_a_jour',   v_maj,
      'ignores',      v_ignores,
      'nb_erreurs',   jsonb_array_length(v_erreurs),
      'erreurs',      v_erreurs,
      'mode',         case when p_mettre_a_jour then 'mise_a_jour' else 'creation' end,
      'boutique',     v_owner
    )
  );

  return jsonb_build_object(
    'nb_lignes',   v_i,
    'crees',       v_crees,
    'mis_a_jour',  v_maj,
    'ignores',     v_ignores,
    'erreurs',     v_erreurs
  );
end;
$$;

comment on function public.rpc_produits_importer(jsonb, boolean) is
  'Import rapide d''articles (≤500 lignes) : création des manquants, mise à jour optionnelle — journalisé IMPORT_PRODUITS.';


-- ============================================================================
--  8. PERMISSIONS — NOUVELLES PAGES (`securite`) ET `audit` ENTREPRISE
-- ============================================================================
--  • `securite` : écran Sécurité, réservé au personnel plateforme (le
--    SUPER_ADMIN l'obtient via « toutes les pages ») ;
--  • `audit`    : désormais aussi une page ENTREPRISE → le PROPRIÉTAIRE
--    peut consulter le journal de SA boutique (RLS déjà cloisonnée).

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
    'fournisseurs', 'depenses', 'collaborateurs', 'qr_codes', 'rapports'
  ];
$$;

comment on function public.pages_permissions() is
  'Liste officielle des pages de permission (Module 4, complétée Module 12 : securite).';

-- Matrice par défaut — copie du Module 4 avec :
--   • PROPRIETAIRE : + page 'audit' ;
--   • SUPER_ADMIN  : reçoit 'securite' via « toutes les pages ».
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
    -- Gestion des comptes : aucun accès à la finance ni aux paiements.
    when 'GESTIONNAIRE_COMPTES' then
      v_pages   := array['entreprises', 'utilisateurs', 'villes', 'activites',
                         'groupes_tarifaires', 'abonnements', 'assistance',
                         'notifications'];
      v_actions := array['voir', 'creer', 'modifier'];

    -- Finance plateforme : abonnements, paiements, rapports financiers.
    when 'FINANCE_LAPERLE' then
      v_pages   := array['dashboard', 'abonnements', 'paiements', 'finance',
                         'rapports', 'audit', 'notifications'];
      v_actions := array['voir', 'creer', 'valider'];

    -- Assistance : lecture des comptes, écriture limitée à l'assistance.
    when 'SUPPORT' then
      v_pages   := array['dashboard', 'assistance', 'entreprises', 'utilisateurs',
                         'abonnements', 'notifications'];
      v_actions := array['voir'];

    -- Propriétaire : tout son espace entreprise (+ journal de SA boutique).
    when 'PROPRIETAIRE' then
      v_pages   := array['dashboard', 'ventes', 'caisse', 'scanner', 'panier',
                         'articles', 'qr_codes', 'stock', 'clients', 'fournisseurs',
                         'finance', 'depenses', 'collaborateurs', 'rapports',
                         'abonnements', 'audit', 'parametres'];
      v_actions := public.actions_permissions();

    -- Caissier : vendre, encaisser, consulter ses ventes. Jamais modifier.
    when 'VENDEUR' then
      v_pages   := array['ventes', 'caisse', 'scanner', 'panier'];
      v_actions := array['voir', 'creer'];

    -- Magasinier : mouvements de stock et lecture du catalogue.
    when 'MAGASINIER' then
      v_pages   := array['stock', 'articles', 'qr_codes', 'rapports'];
      v_actions := array['voir'];

    -- Comptable d'entreprise : dépenses et rapports.
    when 'COMPTABLE_ENTREPRISE' then
      v_pages   := array['dashboard', 'ventes', 'caisse', 'depenses', 'rapports',
                         'finance', 'parametres'];
      v_actions := array['voir'];

    else
      return '{}'::jsonb;
  end case;

  foreach v_page in array v_pages loop
    v_result := jsonb_set(v_result, array[v_page], to_jsonb(v_actions), true);
  end loop;

  -- Exceptions par page (mêmes valeurs que la matrice Dart).
  v_result := case v_role
    when 'SUPPORT' then v_result
      || jsonb_build_object('assistance',    to_jsonb(array['voir', 'modifier']))
      || jsonb_build_object('notifications', to_jsonb(array['voir', 'modifier']))
    when 'MAGASINIER' then v_result
      || jsonb_build_object('stock',    to_jsonb(array['voir', 'creer', 'modifier']))
      || jsonb_build_object('qr_codes', to_jsonb(array['voir', 'creer']))
    when 'COMPTABLE_ENTREPRISE' then v_result
      || jsonb_build_object('depenses', to_jsonb(array['voir', 'creer', 'valider']))
      || jsonb_build_object('rapports', to_jsonb(array['voir', 'valider']))
    else v_result
  end;

  return v_result;
end;
$$;

comment on function public.permissions_defaut(text) is
  'Matrice des permissions par défaut d''un rôle (Module 4, + audit propriétaire et page securite — Module 12).';


-- ============================================================================
--  9. ÉCRAN SÉCURITÉ — `rpc_securite_connexions`, `rpc_securite_alertes`,
--     `rpc_securite_reset_permissions`
-- ============================================================================
--  Réservés au personnel plateforme disposant de `audit/voir` ou
--  `securite/voir` (le SUPER_ADMIN les a par défaut).
--  Codes d'erreur : SESSION_ABSENTE | ACCES_REFUSE | ROLE_INCONNU.

-- 9.a Dernières connexions + résumé -------------------------------------------
create or replace function public.rpc_securite_connexions(p_limit integer default 50)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user   uuid := auth.uid();
  v_limit  integer := least(greatest(coalesce(p_limit, 50), 1), 200);
  v_lignes jsonb := '[]'::jsonb;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour consulter les connexions.';
  end if;

  if not (public.est_plateforme()
          and (public.peut('audit', 'voir') or public.peut('securite', 'voir'))) then
    raise exception 'ACCES_REFUSE|Cet écran est réservé au personnel de la plateforme.';
  end if;

  select coalesce(jsonb_agg(ligne order by ordre desc), '[]'::jsonb)
    into v_lignes
    from (
      select jsonb_build_object(
               'id',          ja.id,
               'action',      ja.action,
               'utilisateur_id', ja.utilisateur_id,
               'utilisateur', coalesce(nullif(btrim(u.nom), ''), u.email, ja.details ->> 'email', ''),
               'email',       coalesce(u.email, ja.details ->> 'email'),
               'ip_address',  ja.ip_address,
               'user_agent',  ja.user_agent,
               'details',     ja.details,
               'created_at',  ja.created_at
             ) as ligne,
             ja.created_at as ordre
        from public.journal_audit ja
        left join public.utilisateurs u on u.id = ja.utilisateur_id
       where ja.action in ('CONNEXION', 'DECONNEXION', 'CONNEXION_ECHEC')
       order by ja.created_at desc
       limit v_limit
    ) s;

  return jsonb_build_object(
    'connexions', v_lignes,
    'resume', jsonb_build_object(
      'reussies_24h',     (select count(*) from public.journal_audit
                            where action = 'CONNEXION'
                              and created_at >= now() - interval '24 hours'),
      'echecs_24h',       (select count(*) from public.journal_audit
                            where action = 'CONNEXION_ECHEC'
                              and created_at >= now() - interval '24 hours'),
      'deconnexions_24h', (select count(*) from public.journal_audit
                            where action = 'DECONNEXION'
                              and created_at >= now() - interval '24 hours'),
      'echecs_7j',        (select count(*) from public.journal_audit
                            where action = 'CONNEXION_ECHEC'
                              and created_at >= now() - interval '7 days'),
      'comptes_echoues_24h', (select count(distinct lower(coalesce(details ->> 'email', '')))
                                from public.journal_audit
                               where action = 'CONNEXION_ECHEC'
                                 and created_at >= now() - interval '24 hours'),
      'ips_echouees_24h', (select count(distinct ip_address)
                             from public.journal_audit
                            where action = 'CONNEXION_ECHEC'
                              and created_at >= now() - interval '24 hours'
                              and ip_address is not null)
    )
  );
end;
$$;

comment on function public.rpc_securite_connexions(integer) is
  'Dernières connexions/déconnexions/échecs + résumé (plateforme).';

-- 9.b Alertes de sécurité ------------------------------------------------------
--  Règles (seuils volontairement simples, 24 h glissantes) :
--    • même email ≥ 3 échecs  → alerte TENTATIVES_ECHOUEES ;
--    • même IP    ≥ 5 échecs  → alerte IP_SUSPECTE.
create or replace function public.rpc_securite_alertes()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user    uuid := auth.uid();
  v_alertes jsonb := '[]'::jsonb;
  v_email   record;
  v_ip      record;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour consulter les alertes.';
  end if;

  if not (public.est_plateforme()
          and (public.peut('audit', 'voir') or public.peut('securite', 'voir'))) then
    raise exception 'ACCES_REFUSE|Cet écran est réservé au personnel de la plateforme.';
  end if;

  for v_email in
    select lower(coalesce(details ->> 'email', '(inconnu)')) as email,
           count(*) as nb,
           max(created_at) as derniere,
           jsonb_agg(distinct ip_address) filter (where ip_address is not null) as ips
      from public.journal_audit
     where action = 'CONNEXION_ECHEC'
       and created_at >= now() - interval '24 hours'
     group by 1
    having count(*) >= 3
     order by count(*) desc
     limit 20
  loop
    v_alertes := v_alertes || jsonb_build_array(jsonb_build_object(
      'type',     'TENTATIVES_ECHOUEES',
      'gravite',  case when v_email.nb >= 5 then 'HAUTE' else 'MOYENNE' end,
      'libelle',  'Tentatives de connexion échouées répétées',
      'email',    v_email.email,
      'nombre',   v_email.nb,
      'derniere', v_email.derniere,
      'ips',      coalesce(v_email.ips, '[]'::jsonb)
    ));
  end loop;

  for v_ip in
    select ip_address as ip,
           count(*) as nb,
           max(created_at) as derniere,
           jsonb_agg(distinct lower(coalesce(details ->> 'email', ''))) as emails
      from public.journal_audit
     where action = 'CONNEXION_ECHEC'
       and created_at >= now() - interval '24 hours'
       and ip_address is not null
     group by 1
    having count(*) >= 5
     order by count(*) desc
     limit 20
  loop
    v_alertes := v_alertes || jsonb_build_array(jsonb_build_object(
      'type',     'IP_SUSPECTE',
      'gravite',  case when v_ip.nb >= 10 then 'HAUTE' else 'MOYENNE' end,
      'libelle',  'Adresse IP à échecs multiples',
      'ip',       v_ip.ip,
      'nombre',   v_ip.nb,
      'derniere', v_ip.derniere,
      'emails',   coalesce(v_ip.emails, '[]'::jsonb)
    ));
  end loop;

  return jsonb_build_object(
    'alertes', v_alertes,
    'resume', jsonb_build_object(
      'echecs_24h',      (select count(*) from public.journal_audit
                           where action = 'CONNEXION_ECHEC'
                             and created_at >= now() - interval '24 hours'),
      'echecs_7j',       (select count(*) from public.journal_audit
                           where action = 'CONNEXION_ECHEC'
                             and created_at >= now() - interval '7 days'),
      'connexions_24h',  (select count(*) from public.journal_audit
                           where action = 'CONNEXION'
                             and created_at >= now() - interval '24 hours'),
      'dernier_echec',   (select max(created_at) from public.journal_audit
                           where action = 'CONNEXION_ECHEC'),
      'nb_alertes',      jsonb_array_length(v_alertes)
    ),
    'seuils', jsonb_build_object('email', 3, 'ip', 5, 'fenetre_heures', 24)
  );
end;
$$;

comment on function public.rpc_securite_alertes() is
  'Alertes de sécurité calculées (tentatives échouées par email, IPs suspectes).';

-- 9.c Réinitialisation des permissions ----------------------------------------
--  p_role NULL → TOUS les rôles (supprime toutes les surcharges).
create or replace function public.rpc_securite_reset_permissions(p_role text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_role text := nullif(upper(btrim(coalesce(p_role, ''))), '');
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour réinitialiser les permissions.';
  end if;

  if not public.est_super_admin() then
    raise exception 'ACCES_REFUSE|Seul le Super Admin peut réinitialiser les permissions.';
  end if;

  if v_role is not null and public.role_enum(v_role) is null then
    raise exception 'ROLE_INCONNU|Rôle inconnu : « % ».', v_role;
  end if;

  if v_role is null then
    update public.app_settings
       set value      = coalesce(value, '{}'::jsonb) #- array['roles'],
           updated_at = now()
     where key = 'permissions_roles';
  else
    update public.app_settings
       set value      = coalesce(value, '{}'::jsonb) #- array['roles', v_role],
           updated_at = now()
     where key = 'permissions_roles';
  end if;

  insert into public.journal_audit (entreprise_id, action, utilisateur_id, details)
  values (
    null, 'PERMISSIONS_REINITIALISEES', v_user,
    jsonb_build_object(
      'role',   coalesce(v_role, 'TOUS'),
      'source', 'ecran_securite',
      'portee', 'plateforme'
    )
  );

  return jsonb_build_object(
    'role',         coalesce(v_role, 'TOUS'),
    'reinitialise', true
  );
end;
$$;

comment on function public.rpc_securite_reset_permissions(text) is
  'Réinitialise les surcharges de permissions (un rôle, ou tous si p_role est NULL) — Super Admin.';


-- ============================================================================
-- 10. RLS — LE JOURNAL SUIT LES MÊMES RÈGLES QUE LES DONNÉES
-- ============================================================================
--  • plateforme + audit/voir → toutes les lignes ;
--  • entreprise + audit/voir → SA boutique uniquement (entreprise_id OU
--    details.boutique pour les modules 8→10) ;
--  • AUCUNE écriture directe : la table est alimentée par les RPC
--    `security definer` et les triggers uniquement.

alter table public.journal_audit enable row level security;

do $$
declare
  r record;
begin
  for r in
    select policyname
      from pg_policies
     where schemaname = 'public' and tablename = 'journal_audit'
  loop
    execute format('drop policy if exists %I on public.journal_audit', r.policyname);
  end loop;
end $$;

create policy m12_journal_audit_lecture on public.journal_audit
  for select to authenticated
  using (
    (
      public.est_plateforme()
      and public.peut('audit', 'voir')
    )
    or (
      public.peut('audit', 'voir')
      and (
        entreprise_id = (case
                           when public.mon_proprietaire() is null then auth.uid()
                           else public.mon_proprietaire()
                         end)
        or (
          entreprise_id is null
          and details ->> 'boutique' = (case
                                         when public.mon_proprietaire() is null then auth.uid()::text
                                         else public.mon_proprietaire()::text
                                       end)
        )
      )
    )
  );

-- Défense en profondeur : aucune écriture directe par les clients API.
revoke insert, update, delete, truncate on public.journal_audit from authenticated;
revoke insert, update, delete, truncate on public.journal_audit from anon;
revoke all on public.journal_audit from public;


-- ============================================================================
-- 11. DROITS D'EXÉCUTION
-- ============================================================================

-- Outils internes : jamais exposés.
revoke all on function public.audit_niveau(text) from public;
revoke all on function public.audit_ip() from public;
revoke all on function public.audit_user_agent() from public;
revoke all on function public.audit_en_tete(text) from public;
revoke all on function public.audit_empreinte_ligne(text, bigint, uuid, uuid, uuid, text, text, jsonb, timestamptz) from public;
revoke all on function public.abonnement_etat(uuid) from public;

-- Outils utilisables par l'application (lecture de l'état d'abonnement).
revoke all on function public.verifier_action_sensible(text) from public;
grant execute on function public.verifier_action_sensible(text) to authenticated;

-- RPC applicatives.
revoke all on function public.rpc_audit_logger(text, jsonb, uuid) from public;
grant execute on function public.rpc_audit_logger(text, jsonb, uuid) to authenticated;
-- EXCEPTION VOLONTAIRE : une tentative de connexion échouée n'a pas de
-- session ; l'insertion est bornée (action unique autorisée, détails réduits).
grant execute on function public.rpc_audit_logger(text, jsonb, uuid) to anon;

revoke all on function public.rpc_audit_lister(uuid, text, date, date, uuid, text, text, integer, integer) from public;
grant execute on function public.rpc_audit_lister(uuid, text, date, date, uuid, text, text, integer, integer) to authenticated;

revoke all on function public.rpc_audit_verifier(integer) from public;
grant execute on function public.rpc_audit_verifier(integer) to authenticated;

revoke all on function public.rpc_securite_connexions(integer) from public;
grant execute on function public.rpc_securite_connexions(integer) to authenticated;

revoke all on function public.rpc_securite_alertes() from public;
grant execute on function public.rpc_securite_alertes() to authenticated;

revoke all on function public.rpc_securite_reset_permissions(text) from public;
grant execute on function public.rpc_securite_reset_permissions(text) to authenticated;

revoke all on function public.rpc_vente_annuler(uuid, bigint, text) from public;
grant execute on function public.rpc_vente_annuler(uuid, bigint, text) to authenticated;

revoke all on function public.rpc_produits_importer(jsonb, boolean) from public;
grant execute on function public.rpc_produits_importer(jsonb, boolean) to authenticated;


-- ============================================================================
-- 12. VÉRIFICATIONS
-- ============================================================================

-- 12.a Colonnes du journal
select column_name, data_type, is_nullable, column_default
  from information_schema.columns
 where table_schema = 'public' and table_name = 'journal_audit'
 order by ordinal_position;

-- 12.b Triggers du journal et des tables surveillées
select c.relname as table_name, t.tgname as trigger_name, t.tgenabled
  from pg_trigger t
  join pg_class c on c.oid = t.tgrelid
  join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'public'
   and not t.tgisinternal
   and (c.relname in ('journal_audit', 'produits', 'conditionnements',
                      'utilisateurs', 'entreprises', 'ventes')
        or t.tgname like 'trg_%audit%' or t.tgname like 'trg_produits_%')
 order by c.relname, t.tgname;

-- 12.c Fonctions du module
select p.proname, pg_get_function_arguments(p.oid) as arguments
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname in (
     'audit_niveau', 'audit_ip', 'audit_user_agent', 'rpc_audit_logger',
     'rpc_audit_lister', 'rpc_audit_verifier', 'rpc_securite_connexions',
     'rpc_securite_alertes', 'rpc_securite_reset_permissions',
     'rpc_vente_annuler', 'rpc_produits_importer', 'abonnement_etat',
     'verifier_action_sensible'
   )
 order by p.proname;

-- 12.d Policies du journal (doivent toutes commencer par `m12_`)
select tablename, policyname, cmd
  from pg_policies
 where schemaname = 'public' and tablename = 'journal_audit'
 order by policyname;

-- 12.e Dernières entrées (aperçu)
select seq, action, niveau, utilise,
       coalesce(details ->> 'boutique', entreprise_id::text) as boutique,
       ip_address, created_at
  from (
    select seq, action, niveau, utilisateur_id as utilise, details, entreprise_id,
           ip_address, created_at
      from public.journal_audit
     order by seq desc
     limit 10
  ) s;


-- ============================================================================
-- 13. CONTRÔLES MANUELS UTILES (à exécuter au besoin, compte connecté)
-- ============================================================================

-- Journaliser une connexion (l'application le fait via AuditService) :
--
-- select public.rpc_audit_logger('CONNEXION', '{"plateforme":false}'::jsonb);
--
-- Journaliser un échec SANS session (grant anon) :
--
-- select public.rpc_audit_logger('CONNEXION_ECHEC',
--          '{"email":"inconnu@exemple.cd","message":"mot de passe incorrect"}'::jsonb);
--
-- Lister le journal (boutique) :
--
-- select public.rpc_audit_lister(p_limit => 20);
--
-- Lister le journal (plateforme, filtré sur une action) :
--
-- select public.rpc_audit_lister(p_action => 'PRIX_MODIFIE', p_limit => 50);
--
-- Vérifier l'intégrité de la chaîne :
--
-- select public.rpc_audit_verifier(500);
--
-- Écran Sécurité (personnel plateforme) :
--
-- select public.rpc_securite_connexions(50);
-- select public.rpc_securite_alertes();
-- select public.rpc_securite_reset_permissions();          -- tous les rôles
-- select public.rpc_securite_reset_permissions('VENDEUR'); -- un seul rôle
--
-- Annuler une vente (propriétaire) :
--
-- select public.rpc_vente_annuler(p_vente_uuid => '<uuid>',
--                                 p_raison     => 'Client s''est ravisé');
--
-- Importer des articles (boutique) :
--
-- select public.rpc_produits_importer(
--   '[{"nom":"Sucre 1kg","categorie":"alimentation","prix_achat":1500,"prix_vente":2000,"quantite":40},
--     {"nom":"Café 500g","prix_achat":3000,"prix_vente":3800,"quantite":12}]'::jsonb,
--   false
-- );
--
-- Vérifier l'état d'abonnement d'une boutique :
--
-- select public.abonnement_etat('<uuid-entreprise>');
