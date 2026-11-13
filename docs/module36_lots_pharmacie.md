# Module 36 — Lots de médicaments (pharmacie)

**Migration** : `supabase/migrations/20260916000163_module36_lots_pharmacie.sql`
**Écran** : `/main/articles/:id/lots` (bouton « Lots & péremption » de la fiche article)
**Activation** : module d'activité `lots_expiration` (profil **Pharmacie**)

---

## 1. Le problème que ce module résout

Une pharmacie ne reçoit pas un médicament « une fois ». Elle le reçoit
plusieurs fois, avec **des lots, des prix d'achat et des dates de péremption
différents** :

| Lot | Quantité | Péremption |
|---|---|---|
| LOT-A | 100 boîtes | 12/2026 |
| LOT-B | 150 boîtes | 06/2027 |
| LOT-C | 80 boîtes | 09/2027 |

Jusqu'ici, une seule date était portée par la fiche de l'article. Dès la
deuxième réception, cette date devenait fausse : impossible de savoir quel
stock périme quand, ni ce qui reste réellement vendable.

## 2. Ce qui a été mis en place

### Base de données

| Objet | Rôle |
|---|---|
| `produits_lots` | un lot = **une réception** : numéro, péremption, quantité reçue, **quantité restante**, prix d'achat, fournisseur, retrait éventuel |
| `produits_lots_mouvements` | historique **append-only** : entrée, vente FEFO ligne par ligne, retrait |
| `trg_lots_apres_entree` | une réception augmente `produits.quantite` (**jamais** saisi à la main) |
| `trg_lots_date_immuable` | la péremption et la quantité reçue d'un lot ne sont **jamais** modifiées : une nouvelle réception crée un nouveau lot |
| `trg_vente_lots_controle` (BEFORE INSERT `ventes`) | refuse un article expiré (`PRODUIT_EXPIRE`) et refuse de vendre plus que le **stock valide des lots** (`STOCK_LOT_INSUFFISANT`) |
| `trg_vente_lots_fefo` (AFTER INSERT `ventes`) | consomme les lots **FEFO** (péremption la plus proche d'abord), avec verrou par lot |
| `rpc_lot_recevoir` | réception d'un lot (droits `stock/creer`, article de la boutique vérifié) |
| `rpc_lot_retirer` | retrait d'un lot avec **motif obligatoire** ; sortie par `ajustements` (tracée) |
| `rpc_lots_lister` | lots ordonnés FEFO + statut + total vendable |
| `rpc_lots_alertes` | lots périmés / proches de la péremption avec valeur d'achat perdue |
| `rpc_lots_ecarts` | diagnostic : stock de la fiche ≠ somme des lots |

### Application

- `lib/models/lot_medicament.dart` — `StatutLot`, `LotMedicament`, `DossierLots`
  (lots vendables, prochain lot FEFO, lots périmés, valeur, écart).
- `lib/services/pharmacie_lots_service.dart` — facade RPC, messages français,
  détection « migration non exécutée » (PGRST202).
- `lib/pages/lots_medicament_page.dart` — résumé (stock, vendable, périmé,
  valeur), bandeau FEFO, cartes de lots, dialogue de réception, dialogue de
  retrait.

## 3. Règles métier garanties par le serveur

1. **Un lot = une réception.** Aucune réception n'écrase la date d'un lot
   existant.
2. **Le stock affiché de l'article** = stock réel ; il augmente à la réception
   et diminue à la vente/au retrait, par les triggers.
3. **La vente applique FEFO** : le lot qui périme le plus tôt part en premier.
4. **Un lot périmé n'est jamais vendable**, même s'il reste du stock.
5. **Un retrait de lot** écrit un `ajustements` (motif « Retrait lot … —
   … ») : les rapports de pertes le retrouvent.
6. **Un article sans aucun lot** garde le comportement historique (le stock de
   la fiche fait foi) : aucune boutique non-pharmacie n'est affectée.

## 4. Procédure d'installation

1. Exécuter `20260916000163_module36_lots_pharmacie.sql` dans le SQL Editor.
   Le dernier résultat doit afficher **`Module 36 lots — OK`**.
2. Se déconnecter / reconnecter dans l'application, puis sélectionner la
   pharmacie.
3. Fiche d'un médicament → icône 🗃️ « Lots & péremption » → **Réception de
   lot**.
4. Vérifier : le stock de l'article augmente ; la vente consomme d'abord le lot
   dont la péremption est la plus proche.

### Ancien stock non suivi par lots

Les produits créés **avant** les lots ont un stock sans lot. Après la première
réception, la vente exigera que le stock valide des lots couvre la quantité
vendue. Pour régulariser sans mentir sur les dates, enregistrez un lot
« STOCK-INITIAL » avec la péremption réelle du stock en rayon
(`rpc_lots_ecarts()` indique les articles concernés).

## 5. Limites assumées

- Le module est **proposé** par l'activité `lots_expiration`, mais la règle
  FEFO s'applique dès qu'un article possède des lots — y compris dans une
  activité qui ne l'affiche pas.
- Les écrans existants (Expirations, rapport `expirations`) restent au niveau
  **article** : ils lisent le résumé (`produits.date_expiration` = péremption
  du lot valide le plus proche). Le détail par lot vit dans le nouvel écran.
- Pas encore d'alerte automatique programmée (notification à heure fixe) sur
  les lots : `rpc_lots_alertes` fournit la donnée, l'écran l'affiche.
