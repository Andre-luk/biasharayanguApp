# Mise à jour v3.10.2 — « je ne dois jamais lire l'entreprise voisine »

**Date** : 14 novembre 2026
**Type** : correctif critique (multi-entreprises)
**Version** : `3.10.2+59`

---

## 1. Le problème constaté

Compte `josephissa` (deux entreprises : **Urembo Market** en boutique et
**HEKIMA PHARMA** en pharmacie) :

1. après un **rechargement de la page** (web) ou un redémarrage de
   l'application, le bouton **« Changer d'entreprise »** disparaissait du
   bandeau ;
2. la liste des articles affichait **les produits de la boutique** alors que
   HEKIMA PHARMA était l'entreprise active ;
3. **« Nouvel article »** enregistrait donc dans la boutique, et les deux
   catalogues semblaient **mélangés**.

## 2. La cause exacte

La liste des entreprises n'était chargée **qu'après une connexion**
(`login_page`). Quand la session est **restaurée** (rechargement web, retour
d'arrière-plan, redémarrage), ce code n'est pas exécuté : l'application ne
savait donc plus quelle entreprise était active.

Conséquences en cascade :

| Ce qui manquait | Effet visible |
| --- | --- |
| Liste des entreprises jamais chargée | le sélecteur ne s'affiche pas (il n'a rien à montrer) |
| Entreprise de travail inconnue | les lectures retombent sur la portée de secours |
| Portée de secours = première entreprise du compte | on lit/écrit dans **la boutique** au lieu de la pharmacie |

## 3. Les correctifs

### 3.1 Chargement au démarrage (cause principale)

`lib/main.dart` — le contexte d'entreprise est désormais chargé **avant** les
services qui en dépendent (modules, type d'activité, devise) :

```dart
await EspaceService.instance.chargerSilencieux();
```

Il est attendu (une seule requête) parce que la portée de travail doit être
connue **avant le premier écran**. `chargerSilencieux` n'échoue jamais : hors
ligne, l'application démarre comme avant.

### 3.2 Filet de sécurité dans les écrans

`lib/services/espace_service.dart` — nouvelle méthode `assurerChargement()` :
elle charge la liste **seulement si elle n'est pas déjà connue**, sans jamais
relancer un chargement en cours (déduplication).

`lib/utils/ecoute_contexte_entreprise.dart` — tout écran qui écoute le
contexte (articles, stock, ventes, caisse, clients…) demande maintenant ce
chargement s'il manque, puis **se recharge tout seul** quand la vraie
entreprise arrive. Plus aucun écran ne peut rester bloqué sur la portée de
secours.

### 3.3 Un pack d'abonnement ne peut plus cacher un écran

`lib/services/modules_service.dart` — nouveau `packHorsActivite()` :
si les fonctionnalités ouvertes par l'abonnement n'ont **aucun rapport** avec
l'activité de l'entreprise (cas réel : le pack « Pharmacie » contenait les
modules du pressing), le filtre d'abonnement est ignoré.

C'est ce qui faisait disparaître « Lot & péremption » du formulaire d'article
d'une pharmacie. La règle d'or reste : **un pack mal configuré ne masque
jamais un champ légitime**.

## 4. Ce qui change concrètement pour vous

- Vous rechargez la page ou vous redémarrez : **l'entreprise reste la bonne**.
- Le bouton **« Changer d'entreprise »** est de nouveau dans le bandeau dès
  l'ouverture, même avec une session déjà connectée.
- La liste des articles, le stock, les ventes et la caisse suivent
  l'entreprise affichée — **jamais** l'autre.
- « Nouvel article » enregistre dans l'entreprise **affichée en haut**.

## 5. Vérification (2 minutes)

1. Connexion avec un compte à deux entreprises.
2. **Recharger** la page (F5) → le bandeau affiche toujours le nom de
   l'entreprise et « Changer d'entreprise ».
3. Ouvrir **Articles** → les produits correspondent à cette entreprise
   (pharmacie : médicaments ; boutique : articles de la boutique).
4. « Nouvel article » → l'article apparaît dans la liste de **cette**
   entreprise, pas dans l'autre.
5. Basculer d'entreprise → la liste change immédiatement.

## 6. Tests

```
flutter test            → 1474 tests OK
flutter analyze         → 0 erreur
```

Nouveaux tests : `test/abonnement_modules_test.dart` (groupe « Pack rattaché
à la mauvaise activité », 4 tests).
