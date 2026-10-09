// lib/models/code_validation_agent.dart
//
// 🔐 CORRECTIF 69 — CODE DE VALIDATION DE L'AGENT.
// Table `public.codes_validation_agent` (migration 20260916000069).
//
// C'est un CONTRÔLE DE TRAÇABILITÉ, pas un verrou : si le code n'arrive pas
// dans les 5 minutes, l'agent continue — mais on saura, après coup, qui a
// ouvert ce compte et avec quelle autorisation.
//
// DEUX RÈGLES QUI VIENNENT DU SERVEUR ET QU'IL FAUT RESPECTER ICI :
//
//   1. `code` NE NOUS EST PAS TOUJOURS TRANSMIS. Le serveur ne le renvoie
//      qu'à la Finance et au Super Admin, parce que ce sont eux qui doivent le
//      TRANSMETTRE à l'agent. Si l'application affichait le code à l'agent, il
//      le lirait lui-même et le contrôle disparaîtrait. D'où `codeDisponible` :
//      l'écran ne doit jamais supposer que `code` est là.
//
//   2. Les fenêtres expirent. Le serveur calcule `minutesRestantes` : on
//      l'affiche tel quel plutôt que de recalculer l'heure sur l'appareil, qui
//      peut être mal réglé.

import 'package:biashara_yangu/utils/json_parsing.dart';

/// État d'une demande de code.
enum StatutCodeAgent {
  enAttente('EN_ATTENTE', 'En attente de la Finance'),
  emis('EMIS', 'Code émis'),
  utilise('UTILISE', 'Utilisé'),
  expire('EXPIRE', 'Expiré'),
  revoque('REVOQUE', 'Révoqué');

  const StatutCodeAgent(this.code, this.libelle);

  final String code;
  final String libelle;

  static StatutCodeAgent fromCode(String? code) {
    for (final StatutCodeAgent statut in values) {
      if (statut.code == code) return statut;
    }
    //  Un statut inconnu est traité comme « pas encore utilisable » : on
    //  n'affirme jamais qu'un code est bon sur un doute.
    return StatutCodeAgent.enAttente;
  }
}

/// Une demande de code, telle que la voient la Finance, le gestionnaire ou
/// l'agent.
class CodeValidationAgent {
  const CodeValidationAgent({
    required this.id,
    this.entrepriseId,
    this.entrepriseNom,
    this.motif,
    this.statut = StatutCodeAgent.enAttente,
    this.demandeParNom,
    this.demandeLe,
    this.emisLe,
    this.emisParNom,
    this.valideLe,
    this.valideParNom,
    this.expireLe,
    this.minutesRestantes = 0,
    this.code,
  });

  final String id;
  final String? entrepriseId;
  final String? entrepriseNom;
  final String? motif;

  final StatutCodeAgent statut;

  final String? demandeParNom;
  final DateTime? demandeLe;

  final DateTime? emisLe;
  final String? emisParNom;

  final DateTime? valideLe;
  final String? valideParNom;

  final DateTime? expireLe;

  /// Minutes restantes, calculées par le SERVEUR (l'horloge de l'appareil
  /// peut être fausse).
  final int minutesRestantes;

  /// Le code lui-même — `null` quand le serveur ne nous l'a pas transmis
  /// (l'agent ne doit jamais le voir).
  final String? code;

  static CodeValidationAgent? depuisJson(dynamic valeur) {
    final Map<String, dynamic>? map = parseMap(valeur);
    if (map == null) return null;

    final String id = parseString(map['id']);
    if (id.isEmpty) return null;

    return CodeValidationAgent(
      id: id,
      entrepriseId: parseStringOrNull(map['entreprise_id']),
      entrepriseNom: parseStringOrNull(map['entreprise_nom']),
      motif: parseStringOrNull(map['motif']),
      statut: StatutCodeAgent.fromCode(parseStringOrNull(map['statut'])),
      demandeParNom: parseStringOrNull(map['demande_par_nom']),
      demandeLe: parseDateTimeOrNull(map['demande_le']),
      emisLe: parseDateTimeOrNull(map['emis_le']),
      emisParNom: parseStringOrNull(map['emis_par_nom']),
      valideLe: parseDateTimeOrNull(map['valide_le']),
      valideParNom: parseStringOrNull(map['valide_par_nom']),
      expireLe: parseDateTimeOrNull(map['expire_le']),
      minutesRestantes: parseInt(map['minutes_restantes']),
      code: parseStringOrNull(map['code']),
    );
  }

