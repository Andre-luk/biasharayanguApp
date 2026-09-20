# Mise à jour v2.1.0 — Biashara Yangu

**Date :** 20 septembre 2026
**Fichiers :** `biashara-yangu.apk` (Android) • `biashara-yangu-linux.tar.gz`
(Linux) • `biashara-yangu-windows.zip` + `biashara-yangu-setup.exe` (Windows) •
`biashara-yangu-web.zip` (navigateur)
**Où télécharger :** dépôt GitHub → onglet **Releases** → *Biashara Yangu
v2.1.0*.

---

## 🆕 Les nouveautés de cette version

### 1. 💱 Votre devise de travail (CDF ou USD)
Vous choisissez désormais la devise de votre entreprise : **franc congolais
(CDF)** ou **dollar américain (USD)**.

* Tous vos montants suivent votre choix : **prix d'achat et de vente des
  articles, ventes, reçus, dépenses, caisse, dettes, hôtel, restaurant, salle
  des fêtes, boulangerie, rapports et exports**.
* Affichage adapté : `15 000 CDF` ou `12,50 $`.
* **Taux de change configurable** — « 1 USD = X CDF », réglé par la plateforme
  et modifiable par vous : **Paramètres → « Devise & conversion »** (avec un
  **simulateur** pour convertir avant d'agir).
* Chaque activité du compte peut avoir **sa propre devise** (ex. boutique en
  CDF, hôtel en USD).

> ⚠️ La devise est une unité d'affichage/saisie : changer de devise **ne
> convertit pas** les montants déjà enregistrés. Vérifiez vos prix après un
> changement (le simulateur vous aide).

### 2. 🔒 Un compte ne commerce qu'une fois validé
La procédure officielle est maintenant **appliquée partout** :

```
Création → Vérification (service comptes) → Paiement → Validation (finance)
        → Activation → compte OPÉRATIONNEL
```

* Avant l'activation : **consultation seule** et **cadenas 🔒** sur
  « Nouvelle vente », « Scanner », « Ajouter un produit », « Collaborateurs ».
* Une page **« Compte verrouillé »** explique la situation, rappelle la
  procédure et donne accès à votre dossier d'activation.
* Les cadenas **disparaissent automatiquement** dès la validation de la finance
  (sans reconnexion).
* **Abonnement échu** ou compte restreint : même verrouillage, levé
  automatiquement après régularisation du paiement.
* Le serveur refuse désormais toute opération commerciale d'un compte non
  activé — même hors de l'application.

### 3. 🏨 La catégorie d'activité est respectée
Choisissez votre métier à l'inscription (**Hôtel, Restaurant, Pharmacie,
Boutique, Salle des fêtes, Boulangerie, Boucherie, Mode, Salon de coiffure,
Dépôt…**) : l'application s'adapte (menus, tableaux de bord, fonctionnalités).

* Un **Hôtel** voit Chambres / Réservations / Réception ; un **Restaurant**
  voit Tables / Commandes / Cuisine.
* Une entreprise déjà créée peut être corrigée : **Mes entreprises → ✏️**.

### 4. 🐧 Correctif Linux (important pour l'ordinateur)
Le plantage au démarrage sur Linux est **corrigé** : la fenêtre est désormais
configurée nativement (titre et taille 1200×800, minimum 900×600).

---

## 🆕 Rappel des versions précédentes

* **v2.0.0** : variantes d'articles (taille, couleur, marque), **limitation des
  modules par pack** (groupe tarifaire), version **web** de l'application.
* **v1.6.0** : pharmacie (lots et dates de péremption, blocage des ventes
  expirées) ; hôtel, restaurant, salle des fêtes, boulangerie, boucherie
  (vente au poids).
* **v1.5.0 / v1.4.0** : activités et modules, permissions par rôle,
  collaborateurs, rapports et exports.
* **v1.3.0** : notifications (vente et rapport de fin de journée).

---

## 📲 Installation

| Appareil | Fichier | Remarque |
|---|---|---|
| Téléphone Android | `biashara-yangu.apk` | Autorisez « installer depuis cette source » |
| Ordinateur Linux | `biashara-yangu-linux.tar.gz` | Décompressez puis lancez `biashara_yangu` |
| Ordinateur Windows | `biashara-yangu-setup.exe` (recommandé) ou `biashara-yangu-windows.zip` | Le runtime Visual C++ est inclus |
| Navigateur (web) | `biashara-yangu-web.zip` | À héberger, ou version en ligne |

**Après la mise à jour, connectez-vous normalement :** vos données sont
conservées (elles restent sur le serveur).

---

## ℹ️ À savoir

* Le **service comptes** puis la **finance** doivent valider votre dossier
  (et votre paiement) pour débloquer les opérations commerciales.
* Les montants d'**abonnement** sont facturés en CDF ; leur **équivalent** dans
  votre devise s'affiche dans « Mon abonnement ».
* Vos données ne sont jamais supprimées, même en cas d'impayé : le compte est
  seulement restreint (consultation possible).

Merci d'utiliser **Biashara Yangu** 🙏

*Édité par **Biashara Tech** — Lubumbashi, RDC — avec La Perle Corp
(marketing). Support : support@biasharayangu.cd / +243 974 084 668.*
