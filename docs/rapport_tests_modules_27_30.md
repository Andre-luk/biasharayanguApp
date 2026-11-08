# Rapport de tests — Modules 27, 28, 29, 30

**Date :** 8 novembre 2026
**Périmètre :** abonnements, paiements, caisse, factures, identités, finance,
lecteur de codes-barres USB, devise par article, paiement multi-mois.
**Exécution :** `flutter test` — **1286 tests, 0 échec** · `dart analyze lib` —
**0 erreur**.

---

## 1. Les 19 points obligatoires du Module 27

| # | Exigence | Où c'est vérifié | Résultat |
|---|---|---|---|
| 1 | Détecter un compte **jamais payé** | `abonnement_a_payer_test.dart` — « Compte jamais payé » | ✅ |
| 2 | Détecter un compte **en essai de 7 jours non payé** | même fichier — « Essai en cours » | ✅ |
| 3 | Bouton **PAYER** visible dans les deux cas | `abonnement_a_payer_test.dart` (`aPayer`, `libellePaiement`) | ✅ |
| 4 | **Alerte avant l'échéance** (J‑5) | `abonnement_test.dart` — bornes J‑0/J‑5 oui, J‑6 non | ✅ |
| 5 | Un accès valide **protège** même si une autre entreprise est échue | `abonnement_test.dart` — « une entreprise active protège » | ✅ |
| 6 | **Aucun jour payé perdu** (paiement pendant l'essai) | `abonnement_test.dart` + `abonnement_a_payer_test.dart` | ✅ |
| 7 | Payer **par anticipation** (essai ou cycle en cours) | `abonnement_a_payer_test.dart` — `AvanceCycle` (3 cas) | ✅ |
| 8 | Un **solde déjà dû** ne rouvre pas un cycle | `abonnement_a_payer_test.dart` — « un solde déjà dû ne rouvre rien » | ✅ |
| 9 | **Supplément collaborateurs** (2 500 FC) facturé | `abonnement_collaborateurs_test.dart` (9 tests) | ✅ |
| 10 | **Facture A4** avec identité de l'établissement | `facture_vente_test.dart` (19 tests) | ✅ |
| 11 | **RCCM / ID national** facultatifs (masqués si absents) | `facture_vente_test.dart` + `etablissement` | ✅ |
| 12 | Mention **« Solution fournie par Biashara Group »** | `facture_vente_test.dart` | ✅ |
| 13 | **Une seule numérotation** caisse / nouvelle vente | `facture_vente_test.dart` — `numeroVente` (4 tests) | ✅ |
| 14 | **Une seule logique de facturation** (même service) | `FactureVenteService` utilisé par les deux écrans | ✅ |
| 15 | Partager la facture sur **WhatsApp** (numéro normalisé) | `facture_vente_test.dart` — `normaliserTelephone` | ✅ |
| 16 | **Facturé / encaissé / dû** côté Finance | `finance_abonnements_test.dart` (13 tests) | ✅ |
| 17 | **Traçabilité** Mobile Money sans valeur inventée | `finance_abonnements_test.dart` — champs `null` tolérés | ✅ |
| 18 | **Rapprochement** du relevé prestataire | `finance_abonnements_test.dart` + migration 0113 | ✅ |
| 19 | **Historique complet par entreprise** | `finance_abonnements_test.dart` — `LigneFinanceEntreprise` | ✅ |

---

## 2. Caisse, formats et lecteur de codes-barres (Modules 27‑28)

| Point | Fichier de test | Tests |
|---|---|---|
| Farde / carton visibles et quantifiables | `panier_vente_test.dart` | 18 |
| Le format vendu part jusqu'au serveur | `vente_format_sync_test.dart` | 5 |
| Scanner USB : reconnaissance d'une rafale | `lecteur_code_barre_usb_test.dart` | 16 |
| Correction AZERTY / QWERTY | `lecteur_code_barre_usb_test.dart` | inclus |
| Résolution `PROD:` / `COND:` / balance / code-barres | `scanner_test.dart` | 15 |
| Négociation, réduction, cadeaux | `ventes_flexibles_test.dart` | 22 |

---

## 3. Devise par article (Module 29)

`devise_produit_test.dart` — **15 tests** :

- un article sans devise **suit** la devise de l'entreprise ;
- la devise d'un article est **respectée** (casse ignorée) ;
- une devise inconnue retombe sur le CDF ;
- conversion USD → CDF au **taux du jour** ;
- les francs sont **arrondis à l'unité** (jamais « 4 249,5 CDF ») ;
- entreprise en USD : un prix en francs est divisé par le taux ;
- affichage `10,00 $ ≈ 28 000 CDF`, sans doublon pour un prix en francs.

---

## 4. Paiement de plusieurs mois (Module 30)

`abonnement_a_payer_test.dart` — **5 tests dédiés** :

- 1 mois = comportement d'avant (30 jours) ;
- 6 mois = 180 jours, montant = prix du cycle × 6 ;
- l'échéance estimée part de la **date future** (aucun jour perdu) ;
- une échéance dépassée repart de maintenant ;
- un solde déjà dû ne rouvre rien.

---

## 5. Migrations SQL validées

Analyse syntaxique PostgreSQL (`pgsql-parser` + `plpgsql-parser`) :

| Script | Fonctions contrôlées |
|---|---|
| 0108 — flexibilité commerciale | 5 |
| 0109 — abonnement par collaborateur | 12 |
| 0110 — fix vente conditionnement | 1 |
| 0111 — identité & finance | 4 |
| 0112 — payer même en essai | 2 |
| 0113 — finance & rapprochement | 2 |
| 0114 — devise par produit | (DDL seule) |
| 0115 — paiement plusieurs mois | 3 |

---

## 6. Ce qui reste à faire

| # | Sujet | État |
|---|---|---|
| 1 | **Avoir / note de crédit** sur une facture déjà émise | à faire |
| 2 | **Changement de forfait** (hausse/baisse) en cours de cycle | à faire |

Ces deux points touchent l'argent réel et demandent chacun un script SQL
dédié (table + transaction + journal d'audit) : ils seront traités au tour
suivant, dans cet ordre.
