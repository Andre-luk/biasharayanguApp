# Mise à jour v2.8.0 — Le code de validation des agents

**Version :** 2.8.0 (build 31)
**Migrations SQL :** `20260916000069_code_validation_agent.sql` puis
`20260916000070_agent_verifie_dossier.sql` *(à exécuter après les correctifs 67
et 68)*
**Tests :** 835/835 ✅

---

## En une phrase

**Une vérification de compte ne peut plus être signée par le seul agent : la
Finance doit lui dicter un code à 6 chiffres, et si elle ne le fait pas dans les
5 minutes, l'agent continue — mais la Finance le voit.**

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

## Notes techniques (pour la fiche store)

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
- `rpc_activation_valider_finance` **n'est délibérément pas touchée** : un bloc
  de contrôle **échoue** si `AGENT_TERRAIN` y apparaît un jour. L'agent peut
  vérifier un dossier, il ne peut pas valider un paiement — et cette limite est
  vérifiée automatiquement, pas seulement promise.

**Application** : `models/code_validation_agent.dart`,
`services/code_validation_agent_service.dart`,
`widgets/code_validation_agent.dart` (côté agent),
`widgets/codes_validation_finance.dart` (côté Finance),
`pages/comptes_verification_page.dart`, `pages/activations_finance_page.dart`.

**Repli assumé** : tant que les migrations 69 et 70 ne sont pas exécutées,
l'application **le dit** (« Migration 69 non installée : le code de validation
n'est pas encore actif sur ce serveur ») au lieu d'échouer sans explication.
