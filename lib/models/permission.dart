// lib/models/permission.dart
//
// MODULE 4 — SYSTÈME DE PERMISSIONS
//
// Ce fichier ne contient que des objets de valeur purs (aucun accès réseau,
// aucun import Flutter) : il peut être testé sans binding.
//
// Trois notions :
//   - [RoleUtilisateur] : les 8 rôles métier (+ le rôle de repli `inconnu`).
//   - [PageAccess]      : les écrans de l'application.
//   - [ActionAccess]    : ce que l'on peut faire sur un écran.
//
// La matrice « rôle → pages/actions » est **statique** (elle vit dans
// `PermissionService`) et peut être surchargée par l'administrateur de la
// plateforme ; les surcharges sont stockées dans `public.app_settings`.

/// Espace d'application auquel une page appartient.
///
/// Ce découpage sert uniquement à regrouper les cases à cocher dans l'écran
/// « Permissions d'un rôle » ; il n'a aucun effet sur les autorisations.
enum EspaceApplication {
  /// Espace La Perle (plateforme) : `/admin`.
  plateforme,

  /// Espace d'une entreprise (boutique) : `/main`.
  entreprise,
}

/// Les 8 rôles du cahier des charges.
///
/// `code` est la valeur réellement stockée dans
/// `public.utilisateurs.new_role` (type `role_utilisateur_enum`).
/// Ne jamais modifier un code sans modifier simultanément le type PostgreSQL.
enum RoleUtilisateur {
  superAdmin('SUPER_ADMIN', 'Expert / Super Administrateur', true),
  gestionnaireComptes('GESTIONNAIRE_COMPTES', 'Gestionnaire des comptes', true),
  financeLaperle('FINANCE_LAPERLE', 'Finance plateforme', true),
  support('SUPPORT', 'Assistance', true),
  proprietaire('PROPRIETAIRE', 'Entreprise / Propriétaire', false),
  vendeur('VENDEUR', 'Caissier (vendeur)', false),
  magasinier('MAGASINIER', 'Magasinier', false),
  comptableEntreprise('COMPTABLE_ENTREPRISE', 'Comptable entreprise', false),

  /// Rôle de repli : aucune permission. Utilisé quand la base renvoie un rôle
  /// que cette version de l'application ne connaît pas (échec fermé).
  inconnu('INCONNU', 'Rôle inconnu', false);

  const RoleUtilisateur(this.code, this.libelle, this.estPlateforme);

  /// Valeur stockée dans `public.utilisateurs.new_role`.
  final String code;

  /// Libellé affiché à l'utilisateur.
  final String libelle;

  /// `true` pour les quatre rôles qui administrent la plateforme La Perle.
  ///
  /// Ces comptes ne sont soumis ni au contrôle d'abonnement, ni aux
  /// permissions d'un espace entreprise.
  final bool estPlateforme;

  /// Rôles proposés dans les listes déroulantes (le rôle `inconnu` est exclu).
  static List<RoleUtilisateur> get rolesSelectionnables => values
      .where((RoleUtilisateur r) => r != RoleUtilisateur.inconnu)
      .toList(growable: false);

  /// Rôles de la plateforme La Perle.
  static List<RoleUtilisateur> get rolesPlateforme => values
      .where((RoleUtilisateur r) => r.estPlateforme)
      .toList(growable: false);

  /// Rôles des entreprises (boutiques).
  static List<RoleUtilisateur> get rolesEntreprise => values
      .where((RoleUtilisateur r) => !r.estPlateforme && r != RoleUtilisateur.inconnu)
      .toList(growable: false);

