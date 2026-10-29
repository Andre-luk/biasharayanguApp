# Mise à jour v3.3.0 — distribution terrain, pesée et mode simple

**Version** : 3.3.0 (build 37) — voir `lib/config/app_version.dart`.
**Migrations à exécuter** (SQL Editor, dans cet ordre) :

1. `20260916000079_passerelle_serdipay.sql` (paiement en ligne)
2. `20260916000080_module23_distribution_terrain.sql`
3. `20260916000081_module23b_mode_simple.sql`

> Sans la 0079, l'application fonctionne : seul l'écran de paiement SerdiPay
> affiche « module non installé ».

---

## 1. Distribution terrain (Module 23)

- **Tournées de livraison** : le patron prépare une dotation par agent
  (produits + quantités), la démarre, la clôture avec les retours.
- **L'agent ne vend que sa dotation** : `rpc_tournee_vente` est plafonné par
  les quantités reçues, puis appelle la vente officielle (prix relus en base,
  caisse, numéro, journal).
- **Rapport par agent** : attribué, vendu, rendu, **écart**, chiffre
  d'affaires, consignes ouvertes, bonus accordés, zone.
- **Consignes** : récipients de l'entreprise restés chez un client
  (casiers, bouteilles), avec récupération partielle.
- **Bonus** : remise, cadeau ou fidélité, toujours rattaché à un client et à
  une tournée.
- **Une seule tournée active par agent** ; écritures directes refusées.

## 2. Pesée rapide (balance)

- Nouvel écran **Pesée rapide** : produit pesé → prix au kilo (relu en base)
  → **poids affiché par la balance** → encaissement immédiat.
- Boutons `−0,1` / `+0,1` / `+0,5`, total en direct, produit conservé pour le
  client suivant.
- Prix manquant : bouton **Définir le prix au kilo** (fiche article).
- **Code balance** accepté par le scanner : `BAL:<produit_id>:<grammes>`
  (ex. `BAL:503:1250` = 1,25 kg). Le produit et le poids arrivent ensemble.
- Calculs centralisés et testés dans `lib/models/pesee.dart`.

## 3. Scanner

- Après un scan : **Encaisser maintenant** (paiement direct) ou **Ajouter au
  panier**.
- **Aucun son ni vibration** au scan (flash visuel uniquement).

## 4. Mode simple & inscription

- Inscription : choix **Rapide** (défaut) / **Complet**.
- Mode rapide : l'entreprise est créée **et l'essai de 7 jours activé
  immédiatement** (`rpc_entreprise_creer_simple`), sans double validation.
- Accueil simple : vendre, mes produits, ajouter, pesée, tournées.
  Onglets Rapports et Stock masqués (jamais bloqués).

## 5. Rapidité et vérité instantanée

- Caisse : synchronisation **ciblée des produits** (plus de téléchargement
  global), écriture par lots, cache du propriétaire.
- Temps réel **filtré par boutique** (produits, ventes, tournées, consignes).
- Tableau de bord : chiffres calculés par le serveur (`rpc_accueil_stats`),
  une seule lecture par table, nombre total de ventes inclus.
- Rafraîchissement de secours toutes les 60 s.

## 6. Corrections de cohérence

- L'agent ne voit plus les consignes des autres agents.
- Un client d'une autre entreprise est refusé pour une consigne ou un bonus.
- Journée comptée à l'heure de **Lubumbashi** (plus UTC).
- Version affichée identique partout (splash, connexion, accueil, À propos)
  et testée contre `pubspec.yaml`.
- Numérotation des sections SQL corrigée.
- Garde anti-écran noir lors du passage au mode rapide sur un onglet masqué.

## 7. Comptes plateforme

Deux comptes **Super Administrateur** ont été créés et vérifiés
(`mon_role()` = `SUPER_ADMIN`) :

- `andrelukengu67@gmail.com`
- `jeanluc@gmail.com`

> Les mots de passe ont été communiqués par le demandeur ; ils ne figurent
> pas dans ce document.

---

**Validation avant publication** : `flutter analyze` 0 erreur ;
`flutter test` 977/977 ; migrations 80 et 81 validées par le parseur SQL.
