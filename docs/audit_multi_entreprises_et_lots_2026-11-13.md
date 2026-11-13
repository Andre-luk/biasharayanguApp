# Audit multi-entreprises & lots pharmacie — 13/11/2026

Branche auditée : `main` @ `a0f289b` (tag **v3.9.2**, 56).
Périmètre : contexte entreprise active, isolation des données (Flutter +
Supabase + SQLite), type d'activité → modules/tableaux de bord, pharmacie
(lots/péremption), pressing.

---

## 1. Méthode

1. Lecture de l'architecture réelle (pas des intentions) : `EspaceService`,
   `ScopeDonnees`, `ModulesService`, `ReglesActivite`, `cartes_accueil`,
   `ArticleService`, `DBHelper.resolveEffectiveOwnerId`, routes go_router,
   migrations 0145 → 0162.
2. Recherche des causes par grep ciblé (pas seulement des symptômes) :
   - où `owner_id` est calculé côté client ;
   - où la RPC `rpc_vente_valider` est **redéfinie** (dernière version = 0116) ;
   - quelles tables portent la péremption.
3. Correction + tests unitaires + analyse statique.
4. Aucun test « live » n'a été exécuté : voir §6.

## 2. Causes racines identifiées

### 2.1 Deux notions confondues : identité du patron / portée des données

Depuis le module 15, `owner_id` ne porte plus l'UUID du patron mais **l'UUID de
l'espace de travail** (`utilisateurs.espace_actif_id`). `mon_proprietaire()`
sert alors à deux choses incompatibles :

- **portée des données** (quel espace on lit/écrit) ;
- **identité du propriétaire** (qui a le droit de faire quoi).

Conséquences historiques (déjà corrigées par **0157** dans la base) :

- `rpc_collaborateur_creer` comparait `auth.uid()` à `mon_proprietaire()` →
  « seul le propriétaire peut créer un collaborateur » dans la 2ᵉ entreprise ;
- un article écrit sous l'espace pharmacie devenait invisible si
  `utilisateurs.entreprise_id` était resté sur l'autre entreprise.

**État vérifié** : la base porte désormais `mon_patron()` (identité) et
`mon_proprietaire()` (portée). La correction Dart du 3.9.2
(`ScopeDonnees.proprietaireEffectif` = valeur renvoyée par `mon_proprietaire()`)
est bien celle utilisée par `ArticleService.proprietaireCourant()`.

**Ce qui restait réellement cassé côté application** (corrigé ici) :

| Défaut | Effet constaté | Correction |
|---|---|---|
| Les écrans vivent dans un `StatefulShellRoute.indexedStack` : ils ne sont jamais recréés | Après une bascule, Articles/Stock/Clients/Caisse continuaient d'afficher l'entreprise précédente | mixin `EcouteContexteEntreprise` branché sur ces écrans → rechargement + remise à zéro des filtres |
| `CacheLecture.cleRpc` ne contenait que l'utilisateur et les paramètres de la RPC | **Hors ligne**, une réponse lue dans la pharmacie pouvait être resservie dans la boutique | la clé inclut désormais l'entreprise (`espace=`), propriétaire effectif d'abord |
| Le panier et l'historique des scans survivaient à une bascule | Une ligne de la pharmacie pouvait être encaissée dans la boutique | `EspaceService._reinitialiserSessionMetier()` : panier vidé, historique vidé, `DonneesService.signale('entreprise')` |

### 2.2 Le blocage de vente des produits expirés avait disparu

