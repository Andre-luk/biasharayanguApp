-- ============================================================================
--  biashara_yangu — MODULE 16 (PHASE B) : PROFILS AFFINÉS PAR ACTIVITÉ
--
--  OBJECTIF (roadmap multi-activités, phase B) :
--    « Fini les cartes inutiles pour un hôtel » — le tableau de bord d'accueil
--    est désormais construit depuis les modules actifs (application), et les
--    profils des activités SPÉCIALISÉES sont affinés ici :
--
--      • Hôtel      : retire les modules de commerce de détail
--                     (ventes, produits, stock, QR) — remplacés par
--                     chambres/réservations/check-in (phase C2) ;
--      • Restaurant : retire « qr » (étiquettes produits).
--
--  ⚠️ SÉCURITÉ DES PERSONNALISATIONS :
--    chaque mise à jour n'est appliquée QUE si le profil est encore
--    STRICTEMENT celui du seed de la phase A. Si l'Expert Administrateur a
--    personnalisé le profil entre-temps, la migration ne touche à RIEN.
--
--  CONTEXTE : aucun espace n'utilise encore ces types (vérifié le 18/09/2026 :
--  seules les boutiques existent) → aucune entreprise impactée aujourd'hui ;
--  les prochains espaces « Hôtel »/« Restaurant » arriveront directement avec
--  le bon profil.
--
--  OÙ : Supabase → SQL Editor → coller → Run
--  IDEMPOTENT : relançable sans effet (2ᵉ exécution = « 0 ligne »).
-- ============================================================================


-- ============================================================================
--  1. HÔTEL — un hôtel n'est pas une boutique de détail
-- ============================================================================
update public.types_espaces_modules
   set modules    = '["clients","caisse","finance","employes","rapports","assistant_ia","chambres","reservations","checkin"]'::jsonb,
       updated_at = now()
 where type = 'hotel'
   -- Uniquement si le profil est encore celui du seed initial (phase A).
   and modules = '["ventes","produits","stock","qr","caisse","clients","finance","employes","rapports","assistant_ia","chambres","reservations","checkin"]'::jsonb;


-- ============================================================================
--  2. RESTAURANT — pas d'étiquettes produits (le QR reste aux commerces)
-- ============================================================================
update public.types_espaces_modules
   set modules    = '["ventes","produits","stock","caisse","clients","finance","employes","rapports","assistant_ia","tables","commandes","cuisine"]'::jsonb,
       updated_at = now()
 where type = 'restaurant'
   and modules = '["ventes","produits","stock","qr","caisse","clients","finance","employes","rapports","assistant_ia","tables","commandes","cuisine"]'::jsonb;


-- ============================================================================
--  3. VÉRIFICATIONS
-- ============================================================================

-- 3.a Les deux profils affinés (attendu : hôtel 9 modules, restaurant 11).
select t.type, t.libelle, t.actif, t.modules,
       jsonb_array_length(t.modules) as nb_modules
  from public.types_espaces_modules t
 where t.type in ('hotel', 'restaurant')
 order by t.type;

-- 3.b Les profils non spécialisés sont intacts (boutique 10, pharmacie 11,
--     dépôt 10, autre 10).
select t.type, jsonb_array_length(t.modules) as nb_modules
  from public.types_espaces_modules t
 where t.type in ('boutique', 'depot', 'pharmacie', 'autre')
 order by t.type;

-- ============================================================================
--  FIN — Phase B. L'application (v1.5.0) construit sa grille d'accueil depuis
--  les modules actifs : un hôtel verra « Clients, Caisse, Finance, Rapports »,
--  pas « Produits, Stock, Mes ventes ». Prochaine étape : phase C
--  (modules métier chambres / commandes / lots…).
-- ============================================================================
