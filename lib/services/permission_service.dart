// lib/services/permission_service.dart
//
// MODULE 4 — SERVICE DE PERMISSIONS
//
// Responsabilités :
//   1. Décrire la matrice « rôle → pages → actions » (STATIQUE, ci-dessous).
//   2. Résoudre le rôle d'un utilisateur (`new_role`, puis `role` hérité).
//   3. Charger les surcharges enregistrées par le Super Admin dans
//      `public.app_settings` (clé `permissions_roles`).
//   4. Répondre aux questions de l'application :
//        - `getPagesAccessibles(role)`  → pages autorisées
//        - `aAcces(role, page, action)` → droit précis
//        - `peut(page, action)`         → droit du rôle connecté
//        - `routeAutorisee(location)`   → middleware de navigation
//        - `menuPour(role, espace)`     → menu dynamique
//
// DEUX GARANTIES IMPORTANTES
//   • Fail-open sur les DÉFAUTS : si `app_settings` est injoignable (hors
//     ligne), l'application retombe sur la matrice statique — jamais sur
//     « aucun droit », ce qui verrouillerait tout le monde.
//   • Fail-closed sur les INCONNUES : un rôle non reconnu ([RoleUtilisateur.inconnu])
//     n'obtient aucune page.
//
// ORDRE D'APPLICATION DES CONTRÔLES
//   Le contrôle d'abonnement (Module 3) passe AVANT les permissions : un
//   abonnement bloqué empêche d'arriver jusqu'ici, un abonnement échu place
//   l'application en lecture seule (voir `AbonnementService` et `LoginPage`).

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'dart:convert';

import 'package:biashara_yangu/models/permission.dart';
import 'package:biashara_yangu/models/utilisateur.dart';
import 'package:biashara_yangu/services/supabase_service.dart';
import 'package:biashara_yangu/utils/json_parsing.dart';

/// Erreur métier du module des permissions (message déjà en français).
class PermissionServiceException implements Exception {
  const PermissionServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Entrée du menu latéral dynamique.
class EntreeMenu {
  const EntreeMenu({
    required this.page,
    required this.libelle,
    this.route,
    this.groupe,
  });

  final PageAccess page;
  final String libelle;

  /// Route go_router à ouvrir, ou `null` si l'entrée est un onglet interne.
  final String? route;

  /// Regroupement d'affichage (ex. « Référentiels »).
  final String? groupe;

  @override
  String toString() => '$libelle (${page.code})';
}

/// Règle de routage : préfixe d'URL → page protégée.
class _RegleRoute {
  const _RegleRoute(this.prefixe, this.page, [this.action]);

  final String prefixe;
  final PageAccess page;

  /// Action explicitement exigée. Quand elle est `null`, l'action est déduite
  /// du suffixe de l'URL (`/new` → créer, `/edit` → modifier, sinon voir).
  final ActionAccess? action;
}

/// Service central des permissions.
///
/// Singleton : `PermissionService.instance`.
class PermissionService {
  PermissionService._();

  static final PermissionService instance = PermissionService._();

  /// Clé utilisée dans `public.app_settings`.
  static const String cleAppSettings = 'permissions_roles';

  SupabaseClient get _client => SupabaseService.instance.client;

  // ---------------------------------------------------------------------------
  // 1. MATRICE STATIQUE DES PERMISSIONS (cahier des charges Module 4)
  // ---------------------------------------------------------------------------
  //  Chaque rôle est décrit par ses pages et les actions autorisées sur ces
  //  pages. Les pages listées par le cahier des charges sous un autre nom
  //  (« avances », « soldes », « nouvelles_ventes »…) sont des alias déclarés
  //  dans `PageAccess` : elles ne créent pas de permission supplémentaire.
  //
  //  Décisions explicites :
  //   • « historique » n'est pas un écran : il désigne, selon le rôle,
  //     `paiements` (Finance), `stock` (Magasinier) ou `rapports` (Comptable).
  //   • Un GESTIONNAIRE_COMPTES ne voit ni la finance ni les paiements
  //     (« INTERDIT : finance, paiements sensibles ») : il gère les comptes,
  //     les rattachements et les échéances d'abonnement, pas l'argent.
  //   • SUPPORT ne peut « modifier » que l'assistance : il est en lecture sur
  //     les entreprises et les utilisateurs.
  //   • Un VENDEUR n'a jamais `modifier` : le prix d'un article ne peut donc
  //     pas être changé depuis son écran (exigence explicite du module).
  // ---------------------------------------------------------------------------

