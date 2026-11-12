-- ============================================================================
--  biashara_yangu — MIGRATION 0152 : LE PRESSING DEVIENT L'ÉCRAN DE TRAVAIL
--  (profil de modules actif + espace typé + permissions pressing)
--
--  PROBLÈME SIGNALÉ (12/11/2026)
--    « Dans le tableau de bord de pressing de lucjean, il y a vente du jour,
--      caisse, clients, ma vitrine, ma visibilité, publicités, caisse, finance,
--      rapports, conseils, suivi… rien d'autre. Comment les activités vont
--      s'effectuer ? »
--
--  CAUSE
--    L'accueil n'affiche une carte que si son MODULE est actif dans le profil
--    de l'espace courant (`rpc_mes_modules` → `types_espaces_modules`).
--    Les cartes listées (Ventes, Stock, Caisse, Finance, Ma vitrine,
--    Publicités…) sont celles du profil « boutique » : le profil « pressing »
--    n'était donc PAS celui appliqué. Trois verrous possibles :
--      1. `espaces.type` n'est pas `pressing` ;
--      2. la ligne `types_espaces_modules.type = 'pressing'` est absente ou
--         INACTIVE (`actif = false`) → `rpc_mes_modules` retombe sur boutique ;
--      3. la matrice de permissions du rôle a été personnalisée sans les
--         pages pressing.
--
--  CE QUE FAIT CE SCRIPT
--    0. Diagnostic : espace actif, profil, modules, profil réellement appliqué.
--    1. Le profil `pressing` existe, contient ses 3 modules métier et est ACTIF.
--    2. L'espace de lucjean@gmail.com est bien de type `pressing`.
--    3. Les permissions « pressing » sont présentes pour le rôle du compte.
--    4. Contrôle final : ce que l'accueil affichera.
--
--  ⚠️ IDEMPOTENT — relançable sans effet de bord.
--  ⚠️ Ne supprime aucune donnée ; ne retire aucune permission.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);


-- ============================================================================
--  0. DIAGNOSTIC — POURQUOI L'ACCUEIL EST « BOUTIQUE »
-- ============================================================================

select 'ESPACE ACTIF' as etape,
       u.email,
       u.espace_actif_id,
       s.nom   as boutique,
       s.type  as type_boutique,
       e.nom   as entreprise,
       e.type_activite
  from public.utilisateurs u
  left join public.espaces s on s.id = u.espace_actif_id
  left join public.entreprises e on e.id = s.entreprise_id
 where lower(u.email) = 'lucjean@gmail.com';

select 'PROFIL DE MODULES' as etape,
       t.type,
       t.libelle,
       coalesce(t.actif, true) as actif,
       t.modules
  from public.types_espaces_modules t
 where t.type in ('pressing', 'boutique')
 order by t.type;

