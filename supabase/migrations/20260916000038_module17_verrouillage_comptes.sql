-- ============================================================================
--  biashara_yangu — MODULE 17 : VERROUILLAGE DES COMPTES NON ACTIVÉS
--  (+ catégorie d'activité respectée à la création)
--
--  PROBLÈMES CORRIGÉS
--  ─────────────────────────────────────────────────────────────────────────
--  1. UN COMPTE NON ENCORE ACTIVÉ POUVAIT COMMERCER.
--     Le workflow du module 14 (vérification Gestionnaire → validation
--     Finance → activation) n'était pas branché sur le moteur d'accès :
--       • `abonnement_etat()` cherchait l'entreprise par l'identifiant
--         reçu… alors qu'on lui passe l'ID DE L'ESPACE (`mon_proprietaire()`)
--         → jamais trouvée → FAIL-OPEN : rien n'était jamais bloqué ;
--       • `rpc_entreprises_de_utilisateur()` renvoyait une LISTE VIDE sur
--         des comptes qui possèdent pourtant une entreprise (constaté en
--         production le 20/09/2026 : compte propriétaire avec
--         `utilisateurs.entreprise_id` renseigné → `[]`) → l'application
--         ne recevait AUCUN statut et restait « fail-open » (accès complet).
--         La fonction est RECRÉÉE ici et renvoie désormais le statut, la
--         date d'échéance, le solde ET l'étape d'activation ;
--       • `activation_etape` (en_attente_verification / verifie / rejete /
--         restreint) n'était JAMAIS consommé par le moteur d'accès ;
--       • les RPC d'écriture (ventes, stock, finance, hôtel, restaurant…)
--         n'appelaient pas `verifier_action_sensible()`.
--
--     CORRECTIF :
--       • nouveau helper `entreprise_de_proprietaire()` (espace / entreprise
--         / utilisateur → entreprise) ;
--       • `abonnement_etat()` v2 : état « ACTIVATION » tant que le dossier
--         n'est pas ACTIF ; « restreint » = lecture seule ;
--       • `verifier_action_sensible()` v2 : message dédié ACTIVATION_REQUISE ;
--       • TRIGGERS `trg_m17_blocage` sur les tables commerciales : toute
--         écriture directe (PostgREST) ou via RPC est refusée serveur-side
--         tant que le compte n'est pas opérationnel — il ne suffit plus de
--         contourner l'interface. Le personnel plateforme est exempté.
--
--  2. LA CATÉGORIE D'ACTIVITÉ N'ÉTAIT PAS RESPECTÉE À L'INSCRIPTION.
--     `rpc_entreprise_creer` créait toujours un espace « boutique » nommé
--     « Boutique <nom> », quelle que soit l'activité du client.
--
--     CORRECTIF :
--       • `rpc_entreprise_creer` v6 : nouveau paramètre `p_type` (validé
--         par le référentiel `types_espaces_modules`) ; nom par défaut
--         « <Libellé de l'activité> <nom> » (ex. « Hôtel Jambo ») ;
--       • `rpc_espace_type_definir()` : le propriétaire peut corriger la
--         catégorie d'un espace existant (les modules suivent aussitôt) ;
--       • `rpc_types_espaces_publics()` : liste des catégories actives pour
--         le sélecteur d'inscription (lisible même avant activation).
--
--  RÈGLES MÉTIER (rappel du cahier des charges)
--  ─────────────────────────────────────────────────────────────────────────
--    • Création → Vérification gestionnaire → Paiement → Validation
--      Finance → Activation → Compte OPÉRATIONNEL.
--    • Avant l'activation : consultation seule (données intactes) ;
--      toute opération commerciale est refusée (serveur).
--    • Abonnement expiré / restreint : même verrouillage, réactivation
--      AUTOMATIQUE dès la validation du paiement (module 14).
--    • Fail-open : compte introuvable ou lecture impossible → on ne bloque
--      jamais par accident.
--
--  OÙ : Supabase → SQL Editor → coller → Run
--  IDEMPOTENT : peut être relancé sans effet de bord.
-- ============================================================================


select set_config('search_path', 'public, extensions', true);


-- ============================================================================
--  1. HELPER — RETROUVER L'ENTREPRISE D'UN « PROPRIÉTAIRE »
-- ============================================================================
--  Les tables métier sont estampillées par l'ESPACE actif (module 15) ou par
--  l'UUID du patron : ce helper remonte à l'ENTREPRISE (qui porte
--  l'abonnement et le dossier d'activation).

create or replace function public.entreprise_de_proprietaire(p_proprietaire uuid)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    -- 1. L'identifiant est celui d'un ESPACE (cas nominal).
    (select s.entreprise_id from public.espaces s where s.id = p_proprietaire),
    -- 2. L'identifiant est déjà celui d'une ENTREPRISE.
    (select e.id from public.entreprises e where e.id = p_proprietaire),
    -- 3. L'identifiant est celui d'un UTILISATEUR (patron ou collaborateur).
    (select coalesce(u.entreprise_id, p.entreprise_id)
       from public.utilisateurs u
       left join public.utilisateurs p on p.id = u.parent_id
      where u.id = p_proprietaire)
  );
