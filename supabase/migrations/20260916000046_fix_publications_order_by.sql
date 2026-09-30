-- ============================================================================
--  MODULE 21 quater — CORRECTIF « order by » APRÈS UNE AGRÉGATION
--  Migration 20260916000046_fix_publications_order_by.sql
-- ============================================================================
--
--  LE DÉFAUT, ET IL EST LE MÊME QUE CELUI DE LA MIGRATION 43
--  ---------------------------------------------------------
--  L'écran « Mes publications » (commerçant) échouait avec :
--
--      column "pb.publie" must appear in the group by clause
--      or be used in an aggregate function
--
--  Dans `rpc_biashara_publications_lister`, la seconde requête est une
--  AGRÉGATION (`jsonb_agg`) SANS `group by`, et elle se terminait par :
--
--      order by coalesce(pb.publie, false) desc, p.nom
--      limit v_limite offset v_decalage;
--
--  En PostgreSQL, dès qu'une requête contient une fonction d'agrégation sans
--  `group by`, TOUTE colonne citée hors agrégat est refusée — y compris dans
--  le `order by` extérieur. C'est le même mécanisme que l'erreur
--  « column s.entreprise must appear in the group by clause » de l'écran
--  Boutiques, corrigée par la migration 43.
--
--  Conséquence secondaire : la PAGINATION ne servait à rien non plus (une
--  agrégation scalaire renvoie une seule ligne ; le `limit` s'appliquait à
--  une ligne unique).
--
--  LE CORRECTIF
--  -----------
--  Toute la sélection — recherche, filtres, TRI, PAGINATION — est déplacée
--  DANS la sous-requête. La requête extérieure ne fait plus qu'agréger.
-- ============================================================================


