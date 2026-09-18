-- ============================================================================
--  biashara_yangu — MODULE 16 : TYPES D'ACTIVITÉS & MODULES  (PHASE A)
--
--  OBJECTIF (roadmap multi-activités, phase A) :
--    « L'activité d'une entreprise détermine les modules affichés. »
--    Un espace de travail (module 15) a un `type` (boutique, hôtel,
--    pharmacie…). Chaque type reçoit ici un PROFIL DE MODULES :
--
--      types_espaces_modules (type → liste de modules)
--
--    L'application charge les modules de l'espace actif au démarrage
--    (`rpc_mes_modules`) et peut alors masquer les écrans qui ne concernent
--    pas l'activité (phase B). L'« Expert Administrateur » (plateforme)
--    gère les types depuis une nouvelle page « Types d'activités ».
--
--  RÈGLE D'OR DE COMPATIBILITÉ (zéro régression) :
--    • profil absent, inactif ou inconnu → profil « boutique » du serveur,
--      sinon liste codée en dur identique aux modules actuels ;
--    • côté application : tant que rien n'est chargé, tout reste VISIBLE.
--
--  PHASE A = SOCLE INVISIBLE : chaque profil conserve TOUS les modules
--  actuels (comportement identique pour tout le monde) et pré-déclare ses
--  modules métier futurs (chambres, commandes… codés en phase C).
--
--  CONTENU :
--    1. table `types_espaces_modules` + RLS + seed des 6 types du module 15 ;
--    2. fonctions `modules_catalogue()` / `modules_base()` ;
--    3. `rpc_mes_modules()`                 — modules de l'espace actif ;
--    4. `rpc_types_espaces_lister()`        — liste admin (nb d'espaces) ;
--    5. `rpc_type_espace_modules_maj()`     — création/modification (Expert) ;
--    6. `rpc_espace_creer()` v2 — accepte les types créés par l'Expert
--       (le CHECK figé de `espaces.type` est remplacé par le référentiel).
--
--  OÙ : Supabase → SQL Editor → coller → Run
--  IDEMPOTENT : peut être relancé sans effet de bord (le seed ne remplace
--  jamais un profil déjà personnalisé par l'Expert).
-- ============================================================================


-- ============================================================================
--  1. TABLE `types_espaces_modules` — LE RÉFÉRENTIEL TYPE → MODULES
-- ============================================================================

create table if not exists public.types_espaces_modules (
  type       text primary key,
  libelle    text not null
    constraint chk_types_espaces_libelle check (length(btrim(libelle)) >= 2),
  modules    jsonb not null default '[]'::jsonb
    constraint chk_types_espaces_modules_array check (jsonb_typeof(modules) = 'array'),
  actif      boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.types_espaces_modules is
  'Module 16 (phase A) — Profil de modules de chaque type d''activité : le type de l''espace de travail (module 15) détermine les modules affichés dans l''application. Le profil « boutique » sert de repli universel.';

-- Index pour les changements de type et les comptages du back-office.
create index if not exists idx_espaces_type
  on public.espaces (type);

alter table public.types_espaces_modules enable row level security;

drop policy if exists m16_types_espaces_lecture on public.types_espaces_modules;
create policy m16_types_espaces_lecture on public.types_espaces_modules
  for select to authenticated
  using (public.est_plateforme());

-- Écritures via les RPC uniquement (security definer) : aucune écriture
-- directe, même pour l'administration.
revoke all on public.types_espaces_modules from public;
revoke all on public.types_espaces_modules from anon;
revoke insert, update, delete, truncate on public.types_espaces_modules from authenticated;
grant select on public.types_espaces_modules to authenticated;


-- ============================================================================
--  2. CATALOGUE DES MODULES (miroir de `ModuleActivite.catalogue` en Dart)
-- ============================================================================
--  Toute évolution doit être faite DES DEUX CÔTÉS (SQL + Flutter) — même
--  règle que la matrice des permissions du module 4.

-- 2.a Tous les modules connus (actuels + phases C à venir).
create or replace function public.modules_catalogue()
returns text[]
language sql
immutable
as $$
  select array[
    -- Modules actuels (déjà codés dans l'application).
    'ventes', 'produits', 'stock', 'qr', 'caisse', 'clients', 'finance',
    'employes', 'rapports', 'assistant_ia',
    -- Modules métier pré-déclarés (codés en phase C de la roadmap).
    'chambres', 'reservations', 'checkin', 'tables', 'commandes', 'cuisine',
    'salles', 'evenements', 'lots_expiration', 'production', 'pesee',
    'variantes'
  ]::text[];
$$;

comment on function public.modules_catalogue() is
  'Module 16 — Catalogue des modules connus (validation des profils). Miroir de ModuleActivite.catalogue (Dart).';

-- 2.b Les modules de base = comportement actuel de l'application
--     (repli universel quand aucun profil n'est applicable).
create or replace function public.modules_base()
returns text[]
language sql
immutable
as $$
  select array[
    'ventes', 'produits', 'stock', 'qr', 'caisse', 'clients', 'finance',
    'employes', 'rapports', 'assistant_ia'
  ]::text[];
$$;

comment on function public.modules_base() is
  'Module 16 — Modules de base (comportement actuel) : repli quand aucun profil n''est applicable. Miroir de ModulesService.modulesBase (Dart).';

revoke all on function public.modules_catalogue() from public;
revoke all on function public.modules_catalogue() from anon;
grant execute on function public.modules_catalogue() to authenticated;

revoke all on function public.modules_base() from public;
revoke all on function public.modules_base() from anon;
grant execute on function public.modules_base() to authenticated;


-- ============================================================================
--  3. SEED — UN PROFIL PAR TYPE DU MODULE 15
-- ============================================================================
--  `on conflict do nothing` : relancer la migration ne remplace JAMAIS un
--  profil personnalisé par l'Expert. Pour forcer un profil : page admin.

insert into public.types_espaces_modules (type, libelle, modules) values
  ('boutique', 'Boutique',
   '["ventes","produits","stock","qr","caisse","clients","finance","employes","rapports","assistant_ia"]'::jsonb),
  ('depot', 'Dépôt / Entrepôt',
   '["ventes","produits","stock","qr","caisse","clients","finance","employes","rapports","assistant_ia"]'::jsonb),
  ('hotel', 'Hôtel',
   '["ventes","produits","stock","qr","caisse","clients","finance","employes","rapports","assistant_ia","chambres","reservations","checkin"]'::jsonb),
  ('pharmacie', 'Pharmacie',
   '["ventes","produits","stock","qr","caisse","clients","finance","employes","rapports","assistant_ia","lots_expiration"]'::jsonb),
  ('restaurant', 'Restaurant',
   '["ventes","produits","stock","qr","caisse","clients","finance","employes","rapports","assistant_ia","tables","commandes","cuisine"]'::jsonb),
  ('autre', 'Autre activité',
   '["ventes","produits","stock","qr","caisse","clients","finance","employes","rapports","assistant_ia"]'::jsonb)
on conflict (type) do nothing;


-- ============================================================================
--  4. `espaces.type` — LE CHECK FIGÉ DEVIENT UN RÉFÉRENTIEL OUVERT
-- ============================================================================
--  Le module 15 limitait `type` aux 6 valeurs connues. L'Expert peut
--  désormais créer de NOUVEAUX types (ex : « Salon de coiffure ») : la
--  contrainte figée est retirée (la validation se fait dans les RPC, avec
--  repli « autre » puis « boutique »).

do $$
declare
  v_con text;
begin
  for v_con in
    select c.conname
      from pg_constraint c
      join pg_class r on r.oid = c.conrelid
      join pg_namespace n on n.oid = r.relnamespace
     where n.nspname = 'public'
       and r.relname = 'espaces'
       and c.contype = 'c'
       and pg_get_constraintdef(c.oid) ilike '%boutique%'
  loop
    execute format('alter table public.espaces drop constraint %I', v_con);
  end loop;
end $$;

comment on column public.espaces.type is
  'Module 15/16 — Type d''activité de l''espace (référentiel `types_espaces_modules`). Types inconnus : repli « autre », puis « boutique ».';


-- ============================================================================
--  5. `rpc_mes_modules()` — LES MODULES DE L'ESPACE ACTIF
-- ============================================================================
--  Appelée par l'application au démarrage, à la connexion et à chaque
--  changement d'entreprise (sélecteur). Renvoie le profil du type de
--  l'espace actif, avec repli universel :
--    profil du type → profil « boutique » → liste de base codée en dur.

create or replace function public.rpc_mes_modules()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_user    uuid := auth.uid();
  v_espace  uuid;
  v_type    text;
  v_libelle text;
  v_modules jsonb;
  v_source  text := 'profil';
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour charger vos modules.';
  end if;

  -- 1. Type de l'espace de travail actif (module 15).
  v_espace := public.mon_proprietaire();

  select s.type into v_type
    from public.espaces s
   where s.id = v_espace;

  -- 2. Repli : première entreprise du compte.
  if v_type is null then
    select s.type into v_type
      from public.utilisateurs u
      join public.espaces s on s.entreprise_id = u.entreprise_id
     where u.id = v_user
     order by s.created_at
     limit 1;
  end if;

  v_type := coalesce(v_type, 'boutique');

  -- 3. Profil du type (actif uniquement).
  select t.libelle, t.modules into v_libelle, v_modules
    from public.types_espaces_modules t
   where t.type = v_type
     and t.actif;

  -- 4. Repli « boutique » (profil du serveur).
  if v_modules is null or jsonb_typeof(v_modules) <> 'array' then
    select t.libelle, t.modules into v_libelle, v_modules
      from public.types_espaces_modules t
     where t.type = 'boutique'
       and t.actif;
    v_source := 'defaut';
  end if;

  -- 5. Repli ultime : liste de base codée en dur (jamais d'échec).
  if v_modules is null or jsonb_typeof(v_modules) <> 'array' then
    v_libelle := 'Boutique';
    v_modules := to_jsonb(public.modules_base());
    v_source  := 'defaut';
  end if;

  return jsonb_build_object(
    'ok',      true,
    'type',    v_type,
    'libelle', v_libelle,
    'modules', v_modules,
    'source',  v_source
  );
end;
$$;

comment on function public.rpc_mes_modules() is
  'Module 16 — Modules du profil de l''espace de travail actif (repli automatique « boutique », jamais d''échec).';

revoke all on function public.rpc_mes_modules() from public;
revoke all on function public.rpc_mes_modules() from anon;
grant execute on function public.rpc_mes_modules() to authenticated;


-- ============================================================================
--  6. `rpc_types_espaces_lister()` — LISTE POUR L'ADMINISTRATION
-- ============================================================================

create or replace function public.rpc_types_espaces_lister()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.est_plateforme() then
    raise exception 'ACCES_REFUSE|Cet écran est réservé au personnel de la plateforme.';
  end if;
  if not public.peut('activites', 'voir') then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de consulter les référentiels.';
  end if;

  return jsonb_build_object(
    'ok', true,
    'types', coalesce((
      select jsonb_agg(jsonb_build_object(
               'type',       t.type,
               'libelle',    t.libelle,
               'modules',    t.modules,
               'actif',      t.actif,
               'nb_espaces', (select count(*)
                                from public.espaces s
                               where s.type = t.type),
               'updated_at', t.updated_at
             ) order by (t.type = 'boutique') desc, t.libelle)
        from public.types_espaces_modules t
    ), '[]'::jsonb)
  );
end;
$$;

comment on function public.rpc_types_espaces_lister() is
  'Module 16 — Liste des profils de modules (page admin « Types d''activités »), avec le nombre d''espaces de chaque type.';

revoke all on function public.rpc_types_espaces_lister() from public;
revoke all on function public.rpc_types_espaces_lister() from anon;
grant execute on function public.rpc_types_espaces_lister() to authenticated;


-- ============================================================================
--  7. `rpc_type_espace_modules_maj()` — CRÉER / MODIFIER UN TYPE (EXPERT)
-- ============================================================================
--  L'« Expert Administrateur » crée un type (ex : « Salon de coiffure ») et
--  coche ses modules → aucune reconstruction de l'application nécessaire.
--  Validation stricte : code slug (minuscules), modules du catalogue.
--  Garde-fou : le profil « boutique » (repli universel) reste toujours actif.

create or replace function public.rpc_type_espace_modules_maj(
  p_type    text,
  p_libelle text,
  p_modules jsonb,
  p_actif   boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user    uuid := auth.uid();
  v_type    text;
  v_libelle text;
  v_actif   boolean := coalesce(p_actif, true);
  v_brut    jsonb := coalesce(p_modules, '[]'::jsonb);
  v_liste   jsonb := '[]'::jsonb;
  v_vus     text[] := array[]::text[];
  v_code    text;
  v_nouveau boolean;
  v_nb      integer := 0;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour gérer les types d''activités.';
  end if;

  if not public.est_plateforme() then
    raise exception 'ACCES_REFUSE|Cet écran est réservé au personnel de la plateforme.';
  end if;
  if not public.peut('activites', 'modifier') then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de modifier les référentiels.';
  end if;

  -- Code du type : identifiant technique « slug » (ex : salon_de_coiffure).
  v_type := lower(btrim(coalesce(p_type, '')));
  if v_type !~ '^[a-z][a-z0-9_]{1,40}$' then
    raise exception 'CODE_INVALIDE|Le code du type doit commencer par une lettre et ne contenir que des minuscules, chiffres et « _ » (ex : salon_de_coiffure).';
  end if;

  v_libelle := nullif(btrim(coalesce(p_libelle, '')), '');
  if v_libelle is null or length(v_libelle) < 2 then
    raise exception 'LIBELLE_REQUIS|Donnez un nom au type d''activité (2 caractères minimum).';
  end if;
  if length(v_libelle) > 60 then
    raise exception 'LIBELLE_REQUIS|Le nom du type est trop long (60 caractères maximum).';
  end if;

  -- Le profil « boutique » est le repli universel : il doit rester actif.
  if v_type = 'boutique' and not v_actif then
    raise exception 'PROFIL_PROTEGE|Le profil « Boutique » est le profil par défaut de l''application : il doit rester actif.';
  end if;

  -- Modules : tableau de codes du catalogue, doublons ignorés.
  if jsonb_typeof(v_brut) <> 'array' then
    raise exception 'MODULES_INVALIDES|La liste des modules doit être un tableau JSON.';
  end if;

  for v_code in
    select lower(btrim(value)) from jsonb_array_elements_text(v_brut)
  loop
    if v_code = '' then
      continue;
    end if;
    if not (v_code = any(public.modules_catalogue())) then
      raise exception 'MODULE_INCONNU|Module inconnu : « % ».', v_code;
    end if;
    if not (v_code = any(v_vus)) then
      v_vus   := v_vus || v_code;
      v_liste := v_liste || to_jsonb(v_code);
    end if;
  end loop;

  v_nouveau := not exists (
    select 1 from public.types_espaces_modules t where t.type = v_type
  );

  insert into public.types_espaces_modules (type, libelle, modules, actif, updated_at)
  values (v_type, v_libelle, v_liste, v_actif, now())
  on conflict (type) do update
    set libelle    = excluded.libelle,
        modules    = excluded.modules,
        actif      = excluded.actif,
        updated_at = now();

  select count(*) into v_nb
    from public.espaces s
   where s.type = v_type;

  -- Trace (best-effort : ne doit jamais faire échouer l'enregistrement).
  begin
    insert into public.journal_audit (entreprise_id, action, utilisateur_id, details)
    values (
      null,
      case when v_nouveau then 'TYPE_ACTIVITE_CREE' else 'TYPE_ACTIVITE_MAJ' end,
      v_user,
      jsonb_build_object(
        'type', v_type, 'libelle', v_libelle,
        'nb_modules', jsonb_array_length(v_liste),
        'actif', v_actif, 'nouveau', v_nouveau
      )
    );
  exception when others then null;
  end;

  return jsonb_build_object(
    'ok',         true,
    'type',       v_type,
    'libelle',    v_libelle,
    'modules',    v_liste,
    'actif',      v_actif,
    'nouveau',    v_nouveau,
    'nb_espaces', v_nb
  );
end;
$$;

comment on function public.rpc_type_espace_modules_maj(text, text, jsonb, boolean) is
  'Module 16 — Crée ou modifie le profil de modules d''un type d''activité (Expert Administrateur).';

revoke all on function public.rpc_type_espace_modules_maj(text, text, jsonb, boolean) from public;
revoke all on function public.rpc_type_espace_modules_maj(text, text, jsonb, boolean) from anon;
grant execute on function public.rpc_type_espace_modules_maj(text, text, jsonb, boolean) to authenticated;


-- ============================================================================
--  8. `rpc_espace_creer()` v2 — ACCEPTE LES TYPES CRÉÉS PAR L'EXPERT
-- ============================================================================
--  Seule la validation du type change : le référentiel remplace la liste
--  figée (repli « autre », puis « boutique »). Le reste est identique à la
--  version du module 15 (migration 19).

create or replace function public.rpc_espace_creer(
  p_nom      text,
  p_type     text default 'boutique',
  p_ville_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_role text := public.mon_role();
  v_ent  uuid;
  v_max  integer := 1;
  v_nb   integer := 0;
  v_nom  text;
  v_type text;
  v_new  uuid;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour créer une entreprise.';
  end if;

  if v_role <> 'PROPRIETAIRE' then
    raise exception 'DROIT_REFUSE|Seul le propriétaire du compte peut créer une entreprise supplémentaire.';
  end if;

  v_nom := nullif(btrim(coalesce(p_nom, '')), '');
  if v_nom is null or length(v_nom) < 2 then
    raise exception 'NOM_REQUIS|Donnez un nom à votre entreprise (2 caractères minimum).';
  end if;

  -- Module 16 — le type doit exister (et être actif) dans le référentiel :
  -- repli « autre » puis « boutique » pour les valeurs inconnues.
  v_type := lower(btrim(coalesce(p_type, 'boutique')));
  if not exists (
    select 1 from public.types_espaces_modules t
     where t.type = v_type and t.actif
  ) then
    v_type := 'autre';
    if not exists (
      select 1 from public.types_espaces_modules t
       where t.type = v_type and t.actif
    ) then
      v_type := 'boutique';
    end if;
  end if;

  select u.entreprise_id into v_ent
    from public.utilisateurs u
   where u.id = v_user;

  if v_ent is null then
    raise exception 'AUCUNE_ENTREPRISE|Créez d''abord votre entreprise principale.';
  end if;

  -- Pack : nombre d'entreprises autorisées par la grille tarifaire.
  select coalesce(g.max_espaces, 1) into v_max
    from public.entreprises e
    left join public.groupes_tarifaires g on g.id = e.groupe_tarifaire_id
   where e.id = v_ent;
  v_max := coalesce(v_max, 1);

  select count(*) into v_nb
    from public.espaces s
   where s.entreprise_id = v_ent;

  if v_nb >= v_max then
    raise exception 'QUOTA_ESPACES|Votre pack autorise % entreprise(s) au maximum. Passez au pack multi-entreprises pour en ajouter.', v_max;
  end if;

  insert into public.espaces (entreprise_id, nom, type, ville_id)
  values (v_ent, v_nom, v_type, p_ville_id)
  returning id into v_new;

  -- Trace (best-effort).
  begin
    insert into public.journal_audit (entreprise_id, action, utilisateur_id, details)
    values (
      null, 'ESPACE_CREE', v_user,
      jsonb_build_object('espace_id', v_new, 'nom', v_nom, 'type', v_type)
    );
  exception when others then null;
  end;

  return jsonb_build_object(
    'ok', true, 'espace_id', v_new, 'nom', v_nom, 'type', v_type,
    'nb_espaces', v_nb + 1, 'max_espaces', v_max
  );
end;
$$;

comment on function public.rpc_espace_creer(text, text, uuid) is
  'Module 15/16 — Crée une entreprise supplémentaire (propriétaire uniquement) ; le type est validé par le référentiel des types d''activités.';

revoke all on function public.rpc_espace_creer(text, text, uuid) from public;
revoke all on function public.rpc_espace_creer(text, text, uuid) from anon;
grant execute on function public.rpc_espace_creer(text, text, uuid) to authenticated;


-- ============================================================================
--  9. VÉRIFICATIONS
-- ============================================================================

-- 9.a Les 6 profils seedés (boutique en premier, puis ordre alphabétique).
select t.type, t.libelle, t.actif,
       jsonb_array_length(t.modules) as nb_modules,
       (select count(*) from public.espaces s where s.type = t.type) as nb_espaces
  from public.types_espaces_modules t
 order by (t.type = 'boutique') desc, t.libelle;

-- 9.b Aucun espace ne doit pointer vers un type absent du référentiel.
select s.type, count(*) as nb
  from public.espaces s
 where not exists (
   select 1 from public.types_espaces_modules t where t.type = s.type
 )
 group by 1;

-- 9.c Le repli fonctionne : boutique doit toujours exister et être actif.
select count(*) as boutique_disponible
  from public.types_espaces_modules t
 where t.type = 'boutique' and t.actif;

-- ============================================================================
--  FIN — Module 16 phase A. Prochaines étapes : phases B/C de la roadmap
--  (tableaux de bord adaptés, modules métier hôtel/pharmacie/restaurant…).
-- ============================================================================