  /// Convertit une valeur SQL en rôle applicatif.
  ///
  /// Accepte les codes officiels du Module 4 **et** les rôles hérités des
  /// versions précédentes de l'application :
  ///
  /// | Valeur rencontrée                       | Rôle retenu              |
  /// |-----------------------------------------|--------------------------|
  /// | `SUPER_ADMIN`, `admin`, `expert`        | [RoleUtilisateur.superAdmin]        |
  /// | `GESTIONNAIRE_COMPTES`, `gestionnaire`  | [RoleUtilisateur.gestionnaireComptes] |
  /// | `FINANCE_LAPERLE`, `finance`            | [RoleUtilisateur.financeLaperle]    |
  /// | `SUPPORT`, `assistance`                 | [RoleUtilisateur.support]           |
  /// | `PROPRIETAIRE`, `vendor`, `patron`, `owner` | [RoleUtilisateur.proprietaire]  |
  /// | `VENDEUR`, `collaborator`, `caissier`   | [RoleUtilisateur.vendeur]           |
  /// | `MAGASINIER`                            | [RoleUtilisateur.magasinier]        |
  /// | `COMPTABLE_ENTREPRISE`, `comptable`     | [RoleUtilisateur.comptableEntreprise] |
  ///
  /// Toute autre valeur (y compris `null`) renvoie [RoleUtilisateur.inconnu] :
  /// un rôle non reconnu n'ouvre **aucune** page.
  ///
  /// ⚠️ `vendor` était utilisé par l'application d'origine pour désigner le
  /// **patron** d'une boutique (et non un vendeur) : `UtilisateurEntreprise`
  /// l'affiche comme « Patron / Vendeur » et `LoginPage` l'envoie sur `/main`.
  /// Il est donc rattaché à [RoleUtilisateur.proprietaire] pour ne pas
  /// rétrograder les comptes existants.
  static RoleUtilisateur fromCode(String? code) {
    if (code == null) return RoleUtilisateur.inconnu;

    final String normalise = code.trim().toUpperCase();
    for (final RoleUtilisateur role in values) {
      if (role.code == normalise) return role;
    }

    switch (normalise) {
      // Rôles hérités.
      case 'ADMIN':
      case 'EXPERT':
      case 'SUPERADMIN':
      case 'SUPER-ADMIN':
        return RoleUtilisateur.superAdmin;
      case 'GESTIONNAIRE':
      case 'GESTIONNAIRE_DE_COMPTES':
        return RoleUtilisateur.gestionnaireComptes;
      case 'FINANCE':
      case 'FINANCE_LAPERLE':
      case 'LAPERLE':
        return RoleUtilisateur.financeLaperle;
      case 'ASSISTANCE':
      case 'TICKETS':
        return RoleUtilisateur.support;
      case 'VENDOR':
      case 'PATRON':
      case 'OWNER':
      case 'PROPRIETAIRE_ENTREPRISE':
      case 'ENTREPRISE':
        return RoleUtilisateur.proprietaire;
      case 'COLLABORATOR':
      case 'COLLABORATEUR':
      case 'CAISSIER':
        return RoleUtilisateur.vendeur;
      case 'COMPTABLE':
        return RoleUtilisateur.comptableEntreprise;
      default:
        return RoleUtilisateur.inconnu;
    }
  }
}

