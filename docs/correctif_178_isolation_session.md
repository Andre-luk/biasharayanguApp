# Correctif 178 — Isolation des sessions et des espaces

**Version :** 3.10.5
**Date :** correctif client (aucune migration SQL)
**Portée :** `lib/` + `test/`

---

## 1. Le problème constaté

> « Quand je me connecte avec le super admin je me trouve sur un tableau de
> bord, rapports et système comme menu d'en bas, même aussi pour une
> boutique, et la boutique est lié au pressing avec comme 3 menus. »

Trois symptômes, un seul sujet : **l'application ne repartait pas d'un état
vierge entre deux comptes**, et **elle décidait du rôle et de l'espace avant
d'avoir demandé au serveur**.

1. Un **Super Admin** atterrissait dans l'interface boutique (`/main`,
   tableau de bord, rapports, système en bas de l'écran) au lieu de la console
   plateforme (`/admin`).
2. Une **boutique** héritait du contexte **pressing** et de ses menus
   (`Dépôts`, `Atelier`, `Retraits`) sans jamais avoir activé ce métier.
3. Les **cartes de l'accueil** dépendaient d'un profil de modules parfois
   vide : tant que le profil n'était pas chargé, toutes les cartes du registre
   étaient affichées (28 cartes : chambres, tables, pressing, production…).

---

## 2. Les quatre causes

### 2.1 Six déconnexions partielles (cause n° 1)

Chaque écran avait sa propre fermeture de session :

| Fichier | Ce qui était nettoyé |
|---|---|
| `lib/pages/home_page.dart` | jeton Supabase + session locale |
| `lib/pages/settings_page.dart` | jeton Supabase + session locale |
| `lib/pages/admin_home_page.dart` (2 endroits) | jeton Supabase |
| `lib/pages/distribution_pro_page.dart` | session locale |
| `lib/pages/admin_users_page.dart` | session locale |

Conséquence : selon l'écran utilisé pour se déconnecter, il restait en mémoire
le rôle, la matrice de permissions, l'entreprise active, le profil de modules,
le panier, l'historique de scan… **Le compte suivant héritait de ces états.**
C'est exactement le scénario « super admin → tableau de bord boutique ».

### 2.2 Le rôle local décidait avant le serveur (cause n° 2)

Au démarrage (`lib/main.dart`), au retour d'une connexion
(`lib/pages/login_page.dart`) et dans la coquille de navigation
(`lib/pages/scaffold_with_nav_bar.dart`), le rôle était lu **d'abord** dans
`SharedPreferences` (`user_role`).

Or cette valeur peut être :

