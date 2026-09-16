// lib/models/audit.dart
//
// MODULE 12 — MODÈLES DU JOURNAL D'AUDIT ET DE LA SÉCURITÉ.
//
// Objets de valeur purs (aucun import Flutter, aucun accès réseau) : ils sont
// testables sans binding, comme `permission.dart`. Les données proviennent des
// RPC du module (`rpc_audit_lister`, `rpc_audit_verifier`,
// `rpc_securite_connexions`, `rpc_securite_alertes`).
//
// Rappels serveur :
//   • le journal est APPEND-ONLY : rien ne se modifie, rien ne s'efface ;
//   • l'IP et le User-Agent sont relevés côté serveur (jamais fournis par
//     l'application) ;
//   • le niveau (CRITIQUE / HAUT / MOYEN / INFO) est déduit de l'action par
//     `public.audit_niveau()`.

import 'package:biashara_yangu/utils/json_parsing.dart';

/// Niveau de gravité d'une entrée du journal (`public.audit_niveau`).
enum NiveauAudit {
  critique('CRITIQUE', 'Critique'),
  haut('HAUT', 'Haut'),
  moyen('MOYEN', 'Moyen'),
  info('INFO', 'Info');

  const NiveauAudit(this.code, this.libelle);

  /// Valeur stockée en base.
  final String code;

  /// Libellé affichable.
  final String libelle;

  /// Convertit un code SQL en niveau ; toute valeur inconnue devient [info].
  static NiveauAudit fromCode(String? code) {
    final String normalise = (code ?? '').trim().toUpperCase();
    for (final NiveauAudit niveau in values) {
      if (niveau.code == normalise) return niveau;
    }
    return NiveauAudit.info;
  }
}

/// Une entrée du journal d'audit.
class EntreeAudit {
  const EntreeAudit({
    required this.id,
    required this.seq,
    required this.utilisateurId,
    required this.utilisateur,
    required this.email,
    required this.entrepriseId,
    required this.action,
    required this.niveau,
    required this.details,
    required this.ipAddress,
    required this.userAgent,
    required this.createdAt,
  });

  final String id;

  /// Ordre total de la ligne (colonne `seq`, identity).
  final int seq;

  final String? utilisateurId;

  /// Nom affichable de l'auteur (nom, sinon email, sinon vide).
  final String utilisateur;

  final String? email;

  final String? entrepriseId;

  /// Code d'action (`VENTE`, `PRIX_MODIFIE`, `CONNEXION`…).
  final String action;

  final NiveauAudit niveau;

  /// Détails JSON (ancien/nouveau, montants, boutique…).
  final Map<String, dynamic> details;

  final String? ipAddress;
  final String? userAgent;
  final DateTime? createdAt;

  /// `true` si l'entrée a été écrite sans session (échec de connexion).
  bool get anonyme => utilisateurId == null;

  /// Libellé français de l'action.
  String get libelleAction => CatalogueAudit.libelle(action);

  static EntreeAudit? depuisJson(dynamic valeur) {
    final Map<String, dynamic>? map = parseMap(valeur);
    if (map == null) return null;

    return EntreeAudit(
      id: parseString(map['id']),
      seq: parseInt(map['seq']),
      utilisateurId: parseStringOrNull(map['utilisateur_id']),
      utilisateur: parseString(map['utilisateur']),
      email: parseStringOrNull(map['email']),
      entrepriseId: parseStringOrNull(map['entreprise_id']),
      action: parseString(map['action']),
      niveau: NiveauAudit.fromCode(parseStringOrNull(map['niveau'])),
      details: parseMap(map['details']) ?? const <String, dynamic>{},
      ipAddress: parseStringOrNull(map['ip_address']),
      userAgent: parseStringOrNull(map['user_agent']),
      createdAt: parseDateTimeOrNull(map['created_at']),
    );
  }
}

/// Page de résultats de `rpc_audit_lister`.
class PageAudit {
  const PageAudit({
    required this.lignes,
    required this.total,
    required this.limite,
    required this.offset,
    required this.portee,
  });

  final List<EntreeAudit> lignes;

  /// Nombre total d'entrées correspondant aux filtres (toutes pages).
  final int total;

  final int limite;
  final int offset;

  /// `plateforme` ou `entreprise` (portée effective calculée par le serveur).
  final String portee;

  static const PageAudit vide = PageAudit(
    lignes: <EntreeAudit>[],
    total: 0,
    limite: 50,
    offset: 0,
    portee: 'entreprise',
  );

