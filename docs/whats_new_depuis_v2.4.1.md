# Nouveautés depuis la v2.4.1 — Biashara Yangu 2.8.0

> **Pour qui :** ce document s'adresse à vous (installateur) **et** sert de
> base aux fiches des magasins d'applications.
> **Dernière version publiée avant celle-ci :** v2.4.1 (7 octobre 2026).
> **Cette version :** **2.8.0** (build 32).

---

## 🔴 À FAIRE AVANT D'INSTALLER CETTE VERSION — 14 scripts, dans cet ordre

Toutes les corrections ci-dessous **côté base de données** sont à exécuter dans
**Supabase → SQL Editor → coller → Run**. Les scripts sont **idempotents** :
les relancer ne casse rien.

```
57  pools de quotas hérités
58  attribution des quotas par le Super Admin
59  code-barres des produits          ← OBLIGATOIRE (nouvelle colonne)
60  deux prix d'abonnement (installation + mensuel)
61  renouvellement au prix mensuel
62  premier renouvellement débloqué
63  sécurité des droits d'écriture
64  l'agent corrige, mais ne suspend pas
65  fonctionnalités selon l'abonnement
66  sécurité de la table des niveaux  ← IMPORTANT (faille, voir ci-dessous)
67  factures d'abonnement
68  CRUD des quotas IA
69  code de validation des agents
70  l'agent peut vérifier un dossier
71  colonne du nom des utilisateurs  ← OBLIGATOIRE (corrige une panne de la 2.8.0)
```

⚠️ **Le 59 est obligatoire** : sans la colonne `produits.code_barre`,
l'enregistrement d'un produit avec un code-barres échouerait.

⚠️ **Le 66 est une correction de faille** et doit être exécuté avec le 65. À
 défaut, voir la section Sécurité ci-dessous.

⚠️ **Le 71 est obligatoire** si vous avez déjà installé la 2.8.0 : elle corrige
une colonne inexistante qui empêchait trois fonctions de répondre. Voir la
section « Correction 71 » ci-dessous.

**Tant qu'un script n'est pas exécuté**, l'application ne plante pas : elle
affiche « module non installé » sur les écrans concernés et continue de
fonctionner pour tout le reste.

---

## 🔒 SÉCURITÉ — deux failles fermées

### 1. La fonction qui efface toute la plateforme (script 63)

La fonction qui **supprime l'ensemble de la plateforme** (comptes +
entreprises) n'exigeait que la phrase de confirmation, **sans aucun contrôle
de rôle** — et elle était ouverte à tout compte connecté. **N'importe quel
compte** (agent, vendeur, commerçant) connaissant la phrase inscrite dans le
code pouvait déclencher l'effacement général.

Elle est désormais **réservée au Super Admin**.

### 2. Le catalogue des abonnements était modifiable par tous (script 66)

La table des niveaux d'abonnement avait été créée **sans sécurité par ligne**.
Or, sur Supabase, une table du schéma `public` sans sécurité par ligne est
accessible en **lecture ET en écriture** à tout compte connecté.

Conséquence : n'importe quel commerçant authentifié aurait pu, en une requête,
**s'octroyer le niveau « Premium »** — donc toutes les fonctionnalités — ou
modifier les prix affichés du catalogue.

La table est maintenant en **lecture seule** ; les seules écritures passent par
des fonctions qui contrôlent le rôle et journalisent l'opération.

### 3. Les droits de l'agent de terrain (scripts 63 et 64)

- ❌ il ne peut plus **suspendre ni réactiver** un compte ;
- ❌ il ne peut plus **activer ni désactiver** un compte utilisateur ;
- ❌ il ne peut plus **supprimer** une entreprise ou un compte ;
- ✅ il peut toujours **corriger** les informations d'un dossier, **vérifier**
  un dossier et **encaisser** un paiement.

La base refuse ces écritures, même si l'interface les proposait.

---

## 🧾 Vos factures d'abonnement, automatiques et traçables (script 67)

Chaque encaissement de l'abonnement produit **tout seul** une facture
numérotée (`FA-2026-000001`), au format PDF, que le client peut recevoir sur
**son WhatsApp** — télécharger, partager, imprimer.

La facture ne se contente pas de dire « payé » : elle fige, au moment de
l'émission, **le prix de l'installation**, **le prix mensuel**, **l'avance
versée**, **le versement reçu**, **ce qui a déjà été payé au total** et **ce
qu'il reste à payer** — ainsi que **qui** l'a générée (nom et rôle) et sur quel
numéro elle est partie.

C'est la réponse directe à la question « ce que le client paie » face à « ce
que l'agent demande » : une pièce unique, non modifiable après coup.

---

## 🤖 Assistant IA — le catalogue de quotas devient modifiable (script 68)

