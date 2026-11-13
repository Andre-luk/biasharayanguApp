# Correctif — « le module Pressing ne s'affiche pas dans l'application »

Date : 14/11/2026 · Version concernée : 3.9.2+56 et toutes les versions depuis le
module 35 · Aucune migration SQL nécessaire.

## 1. Ce que l'on voyait

Connecté avec un compte **Pressing Test Biashara** (métier `pressing` bien
reconnu par le serveur : bandeau « Biashara Yangu PRESSING & BLANCHISSERIE »,
devise CDF), l'accueil affichait la grille d'une **boutique** :

`Produits · Statut du Stock · Mes ventes · Clients & dettes · Ma vitrine ·
Voir Ma visibilité · Gérer Publicités · Caisse · Finance · Rapports ·
Conseils (Assistant IA) · Suivi (Mon abonnement)`

Aucune carte **Pressing**, et l'ouverture directe de
`#/main/pressing/depots` renvoyait sur `#/main`.

## 2. Ce qui n'était PAS la cause

| Piste | Vérification | Verdict |
|---|---|---|
| Métier mal détecté | `rpc_mes_modules()` renvoie `type: "pressing"`, `source: "espace+metier"` | ❌ innocent |
| Modules absent du profil | la RPC renvoie bien `press_depots, press_atelier, press_retraits` | ❌ innocent |
| Blocage par surcharge de permissions | `app_settings?key=eq.permissions_roles` → `[]` (aucune surcharge) | ❌ innocent |
| Carte non déclarée | `registre` contient `id: 'pressing'` → `/main/pressing/depots` | ❌ innocent |
| Routes non déclarées | `_RegleRoute('/main/pressing/...')` présentes depuis le module 35 | ❌ innocent |

## 3. La cause réelle (deux niveaux)

### 3.1 Les trois pages n'étaient accordées à AUCUN rôle (bug principal)

`PageAccess.pressingDepots`, `pressingAtelier` et `pressingRetraits` existaient
dans l'énumération, dans les règles de routes et dans le registre des cartes,
mais **n'apparaissaient dans aucune liste de `PermissionService.defauts`**.

Conséquence en cascade, pour **tous** les rôles, y compris le propriétaire :

1. `CarteAccueil.visibles()` filtre chaque carte par
   `autorise(carte.page, carte.action)` → la carte `pressing` était retirée ;
2. `routeAutorisee('/main/pressing/depots')` renvoyait `false` → go_router
   rebasculait sur `/main` (d'où le « ça revient à l'accueil ») ;
3. `PermissionGate(PageAccess.pressingDepots, …)` masquait les boutons internes.

Le serveur, lui, était correct depuis la migration **0120** :
`permissions_defaut('PROPRIETAIRE')` contient bien les trois pages. **La matrice
Dart avait simplement oublié le module 35** — décalage entre le SQL et le Dart.

### 3.2 Le web déployé était plus ancien que le dépôt

`https://biashara-yangu-app.netlify.app` affichait « Version 3.9.0 (54) » alors
que `pubspec.yaml` est en 3.9.2+56 : le bundle n'a pas été republié depuis. Ce
n'était pas la cause du problème (3.9.0 contient déjà la carte et les écrans),
mais il faut republier pour que les utilisateurs voient le correctif.

## 4. Le correctif

### 4.1 Matrice Dart alignée sur la matrice serveur

`lib/services/permission_service.dart` — ajout, pour les trois pages :

| Rôle | dépôts | atelier | retraits |
|---|---|---|---|
| `PROPRIETAIRE` | tout | tout | tout |
| `VENDEUR` (accueil / caisse) | voir, créer, **modifier** | — | voir, créer, **valider** |
| `MAGASINIER` (atelier) | — | voir, créer, modifier | — |
| `COMPTABLE_ENTREPRISE` | voir | — | — |

> C'est exactement `permissions_defaut()` de la migration 0120 : le Dart ne
> décrit plus autre chose que ce que le serveur autorise.

### 4.2 Une carte peut exiger « au moins une » page

`lib/ui/accueil/cartes_accueil.dart` — nouveau champ `pagesOu` : la carte
s'affiche si le rôle possède `page` **ou** l'une des pages de `pagesOu`.

La carte du pressing l'utilise (`pressingDepots`, `pressingAtelier`,
`pressingRetraits`). Sans cela, l'agent d'**atelier** (rôle `MAGASINIER`, qui
n'a que `pressing_atelier`) aurait vu sa carte disparaître : il ne lui reste
aucun chemin vers son écran. L'écran d'entrée (`pressing_commandes_lister`)
n'exige d'ailleurs aucune permission de page — seulement d'appartenir au
pressing.

### 4.3 Tests

- `test/pressing_permissions_test.dart` (11 tests) : matrice des quatre rôles,
  routes des six écrans, visibilité de la carte (profil pressing, profil
  boutique, profil non chargé, rôle inconnu) ;
- `test/permission_test.dart` mis à jour : le menu du vendeur passe de 16 à
  **18 pages**, et l'invariant « un vendeur ne modifie jamais rien » devient
  « une seule exception : `pressing_depots.modifier` / `pressing_retraits.valider` »,
  conformément au SQL.

## 5. Vérification attendue après déploiement

Compte propriétaire d'un pressing :

1. accueil → carte **« Pressing — Dépôts & retraits »** ;
2. hub `/main/pressing/depots` : dépôts du jour, fiche commande, dépôt, atelier,
   retraits, caisse, équipe, réglages ;
3. compte agent d'atelier : la carte reste visible, l'onglet **Atelier**
   fonctionne, **Retraits** est refusé.

Aucune migration n'est à exécuter pour ce correctif.

## 6. Leçon à retenir

> Ajouter une page dans `PageAccess` **ne suffit pas** : il faut aussi
> l'ajouter à `PermissionService.defauts` (et à `permissions_defaut()` côté
> SQL), sinon la fonctionnalité est **invisible pour tout le monde** — sans
> aucune erreur, ce qui rend le diagnostic difficile.

Réflexe : après l'ajout d'une page, écrire un test qui vérifie qu'au moins un
rôle la possède (voir `test/pressing_permissions_test.dart`).