- absente (première connexion sur l'appareil) ;
- **périmée** (compte promu ou rétrogradé côté serveur) ;
- **celle d'un autre compte** (déconnexion incomplète, cf. 2.1).

Un compte plateforme dont la valeur locale valait `proprietaire` ouvrait donc
`/main` : tableau de bord, rapports, système.

### 2.3 Un cache d'espace GLOBAL (cause n° 3)

`lib/services/espace_service.dart` mémorisait le dernier espace connu
(entreprises + entreprise active) sous **une seule clé** :
`espace_etat_cache_v1`.

Sur le même navigateur ou le même téléphone :

1. le pressing ouvre l'application → cache = pressing ;
2. la boutique se connecte → l'application **publie immédiatement le cache**
   (avant tout appel réseau, pour l'affichage instantané) ;
3. la boutique travaille donc quelques secondes — parfois toute la session si
   le réseau est mauvais — dans **l'espace du pressing**, avec ses trois
   menus.

### 2.4 Les cartes métier « fail-open » (cause n° 4)

`lib/ui/accueil/cartes_accueil.dart` filtrait les cartes selon les modules
actifs, mais **uniquement si le profil était considéré comme chargé**. Profil
non chargé ⇒ aucune restriction ⇒ les 28 cartes du registre s'affichaient.

---

## 3. Les correctifs

### 3.1 Un seul point de sortie : `ReinitialisationSession`

**Nouveau fichier : `lib/services/reinitialisation_session.dart`**

```dart
await ReinitialisationSession.tout(email: email);
```

Ordre d'exécution (best-effort, jamais bloquant) :

1. identifiant du compte sortant capturé (`SessionManager.getUserId()`) ;
2. trace d'audit (`AuditService.deconnexion`) ;
3. `SupabaseService.signOut()` — le jeton ne doit plus servir ;
4. `_viderEtatsMetier()` — **tous** les singletons :
   `PermissionService`, `EspaceService` (avec purge du cache du compte),
   `ScopeDonnees`, `ModulesService`, `TypeActiviteService`,
   `AbonnementService`, `ContexteDistribution`, `MarketplaceService`,
   `DeviseService`, `PeremptionService`, `EtablissementService`,
   `PanierService`, `ScannerService`, `VentesCommercialesService` ;
5. `SessionManager.clearSession()` — `user_id` / `user_role` ;
6. `CacheLecture.instance.vider()` — les caches persistés.

Les **six** déconnexions passent désormais par ce service. `viderEtats()` est
exposé pour la connexion et pour les tests (on repart d'un état vierge **avant**
de charger un nouveau compte).

### 3.2 Le serveur fait foi pour le rôle

`PermissionService` expose une résolution serveur :

```dart
final RoleUtilisateur role = await PermissionService.instance
    .resoudreRoleDepuisServeur(userId: uid);
```

- `lib/pages/login_page.dart` : `ReinitialisationSession.viderEtats()` →
  rôle serveur → repli local **uniquement** si le serveur ne répond pas
  (hors ligne) → `SessionManager.setUserRole()` →
  `PermissionService.instance.initialiser(..., forcerRechargement: true)`.
- `lib/main.dart` : même logique à la restauration de session, avec une trace
  `Démarrage — rôle effectif : … (serveur|local)`.
- `lib/pages/scaffold_with_nav_bar.dart` : idem pour les comptes non
  plateforme.

Le rôle plateforme est envoyé directement sur `/admin`.

### 3.3 Un garde-fou d'espace dans le routeur

`PermissionService.espaceAutorise(role, location)` (fonction **pure**, donc
testable) et `lib/config/app_router.dart` :

```dart
if (!PermissionService.espaceAutorise(role, location)) {
  return role.estPlateforme ? '/admin' : (permissions.accueilPour(role) ?? '/login');
}
```

Un compte plateforme ne peut plus atteindre `/main/...`, et un compte
d'entreprise ne peut plus atteindre `/admin/...`, **même par un lien direct**.

### 3.4 Un cache d'espace par compte

```dart
static const String prefixeCacheUtilisateur = 'espace_etat_cache_v2_';
```

- `restaurerDepuisCache({String? userId})` lit **la clé du compte** et supprime
  l'ancienne clé globale `espace_etat_cache_v1` (elle ne doit plus jamais
  servir d'espace à quelqu'un d'autre) ;
- `_ecrireCache` écrit sous la clé du compte connecté ;
- `_viderCache({String? userId})` supprime la clé du compte **et** l'ancienne
  clé globale ; l'identifiant est fourni par la déconnexion car la session
  locale peut déjà être effacée au moment de la purge ;
- `initialiserContexte({String? userId})` transmet l'identifiant depuis
  `main.dart`.

Une boutique qui se connecte après un pressing ne peut plus restaurer l'espace
du pressing.

### 3.5 Les cartes métier attendent le profil

```dart
// 1 bis — correctif 178 : aucun module métier n'est publié sans profil.
if (!profilCharge && module != null && _modulesMetier.contains(module)) {
  return false;
}
```

`_modulesMetier` : `press_depots`, `press_atelier`, `press_retraits`,
`chambres`, `reservations`, `checkin`, `tables`, `commandes`, `cuisine`,
`salles`, `evenements`, `lots_expiration`, `production`, `distribution`.

Les cartes **transverses** restent visibles sans attendre le réseau : vente,
stock, distribution (`tournees`, `ma-tournee`, `consignes`, `recipients`),
caisse, finance, rapports, marketplace, abonnement.

### 3.6 Le pressing garde son périmètre métier

`PermissionService` porte désormais un contexte pressing explicite
(`definirContextePressing`) alimenté par `PressingService.rolePressingCode()` :

| Rôle pressing | Écrans autorisés |
|---|---|
| `proprietaire`, `responsable` | tableau de bord, paramètres, collaborateurs, finance, rapports, assistant IA, dépôts, atelier, retraits |
| `accueil` | tableau de bord, dépôts, retraits |
| `atelier` | tableau de bord, atelier |
| `caisse` | tableau de bord, retraits |
| rôle métier inconnu | tableau de bord seulement |

`/main/pressing/equipe` et `/main/pressing/reglages` sont réservés au
responsable ; la vente boutique est refusée (`VENTE_INTERDITE_PRESSING`,
message explicite invitant à enregistrer un dépôt).

---

## 4. Procédure de vérification

### 4.1 Sur un même appareil (le cas signalé)

1. Se connecter avec le **pressing** → noter l'espace et les trois menus.
2. Se déconnecter (menu → **Déconnexion**), puis se connecter avec le
   **super admin**.
3. Vérifier : la console **`/admin`** s'ouvre, aucun menu bas de page boutique,
   aucune donnée du pressing.
4. Se déconnecter, se connecter avec une **boutique**.
5. Vérifier : tableau de bord boutique, **aucun** menu `Dépôts` / `Atelier` /
   `Retraits`, aucun montant du pressing.

### 4.2 Après un rechargement de page (web)

Recharger l'onglet (F5) sur un compte boutique : l'espace affiché doit rester
**celui de cette boutique** — jamais celui du compte précédent.

### 4.3 Lien direct

Saisir `.../#/admin` en étant connecté comme entreprise : redirection vers
l'accueil du rôle. Saisir `.../#/main` en étant super admin : redirection vers
`/admin`.

### 4.4 Journaux utiles (mode debug)

```
Démarrage — rôle effectif : proprietaire (serveur)
EspaceService : contexte restauré du cache du compte (1 entreprise(s), active : …)
```

La mention **(serveur)** confirme que le rôle vient de la base et non d'une
valeur locale périmée.

---

## 5. Fichiers touchés

| Fichier | Nature |
|---|---|
| `lib/services/reinitialisation_session.dart` | **nouveau** — point de sortie unique |
| `lib/services/permission_service.dart` | rôle serveur, périmètre pressing, `espaceAutorise` |
| `lib/services/espace_service.dart` | cache d'espace par compte |
| `lib/config/app_router.dart` | garde-fou d'espace |
| `lib/pages/login_page.dart` | reset + rôle serveur + modules rechargés |
| `lib/main.dart` | reset + rôle serveur + `userId` du cache |
| `lib/pages/scaffold_with_nav_bar.dart` | contexte pressing + rôle serveur |
| `lib/pages/{home,settings,admin_home,distribution_pro,admin_users}_page.dart` | déconnexion centralisée |
| `lib/ui/accueil/cartes_accueil.dart` | cartes métier après profil |
| `test/session_isolation_test.dart` | **nouveau** — 12 tests |
| `test/accueil_modules_test.dart` | profil non chargé ⇒ aucune carte métier |

---

## 6. Ce que le correctif ne change pas

- Les données de la base (aucune migration : le correctif est **client**).
- Les droits réels : ils restent calculés côté serveur (RLS + RPC) ; le
  correctif empêche seulement l'**affichage** d'un espace qui n'est pas le
  sien.
- Le mode hors ligne : si le serveur ne répond pas, le rôle local sert encore
  de repli — mais seulement après une déconnexion propre.
