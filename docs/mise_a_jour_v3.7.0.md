# Mise à jour v3.7.0 — Abonnements intelligents, finances et factures

**Date :** 7 novembre 2026
**Thème :** personne n'oublie de payer, et personne ne paie deux fois.

---

## 1. Ce qui change pour le commerçant

### 1.1 « Je n'ai pas encore payé » — enfin détecté

Avant, l'application ne réagissait qu'au moment de la coupure. Un client en
essai de 7 jours ne voyait **aucun bouton de paiement** et devait attendre que
ses ventes se bloquent.

Désormais, l'application reconnaît **quatre situations** et propose toujours
l'action juste :

| Situation | Ce que voit le commerçant | Action proposée |
|---|---|---|
| Essai de 7 jours non payé | « Essai en cours : votre abonnement n'est pas encore payé » | **Payer mon abonnement** |
| Échéance dans 5 jours ou moins | « Votre abonnement se termine dans N jour(s) » + badge `J-N` | **Payer maintenant** |
| Abonnement échu | « Abonnement échu : accès en lecture seule » | **Renouveler** |
| Solde partiel restant | « Paiement en attente » + montant exact | **Payer le solde** |

La bannière reste visible sur tous les écrans de l'application et mène
directement au paiement.

### 1.2 Payer pendant l'essai ne fait plus perdre de jours

C'était le défaut le plus coûteux : un client qui payait au 3ᵉ jour de son
essai repartait de la date du paiement et **perdait les 4 jours restants**.

Le moteur prolonge maintenant **à partir de la date d'expiration réelle**, dès
qu'elle est future — essai, abonnement actif ou mois déjà réglé. Aucun jour
payé n'est perdu, jamais.

### 1.3 Factures professionnelles

Chaque vente, à la caisse **comme** à l'écran « Nouvelle vente », produit une
facture A4 avec :

- le **nom, l'adresse, le téléphone et l'e-mail** de l'établissement ;
- le **RCCM** et l'**identifiant national** s'ils ont été renseignés (facultatifs) ;
- le détail des lignes, les remises, les cadeaux et le récapitulatif ;
- la mention **« Solution fournie par Biashara Group »** en pied de page ;
- un **numéro unique** au format `VTE-AAAAMMJJ-NNNN`, identique en ligne et hors ligne.

La facture est **téléchargée automatiquement**, puis proposée en partage
WhatsApp ou en impression.

> **À faire une fois :** Paramètres → Boutique → **Identité de l'établissement**
> pour renseigner vos mentions légales.

---

## 2. Ce qui change pour la Finance et le Super Admin

### 2.1 Tableau de bord « Finances des abonnements »

Nouvel écran accessible depuis l'administration :

- **Facturé**, **encaissé**, **reste dû** et **taux de recouvrement** ;
- répartition par **moyen de paiement** (espèces, Mobile Money, carte, autres) ;
- **courbe des encaissements** jour par jour sur la période choisie ;
- **situation de chaque boutique** : échéance, jours restants, dû, nombre de
  collaborateurs facturés, dernier paiement ;
- **onglet Mobile Money** : chaque transaction SerdiPay avec référence,
  opérateur, numéro, nom du payeur, frais, montant net et statut.

### 2.2 Rapprochement des paiements

Chaque transaction peut être **pointée** par rapport au relevé du prestataire
(icône de vérification). Le pointage :

- enregistre **qui** a rapproché et **quand** ;
- **ne modifie aucun montant** — c'est une coche de contrôle, pas une écriture
  comptable ;
- est journalisé dans le journal d'audit.

Quand SerdiPay ne communique pas une information (frais, nom du payeur), l'écran
écrit **« non communiqué »** : aucune valeur n'est inventée.

---

## 3. Migrations à exécuter (dans cet ordre)

Dans l'éditeur SQL de Supabase :

1. `supabase/migrations/20260916000110_fix_vente_conditionnement.sql`
   → débloque la vente avec remise / négociation.
2. `supabase/migrations/20260916000111_identite_etablissement_et_finance.sql`
   → identité de l'établissement, en-tête de facture, RPC Finance.
3. `supabase/migrations/20260916000112_payer_meme_en_essai.sql`
   → paiement pendant l'essai + prolongation sans perte de jours.
4. `supabase/migrations/20260916000113_finance_rapprochement.sql`
   → dossier financier par boutique et rapprochement SerdiPay.

---

## 4. Vérifications techniques

| Contrôle | Résultat |
|---|---|
| `dart analyze lib` | 0 erreur |
| `flutter test` | **1240 tests** réussis |
| Migrations 0108 → 0113 | Analyse syntaxique PostgreSQL OK |

---

## 5. Ce qui n'est pas encore fait

- **Paiement de plusieurs mois à l'avance** : le client peut payer son prochain
  cycle par anticipation, mais pas encore 3 ou 6 mois en une seule transaction
  (le moteur de prolongation raisonne en cycles de 30 jours).
- **Avoir / note de crédit** sur une facture déjà émise.
- **Changement de forfait** à la hausse ou à la baisse en cours de cycle.
