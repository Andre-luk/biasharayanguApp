# Mise à jour v3.10.5 (build 62) — correctif 178

**Date** : 20 novembre 2026
**Correctif client** : aucune migration Supabase n'est nécessaire.

## Le problème

En se connectant avec le **super admin**, l'application affichait le tableau de
bord boutique avec les menus du bas « Rapports » et « Système » ; et une
**boutique** héritait du contexte **pressing** avec ses trois menus (Dépôts,
Atelier, Retraits).

## Ce qui a été corrigé

* **Déconnexion complète** : les six déconnexions de l'application passent par
  un seul service qui vide le rôle, les permissions, l'entreprise active, le
  profil de modules, l'abonnement, le panier, l'historique de scan et les
  caches. Aucun état ne survit d'un compte à l'autre.
* **Le rôle vient du serveur** : au démarrage, à la connexion et dans la
  navigation, le rôle est lu dans la base. La valeur locale ne sert plus que de
  repli hors ligne. Un compte plateforme ouvre désormais la console `/admin`.
* **Garde-fou de navigation** : un compte plateforme ne peut plus atteindre
  `/main`, un compte d'entreprise ne peut plus atteindre `/admin`, même par un
  lien direct.
* **Espace mémorisé par compte** : le dernier espace connu n'est plus stocké
  sous une clé commune. Une boutique ne peut plus restaurer l'espace du
  pressing utilisé juste avant sur le même appareil.
* **Accueil** : les cartes propres à un métier (pressing, hôtel, restaurant,
  salle des fêtes, boulangerie, distribution) n'apparaissent qu'une fois le
  profil de l'entreprise connu. Les cartes transverses (vente, stock, caisse,
  finance, rapports, marketplace, abonnement) restent immédiatement visibles.
* **Pressing** : chaque métier (accueil, atelier, caisse, responsable,
  propriétaire) ne voit que ses écrans ; les écrans d'équipe et de réglages
  sont réservés au responsable.

## Vérification

* `dart analyze lib` : aucune erreur.
* `flutter test` : suite complète verte, dont 12 nouveaux tests d'isolation de
  session.
* Vérification manuelle décrite dans `docs/correctif_178_isolation_session.md` :
  pressing → déconnexion → super admin → boutique sur le même appareil.
