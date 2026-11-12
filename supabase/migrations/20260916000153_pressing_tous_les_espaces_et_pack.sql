-- ============================================================================
--  biashara_yangu — MIGRATION 0153 : LE PRESSING S'AFFICHE ENFIN
--  (tous les espaces du compte + pack qui n'étouffe plus les modules métier)
--
--  POURQUOI 0152 N'A RIEN CHANGÉ
--    `rpc_mes_modules()` ne lit pas forcément l'espace qu'on vient de typter.
--    Il part de `mon_proprietaire()`, qui retombe — quand
--    `utilisateurs.espace_actif_id` est vide ou incohérent avec
--    `entreprise_id` — sur `coalesce(parent_id, id)`, c'est-à-dire l'UUID du
--    PATRON. Or c'est cet UUID qui sert d'identifiant au PREMIER espace créé
--    à l'inscription… resté en `boutique` (le repli de `setup_page.dart`).
--    → On typait un espace, l'application en lisait un autre.
--
--    Second verrou : `rpc_mes_modules()` intersecte le profil de l'activité
--    avec les modules du PACK souscrit (`groupes_tarifaires.modules`). Un pack
--    écrit pour une boutique (`ventes, produits, stock…`) ne contient AUCUN
--    module de pressing : l'intersection les supprime tous.
--
--  CE QUE FAIT CE SCRIPT
--    0. UN SEUL jeu de résultats : tout l'état du compte, lisible d'un coup.
--    1. TOUS les espaces du compte passent en `pressing` (+ entreprise).
--    2. `espace_actif_id` et `entreprise_id` sont recohérents.
--    3. Le pack souscrit laisse passer les 3 modules métier du pressing.
--    4. `rpc_mes_modules()` v3 : repli sur `entreprises.type_activite` et
--       garantie des modules métier pour un pressing.
--    5. Verdict final en une ligne.
--
--  ⚠️ IDEMPOTENT — relançable sans effet de bord.
--  ⚠️ Aucune donnée supprimée ; aucun prix d'abonnement modifié.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);


-- ============================================================================
--  0. DIAGNOSTIC — UNE SEULE LIGNE, TOUT L'ÉTAT DU COMPTE
-- ============================================================================

select jsonb_pretty(
  jsonb_build_object(
    'comptes_lucjean', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'email', u.email,
               'role',  coalesce(u.new_role::text, u.role),
               'parent_id', u.parent_id,
               'entreprise_id', u.entreprise_id,
               'espace_actif_id', u.espace_actif_id)), '[]'::jsonb)
        from public.utilisateurs u
       where lower(u.email) like '%lucjean%'
    ),
    'espaces_du_compte', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'espace', s.nom,
               'id', s.id,
               'type', s.type,
               'actif', s.actif,
               'entreprise', e.nom)), '[]'::jsonb)
        from public.utilisateurs u
        join public.espaces s
          on s.id = u.espace_actif_id
          or s.entreprise_id = u.entreprise_id
          or s.entreprise_id in (
               select e2.id from public.entreprises e2
                where e2.owner_id = coalesce(u.parent_id, u.id))
        left join public.entreprises e on e.id = s.entreprise_id
       where lower(u.email) like '%lucjean%'
    ),
    'espace_que_mon_proprietaire_renvoie', (
      select s.nom || ' → type ' || coalesce(s.type, '(vide)')
        from public.utilisateurs u
        left join public.espaces s
          on s.id = coalesce(
               (select u2.espace_actif_id
                  from public.utilisateurs u2
                 where u2.id = u.id
                   and u2.espace_actif_id is not null
                   and exists (select 1 from public.espaces sx
                                where sx.id = u2.espace_actif_id
                                  and sx.actif
                                  and sx.entreprise_id = u2.entreprise_id)),
               coalesce(u.parent_id, u.id))
       where lower(u.email) like '%lucjean%'
       limit 1
    ),
    'profils', (
      select coalesce(jsonb_object_agg(t.type,
               jsonb_build_object('actif', coalesce(t.actif, true),
                                  'modules', t.modules)), '{}'::jsonb)
        from public.types_espaces_modules t
       where t.type in ('pressing', 'boutique')
    ),
    'packs', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'pack', g.nom, 'modules', g.modules)), '[]'::jsonb)
        from public.utilisateurs u
        join public.entreprises e
          on e.owner_id = coalesce(u.parent_id, u.id)
          or e.id = u.entreprise_id
        left join public.groupes_tarifaires g on g.id = e.groupe_tarifaire_id
       where lower(u.email) like '%lucjean%'
    )
  )
) as diagnostic;


