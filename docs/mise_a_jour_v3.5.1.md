# Biashara Yangu — v3.5.1 (build 45)

**Type :** correctifs (aucune fonctionnalité retirée)
**Migrations SQL :** `0106` — s'ajoute aux `0100` → `0105`.

---

## 1. Comptes production / stock coincés entre « Rapports » et « Stock »

Constat : un compte de distribution (gestionnaire de stock, responsable de
production) arrivait directement sur **Rapports** puis **Stock**, sans aucun
moyen de se déconnecter.

Trois causes, toutes corrigées :

- le rôle global MAGASINIER n'avait pas la page **Paramètres** — or c'est là
  que se trouve le bouton **Déconnexion** ;
- la barre de navigation filtrait la branche Paramètres quand aucun droit
  n'était trouvé : elle est désormais **toujours proposée** (garde-fou) ;
- un collaborateur de distribution était traité comme un employé de boutique.

Désormais, un **collaborateur de distribution** (gérant, production, stock,
commercial, comptable) est ouvert **directement sur `/main/distribution`** —
son espace, avec son stock, sa caisse et ses écrans. Le propriétaire garde
l'accueil.

## 2. Abonnement calculé dès la création « setup »

Constat : une boutique créée depuis le setup affichait « montant à régler
**0 CDF** », un renouvellement à 10 000 CDF au lieu du prix de la grille, et
les essais de 7 jours semblaient « sans abonnement ».

Cause : `rpc_entreprise_creer_simple` écrivait `montant_total_du = 0` pour
l'essai, donc aucun solde n'existait — SerdiPay refusait la transaction
(`SOLDE_NUL`).

Corrigé (migration `0106`) :

- à la création, le **montant dû** est celui de la grille
  (`entreprises.prix_installation`, sinon `groupes_tarifaires.montant_abonnement` —
  20 000 CDF pour la distribution). L'essai de 7 jours reste **actif** : rien
  n'est encaissé, mais le montant existe ;
- les entreprises **déjà créées** en essai avec 0 CDF sont réparées
  automatiquement (uniquement `statut = ESSAI_7J`, jamais payées, montant 0) ;
- aucun compte actif, payé ou suspendu n'est touché.

## 3. Choix de l'opérateur Mobile Money plus lisible

Chaque opérateur de l'écran SerdiPay porte maintenant une **pastille de
couleur avec son sigle** (OM, AM, MP, AF, CB) en plus de son nom : le
commerçant identifie le bon service d'un coup d'œil.

---

## Après mise à jour

1. Exécuter `supabase/migrations/20260916000106_abonnement_montant_setup.sql`.
2. Vérifier le résultat :

```sql
select nom, statut, montant_total_du, montant_deja_paye, solde_restant
  from public.entreprises
 where statut = 'ESSAI_7J'
 order by created_at desc
 limit 10;
```

Le `montant_total_du` des essais doit être le prix de leur grille (20 000 CDF
pour la distribution), plus 0.
