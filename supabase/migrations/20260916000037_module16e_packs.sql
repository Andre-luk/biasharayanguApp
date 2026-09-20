-- ============================================================================
--  biashara_yangu — MODULE 16 (PHASE E) : ABONNEMENT PAR MODULES (PACKS)
--
--  OBJECTIF (roadmap multi-activités, phase E) :
--    Un PACK (groupe tarifaire) peut désormais limiter les modules
--    autorisés. Les modules EFFECTIFS d'un espace deviennent :
--
--        modules du profil de l'activité  ∩  modules du pack souscrit
--
--      • `groupes_tarifaires.modules` (jsonb) : liste des modules du pack ;
--        `[]` (défaut) = AUCUN filtre → tous les modules du profil
--        (comportement actuel — zéro régression) ;
--      • `rpc_mes_modules()` filtre désormais le profil par le pack ;
--      • l'écran admin « Groupes tarifaires » permet de cocher les modules
--        du pack (Essentiel, Avancé, Spécialisé…) ;
--      • intersection VIDE (pack vide ou incohérent) : le profil est
--        conservé (fail-open — on ne masque jamais tout par accident).
--
--  CONTENU :
--    1. colonne `groupes_tarifaires.modules` ;
--    2. `rpc_mes_modules()` v2 (profil ∩ pack) ;
--    3. vérifications.
--
--  OÙ : Supabase → SQL Editor → coller → Run
--  IDEMPOTENT : peut être relancé sans effet de bord.
-- ============================================================================


-- ============================================================================
--  1. COLONNE `public.groupes_tarifaires.modules`
-- ============================================================================
--  Tableau JSON de codes de modules (mêmes codes que `modules_catalogue()`).
--  '[]' = pack sans restriction de modules.

alter table public.groupes_tarifaires
  add column if not exists modules jsonb not null default '[]'::jsonb;

comment on column public.groupes_tarifaires.modules is
  'Module 16 E (packs) — modules autorisés par le pack ([] = tous les modules du profil de l''activité).';


-- ============================================================================
--  2. `rpc_mes_modules()` v2 — PROFIL ∩ PACK
-- ============================================================================
--  Copie de la fonction de la migration 27 + le filtre du pack :
--    • le pack vient de `espaces → entreprises.groupe_tarifaire_id →
--      groupes_tarifaires.modules` ;
--    • intersection NON VIDE uniquement (fail-open si pack incohérent) ;
--    • `source` devient « profil+pack » / « defaut+pack » quand filtré ;
--    • `pack_modules` renvoyé pour information (diagnostic).

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
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour charger vos modules.';
  end if;

  -- 1. Type de l'espace de travail actif + modules du PACK souscrit
  --    (module 16 E). `g.modules` vaut NULL si aucun pack : aucun filtre.
  v_espace := public.mon_proprietaire();

  select s.type, g.modules
    into v_type, v_pack
    from public.espaces s
    left join public.entreprises e on e.id = s.entreprise_id
    left join public.groupes_tarifaires g on g.id = e.groupe_tarifaire_id
   where s.id = v_espace;

  -- 2. Repli : première entreprise du compte.
  if v_type is null then
    select s.type, g.modules
      into v_type, v_pack
      from public.utilisateurs u
      join public.espaces s on s.entreprise_id = u.entreprise_id
      left join public.entreprises e on e.id = s.entreprise_id
      left join public.groupes_tarifaires g on g.id = e.groupe_tarifaire_id
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

  -- 6. PACK (module 16 E) — modules effectifs = profil ∩ pack.
  --    Un pack vide ('[]') ou incohérent (intersection vide) ne filtre
  --    RIEN : fail-open, on ne masque jamais tout par accident.
  if v_pack is not null
     and jsonb_typeof(v_pack) = 'array'
     and jsonb_array_length(v_pack) > 0 then

    select coalesce(jsonb_agg(t.v), '[]'::jsonb)
      into v_filtres
      from jsonb_array_elements_text(v_modules) as t(v)
     where t.v in (
       select p.v
         from jsonb_array_elements_text(v_pack) as p(v)
     );

    if jsonb_array_length(v_filtres) > 0 then
      v_modules := v_filtres;
      v_source  := v_source || '+pack';
    end if;
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
  'Module 16 — Modules effectifs de l''espace actif : profil de l''activité ∩ modules du pack souscrit (fail-open : jamais d''échec, jamais tout masquer).';


-- ============================================================================
--  3. VÉRIFICATIONS
-- ============================================================================

-- 3.a La colonne existe (attendu : 1 ligne, jsonb, défaut []).
select column_name, data_type, column_default
  from information_schema.columns
 where table_schema = 'public'
   and table_name = 'groupes_tarifaires'
   and column_name = 'modules';

-- 3.b Exemples (à exécuter avec de vrais identifiants) :
--     -- Pack « Essentiel » : ventes, caisse, stock, rapports.
--     update public.groupes_tarifaires
--        set modules = '["ventes","produits","stock","caisse","rapports"]'::jsonb
--      where nom = 'Essentiel';
--     -- Pack « Avancé » : + finance, clients, collaborateurs, IA.
--     update public.groupes_tarifaires
--        set modules = '["ventes","produits","stock","qr","caisse","clients","finance","employes","rapports","assistant_ia"]'::jsonb
--      where nom = 'Avancé';
--     -- Pack « Spécialisé » : tous les modules du métier (aucun filtre = []).
--     update public.groupes_tarifaires set modules = '[]'::jsonb
--      where nom = 'Spécialisé';

-- ============================================================================
--  FIN — Module 16 E (packs par modules). Un pack peut limiter les écrans
--  d'une activité (Essentiel / Avancé / Spécialisé) ; l'écran admin
--  « Groupes tarifaires » coche les modules du pack et l'accueil s'adapte
--  automatiquement (profil ∩ pack).
-- ============================================================================