  static PageAudit depuisRpc(dynamic reponse) {
    final Map<String, dynamic>? map = parseMap(reponse);
    if (map == null) return PageAudit.vide;

    return PageAudit(
      lignes: parseMapList(map['lignes'])
          .map(EntreeAudit.depuisJson)
          .whereType<EntreeAudit>()
          .toList(growable: false),
      total: parseInt(map['total']),
      limite: parseInt(map['limite'], fallback: 50),
      offset: parseInt(map['offset']),
      portee: parseString(map['portee'], fallback: 'entreprise'),
    );
  }
}

/// Résultat de `rpc_audit_verifier` (contrôle de la chaîne d'empreintes).
class VerificationAudit {
  const VerificationAudit({
    required this.verifie,
    required this.nbControle,
    required this.nbAnomalies,
    required this.premierSeq,
    required this.dernierSeq,
    required this.anomalies,
  });

  final bool verifie;
  final int nbControle;
  final int nbAnomalies;
  final int? premierSeq;
  final int? dernierSeq;
  final List<Map<String, dynamic>> anomalies;

  static VerificationAudit depuisRpc(dynamic reponse) {
    final Map<String, dynamic>? map = parseMap(reponse);
    if (map == null) {
      return const VerificationAudit(
        verifie: true,
        nbControle: 0,
        nbAnomalies: 0,
        premierSeq: null,
        dernierSeq: null,
        anomalies: <Map<String, dynamic>>[],
      );
    }

    return VerificationAudit(
      verifie: map['verifie'] == true,
      nbControle: parseInt(map['nb_controle']),
      nbAnomalies: parseInt(map['nb_anomalies']),
      premierSeq: map['premier_seq'] == null ? null : parseInt(map['premier_seq']),
      dernierSeq: map['dernier_seq'] == null ? null : parseInt(map['dernier_seq']),
      anomalies: parseMapList(map['anomalies']),
    );
  }
}

/// Ligne de connexion / déconnexion / échec (écran Sécurité).
class ConnexionAudit {
  const ConnexionAudit({
    required this.id,
    required this.action,
    required this.utilisateur,
    required this.email,
    required this.ipAddress,
    required this.userAgent,
    required this.details,
    required this.createdAt,
  });

  final String id;

  /// `CONNEXION`, `DECONNEXION` ou `CONNEXION_ECHEC`.
  final String action;

  final String utilisateur;
  final String? email;
  final String? ipAddress;
  final String? userAgent;
  final Map<String, dynamic> details;
  final DateTime? createdAt;

  static ConnexionAudit? depuisJson(dynamic valeur) {
    final Map<String, dynamic>? map = parseMap(valeur);
    if (map == null) return null;

    return ConnexionAudit(
      id: parseString(map['id']),
      action: parseString(map['action']),
      utilisateur: parseString(map['utilisateur']),
      email: parseStringOrNull(map['email']),
      ipAddress: parseStringOrNull(map['ip_address']),
      userAgent: parseStringOrNull(map['user_agent']),
      details: parseMap(map['details']) ?? const <String, dynamic>{},
      createdAt: parseDateTimeOrNull(map['created_at']),
    );
  }
}

/// Compteurs affichés en tête de l'écran Sécurité.
class ResumeConnexions {
  const ResumeConnexions({
    required this.reussies24h,
    required this.echecs24h,
    required this.deconnexions24h,
    required this.echecs7j,
    required this.comptesEchoues24h,
    required this.ipsEchouees24h,
  });

  final int reussies24h;
  final int echecs24h;
  final int deconnexions24h;
  final int echecs7j;
  final int comptesEchoues24h;
  final int ipsEchouees24h;

  static const ResumeConnexions vide = ResumeConnexions(
    reussies24h: 0,
    echecs24h: 0,
    deconnexions24h: 0,
    echecs7j: 0,
    comptesEchoues24h: 0,
    ipsEchouees24h: 0,
  );

  static ResumeConnexions depuisJson(dynamic valeur) {
    final Map<String, dynamic>? map = parseMap(valeur);
    if (map == null) return vide;

    return ResumeConnexions(
      reussies24h: parseInt(map['reussies_24h']),
      echecs24h: parseInt(map['echecs_24h']),
      deconnexions24h: parseInt(map['deconnexions_24h']),
      echecs7j: parseInt(map['echecs_7j']),
      comptesEchoues24h: parseInt(map['comptes_echoues_24h']),
      ipsEchouees24h: parseInt(map['ips_echouees_24h']),
    );
  }
}

/// Résultat de `rpc_securite_connexions`.
class ResultatConnexions {
  const ResultatConnexions({required this.lignes, required this.resume});

  final List<ConnexionAudit> lignes;
  final ResumeConnexions resume;

