# Biashara Yangu

Application de **gestion de commerce multi-activités** (boutique, hôtel, pharmacie,
restaurant, salle des fêtes, boulangerie, boucherie…) — Flutter + Supabase,
éditée et exploitée par **Biashara Tech** — Lubumbashi, République Démocratique
du Congo. Collaborateur marketing : **La Perle Corp**. Développeur principal :
**Andre Lukengu**.

> **Une activité = des modules = des écrans.** Le patron choisit son type
> d'activité ; l'application affiche uniquement les modules utiles (ventes,
> chambres, commandes de restaurant, lots & péremption…). Une seule
> application pour tous les commerces.

---

## 1. Ce que fait l'application

| Domaine | Fonctions |
|---|---|
| **Ventes** | Panier, scanner, encaissement (espèces, mobile money, carte, dette), reçus, historique, annulation motivée |
| **Articles & stock** | Catalogue, catégories, conditionnements (farde, carton…), approvisionnements, ajustements, inventaires, seuils d'alerte |
| **Clients & dettes** | Fiches clients, crédits, remboursements, relances WhatsApp/SMS |
| **Caisse & finance** | Encaissements, clôtures de caisse, dépenses, tableau de bord CA/bénéfice |
| **Rapports** | 11+ types (ventes, articles, catégories, vendeurs, top produits, finance, stock, caisse, dépenses, dettes, expirations), exports PDF/Excel signés |
| **Modules métier** | 🏨 Hôtel (chambres, réservations, check-in/out, facture séjour) · 💊 Pharmacie (lots, péremption, blocage de vente expirée) · 🍽️ Restaurant (tables, commandes, écran cuisine, encaissement caisse) · 🎉 Salle des fêtes (salles, calendrier, prestations, avances & soldes) · 🥖 Boulangerie (matières premières, productions, pertes, coût de revient) · 🥩 Boucherie (vente au poids, pas de 0,5 kg, ticket au kg) · 👕 Mode (variantes taille/couleur/marque, recherche par variante) |
| **Équipe** | Collaborateurs, 8 rôles, permissions fines personnalisables par le Super Admin |
| **Assistant IA** | Chat intégré (quotas par packs), actions contrôlées par les droits |
| **Abonnement** | Workflow d'activation vérifié (comptes → finance), essai 7 j / total 30 j, restrictions sans suppression de données |
| **Notifications** | Alerte à chaque vente + rapport de fin de journée (heure configurable) |
| **Légal** | Politique de confidentialité et Conditions d'utilisation intégrées (droit congolais, juridiction de Lubumbashi) |

Plateformes : **Android, Windows, Linux** et **Web** (Flutter). Les données
sont synchronisées en ligne via **Supabase** ; une base **SQLite locale** sert
de repli hors ligne sur les applications natives. Sur le web, l'application
fonctionne entièrement avec Supabase (la base locale SQLite n'est pas
disponible dans un navigateur — les shims `lib/utils/*_stub.dart` neutralisent
ces fonctions).

---

## 2. Architecture

```
lib/
  main.dart            → démarrage : Supabase, notifications, surveillance modules
  config/app_router.dart → toutes les routes (go_router) + middleware de droits
  models/              → entités pures (Article, Chambre, Réservation,
                          Commande, Permission, Rapport…) — testables sans réseau
  services/            → accès Supabase (RPC + tables), session, notifications
  pages/               → écrans (boutique, hôtel, restaurant, admin, réglages)
  ui/accueil/          → registre des cartes du tableau de bord (modules)
  widgets/             → composants partagés (puces de statut, dialogues…)
  db_helper.dart       → base SQLite locale (repli hors ligne)
supabase/migrations/   → 32 migrations SQL idempotentes (0000 → 0031)
test/                  → 479 tests purs (modèles, permissions, rapports, modules)
docs/                  → documentation interne (roadmap, publication, modules)
tools/                 → utilitaires (signature Android : setup_signature.sh)
```

