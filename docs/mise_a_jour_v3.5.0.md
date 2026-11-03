# Biashara Yangu — v3.5.0 (build 44)

**Type :** version de fonctionnalités (aucune fonctionnalité retirée)
**Migrations SQL :** `0100` (Module 24 — Distribution) et `0101` (compléments)
— s'ajoutent aux `0091` → `0099`.

---

## 1. Module 24 — Distribution complète

Nouveau module de **production et de distribution**, distinct des tournées du
module 23 (qui reste inchangé) : voir `docs/module24_distribution_gestion.md`.

En résumé :

- six rôles dédiés (`proprietaire`, `gerant`, `production`, `stock`,
  `commercial`, `comptable`) portés par `utilisateurs.role_distribution`, avec
  des comptes créés depuis l'écran **Collaborateurs** ;
- **stock d'intrants** séparé du **stock de produits finis**, plus un stock
  personnel par commercial ;
- réceptions d'intrants à **double confirmation** (celui qui réceptionne, puis
  le gérant qui compte à nouveau) ;
- demandes d'intrants de la production, productions déclarées avec
  **reçu / consommé / perdu** (perte motivée obligatoire) ;
- demandes de dotation des commerciaux à trois étapes (production → stock →
  commercial), clients privés par commercial, ventes et **factures PDF** ;
- retours comptés (écart déclaré / constaté), remises d'argent à **trois
  confirmations** (commercial → comptable → gérant) ;
- caisse de la distribution (apports, dépenses, validation), anomalies,
  tableau de bord par rôle.

---

## 2. Refus d'une réception d'intrants

La double confirmation n'a de sens que si le gérant peut **refuser**.

- Nouveau RPC `dist_reception_intrants_refuser(p_reception, p_motif)` :
  motif obligatoire (3 caractères minimum), réservé à `gerant` /
  `proprietaire`, possible uniquement tant que la réception est en
  `attente_gerant`.
- Écran **Stock → Réceptions** : les deux boutons **Refuser** et **Confirmer**
  apparaissent côte à côte sur une réception en attente.
- Un refus **ne touche aucun stock** (rien n'avait été validé) et laisse une
  trace au journal avec le motif.

---

## 3. Journal de traçabilité

Nouvel écran **Distribution → Traçabilité** (lecture seule), alimenté par
`dist_journal_lister(p_action, p_limite)` :

- qui (nom + rôle distribution), quoi (action traduite en français), quand,
  sur quelle entité, avec le détail des quantités / montants ;
- filtre par famille d'opération : réceptions, productions, ventes, retours,
  remises, dépenses, ajustements de stock, anomalies ;
- aucune écriture possible depuis cet écran : la traçabilité reste
  incontestable.

---

## 4. Caisse — décaissement direct (tous les modules)

La caisse (module 10) était en lecture seule : pour sortir de l'argent, il
fallait quitter l'écran. Elle dispose maintenant d'une action
**Décaissement** :

- bouton flottant « Décaissement » **et** carte « Actions rapides » en haut de
  l'écran, visibles si le rôle a le droit `depenses/creer` (comptable,
  magasinier, propriétaire…) ;
- dialogue : montant, motif obligatoire, catégorie (transport, loyer,
  carburant…), date — avec rappel du solde disponible ;
- si le montant dépasse le solde, une confirmation explicite est demandée
  (la caisse peut passer en négatif, mais jamais silencieusement) ;
- l'écriture passe par `rpc_depense_creer` : **aucun solde n'est écrit à la
  main**, le serveur recalcule (encaissements + règlements de dettes −
  dépenses) et le journal d'audit enregistre l'opération ;
- l'écran se recharge automatiquement après le décaissement.

La clôture de caisse reste disponible en second bouton flottant, pour les
rôles qui y ont droit (les deux boutons cohabitent sans se recouvrir).

---

## 5. Séparation boutique ↔ distribution (nouveauté)

Un compte de distribution ne voyait jusqu'ici que des écrans de boutique
(Stock, Ventes, Caisse, Tournées) : c'est corrigé.

- **Stock** : le stock de distribution (`dist_intrants`, `dist_produits`,
  `dist_stock_commercial`) est totalement distinct du stock des articles ; les
  cartes « Stock » et « Articles » de la boutique sont masquées pour ces
  comptes.
- **Commercial** : le commercial de distribution est identifié par
  `role_distribution = 'commercial'` (et non par son rôle global) ; il voit
  **son** portefeuille et **son** stock, et la carte « Ventes » de la boutique
  disparaît.
