# Mise à jour v3.9.0 (build 54)

**Date** : 11 novembre 2026

Cette version ouvre trois chantiers attendus : une **équipe gérée par le
propriétaire** (sans code d'invitation), le **module Pressing** complété, et le
vrai **multi-boutiques facturé** — un seul propriétaire, plusieurs entreprises,
chacune avec son abonnement.

---

## 1. Équipe : le propriétaire crée les comptes lui-même

**Fini le « code boutique ».** Le propriétaire saisit nom, prénom, e-mail,
téléphone, mot de passe et **rôle** ; le compte est créé immédiatement dans son
entreprise.

- écran **Mon Équipe** refondu : recherche, rôle, état, **suppression**,
  **désactivation**, **réinitialisation du mot de passe** ;
- le champ « Code Boutique » a **disparu de l'inscription** : un collaborateur
  ne s'inscrit plus lui-même ;
- rôles proposés : vendeur, magasinier, comptable, responsable — **aucun rôle
  de plateforme** ne peut être attribué par une entreprise ;
- un compte sans boutique valide est refusé, et un collaborateur d'une autre
  entreprise est invisible et intouchable.

> Migrations : `0140` (création), `0141`/`0142` (réparation des comptes
> orphelins), `0143` (affectation à une boutique).

## 2. Pressing : module complet

- **bordereau d'atelier imprimable** (🖨️ dans *Atelier & qualité*) : vêtements
  regroupés par étape, défauts constatés au dépôt, date de retrait, case à
  cocher, visa et contrôle qualité — il suit le filtre de l'écran ;
- **rôles métier** : accueil, caisse, atelier, responsable (les prix et les
  réglages restent au responsable) ;
- **caisse du jour** : encaissements par mode, annulations à part, reste dû
  global, détail imprimable ;
- **annulation de commande** avec motif obligatoire, **QR régénéré**, remise
  partielle ou totale au retrait.

> Migrations : `0120` → `0123`, `0136`, `0137`.

## 3. Multi-boutiques : chaque boutique a ses données

Le sélecteur d'entreprise existait, mais toutes les boutiques partageaient le
même catalogue. Corrigé :

- **produits, stock, ventes, caisse, clients, dettes, dépenses, inventaires et
  rapports** suivent la boutique affichée ;
- un **collaborateur affecté à une boutique** ne voit que ses données ;
- **un propriétaire, plusieurs entreprises** : `entreprises.owner_id` permet
  au patron de posséder plusieurs affaires, **chacune avec son abonnement et
  son échéance** ;
- le **patron n'est plus compté** comme collaborateur dans le supplément
  (sinon chaque facture passait de 12 500 à 15 000).

> Migrations : `0145` (socle `owner_id`), `0146` (bascule entreprise + boutique,
> création d'entreprise en essai), `0147` (ouverture d'une 2ᵉ entreprise).

## 4. Correctifs de production

| Correctif | Effet |
|---|---|
| **Sorties de stock non commerciales** | perte, casse, péremption, consommation du patron : le stock baisse **sans** créer d'argent, avec un rapport imprimable |
| **Vente à crédit** | crée la dette et n'entre **pas** en caisse (plus de double comptage) |
| **Régularisation d'une dette** | option « encaisser une dette » : l'argent entre en caisse au bon moment |
| **SerdiPay obligatoire** | un abonnement se règle par SerdiPay, jamais en espèces ; les 7 jours d'essai s'ajoutent au mois payé (37 jours) |
| **Comptes collaborateurs sans boutique** | nom, rattachement et rôle réparés sans toucher au mot de passe |
| **Déclencheur hérité `uuid ""`** | sécurisé : les mises à jour de fiches ne plantent plus |
| **Liste des utilisateurs vide** | l'erreur RLS est désormais affichée, plus de liste vide silencieuse |

## 5. Migrations à exécuter

Dans l'ordre, si ce n'est pas déjà fait :

```
20260916000132_sorties_stock_speciales.sql
20260916000133_vente_credit_sans_encaissement.sql
20260916000134_serdipay_obligatoire_abonnement.sql
20260916000135_urembo_echeance_09_12_2026.sql
20260916000136_pressing_equipe_et_roles.sql
20260916000137_pressing_caisse_jour.sql
20260916000138_fix_creation_utilisateur_auth.sql
20260916000139_fix_visibilite_utilisateurs.sql
20260916000140_collaborateurs_sans_code.sql
20260916000141_fix_collaborateurs_portes_ouvertes.sql
20260916000142_collaborateurs_entreprise_coherente.sql
20260916000143_collaborateur_boutique.sql
20260916000145_entreprises_owner_id.sql
20260916000146_bascule_entreprise.sql
```

Tous les scripts sont **idempotents** : les relancer ne casse rien.

## 6. Ce qui reste ouvert

1. **Rapports consolidés** toutes boutiques (aujourd'hui : par entreprise).
2. **Vitrine marketplace par boutique** (tables déjà prêtes).
3. **Quotas IA** : pool par compte ou par entreprise — décision produit.
4. Le mot de passe d'un collaborateur créé par la plateforme est **provisoire**
   et doit être changé à la première connexion.

---

**Vérifications de cette version** : `dart analyze` sans erreur,
**1433 tests** au vert, APK/Desktop/Web construits par la CI.
