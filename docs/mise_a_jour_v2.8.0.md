# Mise à jour v2.8.0 — Code de validation des agents & alerte de stock

**Version :** 2.8.0 (build 32)
**Migrations SQL :** `20260916000069_code_validation_agent.sql` puis
`20260916000070_agent_verifie_dossier.sql` *(à exécuter après les correctifs 67
et 68)*
**Tests :** 842/842 ✅

---

## En une phrase

**Une vérification de compte ne peut plus être signée par le seul agent — la
Finance doit lui dicter un code à 6 chiffres — et l'alerte de stock se déclenche
enfin quand la marchandise disparaît, pas seulement quand elle est vendue.**

---

## Ce qui change pour vous

### 👷 Pour l'agent de terrain

Quand vous confirmez une vérification de compte, l'application vous demande un
**code de validation** :

1. vous appuyez sur « Demander un code à la Finance » ;
2. la Finance vous le dicte au téléphone ;
3. vous saisissez les 6 chiffres → le dossier part.

**Et si la Finance ne répond pas ?** Au bout de 5 minutes, le bouton
**« Continuer sans code »** apparaît. Vous pouvez travailler : le terrain n'est
jamais bloqué par un téléphone qui ne répond pas.

> ⚠️ Mais alors la Finance **doit confirmer le compte après coup** — elle le voit
> dans sa liste « dossiers à confirmer ». C'est le prix de la liberté laissée à
> l'agent : ce qui est fait sans code est **tracé comme tel**, jamais caché.

Si vous vous trompez de chiffres, l'application vous dit **exactement** ce qui
ne va pas : code faux, code expiré, code déjà utilisé, ou aucun code encore
émis par la Finance.

### 💼 Pour la Finance et le Super Admin

Un bandeau **« Codes de validation »** apparaît en haut de l'écran « Activations
& paiements ». Il reste discret quand tout va bien, et s'ouvre quand il y a
quelque chose à faire :

- **les demandes en attente** — le code s'affiche en très gros caractères, prêt
  à être dicté à l'agent. Vous pouvez le renvoyer (un nouveau code remplace
  l'ancien) ou révoquer la demande ;
- **les dossiers à confirmer** — les comptes vérifiés par un agent **sans
  aucun code**. La ligne vous dit **qui** doit agir :
  - « Aucun code demandé par l'agent » → l'agent a sonné sans demander ;
  - « La Finance n'a pas encore répondu » → la demande est bien arrivée, mais
    personne n'y a répondu ;
  - « Code jamais saisi — à vérifier » → le code a été émis et n'a pas été
    utilisé.

Cette distinction est le cœur de la liste : **les deux situations n'accusent pas
la même personne**, et les mélanger rendrait le contrôle inutilisable.

### 🔒 Ce que le dispositif garantit

- **Le code ne peut pas être fabriqué par l'agent.** Lui seul ne peut que
  *demander* ; seul la Finance et le Super Admin peuvent *émettre*.
- **Le code n'est jamais écrit dans le journal d'audit** — ni en base, ni dans
  l'application. Un journal se lit, se copie et se partage : y écrire le code
  reviendrait à supprimer le contrôle. Le journal garde **qui**, **quand** et
  **le résultat** — jamais les chiffres.
- **L'agent ne voit jamais le code d'un autre.** Il ne voit que ses propres
  demandes.
- **Un seul code ouvert à la fois** par compte : impossible d'en empiler dix
  pour brouiller la trace.

---

## Alerte de stock : les ajustements et l'inventaire comptent enfin

### 📦 Ce qui n'allait pas

Seule une **vente** pouvait déclencher l'alerte « stock faible ». Un
**ajustement d'inventaire** — c'est-à-dire précisément le moment où l'on
constate que la marchandise a disparu — ne disait rien.

Autrement dit : **le stock ne pouvait passer sous son seuil que si le manquant
avait été vendu.** Une perte, un vol, une casse — le cas le plus grave — était
le seul cas parfaitement muet.

### ✅ Ce qui change

Désormais, l'alerte se déclenche aussi :

- après un **ajustement d'inventaire** d'un article ;
- après une **clôture d'inventaire quotidien** (pour chaque article dont le
  comptage a fait baisser le stock) ;
- après un **ajustement de matière première** (farine, levure, sucre…) ;
- après une **consommation de matière première** en production — le chemin par
  lequel une boulangerie vide vraiment ses réserves, et qui n'émettait
  strictement aucune alerte.

### 🎯 Deux précautions qui évitent de noyer l'alerte

- **On n'alerte que si le seuil vient d'être franchi.** Une marchandise déjà en
  alerte ne redéclenche rien à chaque nouveau mouvement — sinon l'alerte
  perdrait tout sens et on cesserait de la lire.
- **Un écart d'inventaire non appliqué n'alerte pas.** Si vous comptez sans
  corriger le stock (clôture en lecture seule), le stock n'a pas bougé :
  signaler une disparition qui n'a pas eu lieu serait une fausse alerte. Or une
  fausse alerte apprend à ignorer les vraies.

---

## Notes techniques (pour la fiche store)

**Application — correctif 71** (aucune migration) :

- `services/stock_service.dart` : alerte après `ajuster()` (le serveur renvoie
  déjà `stock_avant` / `stock_apres`) et après `cloturerInventaire()` ;
- la **règle de sélection** des articles à examiner est extraite dans une
  fonction **pure et publique** `StockService.baissesDeStockApresInventaire` :
  écart **réellement corrigé** ET **en baisse**. Une règle qu'on ne peut pas
  tester est une règle qu'on cassera sans s'en apercevoir ;
