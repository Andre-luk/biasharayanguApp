# Module 17 — Verrouillage des comptes non activés & catégorie d'activité

> Migration SQL : `supabase/migrations/20260916000038_module17_verrouillage_comptes.sql`
> (à exécuter APRÈS les migrations 0000 → 0037 — idempotente).
>
> Code application :
> `lib/services/abonnement_service.dart` (état d'accès + chemins verrouillés),
> `lib/config/app_router.dart` (middleware : refus par lien direct),
> `lib/pages/compte_verrouille_page.dart` (page explicative),
> `lib/widgets/banniere_abonnement.dart` (bandeau + dialogues),
> `lib/pages/home_page.dart` (cadenas sur les actions),
> `lib/pages/setup_page.dart` (choix de la catégorie à l'inscription),
> `lib/pages/mes_entreprises_page.dart` (+ `lib/services/espace_service.dart`)
> pour corriger la catégorie d'une entreprise existante.

## 1. Le problème corrigé (diagnostic du 20/09/2026)

| # | Symptôme | Cause racine |
|---|---|---|
| 1 | Un compte **non validé par la finance** pouvait vendre, ajouter des articles, gérer son stock… | `activation_etape` n'était **jamais consommé** par le moteur d'accès ; les RPC d'écriture n'appelaient pas `verifier_action_sensible()` |
| 2 | Les cadenas de l'accueil n'apparaissaient pas | `rpc_entreprises_de_utilisateur()` renvoyait une **liste vide** pour des comptes pourtant rattachés à une entreprise → `evaluerAcces([])` → **fail-open** (accès complet) |
| 3 | Le verrou serveur ne bloquait rien | `abonnement_etat(p_owner)` cherchait `entreprises.id = p_owner` alors qu'on lui passe l'**ID de l'espace** (`mon_proprietaire()`) → entreprise introuvable → `'OK'` |
| 4 | Un client qui choisit **Hôtel** obtient un environnement **Boutique** | `rpc_entreprise_creer` créait toujours `espaces.type = 'boutique'` et nommait l'entreprise « Boutique X » : aucune catégorie n'était transmise |

## 2. Règle métier appliquée (partout)

```
CRÉATION → VÉRIFICATION (gestionnaire) → PAIEMENT → VALIDATION (finance)
        → ACTIVATION → COMPTE OPÉRATIONNEL

Avant activation : consultation seule + cadenas sur les opérations
Abonnement échu / compte restreint : même verrouillage (régularisation = lever)
```

L'état unique est calculé côté serveur par `public.abonnement_etat(owner)` :

| État | Signification | Effet application |
|---|---|---|
| `OK` | compte actif et à jour | tout est ouvert |
| `ACTIVATION` | `activation_etape ∈ {en_attente_verification, verifie, rejete}` | cadenas + message « compte en attente de validation » |
| `LECTURE_SEULE` | abonnement échu, complément attendu, ou `activation_etape = restreint` | cadenas + message de régularisation |
| `BLOQUE` | entreprise suspendue par l'administrateur | connexion refusée |

## 3. Verrou **serveur** (impossible à contourner)

La migration 0038 installe la fonction `trg_blocage_commercial()` sur les
tables commerciales : `ventes`, `produits`, `conditionnements`,
`approvisionnements`, `ajustements`, `inventaires_quotidiens`, `depenses`,
`dettes`, `caisse`, `clotures_caisse`, `chambres`, `reservations`,
`tables_salle`, `commandes`, `salles`, `evenements`, `matieres_premieres`,
`productions` (+ tables filles : `lignes_commande`, `lignes_evenement`,
`consommations_production` — propriétaire résolu via la table parente).

Conséquences :

* une écriture PostgREST directe est refusée ;
* une écriture via RPC est refusée (`ACTIVATION_REQUISE`, `ABONNEMENT_EXPIRE`
  ou `ABONNEMENT_BLOQUE` — messages français affichés par les services) ;
* le **personnel plateforme** (`est_plateforme()`) n'est jamais bloqué ;
* propriétaire illisible → **fail-open** (jamais de blocage accidentel).

## 4. Verrou **application** (lisibilité immédiate)

* **Cadenas** sur les actions rapides de l'accueil (« Nouvelle vente »,
  « Scanner ») et sur les actions secondaires (« Ajouter un produit »,
  « Collaborateurs ») : bouton grisé + médaillon 🔒, clic → dialogue
  explicatif avec accès au dossier.
* **Bandeau** persistant en haut de l'application (badge « En attente » ou
  « Lecture seule »).
* **Page `/main/compte-verrouille`** : rappel de la procédure
  (création → vérification → paiement → activation), bouton « J'ai payé —
  vérifier mon compte », lien vers `/main/mon-activation`.
* **Middleware du routeur** : un compte non opérationnel est redirigé vers
  cette page dès qu'il demande un écran commercial, **même par lien direct**
  (`AbonnementService.cheminVerrouille`).
* **Lever automatique** : `rafraichirSilencieux()` est appelé au démarrage de
  l'accueil, au retour au premier plan et au « tirer pour rafraîchir » → dès
  que la finance active le compte, les cadenas disparaissent **sans
  reconnexion**.