  static ResultatConnexions depuisRpc(dynamic reponse) {
    final Map<String, dynamic>? map = parseMap(reponse);
    if (map == null) {
      return const ResultatConnexions(
        lignes: <ConnexionAudit>[],
        resume: ResumeConnexions.vide,
      );
    }

    return ResultatConnexions(
      lignes: parseMapList(map['connexions'])
          .map(ConnexionAudit.depuisJson)
          .whereType<ConnexionAudit>()
          .toList(growable: false),
      resume: ResumeConnexions.depuisJson(map['resume']),
    );
  }
}

/// Alerte de sécurité calculée par `rpc_securite_alertes`.
class AlerteSecurite {
  const AlerteSecurite({
    required this.type,
    required this.gravite,
    required this.libelle,
    required this.email,
    required this.ip,
    required this.nombre,
    required this.derniere,
    required this.ips,
    required this.emails,
  });

  /// `TENTATIVES_ECHOUEES` ou `IP_SUSPECTE`.
  final String type;

  /// `HAUTE` ou `MOYENNE`.
  final String gravite;

  final String libelle;
  final String? email;
  final String? ip;
  final int nombre;
  final DateTime? derniere;
  final List<String> ips;
  final List<String> emails;

  static AlerteSecurite? depuisJson(dynamic valeur) {
    final Map<String, dynamic>? map = parseMap(valeur);
    if (map == null) return null;

    return AlerteSecurite(
      type: parseString(map['type']),
      gravite: parseString(map['gravite'], fallback: 'MOYENNE'),
      libelle: parseString(map['libelle']),
      email: parseStringOrNull(map['email']),
      ip: parseStringOrNull(map['ip']),
      nombre: parseInt(map['nombre']),
      derniere: parseDateTimeOrNull(map['derniere']),
      ips: _listeTextes(map['ips']),
      emails: _listeTextes(map['emails']),
    );
  }

  static List<String> _listeTextes(dynamic valeur) {
    if (valeur is! List) return const <String>[];
    return valeur
        .map((dynamic element) => element?.toString() ?? '')
        .where((String texte) => texte.isNotEmpty)
        .toList(growable: false);
  }
}

/// Résultat de `rpc_securite_alertes`.
class ResultatAlertes {
  const ResultatAlertes({
    required this.alertes,
    required this.echecs24h,
    required this.echecs7j,
    required this.connexions24h,
    required this.dernierEchec,
    required this.nbAlertes,
    required this.seuilEmail,
    required this.seuilIp,
    required this.fenetreHeures,
  });

  final List<AlerteSecurite> alertes;
  final int echecs24h;
  final int echecs7j;
  final int connexions24h;
  final DateTime? dernierEchec;
  final int nbAlertes;
  final int seuilEmail;
  final int seuilIp;
  final int fenetreHeures;

  static const ResultatAlertes vide = ResultatAlertes(
    alertes: <AlerteSecurite>[],
    echecs24h: 0,
    echecs7j: 0,
    connexions24h: 0,
    dernierEchec: null,
    nbAlertes: 0,
    seuilEmail: 3,
    seuilIp: 5,
    fenetreHeures: 24,
  );

  static ResultatAlertes depuisRpc(dynamic reponse) {
    final Map<String, dynamic>? map = parseMap(reponse);
    if (map == null) return vide;

    final Map<String, dynamic> resume = parseMap(map['resume']) ?? const <String, dynamic>{};
    final Map<String, dynamic> seuils = parseMap(map['seuils']) ?? const <String, dynamic>{};

    return ResultatAlertes(
      alertes: parseMapList(map['alertes'])
          .map(AlerteSecurite.depuisJson)
          .whereType<AlerteSecurite>()
          .toList(growable: false),
      echecs24h: parseInt(resume['echecs_24h']),
      echecs7j: parseInt(resume['echecs_7j']),
      connexions24h: parseInt(resume['connexions_24h']),
      dernierEchec: parseDateTimeOrNull(resume['dernier_echec']),
      nbAlertes: parseInt(resume['nb_alertes']),
      seuilEmail: parseInt(seuils['email'], fallback: 3),
      seuilIp: parseInt(seuils['ip'], fallback: 5),
      fenetreHeures: parseInt(seuils['fenetre_heures'], fallback: 24),
    );
  }
}

/// Catalogue des actions connues du journal (filtre + libellés).
///
/// Il reprend exactement la table `public.audit_niveau()` (côté serveur) pour
/// que l'écran propose des filtres pertinents — le serveur accepte néanmoins
/// n'importe quelle action (le filtre reste une simple égalité texte).
class CatalogueAudit {
  const CatalogueAudit._();

