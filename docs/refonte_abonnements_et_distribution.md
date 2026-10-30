# Refonte abonnements & distribution — architecture et feuille de route

> **Statut** : analyse terminée, phase 1 livrée en base et dans l'application.
> Les phases 2 → 6 sont spécifiées ci-dessous avec leurs critères d'acceptation.
> Dernière mise à jour : 30/10/2026.

---

## 1. Ce qui existe déjà (vérifié dans le code)

| Domaine | Existant | Fichier / table |
|---|---|---|
| Forfaits | `groupes_tarifaires` (activite_id, frais_ouverture, montant_abonnement, durées, prix/collaborateur, max_espaces, modules) | `lib/models/groupe_tarifaire.dart` |
| Niveaux | `niveaux_abonnement` (ESSENTIEL / PRO / PREMIUM + `modules jsonb`) | migration 65 |
| Entreprise | `montant_total_du`, `montant_deja_paye`, `solde_restant` (généré), `date_expiration`, `statut`, `prix_installation`, `prix_abonnement_mensuel` | `lib/models/entreprise.dart` |
| Moteur de paiement | `rpc_abonnement_enregistrer_paiement` (migration 03, dernière définition 62, patch live 53) — gère avances, compléments, renouvellements, `EN_ATTENTE_COMPLEMENT` | migrations 03/53/62 |
| Factures | `factures_abonnement` + `compteurs_factures` + numérotation | migration 67 |
| Encaissement | `paiements_abonnement` (module 1) **et** `paiements_abonnements_laperle` (module 3) | migrations 01/03 |
| Mobile Money | Edge Function `serdipay` opérationnelle (jeton, `payment-merchant`, webhook, frais opérateur) | `supabase/functions/serdipay/index.ts` |
| Distribution | `tournees`, `tournee_lignes`, `consignes`, `bonus_clients`, `compteurs_tournee` + 12 RPC | migration 80 |
| Écrans distribution | `tournees_page`, `tournee_form_page`, `tournee_detail_page`, `ma_tournee_page` | `lib/pages/` |
| Service + modèles | `DistributionService` (17 méthodes), `distribution_terrain.dart` (10 modèles) | `lib/services/`, `lib/models/` |
| Activités / modules | `ModuleCode` (23 codes), `ReglesActivite`, `ModulesService` (fail-open) | `lib/models/module_activite.dart` |
| Rôles | `RoleUtilisateur` (10 rôles), `PageAccess.distribution` / `.maTournee` | `lib/models/permission.dart` |
| Mode rapide | `ModeApplicationService` (`complet` / `rapide`) | `lib/services/mode_application_service.dart` |

### Manques constatés

1. **Aucun type d'activité par entreprise** : une boutique et une distribution sont traitées de la même façon (seul `activite_id` distingue les forfaits).
2. **Les cartes de distribution étaient rattachées au module `ventes`** → toute boutique voyait « Tournées », « Consignes », « Ma tournée ».
3. **Pas de consigne facturée / échangée** : `consignes` est un simple compteur de contenants (`libelle_contenant` en texte libre), sans lien avec les produits ni les conditionnements.
4. **Pas de règle de bonus configurable** : `bonus_clients` enregistre un bonus ponctuel, mais aucune règle « 5 fardes = 1 offerte ».
5. **Pas de commissions / écarts d'agent** sur `tournees` ni `tournee_lignes`.
6. **Le mode rapide ne simplifie pas les formulaires produit** (aucun champ masqué).
7. **Pas d'indicateur d'anomalie** sur les tournées (écarts, agents suspects, recommandations).
8. **DDL de base de `entreprises` et `groupes_tarifaires` absente du dépôt** (créées hors migrations) — à ne pas recréer.

---

## 2. Phase 1 — Type d'activité (LIVRÉE le 30/10/2026)

### Base de données — `20260916000083_type_activite_entreprise.sql`
- `entreprises.type_activite` (`boutique` | `distribution` | `NULL`)
- `groupes_tarifaires.type_activite`, `niveaux_abonnement.type_activite`
- `rpc_entreprise_type_activite()` (lecture), `rpc_entreprise_definir_type_activite()` (plateforme ou propriétaire), `rpc_forfaits_lister(type)`
- **Aucune réécriture de données** : `NULL` par défaut.

