// lib/ui/parametres/catalogue_parametres.dart
//
// ⚙️ DES PARAMÈTRES QUI S'ADAPTENT.
//
// Un réglage n'est proposé que s'il a un sens pour CETTE entreprise :
//   • une boutique n'a rien à faire dans les réglages de distribution ;
//   • une activité sans pharmacie n'a pas besoin des lots/péremptions ;
//   • un vendeur ne voit pas les réglages du patron.
//
// Ce fichier est la SOURCE UNIQUE de cette décision. L'écran Paramètres ne
// fait que l'afficher : aucune condition métier n'est recopiée dans la page.
//
// ⚠️ RÈGLE D'OR (zéro régression) : tout est **fail-open**. Module inconnu,
//    profil non chargé, type d'activité non renseigné → le réglage reste
//    visible, exactement comme avant ce fichier.

import 'package:flutter/material.dart';

import 'package:biashara_yangu/l10n/app_localizations.dart';
import 'package:biashara_yangu/models/module_activite.dart';
import 'package:biashara_yangu/models/permission.dart';
import 'package:biashara_yangu/models/type_activite.dart';

/// Un réglage proposé au propriétaire (une entrée de menu).
class ParametreApp {
  const ParametreApp({
    required this.id,
    required this.section,
    required this.titre,
    required this.sousTitre,
    required this.icone,
    this.route,
    this.module,
    this.typeRequis,
    this.page,
    this.action = ActionAccess.voir,
    this.priorite = 50,
  });

  /// Identifiant stable (tests, clés, recherche).
  final String id;

  /// Regroupement affiché (traduit via [SectionParametres]).
  final String section;

  final String Function(AppLocalizations T) titre;
  final String Function(AppLocalizations T) sousTitre;
  final IconData icone;

  /// Route nommée à ouvrir (`null` = action gérée par l'écran).
  final String? route;

  /// Module requis (`null` = commun à toutes les activités).
  final String? module;

  /// Type d'entreprise requis (`null` = commun boutique/distribution).
  final TypeActivite? typeRequis;

  /// Permission requise (`null` = aucune).
  final PageAccess? page;
  final ActionAccess action;

  final int priorite;

  /// Ce réglage doit-il être proposé ?
  bool estVisible({
    required Set<String> modules,
    required bool profilCharge,
    required TypeActivite? typeActivite,
    required bool Function(PageAccess page, ActionAccess action) peut,
  }) {
    if (ReglesTypeActivite.masque(typeActivite, typeRequis)) return false;
    if (module != null &&
        !ReglesActivite.actif(modules, profilCharge, <String>{module!})) {
      return false;
    }
    if (page != null && !peut(page!, action)) return false;
    return true;
  }
}

/// Titres de sections et leur ordre d'affichage.
abstract final class SectionParametres {
  static const String compte = 'Compte';
  static const String equipe = "Gestion d'équipe";
  static const String entreprises = 'Mes entreprises';
  static const String abonnement = 'Abonnement';
  static const String boutique = 'Ma boutique';
  static const String distribution = 'Distribution';
  static const String vitrine = 'Ma vitrine Biashara';
  static const String resultats = 'Résultats Biashara';
  static const String apparence = 'Apparence';
  static const String application = 'Application';
  static const String legal = 'Informations légales';

  /// Ordre d'affichage des sections (une section vide n'est pas rendue).
  static const List<String> ordre = <String>[
    compte,
    equipe,
    entreprises,
    abonnement,
    boutique,
    distribution,
    vitrine,
    resultats,
    apparence,
    application,
    legal,
  ];
}

