# Biashara Yangu

Application de **gestion de commerce multi-activités** (boutique, hôtel, pharmacie,
restaurant, salle des fêtes, boulangerie, boucherie…) — Flutter + Supabase,
éditée et exploitée par **Biashara Tech** — Lubumbashi, République Démocratique
du Congo. Collaborateur marketing : **La Perle Corp**. Développeur principal :
**Andre Lukengu**.

> **Une activité = des modules = des écrans.** Le patron choisit son type
> d'activité ; l'application affiche uniquement les modules utiles (ventes,
> chambres, commandes de restaurant, lots & péremption…). Une seule
> application pour tous les commerces.

---

## 1. Ce que fait l'application

| Domaine | Fonctions |
|---|---|
| **Ventes** | Panier, scanner (**encaisser directement ou continuer le panier**), pesée à la balance, encaissement (espèces, mobile money, carte, dette), reçus, historique, annulation motivée |
| **Articles & stock** | Catalogue, catégories, conditionnements (farde, carton…), approvisionnements, ajustements, inventaires, seuils d'alerte |
| **Clients & dettes** | Fiches clients, crédits, remboursements, relances WhatsApp/SMS |
| **Caisse & finance** | Encaissements, clôtures de caisse, dépenses, tableau de bord CA/bénéfice |
| **Rapports** | 11+ types (ventes, articles, catégories, vendeurs, top produits, finance, stock, caisse, dépenses, dettes, expirations), exports PDF/Excel signés |
| **Modules métier** | 🏨 Hôtel (chambres, réservations, check-in/out, facture séjour) · 💊 Pharmacie (lots, péremption, blocage de vente expirée) · 🍽️ Restaurant (tables, commandes, écran cuisine, encaissement caisse) · 🎉 Salle des fêtes (salles, calendrier, prestations, avances & soldes) · 🥖 Boulangerie (matières premières, productions, pertes, coût de revient) · 🥩 Boucherie (vente au poids, pas de 0,5 kg, ticket au kg) · 👕 Mode (variantes taille/couleur/marque, recherche par variante) |
| **Distribution terrain** | 🚚 Tournées de livraison : dotation par agent, vente plafonnée à la dotation, clôture avec retours et écarts, rapport par agent (CA, quantités, zone), consignes de récipients chez les clients, bonus tracés · ⚖️ **Pesée rapide** : prix au kilo défini sur l'article, poids lu sur la balance, encaissement immédiat (ou code balance `BAL:<produit>:<grammes>`) · ⚡ **Mode rapide** : nom + prix → vendre · 🏭 **Distribution complète (Module 24)** : collaborateurs dédiés (gérant, production, stock, commercial, comptable), stock d'intrants séparé des produits finis, réceptions à double confirmation, demandes d'intrants, productions avec pertes motivées, dotations commerciales, retours comptés, remises d'argent à trois confirmations, caisse/dépenses et anomalies |
| **Équipe** | Collaborateurs, 8 rôles, permissions fines personnalisables par le Super Admin |
| **Assistant IA** | Chat intégré (quotas par packs), actions contrôlées par les droits |
| **Abonnement** | Workflow d'activation vérifié (comptes → finance), essai 7 j / total 30 j, restrictions sans suppression de données |
| **Notifications** | Alerte à chaque vente + rapport de fin de journée (heure configurable) |
| **Légal** | Politique de confidentialité et Conditions d'utilisation intégrées (droit congolais, juridiction de Lubumbashi) |

Plateformes : **Android, Windows, Linux** et **Web** (Flutter). Les données
sont synchronisées en ligne via **Supabase** ; une base **SQLite locale** sert
de repli hors ligne sur les applications natives. Sur le web, l'application
fonctionne entièrement avec Supabase (la base locale SQLite n'est pas
disponible dans un navigateur — les shims `lib/utils/*_stub.dart` neutralisent
ces fonctions).

---

## 2. Architecture