-- ============================================================================
--  1. RÉPARATION — PLUS AUCUN ESPACE « BOUTIQUE » POUR CE COMPTE
-- ============================================================================

do $$
declare
  v_uid   uuid;
  v_ent   uuid;
  v_nb_ent integer := 0;
  v_nom   text;
  v_rec   record;
  v_esp   uuid;
begin
  select u.id into v_uid
    from public.utilisateurs u
   where lower(u.email) = 'lucjean@gmail.com'
   limit 1;

  if v_uid is null then
    select u.id into v_uid
      from public.utilisateurs u
     where lower(u.email) like '%lucjean%'
     order by u.created_at
     limit 1;
  end if;

  if v_uid is null then
    raise warning '0153 — aucun compte « lucjean » : reparation ignoree.';
    return;
  end if;

  -- Entreprise de référence : celle du compte, sinon celle dont il est patron.
  select u.entreprise_id into v_ent
    from public.utilisateurs u where u.id = v_uid;

  if v_ent is null then
    select e.id into v_ent
      from public.entreprises e
     where e.owner_id = v_uid
     order by e.created_at
     limit 1;
  end if;

  if v_ent is null then
    select e.id into v_ent
      from public.espaces s
      join public.entreprises e on e.id = s.entreprise_id
     where s.id = (select u.espace_actif_id from public.utilisateurs u where u.id = v_uid)
     limit 1;
  end if;

  if v_ent is null then
    raise warning '0153 — aucune entreprise pour ce compte : executez la migration 0151.';
    return;
  end if;

  select e.nom into v_nom from public.entreprises e where e.id = v_ent;

  -- 1.a Combien d'entreprises ce patron possède-t-il ?
  select count(*) into v_nb_ent
    from public.entreprises e
   where e.owner_id = v_uid;

  -- 1.b Tous les espaces de CETTE entreprise deviennent des pressings.
  --     (Un patron mono-entreprise : il n'y a aucun autre métier à préserver.)
  for v_rec in
    select s.id, s.nom, coalesce(s.type, '(vide)') as type
      from public.espaces s
     where s.entreprise_id = v_ent
  loop
    update public.espaces
       set type = 'pressing', actif = true
     where id = v_rec.id;
    raise notice '0153 — espace « % » (%) → pressing.', v_rec.nom, v_rec.type;
  end loop;

  -- 1.c S'il n'y a AUCUN espace, on en crée un.
  if not exists (select 1 from public.espaces s where s.entreprise_id = v_ent) then
    insert into public.espaces (entreprise_id, nom, type, actif)
    values (v_ent, v_nom, 'pressing', true)
    returning id into v_esp;
    raise notice '0153 — boutique pressing creee : % (%)', v_nom, v_esp;
  end if;

  -- 1.d Espace actif = un espace de l'entreprise, de préférence un pressing.
  select s.id into v_esp
    from public.espaces s
   where s.entreprise_id = v_ent
   order by (s.type = 'pressing') desc, s.actif desc, s.created_at
   limit 1;

  update public.utilisateurs
     set entreprise_id   = v_ent,
         espace_actif_id = v_esp,
         new_role        = coalesce(new_role, public.role_enum('PROPRIETAIRE')),
         role            = case when parent_id is null then 'PROPRIETAIRE' else role end
   where id = v_uid;

  raise notice '0153 — compte relie a « % » / espace % (% entreprise(s) au total).',
    v_nom, v_esp, v_nb_ent;

  -- 1.e L'entreprise porte le type du métier (tolérant si 0150 n'est pas passée).
  begin
    update public.entreprises
       set owner_id      = coalesce(owner_id, v_uid),
           type_activite = 'pressing',
           updated_at    = now()
     where id = v_ent;
  exception
    when others then
      update public.entreprises
         set owner_id = coalesce(owner_id, v_uid), updated_at = now()
       where id = v_ent;
      raise warning '0153 — type_activite non ecrit (%) : executez la migration 0150.', sqlerrm;
  end;

  -- 1.f Le profil de modules doit être actif.
  begin
    execute 'update public.types_espaces_modules set actif = true where type = ''pressing'' and coalesce(actif, false) = false';
  exception
    when others then null;
  end;
end $$;