/// Le registre des réglages. Ajouter un réglage = ajouter une entrée ici.
abstract final class CatalogueParametres {
  static final List<ParametreApp> tous = <ParametreApp>[
    // ------------------------------------------------------------- Compte
    ParametreApp(
      id: 'profil',
      section: SectionParametres.compte,
      titre: (AppLocalizations T) => T.profileTitle,
      sousTitre: (AppLocalizations T) => T.profileSubtitle,
      icone: Icons.person_rounded,
      route: 'profile-edit',
      priorite: 10,
    ),
    ParametreApp(
      id: 'mot-de-passe',
      section: SectionParametres.compte,
      titre: (AppLocalizations T) => T.changePasswordTitle,
      sousTitre: (AppLocalizations T) => T.changePasswordSubtitle,
      icone: Icons.lock_rounded,
      route: 'password-change',
      priorite: 20,
    ),

    // -------------------------------------------------------------- Équipe
    ParametreApp(
      id: 'equipe',
      section: SectionParametres.equipe,
      titre: (AppLocalizations T) => 'Mes vendeurs',
      sousTitre: (AppLocalizations T) =>
          'Ajouter ou supprimer des collaborateurs',
      icone: Icons.badge_rounded,
      route: 'manage-users',
      page: PageAccess.collaborateurs,
      priorite: 10,
    ),

    // -------------------------------------------------------- Mes entreprises
    ParametreApp(
      id: 'mes-entreprises',
      section: SectionParametres.entreprises,
      titre: (AppLocalizations T) => 'Mes entreprises',
      sousTitre: (AppLocalizations T) =>
          'Boutique, hôtel, pharmacie… : créer, basculer, suivre le pack',
      icone: Icons.apartment_rounded,
      route: 'mes-entreprises',
      page: PageAccess.dashboard,
      priorite: 10,
    ),

    // ----------------------------------------------------------- Abonnement
    ParametreApp(
      id: 'factures-abonnement',
      section: SectionParametres.abonnement,
      titre: (AppLocalizations T) => "Mes factures d'abonnement",
      sousTitre: (AppLocalizations T) =>
          'Installation, mensuel, avances et reste à payer — chaque facture, '
          'avec son auteur',
      icone: Icons.description_rounded,
      route: 'factures-abonnement',
      page: PageAccess.facturesAbonnement,
      priorite: 10,
    ),
    ParametreApp(
      id: 'mon-activation',
      section: SectionParametres.abonnement,
      titre: (AppLocalizations T) => 'Mon abonnement',
      sousTitre: (AppLocalizations T) =>
          'Payer, renouveler, voir la date d\'échéance et les quotas IA',
      icone: Icons.verified_user_rounded,
      route: 'mon-activation',
      page: PageAccess.dashboard,
      priorite: 20,
    ),

    // ------------------------------------------------------------- Boutique
    ParametreApp(
      id: 'categories',
      section: SectionParametres.boutique,
      titre: (AppLocalizations T) => T.manageCategories,
      sousTitre: (AppLocalizations T) => T.manageCategoriesSubtitle,
      icone: Icons.category_rounded,
      route: 'manage-categories',
      module: ModuleCode.produits,
      priorite: 10,
    ),
    ParametreApp(
      id: 'devise',
      section: SectionParametres.boutique,
      titre: (AppLocalizations T) => 'Devise & conversion',
      sousTitre: (AppLocalizations T) =>
          'Devise de travail (CDF/USD) et taux de change 1 USD = X CDF',
      icone: Icons.currency_exchange_rounded,
      route: 'devise',
      priorite: 30,
    ),
    // 🛒 MODULE 25 — négociation, réductions et cadeaux : le propriétaire
    // décide de ce que ses collaborateurs peuvent accorder.
    ParametreApp(
      id: 'ventes-flexibles',
      section: SectionParametres.boutique,
      titre: (AppLocalizations T) => 'Ventes flexibles',
      sousTitre: (AppLocalizations T) =>
          'Négociation des prix, réductions sur le panier, cadeaux et rapports',
      icone: Icons.price_change_rounded,
      route: 'parametres-vente',
      page: PageAccess.caisse,
      action: ActionAccess.modifier,
      priorite: 20,
    ),

    // --------------------------------------------------------- Distribution
    ParametreApp(
      id: 'recipients',
      section: SectionParametres.distribution,
      titre: (AppLocalizations T) => 'Récipients & bonus',
      sousTitre: (AppLocalizations T) =>
          'Bidons, casiers, consignes et règles de bonus',
      icone: Icons.water_drop_rounded,
      route: 'recipients',
      typeRequis: TypeActivite.distribution,
      page: PageAccess.distribution,
      priorite: 10,
    ),
    ParametreApp(
      id: 'tournees',
      section: SectionParametres.distribution,
      titre: (AppLocalizations T) => 'Tournées & agents',
      sousTitre: (AppLocalizations T) =>
          'Dotations, objectifs, commissions et rapport par agent',
      icone: Icons.local_shipping_rounded,
      route: 'tournees',
      typeRequis: TypeActivite.distribution,
      page: PageAccess.distribution,
      priorite: 20,
    ),

    // -------------------------------------------------------------- Vitrine
    ParametreApp(
      id: 'ma-vitrine',
      section: SectionParametres.vitrine,
      titre: (AppLocalizations T) => 'Vitrine & localisation',
      sousTitre: (AppLocalizations T) =>
          'Position de la boutique, adresse, horaires et contacts publics',
      icone: Icons.storefront_rounded,
      route: 'ma-vitrine',
      page: PageAccess.publications,
      priorite: 10,
    ),
    ParametreApp(
      id: 'mes-publications',
      section: SectionParametres.vitrine,
      titre: (AppLocalizations T) => 'Mes publications',
      sousTitre: (AppLocalizations T) =>
          'Choisir les articles visibles dans le catalogue public',
      icone: Icons.checklist_rounded,
      route: 'mes-publications',
      page: PageAccess.publications,
      priorite: 20,
    ),

    // ------------------------------------------------------------- Résultats
    ParametreApp(
      id: 'ma-visibilite',
      section: SectionParametres.resultats,
      titre: (AppLocalizations T) => 'Ma visibilité Biashara',
      sousTitre: (AppLocalizations T) =>
          'Affichages, intérêt, itinéraires, appels et ventes attribuées',
      icone: Icons.insights_rounded,
      route: 'ma-visibilite',
      page: PageAccess.visibilite,
      priorite: 10,
    ),
    ParametreApp(
      id: 'publicites',
      section: SectionParametres.resultats,
      titre: (AppLocalizations T) => 'Publicités Biashara',
      sousTitre: (AppLocalizations T) =>
          'Promouvoir un produit, une promotion ou votre boutique',
      icone: Icons.campaign_rounded,
      route: 'publicites',
      page: PageAccess.publicites,
      priorite: 20,
    ),

    // ------------------------------------------------------------- Apparence
    // ----------------------------------------------------------- Application
    ParametreApp(
      id: 'assistant-ia',
      section: SectionParametres.application,
      titre: (AppLocalizations T) => 'Assistant IA',
      sousTitre: (AppLocalizations T) =>
          'Posez vos questions, l\'assistant agit selon vos droits',
      icone: Icons.smart_toy_rounded,
      route: 'assistant-ia',
      page: PageAccess.assistantIa,
      priorite: 10,
    ),
    ParametreApp(
      id: 'quotas-ia',
      section: SectionParametres.application,
      titre: (AppLocalizations T) => 'Quotas IA',
      sousTitre: (AppLocalizations T) =>
          'Packs, paiements suivis et attributions (patron)',
      icone: Icons.shopping_cart_checkout_rounded,
      route: 'achat-quotas',
      page: PageAccess.assistantIa,
      priorite: 20,
    ),
    ParametreApp(
      id: 'journal-audit',
      section: SectionParametres.application,
      titre: (AppLocalizations T) => 'Journal d\'audit',
      sousTitre: (AppLocalizations T) =>
          'Qui a fait quoi, quand — filtres, détail et export PDF signé',
      icone: Icons.history_edu_rounded,
      route: 'journal-audit',
      page: PageAccess.audit,
      priorite: 30,
    ),
    ParametreApp(
      id: 'import-articles',
      section: SectionParametres.application,
      titre: (AppLocalizations T) => 'Importer des articles',
      sousTitre: (AppLocalizations T) =>
          'Coller un contenu CSV ou choisir un fichier — tracé',
      icone: Icons.upload_file_rounded,
      route: 'import-produits',
      module: ModuleCode.produits,
      page: PageAccess.articles,
      action: ActionAccess.creer,
      priorite: 40,
    ),
    ParametreApp(
      id: 'guide',
      section: SectionParametres.application,
      titre: (AppLocalizations T) => 'Guide d\'utilisation',
      sousTitre: (AppLocalizations T) =>
          'Apprendre à utiliser Biashara Yangu pas à pas',
      icone: Icons.menu_book_rounded,
      route: 'guide-utilisation',
      priorite: 50,
    ),

    // ----------------------------------------------------------------- Légal
    ParametreApp(
      id: 'confidentialite',
      section: SectionParametres.legal,
      titre: (AppLocalizations T) => 'Politique de confidentialité',
      sousTitre: (AppLocalizations T) =>
          'Protection et traitement de vos données',
      icone: Icons.privacy_tip_outlined,
      route: 'politique-confidentialite',
      priorite: 10,
    ),
    ParametreApp(
      id: 'conditions',
      section: SectionParametres.legal,
      titre: (AppLocalizations T) => 'Conditions d\'utilisation',
      sousTitre: (AppLocalizations T) =>
          'Règles du service, abonnement et responsabilités',
      icone: Icons.gavel_rounded,
      route: 'conditions-utilisation',
      priorite: 20,
    ),
    ParametreApp(
      id: 'a-propos',
      section: SectionParametres.legal,
      titre: (AppLocalizations T) => T.settingsAboutTitle,
      sousTitre: (AppLocalizations T) => T.aboutAppDescription,
      icone: Icons.info_outline_rounded,
      route: 'about',
      priorite: 30,
    ),
  ];