- **Tableau de bord** : le gérant / propriétaire de distribution voit un
  bandeau « Espace distribution » (rôle, opérations en attente, caisse de la
  distribution, anomalies) et non les statistiques de la boutique ; le geste
  principal devient « Espace distribution ».
- **Tournées** : dès que le module 24 est actif, les cartes « Tournées »,
  « Ma tournée », « Consignes clients » et « Récipients & bonus » s'effacent,
  et le bouton du mode rapide ouvre `/main/distribution`.

Détail complet : `docs/module24_distribution_gestion.md` §10.

---

## 6. Paiements : Mobile Money passe obligatoirement par SerdiPay

Anomalie corrigée : choisir **Mobile Money** créditait l'abonnement
immédiatement, comme des espèces — y compris depuis la validation finance du
Super Admin, sans aucune transaction SerdiPay.

- **Base (source de vérité, migration `0102`)** : trigger sur
  `paiements_abonnements_laperle` — toute écriture Mobile Money est refusée
  s'il n'existe pas, pour la même entreprise et le même montant, une
  transaction `paiements_serdipay` en attente **avec référence fournisseur**
  (donc réellement créée chez SerdiPay). Même garde-fou sur les achats de
  quotas IA.
- **Vue d'audit** `v_serdipay_audit` (lecture seule) pour le Super Admin :
  transactions, montants, entreprises, statuts, erreurs — sans possibilité de
  transformer une transaction non confirmée en paiement réussi.
- **Application** : `lib/services/paiement_platforme_service.dart` décide du
  chemin (espèces vs Mobile Money), et les écrans d'abonnement (commerçant +
  validation finance) délèguent à SerdiPay. La carte bancaire est refusée
  explicitement (aucun contrat d'acquisition) au lieu d'être encaissée comme
  des espèces.
- Les ventes au comptoir (module 10) ne sont pas concernées : l'argent y est
  reçu par le commerçant, pas par la plateforme.

Détail : `docs/passerelle_serdipay.md` §9.

---

## 7. Distribution : tarifs, bonus/dommages, marges (migration `0103`)

- **Grille multi-tarifs des bidons** (`dist_tarifs`) : bidon neuf, eau avec
  échange, remplissage, bidon vide, remplacement — configurable par produit
  (**Stock → Produits finis → Grille tarifaire**). Les factures passées ne sont
  jamais recalculées.
- **Bonus et produits endommagés** (`dist_bonus_dommages`) : le commercial
  déclare (bonus / endommagé / cassé / perdu) avec motif obligatoire ; le stock
  n'est retiré qu'à la **validation du gérant**. Nouvel onglet **Bonus** de
  l'espace commercial + résumé comparatif par commercial.
- **Coût de revient et marges** : `dist_cout_revient` (intrants consommés et
  perdus ÷ quantités produites) et `dist_rentabilite` (CA, coût des
  marchandises, marge, bonus/dommages, par commercial). Aucune marge n'est
  inventée : si un prix d'intrant manque, `cout_complet = false`.

Détail : `docs/module24_distribution_gestion.md` §11.

---

## 8. Distribution : travail hors ligne du commercial (migration `0105`)

- File d'attente locale persistée : les ventes et les déclarations de bonus
  peuvent être enregistrées sans réseau, puis rejouées automatiquement.
- **Idempotence** : chaque opération porte un identifiant unique
  (`reference_locale`) ; un index unique en base empêche tout doublon lors
  d'un rejeu après réponse perdue.
- Repli sur le **cache local** (produits attribués, clients, tarifs) quand le
  chargement échoue, avec un bandeau « opérations en attente » et un bouton
  **Synchroniser**.
- Une opération interrompue passe en « à vérifier » (jamais rejouée
  silencieusement) ; un refus métier passe en « conflit » avec son message.
- Les encaissements, remises et validations restent strictement en ligne.

Détail : `docs/module24_distribution_gestion.md` §12.

---

## À faire après mise à jour

1. Exécuter dans Supabase → SQL Editor :
   - `supabase/migrations/20260916000100_module24_distribution_gestion.sql`
     (si ce n'est pas déjà fait) ;
   - `supabase/migrations/20260916000101_module24_distribution_complements.sql`.
2. Aucun changement de tarif, aucun changement de permission par défaut
   hormis l'accès au module Distribution déjà décrit.
