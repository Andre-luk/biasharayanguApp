# Prompt final — Agent IA de Biashara Group

**Mode d'emploi** : le bloc ci-dessous se copie **en entier** dans l'agent IA du
projet Biashara Group (celui qui code le back-office `biasharagroup.com/admin`).
Il est autonome : il contient le contexte, le contrat d'API réel, les écrans à
produire et les critères d'acceptation.

> 🔐 **Ne collez jamais la valeur de `BG_ADMIN_TOKEN` dans le prompt.** Dites à
> l'agent de la lire depuis une variable d'environnement serveur
> (`BG_ADMIN_TOKEN`), jamais dans le code frontal.

---

````text
# MISSION — Module « Agents terrain » dans le back-office de BIASHARA GROUP

Tu es l'ingénieur en charge d'intégrer, dans la plateforme d'administration de
BIASHARA GROUP (biasharagroup.com/admin), le suivi de nos AGENTS TERRAIN
recrutés dans l'application « Biashara Yangu ».

Livrables attendus : écrans + services + assistant IA. Code complet, typé,
gestion des erreurs, prêt à déployer.

═══════════════════════════════════════════════════════════════════════════
1. CONTEXTE MÉTIER (à comprendre avant de coder)
═══════════════════════════════════════════════════════════════════════════

BIASHARA GROUP édite l'application mobile/desktop « BIASHARA YANGU », un outil
de gestion destiné aux commerçants (boutiques, pharmacies, hôtels, dépôts…).

