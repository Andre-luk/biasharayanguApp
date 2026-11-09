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

### 1.4 Vos fardes et vos sachets se vendent enfin correctement

Un article vendu en **conditionnement** (farde de 12, sachet de 500 g, carton
de 24) apparaissait comme invisible : on l'ajoutait au panier, rien ne
s'affichait dans le tableau de bord, et rien n'était enregistré avant le clic
sur « Valider la vente ».

Désormais :

- chaque **format** a sa propre ligne dans le panier, avec son nom, son prix et
  un compteur `+` / `−` ;
- le compteur de la fiche article compte les **unités de base** réellement
  disponibles (« 3 fardes = 36 unités ») ;
- la quantité en farde est enregistrée **avec son conditionnement** : la vente
  est relue correctement sur le serveur, le soir comme le lendemain.

### 1.5 💵 Le prix d'un article peut être en dollars

À la création ou à la modification d'un article, un champ **« Devise du prix »**
permet de choisir la devise de la boutique (franc congolais) ou le **dollar**.
L'écran affiche en dessous le **taux du jour** et l'équivalent, pour éviter les
surprises. Le prix est conservé tel que saisi ; la conversion se fait au moment
de la vente, et la facture indique les deux montants.

### 1.6 ♾️ Vendre un article sans suivre son stock

Certains articles ne se comptent pas (eau au robinet, service, article fabriqué
à la demande, produit vendu au poids approximatif). Un interrupteur
**« Vendre sans suivre le stock »** dans la fiche article suffit : le stock
n'est alors ni contrôlé ni décroché, la fiche affiche **∞** et l'article ne
bloque plus jamais une vente.

### 1.7 Payer plusieurs mois d'avance

« Payer mon abonnement » propose maintenant la durée : **1, 3, 6 ou 12 mois**.
L'écran annonce le montant exact et la nouvelle échéance estimée avant le
paiement. Les mois achetés s'ajoutent aux jours restants — aucun jour payé
n'est perdu.

### 1.8 🔌 Un vrai lecteur de codes-barres USB

Le lecteur laser (type *Moss 650 nm*, prise USB) fonctionne maintenant comme
un clavier : on scanne, l'article est ajouté au panier, sans toucher l'écran.

- le code-barres **fabricant** (EAN/UPC), le **QR de la boutique** et le code
  de chaque **conditionnement** sont reconnus ;
- la saisie normale au clavier n'est **jamais** interceptée ;
- un lecteur réglé en **QWERTY** sur un clavier **AZERTY** est corrigé
  automatiquement ;
- sans réseau, les articles déjà connus de l'appareil sont reconnus quand
  même.

### 1.9 🧾 Avoirs et notes de crédit

Rendre de l'argent à un client ne doit **jamais** annuler la vente d'origine.
L'écran **« Avoirs & notes de crédit »** émet un document séparé, numéroté
`AV-AAAAMMJJ-NNNN` :

- type **Avoir** (somme à valoir) ou **Remboursement** (argent rendu) ;
- montant, motif, client, facture d'origine ;
- **plafond vérifié par le serveur** : impossible de rendre plus que ce qui a
  été encaissé ;
- **jamais de suppression** : un avoir se marque « ANNULÉ » avec son motif.

Chaque avoir produit un **PDF A4 imprimable** (impression, téléchargement,
partage, WhatsApp) portant le nom, l'adresse et les mentions légales de
l'établissement, la référence de la facture d'origine et la mention
« Solution fournie par Biashara Group ».

### 1.10 📦 Le retour de marchandise revient en stock

Quand le client rapporte la marchandise, l'avoir propose
**« Remettre la marchandise en stock »** : on choisit l'article et la quantité,
et le stock remonte immédiatement, avec un mouvement d'approvisionnement au nom
de l'avoir.

Le **prix d'achat est facultatif** — on ne le connaît pas toujours. Laissez le
champ vide : le mouvement est enregistré sans prix, aucun montant n'est
inventé. Un même avoir ne peut pas servir deux fois : le serveur refuse le
deuxième retour.

### 1.11 Changer de forfait sans perdre d'argent

Depuis « Mon abonnement », le propriétaire peut passer à un autre forfait. Le
prix est calculé **au prorata des jours restants** :

- **hausse** : l'écran indique le **complément à payer** ;
- **baisse** : rien à payer, le **crédit** des jours restants est noté ;
- les dates d'échéance ne bougent pas et l'opération est journalisée.

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

1. `20260916000110_fix_vente_conditionnement.sql`
   → débloque la vente avec remise / négociation.
2. `20260916000111_identite_etablissement_et_finance.sql`
   → identité de l'établissement, en-tête de facture, RPC Finance.
3. `20260916000112_payer_meme_en_essai.sql`
   → paiement pendant l'essai + prolongation sans perte de jours.
4. `20260916000113_finance_rapprochement.sql`
   → dossier financier par boutique et rapprochement SerdiPay.
5. `20260916000114_devise_par_produit.sql`
   → prix d'un article en dollars ou en francs.
6. `20260916000115_paiement_plusieurs_mois.sql`
   → paiement de 1, 3, 6 ou 12 mois en une fois.
7. `20260916000116_vente_sans_stock.sql`
   → article vendu sans suivi de stock.
8. `20260916000117_avoirs_notes_credit.sql`
   → avoirs et notes de crédit. **À rejouer** si la première tentative s'est
   arrêtée sur `42883 : function note_credit_creer(...) does not exist`.
9. `20260916000118_changement_forfait.sql`
   → changement de forfait au prorata.
10. `20260916000119_avoir_retour_stock.sql`
    → remise en stock de la marchandise rendue (prix d'achat facultatif) et
    liste des avoirs enrichie.

Chaque script est **idempotent** : on peut le rejouer sans risque.

---

## 4. Vérifications techniques

| Contrôle | Résultat |
|---|---|
| `dart analyze lib` | 0 erreur |
| `flutter test` | **1324 tests** réussis |
| Migrations 0108 → 0119 | Analyse syntaxique PostgreSQL OK (60 fonctions) |
| Document d'avoir | 19 tests dédiés (nom de fichier, WhatsApp, PDF, retour) |

---

## 5. Ce qui n'est pas encore fait

- **Impression d'un avoir depuis l'écran de vente** : l'avoir s'émet depuis
  l'écran « Avoirs & notes de crédit », pas encore d'un simple appui sur une
  ligne de l'historique des ventes.
- **Devises dans les rapports** : une vente payée en dollars est convertie
  pour les totaux, mais les rapports n'affichent pas encore le détail par
  devise d'origine.
- **Paiement par carte** : le moteur et l'écran sont prêts, l'ouverture du
  canal auprès du prestataire reste à faire.
- **Publication sur les stores** (Play Store / App Store) : les paquets sont
  signés en debug ; voir `docs/publication_app.md` (§ keystore) avant toute
  mise en ligne publique.