-- Ce que `rpc_mes_modules()` renverra (mêmes règles : type de l'espace actif,
-- profil actif exigé, repli « boutique » implicite en cas d'absence).
with cible as (
  select coalesce(s.type, 'boutique') as type_espace
    from public.utilisateurs u
    left join public.espaces s on s.id = u.espace_actif_id
   where lower(u.email) = 'lucjean@gmail.com'
   limit 1
)
select 'PROFIL RÉELLEMENT APPLIQUÉ' as etape,
       c.type_espace,
       t.libelle,
       coalesce(t.actif, true) as profil_actif,
       t.modules,
       case when t.type is null
            then '❌ Aucun profil actif pour ce type → l''accueil retombe sur boutique'
            else '✅ Profil trouvé' end as verdict
  from cible c
  left join public.types_espaces_modules t
    on t.type = c.type_espace
   and coalesce(t.actif, true);

with cible as (
  select coalesce(s.type, 'boutique') as type_espace
    from public.utilisateurs u
    left join public.espaces s on s.id = u.espace_actif_id
   where lower(u.email) = 'lucjean@gmail.com'
   limit 1
)
select 'MODULES EFFECTIFS (ce que l''accueil utilisera)' as etape,
       c.type_espace,
       coalesce((
         select t.modules::text
           from public.types_espaces_modules t
          where t.type = c.type_espace and coalesce(t.actif, true)
          limit 1),
         (select t.modules::text
            from public.types_espaces_modules t
           where t.type = 'boutique'
           limit 1)) as modules_utilises
  from cible c;


-- ============================================================================
--  1. LE PROFIL « PRESSING » EST PRÉSENT, COMPLET ET ACTIF
-- ============================================================================
--  ⚠️ On AJOUTE les modules métier ; on ne RETIRE jamais ceux que la
--  plateforme aurait ajoutés elle-même.

do $$
declare
  v_cols    text[];
  v_actif   boolean;
  v_modules jsonb;
  v_sql     text;
begin
  if to_regclass('public.types_espaces_modules') is null then
    raise warning '0152 — types_espaces_modules absente : profil pressing non vérifié.';
    return;
  end if;

  select exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'types_espaces_modules'
       and column_name = 'actif'
  ) into v_actif;

  -- 1.a La ligne existe-t-elle ?
  if not exists (select 1 from public.types_espaces_modules where type = 'pressing') then
    insert into public.types_espaces_modules (type, libelle, modules)
    values (
      'pressing',
      'Pressing & Blanchisserie',
      '["clients","caisse","finance","employes","rapports","assistant_ia",
        "press_depots","press_atelier","press_retraits"]'::jsonb
    );
    raise notice '0152 — profil « pressing » créé.';
  end if;

  -- 1.b Elle doit être ACTIVE (sinon `rpc_mes_modules` l'ignore).
  if v_actif then
    execute $q$
      update public.types_espaces_modules
         set actif = true
       where type = 'pressing'
         and coalesce(actif, false) = false
    $q$;
    raise notice '0152 — profil « pressing » activé.';
  end if;

  -- 1.c Les trois modules métier doivent y figurer.
  select modules into v_modules
    from public.types_espaces_modules where type = 'pressing';

  v_modules := coalesce(v_modules, '[]'::jsonb);

  if not (v_modules ? 'press_depots') then
    v_modules := v_modules || '["press_depots"]'::jsonb;
  end if;
  if not (v_modules ? 'press_atelier') then
    v_modules := v_modules || '["press_atelier"]'::jsonb;
  end if;
  if not (v_modules ? 'press_retraits') then
    v_modules := v_modules || '["press_retraits"]'::jsonb;
  end if;
  -- Un pressing n'a ni ventes de marchandises, ni produits, ni stock :
  -- ces modules restent hors profil. Le pressing encaisse, mais par la caisse.

  update public.types_espaces_modules
     set modules    = v_modules,
         updated_at = now()
   where type = 'pressing'
     and modules is distinct from v_modules;

  raise notice '0152 — modules pressing : %', v_modules::text;
end $$;


-- ============================================================================
--  2. L'ESPACE DE lucjean@gmail.com EST DE TYPE « PRESSING »
-- ============================================================================

do $$
declare
  v_uid  uuid;
  v_esp  uuid;
  v_type text;
begin
  select u.id, u.espace_actif_id
    into v_uid, v_esp
    from public.utilisateurs u
   where lower(u.email) = 'lucjean@gmail.com'
   limit 1;

  if v_uid is null then
    raise warning '0152 — lucjean@gmail.com introuvable : étape ignorée.';
    return;
  end if;

  -- Pas d'espace actif ? On prend le premier de son entreprise.
  if v_esp is null then
    select s.id into v_esp
      from public.espaces s
      join public.utilisateurs u on u.entreprise_id = s.entreprise_id
     where u.id = v_uid
     order by s.created_at
     limit 1;

    if v_esp is not null then
      update public.utilisateurs set espace_actif_id = v_esp where id = v_uid;
      raise notice '0152 — espace actif restauré : %', v_esp;
    end if;
  end if;

  if v_esp is null then
    raise warning '0152 — aucun espace pour ce compte : exécutez la migration 0151.';
    return;
  end if;

  select s.type into v_type from public.espaces s where s.id = v_esp;

  if coalesce(v_type, '') <> 'pressing' then
    update public.espaces set type = 'pressing', actif = true where id = v_esp;
    raise notice '0152 — espace % : type % → pressing.', v_esp, coalesce(v_type, '(vide)');
  else
    raise notice '0152 — espace % déjà en pressing.', v_esp;
  end if;

  -- L'entreprise suit (tolérant si la contrainte n'est pas élargie).
  begin
    update public.entreprises e
       set type_activite = 'pressing',
           updated_at    = now()
     where e.id = (select s.entreprise_id from public.espaces s where s.id = v_esp)
       and coalesce(e.type_activite, '') <> 'pressing';
  exception
    when others then
      raise warning '0152 — type_activite non écrit (%) : exécutez la migration 0150.', sqlerrm;
  end;
