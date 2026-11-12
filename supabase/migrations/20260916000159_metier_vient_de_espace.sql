-- ============================================================================
--  biashara_yangu — MIGRATION 0159 : LE MÉTIER D'ABORD, C'EST L'ESPACE
--  (`rpc_mes_modules()` v5)
--
--  CE QUE L'ON A CONSTATÉ (12/11/2026)
--    • « HEKIMA PHARMA » : activité « non renseigné » dans le Super Admin,
--      pas de champ date de péremption dans le formulaire d'article ;
--    • « Pressing Test Biashara » et « Pressing Jean-Luc Takalashi » :
--      également « non renseigné » ;
--    • l'écran Super Admin « Type d'activité » ne propose QUE boutique et
--      distribution.
--
--  CAUSE
--    Il existe DEUX notions différentes, et la migration 0154 les a
--    mélangées :
--
--      1. `entreprises.type_activite` = l'AXE COMMERCIAL :
--         « boutique » ou « distribution ». C'est ce que propose le Super
--         Admin, et c'est ce que lit `TypeActiviteService` côté application.
--
--      2. `espaces.type` = le MÉTIER :
--         boutique, pharmacie, pressing, hotel, restaurant, depot,
--         boulangerie… C'est LUI qui porte le profil de modules
--         (`types_espaces_modules`) : `lots_expiration` pour la pharmacie,
--         `chambres` pour l'hôtel, `press_*` pour le pressing.
--
--    En faisant lire `entreprises.type_activite` EN PREMIER (0154), un
--    pressing ou une pharmacie devaient écrire « pressing »/« pharmacie »
--    dans une colonne qui ne connaît que boutique/distribution : d'où
--    « non renseigné » dans l'administration, et des modules faux.
--
--  CE QUE FAIT CE SCRIPT (idempotent, aucune donnée supprimée)
--    1. `rpc_mes_modules()` v5 :
--         métier = `espaces.type` de l'espace de travail (le vrai métier),
--         sinon `entreprises.type_activite` s'il désigne un métier connu,
--         sinon « boutique ».
--       Le pack de l'abonnement et la garantie des 3 écrans du pressing
--       sont conservés à l'identique.
--    2. Verdict en UNE ligne : pour chaque entreprise → métier de l'espace,
--       axe commercial, et les modules qui seront réellement servis.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);


-- ============================================================================
--  1. `rpc_mes_modules()` v5 — LE MÉTIER VIENT DE L'ESPACE
-- ============================================================================

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

  -- 3. LE MÉTIER — l'ESPACE fait foi (pharmacie, pressing, hôtel…).
  --    ⚠️ 0159 : on revient à l'ordre naturel. `entreprises.type_activite`
  --    ne sert plus que de repli, pour les comptes anciens dont l'espace
  --    n'a pas encore de type spécialisé.
  if v_type_esp is not null then
    select t.libelle, t.modules into v_libelle, v_modules
      from public.types_espaces_modules t
     where t.type = v_type_esp
       and t.actif;

    if v_modules is not null and jsonb_typeof(v_modules) = 'array' then
      v_type   := v_type_esp;
      v_source := 'espace';
    else
      v_modules := null;
    end if;
  end if;

  -- 3 bis. Repli : l'axe commercial de l'entreprise, s'il désigne un métier.
  if v_modules is null and v_type_ent is not null then
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
  '0159 — modules effectifs : MÉTIER de l''ESPACE de travail d''abord (pharmacie, pressing, hôtel…), puis axe commercial de l''entreprise, ∩ pack, + garantie des écrans du pressing.';

revoke all on function public.rpc_mes_modules() from public;
revoke all on function public.rpc_mes_modules() from anon;
grant execute on function public.rpc_mes_modules() to authenticated;


-- ============================================================================
--  2. RÉPARATION — L'AXE COMMERCIAL REDEVIENT VALIDE
-- ============================================================================
--  0153/0154/0157/0158 ont écrit des MÉTIERS (« pressing », « pharmacie »)
--  dans `entreprises.type_activite`, une colonne qui ne connaît que
--  boutique/distribution. Résultat : le Super Admin affiche « Non renseigné »
--  et `TypeActiviteService` ne sait plus quoi masquer.
--
--  Une pharmacie, un pressing, un hôtel… sont commercialement des BOUTIQUES
--  (ils vendent au comptoir). Leur métier, lui, vit dans `espaces.type` — et
--  c'est désormais lui qui pilote les modules (point 1 ci-dessus).

update public.entreprises
   set type_activite = 'boutique'
 where coalesce(btrim(type_activite), '') <> ''
   and lower(btrim(type_activite)) not in ('boutique', 'distribution');


-- ============================================================================
--  3. VERDICT — UNE SEULE LIGNE, TOUTES LES ENTREPRISES
-- ============================================================================

select jsonb_pretty(
  jsonb_build_object(
    'entreprises', (
      select coalesce(
               jsonb_agg(
                 jsonb_build_object(
                   'entreprise', e.nom,
                   'axe_commercial', e.type_activite,
                   'espaces', (
                     select coalesce(
                              jsonb_agg(
                                jsonb_build_object(
                                  'espace',  s.nom,
                                  'metier',  s.type,
                                  'modules_du_metier', (
                                    select t.modules
                                      from public.types_espaces_modules t
                                     where t.type = s.type and t.actif)
                                ) order by s.created_at),
                              '[]'::jsonb)
                       from public.espaces s
                      where s.entreprise_id = e.id)
                 ) order by e.created_at),
               '[]'::jsonb)
        from public.entreprises e),
    'a_faire', 'se déconnecter puis se reconnecter pour recharger les modules'
  )
) as verdict;