/// Écrans de l'application.
///
/// `code` est la clé utilisée dans la matrice des permissions, dans
/// `app_settings` **et** dans les fonctions SQL `public.a_permission(...)`.
/// Ces codes sont donc figés : on n'en change jamais un sans migration.
enum PageAccess {
  // ---------------------------------------------------------------- plateforme
  dashboard('dashboard', 'Tableau de bord', [EspaceApplication.plateforme, EspaceApplication.entreprise]),
  entreprises('entreprises', 'Entreprises', [EspaceApplication.plateforme]),
  utilisateurs('utilisateurs', 'Utilisateurs & comptes', [EspaceApplication.plateforme]),
  villes('villes', 'Villes', [EspaceApplication.plateforme]),
  activites('activites', 'Activités', [EspaceApplication.plateforme]),
  groupesTarifaires('groupes_tarifaires', 'Groupes tarifaires', [EspaceApplication.plateforme]),
  abonnements('abonnements', 'Abonnements', [EspaceApplication.plateforme],
      alias: ['abonnement', 'renouvellements', 'impayes']),
  // 🧾 MODULE 14 — workflow d'activation à double validation. Deux écrans,
  // deux responsabilités : le GESTIONNAIRE DES COMPTES vérifie le dossier
  // et le transmet à la finance ; la FINANCE confirme le paiement puis
  // l'activation est automatique. Les alias couvrent le vocabulaire du
  // cahier des charges (« activations », « dossiers »).
  verificationComptes('verification_comptes', 'Comptes à vérifier',
      [EspaceApplication.plateforme],
      alias: ['activations', 'dossiers_activation', 'verifications']),
  activationsFinance('activations_finance', 'Activations & paiements',
      [EspaceApplication.plateforme],
      alias: ['activation_finance', 'paiements_activation']),
  paiements('paiements', 'Paiements', [EspaceApplication.plateforme],
      alias: ['avances', 'soldes', 'historique_paiements']),
  finance('finance', 'Finance', [EspaceApplication.plateforme, EspaceApplication.entreprise],
      alias: ['rapports_financiers', 'soldes_globaux']),
  // 🔐 MODULE 12 — le journal d'audit existe désormais dans les DEUX espaces :
  // le personnel plateforme voit toutes les boutiques, le PROPRIÉTAIRE voit
  // la sienne (RLS serveur + `audit/voir`).
  audit('audit', 'Journal d\'audit', [EspaceApplication.plateforme, EspaceApplication.entreprise],
      alias: ['journal']),
  // 🔐 MODULE 12 — écran de surveillance réservé au personnel plateforme.
  securite('securite', 'Sécurité', [EspaceApplication.plateforme],
      alias: ['alertes_securite']),
  notifications('notifications', 'Notifications', [EspaceApplication.plateforme]),
  assistance('assistance', 'Assistance (tickets)', [EspaceApplication.plateforme],
      alias: ['tickets', 'support']),
  parametres('parametres', 'Paramètres', [EspaceApplication.plateforme, EspaceApplication.entreprise]),