  static final Map<RoleUtilisateur, RolePermission> defauts =
      <RoleUtilisateur, RolePermission>{
    // ----------------------------------------------------------- plateforme
    RoleUtilisateur.superAdmin: RolePermission.uniforme(
      PageAccess.values,
      ActionAccess.values,
    ),
    RoleUtilisateur.gestionnaireComptes: RolePermission.personnalise(
      <PageAccess, Set<ActionAccess>>{
        for (final PageAccess page in const <PageAccess>[
          PageAccess.entreprises,
          PageAccess.utilisateurs,
          PageAccess.villes,
          PageAccess.activites,
          PageAccess.groupesTarifaires,
          PageAccess.abonnements,
          // 🏢 production des étiquettes QR des boutiques (service plateforme).
          PageAccess.qrCodes,
          PageAccess.assistance,
          PageAccess.notifications,
        ])
          page: const <ActionAccess>{
            ActionAccess.voir,
            ActionAccess.creer,
            ActionAccess.modifier,
          },
        // 🧾 MODULE 14 — première validation du workflow d'activation : il
        // VÉRIFIE le dossier (et le transmet à la finance) ou le rejette
        // avec motif. Il n'active jamais un compte : seule la finance
        // valide le paiement (rôles revérifiés côté serveur).
        PageAccess.verificationComptes: const <ActionAccess>{
          ActionAccess.voir,
          ActionAccess.valider,
        },
      },
    ),
    RoleUtilisateur.financeLaperle: RolePermission.uniforme(
      const <PageAccess>[
        PageAccess.dashboard,
        PageAccess.abonnements, // renouvellements, impayés
        // 🧾 MODULE 14 — deuxième validation : validation du paiement
        // (montant, mode, référence) et activation automatique du compte.
        PageAccess.activationsFinance,
        PageAccess.paiements, // avances, soldes, historique des paiements
        PageAccess.finance, // rapports financiers
        PageAccess.rapports,
        PageAccess.audit,
        PageAccess.notifications,
      ],
      const <ActionAccess>[
        ActionAccess.voir,
        ActionAccess.creer,
        ActionAccess.valider,
      ],
    ),
    RoleUtilisateur.support: RolePermission.personnalise(
      <PageAccess, Set<ActionAccess>>{
        PageAccess.dashboard: const <ActionAccess>{ActionAccess.voir},
        PageAccess.assistance: const <ActionAccess>{
          ActionAccess.voir,
          ActionAccess.modifier,
        },
        PageAccess.entreprises: const <ActionAccess>{ActionAccess.voir},
        PageAccess.utilisateurs: const <ActionAccess>{ActionAccess.voir},
        PageAccess.abonnements: const <ActionAccess>{ActionAccess.voir},
        PageAccess.notifications: const <ActionAccess>{
          ActionAccess.voir,
          ActionAccess.modifier,
        },
      },
    ),

    // ----------------------------------------------------------- entreprise
    RoleUtilisateur.proprietaire: RolePermission.uniforme(
      const <PageAccess>[
        PageAccess.dashboard,
        PageAccess.ventes,
        PageAccess.caisse,
        PageAccess.scanner,
        PageAccess.panier,
        PageAccess.articles,
        PageAccess.stock,
        PageAccess.clients,
        PageAccess.fournisseurs,
        PageAccess.finance,
        PageAccess.depenses,
        PageAccess.collaborateurs,
        PageAccess.rapports,
        PageAccess.abonnements, // suivi de son propre abonnement
        PageAccess.audit, // 🔐 MODULE 12 — journal de SA boutique
        PageAccess.assistantIa, // 🤖 MODULE 13 — assistant IA
        PageAccess.parametres,
      ],
      ActionAccess.values, // tout, sauf l'administration de la plateforme
    ),
    RoleUtilisateur.vendeur: RolePermission.uniforme(
      const <PageAccess>[
        PageAccess.ventes, // historique de ses ventes
        PageAccess.caisse, // nouvelle vente + encaissement
        PageAccess.scanner,
        PageAccess.panier,
        PageAccess.assistantIa, // 🤖 MODULE 13 — assistant IA (outils du rôle)
      ],
      const <ActionAccess>[
        ActionAccess.voir,
        ActionAccess.creer, // vendre — et rien d'autre
      ],
    ),
    RoleUtilisateur.magasinier: RolePermission.personnalise(
      <PageAccess, Set<ActionAccess>>{
        PageAccess.stock: const <ActionAccess>{
          ActionAccess.voir,
          ActionAccess.creer,
          ActionAccess.modifier, // entrées / sorties / inventaire
        },
        PageAccess.articles: const <ActionAccess>{ActionAccess.voir},
        PageAccess.rapports: const <ActionAccess>{ActionAccess.voir},
        PageAccess.assistantIa: const <ActionAccess>{
          ActionAccess.voir,
          ActionAccess.creer,
        },
      },
    ),
    RoleUtilisateur.comptableEntreprise: RolePermission.personnalise(
      <PageAccess, Set<ActionAccess>>{
        PageAccess.dashboard: const <ActionAccess>{ActionAccess.voir},
        PageAccess.ventes: const <ActionAccess>{ActionAccess.voir},
        PageAccess.caisse: const <ActionAccess>{ActionAccess.voir},
        PageAccess.depenses: const <ActionAccess>{
          ActionAccess.voir,
          ActionAccess.creer,
          ActionAccess.valider,
        },
        PageAccess.rapports: const <ActionAccess>{
          ActionAccess.voir,
          ActionAccess.valider,
        },
        PageAccess.finance: const <ActionAccess>{ActionAccess.voir},
        PageAccess.assistantIa: const <ActionAccess>{
          ActionAccess.voir,
          ActionAccess.creer,
        },
        PageAccess.parametres: const <ActionAccess>{ActionAccess.voir},
      },
    ),
  };

