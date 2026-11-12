-- ============================================================================
--  biashara_yangu — MIGRATION 0154 : L'ENTREPRISE FAIT FOI
--  (rpc_mes_modules lit `entreprises.type_activite` AVANT l'espace)
--
--  OBSERVATION (12/11/2026)
--    Après 0153, l'accueil n'affiche plus que :
--      • Vente du jour,
--      • Ma vitrine / Ma visibilité / Publicités / Mon abonnement (cartes
--        sans module),
--    et plus AUCUNE carte métier (ni dépôts, ni caisse, ni clients…).
--
--  LECTURE
--    `modules = profil ∩ pack`. Obtenir « ventes » SEUL signifie que le
--    PROFIL retenu contient `ventes` (donc ce n'est pas le pressing) et que
--    le PACK ne partage avec lui que `ventes`. Autrement dit : le profil lu
--    n'est toujours pas `pressing`, alors que l'entreprise, elle, l'est.
--
--  CAUSE
--    `rpc_mes_modules()` résout le métier par l'ESPACE (`mon_proprietaire()`),
--    qui peut être NULL, incohérent, ou appartenir à une autre entreprise.
--    `entreprises.type_activite` — la vraie fiche du métier (migration 0083)
--    — n'était lue qu'en tout dernier recours.
--
--  CE QUE FAIT CE SCRIPT
--    1. Diagnostic décisif en une ligne (espace lu, espace actif, entreprise).
--    2. `entreprises.type_activite = 'pressing'` écrit pour de bon
--       (contrainte élargie si nécessaire).
--    3. Tous les espaces du compte en `pressing`.
--    4. `rpc_mes_modules()` v4 : entreprise d'abord, espace ensuite, et les
--       3 modules métier toujours garantis pour un pressing.
--    5. Verdict + simulation exacte de ce que l'application recevra.
--
--  ⚠️ IDEMPOTENT — aucun prix, aucun abonnement, aucune donnée supprimée.
--  ⚠️ Zéro régression : `type_activite` vaut NULL par défaut ; la règle
--     « entreprise d'abord » ne s'applique donc que si le métier est renseigné
--     ET qu'un profil actif existe pour ce métier.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);


-- ============================================================================
--  0. DIAGNOSTIC DÉCISIF — UNE LIGNE
-- ============================================================================

with compte as (
  select u.id, u.entreprise_id, u.espace_actif_id, u.parent_id,
         coalesce(u.new_role::text, u.role) as role
    from public.utilisateurs u
   where lower(u.email) like '%lucjean%'
   order by u.created_at
   limit 1
)
select jsonb_pretty(
  jsonb_build_object(
    'role',                    (select c.role from compte c),
    'entreprise_id',           (select c.entreprise_id from compte c),
    'entreprise_nom',          (select e.nom from compte c
                                  join public.entreprises e on e.id = c.entreprise_id),
    'entreprise_type_activite',(select e.type_activite from compte c
                                  join public.entreprises e on e.id = c.entreprise_id),
    'espace_actif_id',         (select c.espace_actif_id from compte c),
    'espace_actif_type',       (select s.type from compte c
                                  join public.espaces s on s.id = c.espace_actif_id),
    'espace_lu_par_mon_proprietaire', (
      select s.id || ' / ' || s.nom || ' → type ' || coalesce(s.type, '(vide)')
        from compte c
        left join public.espaces s
          on s.id = coalesce(
               (select u2.espace_actif_id
                  from public.utilisateurs u2
                 where u2.id = c.id
                   and u2.espace_actif_id is not null
                   and exists (select 1 from public.espaces sx
                                where sx.id = u2.espace_actif_id
                                  and sx.actif
                                  and sx.entreprise_id = u2.entreprise_id)),
               coalesce(c.parent_id, c.id))
    ),
    'tous_les_espaces', (
      select coalesce(jsonb_agg(jsonb_build_object('nom', s.nom, 'type', s.type,
                                                   'actif', s.actif)), '[]'::jsonb)
        from compte c
        join public.espaces s on s.entreprise_id = c.entreprise_id
    ),
    'pack_modules', (
      select g.modules from compte c
        join public.entreprises e on e.id = c.entreprise_id
        left join public.groupes_tarifaires g on g.id = e.groupe_tarifaire_id
    ),
    'profil_pressing', (
      select jsonb_build_object('actif', coalesce(t.actif, true), 'modules', t.modules)
        from public.types_espaces_modules t where t.type = 'pressing'
    )
  )
) as diagnostic;


-- ============================================================================
--  1. LA CONTRAINTE DE TYPE N'EST PLUS UN OBSTACLE
-- ============================================================================

do $$
declare
  v_con   text;
  v_types text[] := array[
    'boutique', 'distribution', 'pressing', 'depot', 'hotel', 'pharmacie',
    'restaurant', 'salle_fetes', 'boulangerie', 'boucherie', 'mode',
    'salon_de_coiffure', 'autre'
  ];
begin
  for v_con in
    select c.conname
      from pg_constraint c
      join pg_class r on r.oid = c.conrelid
      join pg_namespace n on n.oid = r.relnamespace
     where n.nspname = 'public'
       and r.relname = 'entreprises'
       and c.contype = 'c'
       and pg_get_constraintdef(c.oid) ilike '%type_activite%'
  loop
    execute format('alter table public.entreprises drop constraint %I', v_con);
  end loop;

  execute format(
    'alter table public.entreprises add constraint entreprises_type_activite_check '
    'check (type_activite is null or type_activite = any (%L::text[]))',
    v_types
  );
  raise notice '0154 — contrainte entreprises.type_activite elargie.';
exception
  when others then
    raise warning '0154 — contrainte non ajustee : %', sqlerrm;
end $$;


-- ============================================================================
--  2. L'ENTREPRISE DU COMPTE DEVIENT UN PRESSING (ET SES ESPACES AUSSI)
-- ============================================================================

do $$
declare
  v_uid  uuid;
  v_ent  uuid;
  v_esp  uuid;
  v_rec  record;
  v_nom  text;
begin
  select u.id into v_uid
    from public.utilisateurs u
   where lower(u.email) like '%lucjean%'
   order by u.created_at
   limit 1;

  if v_uid is null then
    raise warning '0154 — compte introuvable.';
    return;
  end if;

  select coalesce(
           (select u.entreprise_id from public.utilisateurs u where u.id = v_uid),
           (select e.id from public.entreprises e
             where e.owner_id = v_uid order by e.created_at limit 1),
           (select s.entreprise_id from public.espaces s
             where s.id = (select u.espace_actif_id
                             from public.utilisateurs u where u.id = v_uid)))
    into v_ent;

  if v_ent is null then
    raise warning '0154 — aucune entreprise pour ce compte (voir migration 0151).';
    return;
  end if;

  select e.nom into v_nom from public.entreprises e where e.id = v_ent;

  -- 2.a Le MÉTIER, sur la fiche de l'entreprise (source de vérité).
  update public.entreprises
     set owner_id      = coalesce(owner_id, v_uid),
         type_activite = 'pressing',
         updated_at    = now()
   where id = v_ent;

  raise notice '0154 — entreprise « % » : type_activite = pressing.', v_nom;

  -- 2.b TOUS ses espaces, quel que soit celui que l'application lira.
  for v_rec in
    select s.id, s.nom, coalesce(s.type, '(vide)') as type
      from public.espaces s
     where s.entreprise_id = v_ent
  loop
    update public.espaces set type = 'pressing', actif = true where id = v_rec.id;
    raise notice '0154 — espace « % » (%) → pressing.', v_rec.nom, v_rec.type;
  end loop;

  if not exists (select 1 from public.espaces s where s.entreprise_id = v_ent) then
    insert into public.espaces (entreprise_id, nom, type, actif)
    values (v_ent, v_nom, 'pressing', true)
    returning id into v_esp;
    raise notice '0154 — boutique pressing creee : %', v_esp;
  end if;

  -- 2.c Espace actif cohérent (entreprise + espace).
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

  -- 2.d Le profil doit être actif.
  begin
    execute 'update public.types_espaces_modules set actif = true where type = ''pressing'' and coalesce(actif, false) = false';
  exception when others then null;
  end;

  raise notice '0154 — compte relie a « % » / espace %.', v_nom, v_esp;
end $$;


-- ============================================================================
--  3. `rpc_mes_modules()` v4 — L'ENTREPRISE D'ABORD
-- ============================================================================
--  Ordre de résolution du métier :
--    1. `entreprises.type_activite` (fiche du métier, si profil actif) ;
--    2. `espaces.type` de l'espace de travail ;
--    3. `espaces.type` de la première boutique du compte ;
--    4. `boutique`.
--  Puis : profil ∩ pack (fail-open si vide), et garantie des 3 modules
--  métier quand le métier retenu est `pressing`.

create or replace function public.rpc_mes_modules()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_user     uuid := auth.uid();
  v_espace   uuid;
  v_type_ent text;
  v_type_esp text;
  v_type     text;
  v_libelle  text;
  v_modules  jsonb;
  v_pack     jsonb;
  v_source   text := 'profil';
  v_filtres  jsonb;
  v_mod      text;
  v_metier   text[] := array['press_depots', 'press_atelier', 'press_retraits'];
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour charger vos modules.';
  end if;

  -- 1. Espace de travail et pack souscrit.
  v_espace := public.mon_proprietaire();

  select s.type, e.type_activite, g.modules
    into v_type_esp, v_type_ent, v_pack
    from public.espaces s
    left join public.entreprises e on e.id = s.entreprise_id
    left join public.groupes_tarifaires g on g.id = e.groupe_tarifaire_id
   where s.id = v_espace;

  -- 2. Repli : première boutique du compte.
  if v_type_esp is null and v_type_ent is null then
    select s.type, e.type_activite, g.modules
      into v_type_esp, v_type_ent, v_pack
      from public.utilisateurs u
      join public.espaces s on s.entreprise_id = u.entreprise_id
      left join public.entreprises e on e.id = s.entreprise_id
      left join public.groupes_tarifaires g on g.id = e.groupe_tarifaire_id
     where u.id = v_user
     order by s.created_at
     limit 1;
  end if;

  -- 3. LE MÉTIER — l'entreprise fait foi, l'espace sert de repli.
  if v_type_ent is not null then
    select t.libelle, t.modules into v_libelle, v_modules
      from public.types_espaces_modules t
     where t.type = v_type_ent
       and t.actif;

    if v_modules is not null and jsonb_typeof(v_modules) = 'array' then
      v_type   := v_type_ent;
      v_source := 'entreprise';
    else
      v_modules := null;
    end if;
  end if;

  if v_modules is null and v_type_esp is not null then
    select t.libelle, t.modules into v_libelle, v_modules
      from public.types_espaces_modules t
     where t.type = v_type_esp
       and t.actif;

    if v_modules is not null and jsonb_typeof(v_modules) = 'array' then
      v_type   := v_type_esp;
      v_source := 'profil';
    else
      v_modules := null;
    end if;
  end if;

  -- 4. Repli « boutique ».
  if v_modules is null then
    select t.libelle, t.modules into v_libelle, v_modules
      from public.types_espaces_modules t
     where t.type = 'boutique'
       and t.actif;
    v_type   := coalesce(v_type, 'boutique');
    v_source := 'defaut';
  end if;

  -- 5. Repli ultime (jamais d'échec).
  if v_modules is null or jsonb_typeof(v_modules) <> 'array' then
    v_libelle := 'Boutique';
    v_modules := to_jsonb(public.modules_base());
    v_type    := coalesce(v_type, 'boutique');
    v_source  := 'defaut';
  end if;

  -- 6. PACK — profil ∩ pack (fail-open si l'intersection est vide).
  if v_pack is not null
     and jsonb_typeof(v_pack) = 'array'
     and jsonb_array_length(v_pack) > 0 then

    select coalesce(jsonb_agg(t.v), '[]'::jsonb)
      into v_filtres
      from jsonb_array_elements_text(v_modules) as t(v)
     where t.v in (select p.v from jsonb_array_elements_text(v_pack) as p(v));

    if jsonb_array_length(v_filtres) > 0 then
      v_modules := v_filtres;
      v_source  := v_source || '+pack';
    end if;
  end if;

  -- 7. GARANTIE MÉTIER — un pressing garde toujours ses trois écrans.
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
  '0154 — modules effectifs : MÉTIER de l''entreprise d''abord (puis espace), ∩ pack, + garantie des modules métier du pressing.';

revoke all on function public.rpc_mes_modules() from public;
revoke all on function public.rpc_mes_modules() from anon;
grant execute on function public.rpc_mes_modules() to authenticated;


-- ============================================================================
--  4. VERDICT + SIMULATION DE CE QUE L'APPLICATION RECEVRA
-- ============================================================================

with compte as (
  select u.id, u.entreprise_id, u.espace_actif_id, u.parent_id
    from public.utilisateurs u
   where lower(u.email) like '%lucjean%'
   order by u.created_at
   limit 1
),
ent as (
  select e.id, e.nom, e.type_activite, g.modules as pack
    from compte c
    join public.entreprises e on e.id = c.entreprise_id
    left join public.groupes_tarifaires g on g.id = e.groupe_tarifaire_id
),
profil as (
  select t.type, t.libelle, t.modules
    from public.types_espaces_modules t
   where t.type = (select coalesce(type_activite, 'boutique') from ent)
     and t.actif
),
effectif as (
  select p.type,
         p.libelle,
         p.modules ||
         case when p.type = 'pressing'
              then '["press_depots","press_atelier","press_retraits"]'::jsonb
              else '[]'::jsonb end as modules
    from profil p
)
select jsonb_pretty(
  jsonb_build_object(
    'entreprise',          (select nom from ent),
    'entreprise_metier',   (select type_activite from ent),
    'pack_modules',        (select pack from ent),
    'profil_utilise',      (select type from effectif),
    'modules_renvoyes',    (select modules from effectif),
    'cartes_attendues', (
      select coalesce(jsonb_agg(c), '[]'::jsonb)
        from jsonb_array_elements_text((select modules from effectif)) as c
       where c in ('press_depots','press_atelier','press_retraits',
                   'clients','caisse','finance','rapports','assistant_ia',
                   'ventes','produits','stock')
    ),
    'verdict', case
      when (select type from effectif) = 'pressing'
       and (select modules from effectif) ? 'press_depots'
        then '✅ L''application recevra le profil pressing'
      when (select type from effectif) is null
        then '❌ Aucun profil actif — vérifier types_espaces_modules'
      else '❌ Profil ' || coalesce((select type from effectif), '(aucun)')
              || ' — le métier de l''entreprise n''a pas été appliqué'
    end
  )
) as resultat;

select 'MIGRATION 0154 TERMINÉE' as controle,
       'Déconnectez-vous puis reconnectez-vous. Le bloc « resultat » montre exactement ce que l''application va recevoir.' as consigne;