  // ----------------------------------------------------------------- entreprise
  ventes('ventes', 'Ventes', [EspaceApplication.entreprise],
      alias: ['historique_ventes']),
  caisse('caisse', 'Caisse / encaissement', [EspaceApplication.entreprise],
      alias: ['nouvelle_vente', 'encaissement', 'dettes', 'paiements_clients']),
  scanner('scanner', 'Scanner', [EspaceApplication.entreprise]),
  panier('panier', 'Panier', [EspaceApplication.entreprise]),
  articles('articles', 'Articles & catalogue', [EspaceApplication.entreprise],
      alias: ['categories', 'produits']),
  stock('stock', 'Stock', [EspaceApplication.entreprise],
      alias: ['entrees', 'sorties', 'inventaire', 'inventaires', 'approvisionnements']),
  clients('clients', 'Clients', [EspaceApplication.entreprise]),
  fournisseurs('fournisseurs', 'Fournisseurs', [EspaceApplication.entreprise]),
  depenses('depenses', 'Dépenses', [EspaceApplication.entreprise]),
  collaborateurs('collaborateurs', 'Collaborateurs', [EspaceApplication.entreprise],
      alias: ['equipe']),
  // 🏢 MODE PLATEFORME — la production des étiquettes QR est un service de
  // l'administration (elle seule génère les codes produits) : les boutiques
  // n'ont plus accès à cet écran.
  qrCodes('qr_codes', 'QR codes', [EspaceApplication.plateforme]),
  rapports('rapports', 'Rapports', [EspaceApplication.plateforme, EspaceApplication.entreprise],
      alias: ['resultats', 'statistiques']),
  // 🤖 MODULE 13 — assistant IA (espace entreprise ; les outils accessibles
  // dépendent du rôle, revérifié par le serveur à chaque action).
  assistantIa('assistant_ia', 'Assistant IA', [EspaceApplication.entreprise],
      alias: ['agent_ia', 'ia']),
  // 🏨 MODULE 16 C2 — HÔTEL : chambres, planning des réservations et
  // réception (arrivées / départs / check-in / check-out).
  chambres('chambres', 'Chambres', [EspaceApplication.entreprise]),
  reservations('reservations', 'Réservations', [EspaceApplication.entreprise],
      alias: ['planning']),
  reception('reception', 'Réception (séjours)', [EspaceApplication.entreprise],
      alias: ['checkin', 'check_in', 'arrivees', 'departs']),
  // 🍽️ MODULE 16 C3 — RESTAURANT : plan de salle, commandes et cuisine.
  tables('tables', 'Tables de salle', [EspaceApplication.entreprise],
      alias: ['plan_de_salle', 'salle']),
  commandes('commandes', 'Commandes', [EspaceApplication.entreprise],
      alias: ['salle']),
  cuisine('cuisine', 'Cuisine', [EspaceApplication.entreprise],
      alias: ['ecran_cuisine']),
  // 🎉 MODULE 16 C4 — SALLE DES FÊTES : salles et événements.
  salles('salles', 'Salles', [EspaceApplication.entreprise],
      alias: ['salle_des_fetes', 'salle_fete']),
  evenements('evenements', 'Événements', [EspaceApplication.entreprise],
      alias: ['calendrier', 'reservations_salles']),
  // 🥖 MODULE 16 C5 — BOULANGERIE : matières premières et productions.
  production('production', 'Production', [EspaceApplication.entreprise],
      alias: ['boulangerie', 'atelier', 'fabrication']),
  // 🛒 MODULE 19 — MARKETPLACE LOCAL GÉOLOCALISÉ.
  //  • `publications` : quels articles de la boutique apparaissent dans le
  //    catalogue public (et la vitrine : position, horaires, contacts) ;
  //  • `visibilite`   : « Ma visibilité Biashara » (impressions, intérêt,
  //    intentions, conversions attribuées) ;
  //  • `publicites`   : campagnes publicitaires (espace entreprise) et
  //    modération (espace plateforme).
  publications('publications', 'Publications Biashara',
      [EspaceApplication.entreprise],
      alias: ['vitrine', 'ma_vitrine', 'catalogue_public']),
  visibilite('visibilite', 'Visibilité Biashara',
      [EspaceApplication.entreprise],
      alias: ['ma_visibilite', 'statistiques_publiques']),
  publicites('publicites', 'Publicités Biashara',
      [EspaceApplication.entreprise, EspaceApplication.plateforme],
      alias: ['campagnes', 'annonces', 'sponsorise']);

  const PageAccess(this.code, this.libelle, this.espaces, {this.alias = const <String>[]});

  /// Identifiant technique (base de données + SQL).
  final String code;

  /// Libellé affiché à l'utilisateur.
  final String libelle;

  /// Espaces dans lesquels cette page existe (regroupement d'affichage).
  final List<EspaceApplication> espaces;

  /// Noms utilisés par le cahier des charges qui désignent cette même page.
  ///
  /// Ils ne créent pas de nouvelle permission : ils sont seulement reconnus
  /// par [fromCode] pour éviter les doublons (« avances », « soldes » et
  /// « renouvellements » sont des types de paiement du Module 3, pas des
  /// écrans distincts).
  final List<String> alias;

  /// `true` si la page appartient à l'espace indiqué.
  bool dansEspace(EspaceApplication espace) => espaces.contains(espace);

  /// Convertit un code (technique ou alias) en page.
  ///
  /// Renvoie `null` si le code est inconnu : les permissions stockées qui
  /// contiennent un code inconnu sont simplement ignorées.
  static PageAccess? fromCode(String? code) {
    if (code == null) return null;

    final String normalise = code.trim().toLowerCase();
    for (final PageAccess page in values) {
      if (page.code == normalise) return page;
    }
    for (final PageAccess page in values) {
      if (page.alias.contains(normalise)) return page;
    }
    return null;
  }

  /// Pages de l'espace demandé, dans l'ordre de déclaration.
  static List<PageAccess> deEspace(EspaceApplication espace) => values
      .where((PageAccess page) => page.dansEspace(espace))
      .toList(growable: false);
}

