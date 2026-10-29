# Module 23 — Distribution terrain, consignes, mode rapide et vérité instantanée

> **Statut** : étude + première livraison (migration `20260916000080_module23_distribution_terrain.sql`).
> **Public** : direction produit, développement, support terrain.
> **Contexte** : République démocratique du Congo — Lubumbashi et environs.

---

## 1. Étude de marché — ce que le terrain demande vraiment

### 1.1 Les trois réalités observées

| Secteur | Organisation de la vente | Problème n° 1 aujourd'hui |
|---|---|---|
| Eau minérale / boissons | Dépôt → **caisses et fardes** chargées dans un véhicule → tournée de clients (kiosques, restaurants, ménages) | Savoir **combien chaque livreur est parti avec**, combien il a vendu, combien il rend, et **combien de bouteilles consignées** (casiers, bouteilles vides) dorment encore chez les clients |
| Produits de grande consommation (PGC) / marketing | Patron → **délégués commerciaux** avec un stock attribué et une zone | Le délégué vend « à côté » : il pioche dans le stock de la boutique, sans traçabilité par agent |
| Petit commerce informel | Une personne, un téléphone, un cahier | L'application est **trop lourde** : il faut créer un article, un prix d'achat, un stock, un conditionnement… avant la première vente |

### 1.2 Ce que le marché attend (fonctionnalités concurrentes, simplifiées)

