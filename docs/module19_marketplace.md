# Module 19 — Biashara : marketplace local géolocalisé

> Migration : `supabase/migrations/20260916000040_module19_marketplace.sql`
> Version applicative : 2.2.0+23
> Aucune release publiée à ce stade (politique : release unique finale).

---

## 1. Objectif

Permettre à **n'importe qui, même sans compte**, de chercher un produit et de
découvrir **les commerces qui le vendent autour de lui** : prix, boutique,
distance, itinéraire. Les commerçants, eux, mesurent la visibilité que
Biashara leur apporte et peuvent préparer des campagnes publicitaires.

La promesse centrale tient en quatre mots, affichés partout :

**Produit → Prix → Boutique → Distance**

---

## 2. Principes non négociables (tenus par l'architecture)

| Principe | Comment c'est garanti |
|---|---|
| Aucune régression | `produits`, `ventes`, `caisse`, `depenses`, `clients`, `dettes`, `conditionnements` **ne sont pas modifiées**. On ajoute des colonnes à `espaces` et **7 nouvelles tables**. |
| Aucune fuite de données privées | Le catalogue public ne lit **jamais** les tables directement : tout passe par des RPC `security definer` qui n'exposent qu'une **liste blanche** de colonnes. `anon` n'a **aucun `select`** sur les tables du module. |
| Vie privée du visiteur | La position sert **uniquement** à calculer des distances, n'est **jamais transmise** au serveur, **jamais stockée**. Les statistiques ne retiennent qu'une **tranche** (`<1`, `1-3`, `3-10`, `>10`). |
| Fonctionne sans géolocalisation | « Rechercher dans une ville » donne exactement le même service. Refuser la position ne dégrade rien. |
| Classement transparent | Le score de pertinence ne dépend **que** de la correspondance du texte, de la distance, de la complétude de la fiche et de la disponibilité. Jamais de la taille de l'entreprise, de son ancienneté ou de ses revenus. |
| Publicité honnête | Les annonces vivent dans un **tableau séparé** (`publicites`), sont affichées dans un **emplacement dédié** et portent **toujours** la mention « PUBLICITÉ ». Jamais mélangées aux résultats organiques. |
| Conversion honnête | Une consultation **n'est jamais** comptée comme un achat. La conversion n'apparaît qu'avec un **code d'attribution** réellement utilisé. |
| Aucune clé d'API dans l'application | Carte = tuiles **OpenStreetMap** ; recherche d'adresse = **Nominatim**. Aucun secret, aucune facturation. |

---

## 3. Modèle de données (migration 40)

### 3.1 Colonnes ajoutées à `espaces` (vitrine publique)

`description_publique`, `telephone_public`, `whatsapp`, `horaires` (jsonb),
`logo_url`, `photo_url`, `adresse`, `quartier`, `avenue`, `numero`,
`point_repere`, `latitude`, `longitude`, `precision_localisation`
(`gps|carte|adresse|manuelle`), `statut_localisation`
(`non_renseignee|a_verifier|verifiee`), `localisation_maj_le`,
`visible_publiquement`, `slug`.

Contraintes : bornes géographiques (latitude −90…90, longitude −180…180,
couple lat/lng cohérent), format de slug, index unique partiel sur `slug`,
index partiel sur les boutiques publiées et géolocalisées.

Un **déclencheur** génère le slug dès qu'une boutique devient publique et
horodate la localisation à chaque modification de position/adresse.

### 3.2 Nouvelles tables

