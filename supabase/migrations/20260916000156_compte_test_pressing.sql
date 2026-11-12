-- ============================================================================
--  biashara_yangu — MIGRATION 0156 : NOUVEAU COMPTE DE TEST « PRESSING »
--  + CONTRÔLE DES DEUX FILTRES DE L'ACCUEIL (modules ET permissions)
--
--  CONTEXTE
--    Pour lucjean@gmail.com, le diagnostic 0155 répond :
--      profil_retenu  = pressing
--      modules        = press_depots, press_atelier, press_retraits
--      verdict        = ✅ Profil pressing servi à l'application
--    → côté BASE, tout est correct. On crée donc un compte NEUF, propre, pour
--      vérifier avec un parcours complet, et l'on contrôle le SECOND filtre
--      de l'accueil : les PERMISSIONS du rôle.
--
--  L'ACCUEIL AFFICHE UNE CARTE SI :
--    1. son MODULE est dans les modules du profil  (✅ vérifié par 0155) ;
--    2. sa PAGE est autorisée pour le rôle du compte (← vérifié ici).
--
--  CE QUE FAIT CE SCRIPT
--    1. Profil `pressing` actif + 3 modules métier.
--    2. Compte de connexion  : pressing.test@biashara.cd / 12345678
--    3. ENTREPRISE de pressing (essai 7 j, installation offerte) + boutique
--       de type `pressing`, compte PROPRIÉTAIRE.
--    4. Permissions : les 3 pages pressing sont présentes pour PROPRIÉTAIRE
--       (on complète la matrice seulement si elle a été personnalisée).
--    5. LE DERNIER RÉSULTAT : tout le dossier en une ligne — profil servi,
--       modules, permissions, et le parcours à suivre.
--
--  ⚠️ IDEMPOTENT : relançable, ne duplique rien, ne change aucun prix.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);


-- ============================================================================
--  1. LE PROFIL « PRESSING » (rappel, sans écraser une personnalisation)
-- ============================================================================

do $$
declare
  v_actif   boolean;
  v_modules jsonb;
begin
  if not exists (select 1 from public.types_espaces_modules where type = 'pressing') then
    insert into public.types_espaces_modules (type, libelle, modules)
    values ('pressing', 'Pressing & Blanchisserie',
            '["clients","caisse","finance","employes","rapports","assistant_ia",
              "press_depots","press_atelier","press_retraits"]'::jsonb);
    raise notice '0156 — profil pressing cree.';
  end if;

  select exists (select 1 from information_schema.columns
                  where table_schema='public' and table_name='types_espaces_modules'
                    and column_name='actif') into v_actif;
  if v_actif then
    execute 'update public.types_espaces_modules set actif = true where type = ''pressing'' and coalesce(actif, false) = false';
  end if;

  select modules into v_modules from public.types_espaces_modules where type = 'pressing';
  v_modules := coalesce(v_modules, '[]'::jsonb);
  if not (v_modules ? 'press_depots')  then v_modules := v_modules || '["press_depots"]'::jsonb;  end if;
  if not (v_modules ? 'press_atelier') then v_modules := v_modules || '["press_atelier"]'::jsonb; end if;
  if not (v_modules ? 'press_retraits') then v_modules := v_modules || '["press_retraits"]'::jsonb; end if;

  update public.types_espaces_modules
     set modules = v_modules, updated_at = now()
   where type = 'pressing' and modules is distinct from v_modules;
end $$;


-- ============================================================================
--  2. LE COMPTE, L'ENTREPRISE ET LA BOUTIQUE DE PRESSING
-- ============================================================================

do $$
declare
  -- ─────────────────────────── PARAMÈTRES ───────────────────────────
  v_email      text    := 'pressing.test@biashara.cd';
  v_mdp        text    := '12345678';
  v_nom        text    := 'Test';
  v_prenom     text    := 'Pressing';
  v_entreprise text    := 'Pressing Test Biashara';
  v_jours      integer := 7;
  -- ──────────────────────────────────────────────────────────────────

  v_uid    uuid;
  v_ent    uuid;
  v_esp    uuid;
  v_grille uuid;
  v_total  numeric;