$$;

comment on function public.entreprise_de_proprietaire(uuid) is
  'Module 17 — Entreprise (abonnement) d''un propriétaire : espace actif, entreprise ou utilisateur. NULL = inconnu (fail-open chez les appelants).';

revoke all on function public.entreprise_de_proprietaire(uuid) from public;
revoke all on function public.entreprise_de_proprietaire(uuid) from anon;
grant execute on function public.entreprise_de_proprietaire(uuid) to authenticated;


-- ============================================================================
--  2. `abonnement_etat()` v2 — LE MOTEUR D'ACCÈS COMPLET
-- ============================================================================
--  États renvoyés :
--    'OK'            → opérations autorisées ;
--    'ACTIVATION'    → dossier pas encore ACTIF (vérification / finance) :
--                      consultation seule, message dédié ;
--    'LECTURE_SEULE' → abonnement échu, complément attendu ou restreint ;
--    'BLOQUE'        → entreprise suspendue par l'administrateur.
--  FAIL-OPEN : entreprise introuvable → 'OK' (jamais de blocage accidentel).

create or replace function public.abonnement_etat(p_owner uuid)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_ent    uuid;
  v_statut text;
  v_exp    timestamptz;
  v_etape  text;
begin
  if p_owner is null then
    return 'OK';
  end if;

  -- 🔧 MODULE 17 — résolution espace → entreprise (avant : comparaison
  -- directe `entreprises.id = p_owner`, toujours en échec → fail-open).
  v_ent := public.entreprise_de_proprietaire(p_owner);
  if v_ent is null then
    return 'OK';
  end if;

  select upper(coalesce(e.statut::text, '')),
         e.date_expiration,
         lower(coalesce(e.activation_etape, 'actif'))
    into v_statut, v_exp, v_etape
    from public.entreprises e
   where e.id = v_ent;

  if not found then
    return 'OK';
  end if;

  -- 🛡️ MODULE 17 — double validation : tant que le gestionnaire n'a pas
  -- vérifié ET que la finance n'a pas validé le paiement, le compte n'est
  -- pas opérationnel (aucune opération commerciale, serveur compris).
  if v_etape in ('en_attente_verification', 'verifie', 'rejete') then
    return 'ACTIVATION';
  end if;

  -- Solde impayé à l'échéance (module 14) : lecture seule.
  if v_etape = 'restreint' then
    return 'LECTURE_SEULE';
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
  'Module 12/17 — État d''accès d''un compte : OK, ACTIVATION (dossier non activé), LECTURE_SEULE ou BLOQUE (fail-open).';


-- ============================================================================
--  3. `verifier_action_sensible()` v2 — GARDE DES RPC D'ÉCRITURE
-- ============================================================================
--  À appeler en tête de toute RPC d'écriture sensible :
--      perform public.verifier_action_sensible('vente');

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

  if v_etat = 'ACTIVATION' then
    raise exception
      'ACTIVATION_REQUISE|Votre compte est en attente de validation : impossible de réaliser « % ». Les fonctionnalités seront débloquées dès la validation de votre paiement par notre équipe.',
      v_nature;
  end if;

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
  'Module 12/17 : bloque une action sensible si le compte n''est pas activé (ACTIVATION), suspendu ou échu.';


