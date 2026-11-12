-- ============================================================================
--  biashara_yangu — MIGRATION 0161 : TOUS LES MÉTIERS ONT UN PROFIL
--  (le pressing n'existait pas dans `types_espaces_modules`)
--
--  CONSTAT (12/11/2026)
--    « Le pressing n'a que 4 boutons de stats, pas autre chose. »
--
--  CAUSE
--    `rpc_mes_modules()` cherche le profil du métier dans
--    `types_espaces_modules`. Cette table a été créée par la migration 0027
--    avec SIX types : boutique, depot, hotel, pharmacie, restaurant, autre.
--    Les métiers ajoutés ENSUITE (pressing — module 35, boucherie, mode,
--    salon, salle des fêtes, boulangerie, distribution) ont chacun leur table,
--    leurs RPC, leurs écrans… mais AUCUN PROFIL DE MODULES :
--
--        select 1 from types_espaces_modules where type = 'pressing'  → 0
--
--    Résultat : pour un espace `pressing`, la fonction ne trouve rien, se
--    rabat sur l'axe commercial de l'entreprise (« boutique ») et l'accueil
--    n'affiche plus que les quelques cartes du profil boutique : les écrans
--    dépôts / atelier / retraits n'apparaissent jamais.
--    C'est aussi pourquoi « Changer le type » ne pouvait pas proposer
--    « Pressing » : le type n'existait pas dans le référentiel.
--
--  CE QUE FAIT CE SCRIPT (idempotent, AUCUN profil existant n'est écrasé)
--    1. Crée les profils manquants, en `on conflict do nothing` : un profil
--       personnalisé par l'Expert reste intact.
--    2. Verdict en UNE ligne : pour HEKIMA PHARMA et les deux pressings →
--       axe commercial, espaces, profil trouvé (ou « MANQUANT »), modules.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);


-- ============================================================================
--  1. LES PROFILS MANQUANTS
-- ============================================================================
--  `on conflict (type) do nothing` : on ne remplace JAMAIS un profil qui
--  existe déjà (l'Expert peut l'avoir adapté).

insert into public.types_espaces_modules (type, libelle, modules) values
  -- 🧺 MODULE 35 — le pressing ne vend pas des marchandises : il garde des
  -- vêtements. Ses trois écrans métier sont indispensables.
  ('pressing', 'Pressing & Blanchisserie',
   '["ventes","produits","stock","qr","caisse","clients","finance","employes","rapports","assistant_ia","press_depots","press_atelier","press_retraits"]'::jsonb),

  -- 📦 Distribution professionnelle (agents, tournées, consignes…)
  ('distribution', 'Distribution (production & tournées)',
   '["ventes","produits","stock","qr","caisse","clients","finance","employes","rapports","assistant_ia","distribution","production"]'::jsonb),

  -- 🥩 Boucherie (vente au poids)
  ('boucherie', 'Boucherie',
   '["ventes","produits","stock","qr","caisse","clients","finance","employes","rapports","assistant_ia","pesee","lots_expiration"]'::jsonb),

  -- 👕 Mode & vêtements (tailles / couleurs)
  ('mode', 'Mode & vêtements',
   '["ventes","produits","stock","qr","caisse","clients","finance","employes","rapports","assistant_ia","variantes"]'::jsonb),

  -- 💇 Salon de coiffure
  ('salon_de_coiffure', 'Salon de coiffure',
   '["ventes","produits","stock","qr","caisse","clients","finance","employes","rapports","assistant_ia"]'::jsonb),

  -- 🎉 Salle des fêtes
  ('salle_fetes', 'Salle des fêtes',
   '["ventes","produits","stock","qr","caisse","clients","finance","employes","rapports","assistant_ia","salles","evenements"]'::jsonb),

  -- 🥖 Boulangerie
  ('boulangerie', 'Boulangerie',
   '["ventes","produits","stock","qr","caisse","clients","finance","employes","rapports","assistant_ia","production","pesee"]'::jsonb)
on conflict (type) do nothing;


-- ============================================================================
--  2. SÉCURITÉ — CHAQUE ESPACE DOIT AVOIR UN PROFIL EXPLOITABLE
-- ============================================================================
--  Si un espace porte un métier qui n'a toujours pas de profil (type créé
--  directement en base, par exemple), on crée un profil « commerce » complet
--  plutôt que de le laisser retomber sur les 4 cartes du profil boutique.

insert into public.types_espaces_modules (type, libelle, modules)
select distinct
       lower(btrim(s.type)),
       initcap(replace(lower(btrim(s.type)), '_', ' ')),
       '["ventes","produits","stock","qr","caisse","clients","finance","employes","rapports","assistant_ia"]'::jsonb
  from public.espaces s
 where coalesce(btrim(s.type), '') <> ''
   and not exists (
         select 1 from public.types_espaces_modules t
          where t.type = lower(btrim(s.type)))
on conflict (type) do nothing;


-- ============================================================================
--  3. VERDICT — HEKIMA PHARMA ET LES DEUX PRESSINGS
-- ============================================================================

select jsonb_pretty(
  jsonb_build_object(
    'cibles', (
      select coalesce(
               jsonb_agg(
                 jsonb_build_object(
                   'entreprise',     e.nom,
                   'axe_commercial', coalesce(e.type_activite, 'NON RENSEIGNÉ'),
                   'espaces', (
                     select coalesce(
                              jsonb_agg(
                                jsonb_build_object(
                                  'espace', s.nom,
                                  'metier', s.type,
                                  'profil_trouve', exists (
                                    select 1 from public.types_espaces_modules t
                                     where t.type = s.type and t.actif),
                                  'modules', (
                                    select t.modules
                                      from public.types_espaces_modules t
                                     where t.type = s.type and t.actif)
                                ) order by s.created_at),
                              '[]'::jsonb)
                       from public.espaces s
                      where s.entreprise_id = e.id)
                 ) order by e.created_at),
               '[]'::jsonb)
        from public.entreprises e
       where lower(coalesce(e.nom, '')) like '%hekima%'
          or lower(coalesce(e.nom, '')) like '%pressing%'),
    'total_profils', (select count(*) from public.types_espaces_modules),
    'a_faire',
      'Puis : Super Admin → entreprise → « Changer le type » (pharmacie / '
      'pressing), et déconnexion/reconnexion côté client.'
  )
) as verdict;