```
lib/
  main.dart            → démarrage : Supabase, notifications, surveillance modules
  config/app_router.dart → toutes les routes (go_router) + middleware de droits
  models/              → entités pures (Article, Chambre, Réservation,
                          Commande, Permission, Rapport…) — testables sans réseau
  services/            → accès Supabase (RPC + tables), session, notifications
  pages/               → écrans (boutique, hôtel, restaurant, admin, réglages)
  ui/accueil/          → registre des cartes du tableau de bord (modules)
  ui/                  → mise en page adaptative (contenu centré sur ordinateur)
  widgets/             → composants partagés (puces de statut, dialogues…)
  db_helper.dart       → base SQLite locale (repli hors ligne)
supabase/migrations/   → 177 migrations SQL idempotentes (0000 → 0177, puis 0179)
                        (aucune 0178 : le correctif 178 est purement client)
test/                  → tests purs (modèles, permissions, rapports, modules,
                          devises, factures d'abonnement, quotas IA, codes de
                          validation agent, marketplace, administration,
                          péremption, fiche entreprise, distribution terrain,
                          identifiants UUID, version)
docs/                  → documentation interne (roadmap, publication, modules)
                          · `manuel_modules_et_utilisations.html` pourra être
                            régénéré en PDF : tous les modules, mode d'emploi
tools/                 → utilitaires (signature Android `setup_signature.sh`,
                          déploiement de l'assistant IA `deploy_agent_ia.sh`)
```

**Règle d'or du socle multi-activités :** profil de modules inconnu, absent ou
vide → l'application retombe sur le comportement complet (aucune régression) ;
la personnalisation d'un profil se fait depuis l'admin, côté serveur.

---

## 3. Configuration technique

### 3.1 Supabase (obligatoire)

L'URL et la clé publique `anon` sont déclarées dans `lib/main.dart`
(`Supabase.initialize(...)`). Le projet de référence :
`https://pqzcliibocndiyqbyddr.supabase.co`.

**Ordre d'exécution des migrations** — Supabase → **SQL Editor** → coller →
*Run*, dans l'ordre des fichiers de `supabase/migrations/` :