`PRODUIT_EXPIRE` n'existe que dans la migration **0029**. Or
`rpc_vente_valider` a été **réécrite** en 0108, 0110 puis **0116**
(`vente_sans_stock`) : la vérification `date_expiration` n'y figure plus.
La règle métier « un médicament périmé ne se vend pas » n'était donc plus
appliquée par le serveur (le contrôle Dart n'existe pas).

**Correction** : trigger `trg_vente_lots_controle` (BEFORE INSERT sur `ventes`)
— refus `PRODUIT_EXPIRE`, et refus de vendre plus que le **stock valide des
lots** (`STOCK_LOT_INSUFFISANT`). Aucune réécriture de la RPC n'a été
nécessaire (moins de risque).

### 2.3 La pharmacie n'avait pas de lots

La seule péremption était `produits.date_expiration` : **une** date par
article. Dès la deuxième réception, l'information est fausse. Aucune table de
lots n'existait (`grep lots_medicament|produits_lots|lot_id` : 0 résultat).

**Correction** : migration **0163** (voir `docs/module36_lots_pharmacie.md`).

### 2.4 Constat sur le pressing

Le pressing (module 35) est bien branché : `espaces.type='pressing'` →
profil de modules → carte d'accueil `pressing` → `/main/pressing/depots` →
`PressingCommandesPage`. Les deux pannes connues sont déjà corrigées :

- profil incomplet (0162 : ajout de `ventes/produits/stock/qr`, sans retirer
  de module) — **puis 0173 (13/11) : ces 4 modules « boutique » sont RETIRÉS du
  profil pressing** (décision du patron : un pressing ne vend pas d'articles) ;
- métier lu depuis l'espace et non depuis `entreprises.type_activite`
  (0158/0159).

Aucun défaut bloquant n'a été trouvé sur ce module pendant cet audit.

### 2.5 Point de performance (non bloquant)

`ArticleService.ecouterChangements` et celui du stock écoutent **toutes** les
écritures des tables `produits` / `conditionnements` / `categories` du projet,
sans filtre `owner_id`. Ce n'est pas une fuite (les SELECT restent filtrés par
RLS), mais chaque boutique re-recharge sur les écritures des autres. À filtrer
par espace quand le temps réel sera prioritaire.

## 3. Fichiers modifiés / créés

### Flutter

| Fichier | Changement |
|---|---|
| `lib/utils/ecoute_contexte_entreprise.dart` | **nouveau** — mixin d'écoute du contexte entreprise |
| `lib/services/espace_service.dart` | remise à zéro du panier/scanner + `generation` + annonce globale ; reset aussi sur `charger()` quand l'actif change |
| `lib/services/cache_lecture.dart` | clé de cache cloisonnée par entreprise |
| `lib/pages/articles_page.dart` | rechargement + reset recherche/filtre sur bascule |
| `lib/pages/stock_gestion_page.dart` | idem |
| `lib/pages/clients_page.dart` | idem |
| `lib/pages/caisse_page.dart` | idem (résumé/journal remis à zéro) |
| `lib/models/lot_medicament.dart` | **nouveau** — `StatutLot`, `LotMedicament`, `DossierLots`, résultats RPC |
| `lib/services/pharmacie_lots_service.dart` | **nouveau** — facade RPC + erreurs françaises |
| `lib/pages/lots_medicament_page.dart` | **nouveau** — écran lots, réception, retrait |
| `lib/pages/article_detail_page.dart` | bouton « Lots & péremption » (module `lots_expiration`) |
| `lib/config/app_router.dart` | route `/main/articles/:id/lots` |
| `test/lots_medicament_test.dart` | **nouveau** — 17 tests |

### SQL

| Fichier | Contenu |
|---|---|
| `supabase/migrations/20260916000163_module36_lots_pharmacie.sql` | **nouveau** — tables `produits_lots`, `produits_lots_mouvements` ; triggers d'entrée, d'immuabilité, de contrôle de vente et de consommation FEFO ; 5 RPC ; RLS lecture seule |

**Tables Supabase touchées** : `produits` (lecture/écriture par triggers),
`ventes` (2 triggers), `ajustements` (retrait de lot), `journal_audit`
(`LOT_RECU`, `LOT_RETIRE`), + 2 tables créées.

**RLS** : `produits_lots` et `produits_lots_mouvements` = SELECT si
`owner_id = mon_proprietaire()` ou `est_plateforme()`. **Aucune policy
d'écriture** : tout passe par les RPC `security definer` (contrôle des droits
`stock/creer` / `stock/modifier` + appartenance de l'article).

**SQLite / synchronisation** : le hors-ligne n'est pas modifié par les lots
(module 36 = écran connecté). Le correctif d'isolation du cache de lecture
(`CacheLecture`) s'applique quand même hors ligne ; les clés déjà écrites avec
l'ancien format ne sont simplement plus relues (elles expirent d'elles-mêmes).

