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

## 3. Phase 2 — Forfaits propres à la distribution (LIVRÉE le 31/10/2026)

> **État au 31/10/2026 : LIVRÉE** — migration
> `20260916000087_forfaits_et_installation.sql` (10/10 instructions),
> `EtatInstallation`, `GroupeTarifaire.typeActivite`, filtrage des forfaits,
> encart « installation » dans le détail d'abonnement,
> `test/installation_forfaits_test.dart` (12 tests).

### Ce qui a été ajouté (sans toucher au moteur)

**`rpc_forfaits_entreprise(p_entreprise, p_type)`** — renvoie les forfaits
proposables : ceux du type d'activité de l'entreprise **plus** les forfaits
communs (`type_activite IS NULL`). Un type inconnu ne filtre rien.

**`rpc_abonnement_installation_etat(p_entreprise)`** — répond à la question
« l'installation est-elle déjà réglée ? » en lisant **les faits** :

```
installation_deja_reglee =
      date_activation IS NOT NULL                    -- règle du moteur (correctif 60)
   OR un versement de type installation/ouverture existe
   OR au moins un cycle a été soldé
```

Elle renvoie aussi `prochain_cycle` (`installation` | `abonnement`) et
`prochain_montant` : l'écran affiche donc ce que le prochain encaissement
demandera, sans que personne ait à le calculer de tête.

### ⚠️ Ce qui n'a PAS été fait, volontairement

`rpc_abonnement_enregistrer_paiement` **n'est pas redéfini**. Le correctif 60
y applique déjà la règle :

```sql
v_premier_cycle := (v_entreprise.date_activation is null);
-- premier cycle  → prix_installation (premier mois inclus)
-- cycles suivants → prix_abonnement_mensuel seul
```

Réécrire ce moteur pour « ajouter » une règle déjà présente ferait perdre les
correctifs 43 et 53 (voir `abonnement_paiement.md`). On expose l'état, on ne
duplique pas la règle.

### Application

- `GroupeTarifaire.typeActivite` + `proposableA(TypeActivite?)` — **fail-open** :
  type du pack ou de l'entreprise inconnu → le pack reste proposé.
- `EntrepriseService.getGroupesTarifaires({activiteId, typeActivite})`.
- `AbonnementService.etatInstallation({entrepriseId})` — ne lève jamais
  d'exception : en cas d'échec, `EtatInstallation.inconnu` et l'encart
  disparaît (on ne bloque pas une consultation pour un bandeau).
- `AbonnementDetailPage` : encart « Installation déjà réglée : elle ne sera pas
  refacturée. » + prochain encaissement + nombre de cycles soldés.

### Reste à faire par l'exploitant

```sql
-- Grilles de distribution
update public.groupes_tarifaires set type_activite = 'distribution'
 where nom ilike '%distribu%';
update public.groupes_tarifaires set type_activite = 'boutique'
 where nom ilike '%boutique%' or nom ilike '%standard%';
```

**Critères d'acceptation**
- [x] Un renouvellement ne réintègre jamais l'installation (correctif 60, exposé
      par `prochain_cycle`).
- [x] Un forfait de distribution n'est pas proposé à une boutique — et l'inverse.
- [x] Une entreprise sans type connu voit tous les forfaits (aucune régression).
- [ ] Idempotence des doubles paiements : portée par le moteur (migration 53),
      non modifiée ici.

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

### Livré — `20260916000086_radar_tournee.sql` (10/10 instructions)

**`rpc_radar_tournee(p_tournee uuid default null, p_zone text default null)`**

- `ecarts` : uniquement les lignes dont l'écart n'est **pas** nul, avec
  `attribuee / vendue / retournee / bonus / casse / ecart / valeur`. Un écart
  négatif est renvoyé tel quel (incohérence de saisie, pas un vol).
- `recommandations` : médiane (`percentile_cont(0.5)`) des quantités vendues sur
  les **4 dernières tournées clôturées de la même zone**, corrigée du taux de
  retour observé, puis **bornée par `produits.quantite`**. Le champ
  `quantite_retenue` est ce plafond ; `quantite_suggeree` reste la valeur brute
  pour que le patron voie que le stock limite.
