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
| **`chambres`** | Chambres, statuts, équipements | ✅ C2 |
| **`reservations`** | Réservations hôtel / salle des fêtes | ✅ C2 |
| **`checkin`** | Arrivées / départs, facturation séjour | ✅ C2 |
| **`tables`** | Plan de salle, occupation | ✅ C3 |
| **`commandes`** | Commandes restaurant (table → cuisine) | ✅ C3 |
| **`cuisine`** | Écran cuisine (préparation) | ✅ C3 |
| **`lots_expiration`** | Lots, dates de péremption (pharmacie/boucherie) | ✅ C1 |
| **`production`** | Production + matières premières (boulangerie) | ✅ C5 |
| **`pesee`** | Vente au poids (kg) | ✅ C6 |
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
| C1 ✅ | **Pharmacie** | ✅ **LIVRÉE** *(v1.6.0 — migration 29)* : `produits.lot_numero` + `produits.date_expiration`, écran « Expirations » (tri par urgence + filtres), carte d'accueil avec compteur, alertes dans le rapport quotidien, rapport « Expirations », blocage de vente si expiré (configurable `ventes.bloquer_produits_expires`) |
| C2 ✅ | **Hôtel** | ✅ **LIVRÉE** *(migration 30 — prochaine release)* : `chambres` (n°, type, capacité, prix, statut : libre → réservée → occupée → à nettoyer), `reservations` (client, dates, personnes, avance, solde), **check-in/check-out**, facture séjour, réception du jour (occupation + arrivées/départs), cartes d'accueil « Chambres / Réservations / Réception », permissions `chambres` · `reservations` · `reception` |
| C3 ✅ | **Restaurant** | ✅ **LIVRÉE** *(migration 31 — prochaine release)* : `tables_salle` (zone, places, statut libre/occupée/réservée), `commandes` + `lignes_commande` (statut *ouverte → envoyée → en préparation → prête → servie → encaissée*), **écran cuisine** (auto-refresh 20 s), envoi en cuisine, **encaissement via la caisse existante** (`rpc_vente_valider` : stock, reçu, journal), cartes « Tables / Commandes / Cuisine », permissions `tables` · `commandes` · `cuisine` |
| C4 ✅ | **Salle des fêtes** | ✅ **LIVRÉE** *(migration 33 — prochaine release)* : `salles` (nom, capacité, prix/jour, équipements, actif), `evenements` (client fiche ou libre, dates + heures, invités, prix négocié, avance/solde, cycle *réservé → confirmé → en cours → terminé / annulé*, numéro `EVT-…`), `lignes_evenement` (prestations : traiteur, décoration… **en plus** du prix de la salle), **chevauchement de salle refusé**, encaissements d'avances/soldes tracés, tableau de bord événementiel (salles, événements du jour/à venir, encaissé, solde, 5 prochains), cartes d'accueil « Événements / Salles », profil d'activité « Salle des fêtes » seedé, permissions `salles` · `evenements` |
| C5 ✅ | **Boulangerie** | ✅ **LIVRÉE** *(migration 34 — prochaine release)* : `matieres_premieres` (stock, seuil d'alerte, prix unitaire), `productions` (produit fini, quantité prévue/réelle, **pertes**, coût de revient unitaire, statut *en cours → terminée / annulée*, numéro `PROD-…`), `consommations_production` (matières déduites du stock, coût figé), **entrée en stock automatique du produit fini à la clôture** (via ajustement officiel Module 9), annulation = matières rendues au stock, tableau de bord production du jour (alertes matières, quantité, pertes, coût), cartes d'accueil « Production », profil d'activité « Boulangerie » seedé, permissions `production` |
| C6 ✅ | **Boucherie / vente au poids** | ✅ **LIVRÉE** *(migration 35 — prochaine release)* : `produits.vendable_au_poids` (prix AU KILO), caisse adaptée (saisie du poids 0,75 kg, pas de 0,5 kg au scanner et au panier, badge « / kg » dans la liste), ticket et stock au poids exact (les quantités décimales traversaient déjà vente/stock/reçus), profil d'activité « Boucherie » seedé. **C7 déjà couvert** par les conditionnements ; reste **C8 (variantes)**. |
| C7 | **Quincaillerie / magasin** | déjà couvert par les **conditionnements** (pièce/carton/sac/rouleau) — juste des profils types + libellés |
| C8 | **Variantes mode** | `produits.attributs jsonb` (couleur, taille, marque) + filtre/variantes simples |

### Phase D — Rapports par activité *(1-2 j)* — ✅ **LIVRÉE** *(migration 32)*
- ✅ Nouveaux types de rapports : `occupation_chambres` (taux d'occupation par jour, arrivées, départs, CA séjours), `arrivees_departs` (liste des séjours : client, chambre, dates, nuits, montant, solde), `commandes_jour` (commandes restaurant par jour, encaissées, annulées, CA) — en plus d'`expirations` (livré en v1.6.0).
- ✅ La **liste des rapports affichée** est filtrée par modules actifs (un hôtel ne voit pas « commandes restaurant » s'il ne l'a pas, et inversement).
- ✅ Le titre générique « **Rapports de l'entreprise** » est déjà en place ✓.
- *Reste pour plus tard : `production` / `pertes` (arriveront avec les modules boulangerie C5) — sans bloquer la phase.*

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
Phase A (socle)  →  Phase B (dashboards)  →  C1 Pharmacie ✅  →  C2 Hôtel ✅
   →  C3 Restaurant ✅  →  D Rapports par activité ✅  →  C4 Salle des fêtes ✅
   →  C5 Boulangerie ✅  →  C6 Boucherie ✅  →  C8 Variantes  →  Phase E (packs)
```

Chaque phase : **1 migration SQL idempotente + tests Flutter** — et **une SEULE release à la fin**, quand tous les modules sont terminés (consigne utilisateur du 19/09/2026 : plus de release intermédiaire).

---

*Document préparé le 18/09/2026 — feu vert utilisateur donné. Phases A (v1.4.0), B (v1.5.0), C1 Pharmacie (v1.6.0), **C2 Hôtel** (migration 30), **C3 Restaurant** (migration 31), **D — rapports par activité** (migration 32), **C4 Salle des fêtes** (migration 33), **C5 Boulangerie** (migration 34) et **C6 Boucherie / vente au poids** (migration 35) livrées : socle `types_espaces_modules` + 3 RPC + page admin « Types d'activités » + grille d'accueil pilotée par les modules (registre des cartes) + profils affinés hôtel/restaurant + lots & péremption (expirations, alertes, blocage configurable) + **hôtel : chambres, réservations, check-in/check-out, réception du jour, facture de séjour** + **restaurant : plan de salle, commandes, écran cuisine, encaissement via la caisse** + **rapports filtrés par modules actifs, page « À propos » officielle (éditeur Biashara Tech · développeur Andre Lukengu · La Perle Corp collaborateur marketing) et guide d'utilisation par module (bouton ? partout)** + **salle des fêtes : salles, calendrier, prestations, avances & soldes** + **boulangerie : matières premières, productions, pertes & coût de revient (entrée en stock automatique)** + **boucherie : articles vendus au poids (prix/kg, pas de 0,5 kg, ticket au kg)**. Prochaine action : **C8 Variantes (tailles/couleurs)**, puis **Phase E (packs par modules)** — release unique ensuite.*
