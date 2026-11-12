-- ============================================================================
--  biashara_yangu — MIGRATION 0162 : LE PROFIL PRESSING COMPLET
--
--  CE QUE LE VERDICT DE 0161 A MONTRÉ (12/11/2026)
--    Les deux pressings ont bien le bon métier (`espaces.type = 'pressing'`)
--    et un profil trouvé… mais ce profil ne contient que :
--        clients, caisse, finance, employes, rapports, assistant_ia,
--        press_depots, press_atelier, press_retraits
--
--    Il MANQUE : ventes, produits, stock, qr.
--    D'où l'accueil réduit à quelques compteurs : sans `produits` ni `stock`
--    ni `ventes`, les cartes Catalogue / Stock / Ventes n'existent pas.
--
--  POURQUOI CE PROFIL EST INCOMPLET
--    `0161` n'ajoute que les types ABSENTS (`on conflict do nothing`) pour ne
--    jamais écraser un profil personnalisé. Or le profil « pressing » existait
--    déjà, écrit par une migration antérieure avec une liste réduite : il n'a
--    donc pas été complété.
--
--  CE QUE FAIT CE SCRIPT (idempotent, AUCUN module retiré)
--    Il AJOUTE au profil « pressing » les quatre modules commerciaux qui lui
--    manquent, en conservant tout ce qui s'y trouve déjà (y compris
--    d'éventuels ajouts de l'Expert). Union, jamais remplacement.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);


-- ============================================================================
--  1. UNION — on ajoute les manquants, on ne retire rien
-- ============================================================================

update public.types_espaces_modules t
   set modules = (
         select coalesce(jsonb_agg(distinct m order by m), '[]'::jsonb)
           from (
             select jsonb_array_elements_text(t.modules) as m
              union
             select unnest(array['ventes', 'produits', 'stock', 'qr'])
           ) fusion
       )
 where t.type = 'pressing';


-- ============================================================================
--  2. VERDICT — UNE SEULE LIGNE
-- ============================================================================

select jsonb_pretty(
  jsonb_build_object(
    'profil_pressing', (
      select jsonb_build_object(
               'modules',    t.modules,
               'nb_modules', jsonb_array_length(t.modules),
               'complet',    (t.modules ? 'ventes'
                              and t.modules ? 'produits'
                              and t.modules ? 'stock'
                              and t.modules ? 'qr'
                              and t.modules ? 'press_depots'
                              and t.modules ? 'press_atelier'
                              and t.modules ? 'press_retraits')
             )
        from public.types_espaces_modules t
       where t.type = 'pressing'),
    'a_faire',
      'Côté client : déconnexion puis reconnexion (ou changer d''entreprise) '
      'pour recharger le profil de modules.'
  )
) as verdict;
