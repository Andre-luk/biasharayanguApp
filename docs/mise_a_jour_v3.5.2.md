# Biashara Yangu — v3.5.2 (build 46)

**Type :** correctifs + une fonctionnalité demandée (décaissement d'achat)
**Migrations SQL :** `0107` — s'ajoute aux `0100` → `0106`.

---

## 1. Décaissement = achat de marchandise (entrée en stock)

Dans la **caisse**, le décaissement peut maintenant payer une marchandise :

- interrupteur **« Achat de marchandise »** ;
- choix de l'**article** (produits de la boutique) et de la **quantité reçue** ;
- la dépense est enregistrée en catégorie `achat` ;
- le **stock entre automatiquement** au prix unitaire réellement payé
  (`montant ÷ quantité`), avec le journal d'approvisionnement habituel
  (`approvisionnements`).

Ainsi la caisse et le stock racontent la même histoire : l'argent qui sort
correspond à une quantité qui entre.

## 2. Tout compte a une grille tarifaire (migration `0107`)

Les entreprises créées depuis « setup » n'avaient **aucune grille**
(`groupe_tarifaire_id` vide) : prix inconnu, donc montant dû à 0, renouvellement
au mauvais tarif, SerdiPay qui refuse.

- un **trigger** attribue désormais automatiquement une grille à toute
  entreprise qui n'en a pas : celle de son **type d'activité**, sinon la moins
  chère ;
- les entreprises **existantes** sont réparées par la même règle ;
- le montant dû des essais encore à 0 est re-renseigné (règle de la `0106`).

Aucun compte payé, actif ou suspendu n'est modifié.

## 3. Barre de navigation complète dès la création du compte

Après une inscription, l'accueil n'affichait que **« Accueil »** : il fallait
quitter puis rouvrir l'application pour que le compte du propriétaire soit
réellement pris en charge.

Corrigé : à la fin de la création, l'application relit le profil local, fixe le
**rôle courant**, recharge la **matrice de permissions** et le contexte
Distribution **avant** d'afficher `/main`.

## 4. Tableau de bord Distribution

La tuile **« Collaborateurs »** du bas de la grille d'accès rapide est retirée :
la gestion des collaborateurs passe par l'**icône en haut de l'écran**
(propriétaire uniquement). La grille reste consacrée aux opérations du jour.

---

## Après mise à jour

Exécuter `supabase/migrations/20260916000107_grille_tarifaire_par_defaut.sql`,
puis vérifier :

```sql
select e.nom, e.statut, e.type_activite, g.nom as grille,
       g.montant_abonnement, e.montant_total_du, e.solde_restant
  from public.entreprises e
  left join public.groupes_tarifaires g on g.id = e.groupe_tarifaire_id
 order by e.created_at desc
 limit 15;
```

Aucune entreprise ne doit avoir `groupe_tarifaire_id` vide, et les essais
doivent porter un `montant_total_du` non nul.
