# Mise à jour v3.10.6 (build 63) — correctif 179

**Date** : 21 novembre 2026
**Migration Supabase requise** : `20260916000179_finances_uuid_text_et_rapport_vendeurs.sql`
(à exécuter après la 0177 ; il n'y a pas de 0178 : le correctif 178 était
purement côté application).

> **Cette version contient aussi le correctif 178** (isolation des sessions) :
> un seul service de déconnexion vide rôle, permissions, entreprise active,
> modules, abonnement, panier, scans et caches ; le rôle est lu d'abord au
> serveur (un super admin ne retombe plus dans l'interface boutique) ; le
> cache d'espace est cloisonné par compte ; les cartes métier de l'accueil
> attendent le profil. Détails : `docs/correctif_178_isolation_session.md`.

## Finances : plus d'erreur « uuid = text »

* Les écrans **Finances plateforme** et **Finances des abonnements** refonctionnent :
  la base convertit proprement les anciennes colonnes d'identifiants restées en
  texte, et les fonctions Finance comparent désormais les identifiants de façon
  tolérante (elles fonctionnent même si une sauvegarde restaure du texte).
* Une fonction de contrôle `finance_verifier_types()` indique à tout moment les
  colonnes qui resteraient en texte.
* Le rapprochement Mobile Money conserve sa trace dans le journal d'audit.

## Rapport par collaborateur (vendeur)

* Nouveau rapport disponible depuis **Mon Équipe → 📊 Stats collaborateurs**.
* Chaque vendeur a son propre rapport : nombre de ventes, quantités, chiffre
  d'affaires, panier moyen, produits vendus et **journal détaillé**.
* Chaque vente indique le **stock restant avant et après** :
  « Stock : 4 avant → 3 après », et **qui avait vendu l'unité précédente** du
  même article.
* Le PDF du vendeur contient les colonnes **Stock avant** et **Stock après**.
* Un article supprimé affiche « stock inconnu » : aucun chiffre n'est inventé.

## Les chiffres correspondent partout

* Le tableau de bord, le rapport du patron et les rapports par vendeur
  utilisent désormais **le même périmètre** (toutes les boutiques/espaces de
  l'entreprise), **la même définition de vente** (ventes d'articles +
  prestations de pressing) et **la même journée** (minuit heure de Lubumbashi).
* La date de référence est fournie par le serveur : un téléphone mal réglé ou
  dans un autre fuseau n'affiche plus d'autres chiffres.
* Le tableau de bord expose en plus les ventes et le chiffre d'affaires du
  mois, ainsi que les quantités vendues.
* La migration se termine par un contrôle automatique de cohérence : l'écart
  entre le tableau de bord et le rapport doit être **0**.

## Vérification

* `dart analyze lib` : aucune erreur.
* `flutter test` : suite verte, dont 11 nouveaux tests rejouant l'exemple
  « 5 beignets, A en vend 1, B en vend 1 ».
* Contrôle SQL de structure : migration 0179 équilibrée (52 instructions).