- Une **dotation** claire : « Jean est parti avec 10 casiers de 12 ».
- Un **état de tournée** : vendu / rendu / restant chez l'agent.
- Un **rapport par agent** : chiffre d'affaires, quantités, écarts, consignes, bonus accordés.
- Les **consignes** (récipients de l'entreprise restés chez le client) : combien, chez qui, dans quelle **zone**, lesquelles ont été récupérées.
- Des **bonus / remises** tracés par client : qui a donné quoi, à qui, dans quelle tournée.
- Un **mode simple** : nom + prix → on vend. Le reste (stock, unité, code-barres) devient optionnel.

### 1.3 Positionnement de Biashara Yangu

Biashara Yangu possède déjà les briques que les concurrents n'ont pas :

- un catalogue multi-formats (unité / fardes / casiers, Module 5) ;
- une validation de vente **transactionnelle** côté serveur (`rpc_vente_valider`, Module 8) ;
- un moteur de stock, de caisse, de dettes et de rapports (Modules 9, 10, 11) ;
- un cloisonnement par entreprise et par rôle (Modules 4, 15, 17).

Le module 23 **ne réinvente pas la vente** : il ajoute une **couche de distribution** au-dessus d'elle. Une vente d'agent reste une vraie vente (stock, caisse, numéro, journal), mais elle est **contrainte par la dotation** de sa tournée.

---

## 2. Personas et parcours

### 2.1 Le patron / la patronne (« Propriétaire »)

1. Il crée ses agents comme **collaborateurs** (déjà possible, Module 4).
2. Dans « **Tournées & distribution** » → *Nouvelle tournée* : il choisit l'agent, la date, la zone et les **quantités attribuées** par produit.
3. Il suit l'état : préparée → en cours → clôturée.
4. Il consulte le **rapport par agent** : attribué, vendu, rendu, restant, CA, consignes, bonus, zone des clients.

### 2.2 L'agent / livreur (« Vendeur »)

1. Il se connecte sur son téléphone (compte collaborateur).
2. L'accueil lui propose **« Ma tournée »**.
3. Il ne peut vendre **que** les produits et quantités de sa tournée — le serveur refuse le reste.
4. Il enregistre au passage les **consignes** (récipients laissés chez un client) et les **bonus**.
5. En fin de journée, il **clôture** : il déclare les retours et voit immédiatement ses écarts.

### 2.3 Le débutant (« Mode rapide »)

1. Il active le **mode rapide** dans les Paramètres.
2. Il ajoute un produit en saisissant **un nom et un prix**, c'est tout.
3. Il vend en un geste depuis l'accueil.

---

## 3. Règles métier (décisions à valider)

| # | Règle | Raison |
|---|---|---|
| R1 | Une dotation est une **réservation**, pas une sortie de stock. Le stock ne bouge qu'à la vente. | Éviter le double décrément (le trigger de `ventes` retire déjà le stock) et permettre une tournée sans casser l'inventaire |
| R2 | Une seule tournée **active** (préparée ou en cours) par agent. | Le téléphone de l'agent n'a qu'un « panier de dotation » sans ambiguïté |
| R3 | La vente d'agent passe par `rpc_tournee_vente`, qui appelle `rpc_vente_valider`. Les prix sont **relus en base**. | On garde toutes les garanties du Module 8 (prix serveur, caisse, numéro, journal) |
| R4 | Une quantité **non vendue et non rendue** à la clôture s'appelle un **écart**. Elle est visible, chiffrée, jamais effacée. | C'est la responsabilité de l'agent qui est en jeu |
| R5 | Les consignes sont des **créances physiques** : quantité laissée − quantité récupérée. | Le casier vide a une valeur ; il se remplace ou se facture |
| R6 | Le bonus est **toujours** rattaché à un client et à une tournée, avec un montant. | Le patron doit pouvoir dire « ces 3 000 FC ont été offerts et pourquoi » |
| R7 | En mode rapide, un produit peut être créé sans stock suivi (« stock illimité »). | Un vendeur de rue ne compte pas ses unités |
| R8 | Toute écriture prévient immédiatement **tous** les téléphones de l'entreprise. | Exigence explicite : « l'application doit dire la vérité instantanément » |

---

## 4. Modèle de données (migration 80)

```
tournees
├── id, owner_id, agent_id, reference (TOU-AAAA-MM-JJ-XXXX)
├── date_tournee, zone, statut (preparee | en_cours | cloturee | annulee)
└── note, cree_par, cree_le, demarree_le, cloturee_le

tournee_lignes
├── tournee_id → tournees (cascade)
├── produit_id, nom_produit, unite   (instantané : le rapport survit à une suppression)
├── quantite_attribuee, quantite_vendue, quantite_retournee, prix_vente
└── contraintes : quantités ≥ 0 ; vendu + rendu ≤ attribué

consignes
├── owner_id, agent_id, client_id, client_nom, zone, tournee_id
├── libelle_contenant, quantite, quantite_recuperee
└── statut (chez_client | partielle | recuperee | perdue)

bonus_clients
├── owner_id, agent_id, client_id, client_nom, tournee_id
├── nature (remise | cadeau | fidelite | autre), montant, description
└── date_bonus

+ ventes.tournee_id              (le rapport par agent lit le CA réel)
+ produits.stock_illimite        (mode rapide)
+ clients.zone, clients.quartier (zone du client)
+ compteurs_tournee              (numérotation journalière atomique)
```

### 4.1 RPC (toutes `security definer`, droits vérifiés à l'intérieur)

| RPC | Qui | Rôle |
|---|---|---|
| `rpc_tournee_creer(agent, date, zone, note, lignes)` | propriétaire | Prépare la dotation |
| `rpc_tournee_demarrer(tournee)` | propriétaire ou agent | Passe en « en cours » |
| `rpc_tournee_vente(lignes, mode, reçu, transaction, client)` | agent | Vente contrainte par la dotation |
| `rpc_tournee_cloturer(tournee, retours)` | propriétaire ou agent | Retours + écarts, clôture |
| `rpc_tournee_rapport(debut, fin, agent?)` | propriétaire | Rapport consolidé par agent |
| `rpc_ma_tournee()` | agent | Sa tournée active, ses lignes, consignes, bonus |
| `rpc_consigne_enregistrer(...)` | agent ou propriétaire | Récipient laissé chez un client |
| `rpc_consigne_recuperer(consigne, quantite)` | agent ou propriétaire | Retour d'un récipient |
| `rpc_bonus_enregistrer(...)` | agent ou propriétaire | Remise / cadeau tracé |
| `rpc_distribution_accueil()` | membre de l'entreprise | Compteurs de la carte d'accueil |

### 4.2 RLS

- Lecture : propriétaire, collaborateurs de la même entreprise, plateforme.
- Écritures **directes refusées** (`revoke insert/update/delete`) : tout passe par les RPC.
- Les RPC refusent un agent qui tenterait une tournée d'une autre entreprise.

---

## 5. Mode rapide (« vendre en 10 secondes »)

- Bascule **Paramètres → Mode rapide**, mémorisée sur l'appareil.
- Accueil : une action « **Vente rapide** » ouvre la liste des produits et permet d'ajouter un produit avec **nom + prix** uniquement.
- Valeurs par défaut : `prix_achat = 0`, `quantite = 0`, `unite = pièce`, `categorie = Divers`, `stock_illimite = true`.
- Le mode rapide **masque** les écrans avancés (stock, finance, rapports) sans jamais bloquer les droits : repasser en mode complet les rétablit.
- Un produit « stock illimité » est signalé par ∞ dans les écrans de stock ; il n'entre pas dans les alertes de rupture.

> **Limite assumée de la v1** : la vente d'un produit illimité laisse `produits.quantite` inchangée après compensation. Les rapports de stock excluent ces produits. Une évolution consistera à patcher `rpc_vente_valider` pour ignorer le stock des produits illimités.

---

## 6. Vérité instantanée (multi-postes)

### 6.1 Cause racine du problème constaté

| Symptôme | Cause |
|---|---|
| Le tableau de bord ne bouge pas | il lisait la base **locale** SQLite ; une vente faite sur un autre téléphone n'y arrive qu'à la synchronisation |
| Un produit ajouté « traîne » dans la caisse | la caisse lit SQLite et ne s'abonne ni au temps réel filtré ni à `DonneesService` |
| Deux téléphones se contredisent | aucune des deux lectures n'interrogeait la source de vérité (Supabase) |

### 6.2 Correctifs

1. **Statistiques d'accueil lues sur Supabase** (`TableauBordStatsService`) : produits, ventes du jour, CA, alertes de stock — avec repli local si le réseau manque.
2. **Caisse** : abonnement temps réel **filtré par `owner_id`**, plus écoute de `DonneesService`, rechargement silencieux après chaque écriture.
3. **Publication Realtime garantie** : la migration 80 ajoute les tables manquantes à `supabase_realtime` (produits, ventes, clients, tournées, consignes, bonus, caisse).
4. **Un seul canal par écran**, anti-rebond de 600 à 900 ms pour absorber les salves.

### 6.3 Règle d'architecture

> **Supabase est la vérité. SQLite n'est qu'un cache de secours.**
> Tout écran qui affiche un chiffre doit pouvoir le relire depuis Supabase, et se rafraîchir sur événement (`DonneesService` local + Realtime distant).

---

## 7. Écrans et navigation

| Route | Écran | Rôles |
|---|---|---|
| `/main/tournees` | Liste des tournées + accès rapport | propriétaire |
| `/main/tournees/new` | Préparer une dotation | propriétaire |
| `/main/tournees/:id` | Détail + clôture + rapport | propriétaire |
| `/main/ma-tournee` | Tournée de l'agent (vente, consignes, bonus) | vendeur/agent |
| `/main/distribution/rapport` | Rapport consolidé par agent | propriétaire |

Cartes d'accueil : **Tournées** (nombre actives) et **Ma tournée** (restant à vendre).

---

## 8. Indicateurs de succès (à mesurer après 30 jours)

- Taux de tournées clôturées le jour même (> 90 %).
- Écart moyen déclaré (objectif : < 2 % des quantités attribuées).
- Nombre de consignes récupérées / ouvertes.
- Temps médian entre l'ajout d'un produit et sa première vente.
- Écart entre le CA du tableau de bord et la somme des ventes serveur (objectif : 0).

---

## 9. Découpage de livraison

| Étape | Contenu | État |
|---|---|---|
| 1 | Étude + modèle de données + RPC (migration 80) | ✅ livré |
| 2 | Dart : modèles, service, tournées (patron), ma tournée (agent) | ✅ livré |
| 3 | Mode rapide (paramètre + ajout express + vente express) | ✅ livré |
| 4 | Vérité instantanée (stats Supabase + caisse temps réel) | ✅ livré |
| 5 | Tests et documentation | ✅ livré |
| 6 | Correctifs & mode simple à l'inscription (migration 81) | ✅ livré |
| 7 | Extension : consignes facturées, commissions d'agent, multi-dépôts | à planifier |

### 9.1 Correctifs de cohérence (migration 81)

| Incohérence constatée | Correction |
|---|---|
| L'agent voyait les consignes de TOUS les agents | `rpc_ma_tournee` filtre `agent_id = auth.uid()` |
| Un client d'une autre entreprise pouvait recevoir une consigne / un bonus | contrôle du propriétaire (`to_jsonb(c)->>'owner_id'`) |
| « Aujourd'hui » des bonus calculé en UTC | jour LOCAL Lubumbashi |
| Le tableau de bord mélangeait montants serveur et **nombre de ventes local** | `ventes_total` ajouté à `rpc_accueil_stats` |
| 5 sous-requêtes sur `ventes` à chaque rafraîchissement | un seul agrégat par table + index `(owner_id)` |
| Sections « 12 » dupliquées dans la migration 80 | numérotation 11 → 14 |
| Splash « v1.0.0 », À propos « 3.2.0 » | source unique `AppVersion` + test garde-fou |

### 9.2 Mode simple dès l'inscription

- L'écran d'inscription propose **Rapide** (par défaut) ou **Complet**.
- En mode rapide, `rpc_entreprise_creer_simple` crée l'entreprise **et active
  immédiatement un essai de 7 jours** (aucune double validation), avec la
  catégorie « boutique ». Le commerçant peut vendre dès la première seconde.
- L'essai ne réclame aucun montant (`montant_total_du = 0`) ; à l'échéance,
  le circuit d'abonnement habituel reprend.
- Si la migration 81 n'est pas encore exécutée, l'application retombe
  automatiquement sur `rpc_entreprise_creer` (aucune inscription bloquée).
- L'accueil affiche alors : vendre vite, mes produits, ajouter un produit,
  tournées. Les onglets Rapports et Stock sont masqués (jamais bloqués).

### 9.3 Rapidité & temps réel

- La caisse ne télécharge plus **toutes** les tables à chaque changement :
  synchronisation ciblée des produits puis relecture locale (une requête).
- Le temps réel de la caisse est **filtré par `owner_id`** et démarre une
  fois le propriétaire connu.
- Les écritures par lots (40 lignes) accélèrent la mise à jour du cache.
- Filet de sécurité : rafraîchissement silencieux des chiffres toutes les
  60 s, même si le temps réel est indisponible.
- Scanner : **plus aucun son ni vibration** au scan (flash visuel seul).

### 9.4 Scanner : encaisser directement ou continuer le panier

Après un scan, la fiche propose **deux sorties** :

| Bouton | Effet |
|---|---|
| **Encaisser maintenant** | la ligne rejoint le panier **et** l'écran de paiement s'ouvre (mode, rendu, reçu) |
| **Ajouter au panier** | on continue à scanner (comportement historique) |

Le vendeur ne ressaisit jamais ni le prix ni la quantité par défaut.

### 9.5 Pesée rapide (balance de comptoir)

Écran `/main/pesee` (droits : `caisse / créer`, module `pesee`) :

1. le produit pesé est choisi dans la liste ou **scanné** ;
2. le **prix au kilo** est celui de l'article (relu en base). S'il manque,
   un bouton ouvre la fiche article pour le définir ;
3. le vendeur saisit le **poids affiché par la balance** (champ géant,
   `−0,1` / `+0,1` / `+0,5`) ;
4. **ENCAISSER MAINTENANT** ou **Ajouter au panier**.

Le produit reste sélectionné après la vente : le client suivant est pesé et
encaissé en quelques secondes.

**Code balance optionnel** — une balance qui imprime le poids peut produire
`BAL:<produit_id>:<grammes>` (ex. `BAL:503:1250` = 1,25 kg). Le scanner
reconnaît ce format : produit ET poids arrivent ensemble, le vendeur n'a plus
qu'à encaisser.

Calculs normalisés dans `lib/models/pesee.dart` (`PeseeCalculs`) : lecture du
poids (virgule/point), arrondi au millième, total au centième, formatage
français — testés.

---

## 10. Risques et parades

| Risque | Parade |
|---|---|
| Agent sans smartphone → tournée papier | le patron peut clôturer lui-même une tournée (retours saisis au bureau) |
| Produits supprimés après une tournée | le rapport s'appuie sur `nom_produit` / `unite` figés dans la ligne |
| Réseau coupé en tournée | la vente exige le serveur (garantie anti-fraude) ; les écrans affichent un message explicite et l'agent réessaie |
| Trop de tournées ouvertes | contrainte « une tournée active par agent » |
| Confusion stock boutique / stock agent | l'agent ne voit **que** sa dotation ; la boutique garde son stock complet |

---

*Document de référence du module 23 — à maintenir à chaque évolution.*