  /// Tous les réglages visibles pour l'entreprise et le rôle courants,
  /// triés par section puis par priorité.
  static List<ParametreApp> visibles({
    required Set<String> modules,
    required bool profilCharge,
    required TypeActivite? typeActivite,
    required bool Function(PageAccess page, ActionAccess action) peut,
  }) {
    return tous
        .where((ParametreApp p) => p.estVisible(
              modules: modules,
              profilCharge: profilCharge,
              typeActivite: typeActivite,
              peut: peut,
            ))
        .toList(growable: false)
      ..sort((ParametreApp a, ParametreApp b) {
        final int sa = SectionParametres.ordre.indexOf(a.section);
        final int sb = SectionParametres.ordre.indexOf(b.section);
        if (sa != sb) return sa.compareTo(sb);
        return a.priorite.compareTo(b.priorite);
      });
  }

  /// Regroupe les réglages par section, dans l'ordre d'affichage.
  static Map<String, List<ParametreApp>> sections(List<ParametreApp> entrees) {
    final Map<String, List<ParametreApp>> resultat =
        <String, List<ParametreApp>>{};
    for (final String section in SectionParametres.ordre) {
      final List<ParametreApp> dedans = entrees
          .where((ParametreApp p) => p.section == section)
          .toList(growable: false);
      if (dedans.isNotEmpty) resultat[section] = dedans;
    }
    return resultat;
  }