-- ============================================================================
--  4. VERROU SERVEUR — TRIGGERS SUR LES TABLES COMMERCIALES
-- ============================================================================
--  Objectif : même en passant « par un lien » (PostgREST direct, RPC, script),
--  AUCUNE écriture commerciale n'est possible tant que le compte n'est pas
--  opérationnel. Le personnel plateforme (admin, gestionnaire, finance) est
--  exempté — il doit pouvoir préparer/équiper les comptes.

create or replace function public.trg_blocage_commercial()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row   jsonb;
  v_owner uuid;
  v_etat  text;
  v_parent uuid;
begin
  -- Le personnel plateforme n'est jamais bloqué par le verrou client.
  if public.est_plateforme() then
    return coalesce(new, old);
  end if;

  v_row := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;

  -- 1. Propriétaire direct (`owner_id` de la ligne).
  begin
    v_owner := nullif(v_row ->> 'owner_id', '')::uuid;
  exception when others then
    v_owner := null;
  end;

  -- 2. Table fille : résolution via la table parente.
  --    Trigger créé avec les arguments ('table_parente', 'colonne_fk').
  if v_owner is null and tg_nargs >= 2 then
    begin
      v_parent := nullif(v_row ->> tg_argv[1], '')::uuid;
      if v_parent is not null then
        execute format(
          'select owner_id from public.%I where id = $1', tg_argv[0]
        ) into v_owner using v_parent;
      end if;
    exception when others then
      v_owner := null;
    end;
  end if;

  -- Owner illisible : fail-open (jamais de blocage accidentel).
  if v_owner is null then
    return coalesce(new, old);
  end if;

  v_etat := public.abonnement_etat(v_owner);

  if v_etat = 'OK' then
    return coalesce(new, old);
  end if;

  if v_etat = 'ACTIVATION' then
    raise exception
      'ACTIVATION_REQUISE|Votre compte est en attente de validation. Votre paiement doit être vérifié et votre compte approuvé par notre équipe avant de pouvoir utiliser les fonctionnalités de votre entreprise.';
  end if;

  if v_etat = 'LECTURE_SEULE' then
    raise exception
      'ABONNEMENT_EXPIRE|Abonnement échu ou compte restreint (lecture seule) : cette opération est momentanément indisponible. Régularisez votre abonnement pour la débloquer.';
  end if;

  raise exception
    'ABONNEMENT_BLOQUE|Compte suspendu : contactez l''administrateur pour réactiver votre accès.';
end;
$$;

comment on function public.trg_blocage_commercial() is
  'Module 17 — Refuse toute écriture commerciale tant que le compte n''est pas activé (ou si l''abonnement est échu/suspendu). Personnel plateforme exempté.';


-- 4.a Tables avec `owner_id` direct -------------------------------------------
do $$
declare
  r record;
begin
  for r in
    select *
      from (values
        ('ventes',                'insert'),
        ('produits',              'insert or update or delete'),
        ('conditionnements',      'insert or update or delete'),
        ('approvisionnements',    'insert'),
        ('ajustements',           'insert'),
        ('inventaires_quotidiens', 'insert'),
        ('depenses',              'insert'),
        ('dettes',                'insert'),
        ('caisse',                'insert'),
        ('clotures_caisse',       'insert'),
        ('chambres',              'insert or update or delete'),
        ('reservations',          'insert or update'),
        ('tables_salle',          'insert or update or delete'),
        ('commandes',             'insert or update'),
        ('salles',                'insert or update or delete'),
        ('evenements',            'insert or update'),
        ('matieres_premieres',    'insert or update or delete'),
        ('productions',           'insert or update')
      ) as t(table_name, operations)
  loop
    -- Migration non exécutée (table absente) : on ignore.
    if to_regclass(format('public.%I', r.table_name)) is null then
      continue;
    end if;

    execute format(
      'drop trigger if exists trg_m17_blocage on public.%I', r.table_name
    );
    execute format(
      'create trigger trg_m17_blocage before %s on public.%I '
      'for each row execute function public.trg_blocage_commercial()',
      r.operations, r.table_name
    );
  end loop;