```
0000 → 0019   socle (entreprises, référentiels, permissions, modules 1→15)
0020 → 0026   correctifs (énums, rapports, ventes, caisse…)
0027          Module 16 phase A — types d'activités & modules
0028          Module 16 phase B — profils affinés hôtel/restaurant
0029          Module 16 phase C1 — pharmacie (lots & péremption)
0030          Module 16 phase C2 — hôtel (chambres, réservations, réception)
0031          Module 16 phase C3 — restaurant (tables, commandes, cuisine)
0032          Module 16 phase D — rapports par activité (hôtel, restaurant)
0033          Module 16 phase C4 — salle des fêtes (salles, événements)
0034          Module 16 phase C5 — boulangerie (matières, productions)
0035          Module 16 phase C6 — boucherie (articles vendus au poids)
0036          Module 16 phase C8 — variantes (taille, couleur, marque)
0037          Module 16 phase E — packs par modules (groupes tarifaires)
0038          Module 17 — verrouillage des comptes non activés + catégorie
              d'activité respectée à la création (p_type, triggers, verrou)
0039          Module 18 — devises de travail (CDF/USD) et taux de conversion
0040          Module 19 — Biashara Marketplace local géolocalisé :
              vitrine publique des boutiques, catalogue public (recherche
              sans compte), comparaison des prix, carte, mesure de
              visibilité, codes d'attribution et publicités (7 tables,
              22 RPC, aucune donnée privée exposée)
0041 → 0072   modules 20 et 21 (administration plateforme, marketplace
0073          correctif 73 — créer une entreprise AVEC son propriétaire
              (`proprietaire_id`, `cree_par`, `cree_le`) + la fiche unique
              (`rpc_admin_entreprise_creer`, `rpc_entreprise_fiche`)
0074          correctif 74 — garde-fou des rôles : `niveau_role()` et le
              déclencheur `garder_role_utilisateur` (auto-promotion et rôle
              glissé dans une inscription refusés)
0075          correctif 75 — `activer_apres_code` : l'émission du code par la
              Finance ouvre le compte (essai de 7 jours)
0076          correctif 76 — péremption (lots) ouverte aux activités génériques
              (boutique, dépôt, autre) ; le créateur d'une entreprise devient
              son agent référent (déclencheur + reprise des données) ;
              `rpc_agent_mes_boutiques()` et fiche ouverte à l'agent référent
0077          correctif 77 — « Article n° 83 introuvable » : le panier envoyait
              l'identifiant LOCAL de SQLite au lieu du numéro de la base ;
              réparation côté base (`rpc_articles_verifier`,
              `rpc_article_restaurer`) pour les téléphones déjà installés
0078          correctif 78 — le marché se remplit tout seul : vitrine visible
              par défaut, vue publique sans coordonnées GPS obligatoires,
              publication automatique de chaque article (déclencheur)
              étendue, devises, quotas IA, codes de validation agent,
              droits des agents, abonnements, péremption réglable)
0079          passerelle de paiement SerdiPay (Orange Money, Airtel, M-Pesa,
              carte) — tables + RPC, Edge Function `serdipay`
0080          Module 23 — DISTRIBUTION TERRAIN, CONSIGNES & BONUS :
              tournées de livraison (dotation par agent), ventes plafonnées
              par la dotation, clôture avec retours et écarts, récipients
              laissés chez les clients (consignes), bonus tracés, zones
              clients, mode rapide (`produits.stock_illimite`) et
              statistiques d'accueil calculées par le serveur
              (`rpc_accueil_stats`) + tables publiées au temps réel
0081          Module 23 bis — MODE SIMPLE & CORRECTIFS :
              `rpc_entreprise_creer_simple` (entreprise + essai de 7 jours
              ACTIF immédiatement, sans double validation), consignes
              limitées à l'agent, contrôle du client (autre entreprise
              refusée), statistiques d'accueil en une seule lecture par
              table + nombre total de ventes, index de performance
0100          Module 24 — DISTRIBUTION : PRODUCTION, STOCK, TERRAIN, CAISSE :
              rôles distribution dédiés (`utilisateurs.role_distribution`),
              stock d'intrants séparé des produits finis, réceptions à double
              confirmation, demandes d'intrants de la production, productions
              avec pertes motivées et réception au stock, demandes de
              dotations des commerciaux, retours comptés, clients privés par
              commercial, ventes + factures PDF, remises d'argent à TROIS
              confirmations (commercial → comptable → gérant), caisse et
              dépenses propres au module, anomalies, journal et tableau de
              bord `dist_tableau_bord`
0101          Module 24 (compléments) : refus motivé d'une réception
              d'intrants (`dist_reception_intrants_refuser`) et journal de
              traçabilité lisible (`dist_journal_lister`)
0102          PAIEMENTS — Mobile Money obligatoirement via SerdiPay :
              garde-fous en base (triggers sur `paiements_abonnements_laperle`
              et `agent_ia_achats`), helper de reconnaissance des libellés et
              vue d'audit `v_serdipay_audit` pour le Super Admin
0103          Module 24 — compléments 2 : grille multi-tarifs des bidons
              (`dist_tarifs`), bonus/produits endommagés par commercial
              (`dist_bonus_dommages`, validation gérant) et coût de revient /
              marges (`dist_cout_revient`, `dist_rentabilite`)
0104          Module 24 — la grille tarifaire s'applique en caisse :
              `dist_ventes.type_operation` + `p_type_operation` dans
              `dist_vente_enregistrer` (prix figé sur la ligne de vente)
0105          Module 24 — hors-ligne : idempotence des opérations
              (`reference_locale` unique sur `dist_ventes` et
              `dist_bonus_dommages`, rejeu sans doublon)
0106          ABONNEMENT — montant dû renseigné dès la création « setup »
              (prix de la grille sur les essais de 7 jours) + réparation des
              entreprises en essai créées avec 0 CDF
0107          ABONNEMENT — toute entreprise reçoit une GRILLE TARIFAIRE
              (trigger `entreprise_grille_par_defaut` + réparation des comptes
              sans grille, montant dû des essais recalculé)
0108 → 0173   modules 25 → 36 (abonnements, SerdiPay, marketplace, multi-
              entreprises et isolation `owner_id` = espace, pressing,
              pharmacie par lots, profils métier) — détail dans `docs/`
0174          CORRECTIF 174 — CRÉATION UNIFIÉE & SUPPRESSIONS SÛRES :
              Un seul cœur de création (Setup = Super Admin), identifiants
              UUID tolérants (`uuid_ou_null` → plus de « invalid input syntax
              for type uuid »), profil de modules complet par activité (25
              codes alignés sur le Dart), métier réel exposé par
              `rpc_entreprises_metiers`, journal d'audit SANS clé étrangère
              (instantanés `entreprise_nom` / `utilisateur_email`), suppression
              d'entreprise et d'utilisateur en cascade avec sauvegarde JSON
              préalable (`sauvegardes_suppressions`) et journal en INSERT seul.
0175          CORRECTIF 175 — ÉQUIPE, QR CODES, REVENUS SERDIPAY, ANALYSE :
              équipe du pressing rattachée au PATRON (`mon_patron()` → plus de
              violation `utilisateurs_parent_id_fkey`) + retrait d'un
              collaborateur ; `rpc_scanner_resoudre` (les QR `PROD:<id>` et
              `COND:<uuid>` générés par la plateforme sont reconnus) ; prix du
              QR défini par la plateforme (150 CDF par défaut, modifiable) et
              revenus QR comptés à l'émission (`qr_codes_emis`) ;
              `rpc_admin_tableau_bord` — les revenus affichés sont UNIQUEMENT
              les paiements confirmés par SerdiPay ; `rpc_rapport_entreprise_
              analyse` — rapport semaine / mois téléchargeable (meilleur
              produit, meilleur jour, meilleur moment, conseils, projection
              +10 %) ; champ de saisie maintenu visible au-dessus du clavier
              dans TOUS les formulaires (`ClavierChampVisible`).
0176          CORRECTIF 176 — SUPPRESSION D'UN COLLABORATEUR :
              l'écran « Mon Équipe » appelait `delete_collaborateur`, fonction
              ABSENTE de toutes les migrations (le bouton échouait toujours).
              → `rpc_collaborateur_supprimer(id, 'SUPPRIMER')` (propriétaire
              uniquement, jamais soi-même ni le propriétaire, profil + compte
              Auth, journal d'audit) + alias `delete_collaborateur` pour les
              applications déjà installées. Aucune donnée métier effacée.
0177          CORRECTIF 177 — ÉQUIPE, RÔLES MÉTIER, ANALYSE, QR PAR BOUTIQUE :
              liste/modification/suppression d'un collaborateur filtrées sur
              `mon_patron()` (et non sur l'espace) → équipe enfin visible pour
              un patron multi-entreprises ; l'espace de travail d'un
              collaborateur est celui de SON entreprise (pressing en priorité)
              et un compte de pressing reçoit automatiquement son métier
              (`role_pressing`) ; réparation des comptes mal rattachés ;
              analyse des ventes réécrite (`analyse_lignes_ventes`) — lit les
              ventes d'articles ET les prestations de pressing, classe TOUS
              les produits par meilleure vente, sans table temporaire ; casts
              REAL→NUMERIC pour éviter le 42804 ; permissions pressing par
              métier (aucune vente, scanner, pesée, caisse boutique), routes
              directes protégées, trigger qui bloque aussi l'insertion de
              ventes boutique dans un pressing ; erreurs traduites vers le
              dépôt pressing ; tests de permissions par métier et des routes.
              QR codes : `codes_existants` (1 par article + 1 par emballage)
              et répartition par boutique dans le tableau de bord.
0179          CORRECTIF 179 — FINANCES, RAPPORT PAR COLLABORATEUR, COHÉRENCE :
              fin du « operator does not exist: uuid = text » (les anciennes
              colonnes d'identifiants restées en texte sont converties, et les
              fonctions Finance comparent désormais les identifiants en texte —
              elles fonctionnent quel que soit l'état de la base) ; nouveau
              `rpc_rapport_vendeurs` : rapport par collaborateur avec le stock
              restant AVANT et APRÈS chaque vente et le vendeur de l'unité
              précédente (« il restait 4 beignets, c'est A qui avait vendu ») ;
              UN SEUL périmètre et UNE SEULE journée (minuit heure de
              Lubumbashi, date fournie par le serveur) pour le tableau de bord,
              le rapport du patron et les rapports vendeurs → les chiffres
              correspondent, quel que soit le téléphone.
0180          CORRECTIF 180 — COHÉRENCE DES MÉTIERS PAR ESPACE :
              « une boutique qui passe à la place de pressing ». Toutes les
              décisions (écrans, métiers, blocages) reposent désormais sur le
              TYPE DE L'ESPACE DE TRAVAIL et non sur l'entreprise :
              `espace_type`, `espace_est_pressing`, `mon_espace_actif`,
              `contexte_pressing`. La garde de vente ne bloque plus que
              l'espace qui vend (une boutique du même groupe vend normalement) ;
              un trigger efface `role_pressing` hors d'un espace pressing et
              `pressing_role()` répond « aucun » ; `pressing_exige()` refuse
              l'action (PRESSING_INACTIF) hors pressing ; création/modification
              de collaborateur : l'ESPACE choisi décide du métier (plus
              d'affectation « au pressing par défaut ») ; réparation des espaces
              retypés par la 0153. Côté application : routes `/main/pressing/*`
              fermées hors pressing et bascule d'espace qui recharge modules et
              métier.
0181          CORRECTIF 181 — DEUX ENTREPRISES D'UN MÊME PATRON NE PARTAGENT
              PLUS LEURS VENTES : `perimetre_entreprise()` n'ajoute plus
              l'UUID du patron quand l'entreprise a des espaces (cet UUID est
              aussi l'identifiant du TOUT PREMIER espace créé à l'inscription,
              donc il faisait entrer le premier espace dans le périmètre des
              DEUX entreprises) ; `entreprise_courante()` suit l'ESPACE DE
              TRAVAIL ; réparation des `espace_actif_id` incohérents ;
              contrôle d'intersection des périmètres (doit être vide).
              + ÉQUIPE BORNÉE À L'ESPACE ACTIF (RLS `utilisateurs` et RPC
              collaborateurs), paiements d'abonnement lisibles par la seule
              plateforme, policies restrictives sur la finance.
```

**Correctif 178** — isolation des sessions (client uniquement, aucune
migration) : un seul service de déconnexion (`ReinitialisationSession`) vide
rôle, permissions, espace actif, modules, abonnement, panier, scans et caches ;
le rôle est lu **d'abord au serveur** au démarrage, à la connexion et dans la
navigation (un super admin ne tombe plus dans `/main`) ; le routeur refuse un
espace non autorisé ; le cache d'espace est **cloisonné par compte** ; les
cartes métier de l'accueil attendent le profil de modules. Détails :
`docs/correctif_178_isolation_session.md`.

**Correctif 179** — finances et rapport par collaborateur : plus d'erreur
« uuid = text », rapport par vendeur avec le stock avant/après chaque vente,
et **un seul périmètre / une seule journée pour tous les chiffres** (tableau
de bord, rapport du patron, rapports vendeurs). Détails :
`docs/correctif_179_finances_et_rapport_vendeurs.md`.

⚠️ La migration **0020** doit être exécutée **seule** (PostgreSQL n'autorise
pas d'utiliser une nouvelle valeur d'énum dans la même transaction).
Toutes les autres sont **idempotentes** (relançables sans effet de bord) et
se terminent par des requêtes de vérification.

### 3.2 Réglages en base (`app_settings`)

| Clé | Contenu | Effet |
|---|---|---|
| `ventes` | `{"bloquer_produits_expires": true}` | Bloque la vente d'un article dont la date de péremption est dépassée (pharmacie). Passer à `false` pour l'autoriser |
| `permissions_roles` | `{"roles": {"VENDEUR": {"ventes": ["voir","creer"]}}}` | Personnalisation des permissions par rôle (écran Super Admin → Permissions) ; remplace la matrice par défaut |
| `devises` | `{"taux_usd_cdf": 2800, "devise_defaut": "CDF"}` | Taux de change par défaut de la plateforme (Module 18) et devise proposée aux nouvelles entreprises ; réglable par le Super Admin (écran **Devises & taux**) |

**Alerte de péremption (correctif 72)** — le délai d'alerte n'est pas dans
`app_settings` : il est **propre à chaque entreprise**, dans la colonne
`entreprises.alerte_peremption_jours` (`integer not null default 30`, contrainte
`entreprises_alerte_peremption_plage` = **1..365**), réglable depuis
**Paramètres → Alerte de péremption** (`rpc_peremption_config` /
`rpc_peremption_definir_delai`, réservé au propriétaire). Ce délai **unique**
pilote le badge de la carte article, le compteur de la carte *Expirations*, le
compteur de notifications, les filtres et le tri de l'écran *Expirations*, et le
bandeau du formulaire article. Le seuil est **inclusif** (à exactement N jours,
l'alerte est déjà là). Le **blocage de vente**, lui, reste fondé sur
`produits.date_expiration < current_date` (réglage `ventes.bloquer_produits_expires`)
et **ignore** le délai d'alerte. Base non migrée : repli propre sur 30 jours.

**Devises (Module 18)** — chaque entreprise travaille en **CDF** (défaut) ou
**USD** : tous ses montants (prix, ventes, dépenses, caisse, rapports, reçus,
paiements) s'affichent dans son unité (`15 000 CDF` / `12,50 $`). Le patron
choisit sa devise et, s'il le souhaite, son propre taux de change dans
**Paramètres → Devise & conversion** (l'écran comprend un simulateur
« 1 USD = X CDF »). La devise est **propre à chaque espace** du compte
(`espaces.devise`), avec héritage de la devise du compte
(`entreprises.devise`) puis de celle de la plateforme. ⚠️ Changer de devise
change l'UNITÉ d'affichage, **pas** les montants déjà enregistrés.

**Packs par modules (Module 16 E)** — un groupe tarifaire peut limiter les
modules : `groupes_tarifaires.modules` (`[]` = aucun filtre). Les modules
effectifs d'une entreprise = **profil de l'activité ∩ modules du pack**
(écran admin → Groupes tarifaires → « Modules du pack »).

**Verrou des comptes (Module 17)** — un compte n'est OPÉRATIONNEL qu'après
la vérification du gestionnaire des comptes ET la validation du paiement par
la finance. Avant : consultation seule, cadenas sur les écrans commerciaux
(« Nouvelle vente », « Scanner », « Ajouter produit », « Collaborateurs »…),
et **refus côté serveur** (triggers + RPC) même par lien direct. Abonnement
échu ou compte restreint : même verrouillage, levé automatiquement dès la
validation du paiement (module 14). Vérifier l'état d'un compte :
`select nom, statut, activation_etape, public.abonnement_etat(id) from
public.entreprises;` (`OK` / `ACTIVATION` / `LECTURE_SEULE` / `BLOQUE`).

**Écrans pilotés par l'activité (v2.1.1 → v2.1.2)** — **toutes** les entrées du
monde entreprise suivent les modules de l'activité
(`ReglesActivite`, `lib/models/module_activite.dart`) :

| Entrée | Module(s) requis |
|---|---|
| Nouvelle Vente, Scanner, Suivi commercial, rapports de ventes | `ventes` |
| Ajouter un produit, Catégories, Importer des articles | `produits` (⚠️ **les étiquettes `qr` ne suffisent pas**) |
| Onglet Stock, rapports de stock | `stock` ou `produits` |
| Onglet Rapports | `rapports` |
| Assistant IA, Quotas IA | `assistant_ia` |
| Caisse, dettes, rapports de caisse | `caisse` |
| Dépenses, Finance, rapports de dépenses | `finance` |
| Clients | `clients` |
| Collaborateurs | `employes` |
| Cartes du menu « Gestion commerciale » | chacune son module |

Une activité sans vente au comptoir (hôtel, salon de coiffure) reçoit un
raccourci **Caisse** à la place. Règle d'or inchangée : **masquage uniquement**
(fail-open si le profil n'est pas chargé) — les permissions (module 4) restent
seules décisionnaires, et les écrans restent joignables par lien direct.

**Affichage ordinateur (v2.1.1)** — `lib/ui/mise_en_page_adaptative.dart`
centre le contenu de l'accueil et le borne à 980 px, passe la grille de
statistiques à **3 colonnes** au-delà de 760 px de contenu, et la fenêtre
native (`linux/runner/my_application.cc`) s'ouvre à 1 200 × 800 **bornée à
l'écran** (94 % × 92 %, minimum 900 × 600) : plus de barre de navigation sous
la dalle sur un portable 1 366 × 768.

### 3.3 Réglages dans l'application

| Écran | Réglages |
|---|---|
| **Paramètres** | Infos boutique, notifications (ventes on/off, rapport on/off, heure du rapport), accessibilité (taille du texte), guide, documents légaux |
| **Admin → Types d'activités** | Modules de chaque activité (l'activité détermine les écrans), activation/désactivation, création de nouveaux types |
| **Admin → Permissions** | Matrice rôle × page × action (Super Admin), réinitialisation aux défauts |
| **Admin → Utilisateurs / Entreprises** | Comptes, rattachements, packs multi-entreprises, abonnements |
| **Stock** | Seuil d'alerte par article, inventaires, ajustements |
| **Collaborateurs** | Rôles (VENDEUR, MAGASINIER, COMPTABLE…) |

### 3.4 Secrets de compilation (GitHub Actions)

Pour des APK **signés** (sinon repli clé debug) — Settings → Secrets →
Actions de `Andre-luk/biasharayanguApp` :

| Secret | Valeur |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | keystore `.jks` encodé : `base64 -w0 upload-keystore.jks` |
| `ANDROID_STORE_PASSWORD` / `ANDROID_KEY_PASSWORD` / `ANDROID_KEY_ALIAS` | mots de passe + alias |

L'assistant `tools/setup_signature.sh` configure tout (création du keystore
si oublié, envoi des secrets, re-tag). Détails : `docs/publication_app.md`.

---

## 4. Développement

```bash
flutter pub get          # dépendances
dart analyze lib test    # analyse statique (doit rester à 0 ERREUR)
flutter test             # 977 tests — doit rester 100 % vert
```

> ⛔ **NE JAMAIS lancer `flutter build` localement sur la machine de
> développement** (le build Gradle/CMake complet fige la machine IdeaPad).
> **Tous les builds se font par la CI GitHub.**

### CI/CD (GitHub Actions)

| Workflow | Déclencheur | Rôle |
|---|---|---|
| `.github/workflows/build-apk.yml` | push sur `main` | APK de test (vérification continue) |
| `.github/workflows/build-release.yml` | tag `v*` | Analyse & tests → **APK signé + Linux + Windows (zip + installer)** → création de la release GitHub avec les 4 fichiers |
| `.github/workflows/build-web.yml` | push sur `main`, tag `v*`, manuel | Analyse & tests → **site web (Flutter Web)** → archive `biashara-yangu-web.zip` (artéfact 30 j + release) |

```bash
git tag v1.7.0 && git push origin v1.7.0   # déclenche la release complète
```

### Versions actuelles

- Flutter **3.47.4** / Dart **3.13.3**, app **3.3.3+40**
- Dépendances clés : `supabase_flutter`, `go_router`, `flutter_local_notifications ^22.3.1`,
  `flutter_map` + `latlong2` (carte OpenStreetMap, **aucune clé d'API**),
  `geolocator` (position du visiteur, avec consentement), `http` (recherche
  d'adresse Nominatim)
  (avec *core library desugaring* Android), `sqlite3` + `sqflite_common_ffi`
  (SQLite embarquée), `pdf`/`printing` (exports), `mobile_scanner` (scanner)
- Web : `flutter build web --release` validé par la CI ; exports de fichiers et
  impressions disponibles, base SQLite locale réservée aux apps natives
- Site web en ligne : **https://biashara-yangu-app.netlify.app** (Netlify,
  déploiement par `netlify.toml` + script `deployer-site-web.sh` du dossier de
  diffusion ; GitHub Pages est indisponible pour un dépôt privé en offre gratuite)

---

## 5. Publication sur les stores

1. La release GitHub fournit `biashara-yangu.apk` **signé** ;
2. La fiche store (Uptodown / APKPure) référence cet APK ;
3. Les notes de mise à jour sont préparées dans `docs/mise_a_jour_vX.Y.Z.md`
   (copier-coller prêt pour la fiche) ;
4. Procédure complète : `docs/publication_app.md`.

---

## 6. Dépannage express

| Symptôme | Cause probable | Solution |
|---|---|---|
| `MSVCP140.dll introuvable` (Windows) | Visual C++ absent | Utiliser le `setup.exe` récent (DLL embarquées) ou installer VC++ Redistributable |
| `Failed to load libsqlite3.so` (Linux) | Ubuntu sans `libsqlite3-dev` | Le bundle embarque `lib/libsqlite3.so` ; sinon `sudo apt install libsqlite3-dev` ou `LD_LIBRARY_PATH=$PWD/lib ./biashara_yangu` |
| Crash Linux ~10 s après lancement | Pilote GPU/Impeller sur certaines machines | Lancer sur une autre machine ou tester `--no-enable-impeller` (voir `docs/publication_app.md §9`) |
| « Fonction non déployée » dans un écran | Migration SQL non exécutée | Exécuter les migrations manquantes (SQL Editor), dans l'ordre |
| Le rapport/la vente échoue après mise à jour | Migration exécutée partiellement | Relancer la migration concernée (idempotente) |

---

## 7. Documents internes

- `docs/roadmap_multi_activites.md` — plan complet des phases A → E
- `docs/publication_app.md` — keystore, releases, dépannage, stores
- `docs/deployer_function_ia.md` — publier l'Edge Function `agent-ia`
  (script `tools/deploy_agent_ia.sh` ou Dashboard ; secret `DEEPSEEK_API_KEY`)
- `docs/mise_a_jour_v1.x.x.md` — notes de mise à jour pour les fiches store
- `docs/module12_analyse_actions.md`, `module13_agent_ia.md`, `module14_activation.md`,
  `module15_multi_entreprises.md`, `module17_verrouillage_comptes.md`,
  `module18_devises.md`, `module19_marketplace.md` — documentation par module

### 7.1 Documents officiels (PDF)

Générés depuis l'état réel du code (pipeline HTML → PDF, script
`docs/_build/build_pdf.sh`), rangés par public :

| Dossier | Document | Public |
|---|---|---|
| `docs/officiel/` | Présentation officielle de la plateforme | Partenaires, prospects |
| `docs/politique/` | Politique de la plateforme | Utilisateurs, juridique |
| `docs/utilisateur/` | Guide officiel d'utilisation | Commerçants et équipes |
| `docs/commercial/` | Dossier commercial | Commerçants, entreprises |
| `docs/marketing/` | Document marketing | Communication, terrain |
| `docs/technique/` | Documentation technique | Équipe de développement |
| `docs/audit/` | Rapport final d'audit et de mise à niveau | Direction, qualité |
| `docs/depliants/` | Dépliant commercial A4 (3 volets, recto-verso) | Terrain, affichage |

Régénération : `./docs/_build/build_pdf.sh` (ou un seul dossier en argument).
Les documents réutilisent les captures réelles de l'application.

---

## 8. Support & éditeur

**La Perle — Lubumbashi, République Démocratique du Congo**
Email : **support@biasharayangu.cd** (lundi → samedi)

Documents légaux intégrés : *Politique & confidentialité* et *Conditions
d'utilisation* (droit congolais — tribunaux de Lubumbashi), accessibles dans
Paramètres → Politique & conditions / Conditions d'utilisation.

