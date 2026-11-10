# Mise à jour v3.7.1 — Paiement Mobile Money réparé, devises produit, tableau de bord

**Date :** 10 novembre 2026
**Thème :** l'argent d'abord — plus aucune vente ni aucun abonnement ne peut se
perdre ou se prolonger sans paiement.

---

## 1. Ce qui est réparé

### 1.1 Le paiement Mobile Money ne casse plus (`uuid = text`)

Deux clients ont signalé l'erreur :

> `operator does not exist: uuid = text`

Elle avait **trois** origines, toutes corrigées côté base :

| Origine | Correction |
|---|---|
| Les garde-fous Mobile Money comparaient un identifiant `uuid` à une colonne historique en `text` | comparaison en texte des deux côtés |
| `paiements_abonnements_laperle.entreprise_id` et `agent_ia_achats.entreprise_id` étaient encore en `text` | conversion en `uuid` (sans perte, uniquement si toutes les valeurs sont valides) |
| L'écran de paiement appelait `rpc_abonnement_prix_du_cycle` / `rpc_abonnement_type_cycle`, qui comparaient aussi `texte = uuid` | fonctions réécrites pour comparer en texte : **le paiement ne peut plus échouer sur un type** |

Conséquence concrète : un abonné échu peut de nouveau ouvrir son dossier et
payer par Mobile Money depuis son téléphone.

### 1.1 bis Le webhook peut enfin créditer (`ACCES_REFUSE`)

Le client saisissait son code PIN, la demande était validée sur son téléphone…
et rien ne se passait : l'abonnement n'était jamais crédité, la transaction
restait `en_attente`.

`rpc_serdipay_confirmer` (appelée par le webhook) n'a pas de session : elle
**emprunte** l'identité d'un compte pour appeler le moteur. Elle choisissait le
premier compte `new_role = 'FINANCE_LAPERLE'` **sans regarder son ancien rôle**,
alors que le moteur exige `role = 'admin'` :

```sql
if not exists (select 1 from utilisateurs u
                where u.id = auth.uid() and u.role = 'admin')
  then raise 'ACCES_REFUSE';
```

Résultat : refus, transaction annulée, ligne de nouveau `en_attente` à chaque
rejeu, **en silence**. L'acteur emprunté est désormais choisi pour satisfaire le
moteur (FINANCE puis SUPER_ADMIN, avec l'ancien rôle `admin`) ; sans compte
valide, l'erreur devient explicite.

### 1.1 ter « Vérifier maintenant » répond en quelques secondes

Sur le paiement en attente, ce bouton lançait la boucle complète (3 minutes) et
tournait sans fin. Il fait maintenant **une seule** interrogation (15 s
maximum) et rend toujours la main ; la fenêtre automatique passe à 1 minute ;
une vérification part **immédiatement au retour dans l'application** (le temps
de valider le PIN chez son opérateur) ; si rien n'est confirmé, la **référence**
du paiement est affichée pour le support.

### 1.2 Le bouton « Réactiver l'abonnement » ne donne plus de mois gratuit

Un clic sur « Réactiver l'abonnement » repoussait l'échéance de **30 jours sans
encaisser un franc**. C'était le seul endroit du produit où un abonnement se
prolongeait sans paiement.

Désormais :

* la réactivation **exige une preuve de paiement** postérieure à l'échéance :
  une transaction SerdiPay payée, ou un versement enregistré par la Finance ;
* sans preuve → refus, **zéro jour accordé** ;
* pour offrir des jours, une action délibérée et tracée existe :
  `abonnement_geste_commercial(entreprise, jours, motif)` (Super Admin,
  motif obligatoire, inscrit au journal d'audit).

### 1.3 Le +2 500 CDF par collaborateur est enfin facturé

La règle existait mais ne s'appliquait jamais : le comptage excluait tout
compte portant l'ancien rôle `admin`, or un collaborateur créé par le patron
reçoit exactement ce rôle.

* le propriétaire est maintenant écarté **par identité**, plus par son rôle ;
* le supplément entre dans le montant demandé : une boutique à 10 000 CDF avec
  une collaboratrice paie **12 500 CDF** ;
* sans cela, le client payait 10 000, le moteur attendait 12 500 et le dossier
  restait « en attente de complément » sans être activé.

### 1.4 Payer plusieurs mois sur un abonnement échu

Un client échu qui réglait 3 mois envoyait 30 000 CDF chez SerdiPay… et le
crédit était refusé (`MONTANT_SUPERIEUR`) : le moteur recalculait un seul
cycle. Le dossier est désormais figé en « attente de complément » pour
`durée × mois` jours, et le paiement multiple passe.

### 1.5 Le solde restant redevient juste

Le tableau de bord et la passerelle lisent `solde_restant`. Cette colonne
n'était plus recalculée depuis la refonte du moteur : elle restait figée, parfois
fausse (*un dossier soldé affichait encore 30 000 CDF à payer*).

Un trigger la recalcule à chaque écriture : `solde = total dû − déjà payé`
(jamais négatif). Les soldes existants ont été réparés.

---

## 2. Ce qui change dans l'application

### 2.1 Le prix d'un article s'affiche dans SA devise

Un article saisi en **dollars** était présenté en **CDF** partout (liste des
produits, fiche article, conditionnements). Il s'affiche maintenant dans sa
devise, avec l'équivalent en devise de la boutique :

> `10,00 $ ≈ 28 000 CDF`

Les totaux (panier, facture, caisse, rapports) restent dans la devise de
l'entreprise : on n'additionne jamais deux monnaies.

### 2.2 Les ventes de la caisse apparaissent au tableau de bord

Le tableau de bord lit ses chiffres **sur le serveur**. La caisse, elle, écrit
d'abord la vente **sur le téléphone**, puis l'envoie. Or l'envoi était
déclenché **après** la fermeture de la feuille de facture :

* tant que la facture restait ouverte (impression, WhatsApp), rien ne partait ;
* si l'application était fermée, la vente restait sur le téléphone pour
  toujours — facture émise, tableau de bord vide.

L'envoi démarre maintenant **immédiatement après l'enregistrement**, pendant
que la facture s'affiche. Un second appel de synchronisation attend la
synchronisation en cours au lieu de l'ignorer silencieusement, et l'écran
prévient explicitement si une vente reste en attente (et pourquoi).

### 2.3 Abonnements : bouton d'encaissement Mobile Money

Sur la fiche abonnement, « Réactiver l'abonnement » devient **« Encaisser par
Mobile Money »** : le serveur ouvre le cycle au prix négocié (supplément
collaborateurs inclus), le client valide sur son téléphone, le webhook crédite
et active.

---

## 3. Migrations SQL à exécuter (dans cet ordre)

1. `20260916000124_fix_mobile_money_uuid_text.sql`
2. `20260916000125_fix_entreprise_id_uuid.sql`
3. `20260916000126_reactivation_payante.sql`
4. `20260916000127_abonnement_multi_mois_echu.sql`
5. `20260916000128_prix_tolerant_et_supplement_collaborateur.sql`
6. `20260916000129_solde_restant_coherent.sql`
7. `20260916000130_webhook_serdipay_acteur_admin.sql`

Toutes sont **idempotentes** : elles peuvent être rejouées sans risque.
Aucune publication d'application n'est nécessaire pour que la base soit
protégée.

---

## 4. Notes techniques

* `dart analyze lib` : 0 erreur — `flutter test` : 1 370 tests verts.
* Module 35 (pressing) : présent dans le code mais **inactif** (la carte
  d'accueil n'apparaît que pour une activité dont le profil contient les
  modules pressing). Aucune boutique n'utilise encore ce profil.