Écrans **toujours consultables** : accueil, catalogue, stock, caisse,
finance, rapports, ventes, dossier d'activation, mes entreprises.

## 5. Catégorie d'activité respectée

* **Inscription** (`setup_page`) : sélecteur « Catégorie d'activité »
  alimenté par `rpc_types_espaces_publics()` (repli local : types standards) ;
  la valeur est envoyée à `rpc_entreprise_creer(p_nom, p_telephone, p_type)`.
* **Serveur** : `rpc_entreprise_creer` v6 valide la catégorie contre le
  référentiel `types_espaces_modules` (repli « autre » → « boutique »),
  crée l'espace avec ce type et nomme l'entreprise « `<Libellé> <nom>` » quand
  aucun nom n'est fourni (ex. « Hôtel Jambo »).
* **Correction d'un compte existant** : écran « Mes entreprises » → icône ✏️
  sur une carte → `rpc_espace_type_definir(espace, type)` (propriétaire
  seulement) ; les modules (`rpc_mes_modules`) suivent immédiatement, donc le
  tableau de bord et les menus aussi.
* **Création d'une entreprise supplémentaire** : après création, elle devient
  l'espace ACTIF automatiquement — le client voit tout de suite
  l'environnement de sa catégorie.

Exemple : passer « HÔTEL KM » de Boutique à Hôtel fait apparaître les cartes
Chambres / Réservations / Réception.

## 6. Vérifications après exécution

> ✅ **Migration 38 EXÉCUTÉE et VÉRIFIÉE le 20/09/2026** (base de production).
> Résultats des sondes :
>
> | Test | Résultat |
> |---|---|
> | `rpc_entreprises_de_utilisateur` (compte rattaché) | renvoie enfin la ligne + `activation_etape` (avant : `[]`) |
> | Compte `en_attente_verification` → insertion `produits` (PostgREST direct) | `ACTIVATION_REQUISE` ✅ refusé |
> | Idem → `rpc_depense_creer`, `rpc_stock_definir_seuil` | `ACTIVATION_REQUISE` ✅ refusés |
> | Retour à `actif` → `rpc_stock_definir_seuil` | ✅ accepté (déblocage automatique) |
> | Inscription neuve avec `p_type = 'hotel'` | espace `type=hotel`, `rpc_mes_modules` → chambres/réservations/réception, statut en attente |
> | `rpc_espace_type_definir` boutique→hôtel→boutique | ✅ modules suivent à chaque fois |
> | `rpc_espace_type_definir` avec type inconnu | `TYPE_INCONNU` ✅ refusé |

```sql
-- Triggers de verrou en place (attendu : 21 lignes)
select event_object_table, event_manipulation
  from information_schema.triggers
 where trigger_name = 'trg_m17_blocage'
 order by 1, 2;

-- État d'accès des derniers comptes
--   ACTIVATION  = en attente de vérification/finance
--   OK          = opérationnel
select nom, statut, activation_etape, public.abonnement_etat(id) as etat_acces
  from public.entreprises order by created_at desc limit 10;

-- Catégories proposées à l'inscription
select public.rpc_types_espaces_publics();
```

### 6.1 Corriger un compte existant dont la catégorie est fausse

Les comptes créés **avant** le module 17 sont typés « boutique » (le type
n'était pas transmis). Deux moyens de les corriger :

1. **Dans l'application** : « Mes entreprises » → icône ✏️ → choisir la
   catégorie → les modules suivent immédiatement ;
2. **En SQL** (exemple du compte « HÔTEL KM ») :

```sql
update public.espaces
   set type = 'hotel', updated_at = now()
 where id = '007a0852-4a9a-4b2e-bdd7-be9c8e80eb34';

-- Variante générique : toutes les entreprises dont le nom évoque un hôtel.
update public.espaces s
   set type = 'hotel', updated_at = now()
  from public.entreprises e
 where e.id = s.entreprise_id
   and s.type = 'boutique'
   and (e.nom ilike 'hôtel%' or e.nom ilike 'hotel%' or e.nom ilike '%hôtel%');
```

## 7. Scénarios de recette

| Scénario | Attendu |
|---|---|
| Compte neuf (aucune validation) | Cadenas partout, bandeau « En attente », vente refusée (serveur) |
| Gestionnaire valide le dossier | Toujours verrouillé (attente finance) |
| Finance valide un paiement **total** | Cadenas levés, compte ACTIF 30 jours |
| Finance valide un paiement **partiel** | Débloqué pour 7 jours d'essai, solde suivi |
| Abonnement échu | Cadenas de nouveau, consultation possible |
| Régularisation validée par la finance | Déblocage automatique (sans reconnexion) |
| Catégorie Hôtel choisie à la création | Espace `hotel`, modules chambres/réservations/réception |
| Compte existant « Boutique » qui est un hôtel | ✏️ Mes entreprises → Hôtel → environnement hôtel |

## 8. Tests automatisés

`flutter test test/verrouillage_test.dart` (17 cas) : états d'accès
(activation en attente, vérifié, rejeté, actif, échu, restreint, suspendu,
migration absente), chemins verrouillés / consultables, catégories d'activité.
Suite complète : `flutter test` (584 tests).
