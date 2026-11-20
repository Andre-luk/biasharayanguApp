# Le module Pharmacie — guide complet

**Application** : Biashara Yangu · **Public** : pharmacien propriétaire, responsable, caissier, magasinier, comptable  
**Version du document** : 20 novembre 2026 (application 3.10.x)  
**Complète** : `docs/guide_module_pharmacie.html` (ancien guide, sans la partie collaborateurs)

---

## Sommaire

1. [En une page](#1-en-une-page)
2. [Ce que fait le module](#2-ce-que-fait-le-module)
3. [Mise en route, étape par étape](#3-mise-en-route-étape-par-étape)
4. [Les articles (médicaments)](#4-les-articles-médicaments)
5. [Les lots : réception, consultation, retrait](#5-les-lots--réception-consultation-retrait)
6. [La vente au comptoir](#6-la-vente-au-comptoir)
7. [Alertes de péremption](#7-alertes-de-péremption)
8. [**Ajouter et gérer les collaborateurs**](#8-ajouter-et-gérer-les-collaborateurs)
9. [Rapports et exports](#9-rapports-et-exports)
10. [Bonnes pratiques](#10-bonnes-pratiques)
11. [Dépannage (questions fréquentes)](#11-dépannage-questions-fréquentes)
12. [Annexe technique](#12-annexe-technique)

---

## 1. En une page

Une **pharmacie** n'est pas une boutique comme les autres : un médicament a une
**date de péremption**, il arrive **par lots** (numéro de lot, fournisseur,
prix d'achat), et il doit être vendu **d'abord quand il périme le plus tôt**
(règle FEFO : *First Expired, First Out*).

Le module Pharmacie ajoute donc, à toutes les fonctions d'une boutique
(articles, stock, caisse, clients, dépenses, rapports, QR codes), trois
capacités :

| Capacité | Ce que vous obtenez |
|---|---|
| **Lots** | Chaque livraison devient un lot traçable : numéro, péremption, quantité reçue, quantité restante, fournisseur, prix d'achat |
| **Péremption** | Alerte réglable (7 → 365 jours), écran « Expirations », rapport dédié, et **vente refusée** pour un produit expiré |
| **FEFO** | À chaque vente, le stock est prélevé automatiquement sur le lot qui périme le plus tôt |

Trois écrans seulement sont propres à la pharmacie :

* la section **Lot & péremption** dans la fiche article ;
* l'écran **Lots & péremption** d'un article (icône 🗃️ en haut de la fiche) ;
* l'écran **Expirations** (et sa carte sur l'accueil).

Tout le reste (vente, caisse, stock, clients, rapports) fonctionne comme dans
une boutique : mêmes écrans, mêmes gestes.

---

## 2. Ce que fait le module

### 2.1 La liste des modules installés pour une pharmacie

Quand le métier de l'espace est **« Pharmacie »**, l'application installe et
affiche :

`ventes` · `produits` · `stock` · `qr` · `caisse` · `clients` · `finance` ·
`employes` · `rapports` · `assistant_ia` · **`lots_expiration`**

Le module `lots_expiration` est celui qui ajoute tout ce qui suit. Il
n'apparaît **que** pour les activités qui en ont besoin (pharmacie,
alimentation, dépôt…), jamais pour un salon de coiffure.

### 2.2 Le cycle de vie d'un médicament

```text
   Article (nom, prix de vente)
            |
            v
   Reception d'un lot  (numero + peremption + quantite)
            |
            +------------> Ecran « Expirations » + carte d'accueil
            |                 (alerte a J-90 par defaut)
            v
   Stock de la pharmacie
            |
            v
   Vente au comptoir  --FEFO-->  le lot qui perime le plus tot part en premier
            |
            v
   Retrait de lot (casse / rappel / peremption) -> stock diminue, trace

   Un produit EXPIRE ne peut pas etre vendu : la caisse refuse la vente.
```

### 2.3 Les règles appliquées par le serveur (jamais contournables)

| Règle | Effet concret |
|---|---|
| Un lot = une réception | La date de péremption et la quantité reçue d'un lot **ne se modifient pas**. Nouvelle livraison → nouveau lot. |
| Numéro de lot obligatoire | À la réception, impossible d'enregistrer un lot sans numéro. |
| Péremption obligatoire | À la réception, impossible d'enregistrer un lot sans date de péremption. |
| Lot déjà périmé refusé | Un lot dont la date est passée est refusé à l'entrée : il faut le refuser au fournisseur, pas l'entrer en stock. |
| Produit expiré = vente bloquée | Un article dont la date de péremption est dépassée ne peut plus être vendu, quel que soit le stock. Peut être désactivé par la plateforme si besoin (réglage `ventes.bloquer_produits_expires`). |
| Stock valide seulement | Si un article est suivi par lots, le stock vendable est la somme des **lots non périmés et non retirés**. Un lot périmé ne « sauve » jamais une vente. |
| FEFO | Le stock est prélevé sur le lot le plus proche de la péremption, puis le suivant. |
| Retrait tracé | Retirer un lot demande un **motif** (au moins 3 caractères) et crée un ajustement de stock + une ligne d'historique + une ligne au journal d'audit. |

### 2.4 Ce qui est tracé

* **Journal d'audit** : `LOT_RECU`, `LOT_RETIRE` (qui, quand, quel produit, quel lot, quelle quantité, quel motif).
* **Historique des lots** : chaque mouvement (réception, vente, retrait) avec la quantité et, pour une vente, le lien vers la vente.
* **Mouvements de stock** : le retrait d'un lot crée un ajustement négatif, donc le stock affiché reste toujours juste.

---

## 3. Mise en route, étape par étape

### Étape 1 — Créer l'entreprise avec le métier « Pharmacie »

1. **Créer l'entreprise** (écran de démarrage ou *Paramètres → Mes entreprises*).
2. Choisir le type d'activité **Pharmacie**.
3. L'application installe automatiquement les modules de la pharmacie, dont
   `lots_expiration`.

> Si l'entreprise existe déjà en « Boutique » : ouvrir la fiche de
> l'entreprise → carte **Type d'activité** → **Changer le type** → *Pharmacie*.
> Les modules et les écrans suivent immédiatement (y compris les écrans déjà
> ouverts après actualisation).

### Étape 2 — Vérifier l'espace de travail

En haut de l'écran, le sélecteur d'espace doit afficher la **pharmacie**
(icône 💊). Toutes les données sont cloisonnées par espace : si vous restez sur
une autre boutique, vous ne verrez ni ses articles ni ses lots.

### Étape 3 — Régler l'alerte de péremption

*Paramètres → **Alerte de péremption*** → choisir **90 j** (ou un nombre de
jours entre 1 et 365).

C'est le délai à partir duquel un produit est signalé « expire bientôt ». Il
est utilisé par la liste des articles, l'écran **Expirations**, la carte de
l'accueil et le rappel de fin de journée.

> ⚠️ Ce réglage ne change **pas** le blocage de vente d'un produit déjà expiré :
> un produit périmé reste invendable, quel que soit le délai choisi.

### Étape 4 — Créer les articles (médicaments)

Voir le chapitre 4.

### Étape 5 — Enregistrer la première réception

Voir le chapitre 5.

### Étape 6 — Ajouter les collaborateurs

Voir le chapitre 8.

### Étape 7 — Ouvrir la caisse

*Caisse* → encaisser normalement. Le format de vente (unité / plaquette /
boîte) est proposé s'il existe des conditionnements sur l'article.

---

## 4. Les articles (médicaments)

*Articles → bouton **+** (ou **Nouvel article**)*

### 4.1 Les champs à ne pas oublier

| Champ | Pourquoi c'est important en pharmacie |
|---|---|
| **Nom** | Tel qu'il est écrit sur la boîte (nom + dosage) |
| **Catégorie** | Famille thérapeutique, ou « Divers » |
| **Prix de vente** | Prix au comptoir (par unité de base : comprimé, flacon…) |
| **Prix d'achat** | Sert au calcul de la marge (rapports) |
| **Seuil d'alerte** | Déclenche l'alerte « stock bas » |
| **Unité** | Comprimé, boîte, flacon, sachet… |
| **Numéro de lot** *(facultatif)* | Résumé affiché ; le détail vit dans les lots (chapitre 5) |
| **Date de péremption** *(facultatif)* | Résumé du **lot valide le plus proche**. C'est cette date qui bloque la vente quand elle est dépassée |

La section **Lot & péremption** n'apparaît que si l'activité a le module
`lots_expiration` (donc : en pharmacie, oui).

Sous la date, l'application affiche tout de suite le verdict :

* « Produit EXPIRÉ (…) — la vente sera refusée en caisse. »
* « Expire bientôt : dans N jours. »
* ou rien (produit valide).

### 4.2 Les formats de vente (plaquette, boîte)

Un médicament se vend souvent à l'unité **et** par plaquette ou par boîte.

1. Ouvrir la fiche de l'article.
2. Section **Conditionnements** → **Ajouter**.
3. Indiquer le libellé (« Plaquette de 10 »), le nombre d'unités de base
   contenues (10) et le **prix de vente du format**.

En caisse, l'application propose alors le choix du format, avec des prix
**lus en base** (jamais saisis au comptoir). Chaque format peut aussi recevoir
son propre QR code (module QR codes).

---

## 5. Les lots : réception, consultation, retrait

### 5.1 Accéder aux lots d'un article

*Articles* → ouvrir l'article → icône 🗃️ **Lots & péremption** (en haut à
droite).

L'écran affiche, pour l'article :

* le **stock fiche** (quantité de la fiche article) et le **stock vendable**
  (somme des lots non périmés et non retirés — c'est lui qui autorise la
  vente) ;
* la liste des lots : numéro, péremption, quantité reçue, **quantité restante**,
  fournisseur, prix d'achat, état (valide / périmé / retiré) ;
* l'historique des mouvements du lot.

### 5.2 Réceptionner un lot (livraison d'un fournisseur)

1. Sur l'écran **Lots & péremption**, appuyer sur **Réception de lot**.
2. Remplir :

| Champ | Obligatoire | Remarque |
|---|---|---|
| **Numéro de lot** | Oui | Tel qu'imprimé sur la boîte (ex. `LOT-2026-A17`) |
| **Péremption** | Oui | Refusée si elle est déjà passée |
| **Fabrication** | Non | Refusée si elle est postérieure à la péremption |
| **Quantité reçue** | Oui | Strictement supérieure à zéro, en unités de base |
| **Prix d'achat / unité** | Non | Sert au calcul de la marge |
| **Fournisseur** | Non | Texte libre |
| **Observations** | Non | Facture, bon de livraison… |

3. **Enregistrer**.

Résultat : le stock de l'article augmente de la quantité reçue, le lot apparaît
dans la liste, un mouvement « réception » est créé et une ligne `LOT_RECU` est
ajoutée au journal d'audit.

> 💡 **Une livraison = un lot.** Si le fournisseur livre deux fois le même
> produit avec deux dates différentes, faites **deux réceptions**. Si vous
> saisissez deux fois le même numéro de lot avec la même date, l'application
> refuse (« Ce numéro de lot existe déjà pour cet article avec cette date de
> péremption »).

### 5.3 Retirer un lot (casse, rappel, péremption)

1. Sur l'écran **Lots & péremption**, appuyer sur **Retirer du stock** sur la
   ligne du lot.
2. Saisir le **motif** (obligatoire, au moins 3 caractères) :
   « casse », « rappel fournisseur », « périmé », « vol »…
3. Confirmer **Retirer**.

Résultat : la quantité restante du lot passe à **0**, le stock diminue d'autant
(ajustement tracé), un mouvement « retrait » est enregistré et une ligne
`LOT_RETIRE` est ajoutée au journal d'audit.

> Un lot retiré ne peut pas être retiré deux fois. Les lots périmés **non
> retirés** restent visibles mais ne sont jamais vendus.

### 5.4 Entrée de stock simple ou réception de lot ?

| | **Entrée de stock** (approvisionnement) | **Réception de lot** (pharmacie) |
|---|---|---|
| Où | *Stock → Entrée de stock* | *Fiche article → 🗃️ → Réception de lot* |
| Saisie | Quantité en unités ou en cartons | Numéro de lot + péremption obligatoires |
| Stock | Augmente | Augmente |
| Péremption | Non suivie | Suivie, alerte, blocage à l'expiration |
| Usage pharmacie | Déconseillé pour les médicaments | **À utiliser systématiquement** |

### 5.5 Les messages d'erreur et leur signification

| Message | Cause | Que faire |
|---|---|---|
| `LOT_OBLIGATOIRE` / « Le numéro de lot est obligatoire » | Champ vide | Saisir le numéro imprimé sur la boîte |
| `PEREMPTION_OBLIGATOIRE` | Date absente | Choisir la date de péremption |
| `PEREMPTION_PASSEE` | Le lot est déjà périmé | Refuser le lot au fournisseur |
| `DATES_INCOHERENTES` | Fabrication après péremption | Corriger la date de fabrication |
| `QUANTITE_INVALIDE` | Quantité ≤ 0 | Saisir la quantité réellement reçue |
| `LOT_DOUBLON` | Même numéro + même date | Vérifier la livraison, ou corriger le numéro |
| `MOTIF_OBLIGATOIRE` | Motif trop court | Écrire la raison du retrait |
| `LOT_DEJA_RETIRE` | Lot déjà sorti | Aucune action : il est déjà à zéro |
| `DROIT_REFUSE` | Rôle sans droit stock | Demander au propriétaire d'attribuer le rôle Magasinier |
| `HORS_BOUTIQUE` | Article/lot d'un autre espace | Basculer sur la bonne pharmacie |

---

## 6. La vente au comptoir

*Caisse* → scanner ou choisir l'article → choisir le format (unité, plaquette,
boîte) → encaisser.

Ce que le serveur vérifie **avant** d'accepter la vente :

1. **Produit expiré → refus** : « *X* est expiré depuis le JJ/MM/AAAA : vente
   bloquée. »
2. **Article suivi par lots → stock valide** : seuls les lots non périmés et
   non retirés comptent. Sinon : « Stock valide insuffisant pour *X* : N
   vendable(s) hors lots périmés. »

Puis, une fois la vente acceptée, le stock est prélevé **FEFO** : le lot qui
périme le plus tôt est consommé en premier, et le suivant si nécessaire. Chaque
prélèvement est écrit dans l'historique du lot avec le lien vers la vente.

> Un produit **sans** date de péremption n'est jamais bloqué : il se comporte
> comme un article de boutique ordinaire.

---

## 7. Alertes de péremption

Le module vous prévient à **cinq** endroits :

1. **Fiche article** — verdict immédiat sous la date (expiré / expire bientôt).
2. **Liste des articles** — chaque ligne affiche sa péremption (icône rouge =
   expiré, orange = expire bientôt), avec le délai réglé pour la pharmacie.
3. **Carte « Expirations » sur l'accueil** — compte des produits à traiter ;
   elle passe en alerte rouge dès qu'il y en a au moins un.
4. **Écran Expirations** (*Accueil → carte **Expirations***, ou
   `/main/articles/expirations`) — trois compteurs : **Expiré**, **Expire
   bientôt**, **Valide**, triés par urgence, avec le nombre de jours restants.
5. **Rappel de fin de journée** — la notification de clôture rappelle les
   produits expirés / proches de la péremption.

Le seuil « expire bientôt » est celui réglé dans *Paramètres → Alerte de
péremption* (90 jours conseillés en pharmacie).

---

## 8. Ajouter et gérer les collaborateurs

> En pharmacie, l'équipe se gère avec l'écran **Mon Équipe**, commun à toutes
> les activités. Il n'y a pas d'écran d'équipe spécifique comme au pressing.

### 8.1 Qui peut le faire

* **Propriétaire** de l'entreprise, ou collaborateur ayant le rôle
  **Responsable (tous les droits)**.
* Un **Vendeur**, un **Magasinier** ou un **Comptable** ne voit pas cet écran.
* La plateforme (Super Administrateur) peut aussi intervenir, voir 8.7.

### 8.2 Le chemin le plus court

Deux accès mènent au même écran **Mon Équipe** :

* **Accueil** → bouton **Collaborateurs** (sous les raccourcis) ;
* **Paramètres → section Équipe → « Mes vendeurs »**
  (sous-titre : « Ajouter ou supprimer des collaborateurs »).

### 8.3 Ajouter un collaborateur, champ par champ

1. Sur **Mon Équipe**, appuyer sur le bouton **+** (ou *Nouveau collaborateur*).
2. Remplir la fiche :

| Champ | Obligatoire | Ce qu'il faut savoir |
|---|---|---|
| **Nom** | Oui | Nom de famille |
| **Prénom** | Non | |
| **E-mail** | Oui | **C'est l'identifiant de connexion.** Une adresse = un seul compte sur toute la plateforme |
| **Téléphone** | Non | Utile pour joindre le collaborateur |
| **Mot de passe** | Oui | **8 caractères minimum** — à communiquer vous-même au collaborateur |
| **Rôle** | Oui | Voir le tableau 8.4 |
| **Boutique / espace** | Oui (par défaut : l'espace actif) | Détermine ce que le collaborateur voit en se connectant. En pharmacie : la pharmacie |

3. **Enregistrer**.

Le compte est créé **immédiatement** : aucun code d'invitation, aucun e-mail de
validation. Le collaborateur peut se connecter tout de suite avec son e-mail et
le mot de passe que vous venez de saisir.

Message de confirmation : « Compte de *Nom* créé : il peut se connecter dès
maintenant. »

> 🛠️ Correctif 177 : l'espace de travail proposé par défaut est celui de
> **votre entreprise** (et non celui d'une autre entreprise du même patron).
> Choisissez toujours **la pharmacie** dans le champ « Boutique / espace »
> si votre compte gère plusieurs activités.

### 8.4 Les rôles et ce qu'ils permettent

| Rôle proposé | Pour qui | Ce qu'il peut faire |
|---|---|---|
| **Vendeur / caissier** | Comptoir | Vendre, encaisser, consulter les articles. **Ne modifie jamais un prix** (règle appliquée par le serveur) |
| **Magasinier / stock** | Réception, rayons | Entrées de stock, réceptions de lot, retraits de lot, inventaire, ajustements |
| **Comptable** | Administration | Dépenses, finances, rapports, exports |
| **Responsable (tous les droits)** | Gérant, pharmacien adjoint | Tout ce que fait le propriétaire dans l'entreprise, y compris **gérer l'équipe** |

Les droits détaillés viennent de la matrice de permissions du module 4 : la
plateforme peut les ajuster (elle ne fait jamais confiance au téléphone pour
cela — chaque action est revérifiée côté serveur).

> **Principe de moindre privilège** : donnez le rôle *Vendeur* à un caissier,
> pas *Responsable*. Un compte *Responsable* peut créer d'autres comptes et
> supprimer des données.

### 8.5 Modifier un collaborateur

Sur sa ligne → **Modifier** :

* changer le **rôle** (ex. Vendeur → Magasinier) ;
* **activer / désactiver** le compte (désactivé = ne peut plus se connecter) ;
* **réinitialiser le mot de passe** (8 caractères minimum) ;
* changer l'**espace d'affectation** (utile si la pharmacie a plusieurs
  points de vente).

Message de confirmation : « *Nom* mis à jour. » Les changements sont effectifs
à la connexion suivante (ou immédiatement pour une désactivation).

### 8.6 Supprimer un collaborateur

Sur sa ligne → **Supprimer** → taper **SUPPRIMER** dans le champ de confirmation
→ confirmer.

Ce qui se passe :

* son **profil** et son **compte de connexion** sont supprimés : il ne peut plus
  se connecter ;
* ses **ventes, encaissements, lots et historiques restent** dans la pharmacie
  (l'auteur est simplement détaché) ;
* une ligne `COLLABORATEUR_SUPPRIME` est écrite au journal d'audit ;
* le propriétaire ne peut pas être supprimé par cet écran, et vous ne pouvez pas
  supprimer votre propre compte.

Pour une absence temporaire, préférez **désactiver** plutôt que supprimer : le
compte reste, l'accès est fermé.

> 🛠️ Correctif 176 : jusqu'au 20/11/2026, ce bouton échouait toujours (la
> fonction appelée n'existait pas en base). Il fonctionne dès que la migration
> `20260916000176_suppression_collaborateur.sql` est exécutée.

### 8.7 Cas particuliers

| Situation | Ce qu'il faut faire |
|---|---|
| La personne a **déjà un compte** Biashara Yangu (autre entreprise) | Ne créez pas de doublon : la création échoue avec « Cette adresse e-mail est déjà utilisée ». Utilisez le **rattachement** depuis la fiche entreprise (Super Administrateur) ou choisissez une autre adresse |
| C'est le **Super Administrateur** qui installe l'équipe | *Super Admin → Entreprises → fiche de la pharmacie → **Gérer les utilisateurs*** : rattacher un compte existant, ou vérifier qui est rattaché |
| Le collaborateur **ne voit pas la pharmacie** | Son **espace d'affectation** est probablement une autre boutique : Modifier → choisir la pharmacie |
| Le collaborateur **ne voit pas les lots** | Son rôle n'a pas le droit `stock` : passer en **Magasinier** ou **Responsable** |
| Le patron quitte la pharmacie | Ne supprimez pas son compte : changez son rôle ou créez un nouveau *Responsable*. Le propriétaire de l'entreprise ne peut pas être supprimé par ce biais |

### 8.8 Les erreurs d'ajout, traduites

| Message affiché | Signification |
|---|---|
| « Seul le propriétaire peut créer ou modifier un collaborateur. » | Votre rôle ne le permet pas |
| « Indiquez le nom du collaborateur. » | Nom vide |
| « Adresse e-mail invalide : elle sert d'identifiant de connexion. » | E-mail mal formé |
| « Le mot de passe doit comporter au moins 8 caractères. » | Mot de passe trop court |
| « Choisissez un rôle valide pour ce collaborateur. » | Rôle absent ou inconnu |
| « Cette adresse e-mail est déjà utilisée. Choisissez-en une autre. » | Compte existant |
| « Ce collaborateur n'appartient pas à votre entreprise. » | Ligne périmée : actualisez l'écran |
| « Tapez SUPPRIMER pour confirmer la suppression. » | Confirmation non saisie (suppression) |
| « Le propriétaire de l'entreprise ne peut pas être supprimé ici. » | Cible = compte propriétaire |
| « Suppression bloquée par un historique… » | Migration 174 non exécutée |
| « Vous ne pouvez pas modifier votre propre compte ici. » | Utilisez *Paramètres → Changer le mot de passe* |
| « Session expirée : reconnectez-vous. » | Session terminée : se reconnecter puis recommencer |

### 8.9 Bonnes pratiques d'équipe

* **Un compte par personne** : jamais un compte partagé « caisse » — sinon
  l'historique des ventes ne dit plus qui a vendu quoi.
* Le mot de passe du **propriétaire ne se partage pas** : créez un
  *Responsable* pour le gérant.
* Créez les comptes **le jour de l'embauche**, désactivez-les **le jour du
  départ**.
* Vérifiez une fois par mois la liste **Mon Équipe** : un ancien vendeur encore
  actif est un risque.
* Chaque collaborateur doit avoir une **adresse e-mail qui lui appartient**
  (numéro + nom, ou adresse personnelle).

---

## 9. Rapports et exports

*Rapports* (module `rapports`) → choisir le type :

| Rapport | Contenu utile en pharmacie |
|---|---|
| **Expirations (pharmacie)** | Produits expirés ou proches de la péremption, triés par urgence, avec l'horizon en jours. Apparaît uniquement si le module `lots_expiration` est actif |
| **Ventes** | Journal des ventes de la période, par article et par vendeur |
| **Stock** | Quantités, seuils, valeur du stock |
| **Finance / Dépenses** | Recettes, dépenses, marge |
| **Dettes clients** | Restes à recouvrer et ancienneté |

Chaque rapport peut être **téléchargé en PDF** (mise en page prête à imprimer)
ou en **Excel**, et reste consultable dans l'historique des rapports.

---

## 10. Bonnes pratiques

1. **Enregistrez la réception avant de mettre en rayon.** Un médicament vendu
   sans lot fausse le FEFO et l'inventaire.
2. **Un lot par livraison**, jamais « on ajoutera la date plus tard » — la date
   d'un lot est immuable.
3. **Réglez l'alerte à 90 jours** : c'est le délai qui laisse le temps de
   retourner un stock au fournisseur.
4. **Retirez les lots périmés** au lieu de les laisser en rayon : ils
   n'apparaîtront plus comme vendables et le rapport sera propre.
5. **Renseignez le prix d'achat** à la réception : sans lui, la marge des
   rapports est incomplète.
6. **Créez les conditionnements** (plaquette, boîte) plutôt que de bricoler des
   prix au comptoir.
7. **Un compte par vendeur**, revu chaque mois.
8. **Scannez le QR code** de l'étiquette plutôt que de chercher à la main :
   l'article est identifié sans ambiguïté, même entre deux espaces de la même
   entreprise.

---

## 11. Dépannage (questions fréquentes)

**Je ne vois pas la section « Lot & péremption » dans la fiche article.**
→ L'activité de l'espace n'est pas « Pharmacie ». Fiche de l'entreprise →
**Type d'activité** → **Changer le type**. Puis actualisez.

**Je ne vois pas l'icône 🗃️ « Lots & péremption ».**
→ Même cause (module `lots_expiration` absent), ou votre rôle n'a pas le droit
`stock` en lecture.

**L'écran Expirations est vide alors que j'ai des dates.**
→ Vous êtes sur le mauvais espace (les données sont cloisonnées), ou aucune
date de péremption n'est enregistrée sur les articles. Vérifiez la fiche
article.

**La caisse refuse une vente : « est expiré depuis le … ».**
→ La date de péremption de l'article est dépassée. Retirez le lot concerné,
puis mettez à jour l'article (nouvelle réception avec un lot valide).

**La caisse refuse une vente : « Stock valide insuffisant ».**
→ Le stock existe, mais uniquement dans des lots périmés ou retirés. Retirez
ces lots, puis réceptionnez la nouvelle livraison.

**J'ai enregistré une réception mais le stock n'a pas bougé.**
→ Actualisez l'écran du stock. Si rien ne change, regardez que la réception
s'est bien terminée (message de confirmation) : un `LOT_DOUBLON` ou un
`PEREMPTION_PASSEE` interrompt l'enregistrement.

**Je veux corriger la date de péremption d'un lot.**
→ Impossible : c'est volontaire. Retirez le lot (motif « erreur de saisie ») et
refaites une réception correcte.

**Un collaborateur a oublié son mot de passe.**
→ *Mon Équipe → sa ligne → Modifier → nouveau mot de passe*. Aucun e-mail n'est
nécessaire.

**Je ne trouve pas le bouton pour ajouter un collaborateur.**
→ Vous n'avez pas le rôle Propriétaire/Responsable, ou vous êtes dans un autre
espace. Le bouton est sur **Mon Équipe** (Accueil → **Collaborateurs**).

**Puis-je vendre sans date de péremption ?**
→ Oui : un article sans date n'est jamais bloqué. Mais en pharmacie, c'est
déconseillé — vous perdez l'alerte et le FEFO.

---

## 12. Annexe technique

*(Pour l'équipe technique et la plateforme.)*

### 12.1 Objets en base

| Objet | Rôle |
|---|---|
| `produits.lot_numero`, `produits.date_expiration` | Résumé du lot valide le plus proche (mis à jour par `lots_rafraichir_peremption`) |
| `produits_lots` | Un lot : `numero_lot`, `date_fabrication`, `date_peremption`, `quantite_recue`, `quantite_restante`, `prix_achat_unitaire`, `fournisseur`, `retire_le`, `motif_retrait` |
| `produits_lots_mouvements` | Historique : `reception`, `vente`, `retrait` (avec `vente_id`) |
| `app_settings['ventes'].bloquer_produits_expires` | Blocage de vente des produits expirés (défaut `true`) |
| `app_settings['peremption']` | Délai d'alerte en jours (1–365) |

### 12.2 Fonctions serveur

| Fonction | Usage |
|---|---|
| `rpc_lot_recevoir(produit, numero_lot, peremption, quantite, prix_achat, fournisseur, fabrication, observations)` | Réception d'un lot |
| `rpc_lot_retirer(lot_id, motif)` | Retrait d'un lot (quantité restante → 0) |
| `rpc_lots_lister(produit)` | Lots + stock valide d'un article |
| `rpc_lots_alertes()`, `rpc_lots_ecarts()` | Alertes et écarts de stock (outils de contrôle) |
| `rpc_peremption_config()`, `rpc_peremption_definir_delai(jours)` | Lecture / réglage du délai d'alerte |
| `rpc_rapport_entreprise(type = 'expirations', jours)` | Rapport Expirations |
| `rpc_collaborateurs_lister()`, `rpc_collaborateur_creer(...)` | Équipe : liste et création |
| `rpc_collaborateur_maj(...)` | Équipe : rôle, état, mot de passe, espace |
| `rpc_collaborateur_supprimer(id, 'SUPPRIMER')` | Équipe : suppression (alias `delete_collaborateur`) |

### 12.3 Triggers de vente

| Trigger | Moment | Rôle |
|---|---|---|
| `trg_vente_lots_controle` | `BEFORE INSERT` sur `ventes` | Refuse `PRODUIT_EXPIRE` et `STOCK_LOT_INSUFFISANT` (stock valide seulement) |
| `trg_vente_lots_fefo` | `AFTER INSERT` sur `ventes` | Consomme les lots par `date_peremption ASC`, `recu_le ASC`, avec verrou par lot |
| `trg_lots_avant_insertion`, `trg_lots_date_immuable`, `trg_lots_apres_entree` | Sur `produits_lots` | Force `owner_id` = espace, rend la date immuable, augmente le stock |

### 12.4 Migrations concernées

`0029` (module 16 C1 : colonnes, blocage, rapport), `0163` (module 36 : lots,
FEFO, RPC), `0164` (correctif `rpc_lots_ecarts`), `0157` (cohérence pharmacie),
`0072` (délai de péremption réglable), `0176` (suppression d'un collaborateur),
plus les migrations d'isolation `0165` → `0169` (`owner_id` = espace).

### 12.5 Côté application (Dart)

| Fichier | Rôle |
|---|---|
| `lib/models/lot_medicament.dart` | Modèle d'un lot + mouvements |
| `lib/models/statut_expiration.dart` | Statuts Expiré / Expire bientôt / Valide |
| `lib/services/pharmacie_lots_service.dart` | Appels `rpc_lots_*` |
| `lib/services/peremption_service.dart` | Délai d'alerte de l'entreprise |
| `lib/pages/lots_medicament_page.dart` | Écran **Lots & péremption** |
| `lib/pages/expirations_page.dart` | Écran **Expirations** |
| `lib/services/equipe_service.dart` + `lib/pages/manage_users_page.dart` | **Mon Équipe** (collaborateurs, rôles) |

### 12.6 Modules et droits

* Code du module : `lots_expiration` (`ModuleCode.lotsExpiration`).
* Profil installé par le métier `pharmacie` : voir `types_espaces_modules` en
  base (seed de la migration 0027).
* Écrans soumis aux permissions `articles` / `stock` (`PageAccess`) ×
  `ActionAccess.voir|creer|modifier`.