end $$;

-- 4.b Tables filles (propriétaire résolu via le parent) ------------------------
do $$
declare
  r record;
begin
  for r in
    select *
      from (values
        ('lignes_commande',          'commandes',   'commande_id',    'insert or update or delete'),
        ('lignes_evenement',         'evenements',  'evenement_id',   'insert or update or delete'),
        ('consommations_production', 'productions', 'production_id',  'insert or update or delete')
      ) as t(table_name, parent_table, fk_colonne, operations)
  loop
    if to_regclass(format('public.%I', r.table_name)) is null
       or to_regclass(format('public.%I', r.parent_table)) is null then
      continue;
    end if;

    execute format(
      'drop trigger if exists trg_m17_blocage on public.%I', r.table_name
    );
    execute format(
      'create trigger trg_m17_blocage before %s on public.%I '
      'for each row execute function public.trg_blocage_commercial(%L, %L)',
      r.operations, r.table_name, r.parent_table, r.fk_colonne
    );
  end loop;
end $$;


-- ============================================================================
--  5. `rpc_entreprises_de_utilisateur()` v2 — + ÉTAPE D'ACTIVATION
-- ============================================================================
--  L'application calcule son état d'accès à partir de cette fonction :
--  elle doit connaître `activation_etape` pour afficher les cadenas et le
--  message « compte en attente de validation ».
--
--  ⚠️ BUG CORRIGÉ : la version déployée renvoyait une LISTE VIDE pour des
--  comptes pourtant rattachés à une entreprise (diagnostic production du
--  20/09/2026) → le client restait « fail-open » et pouvait commercer sans
--  validation. La fonction est supprimée puis RECRÉÉE (changement de
--  colonnes retournées) avec la résolution entreprise du module 1 : la ligne
--  de l'utilisateur, ou celle de son patron pour un collaborateur.

drop function if exists public.rpc_entreprises_de_utilisateur(uuid);

create or replace function public.rpc_entreprises_de_utilisateur(
  p_user_id uuid default null
)
returns table (
  entreprise_id   uuid,
  nom             text,
  statut          text,
  date_expiration timestamptz,
  solde_restant   numeric,
  activation_etape text
)
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  v_cible      uuid;
  v_entreprise uuid;