  static List<CodeValidationAgent> listeDepuisJson(dynamic valeur) {
    final List<CodeValidationAgent> liste = <CodeValidationAgent>[];

    for (final Map<String, dynamic> ligne in parseMapList(valeur)) {
      final CodeValidationAgent? c = depuisJson(ligne);
      if (c != null) liste.add(c);
    }

    return liste;
  }

  // ---------------------------------------------------------------------------
  // LECTURES PURES — testables sans réseau
  // ---------------------------------------------------------------------------

  /// Vrai si la demande attend encore une action (émission ou saisie).
  bool get estOuverte =>
      statut == StatutCodeAgent.enAttente || statut == StatutCodeAgent.emis;

  /// Vrai si la Finance peut encore émettre (ou réémettre) un code.
  bool get peutEtreEmise =>
      statut == StatutCodeAgent.enAttente || statut == StatutCodeAgent.emis;

  /// Vrai si l'agent peut saisir un code : un code doit avoir été émis et la
  /// fenêtre ne doit pas être écoulée.
  bool get peutEtreSaisi =>
      statut == StatutCodeAgent.emis && minutesRestantes > 0;

  /// Le serveur nous a-t-il transmis le code ? (Finance et Super Admin seulement.)
  bool get codeDisponible => (code ?? '').trim().isNotEmpty;

  /// Vrai si la fenêtre des 5 minutes est écoulée.
  ///
  /// C'est CETTE information qui déclenche la règle du patron : passé ce
  /// délai, l'agent peut continuer et la Finance confirmera après coup.
  bool get delaiEcoule => estOuverte && minutesRestantes <= 0;

  /// L'agent peut-il poursuivre sans code ?
  ///
  /// Oui — toujours. Le dispositif n'est pas un verrou : le laisser croire
  /// ferait perdre du temps sur le terrain pour rien.
  bool get peutContinuerSansCode => delaiEcoule;

  /// Nom du compte visé, jamais vide.
  String get nomAffiche {
    final String nom = (entrepriseNom ?? '').trim();
    return nom.isEmpty ? 'Compte sans nom' : nom;
  }

  /// Motif de la demande, ou une valeur de repli honnête.
  String get motifAffiche {
    final String texte = (motif ?? '').trim();
    return texte.isEmpty ? 'Non précisé' : texte;
  }

  /// « demandé par X il y a … ».
  String get resumeDemande {
    final String qui = (demandeParNom ?? '').trim();
    final String auteur = qui.isEmpty ? 'Auteur inconnu' : qui;
    return '$auteur — ${_date(demandeLe)}';
  }

  /// « émis par Y le … » (ou l'attente).
  String get resumeEmission {
    if (emisLe == null) return 'Pas encore émis par la Finance';
    final String qui = (emisParNom ?? '').trim();
    final String auteur = qui.isEmpty ? 'auteur inconnu' : qui;
    return 'Émis par $auteur le ${_date(emisLe)}';
  }

  /// « utilisé par Z le … » (ou l'attente).
  String get resumeValidation {
    if (valideLe == null) return 'Pas encore saisi';
    final String qui = (valideParNom ?? '').trim();
    final String auteur = qui.isEmpty ? 'auteur inconnu' : qui;
    return 'Saisi par $auteur le ${_date(valideLe)}';
  }

  /// Compte à rebours lisible.
  String get libelleDelai {
    if (!estOuverte) return '';
    if (minutesRestantes <= 0) return 'délai écoulé';
    return '$minutesRestantes min restantes';
  }

  static String _date(DateTime? moment) {
    if (moment == null) return 'date inconnue';
    final DateTime local = moment.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/'
        '${local.year} à '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}

/// Résultat de `rpc_agent_code_demander`.
class DemandeCodeAgent {
  const DemandeCodeAgent({
    required this.demandeId,
    this.statut = StatutCodeAgent.enAttente,
    this.expireLe,
    this.dejaOuverte = false,
    this.codeEmis = false,
  });

  final String demandeId;
  final StatutCodeAgent statut;
  final DateTime? expireLe;

  /// Une demande était déjà ouverte : on n'en a pas créé une seconde.
  final bool dejaOuverte;

  /// Un code a déjà été émis pour cette demande.
  final bool codeEmis;