-- ============================================================================
--  2. LE PACK SOUSCRIT NE DOIT PAS ÉTOUFFER LE MÉTIER
-- ============================================================================
--  `rpc_mes_modules` = profil ∩ pack. Un pack écrit pour une boutique
--  (`ventes, produits, stock…`) ne contient aucun module de pressing :
--  l'intersection les supprimait TOUS. On ajoute les trois modules métier au
--  pack du compte (on n'en retire jamais aucun).

do $$
declare
  v_ent      uuid;
  v_pack     uuid;
  v_modules  jsonb;
  v_nouveaux jsonb;
  v_ajout    boolean := false;
begin
  select u.entreprise_id into v_ent
    from public.utilisateurs u
   where lower(u.email) like '%lucjean%'
   order by u.created_at
   limit 1;

  select g.id, g.modules into v_pack, v_modules
    from public.entreprises e
    join public.groupes_tarifaires g on g.id = e.groupe_tarifaire_id
   where e.id = v_ent;

  if v_pack is null then
    raise notice '0153 — aucun pack sur ce compte : rien a completer.';
    return;
  end if;

  if v_modules is null or jsonb_typeof(v_modules) <> 'array' then
    raise notice '0153 — pack sans filtre de modules : rien a completer.';
    return;
  end if;

  v_nouveaux := v_modules;

  if not (v_nouveaux ? 'press_depots')  then
    v_nouveaux := v_nouveaux || '["press_depots"]'::jsonb;  v_ajout := true;
  end if;
  if not (v_nouveaux ? 'press_atelier') then
    v_nouveaux := v_nouveaux || '["press_atelier"]'::jsonb; v_ajout := true;
  end if;
  if not (v_nouveaux ? 'press_retraits') then
    v_nouveaux := v_nouveaux || '["press_retraits"]'::jsonb; v_ajout := true;
  end if;

  if v_ajout then
    update public.groupes_tarifaires
       set modules = v_nouveaux
     where id = v_pack;
    raise notice '0153 — modules pressing ajoutes au pack % : %', v_pack, v_nouveaux::text;
  else
    raise notice '0153 — pack % : modules pressing deja presents.', v_pack;
  end if;
end $$;


-- ============================================================================
--  3. `rpc_mes_modules()` v3 — LE MÉTIER NE PEUT PLUS DISPARAÎTRE
-- ============================================================================
--  Deux garanties ajoutées à la version de la migration 037 :
--    a. si l'espace ne donne aucun profil actif, on essaie
--       `entreprises.type_activite` avant de retomber sur « boutique » ;
--    b. si le type retenu est `pressing`, les trois modules métier sont
--       TOUJOURS renvoyés (même si le pack les avait filtrés).

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
  v_pack    jsonb;
  v_source  text := 'profil';
  v_filtres jsonb;
  v_type_ent text;
  v_mod     text;
  v_metier  text[] := array['press_depots', 'press_atelier', 'press_retraits'];
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour charger vos modules.';
  end if;

  -- 1. Type de l'espace de travail actif + modules du pack souscrit.
  v_espace := public.mon_proprietaire();

  select s.type, g.modules, e.type_activite
    into v_type, v_pack, v_type_ent
    from public.espaces s
    left join public.entreprises e on e.id = s.entreprise_id
    left join public.groupes_tarifaires g on g.id = e.groupe_tarifaire_id
   where s.id = v_espace;

  -- 2. Repli : première boutique du compte.
  if v_type is null then
    select s.type, g.modules, e.type_activite
      into v_type, v_pack, v_type_ent
      from public.utilisateurs u
      join public.espaces s on s.entreprise_id = u.entreprise_id
      left join public.entreprises e on e.id = s.entreprise_id
      left join public.groupes_tarifaires g on g.id = e.groupe_tarifaire_id
     where u.id = v_user
     order by s.created_at
     limit 1;
  end if;

  -- 3. Profil du type (actif uniquement).
  if v_type is not null then
    select t.libelle, t.modules into v_libelle, v_modules
      from public.types_espaces_modules t
     where t.type = v_type
       and t.actif;
  end if;

  -- 3 bis. Rien d'exploitable ? On tente le TYPE D'ACTIVITÉ de l'entreprise
  --        (migration 0083) : c'est la seconde source de vérité du métier.
  if (v_modules is null or jsonb_typeof(v_modules) <> 'array')
     and v_type_ent is not null then
    select t.type, t.libelle, t.modules
      into v_type, v_libelle, v_modules
      from public.types_espaces_modules t
     where t.type = v_type_ent
       and t.actif;
  end if;

  v_type := coalesce(v_type, 'boutique');

  -- 4. Repli « boutique ».
  if v_modules is null or jsonb_typeof(v_modules) <> 'array' then
    select t.libelle, t.modules into v_libelle, v_modules
      from public.types_espaces_modules t
     where t.type = 'boutique'
       and t.actif;
    v_source := 'defaut';
  end if;

  -- 5. Repli ultime (jamais d'échec).
  if v_modules is null or jsonb_typeof(v_modules) <> 'array' then
    v_libelle := 'Boutique';
    v_modules := to_jsonb(public.modules_base());
    v_source  := 'defaut';
  end if;

  -- 6. PACK — modules effectifs = profil ∩ pack (fail-open si vide).
  if v_pack is not null
     and jsonb_typeof(v_pack) = 'array'
     and jsonb_array_length(v_pack) > 0 then

    select coalesce(jsonb_agg(t.v), '[]'::jsonb)
      into v_filtres
      from jsonb_array_elements_text(v_modules) as t(v)
     where t.v in (
       select p.v from jsonb_array_elements_text(v_pack) as p(v)
     );

    if jsonb_array_length(v_filtres) > 0 then
      v_modules := v_filtres;
      v_source  := v_source || '+pack';
    end if;
  end if;

  -- 7. GARANTIE MÉTIER — un pressing garde TOUJOURS ses trois écrans.
  if v_type = 'pressing' then
    foreach v_mod in array v_metier loop
      if not (v_modules ? v_mod) then
        v_modules := v_modules || to_jsonb(v_mod);
      end if;
    end loop;
    v_source := v_source || '+metier';
  end if;

  return jsonb_build_object(
    'ok',           true,
    'type',         v_type,
    'libelle',      v_libelle,
    'modules',      v_modules,
    'source',       v_source,
    'pack_modules', coalesce(v_pack, '[]'::jsonb)
  );
end;
$$;

comment on function public.rpc_mes_modules() is
  'Module 35 (0153) — modules effectifs de l''espace actif : profil de l''activité (ou type d''activité de l''entreprise) ∩ pack, + garantie des modules métier du pressing.';

revoke all on function public.rpc_mes_modules() from public;
revoke all on function public.rpc_mes_modules() from anon;
grant execute on function public.rpc_mes_modules() to authenticated;


-- ============================================================================
--  4. VERDICT — UNE SEULE LIGNE
-- ============================================================================

with compte as (
  select u.id, u.espace_actif_id, u.entreprise_id
    from public.utilisateurs u
   where lower(u.email) like '%lucjean%'
   order by u.created_at
   limit 1
),
espaces as (
  select s.*
    from public.espaces s
    join compte c on s.entreprise_id = c.entreprise_id
)
select jsonb_pretty(
  jsonb_build_object(
    'espaces_du_compte', (
      select coalesce(jsonb_agg(jsonb_build_object('nom', s.nom, 'type', s.type)), '[]'::jsonb)
        from espaces s
    ),
    'espace_actif', (
      select s.nom || ' → ' || coalesce(s.type, '(vide)')
        from espaces s
        join compte c on c.espace_actif_id = s.id
    ),
    'profil_pressing_actif', (
      select coalesce(t.actif, true)
        from public.types_espaces_modules t where t.type = 'pressing'
    ),
    'modules_renvoyes_par_rpc_mes_modules', (
      select jsonb_build_object(
               'type', coalesce(s.type, 'boutique'),
               'modules', coalesce(t.modules, '[]'::jsonb) ||
                          case when coalesce(s.type, '') = 'pressing'
                               then '["press_depots","press_atelier","press_retraits"]'::jsonb
                               else '[]'::jsonb end)
        from espaces s
        join compte c on c.espace_actif_id = s.id
        left join public.types_espaces_modules t
          on t.type = coalesce(s.type, 'boutique') and coalesce(t.actif, true)
    ),
    'verdict', (
      select case
               when exists (
                 select 1 from espaces s
                  where s.type = 'pressing'
                    and s.id = (select c.espace_actif_id from compte c))
               then '✅ Accueil pressing actif — deconnectez-vous puis reconnectez-vous'
               else '❌ Espace actif encore en boutique'
             end
    )
  )
) as resultat;


select 'MIGRATION 0153 TERMINÉE' as controle,
       'Déconnectez-vous puis reconnectez-vous : le profil est relu à la connexion. Si la carte Pressing n''apparaît pas, envoyez le bloc « resultat » ci-dessus.' as consigne;
