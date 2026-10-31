# Biashara Yangu — v3.4.0 (build 42)

**Date :** 31 octobre 2026
**Type :** version majeure (abonnements, distribution, hors ligne)
**Migrations SQL :** `0091`, `0092`, `0093`, `0094` — voir « À faire après
l'installation ».

---

## En une phrase

Le compte **s'active tout seul** (7 jours d'essai), les prix viennent d'un
**barème par défaut** négociable, une **avance se lit désormais en jours**, la
**vente fonctionne sans réseau**, et l'**agent peut encaisser pour la
boutique** qu'il a prise en charge.

---

## 1. Le client se débrouille seul

| Avant | Maintenant |
|---|---|
| création → « en attente de vérification » → validation par l'administration | création → **compte actif, essai 7 jours** |
| code de validation transmis à l'agent | **aucun code** |
| prix saisis à la main, souvent oubliés | **barème appliqué automatiquement** |

Un déclencheur serveur (`abonnement_politique_automatique`) fait les deux
choses, quel que soit le créateur : le client lui-même, un agent de terrain ou
un administrateur.

## 2. Le barème

| Profil | Installation | Abonnement mensuel |
|---|---|---|
| Boutique — mode simple (création autonome) | **10 000** | **5 000** |
| Boutique — mode complet | **30 000** | **10 000** |
| Distribution (eau, PGC, tournées) | **50 000** (jusqu'à 100 000) | **20 000** |

Un prix négocié — par le patron, le client ou l'agent — **n'est jamais
écrasé** : le barème ne remplit que ce qui est vide. Et comme le moteur lit le
prix de l'entreprise, **l'autonomie suit automatiquement** les prix négociés.

## 3. L'avance intelligente

Le client verse une partie du mois et **sait tout de suite ce qu'il achète** :

> 30 000 le mois → 1 000 par jour → **5 000 = 5 jours**

L'écran de paiement l'affiche à chaque frappe (« Ce versement couvre environ
5 jour(s), droit d'utiliser l'application jusqu'au … »), calculé **sur le
téléphone**, donc même hors ligne. Payer la totalité = 30 jours.

## 4. L'agent encaisse pour l'entreprise

Un agent de terrain n'était pas reconnu comme « personnel plateforme » : il
recevait un refus. Il peut désormais ouvrir et payer l'abonnement des
**dossiers qu'il a lui-même pris en charge** (bouton « Encaisser » sur chaque
boutique de sa liste). Aucun autre droit n'est élargi : le montant reste
calculé et borné par le serveur.

## 5. Le 100 % hors ligne

**Vendre sans réseau** — c'était le vrai manque : la vente est désormais
enregistrée sur l'appareil (stock local déduit) avec un reçu
`HORS-LIGNE-…`, puis rejouée automatiquement par la transaction officielle
dès le retour du réseau. Un refus métier du serveur (stock, droits,
abonnement) reste un refus : on n'écrit jamais en local par-dessus.

**Lire sans réseau** — chaque écran garde sa dernière réponse connue :
accueil / tableau de bord, dossier d'activation, abonnement, liste des
entreprises, et **tous les rapports déjà consultés**.

**Les conflits sont visibles** — une vente qui ne part pas après 5 tentatives
n'est jamais perdue ni réessayée sans fin : elle apparaît dans « **À vérifier
(N)** » avec son motif, et un bouton « Réessayer ».

## 6. La distribution terrain (rappel des versions précédentes, incluses)

Tournées avec objectif et commission, écarts (casse / offert) déclarés,
**radar de tournée** et radar agent, **rapport de tournée imprimable**
(en-tête, lignes, reçus, productions, signatures), traçabilité des bouteilles
produites, profil « Distribution » avec ses modules.

## 7. Paramètres adaptatifs

Les réglages s'adaptent à l'activité et aux modules activés : un hôtel ne voit
pas les tournées, un vendeur ne voit pas les réglages du patron. Recherche
intégrée (accents et casse ignorés). Principe **fail-open** : un type non
renseigné ou un module inconnu n'affiche jamais moins que la réalité.

---

## À faire après l'installation

⚠️ **Quatre migrations à exécuter** dans le SQL Editor (dans cet ordre) :

1. `0091_bareme_et_activation_auto.sql`
2. `0092_agent_paie_pour_entreprise.sql`
3. `0093_rattrapage_comptes_existants.sql` — applique le barème aux comptes
   **déjà existants** et active ceux restés en attente de validation
4. `0094_solde_restant_ordinaire.sql` — `solde_restant` redevenue colonne
   ordinaire (sinon **chaque encaissement d'abonnement échoue**)

Puis coller `docs/verification_migrations.sql` : chaque objet doit être `OK`.

⚠️ **Redéployer l'Edge Function `serdipay`** : elle transmet le montant
d'avance et l'entreprise ciblée. Sans ce redéploiement, ces deux
fonctionnalités restent inactives.

⚠️ **Renseigner `entreprises.type_activite`** : sans type, tout le monde tombe
sur le barème « boutique complète ».

## Ce qui n'est pas couvert

- Un rapport **jamais ouvert** n'est pas consultable hors ligne (il faut une
  première connexion).
- Le **paiement Mobile Money** est en ligne par nature.
- Les entreprises de **distribution** doivent avoir le profil de modules
  « Distribution » attribué à leur espace.

---

## Technique

- `flutter analyze` : 0 erreur. **1116 tests** automatiques verts.
- Nouvelles suites : `avance_intelligente_test.dart` (10),
  `hors_ligne_complet_test.dart` (10), `radar_tournee_test.dart` (13),
  `rapport_tournee_test.dart` (8), `installation_forfaits_test.dart` (12),
  `mode_rapide_test.dart` (13), `abonnement_autonomie_test.dart` (14),
  `catalogue_parametres_test.dart` (19).
- Base locale SQLite **v13** : table `cache_lecture`, colonnes
  `ventes.tentatives` / `ventes.sync_erreur`.