  /// Actions par niveau, dans l'ordre d'affichage du filtre.
  static const Map<String, List<String>> actionsParNiveau = <String, List<String>>{
    'CRITIQUE': <String>[
      'CREATION_ENTREPRISE',
      'CHANGEMENT_STATUT',
      'REACTIVATION',
      'CHANGEMENT_ROLE',
      'PERMISSIONS_MODIFIEES',
      'PERMISSIONS_REINITIALISEES',
      'PRIX_MODIFIE',
      'ANNULATION_VENTE',
      'VENTE_SUPPRIMEE',
      'UTILISATEUR_SUPPRIME',
      'ENTREPRISE_SUPPRIMEE',
    ],
    'HAUT': <String>[
      'VENTE',
      'PAIEMENT_ENREGISTRE',
      'PAIEMENT_DETTE',
      'DETTE',
      'DEPENSE',
      'CLOTURE_CAISSE',
      'APPROVISIONNEMENT',
      'AJUSTEMENT',
      'INVENTAIRE',
      'STOCK_MODIFIE',
      'ARTICLE_SUPPRIME',
      'CHANGEMENT_ACTIVATION',
      'IMPORT_PRODUITS',
    ],
    'MOYEN': <String>[
      'CONNEXION',
      'DECONNEXION',
      'CONNEXION_ECHEC',
      'ARTICLE_CREE',
      'ARTICLE_MODIFIE',
      'CONDITIONNEMENT_AJOUTE',
      'CONDITIONNEMENT_MODIFIE',
      'CONDITIONNEMENT_SUPPRIME',
      'UTILISATEUR_CREE',
      'UTILISATEUR_MODIFIE',
      'ENTREPRISE_MODIFIEE',
      'RELANCE_DETTE',
    ],
    'INFO': <String>[
      'RAPPORT',
    ],
  };

  /// Toutes les actions connues, aplaties.
  static List<String> get toutes => <String>[
        for (final List<String> actions in actionsParNiveau.values) ...actions,
      ];

  /// Libellé français d'une action ; une action inconnue est « humanisée »
  /// (`STOCK_MODIFIE` → `Stock modifie`), jamais rejetée.
  static String libelle(String? code) {
    final String action = (code ?? '').trim().toUpperCase();
    if (action.isEmpty) return 'Action inconnue';

    final String? connu = _libelles[action];
    if (connu != null) return connu;

    final String humanise = action
        .replaceAll('_', ' ')
        .toLowerCase()
        .trim();
    if (humanise.isEmpty) return action;
    return humanise[0].toUpperCase() + humanise.substring(1);
  }

  static const Map<String, String> _libelles = <String, String>{
    'CREATION_ENTREPRISE': 'Création d\'entreprise',
    'CHANGEMENT_STATUT': 'Changement de statut',
    'REACTIVATION': 'Réactivation',
    'CHANGEMENT_ROLE': 'Changement de rôle',
    'PERMISSIONS_MODIFIEES': 'Permissions modifiées',
    'PERMISSIONS_REINITIALISEES': 'Permissions réinitialisées',
    'PRIX_MODIFIE': 'Prix modifié',
    'ANNULATION_VENTE': 'Annulation de vente',
    'VENTE_SUPPRIMEE': 'Vente supprimée',
    'UTILISATEUR_SUPPRIME': 'Utilisateur supprimé',
    'ENTREPRISE_SUPPRIMEE': 'Entreprise supprimée',
    'VENTE': 'Vente',
    'PAIEMENT_ENREGISTRE': 'Paiement enregistré',
    'PAIEMENT_DETTE': 'Paiement de dette',
    'DETTE': 'Dette créée',
    'DEPENSE': 'Dépense',
    'CLOTURE_CAISSE': 'Clôture de caisse',
    'APPROVISIONNEMENT': 'Approvisionnement',
    'AJUSTEMENT': 'Ajustement de stock',
    'INVENTAIRE': 'Inventaire',
    'STOCK_MODIFIE': 'Stock modifié',
    'ARTICLE_SUPPRIME': 'Article supprimé',
    'CHANGEMENT_ACTIVATION': 'Activation / désactivation',
    'IMPORT_PRODUITS': 'Import d\'articles',
    'CONNEXION': 'Connexion',
    'DECONNEXION': 'Déconnexion',
    'CONNEXION_ECHEC': 'Échec de connexion',
    'ARTICLE_CREE': 'Article créé',
    'ARTICLE_MODIFIE': 'Article modifié',
    'CONDITIONNEMENT_AJOUTE': 'Conditionnement ajouté',
    'CONDITIONNEMENT_MODIFIE': 'Conditionnement modifié',
    'CONDITIONNEMENT_SUPPRIME': 'Conditionnement supprimé',
    'UTILISATEUR_CREE': 'Utilisateur créé',
    'UTILISATEUR_MODIFIE': 'Utilisateur modifié',
    'ENTREPRISE_MODIFIEE': 'Entreprise modifiée',
    'RELANCE_DETTE': 'Relance de dette',
    'RAPPORT': 'Rapport généré / exporté',
  };
}