end $$;


-- ============================================================================
--  3. LES PERMISSIONS « PRESSING » DU RÔLE
-- ============================================================================
--  Les cartes de l'accueil sont filtrées AUSSI par les permissions. Si la
--  plateforme a personnalisé la matrice d'un rôle AVANT le module 35, les
--  pages pressing peuvent manquer : on les AJOUTE (jamais on n'en retire).

do $$
declare
  v_role   text;
  v_eff    jsonb;
  v_ajout  jsonb := '{}'::jsonb;
  v_pages  text[] := array['pressing_depots', 'pressing_atelier', 'pressing_retraits'];
  v_page   text;
  v_perso  boolean;
begin
  select upper(btrim(coalesce(u.new_role::text, u.role, 'PROPRIETAIRE')))
    into v_role
    from public.utilisateurs u
   where lower(u.email) = 'lucjean@gmail.com'
   limit 1;

  if v_role is null then
    return;
  end if;

  v_eff := public.permissions_effectives(v_role);

  select exists (
    select 1 from public.app_settings s
     where s.key = 'permissions_roles'
       and s.value -> 'roles' ? v_role
  ) into v_perso;

  for v_page in array v_pages loop
    if not (coalesce(v_eff, '{}'::jsonb) ? v_page) then
      v_ajout := v_ajout || jsonb_build_object(
        v_page, to_jsonb(public.actions_permissions()));
      raise notice '0152 — page % ajoutée au rôle %.', v_page, v_role;
    end if;
  end loop;

  if v_ajout = '{}'::jsonb then
    raise notice '0152 — rôle % : permissions pressing déjà présentes.', v_role;
    return;
  end if;

  if v_perso then
    -- Matrice personnalisée : on complète UNIQUEMENT ce rôle.
    update public.app_settings s
       set value = jsonb_set(s.value,
                             array['roles', v_role],
                             coalesce(s.value -> 'roles' -> v_role, '{}'::jsonb) || v_ajout,
                             true),
           updated_at = now()
     where s.key = 'permissions_roles';
    raise notice '0152 — matrice personnalisée complétée pour %.', v_role;
  else
    -- Aucune personnalisation : la matrice par défaut fait déjà le travail
    -- (elle contient les pages pressing depuis le module 35).
    raise notice '0152 — rôle % : matrice par défaut utilisée, rien à écrire.', v_role;
  end if;
end $$;


-- ============================================================================
--  4. CONTRÔLE FINAL
-- ============================================================================

with cible as (
  select coalesce(s.type, 'boutique') as type_espace,
         s.nom                        as boutique,
         u.espace_actif_id
    from public.utilisateurs u
    left join public.espaces s on s.id = u.espace_actif_id
   where lower(u.email) = 'lucjean@gmail.com'
   limit 1
)
select 'RÉSULTAT' as controle,
       c.boutique,
       c.type_espace,
       t.libelle                     as profil,
       coalesce(t.actif, true)       as profil_actif,
       t.modules                     as modules,
       case
         when c.type_espace = 'pressing'
          and t.type is not null
          and coalesce(t.actif, true)
          and t.modules ? 'press_depots'
         then '✅ Accueil pressing (dépôts, atelier, retraits)'
         else '❌ Encore en boutique — voir les 3 verrous ci-dessus'
       end                           as verdict
  from cible c
  left join public.types_espaces_modules t
    on t.type = c.type_espace
   and coalesce(t.actif, true);

select 'CE QUE L''ACCUEIL AFFICHERA' as controle,
       'Pressing (dépôts & retraits), Clients, Caisse, Finance, Rapports, Assistant IA, Équipe, Mon abonnement' as cartes_attendues,
       'Ventes, Stock, Articles, Ma vitrine, Ma visibilité, Publicités : MASQUÉS (hors profil pressing)' as cartes_masquees;

select 'MIGRATION 0152 TERMINÉE' as controle,
       'Déconnexion → reconnexion dans l''application : le profil est relu à la connexion.' as consigne;
