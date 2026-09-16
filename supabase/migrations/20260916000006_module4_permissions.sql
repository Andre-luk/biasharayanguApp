-- ============================================================================
--  biashara_yangu — MODULE 4 : SYSTÈME DE PERMISSIONS (RÔLES & ACCÈS)
--
--  Script idempotent : peut être exécuté plusieurs fois sans effet de bord.
--
--  OÙ L'EXÉCUTER
--    Supabase Dashboard → SQL Editor → New query → coller → Run
--
--  PRÉ-REQUIS (dans cet ordre)
--    1. Modules 1, 2 et 3 déjà exécutés.
--    2. `20260916000004_module4_analyse_utilisateurs.sql` exécuté (lecture).
--    3. `20260916000005_module4_permissions_enum.sql` exécuté DANS UNE AUTRE
--       REQUÊTE : il ajoute FINANCE_LAPERLE et PROPRIETAIRE au type
--       `role_utilisateur_enum`.
--
--  CE QUE FAIT CE SCRIPT
--     1. Outils de rôle (conversion des rôles hérités)
--     2. Colonne `new_role` remplie pour les comptes existants + index
--     3. `app_settings` : structure, RLS et policies
--     4. Matrice des permissions EN SQL (identique à `PermissionService`)
--     5. RPC de gestion des permissions (Super Admin)
--     6. Policies alignées sur la matrice (entreprises, paiements, audit)
--     7. Gardes des RPC des Modules 1 & 3 réécrites en permissions
--     8. Règle absolue : un VENDEUR ne modifie JAMAIS un prix
--     9. Journalisation des changements de rôle et de permissions
--    10. Droits d'exécution + vérifications finales
--
--  LES HUIT RÔLES
--    SUPER_ADMIN           Expert / Super Administrateur (tout)
--    GESTIONNAIRE_COMPTES  Gestionnaire des comptes (comptes, référentiels)
--    FINANCE_LAPERLE       Finance plateforme (abonnements, paiements)
--    SUPPORT               Assistance (lecture, tickets)
--    PROPRIETAIRE          Entreprise / Propriétaire (tout son espace)
--    VENDEUR               Caissier (vente uniquement)
--    MAGASINIER            Stock (mouvements, inventaire)
--    COMPTABLE_ENTREPRISE  Comptabilité (dépenses, rapports)
--
--  CONTRAINTES RESPECTÉES
--    - Un utilisateur n'a qu'UN rôle : une seule colonne `new_role`.
--    - Le blocage par abonnement (Module 3) passe AVANT les permissions.
--    - Un VENDEUR ne peut jamais modifier un prix (trigger serveur).
-- ============================================================================


-- ============================================================================
--  1. OUTILS DE RÔLE
-- ============================================================================
--  `role_enum` écrit un rôle dans la colonne `new_role` SANS passer par un
--  littéral typé (`'X'::role_utilisateur_enum`) : c'est ce qui rend ce script
--  exécutable même juste après l'ajout des valeurs d'enum, dans la même
--  transaction. Renvoie NULL si le code n'existe pas (aucune écriture).

create or replace function public.role_enum(p_code text)
returns public.role_utilisateur_enum
language sql
stable
as $$
  select v.valeur
    from unnest(enum_range(null::public.role_utilisateur_enum)) as v(valeur)
   where v.valeur::text = upper(btrim(coalesce(p_code, '')))
   limit 1;
$$;

comment on function public.role_enum(text) is
  'Convertit un code texte en role_utilisateur_enum sans littéral typé (NULL si absent).';

-- Conversion des rôles hérités de l'application d''origine.
--   admin        → SUPER_ADMIN  (compte d''administration de la plateforme)
--   vendor       → PROPRIETAIRE (le « patron » d''une boutique)
--   collaborator → VENDEUR      (le personnel de la boutique)
--   valeur vide  → PROPRIETAIRE (comportement historique : défaut `vendor`)
--   inconnue     → la valeur reste NULL : l''application n''accordera rien.

create or replace function public.role_herite(p_ancien_role text)
returns text
language sql
immutable
as $$
  select case upper(btrim(coalesce(p_ancien_role, '')))
           when ''             then 'PROPRIETAIRE'
           when 'ADMIN'        then 'SUPER_ADMIN'
           when 'EXPERT'       then 'SUPER_ADMIN'
           when 'VENDOR'       then 'PROPRIETAIRE'
           when 'PATRON'       then 'PROPRIETAIRE'
           when 'OWNER'        then 'PROPRIETAIRE'
           when 'ENTREPRISE'   then 'PROPRIETAIRE'
           when 'COLLABORATOR' then 'VENDEUR'
           when 'COLLABORATEUR' then 'VENDEUR'
           when 'CAISSIER'     then 'VENDEUR'
           when 'COMPTABLE'    then 'COMPTABLE_ENTREPRISE'
           when 'GESTIONNAIRE' then 'GESTIONNAIRE_COMPTES'
           when 'ASSISTANCE'   then 'SUPPORT'
           when 'FINANCE'      then 'FINANCE_LAPERLE'
           else upper(btrim(p_ancien_role))
         end;