- `historique_suffisant: false` quand il n'y a aucun historique : on ne
  fabrique pas une recommandation à partir de rien.
- `consignes_risque` : récipients `chez_client`/`partielle` depuis ≥ 30 jours,
  valorisés via `recipients_types.prix_consigne` (jointure par libellé),
  limités à 20, triés par valeur.
- `p_tournee = null` → la RPC ne renvoie que recommandations + consignes : c'est
  ce qu'utilise le bouton « Suggérer les quantités » **avant** de créer la
  tournée.

**`rpc_radar_agent(p_agent uuid default null, p_jours integer default 30)`**

Score **expliqué**, jamais une note magique :

```
score = 100 × (0.6 × part_écart + 0.4 × part_impayé)
part_écart  = min( (écart / confié) / 0.05 , 1 )     -- 5 % du confié = saturation
part_impayé = min( (crédit / CA) / 0.20 , 1 )        -- 20 % du CA     = saturation
niveau      : < 30 normal · 30-59 à surveiller · ≥ 60 alerte
```

`motifs` renvoie toujours au moins une entrée (`AUCUNE_ANOMALIE` si tout est
justifié) avec `code`, `libelle`, `detail` chiffré et `valeur`. Un agent ne peut
consulter que son propre radar ; le propriétaire consulte qui il veut.

### Écrans

