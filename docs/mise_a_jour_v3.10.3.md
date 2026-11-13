# Mise à jour v3.10.3 — l'entreprise active est mémorisée

**Date** : 14 novembre 2026
**Type** : correctif critique (multi-entreprises)
**Version** : `3.10.3+60`
**Complète** : v3.10.2

---

## 1. Ce que vous avez constaté

> « Lorsque je me connecte avec josephissa, j'arrive sur le tableau de bord, je
> sélectionne la pharmacie, les noms de produits pharmaceutiques s'affichent et
> "Nouvel article" propose bien le lot et la date. Mais **quand je quitte
> l'application et que je rentre**, le sélecteur disparaît, il reste seulement
> la pharmacie, et les noms de produits sont redevenus ceux de la boutique. »

C'est exactement ce que la v3.10.2 devait corriger… et c'était **incomplet**.
Voici le maillon manquant.

## 2. Pourquoi cela arrivait encore

L'entreprise active n'était connue que par **le réseau**. Au redémarrage, la
requête `rpc_espaces_lister` doit répondre pour que l'application sache où elle
se trouve. Or :

- sur un réseau lent ou instable (4G faible, wifi qui s'établit, onglet rouvert
  très vite), cette requête **échoue au premier essai** ;
- l'échec était **silencieux** ;
- l'application retombait alors sur la valeur de secours : **l'UUID du patron**,
  c'est-à-dire la **première entreprise** du compte (Urembo Market).

D'où le symptôme exact :

| Élément | Ce qu'il affichait | Pourquoi |
| --- | --- | --- |
| Titre du bandeau | « PHARMACIE » | il vient du **serveur** (activité de l'espace) |
| Bouton « Changer d'entreprise » | absent | la liste locale était vide |
| Liste des articles | produits de la **boutique** | la portée de secours = première entreprise |
| « Nouvel article » | enregistrait dans la boutique | même portée de secours |

## 3. Le correctif

### 3.1 Le contexte est mémorisé sur l'appareil

`lib/services/espace_service.dart` — la dernière liste d'entreprises connue est
enregistrée localement (clé `espace_etat_cache_v1`).

Au démarrage, **avant tout appel réseau**, l'application publie cet état :
l'entreprise active est donc correcte dès le premier écran, **même hors ligne**.

Le serveur reste la source de vérité : dès qu'il répond, la valeur est
remplacée. S'il ne répond pas, on garde la dernière entreprise connue — jamais
la première de la liste.

### 3.2 Trois tentatives au lieu d'une

`chargerSilencieux()` réessaie (400 ms puis 800 ms). Un démarrage sur réseau
instable n'échoue plus systématiquement.

### 3.3 Un délai maximum au démarrage

`initialiserContexte()` : cache d'abord, puis confirmation serveur limitée à
8 secondes. L'application ne reste jamais bloquée sur le splash parce que le
réseau est mauvais.

### 3.4 La déconnexion efface le cache

Aucun risque qu'un autre compte, sur le même appareil, hérite de l'entreprise
du précédent.

## 4. Résultat pour vous

1. Connexion → bascule sur la pharmacie.
2. **Fermer complètement l'application** (ou recharger la page web).
3. Rouvrir : le bandeau affiche **« Changer d'entreprise »** et
   **HEKIMA PHARMA** ; la liste montre les **médicaments** (24 articles) et non
   les articles de la boutique ; « Nouvel article » propose toujours
   **Lot & péremption**.

Le comportement est identique en mode avion : l'application se souvient de la
dernière entreprise utilisée.

## 5. Vérifications techniques

```
flutter test                     → 1479 tests OK
flutter analyze                  → 0 erreur
```

Nouveaux tests : `test/espace_cache_test.dart` (5 tests) — restauration du
cache, publication de la portée de travail, cache illisible, cache vide,
remise à zéro à la déconnexion.

## 6. À noter

- Le cache ne contient **aucune donnée métier** : uniquement les noms/ids des
  entreprises du compte et l'entreprise active.
- Un changement d'entreprise effectué sur un autre appareil est repris dès que
  le serveur répond (le cache n'est qu'un secours).