  /// 🔎 RECHERCHE — le patron tape « devise » et trouve le réglage, même s'il
  /// ne sait pas dans quelle rubrique il se cache. Accents et casse ignorés.
  static List<ParametreApp> rechercher(
    String texte,
    List<ParametreApp> parmi,
    AppLocalizations T,
  ) {
    final String q = _normaliser(texte);
    if (q.isEmpty) return parmi;

    return parmi
        .where((ParametreApp p) =>
            _normaliser(p.titre(T)).contains(q) ||
            _normaliser(p.sousTitre(T)).contains(q) ||
            _normaliser(p.section).contains(q) ||
            _normaliser(p.id).contains(q))
        .toList(growable: false);
  }

  /// Minuscules sans accents (« Péremption » → « peremption »).
  static String _normaliser(String texte) {
    const String avec = 'àâäáãåçéèêëíìîïñóòôöõúùûüýÿ';
    const String sans = 'aaaaaaceeeeiiiinooooouuuuyy';
    final StringBuffer sb = StringBuffer();
    for (final int unit in texte.toLowerCase().runes) {
      final String c = String.fromCharCode(unit);
      final int i = avec.indexOf(c);
      sb.write(i >= 0 ? sans[i] : c);
    }
    return sb.toString().trim();
  }
}
