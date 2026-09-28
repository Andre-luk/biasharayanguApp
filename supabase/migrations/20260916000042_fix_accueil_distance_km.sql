-- ============================================================================
--  CORRECTIF 0042 — « column o.distance_km does not exist »
--  Migration 20260916000042_fix_accueil_distance_km.sql
-- ============================================================================
--
--  POURQUOI CETTE MIGRATION
--  ------------------------
--  À l'ouverture de l'application, la page publique Biashara Yangu appelait
--  `public.rpc_biashara_accueil(...)` et recevait :
--
--      column o.distance_km does not exist
--
--  CAUSE EXACTE (défaut d'alias, aucune donnée en cause)
--  Dans la fonction, la liste des produits est construite à partir d'une
--  sous-requête aliasée « o » :
--
--      from (
--        select ...,
--               public.distance_km(p_lat, p_lng, b.latitude, b.longitude) as distance
--        ...
--      ) o;
--
--  La colonne s'appelle donc **distance**, alors que le `jsonb_build_object`
--  extérieur demandait `o.distance_km` — nom qui n'existe pas dans cette
--  source. PostgreSQL refuse la requête à la compilation de la fonction :
--  l'écran public tombait donc systématiquement en erreur.
--
--  Autres appels vérifiés un par un (AUCUN autre défaut de ce type) :
--    • rpc_biashara_rechercher       : distance calculée en ligne        OK
--    • rpc_biashara_boutique         : « round(coalesce(v_distance…)) »  OK
--    • rpc_biashara_produit          : sous-requête aliasée distance_km  OK
--    • rpc_biashara_boutiques_proches: sous-requête aliasée distance     OK
--    • biashara_publicites_servir    : aucun usage de distance           OK
--
--  CE QUE FAIT CETTE MIGRATION
--  1. elle recrée `rpc_biashara_accueil` avec l'alias corrigé
--     (`'distance_km', round(o.distance::numeric, 2)` — la clé JSON reste
--     `distance_km`, c'est celle que lit l'application) ;
--  2. elle exécute un AUTO-CONTRÔLE de toutes les fonctions publiques du
--     module : chacune est réellement appelée, et le résultat est affiché
--     (OK / ÉCHEC + message). Ce contrôle détecte immédiatement toute erreur
--     SQL de cette famille, au lieu de la découvrir à l'ouverture de l'écran.
--
--  La migration 40 a été corrigée à la source dans le même mouvement : une
--  installation neuve est donc correcte, et cette migration répare les bases
--  où la 40 a déjà été exécutée. IDEMPOTENTE : rejouable sans effet.
-- ============================================================================


-- ============================================================================
--  1. RECRÉATION DE LA FONCTION D'ACCUEIL (alias corrigé)
-- ============================================================================

create or replace function public.rpc_biashara_accueil(
  p_lat      double precision default null,
  p_lng      double precision default null,
  p_ville_id uuid default null,
  p_limite   integer default 8
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_limite integer := least(greatest(coalesce(p_limite, 8), 1), 20);
  v_categories jsonb;
  v_produits jsonb := '[]'::jsonb;
  v_boutiques jsonb;
begin
  v_categories := public.rpc_biashara_categories(p_ville_id, 10) -> 'categories';
  v_boutiques := public.rpc_biashara_boutiques_proches(
                   p_lat, p_lng, p_ville_id, v_limite, null
                 ) -> 'boutiques';

  -- « Produits autour de vous » : les produits publiés les plus proches.
  select coalesce(jsonb_agg(jsonb_build_object(
           'publication_id', o.publication_id,
           'produit_id',     o.produit_id,
           'nom',            o.nom,
           'photo',          o.photo,
           'prix',           o.prix,
           'unite',          o.unite,
           'disponible',     o.disponible,
           'boutique_nom',   o.boutique_nom,
           'boutique_slug',  o.boutique_slug,
           'quartier',       o.quartier,
           'ville',          o.ville,
           -- ⚠️ CORRECTIF : la sous-requête aliase cette colonne « distance ».
           -- La clé JSON exposée reste `distance_km` (celle lue par l'app).
           'distance_km',    round(o.distance::numeric, 2)
         ) order by o.distance asc nulls last, o.nom), '[]'::jsonb)
    into v_produits
    from (
      select pb.id as publication_id, p.id as produit_id, p.nom,
             coalesce(pb.photo_url, p.photo) as photo,
             coalesce(pb.prix_public, p.prix_vente) as prix,
             coalesce(nullif(btrim(pb.unite), ''), p.unite_mesure) as unite,
             (pb.disponible and p.quantite > 0) as disponible,
             b.nom as boutique_nom, b.slug as boutique_slug, b.quartier, b.ville,
             public.distance_km(p_lat, p_lng, b.latitude, b.longitude) as distance
        from public.produits_publications pb
        join public.produits p on p.id = pb.produit_id
        join public.v_biashara_boutiques b on b.espace_id = pb.espace_id
       where pb.publie
         and (p_ville_id is null or b.ville_id = p_ville_id)
       order by distance asc nulls last, pb.updated_at desc
       limit v_limite
    ) o;

  return jsonb_build_object(
    'ok', true,
    'categories', coalesce(v_categories, '[]'::jsonb),
    'produits', v_produits,
    'boutiques', coalesce(v_boutiques, '[]'::jsonb),
    'publicites', public.biashara_publicites_servir(p_lat, p_lng, p_ville_id, null, 3)
  );
end;
$$;

comment on function public.rpc_biashara_accueil(double precision, double precision, uuid, integer) is
  'Module 19 — Données de la page d''accueil PUBLIQUE (catégories populaires, produits autour de vous, boutiques proches, publicités séparées). Correctif 0042 : alias de distance corrigé.';


-- ============================================================================
--  2. AUTO-CONTRÔLE DES FONCTIONS PUBLIQUES
-- ============================================================================
--  Chaque fonction publique du marketplace est RÉELLEMENT appelée. Une erreur
--  SQL (alias erroné, colonne absente, division par zéro…) apparaît donc
--  immédiatement dans les résultats de la migration, au lieu de se manifester
--  plus tard sur un écran de l'application.
--
--  Lecture du résultat : « OK » = la fonction s'exécute et renvoie du JSON ;
--  « ÉCHEC » = le message d'erreur est affiché tel quel (rien n'est masqué).

do $$
declare
  v_tests text[][] := array[
    array['rpc_biashara_accueil',          'select public.rpc_biashara_accueil(null, null, null, 3)'],
    array['rpc_biashara_categories',       'select public.rpc_biashara_categories(null, 5)'],
    array['rpc_biashara_villes',           'select public.rpc_biashara_villes()'],
    array['rpc_biashara_boutiques_proches','select public.rpc_biashara_boutiques_proches(null, null, null, 5, null)'],
    array['rpc_biashara_rechercher',       'select public.rpc_biashara_rechercher(null, null, null, null, ''pertinence'', null, 5, 0, false)'],
    array['biashara_publicites_servir',    'select public.biashara_publicites_servir(null, null, null, null, 3)']
  ];
  v_i      integer := 1;
  v_nom    text;
  v_sql    text;
  v_resultat jsonb;
  v_ok     integer := 0;
  v_ko     integer := 0;
begin
  loop
    exit when v_i > array_length(v_tests, 1);
    v_nom := v_tests[v_i][1];
    v_sql := v_tests[v_i][2];
    v_i := v_i + 1;

    begin
      execute v_sql into v_resultat;
      v_ok := v_ok + 1;
      raise notice 'OK    % → %', rpad(v_nom, 32), left(v_resultat::text, 90);
    exception when others then
      v_ko := v_ko + 1;
      raise warning 'ECHEC % → %', rpad(v_nom, 32), sqlerrm;
    end;
  end loop;

  raise notice 'AUTO-CONTRÔLE : % fonction(s) OK, % en échec.', v_ok, v_ko;
end $$;


-- ============================================================================
--  3. VÉRIFICATIONS AFFICHÉES DANS L'ÉDITEUR SQL
-- ============================================================================

-- 3.a L'accueil s'exécute réellement (attendu : « ok » = true), et la clé
--     `distance_km` est bien présente dans la charge utile des produits.
select
  (public.rpc_biashara_accueil(null, null, null, 3) ->> 'ok')::boolean as accueil_ok,
  jsonb_array_length(
    public.rpc_biashara_accueil(null, null, null, 3) -> 'produits'
  ) as nb_produits_retournes,
  case
    when jsonb_array_length(
           public.rpc_biashara_accueil(null, null, null, 3) -> 'produits'
         ) = 0
      then 'aucun produit publié (état vide normal si le catalogue est vide)'
    else coalesce(
      (public.rpc_biashara_accueil(null, null, null, 3) -> 'produits' -> 0)
        ? 'distance_km',
      false
    )::text
  end as cle_distance_km_presente;

-- 3.b Aucune référence fautive ne subsiste dans le corps des fonctions
--     publiques (recherche du motif exact qui provoquait l'erreur).
select
  count(*) as fonctions_avec_alias_fautif
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname in (
     'rpc_biashara_accueil', 'rpc_biashara_rechercher', 'rpc_biashara_boutique',
     'rpc_biashara_produit', 'rpc_biashara_boutiques_proches',
     'rpc_biashara_categories', 'rpc_biashara_villes'
   )
   and pg_get_functiondef(p.oid) like '%o.distance_km%';

-- ============================================================================
--  FIN — correctif « column o.distance_km does not exist ».
-- ============================================================================