  // ---------------------------------------------------------------------------
  // 2. RÈGLES DE ROUTAGE (middleware de navigation)
  // ---------------------------------------------------------------------------
  //  Le préfixe le plus long l'emporte. Une URL sans règle est autorisée :
  //  seules les zones sensibles sont listées ici.

  static const List<_RegleRoute> _regles = <_RegleRoute>[
    // ---------------------------------------------------------- plateforme
    _RegleRoute('/admin/permissions', PageAccess.parametres, ActionAccess.modifier),
    _RegleRoute('/admin/entreprises', PageAccess.entreprises),
    _RegleRoute('/admin/activites', PageAccess.activites),
    _RegleRoute('/admin/groupes-tarifaires', PageAccess.groupesTarifaires),
    _RegleRoute('/admin/abonnements', PageAccess.abonnements),
    _RegleRoute('/admin/utilisateurs', PageAccess.utilisateurs),
    _RegleRoute('/admin/villes', PageAccess.villes),
    // 🧾 MODULE 14 — écrans admin du workflow d'activation (rôles revérifiés
    // par les RPC : le gestionnaire n'active pas, la finance valide.
    _RegleRoute('/admin/verification-comptes', PageAccess.verificationComptes),
    _RegleRoute('/admin/activations-finance', PageAccess.activationsFinance),
    _RegleRoute('/admin', PageAccess.dashboard),

    // 🔐 MODULE 12 — journal d'audit (plateforme : toutes les boutiques ;
    // entreprise : la sienne), écran Sécurité (plateforme) et import
    // d'articles (exige « articles / créer »). Routes de premier niveau,
    // comme `/scanner`.
    _RegleRoute('/audit', PageAccess.audit),
    _RegleRoute('/securite', PageAccess.securite),
    _RegleRoute('/import-produits', PageAccess.articles, ActionAccess.creer),

    // 🤖 MODULE 13 — assistant IA (chat + quotas) et configuration IA
    // (réservée au Super Admin via `parametres/modifier`, revérifié serveur).
    _RegleRoute('/assistant-ia', PageAccess.assistantIa),
    _RegleRoute('/achat-quotas', PageAccess.assistantIa),
    _RegleRoute('/agent-ia-config', PageAccess.parametres, ActionAccess.modifier),

    // ---------------------------------------------------------- entreprise
    _RegleRoute('/main/new-sale', PageAccess.caisse, ActionAccess.creer),
    // 🧾 MODULE 8 — panier et encaissement (l'encaissement exige caisse/créer).
    _RegleRoute('/main/panier/encaissement', PageAccess.caisse, ActionAccess.creer),
    _RegleRoute('/main/panier', PageAccess.panier),
    _RegleRoute('/main/ventes', PageAccess.ventes),
    _RegleRoute('/confirmation-vente', PageAccess.caisse),
    // 🔳 MODULE 7 — scanner vendeur (écran plein écran, hors barre de navigation).
    _RegleRoute('/scanner', PageAccess.scanner),
    _RegleRoute('/main/articles/categories', PageAccess.articles, ActionAccess.modifier),
    _RegleRoute('/main/articles', PageAccess.articles),
    _RegleRoute('/main/qr-codes', PageAccess.qrCodes),
    // 🏢 MODE PLATEFORME — production des étiquettes QR (administration).
    _RegleRoute('/admin/qr-codes', PageAccess.qrCodes),

    // 🏬 MODULE 9 — écritures de stock : droits fins côté middleware.
    //  (L'écran Stock lui-même reste en « voir » ; la RPC serveur revérifie
    //  les droits `stock/creer` et `stock/modifier` de toute façon.)
    _RegleRoute('/main/stock/inventaire', PageAccess.stock, ActionAccess.modifier),
    _RegleRoute('/main/stock/approvisionnement', PageAccess.stock, ActionAccess.creer),
    _RegleRoute('/main/stock/ajustement', PageAccess.stock, ActionAccess.modifier),
    _RegleRoute('/main/stock', PageAccess.stock),
    _RegleRoute('/main/add-product', PageAccess.articles, ActionAccess.creer),
    _RegleRoute('/main/edit-product', PageAccess.articles, ActionAccess.modifier),
    _RegleRoute('/main/commercial', PageAccess.ventes),
    // 💰 MODULE 10 — finance de l'entreprise : la clôture de caisse est une
    // validation, la création de dépense/dette une écriture commerciale.
    _RegleRoute('/main/caisse/cloture', PageAccess.caisse, ActionAccess.modifier),
    _RegleRoute('/main/caisse', PageAccess.caisse),
    _RegleRoute('/main/finance/rapports', PageAccess.rapports),
    _RegleRoute('/main/finance', PageAccess.finance),
    // 📊 MODULE 11 — écran Rapports & exports.
    _RegleRoute('/main/rapports', PageAccess.rapports),
    _RegleRoute('/main/depenses/new', PageAccess.depenses, ActionAccess.creer),
    _RegleRoute('/main/depenses', PageAccess.depenses),
    _RegleRoute('/main/dettes/new', PageAccess.caisse, ActionAccess.creer),
    _RegleRoute('/main/dettes', PageAccess.caisse),
    _RegleRoute('/main/clients', PageAccess.clients),
    _RegleRoute('/main/inventaires', PageAccess.stock),
    // 🧾 MODULE 14 — tableau de bord du dossier d'activation (consultable par
    // les rôles qui accèdent au tableau de bord de la boutique).
    _RegleRoute('/main/mon-activation', PageAccess.dashboard),
    // 🏢 MODULE 15 — mes entreprises (pack multi-entreprises) : accessible
    // aux rôles qui pilotent la boutique (le serveur limite la CRÉATION au
    // propriétaire et au pack).
    _RegleRoute('/main/mes-entreprises', PageAccess.dashboard),
    _RegleRoute('/main', PageAccess.dashboard),

    _RegleRoute('/reports', PageAccess.rapports),
    _RegleRoute('/stock-management', PageAccess.stock),

    _RegleRoute('/settings/manage-users', PageAccess.collaborateurs),
    _RegleRoute('/settings/manage-categories', PageAccess.articles, ActionAccess.modifier),
    _RegleRoute('/settings/collaborateurs-stats', PageAccess.collaborateurs),
    _RegleRoute('/settings', PageAccess.parametres),
  ];