### Application
- `lib/models/type_activite.dart` — enum, conversion tolérante, `ReglesTypeActivite.masque()`.
- `lib/services/type_activite_service.dart` — `ValueNotifier<TypeActivite?>`, rechargé à la bascule d'entreprise, **fail-open**.
- `ModuleCode.distribution` + `ReglesActivite.distribution()`.
- `CarteAccueil.typeRequis` : « Tournées », « Consignes clients » et « Ma tournée » ne s'affichent plus que pour une entreprise de **distribution** — et restent visibles tant que le type n'est pas renseigné.
- 11 tests purs (`test/type_activite_test.dart`).

### Critères d'acceptation
- [x] Une entreprise dont `type_activite` est `NULL` voit **exactement** les mêmes écrans qu'avant.
- [x] Une entreprise `boutique` ne voit aucune carte de distribution.
- [x] Une entreprise `distribution` voit ses trois cartes.
- [ ] **À faire par l'exploitant** : exécuter la migration 0083, puis renseigner le type des entreprises existantes :
  ```sql
  update public.entreprises set type_activite = 'distribution'
   where id = '<entreprise de distribution>';
  update public.entreprises set type_activite = 'boutique'
   where id = '<boutique>';
  ```

---

## 3. Phase 2 — Forfaits propres à la distribution

> **État au 30/10/2026** : le socle est livré (colonne `type_activite` sur
> `groupes_tarifaires` + `rpc_forfaits_lister(type)`, migration 0083).
> Reste à faire : le patch du moteur pour la règle « installation jamais
> refacturée » — il touche `rpc_abonnement_enregistrer_paiement`, donc il doit
> être appliqué avec la technique `regexp_replace` sur `pg_get_functiondef`
> (voir `abonnement_paiement.md`) et **jamais** par redéfinition complète.

**Base** : renseigner `groupes_tarifaires.type_activite = 'distribution'` pour les grilles de distribution et créer les grilles manquantes (installation + mensuel, max agents, max tournées).

**Règles à faire respecter par le moteur** (à ajouter dans `rpc_abonnement_enregistrer_paiement` / `rpc_abonnement_ouvrir`) :
- l'installation (`prix_installation`) n'est facturée **qu'une seule fois** par entreprise : elle ne revient jamais dans un renouvellement ;
- une avance (paiement partiel) place le dossier en `EN_ATTENTE_COMPLEMENT` **sans** ouvrir un nouveau cycle (règle déjà corrigée par la migration 53 — ne pas la casser) ;
- le délai de 7 jours pour compléter une avance est calculé depuis le **premier** versement partiel du cycle ;
- aucune activation si `solde_restant > 0` **sauf** règle d'avance explicite.

**Application** : écran de choix de forfait filtré par `rpc_forfaits_lister(typeActivité)` ; affichage « installation déjà réglée » quand `prix_installation` a déjà été payé au moins une fois.

**Critères d'acceptation**
- Un renouvellement ne réintègre jamais l'installation.
- Deux paiements simultanés du même dossier ne produisent qu'un seul crédit (idempotence : `reference` unique + `for update`).
- Un paiement dont la transaction Mobile Money n'est pas confirmée ne crédite rien.

---

## 4. Phase 3 — Récipients, échanges et fardes

> **État au 30/10/2026 : LIVRÉE** — migration 0084, service Dart, écran
> `/main/recipients` (types, règles de bonus, solde par client, déclaration de
> perte), carte d'accueil « Récipients & bonus », 25 tests dédiés.

### Livré — `20260916000084_recipients_echanges_bonus.sql` (55/55 instructions)
Tables : `recipients_types`, `recipients_mouvements`, `regles_bonus`,
`bonus_attribues` (RLS lecture seule, écritures par RPC uniquement).
RPC : `rpc_recipients_types_lister`, `rpc_recipient_type_enregistrer`,
`rpc_vente_recipient` (les trois cas), `rpc_recipient_perte`,
`rpc_recipients_solde_client`, `rpc_recipients_tableau_bord`,
`rpc_regles_bonus_lister`, `rpc_bonus_regle_enregistrer`, `rpc_bonus_appliquer`
(idempotent par `(client, règle, tournée)`).
Dart : `lib/models/recipients.dart`, `lib/services/recipients_service.dart`,
`test/recipients_test.dart`.

