# Module 14 — Activation à double validation (WORKFLOW)

> Migration SQL : `supabase/migrations/20260916000018_module14_activation.sql`
> (à exécuter APRÈS les migrations 13 → 17).
>
> Code application : `lib/models/activation.dart`,
> `lib/services/activation_service.dart`,
> `lib/pages/comptes_verification_page.dart` (gestionnaire),
> `lib/pages/activations_finance_page.dart` (finance),
> `lib/pages/mon_activation_page.dart` (client).

## 1. Le circuit officiel

```
CRÉATION (signup / setup)
   ↓  dossier « en_attente_verification »
GESTIONNAIRE DES COMPTES        → VÉRIFIE (ou rejette avec motif)
   ↓  dossier « verifie »
FINANCE PLATEFORME              → VALIDE LE PAIEMENT (montant, mode, référence)
   ↓
ACTIVATION AUTOMATIQUE
   • paiement TOTAL   → compte ACTIF, 30 jours immédiats
   • paiement PARTIEL → statut ESSAI_7J (duree_essai_jours de la grille,
                        7 par défaut) + solde restant
   ↓ (solde impayé à l'échéance)
RESTREINT (lecture seule — les données ne sont JAMAIS supprimées)
   ↓ (régularisation du solde)
ACTIF (nouveau cycle, 30 jours)
```

## 2. Séparation des responsabilités (appliquée 3 fois)

| Étage | Gestionnaire des comptes | Finance plateforme |
|---|---|---|
| **Rôle serveur** | `rpc_activation_verifier` n'accepte que `GESTIONNAIRE_COMPTES` / `SUPER_ADMIN` | `rpc_activation_valider_finance` n'accepte que `FINANCE_LAPERLE` / `SUPER_ADMIN` |
| **Permissions Dart** | page `verification_comptes` (+ `valider`) — **pas** `activations_finance` | page `activations_finance` (+ `valider`) — **pas** `verification_comptes` |
| **Navigation** | route `/admin/verification-comptes` | route `/admin/activations-finance` |

Le gestionnaire ne voit AUCUN champ de paiement ; la finance ne peut pas
sauter la vérification (la base refuse `etape = en_attente_verification`).

## 3. Journal d'audit (automatique)

Chaque décision est consignée dans `public.journal_audit` :

| Action | Déclencheur |
|---|---|
| `ACTIVATION_VERIFIEE` | Vérification approuvée par le gestionnaire |
| `ACTIVATION_REJETEE` | Rejet gestionnaire (motif obligatoire, ≥ 3 caractères) |
| `ACTIVATION_FINANCE` | Paiement validé par la finance (montant, mode, référence, scénario) |
| `PAIEMENT_REJETE_FINANCE` | Paiement non confirmé |
| `ACTIVATION_RESTREINTE` | Restriction automatique (solde impayé à l'échéance) |

L'historique complet est aussi dans `activations_entreprise` (table dédiée,
visible par le client dans « Mon dossier d'activation »).

## 4. RPC exposées

| Fonction | Rôles | Rôle |
|---|---|---|
| `rpc_activation_lister(p_etape)` | plateforme | Liste des dossiers (filtre par étape) |
| `rpc_activation_etat(p_entreprise_id)` | membre ou plateforme | Tableau de bord client (montants, dates, jours, historique) |
| `rpc_activation_verifier(id, approuver, note)` | gestionnaire | 1ʳᵉ validation |
| `rpc_activation_valider_finance(id, approuver, montant, mode, référence, note)` | finance | 2ᵉ validation + activation automatique |
| `rpc_activation_synchroniser()` | — (appelée au démarrage) | Restriction / réactivation automatiques |

## 5. Écrans

| Écran | Qui | Contenu |
|---|---|---|
| **Comptes à vérifier** (`/admin/verification-comptes`) | Gestionnaire des comptes | Dossiers en attente, coordonnées du responsable, boutons **Vérifier** / **Rejeter** (motif) |
| **Activations & paiements** (`/admin/activations-finance`) | Finance | Dossiers vérifiés + restreints, formulaire **montant / mode / référence / note**, bouton **Valider et activer** (aperçu total → 30 j ; partiel → essai) |
| **Mon dossier d'activation** (`/main/mon-activation`) | Boutique | Étape, montants (total / payé / solde), progression, dates, jours restants, historique complet |

## 6. Notes d'exploitation

- Les comptes EXISTANTS restent `actif` (grandfathering) : seules les
  nouvelles entreprises passent par le circuit de validation.
- `rpc_entreprise_creer` (v3) crée désormais le dossier automatiquement.
- La synchronisation (`rpc_activation_synchroniser`) est appelée au démarrage
  de l'application et après chaque connexion (best-effort, jamais bloquante).
- La migration 18 réécrit aussi `rpc_enregistrer_paiement` (Module 1) et
  `rpc_abonnement_enregistrer_paiement` (Module 3) pour ne plus écrire la
  colonne générée `solde_restant` (bug corrigé).
