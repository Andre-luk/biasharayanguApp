# Mise à jour v3.3.2 — version web rapide et icône Biashara

**Version** : 3.3.2 (build 39) — voir `lib/config/app_version.dart`.
**Aucune migration SQL** : cette version ne touche ni la base ni les données.

> Elle reprend tout le contenu de la 3.3.1 (distribution terrain, mode simple,
> pesée, scanner, SerdiPay) et s'occupe de la **version navigateur**.

---

## 1. L'icône : plus de logo Flutter

L'onglet du navigateur, l'écran d'accueil d'un téléphone et le raccourci PWA
affichaient encore le logo Flutter. Ils portent désormais l'emblème de
**Biashara Yangu** (le cercle caddie + téléphone, sans le texte illisible en
32 px).

Fichiers régénérés par un script reproductible —
`python3 tools/generer_icones_web.py` :

| Fichier | Usage |
|---|---|
| `web/favicon.png` (64 px) | onglet du navigateur |
| `web/icons/Icon-192.png`, `Icon-512.png` | installation PWA, Android |
| `web/icons/Icon-maskable-*.png` | icônes « maskable » (Android rogne les bords) |
| `web/apple-touch-icon.png` (180 px) | écran d'accueil iPhone / iPad |
| `web/splash/img/*` | écran de démarrage |

## 2. Le poids : −6 Mo d'images inutiles

| Fichier | Avant | Après |
|---|---|---|
| `assets/user.jpg` (avatar par défaut) | 1,33 Mo — image de **8 000 × 8 000** | 11 Ko (512 px) |
| `assets/utilisateur.jpg` | 1,17 Mo — **4 214 × 5 606** | 20 Ko (512 px) |
| `assets/logo.jpg` | 0,70 Mo — **4 000 × 4 000** | 10 Ko (512 px) |
| `assets/banner.jpg` | 2,10 Mo — **utilisé nulle part** | supprimé |
| `assets/Sans-titre-1.wbm` | 0,49 Mo — fichier Blender | supprimé |

Un avatar affiché dans un cercle de 40 px n'a jamais eu besoin de 8 000 px :
c'est la première cause du temps d'ouverture sur téléphone comme sur le web.

## 3. Le chargement : écran de démarrage crédible

L'ancienne page d'entrée affichait une image fixe, sans rien qui bouge : on ne
savait pas si l'application démarrait ou si elle était bloquée.

La nouvelle page (`web/index.html`) affiche l'emblème, **un anneau de
chargement animé** et « Chargement de Biashara Yangu… », puis s'efface dès le
premier rendu. Elle ajoute aussi :

- `preconnect` vers le serveur de données (la connexion démarre plus tôt) ;
- `theme-color` aux couleurs de la marque, description et aperçu de partage
  (WhatsApp / réseaux) ;
- un `manifest.json` complet : nom, langue `fr`, icônes, couleurs, `scope`.

## 4. Le démarrage : plus jamais bloqué par le réseau

Trois étapes du lancement pouvaient retenir l'écran de démarrage sur une
connexion lente (rafraîchissement de session, notifications, lecture du mode).
Elles sont désormais **bornées** :

| Étape | Limite | Comportement en cas de dépassement |
|---|---|---|
| Initialisation Supabase | 6 s | l'application démarre, la session se rétablit ensuite |
| Notifications locales | 3 s | désactivées pour cette session |
| Mode rapide / complet | 3 s | mode par défaut |

L'écran s'affiche donc **toujours** en quelques secondes ; les données
arrivent après, sans jamais bloquer l'interface.

## 5. Ce qui reste à savoir sur la vitesse du web

Premier chargement : environ **4 Mo compressés** (code 1,7 Mo + moteur de
rendu 2,2 Mo). C'est le prix d'une application complète dans un navigateur.
Ensuite, le service worker conserve tout : les visites suivantes sont
quasi instantanées, et le fichier `netlify.toml` met les ressources en cache
un an.

Piste d'amélioration future (non incluse) : charger à la demande les écrans
lourds et rarement utilisés (carte du marketplace, exports PDF/Excel) avec les
imports différés de Dart — cela retirerait environ 1 Mo au premier chargement.

---

**Validation avant publication** : `flutter analyze` 0 erreur ;
`flutter test` 977 tests.
