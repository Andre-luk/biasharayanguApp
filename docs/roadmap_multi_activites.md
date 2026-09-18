# Biashara Yangu — Roadmap « Multi-activités » 📋

> **Objectif** : transformer Biashara d'une application de caisse en une **plateforme de gestion qui s'adapte à l'activité de chaque entreprise**.
> Le client choisit son activité → Biashara construit automatiquement son environnement : menus, tableau de bord, écrans métier et rapports.
>
> **Fil rouge** : `ACTIVITÉ → MODULES → PERMISSIONS → ABONNEMENT → TABLEAU DE BORD ADAPTÉ → OPÉRATIONS → RAPPORTS → FINANCE → AUDIT`

---

## 1. Le concept : « modules »

Un **module** est une unité fonctionnelle activable/désactivable :

| Module | Contenu | Existe déjà ? |
|---|---|---|
| `ventes` | Panier, encaissement, reçus | ✅ Modules 7/8 |
| `produits` | Articles, catégories, conditionnements | ✅ Module 5 |
| `stock` | Approvisionnements, ajustements, inventaire | ✅ Module 9 |
| `qr` | QR codes, étiquettes, scan | ✅ Modules 5/6/7 |
| `caisse` | Encaissements, clôtures | ✅ Modules 8/10 |
| `clients` | Fiches clients, dettes | ✅ Modules 8/10 |
| `finance` | Dépenses, dettes, bénéfices | ✅ Module 10 |
| `employes` | Collaborateurs, rôles | ✅ Modules 4/13 |
| `rapports` | Rapports & exports | ✅ Module 11 |
| `assistant_ia` | Assistant DeepSeek | ✅ Module 13 |
| **`chambres`** | Chambres, statuts, équipements | ❌ à créer |
| **`reservations`** | Réservations hôtel / salle des fêtes | ❌ à créer |
| **`checkin`** | Arrivées / départs, facturation séjour | ❌ à créer |
| **`tables`** | Plan de salle, occupation | ❌ à créer |
| **`commandes`** | Commandes restaurant (table → cuisine) | ❌ à créer |
| **`cuisine`** | Écran cuisine (préparation) | ❌ à créer |
| **`lots_expiration`** | Lots, dates de péremption (pharmacie/boucherie) | ❌ à créer |
| **`production`** | Production + matières premières (boulangerie) | ❌ à créer |
| **`pesee`** | Vente au poids (kg) | ❌ partiel (unités multiples ✓) |
| **`variantes`** | Tailles / couleurs (mode) | ❌ à créer |

---

## 2. Architecture technique

### 2.1 D'où viennent les modules d'une entreprise ?

**Décision de design** : les modules découlent du **TYPE DE L'ESPACE DE TRAVAIL** (`espaces.type` — Module 15 : `boutique`, `hotel`, `pharmacie`, `restaurant`, `depot`, `autre`).

Pourquoi ? Avec le pack multi-entreprises, un patron peut avoir **une boutique + un hôtel** : chaque espace a donc ses propres modules, et le sélecteur d'entreprise change aussi... l'application affichée. C'est la même clé qui sert déjà à cloisonner les données.

### 2.2 Le référentiel des types → modules

```
Table public.types_espaces_modules
  type       text primary key     -- 'boutique', 'hotel', … + types créés par l'Expert
  libelle    text                 -- « Hôtel », « Salon de coiffure »…
  modules    jsonb                -- ['ventes','produits','stock',…,'chambres','checkin']
  actif      boolean
```

- **Seed** à la migration : un profil par type du Module 15.
- **Expert Administrateur** : nouvelle page admin « Types d'activités » → créer un type (ex : *Salon de coiffure*) et cocher ses modules → **aucune reconstruction de l'app nécessaire**.
- RPC `rpc_mes_modules()` : renvoie les modules du type de l'**espace actif** (∩ limites du pack — Phase E).

### 2.3 Côté application

- `lib/models/module_activite.dart` : référentiel des modules (code, libellé, icône, catégorie).
- `lib/services/modules_service.dart` : singleton, `ValueNotifier<Set<String>> modules` (espace actif), chargé au login avec `EspaceService`.
- **Gating** : trois niveaux s'empilent —
  1. **Permissions** (Module 4, `peut()`) : qui a le droit ;
  2. **Modules** (nouveau) : l'activité a-t-elle ce module ;
  3. **Abonnement** (Module 3) : lecture seule / bloqué.
- UI filtrée : cartes d'accueil, menus Paramètres, entrées admin, liste des rapports — **masquées si module inactif**.
- Règle d'or de compatibilité : **type inconnu ou config absente → profil « boutique » par défaut** = comportement actuel, zéro régression.

---

## 3. Découpage en phases

### Phase A — Socle « modules » ✅ **LIVRÉE** *(v1.4.0, 18/09/2026 — migration 27 exécutée & vérifiée en production)*
1. **Migration** : table `types_espaces_modules` + seed (boutique → modules actuels ; hôtel/pharmacie/restaurant → pré-configurés, y compris les modules **inactifs** car pas encore codés) + RPC `rpc_mes_modules()` + `rpc_types_espaces_lister()` + `rpc_type_espace_modules_maj()` (Expert).
2. **Dart** : `ModuleActivite`, `ModulesService`, branchement login/démarrage, garde `moduleActif()` dans les widgets existants (aucun changement visuel au début).
3. **Admin** : page « Types d'activités » (liste + édition des modules) dans l'onglet Référentiels.
4. **Tests** : parse des profils, merge permissions × modules, défaut boutique.
- ✅ Résultat : infrastructure prête, app inchangée pour tout le monde.