  // ---------------------------------------------------------------------------
  // 3. ÉTAT COURANT (rôle connecté + surcharges chargées)
  // ---------------------------------------------------------------------------

  RoleUtilisateur _roleCourant = RoleUtilisateur.inconnu;
  final Map<RoleUtilisateur, RolePermission> _surcharges =
      <RoleUtilisateur, RolePermission>{};
  bool _surchargesChargees = false;

  /// Rôle de la session courante.
  RoleUtilisateur get roleCourant => _roleCourant;

  /// `true` dès que la matrice (défauts + surcharges) est utilisable.
  bool get pret => _surchargesChargees;

  /// Rôle déduit d'un profil utilisateur.
  ///
  /// 1. `new_role` (colonne officielle du Module 4) s'il est renseigné ;
  /// 2. sinon l'ancien `role` texte, converti par [RoleUtilisateur.fromCode]
  ///    (`admin` → Super Admin, `vendor` → Propriétaire, `collaborator` →
  ///    Vendeur) ;
  /// 3. si les deux colonnes sont vides, on reproduit le comportement
  ///    historique de l'application (`Utilisateur.role` vaut alors `vendor`) :
  ///    un compte rattaché à un patron devient vendeur, un compte autonome
  ///    devient propriétaire.
  ///
  /// Une valeur **inconnue** mais non vide renvoie [RoleUtilisateur.inconnu] :
  /// on n'accorde jamais de droits par défaut à un rôle qu'on ne comprend pas.
  static RoleUtilisateur roleDepuisUtilisateur(Utilisateur? utilisateur) {
    if (utilisateur == null) return RoleUtilisateur.inconnu;

    final RoleUtilisateur depuisNouveau =
        RoleUtilisateur.fromCode(utilisateur.newRole);
    if (depuisNouveau != RoleUtilisateur.inconnu) return depuisNouveau;

    final RoleUtilisateur depuisAncien = RoleUtilisateur.fromCode(utilisateur.role);
    if (depuisAncien != RoleUtilisateur.inconnu) return depuisAncien;

    final bool aucuneValeur =
        utilisateur.role.trim().isEmpty &&
            (utilisateur.newRole ?? '').trim().isEmpty;
    if (aucuneValeur) {
      final bool rattache =
          (utilisateur.parentId ?? '').trim().isNotEmpty;
      return rattache ? RoleUtilisateur.vendeur : RoleUtilisateur.proprietaire;
    }

    return RoleUtilisateur.inconnu;
  }

