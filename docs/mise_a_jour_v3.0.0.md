# Mise à jour v3.0.0 — La vitrine, les prix, et l'agent qui suit ses clients

**Version :** 3.0.0 (build 34)
**Migrations SQL :** `20260916000076`
*(à exécuter dans l'ordre ; le programme SQL fait partie de l'installation)*
**Tests :** 915/915 ✅

---

## En une phrase

**Un seul formulaire pour créer un article, la péremption disponible partout où
elle a du sens, les prix que vous écrivez qui remplacent vraiment ceux du pack,
l'agent qui retrouve ses propres boutiques — et une marketplace qui ressemble
enfin à une vitrine d'application moderne.**

---

## Les cinq corrections de cette version

### 1. La date de péremption n'est plus réservée à la pharmacie

Le champ « Lot & péremption » (et donc le suivi des expirations) dépend d'un
**module**. Il n'était ouvert qu'à la **pharmacie** : impossible de gérer les
dates sur une alimentation, un dépôt de boissons ou une boutique ordinaire —
alors que ces commerces ont exactement le même problème.

Le module **« Lots & péremption »** est désormais **ouvert par défaut** aux
activités génériques (**boutique, dépôt, autre**). Les profils métier (hôtel,
restaurant, salle des fêtes…) ne sont pas touchés : ils n'en ont pas besoin.
L'Expert peut toujours le retirer activité par activité depuis
**Référentiels → Types d'activités**.

> Dès la migration exécutée, le champ « Lot & péremption » et la carte
> **Expirations** apparaissent dans la boutique. Aucune action de votre part.

### 2. « Ajouter un produit » et « Nouvel article » : **un seul formulaire**

C'étaient **deux écrans différents** pour la même chose :

| | Ancien « Ajouter un produit » | « Nouvel article » |
|---|---|---|
| Lot & péremption | ✗ | ✓ |
| Variantes (taille, couleur) | ✗ | ✓ |
| Conditionnements | ✗ | ✓ |
| Import / QR | ✗ | ✓ |

Deux jeux de champs, deux comportements — et aucun moyen de savoir lequel
allait s'ouvrir. Désormais **tout bouton qui mène à la création d'un article
ouvre LE MÊME formulaire** : l'ancienne adresse redirige automatiquement. Un
seul endroit à connaître, un seul endroit à maintenir.

### 3. Le prix que vous écrivez **remplace** celui du pack

Deux vraies causes, toutes deux corrigées :

1. **le pack reprenait la main** : dès que vous changiez d'activité ou de pack,
   les deux champs étaient **réécrits** — votre saisie disparaissait sans le
   moindre message. Le pack **propose** maintenant ses montants, il **n'écrase
   plus** ce que vous avez tapé ;
2. **« 30.000 » était lu comme 30** : le séparateur de milliers était pris pour
   une décimale. « 30.000 », « 30 000 », « 1.500.000 CDF » sont maintenant lus
   pour ce qu'ils valent. Un montant illisible est **refusé** — jamais remplacé
   par une valeur inventée.

Un encadré bleu, sous les deux champs, rappelle la règle : *« Le pack remplit
ces deux montants. Si vous en écrivez un vous-même, c'est LE VÔTRE qui est
enregistré. »* Et l'aperçu du pack, juste en dessous, montre le prix réellement
retenu avant d'enregistrer.

### 4. L'agent retrouve **ses** boutiques et suit leurs abonnements

C'est le constat le plus gênant : *« je vérifie dans l'agent qui a créé la
boutique, je ne trouve rien comme entreprise, alors que c'est cet agent qui a
tout créé »*.

L'agent voyait la liste des boutiques **prises en charge** — et un compte créé
par lui n'était rattaché à personne. Deux corrections :

- **le créateur devient le référent** : si un agent terrain crée le compte, le
  dossier est à lui (déclencheur automatique) — et **les comptes déjà créés
  avant cette version sont repris en une fois**, sans rien ressaisir. Un
  référent déjà désigné n'est **jamais** remplacé ;
- **un nouvel écran « Abonnements de mes clients »** : pour chaque boutique,
  l'étape du dossier, l'échéance et les jours restants, ce qui a été encaissé,
  ce qu'il reste à payer, le contact du propriétaire — et un accès direct à **la
  fiche complète** du compte.

⚠️ **Lecture seule, et c'est volontaire** : l'agent **suit**, il n'encaisse pas
et n'active pas. C'est la Finance qui décide.

### 5. La marketplace devient une vraie vitrine

Fini les rectangles cernés de gris. Le catalogue public adopte le langage
d'une boutique d'applications moderne (Play Store / Shopify) :

- **un cadre net** : coins arrondis, liseré discret, ombre douce — le produit
  est mis en valeur ;
- **le prix dans une pastille colorée**, lu d'un seul coup d'œil ;
- **la boutique sur une ligne « éditeur »**, avec sa vignette ronde ;
- **la disponibilité en pastille d'état** (verte / rouge), lisible même sur une
  photo claire grâce à un voile dégradé ;
- **une grille responsive** à la place de la rangée horizontale : 2 colonnes
  sur téléphone, 3 sur tablette, 4 sur bureau — et un bouton **« Voir tout le
  catalogue »** ;
- **les boutiques en bandeau vitrine** : devanture en couverture, logo en
  médaillon, nom et distance sur l'image, « Position confirmée » conservé.

La proportion des cartes **suit l'échelle de texte** du téléphone : un
utilisateur qui agrandit les caractères obtient des cartes plus hautes, jamais
un texte coupé. C'est vérifié par des tests de mise en page.

---

## Migrations de cette version

| # | Fichier | Ce qu'elle fait |
|---|---|---|
| 76 | `20260916000076_peremption_et_boutiques_agent.sql` | Ouvre « Lots & péremption » aux activités génériques · le créateur d'une entreprise en devient le référent (déclencheur + reprise des données existantes) · `rpc_agent_mes_boutiques()` · la fiche d'un compte accessible à son agent référent |

**Idempotente** : relançable sans effet de bord. Elle se termine par un rapport
de contrôle (profils avec péremption, comptes rattachés à leur agent).

> ⚠️ Rappel : la migration **74** (garde-fou des rôles) doit elle aussi être
> exécutée si ce n'est pas déjà fait.

---

## Ce qu'il faut faire après la mise à jour

1. Exécuter la migration **76** (et la **74** si ce n'est pas fait).
2. Dans l'application : **Paramètres → Mettre à jour** (ou réinstaller l'APK).
3. Vérifier, côté plateforme : **Entreprises →** la liste doit montrer les
   comptes créés par un agent, et, côté agent, l'entrée
   **« Abonnements de mes clients »** doit afficher ses boutiques.

---

## Compatibilité

- Aucune donnée existante n'est supprimée ni renommée.
- Les fiches produit et boutique gardent **exactement** les mêmes informations ;
  seule leur présentation change.
- Les montants déjà enregistrés ne sont pas modifiés par le nouveau lecteur de
  montants : il ne s'applique qu'à ce qui est **saisi**.
