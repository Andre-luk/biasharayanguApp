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

## 10. Garde-fous transverses

- **Une entreprise = un périmètre** : toute nouvelle table porte `owner_id` + RLS.
- **Rôles vérifiés côté serveur** : aucune nouvelle RPC ne fait confiance au client.
- **Historique** : les écarts et les bonus sont des lignes d'historique, jamais des
  suppressions ; une annulation est un `annule_le` horodaté.
- **Idempotence** : toute opération de paiement ou de bonus porte une clé unique.
- **Hors ligne** : les nouvelles opérations passent par les mêmes files locales
  que les ventes (aucune rupture du fonctionnement actuel).