> ⚠️ **Aucune vente n'est écrite par ces RPC** : elles tracent les récipients et
> les bonus, l'encaissement reste celui de la caisse / des tournées. Le chiffre
> d'affaires ne peut donc pas être compté deux fois.

### Modèle de référence
```
recipients_types(id, owner_id, libelle, contenance_litres, prix_consigne, actif)
recipients_mouvements(id, owner_id, agent_id, client_id, tournee_id,
                      type_id, sens, quantite, montant, motif, created_at)
   sens ∈ {livre, recupere, vendu, casse, perdu, rendu}
regles_bonus(id, owner_id, produit_id, type_declencheur, quantite_declencheur,
             type_offert, quantite_offerte, actif)
bonus_attribues(id, owner_id, client_id, regle_id, tournee_id, quantite,
                date_bonus, annule_le)   -- anti double attribution
```

### Opérations (RPC transactionnelles, écritures directes révoquées)
- `rpc_vente_recipient(...)` : trois cas de la demande —
  1. **nouveau récipient** : montant = eau + récipient, sortie d'un récipient plein, entrée d'un récipient « vendu » ;
  2. **échange** : montant = eau seule, entrée d'un vide (`recupere`), sortie d'un plein (`livre`) ;
  3. **récipient du client** : montant = remplissage seul, aucune ligne récipient.
- `rpc_bonus_appliquer(...)` : applique la règle active, refuse un doublon
  (contrainte d'unicité `(client_id, regle_id, tournee_id)`), sort le stock offert
  **sans** créer de chiffre d'affaires.
- `rpc_recipients_solde_client(client)` : ce que le client détient encore.

### Critères d'acceptation
- Un récipient n'est jamais compté deux fois (vendu ≠ prêté ≠ consigné ≠ échangé).
- `quantite_sortie - quantite_echangee - quantite_recuperee = ecart` est calculé, jamais saisi.
- Une vente avec bonus n'augmente pas le chiffre d'affaires du montant offert.

---

## 5. Phase 4 — Espace agent et tournées (LIVRÉE le 30/10/2026)

> **État au 30/10/2026 : LIVRÉE** — migration
> `20260916000085_tournees_commissions_controle.sql` (34/34 instructions),
> modèles et service Dart étendus, écrans « Préparer une tournée »,
> « Ma tournée », « Tournées » et « Détail » enrichis, 26 tests dédiés
> (`test/distribution_test.dart`, 40 au total dans le fichier).

### Ce qui a été décidé (et pourquoi)

- **La commission est CALCULÉE, jamais saisie.** `commission_montant` est
  produite à la clôture par `round(CA × taux / 100, 2)`, sur le chiffre
  d'affaires réellement encaissé (table `ventes`), et non sur la dotation.
  Un pourcentage promis oralement ne laisse aucune trace ; celui-ci oui.
- **L'objectif et le taux sont fixés par le propriétaire uniquement** :
  `rpc_tournee_parametrer` refuse tout autre appelant, et refuse aussi une
  tournée clôturée (la commission ne se renégocie pas après coup).
- **Casse et bonus sont des sorties de dotation nommées** :
  `tournee_lignes.quantite_casse` / `quantite_bonus`, déclarées par l'agent
  pendant la tournée (`rpc_tournee_declarer_ecart`). Elles **ne créent aucune
  vente** — un article offert n'est pas un chiffre d'affaires.
- **Le prix d'achat est figé à la dotation** (`prix_achat_snapshot`, posé par
  trigger) : la marge d'une tournée passée ne bouge plus si le tarif d'achat
  change. La marge est donc `CA − Σ(unités vendues × prix d'achat figé)`.
- **Contrôle serveur conservé** : `rpc_tournee_vente` sélectionne la tournée
  par `agent_id = auth.uid()`. Un agent B ne peut pas vendre sur la tournée de
  l'agent A, même en fabriquant l'appel RPC.

### Invariant central

```
quantite_vendue + quantite_retournee + quantite_bonus + quantite_casse
  <= quantite_attribuee + 0.0001
```

`ecart = attribuee − vendue − retournee − bonus − casse` est calculé par le
serveur, ligne par ligne, et renvoyé **nommé** (`ecarts: [{nom, quantite}]`).


