# Correctif 179 — Finances, rapport par collaborateur, cohérence des chiffres

**Version :** 3.10.6
**Migration :** `20260916000179_finances_uuid_text_et_rapport_vendeurs.sql`
**Date :** 21 novembre 2026

---

## 1. « operator does not exist: uuid = text » dans les Finances

### Ce qui se passait

Les écrans **Finances plateforme** et **Finances des abonnements** échouaient
avec le message PostgreSQL :

```
operator does not exist: uuid = text
```

Deux tables **historiques** du projet ont été créées avant le passage aux
identifiants `uuid` :

- `paiements_abonnements_laperle`
- `agent_ia_achats`

Leur colonne `entreprise_id` est restée en **texte**. Or tout le moteur
d'abonnement et les écrans Finance la comparent à `entreprises.id`, un `uuid` :

```sql
where p.entreprise_id = e.id     -- texte = uuid → ERREUR
```

PostgreSQL refuse la comparaison : c'est exactement le message vu à l'écran.
Le défaut avait déjà été identifié (correctif 45), mais la conversion n'avait
pas pu être menée jusqu'au bout sur toutes les colonnes.

### Ce que fait la migration

1. **Diagnostic** : liste le type réel de chaque colonne d'identifiant.
2. **Conversion sans perte** vers `uuid` :
   - une valeur **vide** devient `NULL` ;
   - une valeur **qui n'est pas un uuid** ne peut désigner aucune entreprise
     (les identifiants sont des uuid) : elle est mise à `NULL` et signalée ;
   - si la colonne est `NOT NULL`, la conversion est **annulée** (avertissement
     explicite) plutôt que de casser la base.
3. **Fonctions Finance réécrites en comparaison de texte** (`::text`), donc
   elles fonctionnent **dans tous les cas** — colonne convertie ou non. Une
   restauration de sauvegarde qui remettrait du texte ne casserait plus rien.
4. **`finance_verifier_types()`** : fonction de contrôle réutilisable.

Fonctions concernées :

| Fonction | Écran |
|---|---|
| `finance_abonnements_resume` | Synthèse facturé / encaissé / dû |
| `finance_abonnements_entreprises` | Dossier par entreprise (le bug principal) |
| `finance_serdipay_transactions` | Traçabilité Mobile Money |
| `finance_serdipay_rapprocher` | Coche de rapprochement |

---

## 2. Rapport par collaborateur, avec le stock au moment de chaque vente

### Le besoin exprimé

> « J'ai 5 beignets ; le collaborateur A en vend 1 → il reste 4 ; le
> collaborateur B vient et en vend 1. Le rapport de B doit montrer qu'il
> restait 4 beignets, et que c'est A qui avait vendu. »

### La réponse : `rpc_rapport_vendeurs(entreprise, debut, fin)`

La fonction renvoie quatre blocs :

| Bloc | Contenu |
|---|---|
| `totaux` | chiffre d'affaires, nombre de ventes, quantité, panier moyen, nombre de vendeurs et d'articles |
| `vendeurs` | **un bloc par collaborateur** : ventes, quantité, CA, panier moyen, première/dernière vente, produits vendus et **journal détaillé** |
| `produits` | par article : stock actuel, **stock au début de la période**, quantité vendue, CA |
| `journal` | la chronologie complète, vente par vente |

Chaque ligne du journal porte :

- `date`, `vendeur`, `produit`, `quantite`, `prix` ;
- **`stock_avant`** et **`stock_apres`** : le stock au moment exact de la vente ;
- **`vendu_avant_par`** : le nom de la personne qui a vendu l'unité précédente
  du même article.

### Comment le stock est reconstitué

Il n'existe pas d'historique de stock « à un instant donné » : le stock est
recalculé à partir des mouvements réels.

```text
stock_apres(vente) = stock_actuel − Σ(effets des mouvements POSTÉRIEURS)
stock_avant(vente) = stock_apres + quantité vendue
```

Mouvements pris en compte, sur tout le périmètre de l'entreprise :

| Mouvement | Effet |
|---|---|
| `ventes` | − quantité |
| `approvisionnements` | + quantité ajoutée |
| `ajustements` | + écart signé |
| `sorties_stock` | − quantité |

Vérification sur l'exemple (stock actuel = 3) :

| Vente | Mouvements postérieurs | `stock_apres` | `stock_avant` |
|---|---|---|---|
| B (1 beignet) | aucun | 3 | **4** ✅ |
| A (1 beignet) | B, −1 | 4 | **5** ✅ |

Un article supprimé donne `stock_avant = stock_apres = null` : l'application
écrit « stock inconnu » plutôt qu'un chiffre inventé.

### Dans l'application

`Mon Équipe → 📊 Stats collaborateurs` :

- chaque carte vendeur affiche désormais « *N ventes · stock restant X* » ;
- la fiche d'un vendeur affiche, pour chaque vente :
  - « **Stock : 4 avant → 3 après** » ;
  - « *Vente précédente de cet article : Aline Kabila* » ;
- le **PDF** du vendeur contient deux colonnes de plus :
  **Stock avant** et **Stock après** ;
- si le rapport serveur est indisponible, un bandeau orange l'explique et les
  totaux locaux restent affichés (jamais de chiffre inventé).

---

## 3. Cohérence des chiffres : « peu importe le téléphone »

### Les quatre causes de divergence

1. **Périmètre différent.** Le tableau de bord comptait
   `ventes.owner_id = patron` (un seul espace) ; le rapport comptait toute
   l'entreprise (espaces + utilisateurs + propriétaire). Une entreprise à
   plusieurs espaces affichait donc deux totaux.
