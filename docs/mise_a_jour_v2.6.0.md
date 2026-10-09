# Mise à jour v2.6.0 — Factures d'abonnement traçables

**Version :** 2.6.0 (build 29)
**Migration SQL :** `20260916000067_factures_abonnement.sql` *(à exécuter avant tout test)*
**Tests :** 788/788 ✅

---

## En une phrase

**Chaque encaissement de votre abonnement produit désormais tout seul une facture
qui dit ce que vous avez payé, ce qui reste, et qui vous l'a envoyée.**

---

## Ce qui change pour vous

### 🧾 Une facture automatique, à chaque paiement

Vous n'avez plus rien à réclamer. À chaque encaissement — par la finance, par
l'agent de terrain, sur le terrain — une facture est écrite et **envoyée
automatiquement sur votre WhatsApp**.

L'envoi ne dépend pas du bon vouloir de celui qui encaisse : la facture est la
contrepartie de l'argent reçu, elle part toute seule.

### 📋 Ce que la facture démontre

Elle affiche exactement ce qui compte en cas de discussion :

| Ligne | Signification |
|---|---|
| **Prix d'installation** | Le prix d'entrée — **le premier mois est inclus** |
| **Abonnement par mois** | Ce que coûteront les mois suivants |
| **Montant dû** | Installation (1er cycle) ou mensuel (renouvellements) |
| **Avance déjà versée** | Ce que vous aviez déjà payé **avant** ce versement |
| **Versement reçu** | Ce qui vient d'être encaissé |
| **Total payé à ce jour** | Le cumul |
| **Reste à payer** | Le complément — avec le délai de **7 jours** sur une avance |

C'est votre preuve : **ce que vous payez** et **ce que l'agent demande**, sur le
même document.

### 🔍 Qui a généré la facture

Chaque facture porte le **nom et le rôle** de son auteur, et mentionne si elle a
été produite automatiquement à l'encaissement ou éditée à la main. La date et le
numéro WhatsApp de l'envoi sont également conservés.

### 📱 Où la retrouver

**Paramètres → Abonnement → « Mes factures d'abonnement »**

Vous pouvez la **télécharger (PDF)**, la **partager** (elle s'ajoute au message
WhatsApp) ou l'**imprimer**.

---

## Bon à savoir

- **L'avance et le complément sont distingués.** Si vous versez une avance à
  l'installation puis complétez dans les 7 jours, les deux apparaissent sur la
  facture, avec le solde exact après chaque versement.
- **Un mois entièrement payé est annoncé clairement** : « votre abonnement est
  entièrement réglé ».
- **Aucun numéro WhatsApp enregistré ?** La facture reste marquée « à envoyer »
  et vous la retrouvez dans l'écran — rien n'est perdu. Demandez à la plateforme
  de renseigner le téléphone du responsable.
- **Une facture n'est jamais supprimée.** Si l'une d'elles est erronée, elle est
  marquée « annulée » avec son motif : la trace reste.
- **Une facture qui atteste un versement déjà encaissé ne peut pas être
  annulée** — faire disparaître la preuve d'un argent reçu serait exactement ce
  qu'elle est là pour empêcher.

---

## Notes techniques (pour la fiche store)

**Base de données — correctif 67** (`20260916000067_factures_abonnement.sql`) :
- table `factures_abonnement` : instantané figé (nom, téléphone, devise, prix,
  avance, versement, cumul, solde), traçabilité de l'émetteur et de l'envoi ;
- numérotation officielle `FA-2026-000001` par compteur atomique ;
- **déclencheur sur les DEUX chemins d'encaissement** : la facture existe quel
  que soit l'écran utilisé, et quel que soit le rôle de celui qui encaisse ;
- **le déclencheur ne bloque jamais un encaissement** : en cas d'échec, l'argent
  reçu est conservé, l'incident est journalisé, et les factures manquantes se
  réparent via « Réparer l'historique » ;
- invariant `payé = avance + versement` posé **par construction** (contrôle
  d'intégrité fourni en fin de migration, doit valoir 0) ;
- **lecture seule** : aucune écriture directe possible, même pour un Super Admin
  — une facture réécrite après coup ne prouverait plus rien.

**Application — correctif 67** : `models/facture_abonnement.dart` (règles pures :
solde, contrôle d'addition, date limite de complément, message WhatsApp),
`services/facture_abonnement_service.dart` (RPC, PDF A4, envoi WhatsApp),
`pages/factures_abonnement_page.dart` (liste, filtres, actions),
`widgets/envoi_facture_automatique.dart` (envoi après encaissement).

**Répartition des rôles :** la Finance et le Super Admin émettent et annulent ;
l'agent de terrain et le client envoient et consultent ; le serveur revérifie —
l'écran n'est jamais l'autorité.