| Table | Rôle |
|---|---|
| `produits_publications` | Quels articles sont **publiés dans le catalogue public** (prix public, unité, texte d'accroche, photo, mots-clés, disponibilité déclarée). `produits` n'est jamais modifiée. |
| `recherches_publiques` | Volume de recherches : texte normalisé (≤ 120 car.), ville, catégorie, nb de résultats, tri. **Aucune donnée personnelle.** |
| `biashara_evenements` | Analytique de visibilité (impression, vue, recherche, itinéraire, appel, WhatsApp, partage, conversion), rangée en tranche de distance, rattachée à la **boutique**. |
| `publicites` | Campagnes (titre, message, type, produit, visuel, prix promo, dates, budget, plafond, statut, compteurs). `mention` = « PUBLICITÉ » par défaut. |
| `publicite_cibles` | Ciblage : ville, quartier, rayon (avec centre), catégorie. |
| `publicite_evenements` | Impressions / clics / conversions d'une campagne. |
| `liens_attribution` | Codes `BIA-XXXXXX` (QR, lien de suivi, code promotionnel). |

### 3.3 Vue publique

`v_biashara_boutiques` : **liste blanche** des informations publiques d'une
boutique (nom, type, contacts publics, horaires, adresse, position, ville,
patron résolu par jointure). Elle n'est lisible par **personne**
(`revoke all` sur `public`, `anon`, `authenticated`) : seules les RPC
`security definer` s'en servent.

Filtre : `visible_publiquement` **et** `actif` **et** géolocalisée **et**
compte **validé** (`activation_etape in ('actif','restreint')`) **et** non
suspendu.

---

## 4. Politique de visibilité & d'activation

- Un commerçant dont le dossier est **en attente de vérification** peut
  **préparer entièrement** sa vitrine : il ne doit pas être bloqué pendant
  l'instruction.
- Un compte **rejeté** ou **suspendu** ne peut plus écrire dans le module
  (déclencheurs sur `espaces`, `produits_publications`, `publicites`,
  `publicite_cibles`, `liens_attribution`).
- La **visibilité publique** n'est effective qu'à l'**activation** : l'écran
  « Ma vitrine » affiche alors honnêtement « vitrine prête, publication dès
  l'activation » (`compte_operationnel`, `visible_effectivement`).

---

## 5. API serveur (22 RPC)

### 5.1 Publiques — accordées à `anon` **et** `authenticated`

| RPC | Rôle |
|---|---|
| `rpc_biashara_accueil(lat, lng, ville, limite)` | Page d'accueil publique : catégories populaires, produits autour de vous, boutiques proches, publicités séparées. |
| `rpc_biashara_rechercher(texte, lat, lng, ville, tri, catégorie, limite, décalage, enregistrer)` | Recherche publique. Tri : `pertinence` (défaut), `distance`, `prix`. Renvoie aussi `publicites` **à part**. |
| `rpc_biashara_boutique(slug, lat, lng, limite)` | Fiche boutique **partageable** (`/biashara/boutique/<slug>`) + produits publiés. |
| `rpc_biashara_produit(publication_id, lat, lng, limite)` | Fiche produit + **comparaison des prix** entre boutiques correspondantes. |
| `rpc_biashara_boutiques_proches(lat, lng, ville, limite, rayon)` | Boutiques les plus proches (accueil public, carte, « Autour de moi »). |
| `rpc_biashara_categories(ville, limite)` / `rpc_biashara_villes()` | Catégories populaires / villes où des boutiques sont publiées. |
| `rpc_biashara_evenement(type, entité, id, publicité, ville, quartier, distance, recherche)` | Enregistre un événement de visibilité (types whitelistés, distance convertie en tranche). |
| `biashara_publicites_servir(contexte)` | Annonces actives correspondant au contexte (ville, catégorie, rayon). |

Helpers purs : `distance_km` (Haversine — **PostGIS non requis**),
`biashara_normaliser`, `biashara_slugifier`, `biashara_tranche_distance`,
`biashara_categorie_evenement`.

### 5.2 Commerçant — `authenticated` uniquement (propriété revérifiée)

`rpc_biashara_boutique_etat`, `rpc_biashara_boutique_enregistrer`,
`rpc_biashara_publications_lister`, `rpc_biashara_publication_enregistrer`,
`rpc_biashara_publication_lot`, `rpc_biashara_visibilite`,
`rpc_biashara_attribution_lister|creer|supprimer`,
`rpc_biashara_publicite_enregistrer`, `rpc_biashara_publicites_lister`,
`rpc_biashara_publicite_statut`, `rpc_biashara_publicites_moderation`
(réservée à la plateforme : `est_plateforme()`).

Chaque RPC vérifie que l'espace visé appartient bien à l'entreprise de
l'appelant — un identifiant d'espace forgé ne donne rien.

### 5.3 Permissions

Les pages `publications`, `visibilite` et `publicites` ont été ajoutées à
`pages_permissions()` et `permissions_defaut()` (PROPRIÉTAIRE : tout ;
SUPER_ADMIN : tout). La matrice **Dart** reste l'autorité pour l'interface.

---

## 6. Sécurité (RLS)

- `espaces` : lecture seule pour les membres de l'entreprise (policy du
  module 15) ; **toutes les écritures** du module 19 passent par
  `rpc_biashara_boutique_enregistrer`.
