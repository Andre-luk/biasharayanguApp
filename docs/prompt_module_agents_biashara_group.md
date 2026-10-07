# PROMPT — Module « Agents terrain » dans la plateforme Biashara Group

> **À copier-coller tel quel** comme cahier des charges d'une IA de développement
> (ou d'un développeur) travaillant sur la plateforme **biasharagroup.com**.
> Le module s'intègre aux données réelles de **Biashara Yangu**.

---

## 0. TON RÔLE

Tu es ingénieur logiciel senior. Tu conçois et implémentes un module complet,
production-ready, dans la plateforme d'administration de **Biashara Group**
(agence technologique, Lubumbashi, RDC — back-office : `https://biasharagroup.com/admin`).
Tu travailles dans le dépôt de la plateforme Biashara Group et tu **réutilises sa
stack, ses conventions, son design system et son système d'authentification**.
Tu ne réécris pas ce qui existe. Tu livres du code testé, avec migrations SQL,
écrans, API et tests.

---

## 1. CONTEXTE

- **Biashara Group** édite notamment **Biashara Yangu** (application de gestion et
  de visibilité pour les commerçants de la RDC ; Flutter + Supabase).
- Biashara Yangu envoie sur le terrain des **agents terrain** (rôle
  `AGENT_TERRAIN` dans Biashara Yangu). Un agent : crée/installe la boutique d'un
  commerçant, vérifie son dossier, encaisse et active son abonnement, aide à
  publier la vitrine et les QR codes.
- Aujourd'hui Biashara Group ne **suit pas** ces agents : aucun dossier RH, aucune
  rémunération, aucun suivi d'activité, aucun contrôle.
- **Objectif** : que Biashara Group puisse **recruter, rattacher, suivre,
  rémunérer et contrôler** ses agents, et que **l'agent se connecte au back-office
  Biashara Group** pour consulter ses paiements, ses revenus et son avancement.

---

## 2. PÉRIMÈTRE

### Dans le périmètre
1. Recrutement d'un agent avec un dossier personnel complet.
2. Compte agent rattaché à l'entité **Biashara Group** (membre interne).
3. Lien entre le compte agent Biashara Group et le compte `AGENT_TERRAIN` de
   Biashara Yangu (1-1).
4. Suivi de l'activité de l'agent (dossiers, boutiques, QR codes, encaissements).
5. Rémunération : salaire et/ou commissions, échéances, paiements, historique.
6. État d'avancement de l'agent (objectifs, niveau, score, progression).
7. Contrôle administrateur : journal des actions, alertes, suspension,
   validation des prises en charge.
8. Espace « Mon espace agent » pour l'agent (paiements, revenus, avancement).

### Hors périmètre (à ne PAS faire)
- Ne pas exposer les **ventes, stocks, dépenses ou clients des commerçants** :
  Biashara Group ne suit que **l'activité de son agent**, pas le commerce du
  commerçant (cf. politique de confidentialité de Biashara Yangu).
- Ne pas modifier les écrans de l'application Biashara Yangu côté commerçant.

---

## 3. DONNÉES EXISTANTES CÔTÉ BIASHARA YANGU (contrat à respecter)

Projet Supabase de Biashara Yangu (référence : `pqzcliibocndiyqbyddr.supabase.co`).

**Tables utiles**
- `utilisateurs` : `id` (uuid), `nom`, `email`, `telephone`, `new_role`
  (énumération ; `'AGENT_TERRAIN'` pour un agent), `role` (hérité, texte),
  `entreprise_id`, `parent_id`, `agent_id` (agent référent), `valide`, `created_at`.
- `entreprises` : `id`, `nom`, `statut`, `activation_etape`
  (`en_attente_verification` | `verifie` | `actif` | `restreint` | `rejete`),
  `montant_total_du`, `montant_deja_paye`, `solde_restant` (généré),
  `date_activation`, `date_expiration`, **`agent_id`** (agent qui a pris en charge),
  `ville_id`, `activite_id`, `created_at`.
- `espaces` : boutiques (`id`, `nom`, `type`, `entreprise_id`, `visible_publiquement`).
- `produits`, `conditionnements`, `produits_publications` (articles, formats de
  vente, publications de vitrine).
- `activations_entreprise` : historique du workflow d'activation
  (`entreprise_id`, `etape`, `acteur_id`, `acteur_role`, `montant`,
  `mode_paiement`, `reference_transaction`, `note`, `created_at`).
- `journal_audit` : `action`, `utilisateur_id`, `entreprise_id`, `details` (jsonb),
  `niveau`, `created_at` (append-only, chaîné).

**Fonctions / RPC déjà disponibles** (source de vérité, `security definer`)
- `rpc_agent_fiche(p_agent_id uuid default null)` → jsonb :
  `nom, email, role, nb_utilisateurs, nb_entreprises, nb_boutiques,
  nb_abonnements_actifs, nb_en_attente, nb_produits, nb_conditionnements,
  nb_qr_codes, nb_produits_publies, montant_encaisse, solde_du,
  entreprises[] (id, nom, statut, activation_etape, solde_restant,
  montant_total_du, montant_deja_paye, date_expiration, created_at),
  utilisateurs[] (id, nom, email, telephone, role, created_at),
  journal[] (action, created_at, niveau, details)`.
  **Un agent ne peut lire que sa fiche ; le personnel plateforme lit celle de tout agent.**
- `rpc_agent_utilisateurs_lister(p_agent_id, p_recherche, p_limite, p_decalage)`
- `rpc_agent_abonnements_lister(p_agent_id, p_filtre, p_limite, p_decalage)`
- `rpc_agent_dossiers_libres(p_limite)` → dossiers non attribués.
- `rpc_admin_creer_agent_terrain(p_email, p_password, p_nom, p_prenom, p_note)`
  (réservé Super Admin / gestionnaire des comptes) → crée le compte Auth + le
  profil `AGENT_TERRAIN` et renvoie `{ok, agent_id, email, role, compte_reutilise}`.
- Helpers : `est_agent_terrain()`, `agent_detient_entreprise(uuid)`,
  `mon_entreprise_id()`, `mon_role()`.

**Commissions / revenus**
- « Revenus d'un agent » = **abonnements encaissés sur les entreprises qu'il a
  prises en charge** (`montant_encaisse` de `rpc_agent_fiche`), et non le chiffre
  d'affaires des commerçants.

---

## 4. MODÈLE DE DONNÉES À CRÉER (Biashara Group)

Crée (migrations versionnées, idempotentes) les tables suivantes. Toutes portent
`created_at`, `updated_at`, et sont soumises à RLS.

1. **`bg_agents`** — dossier RH de l'agent
   - `id uuid pk`, `user_id uuid null` (compte Auth Biashara Group),
   - `agent_yangu_id uuid unique null` (**id du compte `AGENT_TERRAIN` Biashara Yangu**),
   - `matricule text unique`, `nom`, `postnom`, `prenom`, `sexe`, `date_naissance`,
   - `etat_civil`, `nationalite`, `piece_type`, `piece_numero`, `piece_expiration`,
   - `telephone`, `telephone_secondaire`, `email`, `adresse`, `ville`, `commune`, `quartier`,
   - `zone_affectation` (texte/table `bg_zones`), `superviseur_id` (self-fk),
   - `date_embauche`, `type_contrat` (`essai|cdd|cdi|prestataire`), `date_fin_contrat`,
   - `salaire_base numeric`, `commission_type` (`par_dossier|par_montant|mixte|aucune`),
     `commission_valeur numeric`, `devise` (`CDF|USD`),
   - `statut` (`candidat|actif|suspendu|sorti`), `photo_url`, `cv_url`, `diplome_url`,
     `contrat_url`, `notes_internes`,
   - `recrute_par uuid`, `valide_par uuid`, `valide_le timestamptz`.
2. **`bg_agent_references`** — références professionnelles
   (`agent_id`, `nom`, `telephone`, `relation`, `note`).
3. **`bg_agent_documents`** — pièces justificatives (type, url, expiration, vérifié par).
4. **`bg_agent_paiements`** — rémunérations versées ou dues
   (`agent_id`, `periode` (mois), `type` (`salaire|commission|prime|avance`),
   `libelle`, `montant`, `devise`, `statut` (`du|paye|annule`),
   `date_echeance`, `date_paiement`, `mode_paiement`, `reference`,
   `justificatif_url`, `enregistre_par`, `valide_par`).
5. **`bg_agent_objectifs`** — objectifs par période
   (`agent_id`, `periode`, `objectif_dossiers`, `objectif_boutiques`,
   `objectif_encaissement`, `poids`).
6. **`bg_agent_journal`** — évènements de contrôle Biashara Group
   (`agent_id`, `action`, `details jsonb`, `auteur_id`, `created_at`) :
   recrutement, validation, changement de statut, versement, avertissement,
   suspension, changement de zone/superviseur.
7. **`bg_zones`** — zones d'affectation (`nom`, `ville`, `responsable_id`).
8. **`bg_agent_sync`** (optionnel) — cache des agrégats Biashara Yangu
   (`agent_id`, `snapshot jsonb`, `synchronise_le`) pour les tableaux de bord.

**Vues / calculs attendus**
- `bg_v_agent_performance` : pour chaque agent actif, les compteurs issus de
  `rpc_agent_fiche` (dossiers, boutiques, QR, encaissements) + les objectifs de la
  période + l'avancement en % + le cumul payé/dû.
- Score d'avancement (0–100) = moyenne pondérée de l'atteinte des objectifs
  (dossiers, boutiques, encaissement). **Documente la formule et rends-la configurable.**

---

## 5. RÔLES & PERMISSIONS (Biashara Group)

- **`ADMIN_BIASHARA`** : tout (recrute, valide, paie, suspend, paramètre le barème).
- **`RH_BIASHARA`** : dossiers agents, contrats, documents, salaires.
- **`SUPERVISEUR`** : voit **ses** agents (ceux dont il est `superviseur_id`) —
  performance, journal, alertes ; propose des validations.
- **`COMPTABLE_BIASHARA`** : paiements, commissions, exports ; ne modifie pas les dossiers.
- **`AGENT`** : accès **lecture seule** à SON dossier, SES paiements, SES revenus,
  SON avancement, SES boutiques/dossiers (aucun accès aux autres agents).

Applique un contrôle **côté serveur** (RLS + vérification dans chaque fonction),
jamais seulement dans l'interface. Un agent ne peut jamais lire les lignes d'un autre.

---

## 6. RECRUTEMENT

Écran **Agents → Recruter** (assistant en 4 étapes) :
1. **Identité** : nom, postnom, prénom, sexe, date de naissance, état civil,
   nationalité, photo.
2. **Contact & affectation** : téléphone, secondaire, e-mail, adresse, ville,
   commune, quartier, zone, superviseur.
3. **Contrat** : type, date d'embauche, date de fin éventuelle, salaire de base,
   devise, type et valeur de commission, période d'essai.
4. **Pièces & références** : type/numéro/expiration de la pièce d'identité,
   diplôme, CV, contrat signé, références professionnelles.

À la validation :
- crée le compte Auth Biashara Group (rôle `AGENT`, invitation par e-mail) ;
- **crée le compte `AGENT_TERRAIN` dans Biashara Yangu** via
  `rpc_admin_creer_agent_terrain` et enregistre `agent_yangu_id` ;
- écrit une entrée `bg_agent_journal` (`action='RECRUTEMENT'`) et, côté Biashara
  Yangu, une entrée `journal_audit` (`action='AGENT_TERRAIN_CREE'`).
- L'e-mail doit être **unique** ; si un compte Biashara Yangu existe déjà avec cet
  e-mail, le réutiliser et l'aligner (le RPC le fait déjà : `compte_reutilise`).

---

## 7. SUIVI D'ACTIVITÉ

Source **unique** : `rpc_agent_fiche(agent_yangu_id)` (+ `rpc_agent_abonnements_lister`
pour le détail des dossiers). Synchronisation :
- à l'ouverture d'une fiche agent (appel direct, mise en cache 5 min) ;
- tâche planifiée journalière qui alimente `bg_agent_sync` et les tableaux de bord.

Affiche : dossiers pris en charge (libres→pris), boutiques créées, QR codes
générés, articles publiés, abonnements actifs, en attente, **encaissements
générés**, solde dû, et le **journal d'actions** (traduit en français lisible).

**Ne jamais** afficher les ventes/stocks/clients des commerçants.

---

## 8. RÉMUNÉRATION

- Barème configurable par agent (`commission_type` / `commission_valeur`).
- **Calcul de commission mensuel** : sur les dossiers **activés dans le mois**
  (source : `activations_entreprise` via la fiche/sync), × la valeur configurée.
- Liste des **paiements** (dus, payés, annulés) avec période, mode, référence et
  justificatif ; génération d'un **reçu PDF** par paiement.
- Cumul par agent : total dû, total payé, **reste à payer** ; export CSV/PDF.
- Vue **« Ma paie »** côté agent : historique, cumuls, prochain versement.

---

## 9. ÉTAT D'AVANCEMENT

- Objectifs par mois/trimestre (dossiers, boutiques, encaissement).
- Barre de progression + **niveau** (`Débutant < Bronze < Argent < Or < Platine`),
  seuils configurables.
- Alerte automatique : agent sans activité depuis N jours, objectif < 50 %,
  dossier en attente de vérification depuis N jours, pièce d'identité expirée.

---

## 10. CONTRÔLE ADMINISTRATEUR

- **Journal complet** de l'agent (Biashara Yangu + Biashara Group) filtrable.
- Actions : valider/suspendre un compte, **désactiver le compte Biashara Yangu**
  (en accord avec le module 20/21 de Biashara Yangu : désactivation ou
  anonymisation, jamais de suppression sauvage), changer zone/superviseur,
  émettre un avertissement, clôturer le contrat.
- Toute action sensible est journalisée (`bg_agent_journal`) et exige un motif.

---

## 11. ÉCRANS À LIVRER

1. Agents — liste (filtres statut/zone/superviseur/recherche) + KPI d'en-tête.
2. Agent — fiche détaillée à onglets : Profil · Documents · Activité · Paiements · Avancement · Journal.
3. Assistant de recrutement (4 étapes, brouillon conservé).
4. Paiements — liste globale (période, statut, agent) + création/validation.
5. Barème & objectifs — configuration (par agent et par défaut).
6. Tableau de bord direction — KPI : agents actifs, dossiers du mois, boutiques,
   encaissements, commissions dues/payées, top agents, alertes.
7. **Mon espace agent** — mes dossiers/boutiques, mes paiements, mes revenus, mon avancement.
8. Exports (CSV/PDF) : agents, paiements, performance.

---

## 12. CONTRAT D'API (à implémenter côté Biashara Yangu)

Crée une **Edge Function** `admin-agents` (Deno) dans le projet Biashara Yangu,
protégée par un **jeton de service Biashara Group** (secret dédié, jamais côté client) :

- `GET /agents/{agent_yangu_id}/fiche` → renvoie exactement le jsonb de `rpc_agent_fiche`.
- `GET /agents` → liste des comptes `AGENT_TERRAIN` (id, nom, email, created_at).
- `POST /agents` → `{email,password,nom,prenom,note}` → `rpc_admin_creer_agent_terrain`.
- `POST /agents/{id}/desactiver` → `{motif}` → désactivation du compte (jamais de purge).
- Toutes les réponses : `{ok:true, ...}` ou `{erreur, message}` ; journalise chaque
  appel dans `journal_audit` (`action='BG_ADMIN_AGENT'`, `utilisateur_id` = agent visé).

**Sécurité d'accès aux données** : la plateforme Biashara Group ne doit **jamais**
recevoir la clé `service_role` dans son client. Elle appelle l'Edge Function avec
son jeton d'agent de service ; la fonction applique le cloisonnement.

---

## 13. SÉCURITÉ & CONFORMITÉ

- RLS sur **toutes** les tables `bg_*` ; un agent ne lit que ses lignes.
- Données personnelles (pièce d'identité, diplôme, CV) : accès restreint RH/Admin,
  URL signées à durée limitée (pas de bucket public), journalisation de chaque
  consultation, mention de conservation et de suppression.
- MFA obligatoire pour `ADMIN_BIASHARA` et `RH_BIASHARA`.
- Piste d'audit inaltérable ; aucune suppression physique des paiements
  (annulation tracée uniquement).
- Rate-limiting + verrouillage après échecs répétés sur le back-office.

---

## 14. CRITÈRES D'ACCEPTATION

1. Je peux recruter un agent en 4 étapes ; un compte Biashara Group **et** un compte
   `AGENT_TERRAIN` Biashara Yangu sont créés et **liés** (`agent_yangu_id`).
2. L'agent se connecte au back-office et ne voit **que** son dossier, ses paiements,
   ses revenus et son avancement — **aucune** donnée d'un autre agent ni d'un commerçant.
3. L'admin voit, pour chaque agent, des compteurs **réels** (dossiers, boutiques,
   QR, encaissements) issus de Biashara Yangu, avec horodatage de synchronisation.
4. Je peux créer un paiement, le marquer payé, générer un reçu ; l'agent le voit ;
   les cumuls dû/payé/reste sont exacts.
5. Un agent sans activité ou sous-performant déclenche une **alerte**.
6. Toute action sensible apparaît dans le journal, avec auteur et motif.
7. Aucun écran n'expose les données de gestion (ventes/stock/clients) d'un commerçant.
8. Tests : migrations rejouables, tests unitaires (calculs de commission, score,
   progression), tests RLS (un agent ne lit pas les lignes d'un autre),
   test d'intégration de l'Edge Function avec un jeton invalide → refus.

---

## 15. LIVRABLES ET ORDRE D'EXÉCUTION

1. Migrations SQL (`bg_zones`, `bg_agents`, `bg_agent_references`,
   `bg_agent_documents`, `bg_agent_paiements`, `bg_agent_objectifs`,
   `bg_agent_journal`, `bg_agent_sync`) + RLS + index + vues.
2. Edge Function `admin-agents` côté Biashara Yangu + secret de service.
3. Services/API côté Biashara Group (couche métier, erreurs typées).
4. Écrans (§11) en respectant le design system existant.
5. Exports, reçus PDF, alertes, tâche planifiée de synchronisation.
6. Tests + documentation (README du module, procédure d'exploitation).

**Contraintes** : français (interface et messages), montants en `CDF` et `USD`
avec devise explicite, fonctionnement correct sur connexion instable (états de
chargement, reprise), responsive (le back-office s'utilise aussi sur tablette).

---

## 16. POINTS DE VIGILANCE

- **Ne pas dupliquer la vérité** : l'activité vient de Biashara Yangu, Biashara
  Group ne fait que l'afficher et la rémunérer.
- **Ne pas casser** Biashara Yangu : ne modifier ni `produits`, ni `ventes`, ni les
  RPC existantes ; seulement *ajouter* l'Edge Function et, si nécessaire, un champ.
- Le lien agent ↔ Biashara Yangu repose sur **`utilisateurs.new_role='AGENT_TERRAIN'`**
  et **`entreprises.agent_id`** : ne jamais les renommer.
- Un agent **peut exister sans entreprise rattachée** : ne pas rendre `agent_id`
  obligatoire, ne pas considérer l'absence d'activité comme une erreur.