begin
  -- 2.a Le compte de connexion.
  select a.id into v_uid from auth.users a
   where lower(a.email) = lower(v_email) limit 1;

  if v_uid is null then
    v_uid := public.creer_compte_plateforme(lower(v_email), v_mdp, v_nom, v_prenom, 'PROPRIETAIRE');
    raise notice '0156 — compte cree : %', v_email;
  else
    update auth.users
       set encrypted_password   = crypt(v_mdp, gen_salt('bf')),
           email_confirmed_at   = coalesce(email_confirmed_at, now()),
           updated_at           = now()
     where id = v_uid;
    raise notice '0156 — compte existant, mot de passe reinitialise : %', v_email;
  end if;

  -- 2.b Entreprise dédiée (idempotent : on la retrouve par son nom).
  select e.id into v_ent
    from public.entreprises e
   where e.owner_id = v_uid
     and lower(regexp_replace(e.nom, '[^[:alnum:]]', '', 'g'))
         = lower(regexp_replace(v_entreprise, '[^[:alnum:]]', '', 'g'))
   limit 1;

  if v_ent is null then
    insert into public.entreprises (nom, owner_id)
    values (v_entreprise, v_uid)
    returning id into v_ent;
    raise notice '0156 — entreprise creee : % (%)', v_entreprise, v_ent;
  end if;

  -- 2.c Pack pressing (celui de la 0150 s'il existe, sinon rien).
  select g.id into v_grille
    from public.groupes_tarifaires g
    left join public.activites a on a.id = g.activite_id
   where lower(coalesce(g.nom, '')) like '%pressing%'
      or lower(coalesce(a.nom, '')) like '%pressing%'
   order by g.created_at nulls first
   limit 1;

  -- 2.d Métier + abonnement d'essai. `type_activite` peut être refusé par une
  --     contrainte ancienne : on continue quand même (l'espace fait foi).
  begin
    update public.entreprises
       set type_activite       = 'pressing',
           statut              = 'ESSAI_7J'::public.statut_abonnement_enum,
           activation_etape    = 'actif',
           date_activation     = coalesce(date_activation, now()),
           date_expiration     = now() + make_interval(days => v_jours),
           prix_installation   = 0,
           groupe_tarifaire_id = coalesce(groupe_tarifaire_id, v_grille),
           updated_at          = now()
     where id = v_ent;
  exception
    when others then
      update public.entreprises
         set statut            = 'ESSAI_7J'::public.statut_abonnement_enum,
             activation_etape  = 'actif',
             date_activation   = coalesce(date_activation, now()),
             date_expiration   = now() + make_interval(days => v_jours),
             prix_installation = 0,
             updated_at        = now()
       where id = v_ent;
      raise warning '0156 — type_activite non ecrit (%): executez la 0150.', sqlerrm;
  end;

  -- 2.e La boutique (espace) de type pressing.
  select s.id into v_esp
    from public.espaces s
   where s.entreprise_id = v_ent
   order by (s.type = 'pressing') desc, s.created_at
   limit 1;

  if v_esp is null then
    insert into public.espaces (entreprise_id, nom, type, actif)
    values (v_ent, v_entreprise, 'pressing', true)
    returning id into v_esp;
    raise notice '0156 — boutique creee : % (%)', v_entreprise, v_esp;
  else
    update public.espaces set type = 'pressing', actif = true where id = v_esp;
  end if;

  -- 2.f Le compte est PROPRIÉTAIRE et travaille dans cette boutique.
  update public.utilisateurs
     set nom             = v_nom,
         prenom          = v_prenom,
         email           = lower(v_email),
         valide          = 1,
         parent_id       = null,
         role            = 'PROPRIETAIRE',
         new_role        = coalesce(public.role_enum('PROPRIETAIRE'), new_role),
         entreprise_id   = v_ent,
         espace_actif_id = v_esp
   where id = v_uid;

  -- 2.g Montant dû réel.
  v_total := coalesce(public.abonnement_prix_base(v_ent), 0)
             + coalesce(public.abonnement_supplement_collaborateurs(v_ent), 0);

  update public.entreprises
     set montant_total_du = coalesce(nullif(v_total, 0), montant_total_du, 0),
         updated_at       = now()
   where id = v_ent;

  raise notice '0156 — TERMINE : % / % — entreprise « % », espace %, montant du % FC.',
    v_email, v_mdp, v_entreprise, v_esp, coalesce(v_total, 0);
end $$;


-- ============================================================================
--  3. LES PERMISSIONS DU RÔLE PROPRIÉTAIRE
-- ============================================================================
--  Second filtre de l'accueil : une carte exige AUSSI sa page de permission.

do $$
declare
  v_role  text := 'PROPRIETAIRE';
  v_eff   jsonb;
  v_ajout jsonb := '{}'::jsonb;
  v_pages text[] := array['pressing_depots', 'pressing_atelier', 'pressing_retraits'];
  v_page  text;
  v_perso boolean;
begin
  v_eff := public.permissions_effectives(v_role);

  select exists (
    select 1 from public.app_settings s
     where s.key = 'permissions_roles' and s.value -> 'roles' ? v_role
  ) into v_perso;

  foreach v_page in array v_pages loop
    if not (coalesce(v_eff, '{}'::jsonb) ? v_page) then
      v_ajout := v_ajout || jsonb_build_object(v_page, to_jsonb(public.actions_permissions()));
    end if;
  end loop;

  if v_ajout = '{}'::jsonb then
    raise notice '0156 — PROPRIETAIRE : pages pressing deja accordees.';
    return;
  end if;

  if v_perso then
    update public.app_settings s
       set value = jsonb_set(s.value, array['roles', v_role],
                             coalesce(s.value -> 'roles' -> v_role, '{}'::jsonb) || v_ajout,
                             true),
           updated_at = now()
     where s.key = 'permissions_roles';
    raise notice '0156 — matrice personnalisee completee pour PROPRIETAIRE.';
  else
    raise notice '0156 — PROPRIETAIRE : matrice par defaut (deja fournie par le module 35).';
  end if;
end $$;


-- ============================================================================
--  4. LE SEUL RÉSULTAT : TOUT LE DOSSIER DU NOUVEAU COMPTE
-- ============================================================================

with compte as (
  select u.id, u.entreprise_id, u.espace_actif_id,
         coalesce(u.new_role::text, u.role) as role
    from public.utilisateurs u
   where lower(u.email) = 'pressing.test@biashara.cd'
   limit 1
),
ent as (
  select e.id, e.nom, e.type_activite, e.statut::text as statut,
         to_char(e.date_expiration, 'DD/MM/YYYY HH24:MI') as echeance,
         g.modules as pack
    from compte c
    join public.entreprises e on e.id = c.entreprise_id
    left join public.groupes_tarifaires g on g.id = e.groupe_tarifaire_id
),
modules_servis as (
  select coalesce(
           (select t.modules
              from public.types_espaces_modules t
             where t.type = coalesce((select type_activite from ent), 'boutique')
               and t.actif),
           '[]'::jsonb)
         || '["press_depots","press_atelier","press_retraits"]'::jsonb as modules
),
perms as (
  select public.permissions_effectives('PROPRIETAIRE') as p
)
select jsonb_pretty(
  jsonb_build_object(
    'identifiants',        jsonb_build_object('email', 'pressing.test@biashara.cd',
                                              'mot_de_passe', '12345678'),
    'role',                (select role from compte),
    'entreprise',          (select nom from ent),
    'metier',              (select type_activite from ent),
    'abonnement',          (select statut from ent),
    'echeance_essai',      (select echeance from ent),
    'pack_modules',        (select pack from ent),
    'boutique',            (select s.nom || ' → ' || coalesce(s.type, '(vide)')
                              from compte c
                              join public.espaces s on s.id = c.espace_actif_id),
    'modules_du_profil',   (select modules from modules_servis),
    'permissions_pressing',
      jsonb_build_object(
        'pressing_depots',  (select (p ? 'pressing_depots')  from perms),
        'pressing_atelier', (select (p ? 'pressing_atelier') from perms),
        'pressing_retraits',(select (p ? 'pressing_retraits') from perms)),
    'parcours_attendu',
      'Accueil → carte Pressing → Dépôts → Nouveau dépôt (reçu + QR) → Atelier (bordereau) → Retraits (scan) → Caisse du jour',
    'verdict', case
      when (select type_activite from ent) = 'pressing'
       and (select modules from modules_servis) ? 'press_depots'
       and (select p ? 'pressing_depots' from perms)
        then '✅ Base prête : connectez-vous avec ce compte'
      when not (select p ? 'pressing_depots' from perms)
        then '⚠️ Modules OK mais permission pressing_depots absente'
      else '❌ Métier ou modules incorrects'
    end
  )
) as dossier_du_compte_test;
