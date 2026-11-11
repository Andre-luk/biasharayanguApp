# Module 35 — Pressing & Blanchisserie

**État :** terminé côté application, **non encore publié**.
**Migrations :** `20260916000120` → `20260916000123`.

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
| Hors ligne | Le dépôt est idempotent : une demande rejouée ne crée pas deux dossiers. |

---

## 5. Qui peut faire quoi

- **Responsable / propriétaire** : tout, y compris les **réglages**, le
  catalogue, les tarifs et les étapes.
- **Agent de dépôt** : prendre un dépôt, encaisser, imprimer un reçu.
- **Agent d'atelier** : faire avancer les vêtements et passer le contrôle
  qualité.
- **Caisse / retrait** : remettre un vêtement, scanner, encaisser.

Le droit requis pour les réglages est `pressing_depots/modifier` ; le serveur le
revérifie à chaque écriture.

---

## 6. Mise en route d'un nouveau pressing

1. Exécuter les migrations `0120` → `0123` dans le SQL Editor.
2. Créer l'entreprise avec le type d'espace **« Pressing & Blanchisserie »**.
3. Ouvrir **Dépôts & commandes → ⚙️ Réglages** :
   - onglet **Vêtements** → « Créer le catalogue de départ » ;
   - onglet **Prestations** → ajuster les prestations et leurs délais ;
   - onglet **Tarifs** → fixer les prix (par défaut, puis par vêtement) ;
   - onglet **Étapes** → vérifier le circuit et l'étape finale ;
   - onglet **Réglages** → devise, délai, politique de remise.
4. Prendre un premier dépôt de test, imprimer le reçu, scanner le QR au
   retrait.

---

## 7. Ce qui reste volontairement en attente

- **Publication** : le module n'est pas activé dans la version publiée ; il le
  sera quand le parcours complet aura été validé sur un vrai pressing.
- **Envoi sans relecture** : le message est toujours préparé dans WhatsApp et
  envoyé par l'agent (il le relit). Rien ne part silencieusement au nom du
  pressing.
- **Bordereau d'atelier imprimable** (liste des vêtements par étape) : non
  prévu dans cette version.