$$;

comment on function public.role_herite(text) is
  'Convertit un ancien rôle texte (admin/vendor/collaborator) en code du Module 4.';

-- ⚠️ Les fonctions `mon_role()` et `est_*()` sont définies en section 2 ter :
--    elles lisent `utilisateurs.new_role`, colonne dont l'existence est
--    garantie juste avant (PostgreSQL valide le corps des fonctions SQL à la
--    création — l'ordre est donc important).


-- ============================================================================
--  2. COLONNE `new_role` : CONTRÔLE ET REMPLISSAGE DES COMPTES EXISTANTS
-- ============================================================================

do $$
begin
  if not exists (
    select 1 from information_schema.columns
     where table_schema = 'public'
       and table_name = 'utilisateurs'
       and column_name = 'new_role'
  ) then
    execute 'alter table public.utilisateurs add column new_role public.role_utilisateur_enum';
    raise notice 'Colonne public.utilisateurs.new_role ajoutée.';
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from information_schema.columns
     where table_schema = 'public'
       and table_name = 'utilisateurs'
       and column_name = 'entreprise_id'
  ) then
    execute 'alter table public.utilisateurs add column entreprise_id uuid';
    raise notice 'Colonne public.utilisateurs.entreprise_id ajoutée.';
  end if;
  -- L'ancienne application écrivait `role` (texte) : on garantit sa présence
  -- pour ne jamais casser la lecture de repli.
  if not exists (
    select 1 from information_schema.columns
     where table_schema = 'public'
       and table_name = 'utilisateurs'
       and column_name = 'role'
  ) then
    execute 'alter table public.utilisateurs add column role text';
  end if;
end $$;

-- Rattrapage : un seul rôle par utilisateur, jamais écrasé s''il est déjà posé.
update public.utilisateurs u
   set new_role = public.role_enum(public.role_herite(u.role))
 where u.new_role is null
   and public.role_enum(public.role_herite(u.role)) is not null;

create index if not exists idx_utilisateurs_new_role
  on public.utilisateurs (new_role);
create index if not exists idx_utilisateurs_entreprise
  on public.utilisateurs (entreprise_id);


-- ============================================================================
--  2 ter. OUTILS DE RÔLE EFFECTIF (APRÈS la garantie des colonnes)
-- ============================================================================
--  Ces fonctions lisent `utilisateurs.new_role` : elles ne peuvent être créées
--  qu'une fois la colonne assurée (section 2 ci-dessus).

-- Rôle effectif de l'utilisateur connecté : `new_role` s'il est renseigné,
-- sinon conversion du rôle hérité, sinon 'INCONNU' (aucun droit).
create or replace function public.mon_role()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    nullif(upper(btrim(coalesce(u.new_role::text, ''))), ''),
    public.role_herite(u.role),
    'INCONNU'
  )
  from public.utilisateurs u
  where u.id = auth.uid();
$$;

comment on function public.mon_role() is
  'Rôle effectif de l''utilisateur connecté (new_role, sinon conversion du rôle hérité).';

-- Même calcul pour un utilisateur donné (diagnostic, administration).
create or replace function public.mon_role(p_user_id uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    nullif(upper(btrim(coalesce(u.new_role::text, ''))), ''),
    public.role_herite(u.role),
    'INCONNU'
  )
  from public.utilisateurs u
  where u.id = p_user_id;
$$;

comment on function public.mon_role(uuid) is
  'Rôle effectif d''un utilisateur donné.';

-- Raccourcis d'administration (définis AVANT les policies qui les utilisent).
create or replace function public.est_super_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public.mon_role() = 'SUPER_ADMIN', false);
$$;

create or replace function public.est_plateforme()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    public.mon_role() in ('SUPER_ADMIN', 'GESTIONNAIRE_COMPTES',
                          'FINANCE_LAPERLE', 'SUPPORT'),
    false
  );
$$;

comment on function public.est_plateforme() is
  'Vrai pour les quatre rôles qui administrent la plateforme La Perle.';