## 4. Procédure d'application (sans perte de données)

1. Exécuter **uniquement** `20260916000163_module36_lots_pharmacie.sql` dans
   le SQL Editor Supabase. Le script est idempotent (relançable) et ne
   supprime aucune donnée existante. Dernier résultat attendu :
   `Module 36 lots — OK (tables, RPC et triggers en place)`.
2. Vérifier ensuite :
   ```sql
   select * from public.produits_lots limit 5;
   select * from public.produits_lots_mouvements limit 5;
   select public.rpc_lots_ecarts();
   ```
3. Déconnexion / reconnexion de l'app, puis sélection de la pharmacie.
4. Pour l'ancien stock sans lot : enregistrer un lot « STOCK-INITIAL » avec la
   péremption réelle (sinon la vente refusera au-delà du stock des lots).

## 5. Tests réellement exécutés

| Commande | Résultat |
|---|---|
| `node /tmp/sqlcheck/check.js …0163…sql` (pgsql-parser + plpgsql-parser) | **56/56 instructions valides** |
| `flutter analyze --no-fatal-infos --no-fatal-warnings` | **exit 0** — 214 issues préexistantes (info/warning), **0 erreur** |
| `flutter test test/lots_medicament_test.dart` | **17/17 OK** |
| `flutter test` (suite complète) | **1459/1459 OK** |

## 6. Tests NON exécutés (honnêteté)

Les tests **live** ont été exécutés le 13/11/2026 sur le compte
`josephissa@gmail.com` (Urembo Market + HEKIMA PHARMA) — voir §8. Les tests
restants (collaborateurs B, pressing E, multi-appareils F, non-régression H)
ne l'ont pas encore été : ne pas les considérer comme validés.

À faire côté utilisateur après application de 0163 :

| Test | Attendu |
|---|---|
| **A** — 3 articles boutique / 5 médicaments pharmacie | chaque liste ne montre que son entreprise ; plus aucune ligne « fantôme » |
| **B** — collaborateurs séparés | un collaborateur de la pharmacie n'accède pas à la boutique ; création possible dans chaque entreprise |
| **C** — bascule répétée + fermeture/réouverture | menus, tableaux de bord, articles, stock, caisse suivent ; panier vidé à chaque bascule ; contexte restauré au redémarrage |
| **D** — lots | 3 réceptions du même médicament = 3 lots distincts ; vente = lot le plus proche d'abord ; lot périmé refusé ; retrait tracé |
| **E** — pressing | tableau de bord `pressing` + écrans dépôts/atelier/retraits (déjà livré v3.9.2) |
| **F** — 2 appareils | même entreprise, mêmes données, pas de doublon |
| **G** — isolation | un compte hors entreprise reçoit `HORS_BOUTIQUE` / `DROIT_REFUSE` |
| **H** — non-régression | boutique, distribution, hôtel, restaurant inchangés |

## 7. Points restants (non traités ici)

1. **Temps réel non filtré par entreprise** (§2.5) — performance, pas sécurité.
2. **Alerte programmée** des lots : `rpc_lots_alertes` fournit les données,
   mais aucune notification planifiée n'est encore branchée.
3. **Écrans Expirations / rapport `expirations`** restent au niveau article
   (résumé du lot le plus proche). Un rapport « pertes par lot » peut être
   ajouté en lisant `produits_lots_mouvements`.
4. **Stock antérieur aux lots** : régularisation manuelle par un lot
   « STOCK-INITIAL » (choix assumé : on ne réécrit pas une date inconnue).
5. **Référentiel de types dynamiques** : l'écran de création d'entreprise
   propose encore l'énuméré `TypeEspace` (les types Expert restent utilisables
   via le Super Admin). Amélioration UI indépendante de cet audit.

---

## 8. Vérifications LIVE du 13/11/2026 (compte josephissa)