### Phase B — Tableaux de bord adaptés ✅ **LIVRÉE** *(v1.5.0, 18/09/2026 — migration 28 exécutée & vérifiée : hôtel 9 modules, restaurant 12)*
- `HomePage` : grille de cartes construite depuis les **modules actifs** (fini les cartes inutiles pour un hôtel) — registre `lib/ui/accueil/cartes_accueil.dart`.
- Chaque module apporte sa carte d'accueil (CA du jour, chambres libres, commandes en attente…) : ajouter la carte d'un module métier = **1 entrée** au registre.

### Phase C — Modules métier (un module = une migration + écrans + tests)

| Ordre | Module | Contenu principal |
|---|---|---|
| C1 | **Pharmacie** | `produits.lot_numero` + `produits.date_expiration` (+ table `lots_produits` si multi-lots), **alertes d'expiration** (dashboard + notifications), rapport « Expirations », blocage vente si expiré (configurable) |
| C2 | **Hôtel** | `chambres` (n°, type, capacité, prix, statut : libre → réservée → occupée → à nettoyer), `reservations` (client, dates, personnes, avance, solde), **check-in/check-out**, facture séjour, dashboard occupations + arrivées/départs du jour |
| C3 | **Restaurant** | `tables_salle`, commandes (`commandes` + `lignes_commande` : table, statut *envoyée → en préparation → prête → servie*), **écran cuisine**, envoi en cuisine, encaissement via la caisse existante |
| C4 | **Salle des fêtes** | `salles` (capacité, prix), `evenements` (client, date, heures, invités, avance, solde), calendrier, contrats/factures |
| C5 | **Boulangerie** | `matieres_premieres` + consommation, `productions` (produit fini, quantité, pertes), coût de revient, dashboard production du jour |
| C6 | **Boucherie / vente au poids** | saisie au **kg** dans le panier (quantités décimales déjà supportées ✓), prix au kg, arrondis, ticket avec poids |
| C7 | **Quincaillerie / magasin** | déjà couvert par les **conditionnements** (pièce/carton/sac/rouleau) — juste des profils types + libellés |
| C8 | **Variantes mode** | `produits.attributs jsonb` (couleur, taille, marque) + filtre/variantes simples |

### Phase D — Rapports par activité *(1-2 j)*
- Nouveaux types de rapports : `expirations`, `occupation_chambres`, `arrivees_departs`, `commandes_jour`, `production`, `pertes`…
- La **liste des rapports affichée** est filtrée par modules actifs (un hôtel ne voit pas « ventes par article » s'il ne l'a pas).
- Le titre générique « **Rapports de l'entreprise** » est déjà en place ✓.

### Phase E — Abonnement par modules *(2 j)*
- `groupes_tarifaires.modules jsonb` : un pack autorise une liste de modules.
- Les modules effectifs = **type d'espace ∩ pack souscrit**.
- Écran admin Groupes tarifaires : cocher les modules du pack.
- Tarification par packs : « Essentiel » (ventes/stock) / « Avancé » (+multi-entreprises, +IA) / « Spécialisé » (+hôtel/+pharmacie…).

---

## 4. Exemples concrets (telle que demandée)

### 🏪 Pharmacie
Dashboard : `🔴 X produits expirés` `🟠 Y expirant sous 30 j` `⚠️ Z sous le seuil` `💰 Ventes du jour`.
Modules : produits (avec lot + date d'expiration), stock, ventes, caisse, fournisseurs (dépenses), rapports *Expirations*.

### 🏨 Hôtel
Dashboard : `Chambres libres / occupées / réservées / à nettoyer` `Arrivées du jour` `Départs du jour` `CA du jour`.
Écrans : plan des chambres, réservations, check-in/check-out, facture. **Pas** de scanner d'articles.

### 🍽️ Restaurant
Dashboard : `Commandes en cours` `Tables occupées/libres` `Plats du jour`.
Écran cuisine : nouvelle → en préparation → prête → servie. Paiement : espèces/mobile money/carte.

### 🎉 Salle des fêtes & 🥖 Boulangerie & 🥩 Boucherie
Calendrier des événements / Production + matières + pertes / Vente au kg.

### ✂️ Salon de coiffure (exemple « nouveau type »)
Créé par l'**Expert Administrateur** en 2 minutes : modules `clients` + `rendez-vous` *(à créer un jour)* + `prestations` (via produits) + `caisse` + `rapports`.

---

## 5. Ce qui se réutilise déjà (gros avantage)

- ✅ Ventes / caisse / stock / dépenses / dettes / rapports / exports PDF-Excel
- ✅ QR codes & scanner multi-unités (conditionnements)
- ✅ Permissions (Module 4) — la brique « qui a le droit »
- ✅ Abonnement & activation (Modules 3/14)
- ✅ Multi-entreprises & espace actif (Module 15) — fondation du changement d'activité
- ✅ Journal d'audit (Module 12), Notifications (v1.3.0), Assistant IA 35 outils (Module 13)
- ✅ Publication GitHub Releases (CI) — chaque phase arrivera par une mise à jour propre

---

## 6. Ordre de livraison recommandé

```
Phase A (socle)  →  Phase B (dashboards)  →  C1 Pharmacie  →  C2 Hôtel
   →  C3 Restaurant  →  D (rapports par activité)  →  C4/C5/C6  →  Phase E (packs)
```

Chaque phase : **1 migration SQL idempotente + tests Flutter + 1 release** (v1.4.0, v1.5.0…), poussée sur les stores après validation.

---

*Document préparé le 18/09/2026 — feu vert utilisateur donné. Phases A (v1.4.0) et B (v1.5.0) livrées : socle `types_espaces_modules` + 3 RPC + page admin « Types d'activités » + grille d'accueil pilotée par les modules (registre des cartes) + profils affinés hôtel/restaurant. Prochaine action : **Phase C1 — module Pharmacie** (lots & péremption).*