-- ============================================================================
--  3. `app_settings` : STOCKAGE DES PERMISSIONS PERSONNALISÉES
-- ============================================================================
--  Structure attendue : key (text, unique), value (jsonb), updated_at.
--  Document stocké sous la clé 'permissions_roles' :
--
--    { "roles": { "VENDEUR": { "ventes": ["voir","creer"], ... } } }
--
--  Un rôle absent du document utilise la matrice par défaut ; un rôle présent
--  REMPLACE entièrement ses droits par défaut (c'est ce qui permet de
--  retirer une permission, et pas seulement d'en ajouter).

do $$
begin
  if not exists (
    select 1 from information_schema.tables
     where table_schema = 'public' and table_name = 'app_settings'
  ) then
    execute $ddl$
      create table public.app_settings (
        key        text primary key,
        value      jsonb not null default '{}'::jsonb,
        updated_at timestamptz not null default now()
      )
    $ddl$;
    raise notice 'Table public.app_settings créée.';
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'app_settings'
       and column_name = 'updated_at'
  ) then
    execute 'alter table public.app_settings add column updated_at timestamptz not null default now()';
  end if;
  if not exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'app_settings'
       and column_name = 'value'
  ) then
    execute 'alter table public.app_settings add column value jsonb not null default ''{}''::jsonb';
  end if;
end $$;

alter table public.app_settings enable row level security;

-- Lecture ouverte aux utilisateurs connectés : l'application charge la matrice
-- au démarrage, pour tous les rôles.
drop policy if exists "app_settings_lecture_connectes" on public.app_settings;
create policy "app_settings_lecture_connectes" on public.app_settings
  for select to authenticated using (true);

-- Écriture directe réservée au SUPER_ADMIN (les RPC `rpc_permissions_*`
-- écrivent en `security definer`, donc même un déploiement intermédiaire
-- reste fonctionnel).
drop policy if exists "app_settings_ecriture_super_admin" on public.app_settings;
create policy "app_settings_ecriture_super_admin" on public.app_settings
  for all to authenticated
  using (public.est_super_admin())
  with check (public.est_super_admin());


-- ============================================================================
--  4. MATRICE DES PERMISSIONS EN SQL
-- ============================================================================
--  Copie fidèle de `lib/services/permission_service.dart` : les mêmes codes de
--  pages et d'actions. Toute évolution doit être faite DES DEUX CÔTÉS.

create or replace function public.pages_permissions()
returns text[]
language sql
immutable
as $$
  select array[
    'dashboard', 'entreprises', 'utilisateurs', 'villes', 'activites',
    'groupes_tarifaires', 'abonnements', 'paiements', 'finance', 'audit',
    'notifications', 'assistance', 'parametres', 'ventes', 'caisse',
    'scanner', 'panier', 'articles', 'stock', 'clients', 'fournisseurs',
    'depenses', 'collaborateurs', 'qr_codes', 'rapports'
  ];
$$;

create or replace function public.actions_permissions()
returns text[]
language sql
immutable
as $$
  select array['voir', 'creer', 'modifier', 'supprimer', 'valider'];
$$;

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

    -- Propriétaire : tout son espace entreprise.
    when 'PROPRIETAIRE' then
      v_pages   := array['dashboard', 'ventes', 'caisse', 'scanner', 'panier',
                         'articles', 'qr_codes', 'stock', 'clients', 'fournisseurs',
                         'finance', 'depenses', 'collaborateurs', 'rapports',
                         'abonnements', 'parametres'];
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
  'Matrice des permissions par défaut d''un rôle (Module 4).';

-- Droits effectifs : la personnalisation REMPLACE la matrice par défaut.
create or replace function public.permissions_effectives(p_role text)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (
      select s.value -> 'roles' -> upper(btrim(coalesce(p_role, '')))
        from public.app_settings s
       where s.key = 'permissions_roles'
    ),
    public.permissions_defaut(p_role)
  );
$$;

comment on function public.permissions_effectives(text) is
  'Permissions réellement appliquées à un rôle : personnalisation ou matrice par défaut.';

-- Vérification d'un droit : `select public.a_permission('VENDEUR','ventes','creer')`.
create or replace function public.a_permission(
  p_role   text,
  p_page   text,
  p_action text
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    public.permissions_effectives(p_role)
      -> lower(btrim(coalesce(p_page, '')))
      ? lower(btrim(coalesce(p_action, ''))),
    false
  );
$$;

comment on function public.a_permission(text, text, text) is
  'Vrai si le rôle possède l''action demandée sur la page demandée.';