  /// Rôle déduit de valeurs brutes (`new_role`, `role`, `parent_id`).
  static RoleUtilisateur roleDepuisCodes({
    String? newRole,
    String? role,
    String? parentId,
  }) {
    return roleDepuisUtilisateur(Utilisateur(
      id: null,
      nom: '',
      email: '',
      role: role ?? '',
      newRole: newRole,
      parentId: parentId,
    ));
  }

  /// Fixe le rôle de la session (appelé au démarrage et à la connexion).
  void definirRoleCourant(RoleUtilisateur role) {
    _roleCourant = role;
  }

  /// Fixe le rôle à partir du code stocké en session.
  void definirRoleDepuisCode(String? code) {
    _roleCourant = RoleUtilisateur.fromCode(code);
  }

  // ---------------------------------------------------------------------------
  // 4. CHARGEMENT DES SURCHARGES (`app_settings`)
  // ---------------------------------------------------------------------------

  /// Prépare le service pour la session qui commence.
  ///
  /// Best-effort : toute erreur laisse la matrice statique en place.
  Future<void> initialiser(String? codeRole, {bool forcerRechargement = false}) async {
    definirRoleDepuisCode(codeRole);
    if (!_surchargesChargees || forcerRechargement) {
      await rechargerSurcharges();
    }
  }

  /// Relit `app_settings.permissions_roles`.
  Future<void> rechargerSurcharges() async {
    try {
      final dynamic reponse = await _client
          .from('app_settings')
          .select('value')
          .eq('key', cleAppSettings)
          .maybeSingle();

      final Map<String, dynamic>? ligne = parseMap(reponse);
      _surcharges
        ..clear()
        ..addAll(lireSurcharges(ligne?['value']));
      _surchargesChargees = true;
    } catch (e) {
      // Hors ligne, RLS, table absente… : on garde les défauts.
      debugPrint('PermissionService.rechargerSurcharges ignoré : $e');
      _surchargesChargees = true;
    }
  }

  /// Lit un document `app_settings.value` et renvoie les rôles personnalisés.
  ///
  /// Format attendu (les deux formes sont acceptées) :
  ///
  /// ```json
  /// { "roles": { "VENDEUR": { "ventes": ["voir", "creer"] } } }
  /// ```
  ///
  /// Les rôles et les pages inconnus sont ignorés : un document corrompu ne
  /// peut jamais élargir les droits.
  static Map<RoleUtilisateur, RolePermission> lireSurcharges(dynamic valeur) {
    final Map<RoleUtilisateur, RolePermission> resultat =
        <RoleUtilisateur, RolePermission>{};

    dynamic brut = valeur;
    if (brut is String && brut.trim().isNotEmpty) {
      try {
        brut = jsonDecode(brut);
      } catch (_) {
        return resultat;
      }
    }

    final Map<String, dynamic>? racine = parseMap(brut);
    if (racine == null) return resultat;

    // Format accepté : { "roles": { "VENDEUR": { "ventes": ["voir"] } } }
    // ou directement { "VENDEUR": { "ventes": ["voir"] } }.
    final Map<String, dynamic> roles = parseMap(racine['roles']) ?? racine;

    roles.forEach((String code, dynamic valeurRole) {
      final RoleUtilisateur role = RoleUtilisateur.fromCode(code);
      if (role == RoleUtilisateur.inconnu) return;

      final Map<String, dynamic>? parPage = parseMap(valeurRole);
      if (parPage == null) return;

      resultat[role] = RolePermission.fromJson(parPage);
    });

    return resultat;
  }