Espace testé : **HEKIMA PHARMA** (`be5a5d15…`), après bascule depuis
**Urembo Market** (`07a0cdf1…` = UUID de l'utilisateur = espace par défaut).

### 8.1 Nouvelles causes racines, découvertes à l'exécution

| # | Constat live | Cause | Correctif |
|---|---|---|---|
| 1 | Article créé dans HEKIMA enregistré avec `owner_id = Urembo` | trigger legacy `produits.owner_id := auth.uid()` | **0165** (trigger `zzz_produits_owner_espace`) |
| 2 | `fk_produit_owner` refuse HEKIMA | FK `owner_id` → `utilisateurs` | **0166** (FK → `espaces(id)`, NOT VALID) |
| 3 | Vente enregistrée sous Urembo malgré `v_owner = HEKIMA` | trigger legacy `ventes.owner_id := auth.uid()` | **0167** (trigger générique `zzz_owner_espace`) |
| 4 | `0167` protégeait aussi `entreprises` | `entreprises.owner_id` = patron (personne) | **0168** (cas spécial → `mon_patron()`) |
| 5 | `fk_vente_owner` refuse HEKIMA | FK `owner_id` → `utilisateurs` | **0169** (conversion générale des FK) |

FK converties vers `espaces(id)` (0169) : `clients`, `depenses`, `dettes`,
`inventaires_quotidiens`, `produits`, `ventes`. `entreprises.owner_id` reste
volontairement liée à `utilisateurs`.

### 8.2 Résultats des tests

| Test | Résultat live |
|---|---|
| Article créé depuis HEKIMA | ✅ `owner_id = be5a5d15…` |
| 3 réceptions (LOT-A/B/C) | ✅ stock 0 → 100 → 250 → 330 |
| Lots distincts / FEFO | ✅ ordre LOT-A (2027) → LOT-B (2029) → LOT-C (2030) |
| Lot proche (+10 j) | ✅ passe en tête FEFO, statut `proche`, 1 alerte |
| Lot déjà périmé (−5 j) | ✅ refusé `PEREMPTION_PASSEE` |
| Vente d'un produit périmé | ✅ refusée `PRODUIT_EXPIRE`, aucune vente créée |
| Vente normale (1 × 200 CDF) | ✅ owner `HEKIMA`, caisse `HEKIMA`, mouvement `vente` `HEKIMA` |
| Consommation FEFO | ✅ LOT-URGENT 20 → 18 (deux ventes) |
| Stock fiche = somme des lots | ✅ 348 = 348, `rpc_lots_ecarts` = 0 |
| Isolation lecture | ✅ produit présent dans HEKIMA, absent d'Urembo |

### 8.3 Données de test laissées sur HEKIMA (à purger si souhaité)

- produit **1119** « TEST LOTS FEFO (a supprimer) » : stock 348, 4 lots ;
- **2 ventes** de 1 × 200 CDF (`VTE-20261113-0001` et `-0002`), owner HEKIMA ;
- le mouvement de lot de la 1ʳᵉ vente garde `owner_id = Urembo` (RLS en
  lecture seule sur `produits_lots_mouvements`, PATCH refusé) : **historique
  uniquement**, les quantités et le stock sont exacts.

Une vente ne peut pas être supprimée (module 12). Toute purge nécessite un
script SQL explicite et l'accord du propriétaire.

---

## 9. Audit des `owner_id` historiques (13/11/2026)

Compteurs initiaux (FK `NOT VALID`, donc non contrôlées) :
`produits 9 · ventes 10 · clients 1 · depenses 1 · dettes 1 · inventaires 1 · caisse 2`
— soit **25 lignes**, toutes rattachées à **6 patrons sans entreprise** :

| Patron (owner_id) | Entreprises |
|---|---|
| km hôtel `007a0852…` | 0 |
| Jambo mr `29f2138d…` | 0 |
| Patron Diag `33b3ca9e…` | 0 |
| Jean-Luc Takalashi `bc07ab43…` | 0 |
| Hôtel KZ `de005aaf…` | 0 |
| Anaclet Ntumba `fbc5eee3…` | 0 |

**Conclusion** : ces données ne sont **pas réattribuables de façon fiable**
(l'entreprise qui les portait n'existe plus). Elles sont invisibles dans
l'application et ne faussent aucun rapport d'entreprise active. Aucune
suppression n'a été faite. Options ultérieures, sur décision du propriétaire :
les laisser (legacy), les archiver, ou les purger par un script destructif
explicite.

Collaborateurs :
- **5** avaient une entreprise mais aucun espace actif → corrigés par **0172**
  (première boutique active de leur entreprise) ;
- **2** n'ont aucune entreprise (Urembo, joseph Issa) et leur patron
  « La Perle » (`56c414cf…`) n'en a pas non plus → **non réparables** sans
  création d'entreprise ;
- **2** sont inactifs (laissés tels quels).

Module 37 phase 1 (`0171`) : 22 rattachements, 22 utilisateurs, 11 entreprises,
0 à reprendre. Table additive, non encore lue par les fonctions existantes.

---

## 10. Validation live du pressing (13/11/2026)

Compte de test : `pressing.test@biashara.cd` — entreprise
« Pressing Test Biashara », `espaces.type = 'pressing'`.

### Lecture seule — `tools/live/verifier_pressing.sh` → **18 OK / 0 échec**

- métier retenu par `rpc_mes_modules()` : `pressing` (source `espace+metier`) ;
- 13 modules servis, dont `press_depots`, `press_atelier`, `press_retraits` ;
  les modules commerciaux (`ventes`, `produits`, `stock`, `qr`) sont présents
  **volontairement** depuis `0162` (profil complet) ; **retirés par 0173**
  (13/11/2026) à la demande du patron ;
- catalogue 12 catégories / 7 prestations, 10 étapes (`PRET` finale,
  `RETRAITEMENT` = boucle) ;
- tableau de bord, atelier, retraits, caisse du jour et fiche commande
  répondent ; un UUID inconnu est refusé proprement.

### Écriture — `tools/live/pressing_e2e.py` → **22 OK / 0 échec**

Commande `PR-2026-000002`, 5 000 CDF :

| Garantie | Résultat |
|---|---|
| Prix **figés** à la ligne au dépôt (1 500 ×2, 2 000 ×1) | ✅ |
| Numérotation `PR-AAAA-NNNNNN` atomique | ✅ |
| Jeton QR 64 hexadécimaux (aucun id exposé) | ✅ |
| `reference_locale` rejouée → **même** commande (hors ligne) | ✅ |
| Paiement partiel accepté, **surpaiement refusé** (`MONTANT_INVALIDE`) | ✅ |
| Atelier ligne par ligne → `PRETE` | ✅ |
| Remise sans paiement **refusée** (`SOLDE_DU`, politique `SOLDE_OBLIGATOIRE`) | ✅ |
| Solde payé → remise → statut `REMISE`, solde 0 | ✅ |
| Double remise **refusée** (`DEJA_REMIS`) | ✅ |
| Caisse du jour = 10 000 CDF (espèces 2 000 + mobile money 8 000) | ✅ |

**Pièges rencontrés (corrigés dans les scripts, aucune correction serveur) :**
l'étape `RETRAITEMENT` (ordre 100) vient **après** `PRET` : la parcourir renvoie
la commande en `EN_TRAITEMENT` ; le paramètre de signature s'appelle
`p_signataire` ; les statuts sont en majuscules (`PRETE`, `REMISE`).

### Données de test laissées sur le compte pressing

`PR-2026-000001` (5 000 CDF, prête non remise), `PR-2026-000002` (5 000 CDF,
remise), 2 clients `CLIENT TEST E2E …`, 4 paiements, 1 remise, 2 tarifs de
test (1 500 / 2 000). Aucune suppression automatique : les commandes n'ont
aucune politique DELETE, c'est voulu.

### Typage — vérifié côté serveur

`rpc_types_espaces_publics()` renvoie **13 métiers** ; l'énumération Dart
`TypeEspace` en contient exactement 13 (mêmes codes) et les 26 codes de
modules serveur (`ModuleCode`) couvrent tous les profils. `rpc_mes_modules()`
tire le métier de `espaces.type` en premier — prouvé live : passer le pressing
en `pressing` sert les `press_*`, avec garantie métier même si le pack
d'abonnement les omet.