-- Vérification pour la session courante.
create or replace function public.peut(p_page text, p_action text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.a_permission(public.mon_role(), p_page, p_action);
$$;


-- ============================================================================
--  5. RPC DE GESTION DES PERMISSIONS (ÉCRAN SUPER ADMIN)
-- ============================================================================

-- Renvoie l'état complet : matrice par défaut, personnalisation et effectif.
create or replace function public.rpc_permissions_get()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    jsonb_object_agg(
      role_code,
      jsonb_build_object(
        'defaut',        public.permissions_defaut(role_code),
        'effectif',      public.permissions_effectives(role_code),
        'personnalise',  (select s.value -> 'roles' ? role_code
                            from public.app_settings s
                           where s.key = 'permissions_roles')
      )
    ),
    '{}'::jsonb
  )
  from unnest(array['SUPER_ADMIN', 'GESTIONNAIRE_COMPTES', 'FINANCE_LAPERLE',
                    'SUPPORT', 'PROPRIETAIRE', 'VENDEUR', 'MAGASINIER',
                    'COMPTABLE_ENTREPRISE']) as role_code;
$$;

grant execute on function public.rpc_permissions_get() to authenticated;

-- Enregistre les permissions d''un rôle. Réservé au SUPER_ADMIN.
-- `p_permissions` : objet plat { "ventes": ["voir","creer"], ... }.
create or replace function public.rpc_permissions_set(
  p_role        text,
  p_permissions jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role    text := upper(btrim(coalesce(p_role, '')));
  v_nettoye jsonb := '{}'::jsonb;
begin
  if not public.est_super_admin() then
    raise exception 'ACCES_REFUSE';
  end if;

  if v_role = '' or public.role_enum(v_role) is null then
    raise exception 'ROLE_INCONNU';
  end if;

  if p_permissions is null or jsonb_typeof(p_permissions) <> 'object' then
    raise exception 'PERMISSIONS_INVALIDE';
  end if;

  -- Normalisation : seules les pages et actions connues sont conservées, en
  -- minuscules, sans doublon, et les pages sans aucune action valide sont
  -- retirées (une page vide = page interdite).
  with brut as (
    select lower(t.page) as page,
           (select coalesce(jsonb_agg(distinct lower(a.action) order by lower(a.action)),
                            '[]'::jsonb)
              from jsonb_array_elements_text(
                     case when jsonb_typeof(t.valeur) = 'array'
                          then t.valeur else '[]'::jsonb end
                   ) as a(action)
             where lower(a.action) = any (public.actions_permissions())) as actions
      from jsonb_each(coalesce(p_permissions, '{}'::jsonb)) as t(page, valeur)
     where lower(t.page) = any (public.pages_permissions())
  )
  select coalesce(jsonb_object_agg(page, actions), '{}'::jsonb)
    into v_nettoye
    from brut
   where actions <> '[]'::jsonb;

  insert into public.app_settings (key, value, updated_at)
  values (
    'permissions_roles',
    jsonb_build_object('roles', jsonb_build_object(v_role, v_nettoye)),
    now()
  )
  on conflict (key) do update
     set value = jsonb_set(
                   coalesce(public.app_settings.value, '{}'::jsonb),
                   array['roles', v_role],
                   v_nettoye,
                   true
                 ),
         updated_at = now();

  -- Journalisation best-effort : elle ne doit jamais faire échouer l'écriture.
  begin
    insert into public.journal_audit (id, entreprise_id, action, utilisateur_id, details, created_at)
    values (gen_random_uuid(), null, 'PERMISSIONS_MODIFIEES', auth.uid(),
            jsonb_build_object('role', v_role, 'permissions', v_nettoye), now());
  exception
    when others then null;
  end;

  return v_nettoye;
end;
$$;

comment on function public.rpc_permissions_set(text, jsonb) is
  'Enregistre les permissions personnalisées d''un rôle (SUPER_ADMIN uniquement).';

-- Rétablit la matrice par défaut d''un rôle.
create or replace function public.rpc_permissions_reset(p_role text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text := upper(btrim(coalesce(p_role, '')));
begin
  if not public.est_super_admin() then
    raise exception 'ACCES_REFUSE';
  end if;

  -- `#-` RETIRE la clé du document : le rôle repasse alors sur la matrice par
  -- défaut. (Une valeur `null` ne suffirait pas : `coalesce` ne remplace pas
  -- un JSON null.)
  update public.app_settings
     set value      = coalesce(value, '{}'::jsonb) #- array['roles', v_role],
         updated_at = now()
   where key = 'permissions_roles';

  -- Journalisation best-effort.
  begin
    insert into public.journal_audit (id, entreprise_id, action, utilisateur_id, details, created_at)
    values (gen_random_uuid(), null, 'PERMISSIONS_REINITIALISEES', auth.uid(),
            jsonb_build_object('role', v_role), now());
  exception
    when others then null;
  end;

  return public.permissions_defaut(v_role);
end;
$$;

grant execute on function public.rpc_permissions_set(text, jsonb) to authenticated;
grant execute on function public.rpc_permissions_reset(text) to authenticated;
grant execute on function public.a_permission(text, text, text) to authenticated;
grant execute on function public.peut(text, text) to authenticated;
grant execute on function public.mon_role() to authenticated;
grant execute on function public.est_super_admin() to authenticated;
grant execute on function public.est_plateforme() to authenticated;


-- ============================================================================
--  6. POLICIES ALIGNÉES SUR LA MATRICE
-- ============================================================================
--  La LECTURE reste ouverte aux utilisateurs connectés : l'application
--  (bannière d'abonnement, fiches, jointures) en dépend, et un cloisonnement
--  trop strict casserait des écrans existants. Seules les ÉCRITURES sont
--  désormais gouvernées par les permissions.

drop policy if exists "entreprises_ecriture_admin" on public.entreprises;
drop policy if exists "entreprises_ecriture_permissions" on public.entreprises;
create policy "entreprises_ecriture_permissions" on public.entreprises
  for all to authenticated
  using (
    public.a_permission(public.mon_role(), 'entreprises', 'modifier')
    or public.a_permission(public.mon_role(), 'entreprises', 'creer')
    or public.a_permission(public.mon_role(), 'entreprises', 'supprimer')
  )
  with check (
    public.a_permission(public.mon_role(), 'entreprises', 'modifier')
    or public.a_permission(public.mon_role(), 'entreprises', 'creer')
    or public.a_permission(public.mon_role(), 'entreprises', 'supprimer')
  );

drop policy if exists "paiements_laperle_insertion_admin" on public.paiements_abonnements_laperle;
create policy "paiements_laperle_insertion_permissions" on public.paiements_abonnements_laperle
  for insert to authenticated
  with check (public.a_permission(public.mon_role(), 'paiements', 'creer'));

drop policy if exists "journal_audit_lecture_admin" on public.journal_audit;
create policy "journal_audit_lecture_permissions" on public.journal_audit
  for select to authenticated
  using (public.a_permission(public.mon_role(), 'audit', 'voir'));


-- ============================================================================
--  7. GARDES DES RPC EXISTANTES → PERMISSIONS
-- ============================================================================
--  Les Modules 1 et 3 vérifiaient `utilisateurs.role = 'admin'`. Un
--  GESTIONNAIRE_COMPTES ou un comptable FINANCE_LAPERLE ne pouvait donc rien
--  faire. Les gardes passent aux permissions, sans changer le comportement de
--  l'ancien compte `admin` (converti en SUPER_ADMIN, qui a tout).

-- Module 1 — encaissement simple (met à jour les montants uniquement).
create or replace function public.rpc_enregistrer_paiement(
  p_entreprise_id uuid,
  p_montant       numeric
)
returns public.entreprises
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ligne  public.entreprises;
  v_paye   numeric;
  v_total  numeric;
  v_solde   numeric;
begin
  if not public.a_permission(public.mon_role(), 'paiements', 'creer') then
    raise exception 'ACCES_REFUSE';
  end if;

  if p_montant is null or p_montant <= 0 then
    raise exception 'MONTANT_INVALIDE';
  end if;

  select * into v_ligne
  from public.entreprises
  where id = p_entreprise_id
  for update;

  if not found then
    raise exception 'ENTREPRISE_INTROUVABLE';
  end if;

  v_paye  := coalesce(v_ligne.montant_deja_paye, 0);
  v_total := coalesce(v_ligne.montant_total_du, 0);
  v_solde := coalesce(v_ligne.solde_restant, greatest(v_total - v_paye, 0));

  if p_montant > v_solde + 0.001 then
    raise exception 'MONTANT_SUPERIEUR';
  end if;

  update public.entreprises
     set montant_deja_paye = v_paye + p_montant,
         solde_restant      = greatest(v_solde - p_montant, 0),
         updated_at         = now()
   where id = p_entreprise_id
   returning * into v_ligne;

  return v_ligne;
end;
$$;

-- Module 3 — moteur d'abonnement : encaissement complet.
--  (Corps inchangé ; seule la garde d'entrée a été remplacée.)
create or replace function public.rpc_abonnement_enregistrer_paiement(
  p_entreprise_id uuid,
  p_montant       numeric,
  p_type_paiement text default 'AVANCE',
  p_mode_paiement text default null,
  p_note          text default null
)
returns public.entreprises
language plpgsql
security definer
set search_path = public
as $$
declare
  v_entreprise    public.entreprises;
  v_type          text;
  v_duree         integer := 0;
  v_paye          numeric;
  v_total         numeric;
  v_solde         numeric;
  v_statut_avant  text;
  v_nouveau_paye  numeric;
  v_nouveau_solde numeric;
  v_prolongation  integer := 0;
  v_base          timestamptz;
  v_activer       boolean := false;
begin
  -- Réservé aux rôles qui possèdent « créer » sur les paiements
  -- (SUPER_ADMIN et FINANCE_LAPERLE avec la matrice par défaut).
  if not public.a_permission(public.mon_role(), 'paiements', 'creer') then
    raise exception 'ACCES_REFUSE';
  end if;

  if p_montant is null or p_montant <= 0 then
    raise exception 'MONTANT_INVALIDE';
  end if;

  v_type := upper(btrim(coalesce(p_type_paiement, 'AVANCE')));
  if v_type not in ('AVANCE', 'SOLDE', 'RENOUVELLEMENT') then
    raise exception 'TYPE_PAIEMENT_INVALIDE';
  end if;

  select * into v_entreprise
  from public.entreprises
  where id = p_entreprise_id
  for update;

  if not found then
    raise exception 'ENTREPRISE_INTROUVABLE';
  end if;

  v_statut_avant := v_entreprise.statut::text;

  select coalesce(g.duree_abonnement_jours, 30)
    into v_duree
    from public.groupes_tarifaires g
   where g.id = v_entreprise.groupe_tarifaire_id;
  v_duree := coalesce(v_duree, 30);

  v_paye  := coalesce(v_entreprise.montant_deja_paye, 0);
  v_total := coalesce(v_entreprise.montant_total_du, 0);
  v_solde := coalesce(v_entreprise.solde_restant, greatest(v_total - v_paye, 0));

  if v_solde <= 0 or v_statut_avant in ('EXPIRE', 'EN_ATTENTE_COMPLEMENT') then
    select coalesce(g.montant_abonnement, v_total)
      into v_total
      from public.groupes_tarifaires g
     where g.id = v_entreprise.groupe_tarifaire_id;
    v_total := coalesce(v_total, 0);

    if v_total <= 0 then
      raise exception 'MONTANT_TOTAL_INCONNU';
    end if;

    v_paye  := 0;
    v_solde := v_total;
  end if;

  if p_montant > v_solde + 0.001 then
    raise exception 'MONTANT_SUPERIEUR';
  end if;

  v_nouveau_paye  := v_paye + p_montant;
  v_nouveau_solde := greatest(v_solde - p_montant, 0);

  if v_nouveau_solde <= 0 and v_statut_avant <> 'SUSPENDU' then
    v_activer := true;
    v_prolongation := v_duree;

    if v_statut_avant = 'ACTIF'
       and v_entreprise.date_expiration is not null
       and v_entreprise.date_expiration > now() then
      v_base := v_entreprise.date_expiration;
    else
      v_base := now();
    end if;
  end if;

  update public.entreprises
     set montant_total_du   = v_total,
         montant_deja_paye  = v_nouveau_paye,
         solde_restant      = v_nouveau_solde,
         statut             = case
                                when v_activer then 'ACTIF'::public.statut_abonnement_enum
                                when v_statut_avant = 'EXPIRE'
                                  then 'EN_ATTENTE_COMPLEMENT'::public.statut_abonnement_enum
                                else v_entreprise.statut
                              end,
         date_activation    = case
                                when v_activer
                                  then coalesce(v_entreprise.date_activation, now())
                                else v_entreprise.date_activation
                              end,
         date_expiration    = case
                                when v_activer
                                  then v_base + make_interval(days => v_duree)
                                else v_entreprise.date_expiration
                              end,
         updated_at         = now()
   where id = p_entreprise_id
   returning * into v_entreprise;

  insert into public.paiements_abonnements_laperle (
    id, entreprise_id, montant, type_paiement, mode_paiement,
    note, total_apres, solde_apres, prolongation_jours,
    enregistre_par, created_at
  ) values (
    gen_random_uuid(),
    p_entreprise_id,
    p_montant,
    v_type,
    nullif(btrim(p_mode_paiement), ''),
    nullif(btrim(p_note), ''),
    v_entreprise.montant_deja_paye,
    v_entreprise.solde_restant,
    v_prolongation,
    auth.uid(),
    now()
  );

  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(),
    p_entreprise_id,
    'PAIEMENT_ENREGISTRE',
    auth.uid(),
    jsonb_build_object(
      'montant', p_montant,
      'type_paiement', v_type,
      'mode_paiement', nullif(btrim(p_mode_paiement), ''),
      'statut_avant', v_statut_avant,
      'statut_apres', v_entreprise.statut::text,
      'solde_apres', v_entreprise.solde_restant,
      'prolongation_jours', v_prolongation,
      'role', public.mon_role()
    ),
    now()
  );

  return v_entreprise;
end;
$$;

-- Module 3 — réactivation : exige « valider » sur les paiements.
create or replace function public.rpc_abonnement_reactiver(
  p_entreprise_id uuid
)
returns public.entreprises
language plpgsql
security definer
set search_path = public
as $$
declare
  v_entreprise public.entreprises;
  v_duree      integer := 0;
  v_base       timestamptz;
begin
  if not public.a_permission(public.mon_role(), 'paiements', 'valider') then
    raise exception 'ACCES_REFUSE';
  end if;

  select * into v_entreprise
  from public.entreprises
  where id = p_entreprise_id
  for update;

  if not found then
    raise exception 'ENTREPRISE_INTROUVABLE';
  end if;

  if coalesce(v_entreprise.solde_restant, 0) > 0 then
    raise exception 'SOLDE_RESTANT';
  end if;

  select coalesce(g.duree_abonnement_jours, 30)
    into v_duree
    from public.groupes_tarifaires g
   where g.id = v_entreprise.groupe_tarifaire_id;
  v_duree := coalesce(v_duree, 30);

  v_base := greatest(coalesce(v_entreprise.date_expiration, now()), now());

  update public.entreprises
     set statut          = 'ACTIF'::public.statut_abonnement_enum,
         date_activation = coalesce(date_activation, now()),
         date_expiration = v_base + make_interval(days => v_duree),
         updated_at      = now()
   where id = p_entreprise_id
   returning * into v_entreprise;

  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(),
    p_entreprise_id,
    'REACTIVATION',
    auth.uid(),
    jsonb_build_object(
      'date_expiration', v_entreprise.date_expiration,
      'duree_jours', v_duree,
      'role', public.mon_role()
    ),
    now()
  );

  return v_entreprise;
end;
$$;

-- Vérification globale : ouverte à tout utilisateur connecté (elle ne touche
-- ni aux montants ni aux dates, uniquement les statuts échus).
create or replace function public.rpc_abonnement_verification_globale()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nb integer;
begin
  if auth.uid() is null then
    raise exception 'ACCES_REFUSE';
  end if;

  update public.entreprises
     set statut = case
                    when coalesce(montant_deja_paye, 0) > 0
                         and coalesce(solde_restant, 0) > 0
                      then 'EN_ATTENTE_COMPLEMENT'::public.statut_abonnement_enum
                    else 'EXPIRE'::public.statut_abonnement_enum
                  end,
         updated_at = now()
   where statut in ('ESSAI_7J', 'ACTIF')
     and date_expiration is not null
     and date_expiration < now();

  get diagnostics v_nb = row_count;
  return v_nb;
end;
$$;

create or replace function public.rpc_actualiser_statuts_abonnements()
returns integer
language plpgsql
security definer
set search_path = public
as $$
begin
  return public.rpc_abonnement_verification_globale();
end;
$$;


-- ============================================================================
--  8. RÈGLE ABSOLUE : UN VENDEUR NE MODIFIE JAMAIS UN PRIX
-- ============================================================================
--  Le contrôle est fait côté serveur : même un appel direct à l'API (hors
--  application) est refusé. Le trigger compare les deux colonnes de prix via
--  `to_jsonb`, ce qui évite de dépendre de la structure exacte de la table.
--
--  Ne s'applique QUE si la table `produits` existe. Le propriétaire, le
--  magasinier et la plateforme ne sont pas concernés.

create or replace function public.empecher_modification_prix()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.mon_role() = 'VENDEUR' then
    if (to_jsonb(new) ->> 'prix_vente') is distinct from (to_jsonb(old) ->> 'prix_vente')
       or (to_jsonb(new) ->> 'prix_achat') is distinct from (to_jsonb(old) ->> 'prix_achat')
       or (to_jsonb(new) ->> 'prix') is distinct from (to_jsonb(old) ->> 'prix')
    then
      raise exception 'PRIX_INTERDIT_VENDEUR';
    end if;
  end if;
  return new;
end;
$$;

comment on function public.empecher_modification_prix() is
  'Module 4 : interdit au rôle VENDEUR de modifier un prix (trigger produits).';

do $$
begin
  if exists (
    select 1 from information_schema.tables
     where table_schema = 'public' and table_name = 'produits'
  ) then
    execute 'drop trigger if exists trg_produits_prix_vendeur on public.produits';
    execute 'create trigger trg_produits_prix_vendeur
               before update on public.produits
               for each row execute function public.empecher_modification_prix()';
    raise notice 'Protection des prix active sur public.produits.';
  else
    raise notice 'Table public.produits absente : protection des prix non installée.';
  end if;
end $$;


-- ============================================================================
--  9. JOURNALISATION DES CHANGEMENTS DE RÔLE
-- ============================================================================
--  Toute bascule de `new_role` est tracée dans `journal_audit`, y compris
--  lorsqu'elle est faite depuis le Dashboard Supabase. Le journal est
--  best-effort : il ne fait jamais échouer la mise à jour du rôle.

create or replace function public.journaliser_changement_role()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.new_role is distinct from new.new_role then
    begin
      insert into public.journal_audit (
        id, entreprise_id, action, utilisateur_id, details, created_at
      ) values (
        gen_random_uuid(),
        new.entreprise_id,
        'CHANGEMENT_ROLE',
        auth.uid(),
        jsonb_build_object(
          'utilisateur', new.id,
          'ancien_role', old.new_role::text,
          'nouveau_role', new.new_role::text
        ),
        now()
      );
    exception
      when others then
        null; -- journalisation best-effort
    end;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_utilisateurs_audit_role on public.utilisateurs;
create trigger trg_utilisateurs_audit_role
  after update on public.utilisateurs
  for each row
  execute function public.journaliser_changement_role();


-- ============================================================================
--  10. DROITS D'EXÉCUTION
-- ============================================================================

grant execute on function public.role_enum(text) to authenticated;
grant execute on function public.role_herite(text) to authenticated;
grant execute on function public.pages_permissions() to authenticated;
grant execute on function public.actions_permissions() to authenticated;
grant execute on function public.permissions_defaut(text) to authenticated;
grant execute on function public.permissions_effectives(text) to authenticated;

revoke execute on function public.rpc_permissions_get() from anon, public;
revoke execute on function public.rpc_permissions_set(text, jsonb) from anon, public;
revoke execute on function public.rpc_permissions_reset(text) from anon, public;
revoke execute on function public.mon_role() from anon;
revoke execute on function public.mon_role(uuid) from anon;
revoke execute on function public.est_super_admin() from anon;
revoke execute on function public.est_plateforme() from anon;
revoke execute on function public.a_permission(text, text, text) from anon;
revoke execute on function public.peut(text, text) from anon;


-- ============================================================================
--  11. VÉRIFICATIONS
-- ============================================================================

-- 11.1 Répartition des rôles après rattrapage.
select
  coalesce(new_role::text, '(non converti)') as role,
  count(*)                                   as nb_utilisateurs
from public.utilisateurs
group by 1
order by 2 desc;

-- 11.2 Comptes de plateforme (aucune entreprise, aucun parent).
select id, email, coalesce(new_role::text, '(non converti)') as role
from public.utilisateurs
where entreprise_id is null and parent_id is null
order by role;

-- 11.3 La matrice SQL est-elle complète pour les huit rôles ?
select
  role,
  jsonb_object_keys(public.permissions_defaut(role)) as page
from unnest(array['SUPER_ADMIN', 'GESTIONNAIRE_COMPTES', 'FINANCE_LAPERLE',
                  'SUPPORT', 'PROPRIETAIRE', 'VENDEUR', 'MAGASINIER',
                  'COMPTABLE_ENTREPRISE']) as role
limit 200;

-- 11.4 Contrôles de la règle « le vendeur ne modifie jamais un prix ».
select
  public.a_permission('VENDEUR', 'articles', 'modifier')   as vendeur_modifie_article,   -- false
  public.a_permission('VENDEUR', 'ventes', 'creer')        as vendeur_vend,              -- true
  public.a_permission('MAGASINIER', 'stock', 'creer')      as magasinier_stock,          -- true
  public.a_permission('COMPTABLE_ENTREPRISE', 'finance', 'voir') as comptable_finance,   -- true
  public.a_permission('GESTIONNAIRE_COMPTES', 'paiements', 'creer') as gestionnaire_paie, -- false
  public.a_permission('FINANCE_LAPERLE', 'paiements', 'creer')      as finance_paie,      -- true
  public.a_permission('SUPPORT', 'assistance', 'modifier')          as support_assistance,-- true
  public.a_permission('SUPPORT', 'entreprises', 'modifier')         as support_ecrit_entreprise; -- false

-- 11.5 Permissions personnalisées déjà enregistrées.
select key, value, updated_at from public.app_settings where key = 'permissions_roles';

-- 11.6 Fonctions du Module 4 présentes.
select proname
from pg_proc
where pronamespace = 'public'::regnamespace
  and proname in ('role_enum', 'role_herite', 'permissions_defaut',
                  'permissions_effectives', 'a_permission', 'mon_role', 'peut',
                  'est_super_admin', 'est_plateforme',
                  'rpc_permissions_get', 'rpc_permissions_set',
                  'rpc_permissions_reset', 'empecher_modification_prix')
order by proname;