  /// Vide le cache (déconnexion, changement de rôle…).
  void reinitialiser() {
    _roleCourant = RoleUtilisateur.inconnu;
    _surcharges.clear();
    _surchargesChargees = false;
  }

  /// Remplace les surcharges en mémoire, sans passer par le réseau.
  ///
  /// Utilisé par les tests, et disponible pour un pré-chargement hors ligne.
  void appliquerSurcharges(Map<RoleUtilisateur, RolePermission> surcharges) {
    _surcharges
      ..clear()
      ..addAll(surcharges);
    _surchargesChargees = true;
  }

  // ---------------------------------------------------------------------------
  // 5. LECTURE DES PERMISSIONS
  // ---------------------------------------------------------------------------

  /// Permissions effectives d'un rôle : surcharge administrative si elle
  /// existe, sinon matrice statique.
  RolePermission permissionsDe(RoleUtilisateur role) {
    if (role == RoleUtilisateur.inconnu) return RolePermission.aucune;
    return _surcharges[role] ?? defauts[role] ?? RolePermission.aucune;
  }

  /// Permissions par défaut (avant toute personnalisation).
  RolePermission defautsDe(RoleUtilisateur role) =>
      defauts[role] ?? RolePermission.aucune;

  /// `true` si l'administrateur a personnalisé ce rôle.
  bool estPersonnalise(RoleUtilisateur role) => _surcharges.containsKey(role);

  /// Pages accessibles à un rôle.
  List<PageAccess> getPagesAccessibles(RoleUtilisateur role) =>
      permissionsDe(role).pages;

  /// Pages accessibles, filtrées sur un espace d'application.
  List<PageAccess> getPagesAccessiblesDans(
    RoleUtilisateur role,
    EspaceApplication espace,
  ) =>
      getPagesAccessibles(role)
          .where((PageAccess page) => page.dansEspace(espace))
          .toList(growable: false);

  /// Vérification d'un droit précis.
  bool aAcces(RoleUtilisateur role, PageAccess page, ActionAccess action) =>
      permissionsDe(role).aAcces(page, action);

  /// Vérification d'un droit pour le rôle connecté.
  bool peut(PageAccess page, ActionAccess action) =>
      aAcces(_roleCourant, page, action);

  /// Raccourci lisible : `peutVoir(PageAccess.stock)`.
  bool peutVoir(PageAccess page) => peut(page, ActionAccess.voir);

  /// Raccourci lisible : `peutCreer(PageAccess.depenses)`.
  bool peutCreer(PageAccess page) => peut(page, ActionAccess.creer);

  /// Raccourci lisible : `peutModifier(PageAccess.articles)`.
  bool peutModifier(PageAccess page) => peut(page, ActionAccess.modifier);

  /// Raccourci lisible : `peutSupprimer(PageAccess.depenses)`.
  bool peutSupprimer(PageAccess page) => peut(page, ActionAccess.supprimer);

  /// Raccourci lisible : `peutValider(PageAccess.paiements)`.
  bool peutValider(PageAccess page) => peut(page, ActionAccess.valider);

  /// Le rôle est-il l'administrateur de la plateforme (accès total) ?
  bool get estSuperAdmin => _roleCourant == RoleUtilisateur.superAdmin;

  /// Le rôle connecté appartient-il à la plateforme La Perle ?
  bool get estPlateforme => _roleCourant.estPlateforme;

  // ---------------------------------------------------------------------------
  // 6. MIDDLEWARE DE NAVIGATION
  // ---------------------------------------------------------------------------

  /// Page protégée par une URL, ou `null` si l'URL est libre.
  static PageAccess? pageRequisePour(String location) => _resoudre(location)?.page;