- `services/production_service.dart` : alerte après `ajusterMatiere()` et
  `consommer()`. **`rpc_matiere_ajuster` ne renvoie pas le stock avant**
  (contrairement à `rpc_stock_ajuster`) : il est donc **relu en base** — une
  lecture coûte moins cher qu'une migration supplémentaire pour une
  notification, et elle ne dépend d'aucune valeur fournie par l'appelant ;
- **tout est best-effort** : l'opération est déjà enregistrée côté serveur, une
  alerte ratée ne doit jamais remonter comme un échec de stock.

**Base de données — correctif 69** (`20260916000069_code_validation_agent.sql`) :

- table `codes_validation_agent` (demande, motif, émission, expiration,
  validation) avec **index unique partiel** : une seule demande ouverte par
  compte ;
- `rpc_agent_code_demander` (agent — **idempotente** : une demande déjà ouverte
  est renvoyée, pas dupliquée) ;
- `rpc_agent_code_emettre` (**FINANCE_LAPERLE ou SUPER_ADMIN uniquement** —
  code à 6 chiffres, valable 5 minutes) ;
- `rpc_agent_code_valider` (l'agent — distingue `CODE_INCORRECT`, `EXPIRE`,
  `DEJA_UTILISE`, `AUCUN_CODE_EMIS`, `REVOQUE`) ;
- `rpc_agent_code_revoquer`, `rpc_agent_codes_lister`,
  `rpc_agent_dossiers_sans_code` ;
- **le code n'est renvoyé qu'à la Finance et au Super Admin** : la colonne sort
  `null` pour tous les autres rôles — le filtrage est dans la requête, pas dans
  l'affichage ;
- le délai (5 min) vit dans **une seule fonction** `delai_code_agent_minutes()`,
  définie **avant** la table (une fonction ne peut pas être appelée dans le
  `DEFAULT` d'une colonne avant d'exister) ;
- les 5 nouvelles actions d'audit (`AGENT_CODE_DEMANDE`, `_EMIS`, `_VALIDE`,
  `_ECHEC`, `_REVOQUE`) sont classées **HAUT** ou **MOYEN** dans `audit_niveau` —
  sans ce patch elles seraient retombées au niveau `INFO`, c'est-à-dire au même
  niveau qu'un affichage de page.

**Base de données — correctif 70** (`20260916000070_agent_verifie_dossier.sql`) :

- `rpc_activation_verifier` **recréée à l'identique** depuis la migration 18, avec
  **une seule ligne changée** : la garde de rôle accepte désormais
  `AGENT_TERRAIN`. Un script extrait, remplace, et **vérifie que rien d'autre n'a
  bougé** ;
- ⚠️ **CE QUI A ÉTÉ CORRIGÉ DANS CE FICHIER, ET POURQUOI.** La première version
  affirmait que le serveur réservait la validation du paiement à
  `FINANCE_LAPERLE` et `SUPER_ADMIN`, et **faisait échouer** la migration si
  `AGENT_TERRAIN` apparaissait dans cette fonction. C'était une **erreur de
  lecture** : la migration 43 (section 3.c) passe en revue **toutes** les
  fonctions contenant `'SUPER_ADMIN'` et remplace dynamiquement
  `('FINANCE_LAPERLE', 'SUPER_ADMIN')` par
  `('FINANCE_LAPERLE', 'AGENT_TERRAIN', 'SUPER_ADMIN')`. La validation du
  paiement accepte donc l'agent de terrain **depuis la 43, et volontairement**
  (« il crée les entreprises, vérifie et active leurs dossiers et **valide les
  paiements reçus** »). Le contrôle a donc bloqué un choix de conception déjà
  installé, en le prenant pour une escalade de droits ;
- **la leçon, et elle vaut pour tout le dépôt** : lire une vieille migration ne
  donne **pas** la définition en vigueur. Une migration ultérieure peut
  re-patcher une fonction par `replace()` sur `pg_get_functiondef`, et rien dans
  le fichier d'origine ne le laisse voir. Le contrôle cherche désormais la
  **garde réelle** (`v_role not in (...)`, extraite par expression régulière)
  au lieu du mot `AGENT_TERRAIN` n'importe où dans le corps ;
- ce qu'il **refuse** maintenant : que la Finance ou le Super Admin **perde** la
  validation du paiement (le seul invariant défendu ici) ; ce qu'il **signale
  sans juger** : la présence de l'agent dans cette garde, avec un `raise notice`
  qui dit d'où elle vient ;
- **pourquoi la migration est conservée** alors que la 43 avait déjà élargi la
  garde : la migration 18 est idempotente (`create or replace`), et la rejouer —
  un réflexe normal en cas de doute — **remettrait** la garde d'origine sans que
  personne ne s'en aperçoive avant que l'agent voie son bouton refusé. Ce
  fichier fige l'intention dans un texte lisible. Il est sans effet si la 43 a
  déjà fait le travail.

**Application** : `models/code_validation_agent.dart`,
`services/code_validation_agent_service.dart`,
`widgets/code_validation_agent.dart` (côté agent),
`widgets/codes_validation_finance.dart` (côté Finance),
`pages/comptes_verification_page.dart`, `pages/activations_finance_page.dart`.

**Repli assumé** : tant que les migrations 69 et 70 ne sont pas exécutées,
l'application **le dit** (« Migration 69 non installée : le code de validation
n'est pas encore actif sur ce serveur ») au lieu d'échouer sans explication.