2. **Journée décalée de 2 h.** `p_debut::timestamptz` interprète la date en
   UTC : la journée commençait à **02:00** à Lubumbashi. Une vente de 01:00
   tombait la veille dans un écran et le jour même dans l'autre.
3. **Définition de « vente » différente.** Le tableau de bord ne lisait que
   `ventes` (jamais les prestations d'un pressing) ; le rapport lisait les deux.
4. **Horloge du téléphone.** Les périodes étaient calculées avec
   `DateTime.now()` de l'appareil : un téléphone mal réglé, ou dans un autre
   fuseau, demandait une autre période — donc d'autres chiffres.

### Les correctifs

| Nouveau | Rôle |
|---|---|
| `jour_local()` | la date du jour à Lubumbashi, décidée par le **serveur** |
| `entreprise_courante()` | l'entreprise de l'utilisateur (espace actif → propriétaire → rattachement) |
| `resoudre_entreprise(id)` | accepte un identifiant d'entreprise, de propriétaire ou de collaborateur |
| `perimetre_entreprise()` | **le** périmètre unique : espaces + utilisateurs + propriétaire |
| `analyse_lignes_ventes()` | réécrite : périmètre commun + bornes en heure de Lubumbashi + ventes **et** prestations |
| `rpc_accueil_stats()` | réécrite sur cette base : ajoute le mois, les quantités et la date de référence |
| `finance_stats_periode()` | réécrite : mêmes périmètre et journée (CA, coût, dépenses, bénéfice) |
| `rpc_finance_rapport()` | réécrite : écran **Rapports** aligné (article, vendeur, mode, catégorie, jour) |

Côté application :

- `DateLocaleService` demande la date au serveur (`jour_local()`), la mémorise
  et la partage : le tableau de bord la transmet aux autres écrans ;
- `CollaborateursStatsPage` et le rapport d'entreprise
  (`AnalyseEntrepriseService.periodeSemaine/periodeMois`) utilisent cette
  référence au lieu de `DateTime.now()` ;
- l'écran **Rapports** (`rapports_finance_page`) démarre sur la date du
  serveur et recharge si elle diffère de celle du téléphone ;
- la lecture de secours de `ventes` envoie des bornes **explicites**
  (`…T00:00:00+02:00`) : ni le fuseau ni l'heure du téléphone n'entrent plus
  en jeu ;
- la déconnexion oublie la date mémorisée.

### Résultat attendu

| Écran | Ventes du jour | CA du jour |
|---|---|---|
| Tableau de bord (accueil) | X | Y |
| Rapport « aujourd'hui » du patron (PDF d'analyse) | X | Y |
| Écran « Rapports » (période du jour) | X | Y |
| Somme des rapports vendeurs | ≤ X (voir note) | ≤ Y |

> **Note pressing** : les prestations de pressing n'ont pas de vendeur
> attribué. Le rapport par collaborateur ne compte donc que les ventes
> d'articles ; les prestations apparaissent dans le rapport d'entreprise
> (`sources.pressing`). Pour une boutique, les trois chiffres sont identiques.

La migration termine par un contrôle automatique (bloc `5.f`) qui affiche un
`NOTICE` avec les deux totaux et leurs écarts — les deux écarts doivent être
à **0**.

---

## 4. Procédure de vérification

1. Exécuter la migration `0179` dans l'éditeur SQL de Supabase et lire
   l'onglet **Messages** : colonnes converties, puis `NOTICE` de cohérence.
2. Ouvrir **Finances plateforme** : la synthèse, la liste des entreprises et
   les transactions Mobile Money s'affichent sans erreur.
3. Ouvrir une fiche d'abonnement : plus de « operator does not exist ».
4. Faire une vente avec un collaborateur, puis une seconde avec un autre :
   - le tableau de bord passe de N à N+1 ventes ;
   - dans `Stats collaborateurs`, la fiche du second vendeur affiche
     « Stock : 4 avant → 3 après » et le nom du premier vendeur ;
   - le PDF du vendeur contient les deux colonnes de stock.
5. Comparer le tableau de bord et le rapport « aujourd'hui » : **mêmes
   chiffres**, sur deux téléphones différents.

---

## 5. Fichiers touchés

| Fichier | Nature |
|---|---|
| `supabase/migrations/20260916000179_…sql` | **nouvelle migration** (finance, rapport vendeur, cohérence) |
| `lib/models/rapport_vendeurs.dart` | **nouveau** modèle du rapport |
| `lib/services/rapport_vendeurs_service.dart` | **nouveau** accès à `rpc_rapport_vendeurs` |
| `lib/services/date_locale_service.dart` | **nouveau** date de référence serveur |
| `lib/services/tableau_bord_stats_service.dart` | nouvelles valeurs (mois, quantités, jour) |
| `lib/services/reinitialisation_session.dart` | oublie la date à la déconnexion |
| `lib/pages/collaborateurs_stats_page.dart` | stock avant/après, PDF enrichi, période serveur |
| `lib/pages/entreprise_detail_page.dart` | période du rapport calculée sur la date serveur |
| `lib/pages/rapports_finance_page.dart` | écran Rapports calé sur la date serveur |
| `lib/pages/home_page.dart` | transmet la date serveur aux autres écrans |
| `lib/models/vente.dart` | `VenteDetail` porte le stock |
| `test/rapport_vendeurs_test.dart` | **nouveau** — 11 tests (dont l'exemple des beignets) |
