-- ============================================================================
--  biashara_yangu — MIGRATION 0155 : UN SEUL RÉSULTAT, UNE SEULE VÉRITÉ
--
--  POURQUOI
--    Le SQL Editor n'affiche par défaut que le DERNIER jeu de résultats. Les
--    diagnostics des migrations 0152 → 0154 étaient donc perdus, et l'on
--    corrigeait à l'aveugle.
--
--  CE QUE FAIT CE SCRIPT
--    1. Extrait la logique de `rpc_mes_modules()` dans une fonction
--       réutilisable : `modules_pour_utilisateur(uuid)`. Comportement
--       IDENTIQUE à la version 0154 (entreprise d'abord, espace ensuite,
--       ∩ pack, garantie des modules métier du pressing).
--    2. `rpc_mes_modules()` devient un simple emballage (même réponse).
--    3. `diag_modules_pour_email(text)` : renvoie en UNE ligne tout ce qui
--       décide de l'accueil (compte, entreprise/métier, pack, espaces,
--       modules calculés, verdict).
--    4. Le DERNIER ordre du script est CE diagnostic → ce que vous verrez
--       est exactement ce que l'application recevra.
--
--  ⚠️ IDEMPOTENT. Aucune donnée modifiée par ce script.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);


-- ============================================================================
--  1. LA LOGIQUE DEVIENT UNE FONCTION RÉUTILISABLE
-- ============================================================================

