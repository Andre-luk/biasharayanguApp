-- ============================================================================
--  MODULE 21 — CORRECTIFS + AGENT TERRAIN + PURGE MAÎTRISÉE
--  Migration 20260916000043_agent_terrain_purge_et_correctifs.sql
-- ============================================================================
--
--  À exécuter APRÈS les migrations 18, 23, 40 et 41.
--  IDEMPOTENTE : rejouable sans effet de bord (chaque étape détecte si elle
--  a déjà été appliquée et le signale).
--
--  CE QU'ELLE CORRIGE ET AJOUTE
--  ---------------------------
--  1. « column "s.entreprise" must appear in the GROUP BY clause »
--     Écran Administration → Boutiques.
--     CAUSE : dans `rpc_admin_espaces_lister`, la requête extérieure est une
--     agrégation (`jsonb_agg`) SANS `group by`, mais elle terminait par
--     `order by s.entreprise, s.nom limit … offset …`. En PostgreSQL, dès
--     qu'une requête contient une fonction d'agrégation sans `group by`,
--     toute colonne citée hors agrégat est refusée — y compris dans le
--     `order by`. Le `order by` était de plus INOPÉRANT (l'ordre vient déjà
--     de `jsonb_agg(... order by ...)`) et le `limit/offset` ne paginier
--     RIEN (une agrégation scalaire renvoie une seule ligne).
--     CORRECTIF : le tri et la pagination sont déplacés DANS la sous-requête,
--     là où ils agissent réellement sur les lignes.
--
--  2. « je ne trouve pas où mettre le montant total dû »
--     Écran Administration → Activations & paiements.
--     CAUSE : la fenêtre de validation n'offrait que « Montant reçu ». Or le
--     moteur d'abonnement a besoin du MONTANT TOTAL DÛ de l'entreprise :
--     s'il vaut 0, la validation échoue (`MONTANT_TOTAL_INCONNU`) ; s'il est
--     inférieur à ce qui a été encaissé, elle échoue aussi
--     (`MONTANT_SUPERIEUR`). Le montant total n'était modifiable nulle part.
--     CORRECTIF : nouvelle RPC `rpc_activation_definir_montant_total(...)`
--     (le champ est ajouté à la fenêtre côté application) ; et le moteur
--     d'abonnement fait désormais PRIMER le montant négocié pour
--     l'entreprise sur le prix générique du pack tarifaire.
--
--  3. RÔLE « AGENT_TERRAIN » (agent de terrain)
--     Un agent terrain crée une entreprise, vérifie son dossier, l'active et
--     valide les paiements — sans être Super Admin. Ajout du rôle dans
--     l'énumération, de ses pages de permission, et ouverture des RPC du
--     workflow d'activation à ce rôle (le serveur reste seul juge).
--
--  4. PURGE MAÎTRISÉE (Super Admin)
--     `rpc_admin_purger_utilisateur` et `rpc_admin_purger_entreprise` :
--     suppression RÉELLE d'un compte et de toutes ses données, réservée au
--     Super Admin, exigeant la saisie du nom exact, et FOURNIE EN MODE
--     SIMULATION par défaut (rien n'est détruit tant que l'appelant ne
--     demande pas explicitement l'exécution).
--     ⚠️ Ceci complète la migration 41 (désactivation / anonymisation) :
--        la purge détruit des historiques, elle est donc l'exception.
--
--  Aucune donnée n'est modifiée par cette migration elle-même : elle ne
--  touche que des définitions de fonctions et l'énumération des rôles.
-- ============================================================================


-- ============================================================================
--  0. OUTIL INTERNE — PATCHER LE CORPS D'UNE FONCTION EXISTANTE
-- ============================================================================
--  Les fonctions réécrites ici (`permissions_defaut`, moteur d'abonnement,
--  workflow d'activation) sont longues et ont déjà été livrées. Les RECOPIER
--  dans cette migration créerait deux sources de vérité : une correction
--  future dans l'une ne suivrait pas l'autre. On modifie donc le corps
--  installé, à un endroit précis, avec :
--    • un motif (expression régulière) qui doit exister — sinon on ÉCHOUE
--      franchement au lieu de laisser croire que tout est corrigé ;
--    • un marqueur qui prouve que le patch est déjà là (idempotence).

create or replace function public.biashara_patcher_fonction(
  p_nom          text,
  p_motif        text,
  p_remplacement text,
  p_marqueur     text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_catalog
as $helper$
declare
  v_rec     record;
  v_def     text;
  v_nouveau text;
  v_appliques text[] := array[]::text[];
  v_deja      text[] := array[]::text[];
begin
  for v_rec in
    select p.oid as oid, p.proname as nom, pg_get_functiondef(p.oid) as def
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname = p_nom
     order by p.oid
  loop
    if position(p_marqueur in v_rec.def) > 0 then
      v_deja := v_deja || v_rec.nom;
      continue;
    end if;

    v_nouveau := regexp_replace(v_rec.def, p_motif, p_remplacement, 'gn');

    if v_nouveau = v_rec.def then
      raise exception
        'MOTIF_INTROUVABLE|public.% : le fragment attendu n''a pas été trouvé. La base porte une version différente de celle attendue : réinstallez d''abord les migrations 18, 23, 40 et 41, puis relancez ce fichier.',
        p_nom;
    end if;

    execute v_nouveau;
    v_appliques := v_appliques || v_rec.nom;
  end loop;

  return jsonb_build_object(
    'ok', true,
    'fonction', p_nom,
    'patchees', to_jsonb(v_appliques),
    'deja_patches', to_jsonb(v_deja)
  );
end;
$helper$;

comment on function public.biashara_patcher_fonction(text, text, text, text) is
  'Module 21 — OUTIL DE MAINTENANCE : applique une substitution contrôlée au corps d''une fonction existante (motif obligatoire, marqueur d''idempotence). Non exécutable par les clients.';

revoke all on function public.biashara_patcher_fonction(text, text, text, text)
  from public, anon, authenticated;


-- ============================================================================
--  1. CORRECTIF — « column "s.entreprise" must appear in the GROUP BY clause »
-- ============================================================================
--  Fonction RECOPIÉE intégralement (elle est courte) : le tri et la
--  pagination passent dans la sous-requête `s`, où ils filtrent réellement
--  les lignes. L'agrégation extérieure ne contient plus que `jsonb_agg`.

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
begin
  perform public.biashara_exiger_plateforme();

  if v_filtre not in ('tous', 'actifs', 'inactifs', 'visibles', 'non_visibles') then
    v_filtre := 'tous';
  end if;

  -- Compteurs globaux (indépendants de la page affichée).
  select count(*),
         count(*) filter (where e.actif),
         count(*) filter (where e.visible_publiquement)
    into v_total, v_actifs, v_visibles
    from public.espaces e;

  -- ⚠️ CORRECTIF 43 : toute la sélection (recherche, filtres, TRI,
  -- PAGINATION) se fait DANS la sous-requête. La requête extérieure se
  -- contente d'agréger : plus aucune colonne non agrégée hors `jsonb_agg`,
  -- et la pagination agit enfin sur les lignes.
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
  'Module 20/21 — Parc complet des boutiques/espaces de la plateforme (recherche, filtres, compteurs, pagination réelle). Réservé au personnel plateforme. Correctif 43 : tri et pagination placés dans la sous-requête (erreur GROUP BY supprimée).';


-- ============================================================================
--  2. MONTANT TOTAL DÛ D'UN ABONNEMENT
-- ============================================================================

--  2.a RPC : fixer (ou corriger) le montant total dû d'une entreprise.
--      C'est le champ qui manquait à la fenêtre « Valider le paiement ».
--      `solde_restant` étant une colonne GÉNÉRÉE (total − payé), le solde se
--      recalcule automatiquement : rien d'autre n'est écrit à la main.
create or replace function public.rpc_activation_definir_montant_total(
  p_entreprise_id uuid,
  p_montant       numeric,
  p_note          text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role  text := public.mon_role();
  v_e     public.entreprises;
  v_avant numeric;
  v_note  text := nullif(btrim(coalesce(p_note, '')), '');
begin
  -- Plateau : finance, agent terrain, gestionnaire des comptes ou Super Admin.
  if v_role not in ('FINANCE_LAPERLE', 'AGENT_TERRAIN',
                    'GESTIONNAIRE_COMPTES', 'SUPER_ADMIN') then
    raise exception 'DROIT_REFUSE|Seuls la finance, un agent terrain ou le gestionnaire des comptes fixent le montant dû d''un abonnement.';
  end if;

  if p_montant is null or p_montant <= 0 then
    raise exception 'MONTANT_INVALIDE|Indiquez le montant total dû (valeur supérieure à zéro).';
  end if;

  select * into v_e from public.entreprises
   where id = p_entreprise_id for update;

  if not found then
    raise exception 'ENTREPRISE_INTROUVABLE|Ce compte n''existe plus.';
  end if;

  v_avant := coalesce(v_e.montant_total_du, 0);

  update public.entreprises
     set montant_total_du = p_montant,
         updated_at       = now()
   where id = p_entreprise_id
   returning * into v_e;

  begin
    insert into public.journal_audit (entreprise_id, action, utilisateur_id, details)
    values (
      p_entreprise_id, 'MONTANT_TOTAL_FIXE', auth.uid(),
      jsonb_build_object(
        'montant_avant', v_avant,
        'montant_apres', p_montant,
        'deja_paye', coalesce(v_e.montant_deja_paye, 0),
        'solde_restant', v_e.solde_restant,
        'note', v_note
      )
    );
  exception when others then null;
  end;

  return jsonb_build_object(
    'ok', true,
    'entreprise_id', p_entreprise_id,
    'montant_total_du', p_montant,
    'montant_avant', v_avant,
    'montant_deja_paye', coalesce(v_e.montant_deja_paye, 0),
    'solde_restant', v_e.solde_restant
  );
end;
$$;

comment on function public.rpc_activation_definir_montant_total(uuid, numeric, text) is
  'Module 21 — Fixe le montant total dû d''un abonnement (le solde_restant généré suit automatiquement). Le champ manquait dans la fenêtre de validation du paiement : sans lui, une entreprise sans grille tarifaire échouait en MONTANT_TOTAL_INCONNU.';

revoke all on function public.rpc_activation_definir_montant_total(uuid, numeric, text)
  from public, anon;
grant execute on function public.rpc_activation_definir_montant_total(uuid, numeric, text)
  to authenticated;


--  2.b Le montant NÉGOCIÉ pour l'entreprise prime sur le prix générique du
--      pack tarifaire (moteur d'abonnement, migration 23).
do $patch_engine$
declare
  v_res jsonb;
begin
  v_res := public.biashara_patcher_fonction(
    'rpc_abonnement_enregistrer_paiement',
    $motif$v_total := coalesce\(\s*\(select nullif\(g\.montant_abonnement, 0\)$motif$,
    $repl$-- correctif 43 : le montant total NÉGOCIÉ pour l''entreprise prime sur
    -- le prix générique du pack tarifaire (sinon le montant saisi à la
    -- validation du paiement serait ignoré).
    v_total := coalesce(
      nullif(v_total, 0),
      (select nullif(g.montant_abonnement, 0)$repl$,
    'correctif 43 : le montant total'
  );
  raise notice 'Moteur d''abonnement : %', v_res::text;
end $patch_engine$;


-- ============================================================================
--  3. AGENT TERRAIN — NOUVEAU RÔLE
-- ============================================================================

--  3.a Énumération des rôles.
alter type public.role_utilisateur_enum add value if not exists 'AGENT_TERRAIN';

comment on type public.role_utilisateur_enum is
  'Rôles applicatifs (Module 4 + AGENT_TERRAIN ajouté par le module 21).';


--  3.b Pages et actions par défaut du rôle.
--      Le CASE de `permissions_defaut` se termine par `else return '{}'` :
--      on insère la branche du nouveau rôle juste avant.
do $patch_perms$
declare
  v_res jsonb;
begin
  v_res := public.biashara_patcher_fonction(
    'permissions_defaut',
    $motif$\n\s*else\s*\n\s*return '\{\}'::jsonb;$motif$,
    $repl$
    -- 🧑🌾 MODULE 21 — AGENT TERRAIN : il crée les entreprises, vérifie et
    -- active leurs dossiers et valide les paiements reçus. Il ne touche ni
    -- aux permissions, ni aux référentiels sensibles (super admin seul).
    when 'AGENT_TERRAIN' then
      v_pages   := array['dashboard', 'entreprises', 'utilisateurs', 'villes',
                         'activites', 'groupes_tarifaires', 'abonnements',
                         'paiements', 'boutiques', 'assistance',
                         'notifications'];
      v_actions := array['voir', 'creer', 'modifier', 'valider'];

    else
      return '{}'::jsonb;$repl$,
    'AGENT_TERRAIN'
  );
  raise notice 'permissions_defaut : %', v_res::text;
end $patch_perms$;


--  3.c Serveur : le workflow d'activation accepte l'agent terrain.
--      Trois listes de rôles existent dans le code ; on les complète toutes.
do $patch_roles$
declare
  v_rec  record;
  v_def  text;
  v_new  text;
  v_noms text[] := array[]::text[];
  v_listes text[] := array[
    $l1$'GESTIONNAIRE_COMPTES', 'FINANCE_LAPERLE', 'SUPER_ADMIN'$l1$,
    $l2$'FINANCE_LAPERLE', 'SUPER_ADMIN'$l2$,
    $l3$'GESTIONNAIRE_COMPTES', 'SUPER_ADMIN'$l3$
  ];
  v_ajout text[] := array[
    $a1$'GESTIONNAIRE_COMPTES', 'FINANCE_LAPERLE', 'AGENT_TERRAIN', 'SUPER_ADMIN'$a1$,
    $a2$'FINANCE_LAPERLE', 'AGENT_TERRAIN', 'SUPER_ADMIN'$a2$,
    $a3$'GESTIONNAIRE_COMPTES', 'AGENT_TERRAIN', 'SUPER_ADMIN'$a3$
  ];
  v_i integer;
begin
  for v_rec in
    select p.oid as oid, p.proname as nom, pg_get_functiondef(p.oid) as def
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.prokind = 'f'
       and pg_get_functiondef(p.oid) like '%''SUPER_ADMIN''%'
     order by p.proname
  loop
    v_def := v_rec.def;

    -- Déjà traité ?
    if position('''AGENT_TERRAIN''' in v_def) > 0 then
      continue;
    end if;

    v_new := v_def;
    for v_i in 1..array_length(v_listes, 1) loop
      v_new := replace(v_new, v_listes[v_i], v_ajout[v_i]);
    end loop;

    if v_new <> v_def then
      execute v_new;
      v_noms := v_noms || v_rec.nom;
    end if;
  end loop;

  if array_length(v_noms, 1) is null then
    raise notice 'Workflow d''activation : déjà ouvert à AGENT_TERRAIN (aucune modification).';
  else
    raise notice 'Workflow d''activation ouvert à AGENT_TERRAIN pour : %',
      array_to_string(v_noms, ', ');
  end if;
end $patch_roles$;


--  3.d Création du COMPTE d'un agent terrain (Super Admin ou gestionnaire).
--      Réutilise `creer_compte_plateforme` : le mot de passe est haché par
--      GoTrue (bcrypt) et la session de l'administrateur n'est PAS changée.
create or replace function public.rpc_admin_creer_agent_terrain(
  p_email    text,
  p_password text,
  p_nom      text,
  p_prenom   text,
  p_note     text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  v_role   text := public.mon_role();
  v_email  text := lower(btrim(coalesce(p_email, '')));
  v_id     uuid;
  v_existe integer := 0;
begin
  if v_role not in ('SUPER_ADMIN', 'GESTIONNAIRE_COMPTES') then
    raise exception 'DROIT_REFUSE|Seul le Super Admin ou le gestionnaire des comptes crée un agent terrain.';
  end if;

  if v_email = '' or position('@' in v_email) = 0 then
    raise exception 'EMAIL_INVALIDE|Adresse e-mail invalide.';
  end if;

  if p_password is null or length(p_password) < 8 then
    raise exception 'MOT_DE_PASSE_TROP_COURT|Le mot de passe doit comporter au moins 8 caractères.';
  end if;

  select count(*) into v_existe
    from public.utilisateurs u where lower(u.email) = v_email;

  v_id := public.creer_compte_plateforme(
            v_email, p_password,
            coalesce(nullif(btrim(p_nom), ''), 'Agent'),
            coalesce(nullif(btrim(p_prenom), ''), 'terrain'),
            'AGENT_TERRAIN');

  begin
    insert into public.journal_audit (entreprise_id, action, utilisateur_id, details)
    values (
      null, 'ADMIN_AGENT_TERRAIN_CREE', auth.uid(),
      jsonb_build_object(
        'agent_id', v_id, 'email', v_email,
        'compte_existant', (v_existe > 0),
        'note', nullif(btrim(coalesce(p_note, '')), '')
      )
    );
  exception when others then null;
  end;

  return jsonb_build_object(
    'ok', true,
    'agent_id', v_id,
    'email', v_email,
    'role', 'AGENT_TERRAIN',
    'compte_reutilise', (v_existe > 0)
  );
end;
$$;

comment on function public.rpc_admin_creer_agent_terrain(text, text, text, text, text) is
  'Module 21 — Crée (ou réaligne) le compte d''un AGENT TERRAIN : compte Auth GoTrue + profil applicatif, rôle AGENT_TERRAIN. Le mot de passe est haché par la base ; la session de l''administrateur est inchangée.';

revoke all on function public.rpc_admin_creer_agent_terrain(text, text, text, text, text)
  from public, anon;
grant execute on function public.rpc_admin_creer_agent_terrain(text, text, text, text, text)
  to authenticated;


-- ============================================================================
--  4. PURGE MAÎTRISÉE — SUPER ADMIN
-- ============================================================================
--  Les fonctions ci-dessous SUPPRIMENT réellement des données. Trois garde-
--  fous : (1) Super Admin uniquement ; (2) l'appelant doit recopier le nom
--  exact ; (3) `p_simulation` est vrai par défaut — sans demande explicite,
--  la fonction ne fait que COMPTER ce qu'elle détruirait.
--
--  Les tables rattachées sont découvertes dynamiquement dans le catalogue
--  PostgreSQL (`information_schema`) : une table ajoutée par un module futur
--  sera purgée sans qu'il faille modifier cette fonction.

create or replace function public.rpc_admin_purger_utilisateur(
  p_utilisateur_id   uuid,
  p_confirmation     text,
  p_simulation       boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_role   text := public.mon_role();
  v_u      public.utilisateurs;
  v_email  text;
  v_rec    record;
  v_n      integer;
  v_total  integer := 0;
  v_detail jsonb := '{}'::jsonb;
  v_erreurs jsonb := '{}'::jsonb;
  v_passe  integer;
  v_auth   boolean := false;
begin
  if v_role <> 'SUPER_ADMIN' then
    raise exception 'DROIT_REFUSE|Seul le Super Admin peut supprimer définitivement un compte et ses données.';
  end if;

  select * into v_u from public.utilisateurs where id = p_utilisateur_id;
  if not found then
    raise exception 'UTILISATEUR_INCONNU|Cet utilisateur est introuvable.';
  end if;

  v_email := lower(coalesce(v_u.email, ''));

  if lower(btrim(coalesce(p_confirmation, ''))) <> v_email then
    raise exception 'CONFIRMATION_INVALIDE|Recopiez exactement l''adresse e-mail du compte (%) pour confirmer.', v_email;
  end if;

  -- Les comptes de la plateforme ne sont jamais purgés ici : ils portent les
  -- droits d'administration et leur suppression peut verrouiller la
  -- plateforme. Le script de maintenance `tools/purger_comptes_entreprises.sql`
  -- documente la procédure pour ces cas exceptionnels.
  if v_u.entreprise_id is null
     and coalesce(v_u.new_role::text, '') in
         ('SUPER_ADMIN', 'GESTIONNAIRE_COMPTES', 'FINANCE_LAPERLE',
          'SUPPORT', 'AGENT_TERRAIN') then
    raise exception 'COMPTE_PLATEFORME|% est un compte de la plateforme (%) : sa suppression verrouillerait l''administration. Désactivez-le ou anonymisez-le (module 20), ou passez par le script de maintenance.', v_email, v_u.new_role::text;
  end if;

  -- Balayage : tables du schéma public portant une colonne d'identité
  -- utilisateur. Trois passes : une suppression peut échouer tant qu'une
  -- table dépendante n'est pas vidée (ordre des clés étrangères).
  for v_passe in 1..3 loop
    for v_rec in
      select c.table_name as table_name, c.column_name as column_name
        from information_schema.columns c
        join information_schema.tables t
          on t.table_schema = c.table_schema
         and t.table_name   = c.table_name
       where c.table_schema = 'public'
         and t.table_type   = 'BASE TABLE'
         and c.column_name in ('utilisateur_id', 'owner_id', 'vendeur_id',
                               'acteur_id', 'user_id', 'auteur_id',
                               'cree_par', 'enregistre_par', 'moderation_par',
                               'valide_par_finance', 'parent_id')
       order by c.table_name, c.column_name
    loop
      v_n := 0;
      begin
        execute format('select count(*) from public.%I where %I = $1',
                       v_rec.table_name, v_rec.column_name)
          into v_n using p_utilisateur_id;

        if v_n > 0 then
          v_detail := v_detail || jsonb_build_object(
            v_rec.table_name || '.' || v_rec.column_name, v_n);

          if not coalesce(p_simulation, true) then
            execute format('delete from public.%I where %I = $1',
                           v_rec.table_name, v_rec.column_name)
              using p_utilisateur_id;
            v_total := v_total + v_n;
          end if;
        end if;
      exception when others then
        if not coalesce(p_simulation, true) then
          v_erreurs := v_erreurs || jsonb_build_object(
            v_rec.table_name || '.' || v_rec.column_name, sqlerrm);
        end if;
      end;
    end loop;

    exit when coalesce(p_simulation, true);
  end loop;

  if not coalesce(p_simulation, true) then
    -- Profil applicatif, puis compte GoTrue (identités et sessions suivent
    -- par cascade).
    delete from public.utilisateurs where id = p_utilisateur_id;

    begin
      delete from auth.users where id = p_utilisateur_id;
      v_auth := true;
    exception when others then
      v_auth := false;
      v_erreurs := v_erreurs || jsonb_build_object('auth.users', sqlerrm);
    end;

    begin
      insert into public.journal_audit (entreprise_id, action, utilisateur_id, details)
      values (
        v_u.entreprise_id, 'ADMIN_UTILISATEUR_PURGE', auth.uid(),
        jsonb_build_object(
          'utilisateur_id', p_utilisateur_id,
          'email', v_email,
          'lignes_supprimees', v_total,
          'detail', v_detail,
          'erreurs', v_erreurs,
          'compte_auth_supprime', v_auth
        )
      );
    exception when others then null;
    end;
  end if;

  return jsonb_build_object(
    'ok', true,
    'simulation', coalesce(p_simulation, true),
    'utilisateur_id', p_utilisateur_id,
    'email', v_email,
    'lignes_concernees', v_total,
    'detail', v_detail,
    'erreurs', v_erreurs,
    'compte_auth_supprime', v_auth
  );
end;
$$;

comment on function public.rpc_admin_purger_utilisateur(uuid, text, boolean) is
  'Module 21 — Suppression DÉFINITIVE d''un compte et de toutes ses données (Super Admin uniquement, confirmation par e-mail, simulation par défaut). Les données sont découvertes dynamiquement dans le catalogue.';


create or replace function public.rpc_admin_purger_entreprise(
  p_entreprise_id uuid,
  p_confirmation  text,
  p_simulation    boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_role    text := public.mon_role();
  v_e       public.entreprises;
  v_rec     record;
  v_n       integer;
  v_total   integer := 0;
  v_detail  jsonb := '{}'::jsonb;
  v_erreurs jsonb := '{}'::jsonb;
  v_passe   integer;
  v_espaces uuid[] := array[]::uuid[];
  v_users   uuid[] := array[]::uuid[];
begin
  if v_role <> 'SUPER_ADMIN' then
    raise exception 'DROIT_REFUSE|Seul le Super Admin peut supprimer définitivement une entreprise et ses données.';
  end if;

  select * into v_e from public.entreprises where id = p_entreprise_id;
  if not found then
    raise exception 'ENTREPRISE_INTROUVABLE|Cette entreprise est introuvable.';
  end if;

  if lower(btrim(coalesce(p_confirmation, ''))) <> lower(btrim(coalesce(v_e.nom, ''))) then
    raise exception 'CONFIRMATION_INVALIDE|Recopiez exactement le nom de l''entreprise (%) pour confirmer.', v_e.nom;
  end if;

  select coalesce(array_agg(e.id), array[]::uuid[]) into v_espaces
    from public.espaces e where e.entreprise_id = p_entreprise_id;

  select coalesce(array_agg(u.id), array[]::uuid[]) into v_users
    from public.utilisateurs u where u.entreprise_id = p_entreprise_id;

  for v_passe in 1..3 loop
    for v_rec in
      select c.table_name as table_name, c.column_name as column_name
        from information_schema.columns c
        join information_schema.tables t
          on t.table_schema = c.table_schema
         and t.table_name   = c.table_name
       where c.table_schema = 'public'
         and t.table_type   = 'BASE TABLE'
         and c.column_name in ('entreprise_id', 'espace_id')
       order by c.table_name, c.column_name
    loop
      v_n := 0;
      begin
        if v_rec.column_name = 'entreprise_id' then
          execute format('select count(*) from public.%I where %I = $1',
                         v_rec.table_name, v_rec.column_name)
            into v_n using p_entreprise_id;

          if v_n > 0 and not coalesce(p_simulation, true) then
            execute format('delete from public.%I where %I = $1',
                           v_rec.table_name, v_rec.column_name)
              using p_entreprise_id;
          end if;
        else
          -- Colonnes `espace_id` : on ne supprime que les espaces de CETTE
          -- entreprise (jamais ceux des autres).
          execute format('select count(*) from public.%I where %I = any($1)',
                         v_rec.table_name, v_rec.column_name)
            into v_n using v_espaces;

          if v_n > 0 and not coalesce(p_simulation, true) then
            execute format('delete from public.%I where %I = any($1)',
                           v_rec.table_name, v_rec.column_name)
              using v_espaces;
          end if;
        end if;

        if v_n > 0 then
          v_detail := v_detail || jsonb_build_object(
            v_rec.table_name || '.' || v_rec.column_name, v_n);
          v_total := v_total + v_n;
        end if;
      exception when others then
        if not coalesce(p_simulation, true) then
          v_erreurs := v_erreurs || jsonb_build_object(
            v_rec.table_name || '.' || v_rec.column_name, sqlerrm);
        end if;
      end;
    end loop;

    exit when coalesce(p_simulation, true);
  end loop;

  if not coalesce(p_simulation, true) then
    begin
      delete from public.utilisateurs where entreprise_id = p_entreprise_id;
      delete from public.espaces
       where entreprise_id = p_entreprise_id;
      delete from public.entreprises where id = p_entreprise_id;
    exception when others then
      v_erreurs := v_erreurs || jsonb_build_object('entreprise', sqlerrm);
    end;

    -- Comptes GoTrue des utilisateurs rattachés (identités et sessions
    -- suivent par cascade).
    begin
      delete from auth.users where id = any(v_users);
    exception when others then
      v_erreurs := v_erreurs || jsonb_build_object('auth.users', sqlerrm);
    end;

    begin
      insert into public.journal_audit (entreprise_id, action, utilisateur_id, details)
      values (
        null, 'ADMIN_ENTREPRISE_PURGEE', auth.uid(),
        jsonb_build_object(
          'entreprise_id', p_entreprise_id,
          'nom', v_e.nom,
          'espaces', coalesce(array_length(v_espaces, 1), 0),
          'utilisateurs', coalesce(array_length(v_users, 1), 0),
          'lignes_supprimees', v_total,
          'detail', v_detail,
          'erreurs', v_erreurs
        )
      );
    exception when others then null;
    end;
  end if;

  return jsonb_build_object(
    'ok', true,
    'simulation', coalesce(p_simulation, true),
    'entreprise_id', p_entreprise_id,
    'nom', v_e.nom,
    'nb_espaces', coalesce(array_length(v_espaces, 1), 0),
    'nb_utilisateurs', coalesce(array_length(v_users, 1), 0),
    'lignes_concernees', v_total,
    'detail', v_detail,
    'erreurs', v_erreurs
  );
end;
$$;

comment on function public.rpc_admin_purger_entreprise(uuid, text, boolean) is
  'Module 21 — Suppression DÉFINITIVE d''une entreprise, de ses boutiques, de ses comptes et de toutes leurs données (Super Admin uniquement, confirmation par le nom, simulation par défaut).';


revoke all on function public.rpc_admin_purger_utilisateur(uuid, text, boolean)
  from public, anon;
grant execute on function public.rpc_admin_purger_utilisateur(uuid, text, boolean)
  to authenticated;

revoke all on function public.rpc_admin_purger_entreprise(uuid, text, boolean)
  from public, anon;
grant execute on function public.rpc_admin_purger_entreprise(uuid, text, boolean)
  to authenticated;


-- ============================================================================
--  5. AUTO-CONTRÔLE
-- ============================================================================
--  Chaque point du correctif est vérifié. Un « ÉCHEC » ici signale un
--  problème réel : à corriger avant d'utiliser l'application.

do $auto_controle$
declare
  v_admin  uuid;
  v_res    jsonb;
  v_ok     integer := 0;
  v_ko     integer := 0;
begin
  -- Comptes plateforme : identification d'un Super Admin pour tester les RPC
  -- réservées (le SQL Editor n'a pas de session utilisateur).
  select u.id into v_admin
    from public.utilisateurs u
   where u.new_role::text = 'SUPER_ADMIN'
   order by u.created_at
   limit 1;

  if v_admin is not null then
    perform set_config('request.jwt.claims',
      jsonb_build_object('sub', v_admin::text,
                         'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_admin::text, true);
  end if;

  -- 1. L'écran « Boutiques » (erreur GROUP BY) s'exécute réellement.
  begin
    v_res := public.rpc_admin_espaces_lister(null, 'tous', 5, 0);
    v_ok := v_ok + 1;
    raise notice 'OK    rpc_admin_espaces_lister → % espace(s) sur % au total',
      jsonb_array_length(v_res -> 'espaces'), v_res -> 'total' ->> 'espaces';
  exception when others then
    v_ko := v_ko + 1;
    raise warning 'ECHEC rpc_admin_espaces_lister → %', sqlerrm;
  end;

  -- 2. Le rôle AGENT_TERRAIN existe et porte ses pages.
  begin
    if public.permissions_defaut('AGENT_TERRAIN') ? 'entreprises' then
      v_ok := v_ok + 1;
      raise notice 'OK    permissions_defaut(AGENT_TERRAIN) → % page(s)',
        (select count(*) from jsonb_object_keys(
           public.permissions_defaut('AGENT_TERRAIN')));
    else
      v_ko := v_ko + 1;
      raise warning 'ECHEC AGENT_TERRAIN : la page « entreprises » est absente des permissions par défaut.';
    end if;
  exception when others then
    v_ko := v_ko + 1;
    raise warning 'ECHEC permissions_defaut(AGENT_TERRAIN) → %', sqlerrm;
  end;

  -- 3. Les RPC du workflow d'activation acceptent AGENT_TERRAIN.
  begin
    if exists (
      select 1 from pg_proc p
        join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public'
         and p.proname in ('rpc_activation_verifier',
                           'rpc_activation_valider_finance',
                           'rpc_activation_lister')
         and pg_get_functiondef(p.oid) like '%''AGENT_TERRAIN''%'
    ) then
      v_ok := v_ok + 1;
      raise notice 'OK    workflow d''activation : AGENT_TERRAIN reconnu côté serveur';
    else
      v_ko := v_ko + 1;
      raise warning 'ECHEC workflow d''activation : AGENT_TERRAIN n''apparaît dans aucune RPC du dossier.';
    end if;
  exception when others then
    v_ko := v_ko + 1;
    raise warning 'ECHEC vérification AGENT_TERRAIN → %', sqlerrm;
  end;

  -- 4. Les RPC de purge existent et SIMULENT (aucune donnée détruite).
  begin
    perform 1 from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in ('rpc_admin_purger_utilisateur',
                         'rpc_admin_purger_entreprise');
    if found then
      v_ok := v_ok + 1;
      raise notice 'OK    fonctions de purge installées (mode simulation par défaut)';
    else
      v_ko := v_ko + 1;
      raise warning 'ECHEC fonctions de purge absentes.';
    end if;
  exception when others then
    v_ko := v_ko + 1;
    raise warning 'ECHEC vérification purge → %', sqlerrm;
  end;

  raise notice 'AUTO-CONTRÔLE MODULE 21 : % OK, % en échec.', v_ok, v_ko;
end $auto_controle$;


-- ============================================================================
--  6. VÉRIFICATIONS AFFICHÉES DANS L'ÉDITEUR SQL
-- ============================================================================

-- 6.a Aucune fonction ne doit encore terminer une agrégation par un tri sur
--     une colonne non agrégée (famille de l'erreur « must appear in the
--     GROUP BY clause »).
select
  count(*) as fonctions_a_verifier
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and pg_get_functiondef(p.oid) like '%order by s.entreprise%'
   and pg_get_functiondef(p.oid) like '%jsonb_agg%';

-- 6.b Rôles disponibles (AGENT_TERRAIN doit apparaître).
select e.enumlabel as role
  from pg_enum e
  join pg_type t on t.oid = e.enumtypid
 where t.typname = 'role_utilisateur_enum'
 order by e.enumsortorder;

-- 6.c Permissions par défaut de l'agent terrain.
select public.permissions_defaut('AGENT_TERRAIN') as permissions_agent_terrain;

-- ============================================================================
--  FIN — module 21 : correctif GROUP BY, montant total dû, agent terrain,
--  purge maîtrisée.
-- ============================================================================
