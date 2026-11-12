# Mise à jour v3.9.2 — types d'activité, pressing complet, pharmacie

**Version** : 3.9.2 (56)
**Date** : 12 novembre 2026

---

## 1. Le pressing retrouve tous ses écrans

### Ce qui se passait

Un compte pressing n'affichait que quelques compteurs sur l'accueil : ni
Catalogue, ni Stock, ni Ventes.

### Cause

Le profil de modules du pressing (`types_espaces_modules`) avait été écrit avec
une liste réduite :

```
clients, caisse, finance, employes, rapports, assistant_ia,
press_depots, press_atelier, press_retraits
```

Il manquait `ventes`, `produits`, `stock` et `qr` — donc les cartes
correspondantes n'existaient pas.

### Correctif (migration 0162)

Les quatre modules manquants sont **ajoutés** au profil, par union : aucun
module existant n'est retiré, un ajout de l'Expert est conservé.

---

## 2. Le métier pilote les modules, l'axe commercial reste distinct

Deux réglages différents, désormais cohérents partout :

| Réglage | Colonne | Valeurs | Effet |
|---|---|---|---|
| **Métier** | `espaces.type` | boutique, pharmacie, pressing, hôtel, restaurant, dépôt, boulangerie… | Profil de modules (lots/péremption, chambres, press_*) |
| **Axe commercial** | `entreprises.type_activite` | boutique, distribution | Tournées, agents, récipients |

- **0160** : un trigger recalcule l'axe commercial à chaque création ou
  modification d'espace → **plus jamais « non renseigné »**, quel que soit le
  chemin de création (inscription, Super Admin, RPC).
- **0161** : les profils manquants sont créés (pressing, distribution,
  boucherie, mode, salon, salle des fêtes, boulangerie).
- **0159** : `rpc_mes_modules()` lit le métier de l'**espace** d'abord.

---

## 3. Super Admin : changer le type d'une entreprise

« Changer le type » liste désormais **toutes** les activités du référentiel
(pharmacie, pressing, hôtel, restaurant…) au lieu des deux valeurs codées en
dur. Le choix s'applique à **tous les espaces** de l'entreprise et recharge
immédiatement son profil de modules (`rpc_entreprise_metier_definir`).

---

## 4. Pharmacie : date de péremption

« HEKIMA PHARMA » portait `type_activite = 'boutique'` : l'entreprise recevait
le profil boutique, sans `lots_expiration`, donc le formulaire d'article
masquait la section **Lot + date de péremption**. Corrigé par 0158/0159 : le
métier vient de l'espace (`pharmacie`), le profil contient `lots_expiration`.

---

## 5. Équipe : création de collaborateur

`rpc_collaborateur_creer` comparait `auth.uid()` à `mon_proprietaire()` — qui
renvoie l'**espace**, pas l'utilisateur. Dans une deuxième entreprise la
comparaison était donc toujours fausse → « seul le propriétaire peut créer un
collaborateur ». L'identité passe maintenant par `mon_patron()` (0157).

---

## 6. Portée des données (articles invisibles)

Un article encodé dans la pharmacie « s'enregistrait » puis restait invisible
(liste vide, tableau de bord à 0). L'application calcule désormais
`owner_id` à partir de la **valeur vérifiée par le serveur**
(`mon_proprietaire()`), exactement celle que la RLS compare. Si les deux
divergent, un message le signale dans les journaux.

---

## Migrations à exécuter (dans cet ordre)

```
20260916000157_pharmacie_coherence.sql
20260916000158_metier_espace_specialise.sql
20260916000159_metier_vient_de_espace.sql
20260916000160_type_toujours_renseigne.sql
20260916000161_profils_metiers_manquants.sql
20260916000162_profil_pressing_complet.sql
```

Après exécution : **déconnexion / reconnexion** dans l'application, puis
sélectionner l'entreprise concernée.

---

## Rappel : ce qui relève du code, pas de la base

Installer cette version (APK / Linux / Web) est nécessaire pour :

- le partage du PDF comme **fichier** sur WhatsApp (et non un texte) ;
- l'ouverture des factures sur ordinateur (plus de message « ce fichier ne
  contient pas d'application associée ») ;
- les cartes métier en **mode rapide** (pressing, hôtel, restaurant) ;
- le sélecteur de type d'activité complet dans le Super Admin.