  static DemandeCodeAgent? depuisJson(dynamic valeur) {
    final Map<String, dynamic>? map = parseMap(valeur);
    if (map == null) return null;

    final String id = parseString(map['demande_id']);
    if (id.isEmpty) return null;

    return DemandeCodeAgent(
      demandeId: id,
      statut: StatutCodeAgent.fromCode(parseStringOrNull(map['statut'])),
      expireLe: parseDateTimeOrNull(map['expire_le']),
      dejaOuverte: map['deja_ouverte'] == true,
      codeEmis: map['code_emis'] == true,
    );
  }
}

/// Résultat de `rpc_agent_code_emettre` — le code, à transmettre à l'agent.
class EmissionCodeAgent {
  const EmissionCodeAgent({required this.demandeId, required this.code, this.expireLe});

  final String demandeId;
  final String code;
  final DateTime? expireLe;

  static EmissionCodeAgent? depuisJson(dynamic valeur) {
    final Map<String, dynamic>? map = parseMap(valeur);
    if (map == null) return null;

    //  ⚠️ `parseString` ne rogne PAS les espaces : sans le `trim()` ci-dessous,
    //  un code réduit à des blancs passerait pour valide et la Finance
    //  afficherait un cadre vide en croyant avoir un code à transmettre.
    final String code = parseString(map['code']).trim();
    if (code.isEmpty) return null;

    return EmissionCodeAgent(
      demandeId: parseString(map['demande_id']).trim(),
      code: code,
      expireLe: parseDateTimeOrNull(map['expire_le']),
    );
  }
}

/// Un dossier vérifié SANS code validé : c'est ce que la Finance doit
/// confirmer après coup.
class DossierSansCode {
  const DossierSansCode({
    required this.entrepriseId,
    this.nom = 'Compte sans nom',
    this.etape = '',
    this.statut = '',
    this.verifieParNom,
    this.verifieLe,
    this.aDemandeUnCode = false,
    this.demandeEnAttente = false,
  });

  final String entrepriseId;
  final String nom;
  final String etape;
  final String statut;
  final String? verifieParNom;
  final DateTime? verifieLe;

  /// Une demande a-t-elle au moins été faite par l'agent ?
  final bool aDemandeUnCode;

  /// Une demande attend-elle encore une réponse de la Finance ?
  final bool demandeEnAttente;

  static DossierSansCode? depuisJson(dynamic valeur) {
    final Map<String, dynamic>? map = parseMap(valeur);
    if (map == null) return null;

    final String id = parseString(map['entreprise_id']);
    if (id.isEmpty) return null;

    return DossierSansCode(
      entrepriseId: id,
      nom: parseString(map['nom'], fallback: 'Compte sans nom'),
      etape: parseString(map['etape']),
      statut: parseString(map['statut']),
      verifieParNom: parseStringOrNull(map['verifie_par_nom']),
      verifieLe: parseDateTimeOrNull(map['verifie_le']),
      aDemandeUnCode: map['a_demande_un_code'] == true,
      demandeEnAttente: map['demande_en_attente'] == true,
    );
  }

  /// Nom affichable. Le serveur renvoie déjà `null` pour un nom vide, mais on
  /// ne s'y fie pas : une chaîne d'espaces donnerait une ligne muette dans la
  /// liste des dossiers à confirmer.
  String get nomAffiche {
    final String texte = nom.trim();
    return texte.isEmpty ? 'Compte sans nom' : texte;
  }

  /// QUI doit agir, en clair.
  ///
  /// C'est la distinction la plus utile pour la Finance : « l'agent n'a rien
  /// demandé » et « la Finance n'a pas répondu » sont deux responsabilités
  /// différentes, et les confondre rendrait la liste inexploitable.
  String get responsabilite {
    if (demandeEnAttente) return 'La Finance n\'a pas encore répondu';
    if (aDemandeUnCode) return 'Code jamais saisi — à vérifier';
    return 'Aucun code demandé par l\'agent';
  }
}

/// La liste renvoyée par `rpc_agent_dossiers_sans_code`.
class DossiersSansCode {
  const DossiersSansCode({this.total = 0, this.dossiers = const <DossierSansCode>[]});

  final int total;
  final List<DossierSansCode> dossiers;

  static const DossiersSansCode vide = DossiersSansCode();

  bool get estVide => total <= 0 && dossiers.isEmpty;

  static DossiersSansCode depuisJson(dynamic valeur) {
    final Map<String, dynamic>? map = parseMap(valeur);
    if (map == null) return vide;

    final List<DossierSansCode> liste = <DossierSansCode>[];
    for (final Map<String, dynamic> ligne in parseMapList(map['dossiers'])) {
      final DossierSansCode? d = DossierSansCode.depuisJson(ligne);
      if (d != null) liste.add(d);
    }

    final int total = parseInt(map['total']);
    return DossiersSansCode(
      total: total > 0 ? total : liste.length,
      dossiers: liste,
    );
  }
}