- Nouvelles tables : RLS **activée**, lecture pour le propriétaire (et la
  plateforme), **écritures révoquées** (RPC seulement), **aucun accès `anon`**.
- `recherches_publiques`, `biashara_evenements`, `publicite_evenements` :
  alimentées exclusivement par les RPC `security definer`.

**Ne sont jamais publiés** : `prix_achat`, stock exact, marges, clients,
dettes, dépenses, données d'audit, informations internes.

---

## 7. Application (Flutter)

### Point d'entrée — « Marketplace d'abord »

Un téléphone **sans compte, sans session et sans utilisateur local** est très
probablement celui d'un simple client. Au démarrage, `_handleStartup()`
(`lib/main.dart`) ouvre donc directement **`/biashara`** : le visiteur découvre
le catalogue sans jamais croiser un formulaire d'inscription. La page publique
contient elle-même les deux portes commerçant :

- **« Se connecter »** (en-tête) → `/login` ;
- **« Enregistrer ma boutique »** (bloc commerçants, présent aussi bien dans
  l'état vide que dans l'état d'erreur réseau) → `/setup`.

Aucun écran public n'est une impasse : si la base n'est pas encore migrée, la
page affiche le message explicite « *Le catalogue public « Biashara » n'est pas
encore installé sur la base…* » + **Réessayer**, et laisse les accès commerçant.

### 7.1 Pages publiques (sans compte)

| Route | Écran |
|---|---|
| `/biashara` | Page Welcome : hero + recherche + « Autour de moi », catégories populaires, produits autour de vous, boutiques à proximité, bloc commerçants, emplacement publicitaire. |
| `/biashara/recherche?q=&categorie=&tri=` | Résultats : tri (Plus proche / Prix le plus bas / Pertinence), **comparaison des prix**, chargement progressif. |
| `/biashara/boutique/:slug` | Fiche boutique partageable : adresse lisible par un étranger, point de repère, horaires, appel/WhatsApp, itinéraire, partage, produits. |
| `/biashara/produit/:id` | Fiche produit : photo, prix + unité, disponibilité, boutique + distance, **comparaison des prix**, itinéraire, partage. |
| `/biashara/carte` | Carte interactive OpenStreetMap : position du visiteur (si autorisée), marqueurs des boutiques, fiche du marqueur sélectionné. |

### 7.2 Pages commerçant

| Route | Écran | Permission |
|---|---|---|
| `/main/vitrine` | Localisation guidée (3 options + confirmation), adresse détaillée, horaires, contacts publics, visuels, aperçu public, publication. | `publications` |
| `/main/publications` | Articles publiés / non publiés, filtres, complétude, réglage par article, actions groupées, bascule rapide. | `publications` |
| `/main/visibilite` | « Ma visibilité Biashara » : 4 niveaux (visibilité / intérêt / intention / conversion), graphique journalier, produits les plus consultés, recherches, codes d'attribution. | `visibilite` |
| `/main/publicites` (+ `new`, `:id`) | Campagnes : brouillon → soumise → active / pause / terminée, ciblage ville / quartier / catégorie / rayon. | `publicites` |
| `/admin/publicites` | Modération plateforme : activer ou refuser les campagnes soumises. | `publicites` |

### 7.3 Parcours de localisation (exigence §4)

1. **Option A** — « Utiliser ma position actuelle » (GPS, avec consentement) ;
2. **Option B** — « Choisir ma position sur la carte » (repère posé au doigt) ;
3. **Option C** — « Rechercher mon adresse » (Nominatim, sans clé) ;

puis la **confirmation** : « Cette position correspond-elle bien à
l'emplacement de votre boutique ? ». Sans réponse positive, la position reste
« à confirmer » — et l'écran public le dit honnêtement. Un **aperçu public**
montre exactement ce que verront les clients avant l'enregistrement final.

---

## 8. Dépendances ajoutées

| Paquet | Usage | Risque plateforme |
|---|---|---|
| `flutter_map` + `latlong2` | Carte interactive (tuiles OpenStreetMap) | Dart pur : mobile, web, Linux, Windows — **aucune clé d'API**. |
| `geolocator` | Position du visiteur/commerçant | Android/iOS/web/Windows ; **pas d'implémentation Linux** → repli propre (message + choix sur la carte). |
| `http` | Recherche d'adresse (Nominatim) | Dart pur. |

**Permissions déclarées** (demandées par le système **uniquement** quand le
visiteur touche « Autour de moi », jamais au démarrage) :

| Plateforme | Fichier | Déclaration |
|---|---|---|
| Android | `android/app/src/main/AndroidManifest.xml` | `ACCESS_COARSE_LOCATION`, `ACCESS_FINE_LOCATION` |
| iOS | `ios/Runner/Info.plist` | `NSLocationWhenInUseUsageDescription` |

Un refus laisse l'application entièrement fonctionnelle : repli « Choisir une
ville » ou position posée sur la carte.

---

## 9. Ce qui reste à faire côté utilisateur

1. **Exécuter la migration 40** dans le SQL Editor Supabase (DDL + RPC
   impossibles via PostgREST). Elle est **idempotente** et se termine par des
   requêtes de vérification (`tables_marketplace`, `colonnes_geo`,
   `page_publications`, matrice PROPRIÉTAIRE, test de `distance_km`).
2. Vérifier que le bucket **`boutiques`** a bien été créé (il l'est par la
   migration) : il stocke les logos et photos de devanture.
3. Tester le parcours complet depuis un téléphone :
   - Ma vitrine → position (GPS) → confirmation → enregistrer ;
   - Mes publications → publier 2-3 articles ;
   - ouvrir `/biashara` depuis un navigateur **sans être connecté** ;
   - rechercher un produit, comparer les prix, demander l'itinéraire ;
   - revenir sur « Ma visibilité » : les compteurs d'affichage doivent monter.

---

## 10. Limites assumées

- **Pas de PostGIS** : les distances sont calculées par Haversine. Suffisant à
  cette échelle ; l'API ne changerait pas si l'on passait à PostGIS plus tard.
- **Recherche textuelle par `like`** sur une expression normalisée. Des index
  trigrammes pourront être ajoutés quand le catalogue dépassera quelques
  dizaines de milliers d'articles.
- **Nominatim** est un service public : usage occasionnel (saisie manuelle du
  commerçant). Un géocodeur commercial pourra le remplacer sans changer l'API.
- **Encaissements non rattachés à la caisse** pour les conversions : les codes
  d'attribution enregistrent l'intention et la conversion, l'intégration au
  module 8 (`rpc_vente_valider`) est une évolution dédiée — elle n'a
  volontairement pas été touchée.
- **Facturation publicitaire** : le budget est indicatif ; aucune dépense n'est
  prélevée automatiquement (Biashara contacte le commerçant avant diffusion
  payante).

---

## 11. Vérifications effectuées

- Migration validée par le parseur `pgsql-parser` + `plpgsql-parser` :
  **251/251 instructions valides** (syntaxe SQL **et** corps PL/pgSQL).
- `dart analyze lib` : **0 erreur** (183 issues préexistantes, en baisse).
- `flutter analyze --no-fatal-infos --no-fatal-warnings` : **exit 0, 0 erreur**
  — exactement le seuil appliqué par l'intégration continue.
- `flutter test` : **678/678 tests verts**, dont **54 nouveaux** cas dédiés au
  module (`test/marketplace_test.dart`).