/// Actions applicables à une page.
enum ActionAccess {
  voir('voir', 'Voir'),
  creer('creer', 'Créer'),
  modifier('modifier', 'Modifier'),
  supprimer('supprimer', 'Supprimer'),
  valider('valider', 'Valider');

  const ActionAccess(this.code, this.libelle);

  /// Identifiant technique (base de données + SQL).
  final String code;

  /// Libellé affiché à l'utilisateur.
  final String libelle;

  /// Convertit un code SQL en action. Renvoie `null` si inconnu.
  static ActionAccess? fromCode(String? code) {
    if (code == null) return null;

    final String normalise = code.trim().toLowerCase();
    for (final ActionAccess action in values) {
      if (action.code == normalise) return action;
    }
    return null;
  }
}

/// Permissions d'un rôle : pour chaque page accessible, l'ensemble des
/// actions autorisées.
///
/// Le cahier des charges décrit un rôle par « des pages + des actions »
/// (ex. « pages : ventes, caisse — actions : voir, creer »), avec parfois des
/// exceptions (« modifier, assistance uniquement »). Cette classe couvre les
/// deux cas :
///
/// ```dart
/// // Actions identiques sur toutes les pages.
/// RolePermission.uniforme([PageAccess.ventes, PageAccess.caisse],
///     [ActionAccess.voir, ActionAccess.creer]);
///
/// // Exceptions par page (« modifier » réservé à l'assistance).
/// RolePermission.personnalise({
///   PageAccess.assistance: {ActionAccess.voir, ActionAccess.modifier},
///   PageAccess.entreprises: {ActionAccess.voir},
/// });
/// ```
class RolePermission {
  /// Table page → actions autorisées. Un rôle ne détenant jamais de page
  /// sans aucune action, une entrée existe dès que la page est accessible.
  final Map<PageAccess, Set<ActionAccess>> _parPage;

  const RolePermission._(this._parPage);

  /// Construit des permissions où [actions] s'appliquent à toutes les [pages].
  factory RolePermission.uniforme(
    Iterable<PageAccess> pages,
    Iterable<ActionAccess> actions,
  ) {
    final Set<ActionAccess> set = actions.toSet();
    return RolePermission._(<PageAccess, Set<ActionAccess>>{
      for (final PageAccess page in pages) page: Set<ActionAccess>.unmodifiable(set),
    });
  }

  /// Construit des permissions avec des actions propres à chaque page.
  ///
  /// Les entrées dont l'ensemble d'actions est vide sont retirées : une page
  /// sans action n'est pas accessible.
  factory RolePermission.personnalise(Map<PageAccess, Set<ActionAccess>> parPage) {
    return RolePermission._(<PageAccess, Set<ActionAccess>>{
      for (final MapEntry<PageAccess, Set<ActionAccess>> e in parPage.entries)
        if (e.value.isNotEmpty) e.key: Set<ActionAccess>.unmodifiable(e.value),
    });
  }

  /// Aucune permission (rôle inconnu, ou rôle volontairement vidé).
  static const RolePermission aucune = RolePermission._(<PageAccess, Set<ActionAccess>>{});

  /// Pages accessibles, dans l'ordre de déclaration de [PageAccess].
  List<PageAccess> get pages => PageAccess.values
      .where((PageAccess page) => _parPage.containsKey(page))
      .toList(growable: false);

  /// `true` si le rôle n'a strictement aucun droit.
  bool get estVide => _parPage.isEmpty;

  /// Actions autorisées sur [page] (`const {}` si la page est interdite).
  Set<ActionAccess> actionsPour(PageAccess page) =>
      _parPage[page] ?? const <ActionAccess>{};

  /// `true` si l'action est autorisée sur la page.
  bool aAcces(PageAccess page, ActionAccess action) =>
      _parPage[page]?.contains(action) ?? false;