  /// Règle exacte appliquée à une URL.
  static ({PageAccess page, ActionAccess action})? _resoudre(String location) {
    if (location.endsWith('/paiement')) {
      return (page: PageAccess.paiements, action: ActionAccess.creer);
    }

    _RegleRoute? retenue;
    for (final _RegleRoute regle in _regles) {
      final bool correspond = location == regle.prefixe ||
          location.startsWith('${regle.prefixe}/');
      if (!correspond) continue;
      if (retenue == null || regle.prefixe.length > retenue.prefixe.length) {
        retenue = regle;
      }
    }
    if (retenue == null) return null;

    ActionAccess action = retenue.action ?? ActionAccess.voir;
    if (retenue.action == null) {
      if (location.endsWith('/new')) {
        action = ActionAccess.creer;
      } else if (location.endsWith('/edit')) {
        action = ActionAccess.modifier;
      }
    }
    return (page: retenue.page, action: action);
  }

  /// `true` si la navigation vers [location] est autorisée pour le rôle courant.
  bool routeAutorisee(String location) {
    final ({PageAccess page, ActionAccess action})? regle = _resoudre(location);
    if (regle == null) return true;
    return peut(regle.page, regle.action);
  }

  /// Première page accessible du rôle, pour y rediriger un accès refusé.
  ///
  /// Renvoie `null` si le rôle n'a droit à rien (cas théorique : un rôle
  /// inconnu — l'utilisateur reste alors sur l'écran de connexion).
  String? accueilPour(RoleUtilisateur role) {
    if (role.estPlateforme) {
      for (final PageAccess page in <PageAccess>[
        PageAccess.dashboard,
        PageAccess.entreprises,
        PageAccess.utilisateurs,
        PageAccess.abonnements,
        PageAccess.paiements,
        PageAccess.assistance,
      ]) {
        if (aAcces(role, page, ActionAccess.voir)) return '/admin';
      }
      return null;
    }

    // 1. Le tableau de bord mène à l'accueil de la boutique ; c'est la
    //    destination naturelle du propriétaire et du comptable (et non
    //    l'écran de vente, contrairement à l'ancienne logique binaire
    //    `vendor` / autre).
    if (aAcces(role, PageAccess.dashboard, ActionAccess.voir)) return '/main';

    // 2. Un caissier n'a que la caisse : il ouvre directement la vente.
    if (aAcces(role, PageAccess.caisse, ActionAccess.creer)) {
      return '/main/new-sale';
    }

    if (aAcces(role, PageAccess.ventes, ActionAccess.voir)) return '/main';
    if (aAcces(role, PageAccess.stock, ActionAccess.voir)) return '/main/stock';

    return null;
  }

  // ---------------------------------------------------------------------------
  // 7. MENU DYNAMIQUE
  // ---------------------------------------------------------------------------

  /// Entrées de menu d'un espace, limitées aux pages autorisées.
  ///
  /// Les libellés proviennent de [PageAccess.libelle] : une seule source de
  /// vérité, donc aucun risque d'afficher une entrée vers une page interdite.
  List<EntreeMenu> menuPour(RoleUtilisateur role, EspaceApplication espace) {
    final RolePermission permissions = permissionsDe(role);
    return getPagesAccessiblesDans(role, espace)
        .map((PageAccess page) => EntreeMenu(
              page: page,
              libelle: page.libelle,
              route: routesPage[page],
            ))
        .where((EntreeMenu entree) => permissions.aAcces(entree.page, ActionAccess.voir))
        .toList(growable: false);
  }

  /// Route principale d'une page (quand elle en a une).
  static const Map<PageAccess, String> routesPage = <PageAccess, String>{
    PageAccess.dashboard: '/main',
    PageAccess.ventes: '/main/ventes',
    // 💰 MODULE 10 — la page « Caisse / encaissement » mène à l'écran Caisse
    // (solde, historique, clôture) ; l'écran de vente reste '/main/new-sale'.
    PageAccess.caisse: '/main/caisse',
    PageAccess.stock: '/main/stock',
    PageAccess.clients: '/main/clients',
    PageAccess.depenses: '/main/depenses',
    PageAccess.articles: '/main/stock',
    // 📊 MODULE 11 — l'écran Rapports & exports (l'ancien `/reports` reste
    // le chemin de l'onglet, mais la route principale est `/main/rapports`).
    PageAccess.rapports: '/main/rapports',
    PageAccess.finance: '/main/finance',
    PageAccess.parametres: '/settings',
    PageAccess.collaborateurs: '/settings/manage-users',
    PageAccess.entreprises: '/admin',
    PageAccess.utilisateurs: '/admin',
    PageAccess.abonnements: '/admin',
    PageAccess.paiements: '/admin',
    // 🧾 MODULE 14 — écrans du workflow d'activation.
    PageAccess.verificationComptes: '/admin/verification-comptes',
    PageAccess.activationsFinance: '/admin/activations-finance',
    PageAccess.villes: '/admin',
    PageAccess.activites: '/admin',
    PageAccess.groupesTarifaires: '/admin',
    // 🔐 MODULE 12 — routes réelles du journal et de l'écran Sécurité
    // (l'import d'articles n'est pas une page de menu : bouton dédié).
    PageAccess.audit: '/audit',
    PageAccess.securite: '/securite',
    // 🤖 MODULE 13 — écran principal de l'assistant (le chat).
    PageAccess.assistantIa: '/assistant-ia',
    PageAccess.assistance: '/admin',
    PageAccess.notifications: '/admin',
    PageAccess.qrCodes: '/admin/qr-codes',
    PageAccess.scanner: '/scanner',
    PageAccess.panier: '/main/panier',
    PageAccess.fournisseurs: '/main/stock',
  };