- `tournees` : ajouter `zone_couverte`, `objectif_montant`, `commission_taux`, `cloturee_par`.
- `tournee_lignes` : ajouter `quantite_bonus`, `quantite_casse`, `prix_achat_snapshot`.
- Contrôle serveur : `rpc_tournee_vente` vérifie `agent_id = auth.uid()` **ou** délégation explicite (`peut_gerer_espace`), et que le produit figure bien dans `tournee_lignes` (on ne vend pas ce qui n'a pas été confié).
- Nouveaux rôles de distribution à mapper sur la matrice existante : `RESPONSABLE_DISTRIBUTION`, `SUPERVISEUR`, `GESTIONNAIRE_STOCK`, `AGENT_DISTRIBUTEUR` (aucun accès caisse boutique).

**Critère d'acceptation** : un agent B ne peut pas modifier une opération de la tournée de l'agent A, même en appelant la RPC directement.

---

## 6. Phase 5 — Mode rapide réellement simple (LIVRÉE le 30/10/2026)

> **État au 30/10/2026 : LIVRÉE** — `add_product_page.dart`,
> `article_form_page.dart`, getter `ModeApplicationService.afficherReglagesAvances`,
> `test/mode_rapide_test.dart` (13 tests).

En mode rapide, la création d'un article ne demande plus que **le nom et le
prix de vente** (plus la quantité, pour pouvoir vendre tout de suite). Photo,
catégorie, unité de base, prix d'achat, seuils et lots sont des réglages
**avancés** : ils restent disponibles en mode complet.

La règle n'est pas dupliquée dans chaque écran : elle vit dans
`ModeApplicationService.afficherReglagesAvances`, donc testable sans interface.
L'unité de base retombe sur « pièce » à l'enregistrement (jamais vide), et les
deux modes écrivent **exactement les mêmes données**.


- `add_product_page` **et** `article_form_page` : en mode `rapide`, n'afficher que
  **nom** + **prix de vente** ; tous les autres champs passent sous un
  « Paramètres avancés » replié (visibles en mode `complet`).
- Même traitement dans la création de produit d'une tournée.
- Aucun champ technique obligatoire supplémentaire (`stock_illimite` reste une
  valeur par défaut, modifiable dans les paramètres avancés).

**Critère d'acceptation** : en mode rapide, créer un article ne demande que deux saisies, et l'article est immédiatement vendable en caisse.

---

## 7. Phase 6 — Contrôle intelligent des marchandises (fonctionnalité différenciante)

**« Radar de tournée »** — un contrôle automatique, calculé en base, affiché à
l'ouverture d'une tournée et à sa clôture :

1. **Écarts** : `confié − vendu − retourné − bonus − casse` ; tout écart non nul
   est nommé (marchandise, quantité), jamais noyé dans un total.
2. **Score d'anomalie par agent** sur 30 jours : moyenne pondérée des écarts
   rapportés à ce qui a été confié, plus les ventes à crédit non recouvrées.
   Trois niveaux (normal / à surveiller / alerte) — **explicables** : l'écran dit
   toujours *pourquoi*.
3. **Recommandation de chargement** : pour la tournée suivante, propose une
   quantité par produit = médiane des ventes des 4 dernières tournées de la même
   zone, ajustée du taux de retour observé.
4. **Clients à risque de consigne** : clients détenant des récipients depuis plus
   de N jours, triés par valeur de consigne.

Tout est calculé par RPC (`rpc_radar_tournee`, `rpc_radar_agent`) sur des
transactions réelles — aucune donnée inventée, aucun écran « décoratif ».

**Critère d'acceptation** : sur une tournée clôturée avec un écart réel, le radar
identifie le bon produit et la bonne quantité ; les recommandations restent
bornées par le stock disponible.

---

## 8. Garde-fous transverses

- **Une entreprise = un périmètre** : toute nouvelle table porte `owner_id` + RLS.
- **Rôles vérifiés côté serveur** : aucune nouvelle RPC ne fait confiance au client.
- **Historique** : les écarts et les bonus sont des lignes d'historique, jamais des
  suppressions ; une annulation est un `annule_le` horodaté.
- **Idempotence** : toute opération de paiement ou de bonus porte une clé unique.
- **Hors ligne** : les nouvelles opérations passent par les mêmes files locales
  que les ventes (aucune rupture du fonctionnement actuel).