create or replace function public.modules_pour_utilisateur(p_user uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_esp      uuid;
  v_type_esp text;
  v_type_ent text;
  v_type     text;
  v_libelle  text;
  v_modules  jsonb;
  v_pack     jsonb;
  v_source   text := 'profil';
  v_filtres  jsonb;
  v_mod      text;
  v_metier   text[] := array['press_depots', 'press_atelier', 'press_retraits'];
begin
  if p_user is null then
    raise exception 'SESSION_ABSENTE|Aucun compte à analyser.';
  end if;

  -- 0. Espace de travail — mêmes règles que `mon_proprietaire()`, mais pour
  --    l'utilisateur demandé (la fonction est aussi utilisée par le diagnostic).
  select coalesce(
           (select u.espace_actif_id
              from public.utilisateurs u
             where u.id = p_user
               and u.espace_actif_id is not null
               and exists (select 1 from public.espaces sx
                            where sx.id = u.espace_actif_id
                              and sx.actif
                              and sx.entreprise_id = u.entreprise_id)),
           (select coalesce(u.parent_id, u.id)
              from public.utilisateurs u where u.id = p_user))
    into v_esp;

  -- 1. Métier lisible sur l'espace + pack souscrit.
  select s.type, e.type_activite, g.modules
    into v_type_esp, v_type_ent, v_pack
    from public.espaces s
    left join public.entreprises e on e.id = s.entreprise_id
    left join public.groupes_tarifaires g on g.id = e.groupe_tarifaire_id
   where s.id = v_esp;

  -- 2. Repli : première boutique du compte.
  if v_type_esp is null and v_type_ent is null then
    select s.type, e.type_activite, g.modules
      into v_type_esp, v_type_ent, v_pack
      from public.utilisateurs u
      join public.espaces s on s.entreprise_id = u.entreprise_id
      left join public.entreprises e on e.id = s.entreprise_id
      left join public.groupes_tarifaires g on g.id = e.groupe_tarifaire_id
     where u.id = p_user
     order by s.created_at
     limit 1;
  end if;

  -- 3. LE MÉTIER — l'entreprise fait foi, l'espace sert de repli.
  if v_type_ent is not null then
    select t.libelle, t.modules into v_libelle, v_modules
      from public.types_espaces_modules t
     where t.type = v_type_ent and t.actif;

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
     where t.type = v_type_esp and t.actif;

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
     where t.type = 'boutique' and t.actif;
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

comment on function public.modules_pour_utilisateur(uuid) is
  '0155 — modules effectifs d''un compte : métier de l''entreprise (puis espace), ∩ pack, + garantie des modules métier du pressing.';

revoke all on function public.modules_pour_utilisateur(uuid) from public, anon;
grant execute on function public.modules_pour_utilisateur(uuid) to authenticated;


-- ============================================================================
--  2. `rpc_mes_modules()` — MÊME RÉPONSE QU'AVANT (emballage)
-- ============================================================================

create or replace function public.rpc_mes_modules()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour charger vos modules.';
  end if;

  return public.modules_pour_utilisateur(auth.uid());
end;
$$;

comment on function public.rpc_mes_modules() is
  '0155 — modules effectifs de la session : délègue à modules_pour_utilisateur(auth.uid()).';

revoke all on function public.rpc_mes_modules() from public, anon;
grant execute on function public.rpc_mes_modules() to authenticated;


-- ============================================================================
--  3. LE DIAGNOSTIC EN UNE SEULE LIGNE
-- ============================================================================
--    Réservé à l'éditeur SQL (postgres) : la fonction n'est PAS exposée aux
--    applications (elle lit le dossier d'un compte à partir de son e-mail).

create or replace function public.diag_modules_pour_email(p_email text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_id     uuid;
  v_res    jsonb;
  v_ent    uuid;
  v_ent_nom text;
  v_metier text;
  v_pack   jsonb;
  v_esp    text;
  v_esp_actif text;
  v_espaces jsonb;
  v_mods   jsonb;
  v_type   text;
begin
  select u.id, u.entreprise_id into v_id, v_ent
    from public.utilisateurs u
   where lower(u.email) = lower(btrim(coalesce(p_email, '')))
   order by u.created_at
   limit 1;

  if v_id is null then
    -- recherche tolérante (prénom, e-mail partiel)
    select u.id, u.entreprise_id into v_id, v_ent
      from public.utilisateurs u
     where lower(u.email) like '%' || lower(btrim(coalesce(p_email, ''))) || '%'
     order by u.created_at
     limit 1;
  end if;

  if v_id is null then
    return jsonb_build_object(
      'verdict', '❌ Aucun compte pour cet e-mail',
      'recherche', p_email);
  end if;

  select e.nom, e.type_activite, g.modules
    into v_ent_nom, v_metier, v_pack
    from public.entreprises e
    left join public.groupes_tarifaires g on g.id = e.groupe_tarifaire_id
   where e.id = v_ent;

  select coalesce(jsonb_agg(jsonb_build_object(
           'espace', s.nom,
           'type',   coalesce(s.type, '(vide)'),
           'actif',  s.actif,
           'actif_du_compte', s.id = (select u2.espace_actif_id
                                        from public.utilisateurs u2
                                       where u2.id = v_id))), '[]'::jsonb)
    into v_espaces
    from public.espaces s
   where s.entreprise_id = v_ent;

  v_res := public.modules_pour_utilisateur(v_id);

  v_type := v_res ->> 'type';
  v_mods := v_res -> 'modules';

  select s.nom || ' → ' || coalesce(s.type, '(vide)')
    into v_esp
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
   where u.id = v_id;

  select s.nom || ' → ' || coalesce(s.type, '(vide)')
    into v_esp_actif
    from public.utilisateurs u
    left join public.espaces s on s.id = u.espace_actif_id
   where u.id = v_id;

  return jsonb_build_object(
    'compte_id',         v_id,
    'entreprise',        v_ent_nom,
    'entreprise_metier', coalesce(v_metier, '(non renseigné)'),
    'pack_modules',      coalesce(v_pack, '[]'::jsonb),
    'espace_actif',      coalesce(v_esp_actif, '(aucun)'),
    'espace_lu',         coalesce(v_esp, '(aucun)'),
    'espaces',           v_espaces,
    'profil_retenu',     v_type,
    'libelle_profil',    v_res ->> 'libelle',
    'source',            v_res ->> 'source',
    'modules_renvoyes',  v_mods,
    'cartes_metier', (
      select coalesce(jsonb_agg(x), '[]'::jsonb)
        from jsonb_array_elements_text(coalesce(v_mods, '[]'::jsonb)) as x
       where x in ('press_depots', 'press_atelier', 'press_retraits',
                   'clients', 'caisse', 'finance', 'rapports', 'assistant_ia',
                   'ventes', 'produits', 'stock', 'chambres', 'tables')
    ),
    'verdict', case
      when v_type = 'pressing' and coalesce(v_mods, '[]'::jsonb) ? 'press_depots'
        then '✅ Profil pressing servi à l''application'
      when v_type = 'pressing'
        then '⚠️ Profil pressing mais module press_depots absent (pack ?)'
      else '❌ Profil « ' || coalesce(v_type, '?') || ' » servi — le métier n''est pas appliqué'
    end
  );
end;
$$;

comment on function public.diag_modules_pour_email(text) is
  '0155 — diagnostic : tout ce qui décide de l''accueil d''un compte (entreprise, pack, espaces, modules calculés, verdict). Éditeur SQL uniquement.';

-- Volontairement PAS accordé aux applications : réservé à l'éditeur SQL.
revoke all on function public.diag_modules_pour_email(text) from public, anon, authenticated;


-- ============================================================================
--  4. LE SEUL RÉSULTAT QUE VOUS VERREZ (le diagnostic est le DERNIER ordre)
-- ============================================================================

select jsonb_pretty(
         public.diag_modules_pour_email('lucjean@gmail.com') -> 'verdict'
       ) as verdict;

select jsonb_pretty(
         public.diag_modules_pour_email('lucjean@gmail.com')
       ) as diagnostic_lucjean;
