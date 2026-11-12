# Module 35 — Pressing & Blanchisserie

**État :** terminé côté application, **non encore publié**.
**Migrations :** `20260916000120` → `20260916000123`, puis `20260916000136`
(l'équipe et les métiers) et `20260916000137` (caisse du jour).

---

## 1. À quoi sert ce module

Un pressing ne **vend** pas : il **garde** les vêtements de ses clients, les
traite, et doit **prouver** leur restitution. Toute la conception part de là :

- une **commande = un dossier** ;
- un **vêtement = une ligne de dossier** (jamais une ligne de produit) ;
- **« facturé » et « encaissé » sont toujours deux chiffres séparés** : déposer
  un vêtement, ce n'est pas de l'argent en caisse.

Le module ne mélange donc pas les mondes : pas de ventes, pas de produits, pas
de stock de boutique. Ce sont des vêtements **confiés**, tracés un par un.

---

## 2. Le parcours quotidien

| Étape | Écran | Ce qui se passe |
|---|---|---|
| 1. Dépôt | **Dépôts & commandes → Nouveau dépôt** | On choisit le client (ou on le crée sur place), on ajoute chaque vêtement avec sa prestation. Le numéro `PR-AAAA-NNNNNN` est attribué, le **prix est figé**, un **QR** est généré et le **reçu** est imprimable / partageable. |
| 2. Atelier | **Atelier & qualité** | La file de travail affiche des **vêtements**, pas des dossiers. On fait avancer un vêtement (ou plusieurs d'un coup), puis on passe le **contrôle qualité** : conforme ⇒ prêt, sinon ⇒ à retraiter. Quand un vêtement devient prêt, l'application **propose** aussitôt de prévenir le client (si le réglage est actif). |
| 3. Retrait | **Retraits & scan** | On scanne le QR du client (ou on cherche le numéro), on vérifie le **contrôle qualité**, on encaisse, et le vêtement est remis. |

Depuis la fiche d'une commande, deux boutons complètent le parcours :
- **Reçu** : le PDF du dépôt (impression, partage, WhatsApp) ;
- **Prévenir le client** : prépare le message WhatsApp « votre commande est
  prête » (numéro, date de retrait, solde restant). Pour une commande
  partiellement prête, le message dit « **une partie** de votre commande est
  prête » ; pour une commande en retard, il s'excuse et rappelle la date
  promise. Ce bouton n'apparaît que si le réglage **« Prévenir quand c'est
  prêt »** est actif.

Un menu **« Autres actions »** (en haut de la fiche) permet en plus :

- **Rééditer le QR code** — le reçu est perdu ou abîmé : l'ancien QR cesse de
  fonctionner, un nouveau est émis (`qr_version`), et le client doit présenter
  le nouveau reçu ;
- **Annuler la commande** — avec un **motif obligatoire**. Rien n'est supprimé :
  le dossier reste dans l'historique, marqué « Annulée ».

Et sur chaque encaissement, une flèche de retour permet d'**annuler un
paiement** saisi par erreur (motif obligatoire) — réservé à qui a le droit de
valider la finance, c'est-à-dire au patron.

Ce qui est affiché en permanence : ce qui est **en cours**, ce qui est **prêt**,
ce qui est **en retard**, et ce qui **reste à encaisser**.

---

## 3. Le catalogue et les tarifs (écran **Réglages du pressing**)

Sans catalogue, un pressing ne peut rien facturer. L'écran s'ouvre par
l'icône ⚙️ de « Dépôts & commandes » et comporte cinq onglets.

### 3.1 Réglages

| Réglage | Effet |
|---|---|
| **Devise** | Monnaie affichée (CDF, USD…). |
| **Délai standard (jours)** | Délai promis au client pour un traitement normal. |
| **Supplément d'urgence** | Montant ajouté quand le client veut plus vite. |
| **Politique de remise** | `Solde obligatoire` : aucun vêtement ne sort avec un impayé. `Remise avec dette` : le responsable autorise une sortie avec solde. |
| **Collecte à domicile** | Active le ramassage, avec ses frais. |
| **Carte de fidélité** | Seuil cumulé et pourcentage de remise. |
| **Notifications** | Dépôt, « c'est prêt », retards, paiements. |

### 3.2 Vêtements (types)

Les types reçus : chemise, costume, robe, couverture… Ils servent à appliquer
le **bon** tarif. Un bouton **« Créer le catalogue de départ »** propose une
liste de base — **sans aucun prix** : c'est au pressing de fixer les siens.

### 3.3 Prestations

Ce qui est facturé : lavage, repassage, détachage, express… Chaque prestation a
son **délai** (jours), sa **durée** (heures) et son **supplément d'urgence**.

### 3.4 Tarifs

On choisit une prestation, puis on fixe :

- le **tarif par défaut** (appliqué quand le vêtement n'a pas de tarif propre) ;
- un **tarif par type de vêtement** — le tarif du vêtement **prime** toujours
  sur le tarif par défaut.

Un prix laissé vide (ou mis à 0) retire le tarif : l'agent pourra alors saisir
le prix au dépôt.

### 3.5 Étapes

Le circuit d'un vêtement, dans l'ordre (lavage → repassage → contrôle…).
L'étape marquée **finale** est celle qui rend le vêtement **remisable** et qui
permet de prévenir le client que sa commande est prête.

---

## 4. Les garde-fous (côté serveur, jamais côté application)

| Garantie | Détail |
|---|---|
| Numérotation | `PR-AAAA-NNNNNN` attribuée de façon atomique. |
| Prix figés | Le prix est enregistré au dépôt : changer le catalogue demain ne réécrit pas l'histoire. |
| QR | Jeton aléatoire de 64 caractères — jamais un identifiant de la base. Un QR inconnu et un QR d'un autre pressing donnent **le même message**. |
| Statut | Calculé depuis les lignes : « 3 prêts / 2 en traitement » n'est jamais « terminé ». |
| Remise | Refusée si le vêtement n'est pas prêt, s'il est déjà remis, ou si le solde est dû (selon la politique). |
| Paiement | Jamais au-delà du facturé ; une annulation **trace** (motif + auteur) au lieu de supprimer. |
| Annulation de commande | Motif **obligatoire** ; le dossier reste dans l'historique. |
| Annulation d'encaissement | Réservée au patron (droit `finance/valider`) ; motif **obligatoire**. |
| Hors ligne | Le dépôt est idempotent : une demande rejouée ne crée pas deux dossiers. |

---

## 5. Qui peut faire quoi — les métiers du pressing

Un patron de pressing ne dit pas « tu es magasinier » : il dit « tu es à
l'atelier » ou « tu es à l'accueil ». Le module a donc **ses propres métiers**
(écran **Équipe du pressing**, icône 👥 du hub) :

| Métier | Ce qu'il peut faire | Ce qu'il ne peut pas |
|---|---|---|
| **Responsable** | tout, y compris les **réglages, le catalogue et les tarifs** | — |
| **Accueil & dépôt** | recevoir un vêtement, créer un client, imprimer le reçu, encaisser | modifier un tarif, faire avancer un vêtement à l'atelier |
| **Atelier** | traiter les vêtements, passer le contrôle qualité | toucher au prix, encaisser, remettre un vêtement |
| **Caisse & retrait** | encaisser, scanner le QR, remettre les vêtements | modifier un tarif, faire avancer un vêtement |

Le **patron** (propriétaire de l'entreprise) n'a pas de métier : il peut tout.

### Créer un collaborateur

**Dépôts & commandes → 👥 Équipe du pressing → Nouveau collaborateur** :

- nom, prénom, e-mail (identifiant de connexion), téléphone ;
- **métier** dans le pressing ;
- mot de passe (8 caractères minimum) — le collaborateur se connecte ensuite
  avec son propre e-mail et **son** mot de passe.

Un compte peut être **désactivé** d'un geste (il ne peut plus se connecter sans
que l'on supprime rien : l'historique reste intact), et son **métier changé** à
tout moment.

### Où la règle est réellement appliquée

Dans la **base**, pas seulement dans l'écran : des garde-fous par table
(`trg_press_metier`) refusent l'écriture hors métier avec le message
« Votre métier dans le pressing (atelier) ne permet pas les tarifs et le
catalogue ». Un collaborateur qui contournerait l'interface est donc arrêté
quand même.

> Un compte créé **avant** cette version n'a pas de métier : il conserve
exactement les droits de ses pages (aucune régression). Il suffit de lui
attribuer un métier pour qu'il entre dans le cadre.

---

## 6. La caisse du jour

**Dépôts & commandes → 💰 Caisse du jour** (`/main/pressing/caisse`).

L'argent d'un pressing entre **plusieurs fois** : acompte au dépôt, solde à la
remise. Cet écran répond à la seule question de fin de journée :

- **combien est réellement entré**, et **par quel moyen** (espèces, Mobile
  Money, carte, virement) ;
- **ce qui a été annulé** — affiché **à part**, jamais déduit en silence ;
- l'activité du jour : dossiers déposés, montant facturé, remises effectuées ;
- le **reste dû global** du pressing (toutes périodes) ;
- le **détail de chaque encaissement** : heure, dossier, client, mode, agent.

Un bouton **imprimer** produit le rapport A4 correspondant (le même document
que le comptable demande). On peut consulter n'importe quelle journée passée.

> ⚠️ Une seule source de vérité pour l'argent : `pressing_paiements`. La colonne
> `montant_encaisse` d'un retrait n'est qu'une trace : la compter aussi
doublerait la caisse.

---

## 7. Mise en route d'un nouveau pressing

1. Exécuter les migrations `0120` → `0123`, puis `0136` (équipe et métiers),
   `0137` (caisse du jour), `0140` (comptes collaborateurs créés par le
   propriétaire), `0141`/`0142` (rattachement des comptes) dans le SQL Editor.
2. Créer l'entreprise avec le type d'espace **« Pressing & Blanchisserie »**.
3. Ouvrir **Dépôts & commandes → ⚙️ Réglages** :
   - onglet **Vêtements** → « Créer le catalogue de départ » ;
   - onglet **Prestations** → ajuster les prestations et leurs délais ;
   - onglet **Tarifs** → fixer les prix (par défaut, puis par vêtement) ;
   - onglet **Étapes** → vérifier le circuit et l'étape finale ;
   - onglet **Réglages** → devise, délai, politique de remise.
4. **👥 Équipe** → créer les comptes des agents avec leur métier.
5. Prendre un premier dépôt de test, imprimer le reçu, scanner le QR au
   retrait.

> ℹ️ Deux chemins pour créer un agent : **Mon Équipe** (rôle général de
> l'entreprise, commun à tous les modules) et **Pressing → 👥 Équipe** (rôle
> **métier** : accueil, caisse, atelier, responsable). Le second est celui qui
> active les garde-fous du pressing ; un compte sans métier travaille
> normalement mais ne peut pas toucher aux prix ni aux réglages.

---

## 8. Le bordereau d'atelier (imprimable)

**Atelier & qualité → icône 🖨️** (`/main/pressing/atelier`).

L'atelier travaille debout, loin de l'écran : le bordereau est la feuille à
punaiser ou à remettre à l'agent.

- vêtements **regroupés par étape** (lavage, repassage, contrôle…), dans
  l'ordre du circuit ;
- pour chacun : n° de dossier, client, description (type · couleur · taille),
  **défauts constatés au dépôt** et date de retrait prévue (en rouge si en
  retard) ;
- une **case à cocher** par vêtement, pour le marquage au stylo ;
- un résumé en tête : vêtements, dossiers, urgents, en retard ;
- visa atelier et contrôle qualité en bas de page.

Le document suit **le filtre de l'écran** (étape sélectionnée, « mes
vêtements ») : on peut donc imprimer uniquement la file du jour. Deux actions :
**imprimer** ou **partager le PDF**.

> ⚠️ C'est un document de TRAVAIL interne : aucun montant, et il ne remplace
> pas le reçu du client.

---

## 9. Ce qui reste volontairement en attente

- **Envoi sans relecture** : le message est toujours préparé dans WhatsApp et
  envoyé par l'agent (il le relit). Rien ne part silencieusement au nom du
  pressing.

---

## 10. Le pressing est une ACTIVITÉ à part entière

Trois choses doivent être vraies **en même temps** pour qu'un compte soit
réellement un pressing :

| Ce qui doit être vrai | Où ça se règle |
| --- | --- |
| L'**espace** est de type `pressing` | `public.espaces.type` |
| L'**activité** existe dans les groupes tarifaires | `public.activites` + `public.groupes_tarifaires` |
| L'**entreprise** est typée pressing | `public.entreprises.type_activite` |

La migration `20260916000150_pressing_activite_et_groupe_tarifaire.sql` met ces
trois points en place :

- activité **« Pressing & Blanchisserie »** dans le référentiel des métiers
  (elle apparaît donc dans **Groupes tarification**) ;
- forfait **« Pressing & Blanchisserie — Standard »** : 10 000 FC/mois,
  essai 7 jours, cycle 30 jours, 2 500 FC par collaborateur, 1 entreprise
  (modifiable ensuite par la plateforme) ;
- contraintes de type élargies à tous les métiers (un pressing ne peut plus
  être forcé en « boutique » par une contrainte obsolète).

### 10.1 Corriger la catégorie d'un compte déjà créé

Deux chemins, sans intervention technique :

1. **Depuis l'application** — *Mes entreprises* → menu de l'entreprise →
   **Catégorie d'activité** → « Pressing & Blanchisserie ». L'environnement
   (modules, accueil, navigation) suit immédiatement.
2. **Depuis le SQL Editor** — rejouer la section 5 de la migration 0150 (elle
   est idempotente) en vérifiant l'e-mail du patron.

⚠️ Un pressing **ne voit ni ventes, ni produits, ni stock** : son profil de
modules ne contient que dépôts, atelier, retraits, clients, finance, équipe et
rapports. Si un compte pressing affiche encore la caisse, c'est que son espace
est resté de type `boutique`.

---

## 11. Consommer son propre stock (hors pressing)

Un patron qui prend une bouteille dans sa boutique pour la boire ne fait **pas**
une vente et ne fait **pas** une dépense :

- le **stock diminue** ;
- la **caisse ne bouge pas** (aucun encaissement, aucun chiffre d'affaires) ;
- la sortie est **justifiée** par un motif : consommation du propriétaire,
  offert, perte, casse, péremption, retour fournisseur, usage interne, autre ;
- un **rapport imprimable** récapitule toutes les sorties de la période.

Chemin : **Stock** → menu d'un article → **Sortie de stock** (ou l'icône
« sorties » de la barre du haut pour un état global). Ces sorties sont
installées par la migration `20260916000132_sorties_stock_speciales.sql` ; la
fin de la migration 0150 vérifie leur présence (`rpc_sortie_ok`,
`table_sorties_ok`, `stock_applique_ok`).