- **(Plateforme)** créer, modifier, désactiver ou supprimer un pack de quotas
  (taille, prix, nom commercial, ordre d'affichage). Le client paie
  **exactement le prix du pack affiché**, calculé côté serveur.
- **(Entreprise)** voir **où sont passés** les quotas : ce que détient chaque
  collaborateur, ce qu'il a consommé, **qui** les lui a attribués.
- **Reprendre** les quotas non utilisés d'un collaborateur qui s'en va — le
  travail déjà rendu reste dû et n'est jamais repris.
- **(Plateforme)** offrir des quotas à une boutique, avec **motif obligatoire**.

---

## 🔐 Le code de validation des agents de terrain (script 69)

Quand un agent confirme la vérification d'un compte, l'application lui demande
un **code à 6 chiffres** que la **Finance ou le Super Admin** doit lui dicter.
L'agent ne peut pas le fabriquer lui-même.

- le code **n'est jamais écrit dans le journal d'audit** — un journal se lit et
  se copie, y écrire le code supprimerait le contrôle ;
- il n'est visible que de la Finance et du Super Admin ;
- il est valable **5 minutes** ; au-delà, l'agent **peut continuer** — le
  dispositif est une **trace**, pas un blocage. Le terrain ne s'arrête pas
  parce qu'un téléphone ne répond pas ;
- mais alors la Finance **voit** ces dossiers dans sa liste « à confirmer », et
  la ligne lui dit **qui** doit agir : « aucun code demandé par l'agent » ou
  « la Finance n'a pas encore répondu ».

---

## 🏷️ Lecteur de codes-barres partout (script 59)

Chaque produit peut porter **son** code-barres fabricant (EAN-13, EAN-8,
UPC-A/E, Code 128, Code 39/93, ITF-14, Codabar, DataMatrix) — et les étiquettes
QR déjà imprimées continuent de fonctionner.

---

## 📦 L'alerte de stock ne dépend plus d'une vente (aucun script)

Avant, seule une **vente** déclenchait l'alerte « stock faible ». Un
**inventaire** qui découvre une marchandise perdue, volée ou cassée ne disait
rien — le stock ne pouvait donc passer sous son seuil que si le manquant avait
été **vendu**. Le cas le plus grave était le seul cas muet.

L'alerte se déclenche désormais aussi après un **ajustement d'inventaire**, une
**clôture d'inventaire**, un **ajustement de matière première** et une
**consommation en production**.

---

## 💵 Deux prix d'abonnement, un renouvellement juste (scripts 60 à 62)

- le **prix d'installation** (payé une fois) et le **prix mensuel** sont
  désormais **distincts** ;
- l'installation **n'est plus refacturée** au renouvellement ;
- le **premier renouvellement** est débloqué correctement ;
- les **fonctionnalités disponibles dépendent du niveau d'abonnement**
  (scripts 65 et 66).

---

## 🔧 Correction 71 — trois fonctions de la 2.8.0 ne répondaient pas

**À exécuter si vous avez déjà installé la 2.8.0.**

Les correctifs 67, 68 et 69 lisaient le nom d'un utilisateur dans une colonne
qui **n'existe pas** (`nom_complet`, au lieu de `nom`). Trois fonctions
échouaient donc à l'usage, avec le message :

> `column demandeur.nom_complet does not exist`

Ce qui ne fonctionnait pas :

- la liste des **codes de validation** et celle des **dossiers à confirmer** ;
- la liste des **attributions de quotas** (le nom du collaborateur) ;
- la génération d'une **facture d'abonnement** (le nom de celui qui l'émet).

Tout le reste de l'application est intact : la vente, le stock, les factures
déjà émises, l'activation des comptes. Le script **71** réinstalle les trois
fonctions corrigées. Aucune donnée n'est touchée et **aucune réinstallation de
l'application n'est nécessaire**.

> ⚠️ **Pourquoi le contrôle automatique ne l'avait pas vu :** PostgreSQL ne
> vérifie les noms de colonnes **qu'à la première exécution** d'une fonction,
> pas au moment où on l'installe. Le script s'était donc installé sans la
> moindre erreur — et le défaut n'apparaissait qu'à l'écran, chez l'utilisateur.
> Le script 71 ajoute désormais ce contrôle : il vérifie que les colonnes
> utilisées **existent réellement**.

---

## Version courte (pour la fiche du magasin)

> **Biashara Yangu 2.8.0** — Gérez votre commerce à Lubumbashi, même hors
> connexion.
>
> **Nouveau depuis la version précédente :** vos factures d'abonnement
> arrivent automatiquement sur votre WhatsApp (prix d'installation, abonnement
> mensuel, avance, versements et solde restant, avec le nom de celui qui les a
> générées) · le catalogue des packs de l'assistant IA est modifiable · un code
> de validation à 6 chiffres protège la vérification des comptes par les agents
> de terrain · l'alerte de stock se déclenche aussi quand la marchandise
> disparaît en inventaire, pas seulement quand elle est vendue · lecture des
> codes-barres fabricant sur tous les produits · plusieurs corrections de
> sécurité.
>
> Ventes, stock, caisse, crédits, abonnements clients, hôtel, boucherie,
> boulangerie, rapports et exports — en français, en francs congolais et en
> dollars.

---

## Mises à jour à exécuter (rappel)

| # | Script | Pourquoi c'est important |
|---|---|---|
| 57–58 | pools de quotas, attribution IA | quotas hérités et attribution |
| 59 | **code-barres des produits** | colonne obligatoire |
| 60–62 | prix d'abonnement | installation vs mensuel, renouvellement |
| 63–64 | droits d'écriture, agent | **faille** : effacement réservé au Super Admin |
| 65–66 | fonctionnalités par abonnement | **faille** : catalogue des niveaux en écriture libre |
| 67 | factures d'abonnement | nouvelles tables et fonctions |
| 68 | quotas IA | catalogue des packs |
| 69 | code de validation | nouvelles tables et fonctions |
| 70 | l'agent vérifie un dossier | garde de rôle figée explicitement |
| 71 | **colonne du nom des utilisateurs** | **obligatoire** : répare 3 fonctions de la 2.8.0 |
