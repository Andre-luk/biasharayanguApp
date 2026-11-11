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

1. Exécuter les migrations `0120` → `0123`, puis `0136` (équipe et métiers)
   et `0137` (caisse du jour) dans le SQL Editor.
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

---

## 8. Ce qui reste volontairement en attente

- **Publication** : le module n'est pas activé dans la version publiée ; il le
  sera quand le parcours complet aura été validé sur un vrai pressing.
- **Envoi sans relecture** : le message est toujours préparé dans WhatsApp et
  envoyé par l'agent (il le relit). Rien ne part silencieusement au nom du
  pressing.
- **Bordereau d'atelier imprimable** (liste des vêtements par étape) : non
  prévu dans cette version.
