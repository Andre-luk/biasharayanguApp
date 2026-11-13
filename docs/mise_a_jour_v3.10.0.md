# Mise à jour 3.10.0 (build 57)

**En une phrase :** le pharmacien gère enfin ses **lots et péremptions** (FEFO),
le **pressing s'affiche** dans l'application, et la **facture n'est plus
téléchargée ni ouverte toute seule** (fini le message Windows « aucune
application associée »).

---

## 1. Pharmacie — lots, péremptions et FEFO (Module 36)

Nouvel écran **Lots & péremptions**, ouvert depuis la fiche d'un article
(icône 🗃️), disponible quand le module `lots_expiration` est actif.

- **Réception d'un lot** : numéro, date de péremption, date de fabrication,
  quantité reçue, prix d'achat, fournisseur, observations.
- **Retrait d'un lot** (casse, perte, rappel, péremption) avec **motif
  obligatoire**, tracé dans les mouvements.
- **Tableau de bord** : stock de la fiche, stock *vendable* (lots non périmés),
  quantité périmée, valeur d'achat du stock, **écart** entre les deux.
- **FEFO automatique** : la vente sort d'abord le lot qui périme le plus tôt.
  Une vente de produit périmé reste **refusée** (`PRODUIT_EXPIRE`).
- Détail technique : migrations `0163` à `0169` (tables `produits_lots` et
  `produits_lots_mouvements`, triggers de contrôle à la vente, 5 RPC).

## 2. Chaque entreprise travaille chez elle (isolation multi-entreprises)

Correction de fond, côté base : l'`owner_id` des tables métier désigne
désormais **l'espace de travail** (l'entreprise active) et non plus le compte
de l'utilisateur.

- Un article saisi dans « Pharmacie HEKIMA » n'apparaît **plus** dans
  « Urembo » : il est enregistré dans le bon espace.
- Les **ventes**, la **caisse**, les **clients**, les **dettes**, les
  **dépenses**, les **inventaires** suivent la même règle.
- Un **collaborateur** ne voit plus que l'entreprise à laquelle il appartient :
  le sélecteur d'entreprises ne lui propose pas celles du patron.
- Côté application : les écrans **Articles, Stock, Clients, Caisse** se
  rechargent réellement au changement d'entreprise (ils restaient affichés avec
  les données de l'ancienne), le **cache hors ligne** est séparé par entreprise,
  et **panier + historique de scan** sont vidés à la bascule.
- Migrations `0164` à `0170`.

## 3. Pressing — le module s'affiche enfin

Les trois pages du pressing (dépôts, atelier, retraits) existaient mais
n'étaient **accordées à aucun rôle** : la carte d'accueil, les routes et les
boutons étaient donc filtrés pour tout le monde, y compris le propriétaire.

- La matrice de droits de l'application est maintenant **alignée sur celle du
  serveur** : propriétaire (tout), caissier/accueil (dépôts + retraits),
  magasinier (atelier), comptable (consultation des dépôts).
- La carte « Pressing » reste accessible à un agent d'**atelier**, qui n'a que
  la page atelier.
- **Migration `0173`** : le profil pressing perd les modules de boutique
  (`ventes`, `produits`, `stock`, `qr`). Un pressing n'a donc plus « Produits »,
  « Statut du Stock », « Mes ventes », ni les boutons « Nouvelle Vente » /
  « Scanner », ni l'onglet « Stock » — il garde dépôts, atelier, retraits,
  caisse, clients, finance, rapports, assistant IA et abonnement.

## 4. Facture — plus de téléchargement automatique

Sous Windows, chaque vente ouvrait le PDF et déclenchait :
« ce fichier ne contient pas l'application associée pour effectuer cette
action… ». C'est terminé.

- La facture s'ouvre dans une feuille d'actions : **TÉLÉCHARGER LA FACTURE
  (PDF)**, **ENVOYER SUR WHATSAPP**, **IMPRIMER**, **OUVRIR LE DOSSIER**.
- Sur ordinateur, le PDF est **enregistré** dans
  `Téléchargements/Biashara Yangu/Factures` **sans être ouvert**.
- Sur téléphone, la feuille de partage reçoit le **fichier joint** : WhatsApp
  envoie réellement le PDF.
- Les avoirs, reçus de pressing, rapports et QR suivent la même règle : plus
  aucune ouverture forcée.

## 5. Collaborateurs & entreprises (préparation Module 37)

- Nouvelle table `collaborateurs_entreprises` (utilisateur ↔ entreprise ↔ rôle)
  et rattachement des comptes existants (migration `0171`).
- Migration `0172` à exécuter : elle complète l'espace actif des collaborateurs
  qui n'en avaient pas.

---

## Ce qu'il faut faire après la mise à jour

| Qui | Action |
|---|---|
| Exploitant de la base | Exécuter dans le SQL Editor `20260916000172_fix_collaborateurs_espaces.sql` puis `20260916000173_pressing_profil_sans_boutique.sql` (les migrations `0163` à `0171` le sont déjà). |
| Pharmacien | Vérifier que le module « Lots & péremptions » est actif, puis saisir la péremption des articles existants. |
| Tout le monde | Rien : la facture et le pressing fonctionnent dès l'installation. |

> Les données de démonstration laissées lors des essais (produits et ventes de
> test) n'ont pas été supprimées par cette version.
