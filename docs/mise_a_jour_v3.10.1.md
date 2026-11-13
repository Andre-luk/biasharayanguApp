# Mise à jour 3.10.1 (build 58)

> **En une phrase :** le pressing n'affiche plus les écrans d'une boutique, et son
> tableau de bord parle enfin de **dépôts** au lieu de « ventes du jour ».

---

## 1. Le pressing n'est pas une boutique

L'accueil d'un compte **pressing** affichait encore :

- les cartes **Produits**, **Statut du Stock** et **Mes ventes** ;
- les boutons **Nouvelle Vente** et **Scanner** ;
- un onglet **Stock** dans la barre du bas.

**Cause** : le profil de modules de l'activité `pressing` contenait encore
`ventes`, `produits`, `stock` et `qr` — des modules ajoutés en mode « union »
par la migration `0162`, qui n'ont aucun sens dans un pressing (il **reçoit**,
**traite** et **restitue** des vêtements confiés ; son catalogue est
« Prestations / Tarifs », pas « Produits »).

**Correction** : migration **`0173`** — ces quatre codes sont retirés du profil
`pressing`. L'accueil ne montre plus que le métier :

| Conservé | Retiré |
|---|---|
| Dépôts & retraits, Atelier, Retraits, **Caisse**, Clients, Finance, Collaborateurs, Rapports, Assistant IA, Abonnement | Produits, Statut du Stock, Mes ventes, onglet Stock, Nouvelle Vente, Scanner |

> Aucune donnée n'est supprimée : les tables `produits` / `ventes` restent
> intactes, seules les entrées de menu disparaissent. Le module **Caisse** est
> conservé : c'est lui qui encaisse les dépôts, les soldes et les retraits.

## 2. Le bandeau d'accueil suit le métier

Le bandeau affichait « **VENTES DU JOUR — 0 CDF — 0 nombre de ventes** » pour
tout le monde, y compris un pressing, un hôtel ou un restaurant.

Désormais :

| Métier | Bandeau |
|---|---|
| Boutique (module `ventes`) | « VENTES DU JOUR » + montant encaissé — inchangé |
| **Pressing** | « **FACTURÉ AUJOURD'HUI** » + montant, pastille « 3 dépôts · 5 vêtements prêts » |
| Hôtel, restaurant, autre métier sans `ventes` | bloc masqué (plus de faux « 0 vente ») |

Les chiffres du pressing viennent de `rpc_pressing_tableau_bord` (dépôts du
jour, vêtements prêts, facturé) : une seule requête, best-effort — si elle
échoue, le bandeau garde simplement les valeurs précédentes.

## 3. Rien d'autre ne change

- mêmes écrans, mêmes permissions, mêmes données ;
- aucune migration à exécuter en plus de `0173` (et `0172` si ce n'est pas déjà fait).

## Vérification après mise à jour

1. Compte pressing → accueil : **aucune** carte Produits / Stock / Mes ventes ;
2. bandeau : « FACTURÉ AUJOURD'HUI » avec le montant du jour ;
3. ouverture de **Dépôts & retraits** : la liste, les filtres et « Nouveau dépôt » fonctionnent comme avant.