  /// Copie profonde de la table courante (les instances sont immuables).
  Map<PageAccess, Set<ActionAccess>> _copie() => <PageAccess, Set<ActionAccess>>{
        for (final MapEntry<PageAccess, Set<ActionAccess>> e in _parPage.entries)
          e.key: <ActionAccess>{...e.value},
      };

  /// Autorise (ou retire) une action sur une page.
  ///
  /// Retirer la dernière action d'une page rend la page inaccessible — c'est
  /// exactement ce que fait une case décochée dans l'écran d'administration.
  RolePermission avec(PageAccess page, ActionAccess action, bool autorise) {
    final Map<PageAccess, Set<ActionAccess>> copie = _copie();
    final Set<ActionAccess>? actions = copie[page];

    if (actions == null) {
      if (!autorise) return this;
      copie[page] = <ActionAccess>{action};
    } else if (autorise) {
      actions.add(action);
    } else {
      actions.remove(action);
      if (actions.isEmpty) copie.remove(page);
    }
    return RolePermission.personnalise(copie);
  }

  /// Autorise ou interdit **toutes** les actions d'une page d'un seul geste
  /// (case à cocher principale de l'écran d'administration).
  ///
  /// À l'activation, les actions déjà choisies sont conservées ; si la page
  /// était totalement interdite, elle revient avec l'action [ActionAccess.voir].
  RolePermission avecPage(PageAccess page, bool autorise) {
    if (!autorise) {
      final Map<PageAccess, Set<ActionAccess>> copie = _copie()..remove(page);
      return RolePermission.personnalise(copie);
    }

    final Set<ActionAccess> existantes = actionsPour(page);
    return avecActions(
      page,
      existantes.isEmpty ? <ActionAccess>{ActionAccess.voir} : existantes,
    );
  }

  /// Remplace d'un coup toutes les actions de [page] (ensemble vide = page
  /// interdite).
  RolePermission avecActions(PageAccess page, Set<ActionAccess> actions) {
    final Map<PageAccess, Set<ActionAccess>> copie = _copie();
    if (actions.isEmpty) {
      copie.remove(page);
    } else {
      copie[page] = <ActionAccess>{...actions};
    }
    return RolePermission.personnalise(copie);
  }

  /// Union avec [autre] : utile pour composer un rôle par héritage.
  RolePermission fusionner(RolePermission autre) {
    final Map<PageAccess, Set<ActionAccess>> copie = _copie();
    autre._parPage.forEach((PageAccess page, Set<ActionAccess> actions) {
      copie.putIfAbsent(page, () => <ActionAccess>{}).addAll(actions);
    });
    return RolePermission.personnalise(copie);
  }

  /// Sérialisation JSON — c'est ce qui est stocké dans `app_settings.value`.
  ///
  /// ```json
  /// { "ventes": ["voir", "creer"], "caisse": ["voir", "creer"] }
  /// ```
  Map<String, List<String>> toJson() => <String, List<String>>{
        for (final PageAccess page in pages)
          page.code: actionsPour(page).map((ActionAccess a) => a.code).toList()
            ..sort(),
      };

  /// Reconstruit des permissions depuis `app_settings.value`.
  ///
  /// Les codes inconnus sont ignorés (compatibilité ascendante).
  factory RolePermission.fromJson(Map<String, dynamic> json) {
    final Map<PageAccess, Set<ActionAccess>> parPage =
        <PageAccess, Set<ActionAccess>>{};

    json.forEach((String cle, dynamic valeur) {
      final PageAccess? page = PageAccess.fromCode(cle);
      if (page == null) return;

      final Set<ActionAccess> actions = <ActionAccess>{};
      if (valeur is List) {
        for (final dynamic code in valeur) {
          final ActionAccess? action = ActionAccess.fromCode(code?.toString());
          if (action != null) actions.add(action);
        }
      }
      if (actions.isNotEmpty) parPage[page] = actions;
    });

    return RolePermission.personnalise(parPage);
  }

  @override
  String toString() => toJson().toString();
}
