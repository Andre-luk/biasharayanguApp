# Mise à jour v3.3.3 — page de connexion et catalogue fluide

**Version** : 3.3.3 (build 40) — voir `lib/config/app_version.dart`.
**Aucune migration SQL.**

---

## 1. « La page de connexion ne s'affiche pas correctement »

Deux causes distinctes ont été trouvées, toutes deux corrigées.

### a) Le lien direct vers la connexion était ignoré

Ouvrir `…/#/login` dans le navigateur affichait le **catalogue**, pas le
formulaire : au démarrage, l'application choisissait sa page d'entrée sans
regarder l'adresse demandée (le comportement voulu sur téléphone, faux sur le
web).

Désormais l'URL du navigateur est **lue avant l'initialisation** du routeur
(le routeur la réécrit ensuite en `/login`, d'où la nécessité de la mémoriser
tout au début) et un lien explicite est respecté :

| Adresse ouverte | Écran affiché |
|---|---|
| `…/` | catalogue public (comportement inchangé) |
| `…/#/login` | **page de connexion** |
| `…/#/biashara/boutique/urembo-market` | la fiche de cette boutique |
| session déjà ouverte | espace de travail habituel |

### b) Écrans bas : le bouton « Se connecter » sortait de l'écran

Sur un ordinateur portable (1366 × 768 moins les barres du navigateur), une
fenêtre réduite ou un téléphone en paysage, la carte de connexion dépassait la
hauteur disponible : le formulaire était coupé et le bouton devenait
difficile à atteindre.

Un **mode compact** s'active sous 620 px de hauteur :

- marges réduites (12 px au lieu de 28), logo à 40 px au lieu de 64 ;
- phrase d'accroche masquée (elle n'apporte rien quand la place manque) ;
- espacements resserrés entre les champs et le bouton.

Le formulaire complet (email, mot de passe, « mot de passe oublié », bouton)
reste visible et cliquable ; le défilement reste possible en dernier recours.

## 2. Marketplace lent : les photos étaient décodées en pleine résolution

Le widget d'image du catalogue (`lib/widgets/photo_biashara.dart`) affichait
les photos **à leur taille d'origine**. Une photo prise au téléphone
(3 000 × 2 000) était donc décompressée en pleine résolution pour une vignette
de 160 px : beaucoup de mémoire, beaucoup de calcul, et des saccades au
défilement — surtout sur un appareil modeste.

Ce qui change :

| Avant | Après |
|---|---|
| Décodage à la taille d'origine | **Décodage à la taille d'affichage** (`cacheWidth` × densité de l'écran, plafonné à 1 080 px) |
| Filtrage coûteux | `FilterQuality.low` (adapté aux vignettes) |
| Apparition brutale / icône figée | **Fondu de 220 ms** dès que l'image est prête |
| Retour au vide au rafraîchissement | `gaplessPlayback` (l'ancienne image reste jusqu'à la nouvelle) |
| Cache d'images par défaut | 220 images / **64 Mo** réservés aux vignettes |

Effet attendu : mémoire divisée par 5 à 10 sur les listes de photos, défilement
fluide, et retour en arrière instantané (les vignettes restent en mémoire).

> Remarque honnête : à ce jour, **aucune photo n'est encore enregistrée** dans
> le catalogue public (les champs `photo`, `logo_url` et `photo_url` sont
> vides). Le visuel de repli aux couleurs de Biashara s'affiche donc partout.
> Dès qu'un commerçant ajoute des photos, elles bénéficient des optimisations
> ci-dessus.

## 3. Mesures faites sur le serveur

- Catalogue public (`rpc_biashara_accueil`) : **0,5 à 0,9 s** de réponse —
  le serveur n'est pas le goulot d'étranglement.
- Page d'accueil du site : **affichée en moins de 3 s** sur cette machine
  (contre plus de 25 s avant la 3.3.2 sur le même poste).

---

**Validation avant publication** : `flutter analyze` 0 erreur ;
`flutter test` 977 tests.
