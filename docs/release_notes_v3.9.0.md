## Biashara Yangu 3.9.0 — l'équipe, le multi-boutiques et le pressing complet

Cette version réunit trois chantiers longtemps attendus : **créer son équipe sans
code d'invitation**, **gérer plusieurs boutiques séparées** sur un même compte,
et **terminer le module Pressing**.

### 👥 Mon Équipe — le propriétaire crée ses comptes

- **Plus de code d'invitation.** Le patron saisit nom, prénom, e-mail,
  téléphone, mot de passe et **rôle** : le compte est créé immédiatement et
  rattaché à son entreprise. Le champ « Code Boutique » a disparu de
  l'inscription.
- **Rôles d'entreprise** : responsable (tous les droits), vendeur/caissier,
  magasinier/stock, comptable. Aucun rôle de plateforme ne peut être attribué
  depuis une boutique.
- **Modifier / désactiver / supprimer** un collaborateur, réinitialiser son mot
  de passe, et voir sa **boutique** d'affectation.
- La session du propriétaire n'est plus remplacée par celle du nouvel employé.

### 🏬 Plusieurs boutiques, données vraiment séparées

- Chaque boutique a **ses produits, son stock, ses ventes, sa caisse, ses
  clients, ses dettes, ses dépenses, ses inventaires et ses rapports** :
  basculer de boutique change réellement les données affichées.
- **Un collaborateur par boutique** : il ne voit que la sienne.
- **Route B — un propriétaire, plusieurs entreprises** : le patron peut posséder
  Urembo Market **et** Hekima Pharma avec **un seul identifiant**, chacune avec
  **son propre abonnement et sa propre échéance**, et basculer de l'une à
  l'autre depuis le sélecteur.
- Le **patron n'est plus compté** comme collaborateur dans la facture : une
  entreprise avec un collaborateur paie bien **10 000 + 2 500 = 12 500 FC**.

### 🧺 Pressing

- **Bordereau d'atelier imprimable** (icône 🖨️ dans *Atelier & qualité*) :
  vêtements regroupés par étape, défauts constatés au dépôt, retard en rouge,
  case à cocher, visa atelier et contrôle qualité. Il suit le filtre de l'écran
  et peut être imprimé ou partagé en PDF.
- Caisse du jour, rôles métier (accueil, caisse, atelier, responsable) et
  annulations tracées, comme en 3.8.0.

### 🛠️ Correctifs de base de données

- `0140` comptes collaborateurs sans code d'invitation.
- `0141` comptes sans fiche ou sans rattachement (nom, patron, rôle, entreprise).
- `0142` tout collaborateur pointe vers **l'entreprise de son patron** (+
  sécurisation d'un ancien déclencheur qui bloquait les mises à jour).
- `0143` affectation d'un collaborateur à une boutique.
- `0145`→`0147` : propriétaire explicite d'une entreprise, bascule
  entreprise + boutique, comptage des collaborateurs corrigé.

### ✅ Qualité

- `flutter analyze` : **0 erreur**.
- **1 433 tests** au vert (dont 22 nouveaux sur l'équipe et le périmètre de
  données).

### ⚠️ À faire après la mise à jour

1. Exécuter les migrations `0140` → `0147` dans le SQL Editor (toutes
   idempotentes).
2. Se **déconnecter / reconnecter** une fois : le rôle et la boutique active
   sont mémorisés localement.
3. Pour ouvrir une seconde entreprise depuis l'app, le profil tarifaire doit
   autoriser plusieurs entreprises (`groupes_tarifaires.max_espaces`).