- **Détail d'une tournée** : carte « Radar de tournée » — écarts nommés et
  valorisés, chargement conseillé (avec l'icône de stock limité), récipients à
  relancer. La carte est chargée en parallèle des lignes ; si elle échoue,
  l'écran reste utilisable (`catchError` → radar vide).
- **Ma tournée** (agent) : carte « Mon radar (30 jours) » avec le niveau, les
  motifs et une phrase qui rappelle que le score montre « ce qui reste à
  justifier », pas une accusation.
- **Préparer une tournée** (patron) : bouton ✨ « Suggérer les quantités » qui
  pré-remplit la dotation à partir de `radarTournee(zone: …)`. Les quantités
  restent modifiables : le radar propose, le patron décide.

Dart : `EcartProduit`, `RecommandationChargement`, `ConsigneARisque`,
`RadarTournee`, `MotifRadar`, `RadarAgent`, `NiveauAnomalie` dans
`lib/models/distribution_terrain.dart` ; `radarTournee()` / `radarAgent()` dans
`DistributionService` ; `test/radar_tournee_test.dart` (13 tests).

---

## 8. Phase 7 — L'abonnement en autonomie (LIVRÉE le 31/10/2026)

> **État au 31/10/2026 : LIVRÉE** — migration
> `20260916000088_abonnement_autonomie.sql` (32/32 instructions),
> Edge Function `serdipay` (montant d'avance), écrans « Mon dossier
> d'activation » et « Paiement Mobile Money », menu de gestion du compte,
> `test/abonnement_autonomie_test.dart` (11 tests).

### Le blocage constaté

`rpc_serdipay_ouvrir` (migration 0079) facturait `entreprises.solde_restant`.
Un cycle **entièrement payé puis expiré** laisse `solde_restant = 0` : aucun
mécanisme n'ouvrait le cycle suivant. Le client recevait
« Aucun montant à payer : votre abonnement est déjà réglé » et ne pouvait donc
PAS se renouveler seul. Le paiement passait obligatoirement par un agent.

### Ce qui a été livré

**1. `rpc_abonnement_prix_du_cycle(p_entreprise)`** — prix du prochain cycle :
`prix_abonnement_mensuel` → `groupes_tarifaires.montant_abonnement` → montant du
cycle précédent (**jamais** l'installation).

**2. `rpc_abonnement_preparer_renouvellement(p_entreprise)`** — ouvre le cycle
suivant (`montant_total_du = prix`, `montant_deja_paye = 0`).
Garde-fous :
- refus si le compte n'a jamais été activé (`PREMIER_CYCLE` : l'installation
  est due, ce n'est pas un renouvellement) ;
- refus si l'abonnement **court encore** (`CYCLE_EN_COURS`) : aucun risque de
  facturer deux fois le même mois ;
- rien à faire si un solde est déjà ouvert (`DEJA_OUVERT`).

**3. `rpc_serdipay_ouvrir` v2** — supprime la v1 (sinon surcharge ambiguë),
appelle la préparation quand l'abonnement est échu et accepte un
`p_montant` : le client peut verser une **avance** (bornée par le solde réel).
Le moteur (`rpc_abonnement_enregistrer_paiement`, inchangé) active
automatiquement dès que le cycle est soldé, et place le dossier en
`EN_ATTENTE_COMPLEMENT` sur un versement partiel.

**4. Quotas IA inclus** — `groupes_tarifaires.quotas_ia_mensuels` (pack) et
`entreprises.quotas_ia_mensuels` (négocié, prioritaire), réglables via
`rpc_abonnement_definir_quotas_ia` ou l'écran « Prix de l'abonnement et quotas
IA ». Un **trigger sur `entreprises.date_expiration`** crédite le pool
`agent_ia_quotas` à chaque cycle payé — quel que soit le payeur (client,
agent, webhook). Le trigger n'échoue jamais (erreurs avalées) : un quota ne
peut pas bloquer un paiement.

**5. `rpc_entreprise_supprimer(p_entreprise, p_confirmation)`** — nettoyage des
entreprises de test : SUPER_ADMIN uniquement, confirmation écrite
« SUPPRIMER ». Le catalogue est interrogé pour supprimer **toutes** les tables
portant `owner_id` ou `entreprise_id`, puis les comptes liés (y compris par
`parent_id`), puis l'entreprise. Les comptes Supabase *Authentication* restent
à supprimer séparément (l'écran le dit).

**6. Type d'activité des entreprises existantes** — menu « Gestion du compte »
sur la fiche entreprise : Boutique / Distribution / Non renseigné
(`rpc_entreprise_definir_type_activite`, migration 0083).

### Parcours client

```
Mon abonnement  →  (solde > 0)  → Payer maintenant  → montant exact ou avance
                →  (échu, soldé) → Renouveler maintenant → cycle ouvert
                                 → Payer maintenant  → activation AUTOMATIQUE
```

Les agents de la plateforme ne sont plus un passage obligé ; ils restent
disponibles en cas de demande du client.

---

## 9. Phase 8 — Traçabilité du produit et rapport imprimable (LIVRÉE le 31/10/2026)

> **État au 31/10/2026 : LIVRÉE** — migration
> `20260916000089_rapport_tournee_detail.sql` (7/7 instructions),
> `RapportTourneePdf` (A4), bouton « Imprimer » sur le détail d'une tournée,
> `test/rapport_tournee_test.dart` (8 tests).

### Le circuit complet d'une bouteille

```
1. PRODUCTION   → `productions` (quantite_reelle) → à la clôture, le produit
                  fini ENTRE EN STOCK (ajustement officiel, module 9).
                  Profil d'espace « distribution » : module `production` inclus.
2. DOTATION     → `tournee_lignes.quantite_attribuee` : RÉSERVATION.
                  ⚠️ Le stock ne baisse PAS ici.
3. VENTE        → `rpc_tournee_vente` → `rpc_vente_valider` : le stock baisse
                  réellement, un reçu (numero_vente) est émis.
4. RETOUR       → `quantite_retournee` : rien à réinjecter, car rien n'est
                  sorti du stock à la dotation.
5. CASSE/OFFERT → `quantite_casse` / `quantite_bonus` : sortis sans vente.
6. ÉCART        → confié − vendu − rendu − offert − cassé, CALCULÉ.
```

**Conséquence à retenir** : « ce que l'agent rapporte s'ajoute au stock » est
vrai en comptabilité physique, mais dans l'application la bouteille n'a jamais
quitté le stock. Double-saisir le retour créerait un stock faux. Le rapport
l'écrit noir sur blanc (`note_stock`).

### `rpc_rapport_tournee_detail(p_tournee)`

Renvoie un JSON prêt à imprimer :
- `entete` : référence, date, agent, zone, statut, société, devise, objectif,
  taux et montant de commission ;
- `lignes[]` : par produit — confié / vendu / rendu / offert / cassé /
  manquant + valeur du manquant ;
- `recus[]` : numéro, heure, nombre de lignes, montant (une ligne par panier) ;
- `productions[]` : ce qui est entré en stock le jour de la tournée ;
- `totaux` : somme de tout, plus CA et nombre de reçus.

### Application

- `RapportTournee`, `LigneRapportTournee`, `RecuTournee`, `ProductionDuJour`
  (`lib/models/distribution_terrain.dart`).
- `RapportTourneePdf.imprimer()` : A4, en-tête répété, totaux colorés selon
  qu'il y a un manquant ou non, tableau par produit, production du jour,
  reçus, note sur le stock, deux lignes de signature (agent / responsable).
- Bouton 🖨️ dans la barre du détail de tournée.
- `DistributionService.rapportTourneeDetail(tourneeId)`.

### Reçus déjà disponibles

Les reçus de vente existent depuis la caisse : `InvoiceService` imprime un
ticket 57 mm ou une facture A4 (`new_sale_page`, `vente_confirmation_page`), et
le rapport de tournée liste leurs numéros, heures et montants.

---

## 10. Phase 9 — Installation optionnelle, abonnement obligatoire, démarrage hors ligne (LIVRÉE le 31/10/2026)

> **État au 31/10/2026 : LIVRÉE** — migration
> `20260916000090_mode_simple_abonnement_obligatoire.sql` (11/11),
> cache local de la décision d'accès, délais réseau bornés.

### La règle demandée

« Le client peut **ou non** payer l'installation, mais il est **obligé** de
payer un abonnement. »

| Cas | Ce que le système demande |
|---|---|
| `prix_installation` défini (> 0), **aucun versement** enregistré | l'**installation** (premier mois inclus) — une seule fois |
| `prix_installation` = 0 / NULL (offertes) | directement l'**abonnement mensuel** |
| après le premier versement | **l'abonnement mensuel**, à chaque cycle |
| aucun prix défini nulle part | `PRIX_ABSENT` : la plateforme doit fixer un tarif (aucun accès payant n'est ouvert) |

### Pourquoi ça ne marchait pas

`rpc_entreprise_creer_simple` (mode simple) pose `date_activation = now()` pour
activer l'essai de 7 jours. Le moteur en déduisait « compte déjà activé » et
facturait le **mensuel** : l'installation n'était jamais réclamée, même quand
un prix avait été négocié.

### Les deux corrections (sans toucher au moteur)

1. **`rpc_abonnement_prix_du_cycle`** : si *aucun versement* n'existe sur le
   dossier et qu'une installation est définie, le prochain cycle est
   l'installation. Nouvelle RPC `rpc_abonnement_type_cycle` pour l'afficher.
2. **`rpc_abonnement_preparer_renouvellement`** : à l'ouverture du cycle, le
   statut passe à `EN_ATTENTE_COMPLEMENT`. C'est ce qui **fige le montant** :
   le moteur ne rouvre un cycle que sur `EXPIRE` ou solde nul, donc il crédite
   exactement le montant préparé (installation ou mensuel), sans le recalculer.

### Démarrage rapide, même sans Internet

Le socle local existait déjà (`db_helper` : produits, ventes, clients,
dépenses, dettes, inventaire, approvisionnements). Deux points bloquaient :

- `AbonnementService.verifierAccesUtilisateur` était **attendu sans limite de
  temps** au démarrage → l'écran de lancement pouvait rester figé hors ligne.
  Désormais : **délai de 4 s**, puis **reprise de la dernière décision connue**
  du serveur (`SharedPreferences`, clé `acces_abonnement_dernier`). Sans cache
  (premier lancement), accès complet : on ne bloque jamais un commerçant à
  cause du réseau.
- `PermissionService.rechargerSurcharges` (lecture `app_settings`) : **délai
  de 4 s**, puis permissions par défaut (fail-open).

⚠️ Ce qui reste à faire pour un mode 100 % hors ligne : la **file d'attente
d'écritures** (ventes saisies sans réseau, rejouées à la reconnexion) et la
résolution des conflits. Le socle SQLite existe ; c'est un chantier à part.

---

## 11. Phase 10 — Paramètres adaptatifs et reprise hors ligne (LIVRÉE le 31/10/2026)

> **État au 31/10/2026 : LIVRÉE** — `CatalogueParametres` (registre unique),
> écran Paramètres piloté par le catalogue + recherche, `ReseauService`
> (surveillance + reprise automatique), `BanniereHorsLigne`,
> `test/catalogue_parametres_test.dart` (19 tests).

### Des paramètres qui s'adaptent — et que le propriétaire configure

Un réglage n'est proposé que s'il a un sens pour **cette** entreprise :

| Critère | Effet |
|---|---|
| `typeRequis` (TypeActivite) | « Tournées » et « Récipients » n'apparaissent qu'en distribution |
| `module` (ModuleCode) | « Catégories » exige `produits`, « Alerte de péremption » `lots_expiration` |
| `page` / `action` (permissions) | un vendeur ne voit pas les réglages du patron |

Règle d'or : **fail-open**. Type non renseigné, profil non chargé, module
inconnu → le réglage reste visible, exactement comme avant.

Tout est déclaré dans `lib/ui/parametres/catalogue_parametres.dart` :
**ajouter un réglage = ajouter une entrée**. La page ne contient plus aucune
condition métier ; elle affiche les sections renvoyées par le catalogue.

**Recherche** : le patron tape « devise », « tournée », « publicités » — accents
et casse ignorés — et trouve le réglage sans connaître sa rubrique.

### Hors ligne : la pièce qui manquait

Le socle local existait déjà (`db_helper` : ventes, produits, clients,
dépenses, dettes, inventaire, approvisionnements ; `SyncService` pousse ensuite
vers Supabase).

**`ReseauService`** ajoute ce qui manquait vraiment :

- une sonde minuscule (`app_settings`, 1 ligne, 6 s max) toutes les 25 s en
  ligne, toutes les 8 s hors ligne ;
- `enLigne` (ValueNotifier) : l'état réel, pas une supposition ;
- **transition hors-ligne → en-ligne = `SyncService.syncAll()`** : la file
  locale se vide toute seule, sans bouton ;
- `signalerEchec()` / `signalerSucces()` pour que les écrans informent le
  service sans attendre la sonde.

**`BanniereHorsLigne`** (sous la bannière d'abonnement) : « Hors ligne — vos
ventes restent enregistrées sur cet appareil et seront synchronisées
automatiquement. » + bouton *Réessayer*.

---

## 12. Phase 11 — Barème automatique, activation sans administration, avance intelligente (LIVRÉE le 31/10/2026)

> **État au 31/10/2026 : LIVRÉE** — migration `0091`, `SimulationAvance`
> (modèle + tests), encart d'avance dans l'écran SerdiPay, reprise des ventes
> hors ligne par la RPC officielle. **1106 tests verts**, `flutter analyze`
> 0 erreur.

### Le principe : le client se débrouille seul

Plus aucune étape ne dépend de la bonne volonté d'un administrateur.

| Avant | Maintenant |
|---|---|
| création → `en_attente_verification` → validation admin | création → **compte actif, essai 7 jours** |
| code de validation transmis à l'agent | **aucun code** |
| prix saisis à la main, souvent oubliés | **barème par défaut** appliqué automatiquement |

Un **trigger `BEFORE INSERT OR UPDATE`** (`abonnement_politique_automatique`)
fait les deux choses, pour **tous** les chemins de création (client seul, agent
terrain, administrateur) :

1. `activation_etape = 'en_attente_verification'` → `'actif'`,
   `statut = 'ESSAI_7J'`, `date_expiration = now() + 7 jours` ;
2. `prix_installation` / `prix_abonnement_mensuel` remplis **seulement s'ils
   sont vides**. Un prix négocié garde donc toujours la priorité.

⚠️ Conséquence assumée : un administrateur qui remet une entreprise en
`en_attente_verification` la réactive immédiatement. C'est le prix de
« plus d'activation par administration » ; une **suspension** doit passer par
`statut` / l'accès, pas par l'étape d'activation.

### Le barème (`bareme_abonnement`)

| Profil | Installation | Mensuel | Plafond installation |
|---|---|---|---|
| `boutique_simple` | 10 000 | 5 000 | — |
| `boutique_complete` | 30 000 | 10 000 | — |
| `distribution` | 50 000 | 20 000 | 100 000 |

- `rpc_bareme_abonnement()` renvoie le barème (lecture seule pour tous).
- Le profil se choisit sur `entreprises.type_activite` : `distribution` →
  distribution, sinon boutique complète.
- La création autonome (`rpc_entreprise_creer_simple`) force le profil
  `boutique_simple` (10 000 / 5 000) — sauf pour une distribution.
- Le patron ou l'agent peut changer le prix à la création : il est négocié,
  donc le barème ne l'écrase plus.

### L'avance intelligente

Un versement partiel a maintenant une **durée lisible** :

> prix d'une journée = **prix du cycle ÷ 30**
> 30 000 le mois → 1 000 / jour → **5 000 = 5 jours**

- `rpc_abonnement_simulation_avance(p_entreprise, p_montant)` répond
  `{prix_jour, jours_obtenus, cycle_complet, reste_a_payer, date_fin_estimee}`.
- Le même calcul existe **en Dart, hors ligne** (`SimulationAvance.calculer`) :
  l'écran de paiement affiche la durée à chaque frappe, sans réseau.
- Le prix du jour se lit sur le prix du **cycle**, jamais sur le reste à payer :
  une avance garde la même valeur en jours même après un premier versement.
- Payer la totalité → `cycle_complet = true`, 30 jours.
- Un montant sous le prix d'une journée → message explicite, jamais un blocage.

### Rattrapage des comptes déjà existants (migration 0093)

Un trigger `BEFORE INSERT OR UPDATE` **n'a aucun effet rétroactif** : après
l'exécution des migrations, les entreprises créées avant `0091` restaient avec
`prix_*` à `NULL` (moteur bloqué, « prix absent ») et celles qui attendaient
une validation administrative restaient bloquées.

`0093` fait **une seule fois** ce que le trigger fait désormais tout seul, et
est **idempotente** :

- prix par défaut appliqués **là où ils manquent seulement** (boutique
  30 000 / 10 000, distribution 50 000 / 20 000) — une négociation n'est
  jamais écrasée ;
- `en_attente_verification` → `actif` + `ESSAI_7J` + 7 jours ;
- `raise notice` indique le nombre de lignes traitées, `raise warning` liste
  les comptes restés sans prix.

Elle ne touche ni les comptes déjà `actif` / `restreint` / `rejete`, ni les
dates d'expiration en cours.

**Contrôle d'installation** : `docs/verification_migrations.sql` (lecture
seule) liste chaque objet attendu de `0083` à `0093` avec `OK` / `MANQUANT`,
puis propose les cinq vérifications de données (barème, comptes sans prix,
dossiers en attente, entreprises de distribution, rattachement des agents).

### L'agent encaisse pour l'entreprise (migration 0092)

Demande du patron : « si c'est un agent qui crée le compte, il peut effectuer
le paiement directement pour l'entreprise ».

`rpc_serdipay_ouvrir` n'acceptait que le **propriétaire** et les quatre rôles
plateforme (`est_plateforme()`) ; un agent de terrain recevait
`ENTREPRISE_REFUSEE`. La migration `0092` ajoute **une seule** possibilité :

```sql
elsif public.agent_de_entreprise(p_entreprise_id) then ...
```

`agent_de_entreprise(p)` = `entreprises.agent_id = auth.uid()` — l'agent ne
peut donc payer que pour les dossiers **qu'il a pris en charge**. Aucun autre
droit n'est élargi : le montant reste calculé et borné en base, l'agent ne
peut ni l'augmenter ni le réduire.

Côté application : bouton **« Encaisser »** sur chaque carte de
`agent_abonnements_page` → `PaiementSerdipayPage(entrepriseId: …)`. L'écran
affiche alors le solde **de la boutique** (et non celui de l'agent) et
l'avance intelligente fonctionne de la même façon.

### Reprise des ventes hors ligne (correctif)

`SyncService._syncVentes` n'écrit plus dans la table `ventes` :

- la vente rejouée passe par **`rpc_vente_valider`** → numéro de vente, contrôle
  du stock, audit et traçabilité identiques à une vente faite en ligne ;
- les produits sont poussés **avant** les ventes (la vente a besoin de leur
  identifiant serveur) ;
- une vente qui ne peut pas partir n'est **plus sautée en silence** : elle
  reste dans la file (`is_synced = 0`), `ventesEnAttente` la compte et
  `dernierMotifVenteBloquee` dit pourquoi.

---

## 13. Phase 12 — 100 % hors ligne (LIVRÉE le 31/10/2026)

> **État au 31/10/2026 : LIVRÉE** — `cache_lecture` (SQLite v13),
> `CacheLecture` (repli automatique), **vente possible sans réseau**,
> conflits de synchronisation visibles et résolubles.
> `test/hors_ligne_complet_test.dart` (10 tests).

### 1. Vendre sans réseau (le vrai manque)

Avant, une vente hors ligne était **refusée** : `rpc_vente_valider` est une
transaction serveur. Désormais, quand le serveur est **injoignable** :

- la vente est écrite dans la base **locale** (`ventes`, `is_synced = 0`)
  et le stock du téléphone est décrémenté, dans la même transaction SQLite ;
- le client reçoit un reçu **`HORS-LIGNE-…`** — il sait que la vente est
  enregistrée sur l'appareil ;
- au retour du réseau, `SyncService` la rejoue par la **RPC officielle**
  (numéro de vente, stock, caisse, audit) : aucune différence avec une vente
  en ligne.

⚠️ Règle de sécurité : un **refus métier** du serveur (stock, droits,
abonnement) lève toujours une erreur — on n'écrit jamais en local par-dessus
un refus. Seule une panne réseau déclenche le repli.

### 2. Lire sans réseau — `CacheLecture`

`lib/services/cache_lecture.dart` : lire → mémoriser → **se replier sur la
dernière valeur connue** si le serveur ne répond pas.

| Écran | Fonction | Effet hors ligne |
|---|---|---|
| Accueil / tableau de bord | `rpc_accueil_stats` | derniers chiffres affichés |
| Dossier d'activation | `rpc_activation_etat` | dossier du dernier passage |
| Abonnement | `rpc_abonnement_installation_etat` | solde connu |
| **Tous les rapports** | funnel `_appelerRpc` | rapport déjà consulté relisible |
| Liste des entreprises | REST (5 tables) | liste locale au démarrage |

Trois garanties :
1. **Aucune écriture** ne passe par le cache ;
2. une réponse du serveur **n'est jamais** remplacée par du cache
   (`PostgrestException` → l'erreur remonte : un refus de droit reste un
   refus) ;
3. la clé est **cloisonnée** (utilisateur + fonction + arguments triés) :
   deux boutiques sur le même téléphone ne voient pas les chiffres de l'autre.

### 3. Conflits de synchronisation

Une vente rejouée qui échoue :

- tentatives **1 à 4** → elle reste dans la file (le stock serveur peut être
  reconstitué par un approvisionnement en attente) ;
- à la **5ᵉ** → `is_synced = -1` : elle devient un **conflit**, avec son
  motif enregistré (`sync_erreur`).

Elle n'est **jamais perdue** et n'est **jamais réessayée sans fin**.
Le bandeau hors ligne affiche « **À vérifier (N)** » → écran
`ventes_a_verifier_page` : date, montant, quantité, motif, tentatives, et
bouton **Réessayer** (remet la vente en file + relance `syncAll`).

### Bilan honnête

| Capacité | État |
|---|---|
| Vendre, encaisser un reçu | ✅ sans réseau |
| Consulter accueil, abonnement, rapports déjà ouverts | ✅ sans réseau |
| Consulter un rapport **jamais ouvert** | ❌ nécessite une première connexion |
| Créer un produit, un client | ✅ local, poussé ensuite |
| Payer l'abonnement | ❌ intrinsèquement en ligne (Mobile Money) |

---

## 14. Garde-fous transverses

- **Une entreprise = un périmètre** : toute nouvelle table porte `owner_id` + RLS.
- **Rôles vérifiés côté serveur** : aucune nouvelle RPC ne fait confiance au client.
- **Historique** : les écarts et les bonus sont des lignes d'historique, jamais des
  suppressions ; une annulation est un `annule_le` horodaté.
- **Idempotence** : toute opération de paiement ou de bonus porte une clé unique.
- **Hors ligne** : les nouvelles opérations passent par les mêmes files locales
  que les ventes (aucune rupture du fonctionnement actuel).