**Règle d'or du socle multi-activités :** profil de modules inconnu, absent ou
vide → l'application retombe sur le comportement complet (aucune régression) ;
la personnalisation d'un profil se fait depuis l'admin, côté serveur.

---

## 3. Configuration technique

### 3.1 Supabase (obligatoire)

L'URL et la clé publique `anon` sont déclarées dans `lib/main.dart`
(`Supabase.initialize(...)`). Le projet de référence :
`https://pqzcliibocndiyqbyddr.supabase.co`.

**Ordre d'exécution des migrations** — Supabase → **SQL Editor** → coller →
*Run*, dans l'ordre des fichiers de `supabase/migrations/` :

```
0000 → 0019   socle (entreprises, référentiels, permissions, modules 1→15)
0020 → 0026   correctifs (énums, rapports, ventes, caisse…)
0027          Module 16 phase A — types d'activités & modules
0028          Module 16 phase B — profils affinés hôtel/restaurant
0029          Module 16 phase C1 — pharmacie (lots & péremption)
0030          Module 16 phase C2 — hôtel (chambres, réservations, réception)
0031          Module 16 phase C3 — restaurant (tables, commandes, cuisine)
0032          Module 16 phase D — rapports par activité (hôtel, restaurant)
0033          Module 16 phase C4 — salle des fêtes (salles, événements)
0034          Module 16 phase C5 — boulangerie (matières, productions)
0035          Module 16 phase C6 — boucherie (articles vendus au poids)
0036          Module 16 phase C8 — variantes (taille, couleur, marque)
0037          Module 16 phase E — packs par modules (groupes tarifaires)
```

⚠️ La migration **0020** doit être exécutée **seule** (PostgreSQL n'autorise
pas d'utiliser une nouvelle valeur d'énum dans la même transaction).
Toutes les autres sont **idempotentes** (relançables sans effet de bord) et
se terminent par des requêtes de vérification.

### 3.2 Réglages en base (`app_settings`)

| Clé | Contenu | Effet |
|---|---|---|
| `ventes` | `{"bloquer_produits_expires": true}` | Bloque la vente d'un article dont la date de péremption est dépassée (pharmacie). Passer à `false` pour l'autoriser |
| `permissions_roles` | `{"roles": {"VENDEUR": {"ventes": ["voir","creer"]}}}` | Personnalisation des permissions par rôle (écran Super Admin → Permissions) ; remplace la matrice par défaut |

**Packs par modules (Module 16 E)** — un groupe tarifaire peut limiter les
modules : `groupes_tarifaires.modules` (`[]` = aucun filtre). Les modules
effectifs d'une entreprise = **profil de l'activité ∩ modules du pack**
(écran admin → Groupes tarifaires → « Modules du pack »).

### 3.3 Réglages dans l'application

| Écran | Réglages |
|---|---|
| **Paramètres** | Infos boutique, notifications (ventes on/off, rapport on/off, heure du rapport), accessibilité (taille du texte), guide, documents légaux |
| **Admin → Types d'activités** | Modules de chaque activité (l'activité détermine les écrans), activation/désactivation, création de nouveaux types |
| **Admin → Permissions** | Matrice rôle × page × action (Super Admin), réinitialisation aux défauts |
| **Admin → Utilisateurs / Entreprises** | Comptes, rattachements, packs multi-entreprises, abonnements |
| **Stock** | Seuil d'alerte par article, inventaires, ajustements |
| **Collaborateurs** | Rôles (VENDEUR, MAGASINIER, COMPTABLE…) |

### 3.4 Secrets de compilation (GitHub Actions)

Pour des APK **signés** (sinon repli clé debug) — Settings → Secrets →
Actions de `Andre-luk/biasharayanguApp` :

| Secret | Valeur |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | keystore `.jks` encodé : `base64 -w0 upload-keystore.jks` |
| `ANDROID_STORE_PASSWORD` / `ANDROID_KEY_PASSWORD` / `ANDROID_KEY_ALIAS` | mots de passe + alias |

L'assistant `tools/setup_signature.sh` configure tout (création du keystore
si oublié, envoi des secrets, re-tag). Détails : `docs/publication_app.md`.