  // ---------------------------------------------------------------------------
  // 8. ÉCRITURE DES SURCHARGES (écran Super Admin)
  // ---------------------------------------------------------------------------

  /// Enregistre les permissions personnalisées d'un rôle.
  ///
  /// Passe par la RPC `rpc_permissions_set` (réservée au SUPER_ADMIN côté
  /// serveur) ; en cas d'absence, l'écriture directe dans `app_settings` est
  /// tentée pour ne pas bloquer un déploiement intermédiaire.
  Future<void> enregistrerPermissions(
    RoleUtilisateur role,
    RolePermission permissions,
  ) async {
    if (role == RoleUtilisateur.inconnu) {
      throw const PermissionServiceException('Rôle inconnu : rien à enregistrer.');
    }

    final Map<String, dynamic> valeur = <String, dynamic>{
      'pages': permissions.toJson(),
    };

    try {
      await _client.rpc('rpc_permissions_set', params: <String, dynamic>{
        'p_role': role.code,
        'p_permissions': valeur,
      });
    } on PostgrestException catch (e) {
      if (!_rpcAbsente(e)) {
        throw PermissionServiceException(
          'Enregistrement refusé par le serveur : ${e.message}',
        );
      }
      await _ecrireDirectement(role, valeur);
    } catch (e) {
      throw PermissionServiceException(
        'Impossible d\'enregistrer les permissions (connexion ?) : $e',
      );
    }

    _surcharges[role] = permissions;
    _surchargesChargees = true;
  }

  /// Rétablit la matrice par défaut d'un rôle.
  Future<void> reinitialiserRole(RoleUtilisateur role) async {
    try {
      await _client.rpc('rpc_permissions_reset', params: <String, dynamic>{
        'p_role': role.code,
      });
    } on PostgrestException catch (e) {
      if (!_rpcAbsente(e)) {
        throw PermissionServiceException(
          'Réinitialisation refusée par le serveur : ${e.message}',
        );
      }
      // Repli : on retire le rôle du document puis on réécrit l'ensemble.
      final Map<String, dynamic> restantes = _surchargesDocument();
      restantes.remove(role.code);
      await _ecrireDocument(restantes);
    } catch (e) {
      throw PermissionServiceException(
        'Impossible de réinitialiser ce rôle (connexion ?) : $e',
      );
    }

    _surcharges.remove(role);
  }

  /// RPC absente / non déployée → on autorise le repli applicatif.
  static bool _rpcAbsente(PostgrestException e) =>
      e.code == 'PGRST202' || e.code == '42883' || e.message.contains('Could not find');

  Map<String, dynamic> _surchargesDocument() => <String, dynamic>{
        'roles': <String, dynamic>{
          for (final MapEntry<RoleUtilisateur, RolePermission> e
              in _surcharges.entries)
            e.key.code: e.value.toJson(),
        },
      };

  Future<void> _ecrireDirectement(
    RoleUtilisateur role,
    Map<String, dynamic> valeur,
  ) async {
    final Map<String, dynamic> document = _surchargesDocument();
    (document['roles'] as Map<String, dynamic>)[role.code] = valeur['pages'];
    await _ecrireDocument(document);
  }

  Future<void> _ecrireDocument(Map<String, dynamic> document) async {
    await _client.from('app_settings').upsert(<String, dynamic>{
      'key': cleAppSettings,
      'value': document,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'key');
  }
}
