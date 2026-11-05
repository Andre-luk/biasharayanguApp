# Biashara Yangu — v3.6.0 (build 49)

**Type :** nouvelles fonctionnalités — flexibilité commerciale des boutiques et
abonnement au nombre de collaborateurs.

**Migrations SQL :** **deux** nouvelles, à exécuter dans le SQL Editor, dans cet
ordre :

1. `supabase/migrations/20260916000108_module25_flexibilite_commerciale.sql`
2. `supabase/migrations/20260916000109_abonnement_par_collaborateur.sql`

---

## 1. Négocier le prix, sans casser le catalogue

Un article affiché à 2 500 FC peut désormais être vendu à 2 200 FC.

- Le vendeur touche l'icône de prix sur la ligne, saisit le prix accepté :
  la facture et le panier affichent **2 200**, le catalogue reste **2 500**.
- Le propriétaire décide : négociation **activée/désactivée**, **limite en %**
  par ligne, **prix plancher**, et **quels collaborateurs** y ont droit.
- Au-delà du seuil qu'il a fixé (négociation + réduction), seul le
  propriétaire peut conclure : le collaborateur reçoit un message clair.
- Chaque opération est tracée : prix initial, prix final, montant accordé,
  vendeur, date — consultable dans **Paramètres → Ventes flexibles**.

## 2. Réduction sur l'ensemble du panier

430 FC d'achat, 30 FC de remise → 400 FC à payer. En **montant** ou en
**pourcentage**, avec un plafond configurable et une seule réduction par vente
(impossible d'en cumuler deux par accident). Une remise ne peut jamais dépasser
le panier ni rendre un montant négatif.

## 3. Cadeaux commerciaux

Le vendeur peut offrir un produit (ou plusieurs) :

- le cadeau **sort du stock** (mouvement réel), il n'est **jamais facturé** et
  n'entre **jamais** dans le chiffre d'affaires ;
- impossible d'offrir plus que le stock disponible ;
- le coût du cadeau est valorisé dans les rapports ;
- le gérant/propriétaire peut être le seul à pouvoir offrir.

**Bonus automatiques** : le propriétaire crée des règles « dès 10 000 FC
d'achat → 1 produit offert ». Chaque règle ne s'applique **qu'une fois par
vente** (pas de double attribution) et l'historique est conservé.

## 4. Cumul et facture

Négociation + réduction + cadeau peuvent se cumuler. La facture (écran et PDF
imprimé) affiche séparément : **prix catalogue**, **négociation accordée**,
**réduction**, **produits offerts**, **total à payer**. Les trois notions ne
sont jamais mélangées.

## 5. Rapports commerciaux

Nouvel écran **Paramètres → Ventes flexibles → 30 derniers jours** :

- CA brut, négociations accordées, réductions, montant réellement facturé ;
- ventes négociées / au prix normal, cadeaux distribués, valeur et coût ;
- marge commerciale — affichée seulement si les prix d'achat sont renseignés ;
- alerte sur les lignes vendues **sous le prix d'achat** ;
- ventes par collaborateur et historique des opérations.

## 6. Abonnement : 2 500 FC par collaborateur actif

Le prix de l'abonnement suit enfin l'équipe :

| Désignation | Montant |
|---|---:|
| Abonnement de base | 30 000 FC |
| Collaborateurs actifs | 3 |
| Prix par collaborateur | 2 500 FC |
| Supplément | 7 500 FC |
| **Total** | **37 500 FC** |

- le prix unitaire est réglé par la plateforme (2 500 FC par défaut) ;
- le **propriétaire n'est jamais compté** ;
- un collaborateur **désactivé** n'est plus facturé au prochain renouvellement ;
- un compte à plusieurs rôles ne compte **qu'une fois** ;
- deux entreprises comptent séparément ;
- les factures déjà émises et les périodes payées ne sont **jamais**
  recalculées ;
- l'historique du nombre de collaborateurs facturés est conservé par période ;
- le supplément est inclus dans le montant SerdiPay : aucun chemin de paiement
  parallèle.

Le propriétaire voit le détail dans **Mon dossier d'activation → Prochain
abonnement**.

## 7. Caisse : le format se choisit à l'ajout

- Un article qui existe à l'unité **et** en farde/carton l'annonce sur sa
  carte (« Aussi : Farde de 12, Carton de 24 ») et son bouton devient
  **Choisir**.
- Le sélecteur s'ouvre **immédiatement** : unité, farde, carton, chacun avec
  son prix et sa quantité.
- Les formats sont désormais recopiés dans le téléphone : le choix fonctionne
  **hors ligne**.
- Le stock est contrôlé en unités de base, tous formats confondus.
- Le panneau de caisse liste les lignes réelles (`2 × Eau — Farde de 12`) et
  permet de les retirer.

## 8. Fiche article : le code-barres écrit le nom

- Scan à la caméra du code-barres fabricant.
- Produit **déjà dans le catalogue** → nom, unité et prix se remplissent tout
  seuls (rien de déjà saisi n'est écrasé).
- Code **inconnu de la boutique** → un nom est **proposé** (base publique
  OpenFoodFacts) : un appui sur « Utiliser » et il est écrit.
- Hors ligne ou produit très local → le code reste enregistré, le nom sera
  reconnu automatiquement la prochaine fois.

## 9. Corrections

- **Hors ligne** : chaque vente rejouée porte une clé d'idempotence — une
  réponse perdue ne crée plus de doublon ni de double sortie de stock.
  La réduction globale est répartie au prorata sur les lignes enregistrées
  localement.
- Le panier et la caisse affichent le **montant réellement dû** (après
  réduction), plus le sous-total.
- Les droits de négociation/réduction/cadeau sont **réinitialisés à la
  déconnexion** (aucun risque qu'un collaborateur hérite des droits d'un
  autre).
- Le module Distribution n'est pas modifié : production, stock, tournées et
  validations gardent leurs propres règles.

---

## À faire après la publication

1. Exécuter les migrations `0108` puis `0109` dans le SQL Editor Supabase.
2. Vérifier le réglage plateforme :
   `select * from public.app_settings where key = 'abonnement_collaborateur';`
   (2 500 FC par défaut, modifiable par
   `rpc_abonnement_parametres_collaborateur_definir(prix, prorata)`).
3. Dans **Paramètres → Ventes flexibles**, activer la négociation, la réduction
   et/ou les cadeaux, puis définir les limites.
4. Ouvrir la caisse au moins une fois **avec du réseau** : les produits et leurs
   formats sont recopiés sur le téléphone (ensuite tout fonctionne hors ligne).