begin
  if auth.uid() is null then
    raise exception 'ACCES_REFUSE';
  end if;

  v_cible := coalesce(p_user_id, auth.uid());

  -- Consulter l'entreprise d'un autre utilisateur est réservé aux admins.
  if v_cible <> auth.uid() then
    if not exists (
      select 1 from public.utilisateurs u
      where u.id = auth.uid() and u.role = 'admin'
    ) then
      raise exception 'ACCES_REFUSE';
    end if;
  end if;

  -- Entreprise de l'utilisateur. Un collaborateur dont la colonne
  -- `entreprise_id` est vide hérite de celle de son patron (`parent_id`).
  select coalesce(utilisateur.entreprise_id, patron.entreprise_id)
    into v_entreprise
    from public.utilisateurs utilisateur
    left join public.utilisateurs patron
           on patron.id = utilisateur.parent_id
   where utilisateur.id = v_cible;

  -- Aucune entreprise rattachée : on ne renvoie rien (l'application laisse
  -- alors l'accès ouvert).
  if v_entreprise is null then
    return;
  end if;

  return query
    select e.id,
           e.nom,
           e.statut::text,
           e.date_expiration,
           e.solde_restant,
           e.activation_etape
      from public.entreprises e
     where e.id = v_entreprise;
end;
$$;

comment on function public.rpc_entreprises_de_utilisateur(uuid) is
  'Module 1/17 — Entreprise d''un utilisateur (statut, échéance, solde ET étape d''activation) pour le middleware d''accès de l''application.';

revoke all on function public.rpc_entreprises_de_utilisateur(uuid) from public;
revoke all on function public.rpc_entreprises_de_utilisateur(uuid) from anon;
grant execute on function public.rpc_entreprises_de_utilisateur(uuid) to authenticated;


-- ============================================================================
--  6. `rpc_types_espaces_publics()` — CATÉGORIES POUR L'INSCRIPTION
-- ============================================================================
--  Le client choisit sa catégorie d'activité DÈS LA CRÉATION du compte.
--  Le référentiel `types_espaces_modules` n'est pas lisible directement par
--  les clients (RLS plateforme) : cette fonction n'expose que le code et le
--  libellé des catégories actives — aucune donnée sensible.

create or replace function public.rpc_types_espaces_publics()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if to_regclass('public.types_espaces_modules') is null then
    return '[]'::jsonb;
  end if;

  return coalesce(
    (
      select jsonb_agg(
               jsonb_build_object('type', t.type, 'libelle', t.libelle)
               order by (t.type = 'boutique') desc, t.libelle
             )
        from public.types_espaces_modules t
       where t.actif
    ),
    '[]'::jsonb
  );
end;
$$;

comment on function public.rpc_types_espaces_publics() is
  'Module 17 — Catégories d''activité actives (code + libellé) pour le sélecteur d''inscription. Aucune donnée sensible.';

revoke all on function public.rpc_types_espaces_publics() from public;
grant execute on function public.rpc_types_espaces_publics() to anon;
grant execute on function public.rpc_types_espaces_publics() to authenticated;


-- ============================================================================
--  7. `rpc_entreprise_creer()` v6 — LA CATÉGORIE EST RESPECTÉE
-- ============================================================================
--  Nouveau paramètre `p_type` (catégorie choisie) :
--    • validé par le référentiel (repli « autre », puis « boutique ») ;
--    • l'espace créé porte cette catégorie → les modules de l'application
--      suivent automatiquement (`rpc_mes_modules`) ;
--    • nom par défaut : « <Libellé> <nom> » (ex. « Hôtel Jambo ») au lieu
--      du « Boutique <nom> » figé.
--  ⚠️ L'ancienne signature (text, text) est supprimée pour éviter une
--  surcharge ambiguë côté PostgREST.

drop function if exists public.rpc_entreprise_creer(text, text);

create or replace function public.rpc_entreprise_creer(
  p_nom       text default null,
  p_telephone text default null,
  p_type      text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user    uuid := auth.uid();
  v_exist   uuid;
  v_nomu    text;
  v_nom     text;
  v_new     uuid;
  v_tel     text;
  v_type    text;
  v_libelle text;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour créer votre entreprise.';
  end if;

  -- Déjà rattaché ? On ne duplique pas.
  select u.entreprise_id into v_exist
    from public.utilisateurs u
   where u.id = v_user;

  if v_exist is not null then
    return jsonb_build_object('ok', true, 'deja', true, 'entreprise_id', v_exist);
  end if;

  select coalesce(nullif(btrim(u.nom), ''), u.email) into v_nomu
    from public.utilisateurs u
   where u.id = v_user;

  -- 🧩 MODULE 17 — catégorie d'activité validée par le référentiel.
  v_type := lower(btrim(coalesce(p_type, 'boutique')));
  if to_regclass('public.types_espaces_modules') is not null then
    select t.libelle into v_libelle
      from public.types_espaces_modules t
     where t.type = v_type and t.actif;

    if v_libelle is null then
      v_type := 'autre';
      select t.libelle into v_libelle
        from public.types_espaces_modules t
       where t.type = v_type and t.actif;
    end if;

    if v_libelle is null then
      v_type := 'boutique';
      select t.libelle into v_libelle
        from public.types_espaces_modules t
       where t.type = v_type and t.actif;
    end if;
  end if;

  v_type    := coalesce(v_type, 'boutique');
  v_libelle := coalesce(v_libelle, 'Boutique');

  v_nom := nullif(btrim(coalesce(p_nom, '')), '');
  if v_nom is null then
    v_nom := v_libelle || ' ' || coalesce(v_nomu, 'nouvelle');
  end if;

  v_tel := nullif(btrim(coalesce(p_telephone, '')), '');

  insert into public.entreprises (nom)
  values (v_nom)
  returning id into v_new;

  -- Module 15/17 — espace par défaut (identifiant = UUID du patron) avec la
  -- CATÉGORIE choisie : l'environnement (modules, tableaux de bord) suivra.
  insert into public.espaces (id, entreprise_id, nom, type, actif)
  values (v_user, v_new, v_nom, v_type, true)
  on conflict (id) do nothing;

  -- Rattachement + téléphone + normalisation du rôle du PATRON.
  update public.utilisateurs
     set entreprise_id   = v_new,
         espace_actif_id = v_user,
         telephone       = coalesce(v_tel, telephone),
         new_role        = case when parent_id is null
                                then coalesce(public.role_enum('PROPRIETAIRE'), new_role)
                                else new_role end,
         role            = case when parent_id is null
                                then 'PROPRIETAIRE'
                                else role end
   where id = v_user;

  -- 🛡️ MODULE 14 — double validation obligatoire : le compte n'est PAS
  -- opérationnel tant que le gestionnaire puis la finance n'ont pas validé.
  -- (`abonnement_etat` renvoie désormais 'ACTIVATION' → verrou serveur.)
  update public.entreprises
     set activation_etape = 'en_attente_verification',
         statut = 'EN_ATTENTE_COMPLEMENT'::public.statut_abonnement_enum,
         updated_at = now()
   where id = v_new;

  insert into public.activations_entreprise (
    entreprise_id, etape, acteur_id, acteur_role, note
  ) values (
    v_new, 'soumission', v_user, public.mon_role(), 'Création du compte'
  );

  -- Trace (best-effort : ne doit jamais faire échouer la création).
  begin
    insert into public.journal_audit (entreprise_id, action, utilisateur_id, details)
    values (
      null, 'CREATION_ENTREPRISE', v_user,
      jsonb_build_object(
        'entreprise_id', v_new, 'nom', v_nom,
        'type', v_type, 'libelle', v_libelle,
        'activation_etape', 'en_attente_verification',
        'telephone', v_tel
      )
    );
  exception when others then null;
  end;

  return jsonb_build_object(
    'ok', true, 'deja', false,
    'entreprise_id', v_new, 'nom', v_nom,
    'type', v_type, 'libelle', v_libelle,
    'activation_etape', 'en_attente_verification'
  );
end;
$$;

comment on function public.rpc_entreprise_creer(text, text, text) is
  'Module 14/15/17 — Crée l''entreprise (EN ATTENTE DE VÉRIFICATION) avec la CATÉGORIE choisie, son espace, rattache le patron (rôle normalisé) et enregistre son téléphone.';

revoke all on function public.rpc_entreprise_creer(text, text, text) from public;
revoke all on function public.rpc_entreprise_creer(text, text, text) from anon;
grant execute on function public.rpc_entreprise_creer(text, text, text) to authenticated;


-- ============================================================================
--  8. `rpc_espace_type_definir()` — CORRIGER LA CATÉGORIE D'UN ESPACE
-- ============================================================================
--  Réservé au PROPRIÉTAIRE : change la catégorie d'activité d'une de ses
--  entreprises. Les modules de l'application suivent immédiatement
--  (`rpc_mes_modules` lit `espaces.type`).

create or replace function public.rpc_espace_type_definir(
  p_espace_id uuid,
  p_type      text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user    uuid := auth.uid();
  v_role    text := public.mon_role();
  v_ent     uuid;
  v_esp_ent uuid;
  v_type    text;
  v_libelle text;
  v_modules jsonb;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour changer la catégorie.';
  end if;

  if v_role <> 'PROPRIETAIRE' then
    raise exception 'DROIT_REFUSE|Seul le propriétaire du compte peut changer la catégorie de l''activité.';
  end if;

  if p_espace_id is null then
    raise exception 'ESPACE_REQUIS|Précisez l''entreprise à modifier.';
  end if;

  if to_regclass('public.types_espaces_modules') is null then
    raise exception 'NON_DEPLOYE|Le référentiel des activités n''est pas installé (migration 27).';
  end if;

  select s.entreprise_id into v_esp_ent
    from public.espaces s
   where s.id = p_espace_id;

  if v_esp_ent is null then
    raise exception 'ESPACE_INTROUVABLE|Cette entreprise n''existe pas.';
  end if;

  select u.entreprise_id into v_ent
    from public.utilisateurs u
   where u.id = v_user;

  if v_ent is null or v_esp_ent is distinct from v_ent then
    raise exception 'HORS_ENTREPRISE|Cette entreprise n''appartient pas à votre compte.';
  end if;

  -- Catégorie validée STRICTEMENT : une valeur inconnue est refusée (le
  -- client a explicitement demandé cette catégorie).
  v_type := lower(btrim(coalesce(p_type, '')));
  select t.libelle, t.modules into v_libelle, v_modules
    from public.types_espaces_modules t
   where t.type = v_type and t.actif;

  if v_libelle is null then
    raise exception 'TYPE_INCONNU|Cette catégorie d''activité n''existe pas ou n''est plus disponible.';
  end if;

  update public.espaces
     set type = v_type,
         updated_at = now()
   where id = p_espace_id;

  -- Trace (best-effort).
  begin
    insert into public.journal_audit (entreprise_id, action, utilisateur_id, details)
    values (
      null, 'ESPACE_TYPE', v_user,
      jsonb_build_object(
        'espace_id', p_espace_id, 'type', v_type, 'libelle', v_libelle
      )
    );
  exception when others then null;
  end;

  return jsonb_build_object(
    'ok', true,
    'espace_id', p_espace_id,
    'type', v_type,
    'libelle', v_libelle,
    'modules', coalesce(v_modules, '[]'::jsonb)
  );
end;
$$;

comment on function public.rpc_espace_type_definir(uuid, text) is
  'Module 17 — Le propriétaire change la catégorie d''activité d''un de ses espaces (Hôtel, Restaurant…) : les modules de l''application suivent automatiquement.';

revoke all on function public.rpc_espace_type_definir(uuid, text) from public;
revoke all on function public.rpc_espace_type_definir(uuid, text) from anon;
grant execute on function public.rpc_espace_type_definir(uuid, text) to authenticated;


-- ============================================================================
--  9. VÉRIFICATIONS (à relire après exécution)
-- ============================================================================

-- 9.a Les triggers de verrou sont en place (attendu : 21 lignes).
select event_object_table as table_protegee,
       trigger_name,
       event_manipulation
  from information_schema.triggers
 where trigger_schema = 'public'
   and trigger_name = 'trg_m17_blocage'
 order by event_object_table, event_manipulation;

-- 9.b Les fonctions du module existent (attendu : 6 lignes).
select routine_name
  from information_schema.routines
 where routine_schema = 'public'
   and routine_name in (
     'entreprise_de_proprietaire', 'abonnement_etat',
     'verifier_action_sensible', 'trg_blocage_commercial',
     'rpc_entreprise_creer', 'rpc_espace_type_definir',
     'rpc_types_espaces_publics'
   )
 order by routine_name;

-- 9.c État d'accès des dernières entreprises (diagnostic).
--     ACTIVATION = en attente de vérification/finance ; OK = opérationnel.
select e.nom,
       e.statut,
       e.activation_etape,
       e.date_expiration,
       public.abonnement_etat(e.id) as etat_acces
  from public.entreprises e
 order by e.created_at desc
 limit 10;

-- 9.d Catégories d'activité proposées à l'inscription.
select public.rpc_types_espaces_publics() as categories;

-- ============================================================================
--  FIN — Module 17. Un compte ne commerce qu'une fois VÉRIFIÉ (gestionnaire)
--  et ACTIVÉ (finance). Il ne suffit plus de masquer des boutons : le
--  serveur refuse toute écriture commerciale (triggers + RPC). La catégorie
--  choisie à la création détermine désormais l'environnement du client
--  (Hôtel → chambres/réservations…, Boutique → ventes/stock…).
-- ============================================================================