create or replace function public.rpc_biashara_publications_lister(
  p_espace_id uuid default null,
  p_recherche text default null,
  p_filtre    text default 'tous',
  p_limite    integer default 100,
  p_decalage  integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_moi    uuid := public.mon_proprietaire();
  v_espace uuid := coalesce(p_espace_id, v_moi);
  v_q      text := public.biashara_normaliser(p_recherche);
  v_filtre text := lower(btrim(coalesce(p_filtre, 'tous')));
  v_limite integer := least(greatest(coalesce(p_limite, 100), 1), 300);
  v_decalage integer := greatest(coalesce(p_decalage, 0), 0);
  v_liste  jsonb := '[]'::jsonb;
  v_total  integer := 0;
  v_publies integer := 0;
begin
  if auth.uid() is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour gérer vos publications.';
  end if;

  if v_filtre not in ('tous', 'publies', 'non_publies', 'indisponibles') then
    v_filtre := 'tous';
  end if;

  -- Compteurs (agrégation scalaire sans colonne non agrégée : correct).
  select count(*),
         count(*) filter (where coalesce(pb.publie, false))
    into v_total, v_publies
    from public.produits p
    left join public.produits_publications pb on pb.produit_id = p.id
   where p.owner_id = v_espace
     and (v_q = '' or public.biashara_normaliser(
            p.nom || ' ' || coalesce(p.categorie, '')) like '%' || v_q || '%')
     and (
       v_filtre = 'tous'
       or (v_filtre = 'publies' and coalesce(pb.publie, false))
       or (v_filtre = 'non_publies' and not coalesce(pb.publie, false))
       or (v_filtre = 'indisponibles' and pb.publie and not pb.disponible)
     );

  -- ⚠️ CORRECTIF 46 : recherche, filtres, TRI et PAGINATION dans la
  -- sous-requête `s`. La requête extérieure n'agrège que `s`, donc plus
  -- aucune colonne non agrégée hors de `jsonb_agg` — et la pagination agit
  -- enfin sur les lignes.
  select coalesce(jsonb_agg(jsonb_build_object(
           'publication_id', s.publication_id,
           'produit_id',     s.produit_id,
           'nom',            s.nom,
           'categorie',      s.categorie,
           'photo',          s.photo,
           'prix_vente',     s.prix_vente,
           'prix_public',    s.prix_public,
           'unite',          s.unite,
           'description_courte', s.description_courte,
           'mots_cles',      s.mots_cles,
           'publie',         s.publie,
           'disponible',     s.disponible,
           'stock',          s.stock,
           'mis_a_jour_le',  s.mis_a_jour_le
         ) order by s.publie desc, s.nom), '[]'::jsonb)
    into v_liste
    from (
      select pb.id as publication_id,
             p.id  as produit_id,
             p.nom,
             nullif(btrim(p.categorie), '') as categorie,
             coalesce(pb.photo_url, p.photo) as photo,
             p.prix_vente,
             pb.prix_public,
             coalesce(nullif(btrim(pb.unite), ''), p.unite_mesure) as unite,
             pb.description_courte,
             pb.mots_cles,
             coalesce(pb.publie, false) as publie,
             coalesce(pb.disponible, false) as disponible,
             p.quantite as stock,
             pb.updated_at as mis_a_jour_le
        from public.produits p
        left join public.produits_publications pb on pb.produit_id = p.id
       where p.owner_id = v_espace
         and (v_q = '' or public.biashara_normaliser(
                p.nom || ' ' || coalesce(p.categorie, '')) like '%' || v_q || '%')
         and (
           v_filtre = 'tous'
           or (v_filtre = 'publies' and coalesce(pb.publie, false))
           or (v_filtre = 'non_publies' and not coalesce(pb.publie, false))
           or (v_filtre = 'indisponibles' and pb.publie and not pb.disponible)
         )
       order by coalesce(pb.publie, false) desc, p.nom
       limit v_limite offset v_decalage
    ) s;

  return jsonb_build_object(
    'ok', true,
    'espace_id', v_espace,
    'total', v_total,
    'nb_publies', v_publies,
    'articles', v_liste
  );
end;
$$;

comment on function public.rpc_biashara_publications_lister(uuid, text, text, integer, integer) is
  'Module 19/21 — Publications du commerçant (recherche, filtres, compteurs, pagination réelle). Correctif 46 : tri et pagination placés dans la sous-requête (erreur « pb.publie must appear in the group by clause » supprimée).';


revoke all on function public.rpc_biashara_publications_lister(uuid, text, text, integer, integer)
  from public, anon;
grant execute on function public.rpc_biashara_publications_lister(uuid, text, text, integer, integer)
  to authenticated;


-- ============================================================================
--  RECHERCHE DES AUTRES FONCTIONS ATTEINTES DU MÊME DÉFAUT
-- ============================================================================
--  Le motif est : une fonction qui contient `jsonb_agg`, AUCUN `group by`, et
--  un `order by` suivi d'un `limit` au niveau de la requête extérieure.
--  `suspect_fort = true` désigne les cas à corriger en priorité.

select p.proname as fonction,
       (pg_get_functiondef(p.oid) ~* E'\n[ \t]*order by[^;]*\n[ \t]*limit') as suspect_fort
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.prokind = 'f'
   and pg_get_functiondef(p.oid) like '%jsonb_agg%'
   and pg_get_functiondef(p.oid) not ilike '%group by%'
 order by suspect_fort desc, p.proname;


-- ============================================================================
--  VÉRIFICATION DU CORRECTIF — À LANCER SÉPARÉMENT, JAMAIS DANS LE MÊME RUN
-- ============================================================================
--  ⚠️ POURQUOI CETTE REQUÊTE EST COMMENTÉE
--  Le SQL Editor exécute TOUT le texte collé en UNE SEULE transaction. Une
--  requête qui échoue à la fin annule donc le `create or replace` du début :
--  la migration semble avoir tourné et la fonction reste inchangée.
--
--  Cette vérification exige une session utilisateur (`auth.uid()`), que le SQL
--  Editor n'a pas → elle échouerait toujours si on la collait avec le DDL.
--  Elle doit être lancée DANS UN RUN SÉPARÉ, après avoir posé la session.
--
--  Étape 1 — sélectionne et exécute SEULEMENT ceci pour vérifier la version
--  installée. Si `correctif_46_present` est FAUX, le DDL n'a pas été appliqué.
--
--    select (pg_get_functiondef(p.oid) like '%s.publie%')  as correctif_46_present,
--           (pg_get_functiondef(p.oid) like '%group by%')  as contient_group_by
--      from pg_proc p
--      join pg_namespace n on n.oid = p.pronamespace
--     where n.nspname = 'public'
--       and p.proname = 'rpc_biashara_publications_lister';
--
--  Étape 2 — la vérification fonctionnelle, session comprise (run séparé) :
--
--    select set_config('request.jwt.claims',
--      jsonb_build_object('sub', (select u.id from public.utilisateurs u
--                                  where lower(u.email) = 'ADRESSE_DU_COMMERCANT')::text,
--                         'role', 'authenticated')::text, false);
--
--    select jsonb_array_length(
--             public.rpc_biashara_publications_lister(null, null, 'tous', 20, 0) -> 'articles'
--           ) as articles_visibles,
--           (public.rpc_biashara_publications_lister(null, null, 'tous', 20, 0) ->> 'total') as total;
--
--  Le vrai test reste l'application : Paramètres → Ma vitrine Biashara →
--  « Mes publications ».

-- ============================================================================
--  FIN — module 21 quater.
-- ============================================================================
