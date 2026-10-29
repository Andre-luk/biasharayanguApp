# Mise à jour v3.3.4 — la version web devient utilisable · connexion mobile

**Version** : 3.3.4 (build 41) — voir `lib/config/app_version.dart`.
**Aucune migration SQL.**

---

## 1. « Sur Chrome de mon téléphone, la connexion ne se connecte pas »

C'était **le** défaut de la version web, et il était bloquant : **il n'y avait
pas de base locale dans le navigateur**.

L'application enregistre tout (comptes, produits, ventes, stock, caisse) dans
une base SQLite locale, puis synchronise avec le serveur. Sur ordinateur et
sur téléphone cette base est fournie par le système. Dans un navigateur, elle
n'existait pas : la connexion réussissait bien côté serveur Supabase, puis
**échouait à la première lecture de la base locale** — d'où l'écran qui
reste immobile, sans message : « rien ne se connecte ».

### Correction

SQLite est désormais **embarqué dans le navigateur** (WebAssembly), exécuté
dans un worker et **persisté dans IndexedDB** — c'est l'implémentation
officielle du projet `sqflite` (`sqflite_common_ffi_web`).

| Avant | Après |
|---|---|
| `…/#/` : catalogue public seulement | catalogue public **+ espace de travail complet** |
| Connexion : le bouton tournait puis rien | connexion, création de compte, vente, stock, rapports |
| Aucune donnée conservée entre deux visites | données conservées (IndexedDB du navigateur) |
| — | mêmes tables, mêmes requêtes SQL que sur Android / ordinateur |

Deux fichiers sont livrés dans `web/` et versionnés dans le dépôt :

- `web/sqlite3.wasm` — le moteur SQLite (compilé en WebAssembly) ;
- `web/sqflite_sw.js` — le worker qui le fait tourner.

Ils sont produits par `dart run sqflite_common_ffi_web:setup` (à relancer avec
`--force` seulement si la dépendance `sqlite3` est mise à jour).

### Les erreurs ne sont plus muettes

Trois filets de sécurité ont été ajoutés dans la page de connexion :

1. si la préparation de l'espace de travail échoue après une connexion
   réussie, un message le dit explicitement au lieu de laisser l'écran figé ;
2. le repli hors ligne (base locale) est protégé : une base indisponible
   n'interrompt plus la connexion ;
3. la lecture du profil local (qui détermine le rôle) ne peut plus faire
   échouer la navigation.

## 2. Page de connexion coupée sur téléphone

Le mode compact ne s'activait qu'en dessous de **620 px** de hauteur. Or un
téléphone en portrait, dans Chrome, dispose de **640 à 800 px utiles** une
fois la barre d'adresse affichée : la carte dépassait donc de l'écran et le
bas (mot de passe oublié, « Explorer les boutiques », numéro de version)
apparaissait coupé.

Trois paliers remplacent le seuil unique :

| Hauteur utile | Rendu |
|---|---|
| ≥ 800 px | mise en page aérée (logo 64 px, phrase d'accroche) |
| 645 – 800 px | **compact** : logo 44 px, accroche masquée, marges 14 px |
| < 645 px | **très compact** : logo 34 px, marges 12 px, phrase explicative du bas masquée |

Résultat vérifié sur **360 × 640**, **390 × 664** et **390 × 844** : la carte
tient entièrement dans l'écran, sans défilement, bouton « Se connecter »
visible.

## 3. Marketplace : libellés rognés

La pastille d'état des cartes produit affichait « **Dispon…** » sur téléphone :
un `Spacer()` dans la rangée partageait la largeur à parts égales avec le
libellé. La rangée utilise maintenant `spaceBetween`, qui pousse la seconde
pastille à droite sans priver la première de sa place. « Disponible » et
« Indisponible » s'affichent en entier.

---

## Vérifications

- `flutter analyze --no-fatal-infos --no-fatal-warnings` : 0 erreur ;
- `flutter test` : 977 tests au vert ;
- `flutter build web --release` : compilé, testé dans Chrome en 360, 390 et
  412 px de large ;
- aucune migration SQL, aucun changement de schéma.