---

## 4. Développement

```bash
flutter pub get          # dépendances
dart analyze lib test    # analyse statique (doit rester à 0 ERREUR)
flutter test             # 567 tests — doit rester 100 % vert
```

> ⛔ **NE JAMAIS lancer `flutter build` localement sur la machine de
> développement** (le build Gradle/CMake complet fige la machine IdeaPad).
> **Tous les builds se font par la CI GitHub.**

### CI/CD (GitHub Actions)

| Workflow | Déclencheur | Rôle |
|---|---|---|
| `.github/workflows/build-apk.yml` | push sur `main` | APK de test (vérification continue) |
| `.github/workflows/build-release.yml` | tag `v*` | Analyse & tests → **APK signé + Linux + Windows (zip + installer)** → création de la release GitHub avec les 4 fichiers |
| `.github/workflows/build-web.yml` | push sur `main`, tag `v*`, manuel | Analyse & tests → **site web (Flutter Web)** → archive `biashara-yangu-web.zip` (artéfact 30 j + release) |

```bash
git tag v1.7.0 && git push origin v1.7.0   # déclenche la release complète
```

### Versions actuelles

- Flutter **3.47.4** / Dart **3.13.3**, app **2.0.0+16**
- Dépendances clés : `supabase_flutter`, `go_router`, `flutter_local_notifications ^22.3.1`
  (avec *core library desugaring* Android), `sqlite3` + `sqflite_common_ffi`
  (SQLite embarquée), `pdf`/`printing` (exports), `mobile_scanner` (scanner)
- Web : `flutter build web --release` validé par la CI ; exports de fichiers et
  impressions disponibles, base SQLite locale réservée aux apps natives

---

## 5. Publication sur les stores

1. La release GitHub fournit `biashara-yangu.apk` **signé** ;
2. La fiche store (Uptodown / APKPure) référence cet APK ;
3. Les notes de mise à jour sont préparées dans `docs/mise_a_jour_vX.Y.Z.md`
   (copier-coller prêt pour la fiche) ;
4. Procédure complète : `docs/publication_app.md`.

---

## 6. Dépannage express

| Symptôme | Cause probable | Solution |
|---|---|---|
| `MSVCP140.dll introuvable` (Windows) | Visual C++ absent | Utiliser le `setup.exe` récent (DLL embarquées) ou installer VC++ Redistributable |
| `Failed to load libsqlite3.so` (Linux) | Ubuntu sans `libsqlite3-dev` | Le bundle embarque `lib/libsqlite3.so` ; sinon `sudo apt install libsqlite3-dev` ou `LD_LIBRARY_PATH=$PWD/lib ./biashara_yangu` |
| Crash Linux ~10 s après lancement | Pilote GPU/Impeller sur certaines machines | Lancer sur une autre machine ou tester `--no-enable-impeller` (voir `docs/publication_app.md §9`) |
| « Fonction non déployée » dans un écran | Migration SQL non exécutée | Exécuter les migrations manquantes (SQL Editor), dans l'ordre |
| Le rapport/la vente échoue après mise à jour | Migration exécutée partiellement | Relancer la migration concernée (idempotente) |

---

## 7. Documents internes

- `docs/roadmap_multi_activites.md` — plan complet des phases A → E
- `docs/publication_app.md` — keystore, releases, dépannage, stores
- `docs/mise_a_jour_v1.x.x.md` — notes de mise à jour pour les fiches store
- `docs/module12_analyse_actions.md`, `module13_agent_ia.md`, `module14_activation.md`,
  `module15_multi_entreprises.md` — documentation par module

---

## 8. Support & éditeur

**La Perle — Lubumbashi, République Démocratique du Congo**
Email : **support@biasharayangu.cd** (lundi → samedi)

Documents légaux intégrés : *Politique & confidentialité* et *Conditions
d'utilisation* (droit congolais — tribunaux de Lubumbashi), accessibles dans
Paramètres → Politique & conditions / Conditions d'utilisation.