Le réseau commercial repose sur des AGENTS TERRAIN. Sur le terrain, un agent :

  • recrute et fait activer des commerçants (création du compte + de l'entreprise) ;
  • crée les BOUTIQUES (points de vente) de ces commerçants ;
  • enregistre la VITRINE de la boutique et la publie (catalogue visible en ligne) ;
  • génère les QR CODES des produits de la boutique ;
  • crée les ABONNEMENTS et suit les paiements (encaissements, soldes dus) ;
  • gère uniquement les utilisateurs qu'il a lui-même créés.

BIASHARA GROUP doit désormais suivre cette activité depuis SON back-office :
recrutement, avancement, production (boutiques, QR codes), encaissements,
journal complet, et pouvoir désactiver un agent.

⚠️ PÉRIMÈTRE DE DONNÉES — RÈGLE ABSOLUE
Notre API n'expose QUE L'ACTIVITÉ DE L'AGENT. Nous n'avons AUCUN accès :
  ✗ aux ventes des commerçants
  ✗ à leur stock
  ✗ à leurs dépenses
  ✗ à leur fichier clients
Ne construis donc aucun écran qui laisserait croire le contraire, et ne
demande jamais ces données à l'API : elles n'existent pas dans le contrat.

═══════════════════════════════════════════════════════════════════════════
2. API DISPONIBLE (DÉJÀ DÉPLOYÉE ET TESTÉE — NE PAS LA MODIFIER)
═══════════════════════════════════════════════════════════════════════════

URL de base :
  https://pqzcliibocndiyqbyddr.functions.supabase.co/admin-agents

Authentification — un SEUL en-tête, obligatoire sur CHAQUE appel :
  x-bg-token: <BG_ADMIN_TOKEN>

  • `BG_ADMIN_TOKEN` est un secret de service fourni par BIASHARA YANGOU.
    Stocke-le côté serveur (variable d'environnement) ou dans un stockage
    sécurisé. Ne le mets JAMAIS dans du code frontal, un dépôt Git ou un log.
  • Il n'y a PAS de JWT utilisateur : cette API est machine-à-machine.
  • Ne jamais exposer cette URL directement au navigateur : fais passer les
    appels par TON backend (proxy), qui injecte l'en-tête.

FORMAT DES RÉPONSES
  • Succès : JSON brut (souvent un objet { ok: true, ... }, mais la route
    GET /agents renvoie un TABLEAU JSON à la racine — attention).
  • Erreur  : { "erreur": "CODE", "message": "texte lisible en français" }

───────────────────────────────────────────────────────────────────────────
2.1  GET /ping  — vérifier que le service répond
───────────────────────────────────────────────────────────────────────────
Réponse 200 :
{ "ok": true, "service": "admin-agents" }

Utilisation : écran « Diagnostic » / test de connexion dans les réglages.

───────────────────────────────────────────────────────────────────────────
2.2  GET /agents  — liste des agents + compteurs
───────────────────────────────────────────────────────────────────────────
Réponse 200 (TABLEAU à la racine) :
[
  {
    "agent_id": "83162486-0478-4314-bb8e-9bdee71cc516",
    "nom": "Espoir",
    "email": "agent@espoir.com",
    "telephone": null,
    "valide": 1,
    "created_at": "2026-09-18T09:12:44.312Z",
    "nb_entreprises": 1,
    "nb_boutiques": 1,
    "nb_abonnements_actifs": 0,
    "montant_encaisse": 0
  }
]

Notes :
  • `valide` : 1 = compte actif, 0 = compte désactivé.
  • `montant_encaisse` : total des paiements d'abonnement validés, en CDF.
  • La liste peut être vide : [] (pas d'agent recruté). Gère ce cas.

───────────────────────────────────────────────────────────────────────────
2.3  GET /agents/{agentId}  — fiche complète d'un agent
───────────────────────────────────────────────────────────────────────────
Réponse 200 :
{
  "ok": true,
  "agent_id": "83162486-0478-4314-bb8e-9bdee71cc516",
  "nom": "Espoir",
  "email": "agent@espoir.com",
  "telephone": null,
  "valide": 1,
  "role": "AGENT_TERRAIN",
  "nb_utilisateurs": 1,
  "nb_entreprises": 1,
  "nb_boutiques": 1,
  "nb_abonnements_actifs": 0,
  "nb_en_attente": 0,
  "nb_produits": 3,
  "nb_conditionnements": 2,
  "nb_qr_codes": 5,
  "nb_produits_publies": 0,
  "montant_encaisse": 0,
  "solde_du": 0,
  "entreprises": [
    {
      "entreprise_id": "…",
      "nom": "Boutique Jean-Luc Takalashi",
      "statut": "actif",
      "activation_etape": "actif",
      "solde_restant": 0,
      "montant_total_du": null,
      "montant_deja_paye": null,
      "date_expiration": "2027-09-18",
      "created_at": "2026-09-18T09:20:00.000Z"
    }
  ],
  "utilisateurs": [
    {
      "id": "…",
      "nom": "Jean-Luc Takalashi",
      "email": "…",
      "telephone": "…",
      "role": "COMMERCANT",
      "created_at": "2026-09-18T09:20:00.000Z"
    }
  ],
  "journal": [
    { "action": "AGENT_TERRAIN_RATTACHEMENT", "created_at": "…", "niveau": "MOYEN", "details": { … } }
  ]
}

Définitions des compteurs :
  nb_utilisateurs        comptes créés par l'agent (commerçants, etc.)
  nb_entreprises         entreprises qu'il a rattachées
  nb_boutiques           points de vente créés
  nb_abonnements_actifs  entreprises dont l'activation est terminée (« actif »)
  nb_en_attente          dossiers en cours de vérification / à activer
  nb_produits            produits saisis dans ses boutiques
  nb_conditionnements    formats de vente (sachet, carton, plaquette…) créés
  nb_qr_codes            = nb_produits + nb_conditionnements (QR générables)
  nb_produits_publies    produits réellement publiés dans une vitrine
  montant_encaisse       CDF réellement encaissés sur ses abonnements
  solde_du               CDF restant à payer sur ses entreprises

Le tableau `journal` inclus ici ne contient que les 20 dernières actions.
Pour l'historique complet et paginé, utilise la route 2.4.

───────────────────────────────────────────────────────────────────────────
2.4  GET /agents/{agentId}/journal?limite=100&decalage=0  — journal unifié
───────────────────────────────────────────────────────────────────────────
  • `limite` : 1 à 500 (défaut 100)
  • `decalage` : pour la pagination (défaut 0)

Réponse 200 :
{
  "ok": true,
  "total": 42,
  "journal": [
    {
      "source": "yangu_activation",
      "action": "ACTIVATION_PAIEMENT_FINANCE",
      "niveau": "MOYEN",
      "entreprise_id": "…",
      "entreprise": "Boutique Jean-Luc Takalashi",
      "details": {
        "montant": 15000,
        "mode_paiement": "mobile_money",
        "reference": "…",
        "acteur_role": "AGENT_TERRAIN",
        "note": "…"
      },
      "created_at": "2026-09-18T11:02:00.000Z"
    },
    {
      "source": "yangu_journal",
      "action": "AGENT_TERRAIN_RATTACHEMENT",
      "niveau": "MOYEN",
      "entreprise_id": "…",
      "entreprise": "Boutique Jean-Luc Takalashi",
      "details": { … },
      "created_at": "2026-09-18T09:20:00.000Z"
    }
  ]
}

`source` vaut :
  • "yangu_journal"    → action tracée dans le journal d'audit de Biashara Yangu
  • "yangu_activation" → étape du workflow d'activation (surtout les paiements)

Exemples d'`action` fréquentes :
  CONNEXION, AGENT_TERRAIN_RATTACHEMENT, AGENT_TERRAIN_CREE,
  AGENT_TERRAIN_DESACTIVE, COMPTE_VERIFIE, MONTANT_DEFINI,
  VITRINE_ENREGISTREE, VITRINE_PUBLIEE, ACTIVATION_* …
Prévois un LIBELLÉ LISIBLE + une ICÔNE + une COULEUR par famille d'action
(connexion, vérification, argent, vitrine/publication, recrutement, IA) et un
repli élégant pour les actions inconnues (affiche le code brut).

`total` = nombre d'entrées du journal d'audit : sert à calculer les pages.

───────────────────────────────────────────────────────────────────────────
2.5  POST /agents  — recruter un agent
───────────────────────────────────────────────────────────────────────────
Corps :
{
  "email": "nouvel.agent@exemple.com",
  "password": "motdepasse8+",
  "nom": "Kabila",
  "prenom": "Jeanne",
  "note": "Recrutée le 07/10 — zone Nord-Kivu"
}

Contraintes :
  • `email` obligatoire et valide ;
  • `password` : 8 caractères minimum ;
  • `nom`, `prenom` : facultatif (valeurs de repli sinon) ;
  • `note` : facultatif, texte libre (référence de recrutement).

Réponse 200 :
{
  "ok": true,
  "agent_id": "…uuid…",
  "email": "nouvel.agent@exemple.com",
  "role": "AGENT_TERRAIN",
  "compte_reutilise": false
}

⚠️ `compte_reutilise: true` signifie qu'un compte existait déjà avec cet e-mail :
il a été réaligné en AGENT_TERRAIN (aucune donnée perdue). Dans ce cas, affiche
un avertissement à l'administrateur au lieu d'un simple succès.

C'est BIASHARA YANGU qui crée le compte d'authentification. L'agent pourra se
connecter à l'application Biashara Yangu avec cet e-mail / ce mot de passe.

───────────────────────────────────────────────────────────────────────────
2.6  POST /agents/{agentId}/desactiver  — désactiver (jamais supprimer)
───────────────────────────────────────────────────────────────────────────
Corps : { "motif": "Fraude constatée le 07/10/2026" }   (3 caractères minimum)

Réponse 200 :
{ "ok": true, "agent_id": "…", "valide": 0, "motif": "Fraude constatée…" }

Aucune donnée n'est supprimée : le compte passe simplement à `valide = 0` et
l'action est inscrite au journal. Exige TOUJOURS une confirmation explicite
(dialogue + saisie du motif) avant l'appel.

───────────────────────────────────────────────────────────────────────────
2.7  ASSISTANT IA (DeepSeek) — analyse de l'activité des agents
───────────────────────────────────────────────────────────────────────────
BIASHARA YANGOU fournit un assistant IA côté serveur. Tu n'as AUCUNE clé IA à
gérer : appelle simplement nos routes.

• GET /ia  — état de l'assistant (à appeler une fois au démarrage)
  Réponse 200 :
  {
    "ok": true,
    "assistant": "deepseek",
    "modele": "deepseek-chat",
    "disponible": true,
    "usage": "POST /admin-agents/ia { \"question\": \"...\", \"agentId\": \"<uuid>|null\" }"
  }
  Si `disponible` vaut false, masque le bouton IA et affiche « Assistant IA
  indisponible » (n'invente pas de réponse localement).

• POST /ia  — poser une question
  Corps SANS agentId (question sur tout le portefeuille) :
  { "question": "Classe mes agents par nombre de boutiques créées." }

  Corps AVEC agentId (question sur un agent précis) :
  { "question": "Cet agent est-il en retard ? Que doit-il faire ?",
    "agentId": "83162486-0478-4314-bb8e-9bdee71cc516" }

  Contraintes : `question` = 3 à 1000 caractères ; `agentId` = UUID ou null
  (null/absent = portefeuille entier).

  Réponse 200 :
  {
    "ok": true,
    "agent_id": "83162486-0478-4314-bb8e-9bdee71cc516",
    "reponse": "L'agent a créé 1 boutique pour 1 entreprise…",
    "jetons": 812
  }

  L'assistant répond en FRANÇAIS, uniquement d'après les données de l'agent.
  Il refuse les questions sur les ventes / le stock / les dépenses / les clients
  des commerçants : c'est normal et voulu, affiche sa réponse telle quelle.
  `jetons` = consommation (utile pour un compteur interne/statistiques).

  L'appel peut prendre 5 à 20 secondes : affiche un indicateur de chargement,
  désactive le bouton pendant l'appel, et prévois un délai d'attente client
  d'au moins 60 secondes pour éviter les coupures réseau.

───────────────────────────────────────────────────────────────────────────
2.8  CODES D'ERREUR — à traiter tous explicitement
───────────────────────────────────────────────────────────────────────────
HTTP 400 : EMAIL_INVALIDE · MOT_DE_PASSE_TROP_COURT · MOTIF_REQUIS ·
           CORPS_INVALIDE · AGENT_ID_INVALIDE · QUESTION_REQUISE ·
           QUESTION_TROP_LONGUE · UTILISATEUR_INCONNU · ROLE_INVALIDE
           → affiche `message` à l'utilisateur, tel quel.

HTTP 401 : JETON_INVALIDE
           → problème de configuration serveur (BG_ADMIN_TOKEN absent ou faux).
             Affiche : « Service Biashara Group indisponible : jeton de service
             invalide. » et journalise côté serveur. NE PAS réessayer en boucle.

HTTP 403 : ACCES_REFUSE / DROIT_REFUSE  → action non autorisée.

HTTP 404 : ROUTE_INCONNUE  → bug d'intégration, à journaliser.

HTTP 405 : METHODE_INVALIDE → mauvaise méthode HTTP (bug d'intégration).

HTTP 502 : ERREUR_BASE · IA_ERREUR · IA_CONTEXTE_ERREUR
           → erreur temporaire : propose un bouton « Réessayer ». Pour
             IA_ERREUR, vérifie aussi que DEEPSEEK_API_KEY est bien défini.

HTTP 503 : SECRET_MANQUANT · NON_DEPLOYE · IA_INDISPONIBLE ·
           SERVICE_INDISPONIBLE
           → service non configuré / migration SQL manquante. Message d'admin.

Ces codes sont stables : base ton mapping d'erreurs dessus.

═══════════════════════════════════════════════════════════════════════════
3. ÉCRANS À PRODUIRE
═══════════════════════════════════════════════════════════════════════════

ÉCRAN 1 — « Agents terrain » (liste)
  • Tableau ou cartes : photo/avatar, nom, e-mail, téléphone, badour
    Actif/Inactif, nb_boutiques, nb_qr_codes, montant_encaisse, date de recrutement.
  • Recherche par nom / e-mail.
  • Filtres : Actifs · Inactifs · Tous ; Tri : encaissements, boutiques, date.
  • KPIs en haut : nombre d'agents, total boutiques, total QR codes,
    total encaissé (CDF).
  • Actions par ligne : « Voir la fiche », « Désactiver » (si actif).
  • Bouton principal « Recruter un agent ».
  • Gère : chargement (squelettes), liste vide (« Aucun agent recruté pour le
    moment » + bouton Recruter), erreur réseau (message + Réessayer).

ÉCRAN 2 — « Fiche agent » (détail)
  En-tête : photo, nom, e-mail, téléphone, statut, date de recrutement,
            bouton Désactiver, bouton « Demander à l'IA ».
  Cartes de compteurs :
      Utilisateurs créés · Entreprises · Boutiques · Abonnements actifs ·
      Dossiers en attente · Produits · QR codes · Produits publiés
  Cartes financières : « Encaissé » (montant_encaisse) et « Solde dû »
      (solde_du), en CDF, mises en avant.
  Avancement : barre de progression = abonnements actifs / entreprises.
  Onglet « Entreprises » : nom, statut, étape d'activation, solde restant,
      date d'expiration. Cliquable → ouvre le détail entreprise si tu en as un.
  Onglet « Utilisateurs » : nom, e-mail, téléphone, rôle, date de création.
  Onglet « Journal » : voir ÉCRAN 3.

ÉCRAN 3 — « Journal de l'agent » (activité complète)
  • Liste chronologique (plus récent en haut), avec :
      icône + libellé lisible selon `action`, badge de `niveau`
      (INFO / MOYEN / ÉLEVE → couleur), entreprise concernée, date/heure relative
      (« il y a 2 h ») + date absolue en infobulle, et `details` repliables.
  • Dépliage `details` : tableau clé → valeur lisible. Traduis les clés connues
    (montant, mode_paiement, motif, note, reference…) et affiche les autres telles
    quelles. Formate les montants en CDF.
  • Filtres : par famille d'action, par entreprise, par période.
  • Pagination : bouton « Charger plus » utilisant `limite` / `decalage`
    (note : `total` couvre le journal d'audit, pas les lignes d'activation —
    utilise donc le bouton « Charger plus » plutôt qu'un compteur de pages).
  • Bouton « Exporter » (CSV/PDF) — optionnel mais apprécié.

ÉCRAN 4 — « Recruter un agent » (formulaire / assistant)
  Champs : nom, prénom, e-mail (validation), mot de passe (≥ 8 caractères, avec
  jauge de robustesse), note de recrutement (texte libre), photo.
  → photo : voir section 4.
  → appel POST /agents, puis enregistrement local de la photo avec l'agent_id.
  → si compte_reutilise = true : message d'avertissement explicite.
  → message de fin : rappeler à l'administrateur de communiquer ses
    identifiants à l'agent (il se connecte à Biashara Yangu, côté terrain).

ÉCRAN 5 — « Assistant IA »
  • Zone de discussion (historique de la conversation en mémoire de session).
  • Un sélecteur de contexte : « Tout le portefeuille » ou un agent précis.
  • Suggestions cliquables au démarrage, par exemple :
      - « Quel agent a créé le plus de boutiques ? »
      - « Qui n'a rien encaissé ce mois-ci ? »
      - « Résume l'activité de cet agent. »
      - « Que doit faire cet agent pour avancer ? »
  • Affiche la réponse en texte formaté (gère les listes à puces), avec le
    temps de réflexion, et un bouton « Réessayer » en cas d'erreur 502.
  • Affiche un avertissement : « L'assistant ne voit que l'activité des agents,
    pas les ventes ni le stock des commerçants. »

═══════════════════════════════════════════════════════════════════════════
4. PHOTO DE L'AGENT
═══════════════════════════════════════════════════════════════════════════

Notre API ne transporte PAS de photo : elle vit dans TA base, indexée par
`agent_id` (c'est la clé de jointure stable entre les deux systèmes).

À implémenter :
  • Upload : JPG/PNG/WEBP, 5 Mo maximum, recadrage carré + redimensionnement
    (256×256 suffit) avant envoi.
  • Stockage : ton service de fichiers habituel (bucket / dossier) privé.
  • Métadonnées : table locale `agents_bg` (agent_id PK, photo_url,
    telephone, zone, date_recrutement, statut_rh, informations personnelles…).
  • Affichage : avatars ronds + repli sur les initiales si pas de photo.
  • Envoi de la photo à Biashara Yangu : NON POUR L'INSTANT (pas d'endpoint) ;
    prépare simplement la table pour permettre un envoi ultérieur.

IMPORTANT : recruter un agent = deux écritures à garder cohérentes :
  1) POST /agents → renvoie `agent_id` (Biashara Yangu) ;
  2) insert local avec cet `agent_id`.
Si l'étape 2 échoue, l'agent existe quand même chez nous : ne fais pas
d'appel de compensation, affiche juste un avertissement et permets de
ressaisir les informations RH depuis la fiche.

═══════════════════════════════════════════════════════════════════════════
5. RÈGLES DE SÉCURITÉ ET DE QUALITÉ (NON NÉGOCIABLES)
═══════════════════════════════════════════════════════════════════════════

  1. `BG_ADMIN_TOKEN` : uniquement côté serveur, via variable d'environnement.
     Jamais dans le code frontal, jamais dans un dépôt, jamais dans un log.
  2. Tous les appels à notre API passent par TON backend (proxy). Le navigateur
     n'appelle jamais l'URL Supabase directement.
  3. Restreins l'accès aux écrans « Agents » aux rôles habilités
     (administrateur, RH, superviseur, comptable) — jamais aux agents eux-mêmes.
  4. Trace côté Biashara Group QUI a recruté / désactivé QUEL agent et QUAND.
  5. Aucune suppression d'agent : uniquement la désactivation.
  6. Gère explicitement : chargement, vide, erreur, nouvel essai.
  7. Formate les montants en CDF avec une espace comme séparateur de milliers.
  8. Code typé, composants réutilisables, aucun secret en dur, aucun `any`
     implicite.

═══════════════════════════════════════════════════════════════════════════
6. CRITÈRES D'ACCEPTATION
═══════════════════════════════════════════════════════════════════════════

  ✓ GET /ping renvoie { ok: true } → écran de diagnostic au vert.
  ✓ La liste affiche les agents de Biashara Yangu avec leurs compteurs.
  ✓ Un agent désactivé apparaît « Inactif » (valide = 0).
  ✓ La fiche affiche tous les compteurs, l'encaissé et le solde dû.
  ✓ Le journal se pagine avec « Charger plus » et affiche des libellés lisibles.
  ✓ Recruter un agent crée bien un compte utilisable dans Biashara Yangu.
  ✓ Désactiver exige un motif et passe l'agent à Inactif.
  ✓ L'assistant IA répond en français sur le portefeuille ou sur un agent précis,
    et refuse les questions hors périmètre (ventes / stock / dépenses / clients).
  ✓ Aucune valeur de jeton n'apparaît dans le code livré.
  ✓ Aucun appel direct au domaine Supabase depuis le navigateur.

═══════════════════════════════════════════════════════════════════════════
7. JEU DE TEST DISPONIBLE
═══════════════════════════════════════════════════════════════════════════

Un agent de recette existe, utilise-le pour valider tes écrans :

  agent_id : 83162486-0478-4314-bb8e-9bdee71cc516
  e-mail   : agent@espoir.com
  mot de passe (application Biashara Yangu) : 12345678
  attendu  : 1 entreprise (« Boutique Jean-Luc Takalashi »), 1 boutique,
             1 utilisateur créé, plusieurs entrées de journal.

Commence par ces trois appels pour vérifier ta configuration avant de coder :

  curl -H "x-bg-token: $BG_ADMIN_TOKEN" \
    https://pqzcliibocndiyqbyddr.functions.supabase.co/admin-agents/ping

  curl -H "x-bg-token: $BG_ADMIN_TOKEN" \
    https://pqzcliibocndiyqbyddr.functions.supabase.co/admin-agents/agents

  curl -H "x-bg-token: $BG_ADMIN_TOKEN" \
    https://pqzcliibocndiyqbyddr.functions.supabase.co/admin-agents/ia

═══════════════════════════════════════════════════════════════════════════
8. MÉTHODE DE TRAVAIL DEMANDÉE
═══════════════════════════════════════════════════════════════════════════

  1. Commence par un court plan (fichiers à créer/modifier, routes, modèles).
  2. Crée une couche « client API » unique (base URL + en-tête x-bg-token +
     mapping des erreurs) réutilisée par tous les écrans.
  3. Implémente les écrans dans l'ordre : liste → fiche → journal → recrutement
     → désactivation → assistant IA.
  4. Termine par un récapitulatif : fichiers créés, écrans livrés, ce qui reste
     à faire, et les tests effectués avec les trois appels ci-dessus.
````

---

## Annexe — commandes de vérification (côté Biashara Yangu)

À exécuter avant d'envoyer le prompt, pour confirmer que l'API est vivante :

```bash
cd ~/Documents/biasharayanguApp
bash tools/test_admin_agents.sh      # saisie invisible du jeton
```

Et après l'ajout de la route IA, redéployer `admin-agents` :

1. Supabase → **Edge Functions** → `admin-agents` → **Éditer** → **Ctrl+A**
   → **Suppr** → coller `supabase/functions/admin-agents/index.ts` → **Deploy**.
2. Vérifier : `GET /admin-agents/ia` doit renvoyer
   `{"ok":true,"assistant":"deepseek","disponible":true,…}`.

> Si `disponible` vaut `false`, le secret `DEEPSEEK_API_KEY` n'est pas visible
> par cette fonction : ajoutez-le dans **Edge Functions → Secrets**.
