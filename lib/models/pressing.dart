// lib/models/pressing.dart
//
// 🧺 MODULE 35 — PRESSING & BLANCHISSERIE : LE MODÈLE MÉTIER.
//
// PRINCIPE QUI COMMANDE TOUT CE FICHIER
//   Un pressing ne vend pas des marchandises : il REÇOIT des vêtements qui
//   appartiennent à ses clients, en prend la responsabilité, les traite un
//   par un, et doit pouvoir prouver leur restitution.
//
//   ⇒ Une commande n'est PAS un ticket de caisse : c'est un DOSSIER.
//   ⇒ Un vêtement n'est PAS une ligne de produit : c'est une LIGNE DE DOSSIER
//     avec son état au dépôt, ses défauts constatés, son étape de traitement
//     et sa remise.
//   ⇒ « Facturé » et « encaissé » sont DEUX montants distincts, jamais
//     confondus à l'écran.
//
// Aucune valeur n'est inventée : un champ absent reste vide, un montant
// inconnu vaut 0, et les erreurs viennent du serveur (déjà en français).

import 'package:biashara_yangu/utils/json_parsing.dart';

// ============================================================================
//  STATUTS
// ============================================================================

/// État global d'un dossier de dépôt (calculé par le serveur à partir des
/// lignes : 3 prêts / 2 en repassage ⇒ la commande n'est PAS prête).
enum StatutCommandePressing {
  enTraitement('EN_TRAITEMENT', 'En traitement'),
  prete('PRETE', 'Prête à récupérer'),
  partiellementRemise('PARTIELLEMENT_REMISE', 'Partiellement remise'),
  remise('REMISE', 'Entièrement remise'),
  annulee('ANNULEE', 'Annulée');

  const StatutCommandePressing(this.code, this.libelle);

  final String code;
  final String libelle;

  static StatutCommandePressing fromCode(String? code) {
    final String c = (code ?? '').trim().toUpperCase();
    for (final StatutCommandePressing s in values) {
      if (s.code == c) return s;
    }
    return StatutCommandePressing.enTraitement;
  }

  bool get estClose =>
      this == StatutCommandePressing.remise ||
      this == StatutCommandePressing.annulee;
}

// ============================================================================
//  RÉGLAGES
// ============================================================================

/// Réglages du pressing (une ligne par entreprise, créée à la demande).
class PressingConfig {
  const PressingConfig({
    this.devise = 'CDF',
    this.delaiStandardJours = 3,
    this.supplementUrgence = 0,
    this.politiqueRemise = 'SOLDE_OBLIGATOIRE',
    this.collecteActive = false,
    this.fraisCollecte = 0,
    this.fideliteActive = false,
    this.fideliteSeuil = 0,
    this.fideliteRemisePct = 0,
    this.notifyDepot = true,
    this.notifyPret = true,
    this.notifyRetard = true,
    this.notifyPaiement = true,
  });

  final String devise;
  final int delaiStandardJours;
  final double supplementUrgence;

  /// `SOLDE_OBLIGATOIRE` = le solde doit être réglé avant la remise finale ;
  /// `REMISE_POSSIBLE` = le propriétaire autorise une remise avec dette.
  final String politiqueRemise;

  final bool collecteActive;
  final double fraisCollecte;
  final bool fideliteActive;
  final double fideliteSeuil;
  final double fideliteRemisePct;
  final bool notifyDepot;
  final bool notifyPret;
  final bool notifyRetard;
  final bool notifyPaiement;

  bool get soldeObligatoire => politiqueRemise == 'SOLDE_OBLIGATOIRE';

  static const PressingConfig defaut = PressingConfig();

  factory PressingConfig.fromMap(Map<String, dynamic> map) {
    return PressingConfig(
      devise: parseString(map['devise'], fallback: 'CDF'),
      delaiStandardJours: parseInt(map['delai_standard_jours'], fallback: 3),
      supplementUrgence: parseDouble(map['supplement_urgence']),
      politiqueRemise: parseString(
        map['politique_remise'],
        fallback: 'SOLDE_OBLIGATOIRE',
      ),
      collecteActive: parseBool(map['collecte_active']),
      fraisCollecte: parseDouble(map['frais_collecte']),
      fideliteActive: parseBool(map['fidelite_active']),
      fideliteSeuil: parseDouble(map['fidelite_seuil']),
      fideliteRemisePct: parseDouble(map['fidelite_remise_pct']),
      notifyDepot: parseBool(map['notify_depot'], fallback: true),
      notifyPret: parseBool(map['notify_pret'], fallback: true),
      notifyRetard: parseBool(map['notify_retard'], fallback: true),
      notifyPaiement: parseBool(map['notify_paiement'], fallback: true),
    );
  }

  Map<String, dynamic> toRpc() => <String, dynamic>{
        'devise': devise,
        'delai_standard_jours': delaiStandardJours,
        'supplement_urgence': supplementUrgence,
        'politique_remise': politiqueRemise,
        'collecte_active': collecteActive,
        'frais_collecte': fraisCollecte,
        'fidelite_active': fideliteActive,
        'fidelite_seuil': fideliteSeuil,
        'fidelite_remise_pct': fideliteRemisePct,
        'notify_depot': notifyDepot,
        'notify_pret': notifyPret,
        'notify_retard': notifyRetard,
        'notify_paiement': notifyPaiement,
      };

  PressingConfig copyWith({
    String? devise,
    int? delaiStandardJours,
    double? supplementUrgence,
    String? politiqueRemise,
    bool? collecteActive,
    double? fraisCollecte,
    bool? fideliteActive,
    double? fideliteSeuil,
    double? fideliteRemisePct,
    bool? notifyDepot,
    bool? notifyPret,
    bool? notifyRetard,
    bool? notifyPaiement,
  }) {
    return PressingConfig(
      devise: devise ?? this.devise,
      delaiStandardJours: delaiStandardJours ?? this.delaiStandardJours,
      supplementUrgence: supplementUrgence ?? this.supplementUrgence,
      politiqueRemise: politiqueRemise ?? this.politiqueRemise,
      collecteActive: collecteActive ?? this.collecteActive,
      fraisCollecte: fraisCollecte ?? this.fraisCollecte,
      fideliteActive: fideliteActive ?? this.fideliteActive,
      fideliteSeuil: fideliteSeuil ?? this.fideliteSeuil,
      fideliteRemisePct: fideliteRemisePct ?? this.fideliteRemisePct,
      notifyDepot: notifyDepot ?? this.notifyDepot,
      notifyPret: notifyPret ?? this.notifyPret,
      notifyRetard: notifyRetard ?? this.notifyRetard,
      notifyPaiement: notifyPaiement ?? this.notifyPaiement,
    );
  }
}

// ============================================================================
//  CATALOGUE
// ============================================================================

/// Type de vêtement (chemise, costume, couverture…) — propre à chaque pressing.
class PressingCategorie {
  const PressingCategorie({
    required this.id,
    required this.nom,
    this.ordre = 100,
    this.actif = true,
  });

  final String id;
  final String nom;
  final int ordre;
  final bool actif;

  factory PressingCategorie.fromMap(Map<String, dynamic> map) {
    return PressingCategorie(
      id: parseString(map['id']),
      nom: parseString(map['nom']),
      ordre: parseInt(map['ordre'], fallback: 100),
      actif: parseBool(map['actif'], fallback: true),
    );
  }
}

/// Prestation facturable (lavage, repassage, détachage, express…).
class PressingPrestation {
  const PressingPrestation({
    required this.id,
    required this.nom,
    this.description,
    this.dureeHeures = 24,
    this.delaiJours = 3,
    this.supplementUrgence = 0,
    this.actif = true,
  });

  final String id;
  final String nom;
  final String? description;
  final int dureeHeures;
  final int delaiJours;
  final double supplementUrgence;
  final bool actif;

  factory PressingPrestation.fromMap(Map<String, dynamic> map) {
    return PressingPrestation(
      id: parseString(map['id']),
      nom: parseString(map['nom']),
      description: parseStringOrNull(map['description']),
      dureeHeures: parseInt(map['duree_heures'], fallback: 24),
      delaiJours: parseInt(map['delai_jours'], fallback: 3),
      supplementUrgence: parseDouble(map['supplement_urgence']),
      actif: parseBool(map['actif'], fallback: true),
    );
  }
}

/// Prix d'une prestation pour un type de vêtement.
/// `categorieId == null` = tarif par défaut de la prestation.
class PressingTarif {
  const PressingTarif({
    required this.id,
    required this.prestationId,
    this.categorieId,
    this.prix = 0,
    this.actif = true,
  });

  final String id;
  final String prestationId;
  final String? categorieId;
  final double prix;
  final bool actif;

  factory PressingTarif.fromMap(Map<String, dynamic> map) {
    return PressingTarif(
      id: parseString(map['id']),
      prestationId: parseString(map['prestation_id']),
      categorieId: parseStringOrNull(map['categorie_id']),
      prix: parseDouble(map['prix']),
      actif: parseBool(map['actif'], fallback: true),
    );
  }
}

/// Le catalogue complet d'un pressing.
class PressingCatalogue {
  const PressingCatalogue({
    this.categories = const <PressingCategorie>[],
    this.prestations = const <PressingPrestation>[],
    this.tarifs = const <PressingTarif>[],
  });

  final List<PressingCategorie> categories;
  final List<PressingPrestation> prestations;
  final List<PressingTarif> tarifs;

  bool get estVide => categories.isEmpty && prestations.isEmpty;

  /// Prix applicable : le tarif du type de vêtement s'il existe, sinon le
  /// tarif par défaut. `null` = aucun prix défini (l'agent devra le saisir).
  double? prixPour(String prestationId, String? categorieId) {
    PressingTarif? defaut;
    for (final PressingTarif t in tarifs) {
      if (!t.actif || t.prestationId != prestationId) continue;
      if (categorieId != null && t.categorieId == categorieId) return t.prix;
      if (t.categorieId == null) defaut = t;
    }
    return defaut?.prix;
  }

  PressingCategorie? categorieParId(String? id) {
    if (id == null) return null;
    for (final PressingCategorie c in categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  PressingPrestation? prestationParId(String? id) {
    if (id == null) return null;
    for (final PressingPrestation p in prestations) {
      if (p.id == id) return p;
    }
    return null;
  }

  factory PressingCatalogue.fromMap(Map<String, dynamic> map) {
    return PressingCatalogue(
      categories: parseMapList(map['categories'])
          .map(PressingCategorie.fromMap)
          .toList(growable: false),
      prestations: parseMapList(map['prestations'])
          .map(PressingPrestation.fromMap)
          .toList(growable: false),
      tarifs: parseMapList(map['tarifs'])
          .map(PressingTarif.fromMap)
          .toList(growable: false),
    );
  }
}

/// Étape du pipeline de traitement (personnalisable par le propriétaire).
class PressingEtape {
  const PressingEtape({
    required this.id,
    required this.code,
    required this.libelle,
    this.ordre = 100,
    this.estFinale = false,
    this.actif = true,
  });

  final String id;
  final String code;
  final String libelle;
  final int ordre;

  /// Étape qui rend le vêtement remis­able (PRÊT par défaut).
  final bool estFinale;
  final bool actif;

  factory PressingEtape.fromMap(Map<String, dynamic> map) {
    return PressingEtape(
      id: parseString(map['id']),
      code: parseString(map['code']),
      libelle: parseString(map['libelle']),
      ordre: parseInt(map['ordre'], fallback: 100),
      estFinale: parseBool(map['est_finale']),
      actif: parseBool(map['actif'], fallback: true),
    );
  }
}

// ============================================================================
//  CLIENTS
// ============================================================================

/// Client d'un pressing. Table séparée de `clients` (boutiques) : un client de
/// pressing a des vêtements en garde, pas des achats.
class PressingClient {
  const PressingClient({
    required this.id,
    required this.nom,
    this.telephone,
    this.adresse,
    this.email,
    this.notes,
    this.derniereActivite,
    this.createdAt,
  });

  final String id;
  final String nom;
  final String? telephone;
  final String? adresse;
  final String? email;
  final String? notes;
  final DateTime? derniereActivite;
  final DateTime? createdAt;

  /// « Mama Sarah · +243 990… » — pour les listes.
  String get sousTitre {
    final List<String> morceaux = <String>[
      if ((telephone ?? '').trim().isNotEmpty) telephone!.trim(),
      if ((adresse ?? '').trim().isNotEmpty) adresse!.trim(),
    ];
    return morceaux.join(' · ');
  }

  factory PressingClient.fromMap(Map<String, dynamic> map) {
    return PressingClient(
      id: parseString(map['id']),
      nom: parseString(map['nom']),
      telephone: parseStringOrNull(map['telephone']),
      adresse: parseStringOrNull(map['adresse']),
      email: parseStringOrNull(map['email']),
      notes: parseStringOrNull(map['notes']),
      derniereActivite: parseDateTimeOrNull(map['derniere_activite']),
      createdAt: parseDateTimeOrNull(map['created_at']),
    );
  }
}

// ============================================================================
//  VÊTEMENTS ET COMMANDES
// ============================================================================

/// Un vêtement déposé (ou un lot identique : 3 serviettes).
class PressingLigne {
  const PressingLigne({
    required this.id,
    this.position = 1,
    this.categorieId,
    this.categorieNom,
    this.prestationId,
    this.prestationNom,
    this.designation,
    this.marque,
    this.couleur,
    this.matiere,
    this.taille,
    this.etatDepot,
    this.defauts,
    this.accessoires,
    this.observations,
    this.photos = const <String>[],
    this.quantite = 1,
    this.prixUnitaire = 0,
    this.prix = 0,
    this.etapeCode = 'DEPOSE',
    this.etapeLibelle,
    this.estPrete = false,
    this.debutTraitement,
    this.finTraitement,
    this.controleOk,
    this.controleLe,
    this.controleNote,
    this.remisLe,
    this.remisPar,
  });

  final String id;
  final int position;
  final String? categorieId;
  final String? categorieNom;
  final String? prestationId;
  final String? prestationNom;
  final String? designation;
  final String? marque;
  final String? couleur;
  final String? matiere;
  final String? taille;
  final String? etatDepot;
  final String? defauts;
  final String? accessoires;
  final String? observations;
  final List<String> photos;
  final double quantite;
  final double prixUnitaire;
  final double prix;
  final String etapeCode;
  final String? etapeLibelle;
  final bool estPrete;
  final DateTime? debutTraitement;
  final DateTime? finTraitement;
  final bool? controleOk;
  final DateTime? controleLe;
  final String? controleNote;
  final DateTime? remisLe;
  final String? remisPar;

  bool get estRemis => remisLe != null;

  /// « 3 · Chemise (Lavage et repassage) ».
  String get titre {
    final String nom = (designation ?? '').trim().isNotEmpty
        ? designation!.trim()
        : (categorieNom ?? 'Vêtement');
    final String prest =
        (prestationNom ?? '').trim().isEmpty ? '' : ' ($prestationNom)';
    return '$position · $nom$prest';
  }

  /// Détails utiles à l'agent : couleur, taille, marque.
  String get details {
    final List<String> morceaux = <String>[
      if ((marque ?? '').trim().isNotEmpty) marque!.trim(),
      if ((couleur ?? '').trim().isNotEmpty) couleur!.trim(),
      if ((taille ?? '').trim().isNotEmpty) 'taille ${taille!.trim()}',
      if ((matiere ?? '').trim().isNotEmpty) matiere!.trim(),
    ];
    return morceaux.join(' · ');
  }

  bool get aDefauts => (defauts ?? '').trim().isNotEmpty;

  factory PressingLigne.fromMap(Map<String, dynamic> map) {
    final List<String> photos = <String>[];
    final dynamic brutPhotos = map['photos'];
    if (brutPhotos is List) {
      for (final dynamic p in brutPhotos) {
        final String url = p?.toString() ?? '';
        if (url.trim().isNotEmpty) photos.add(url);
      }
    }

    return PressingLigne(
      id: parseString(map['id']),
      position: parseInt(map['position'], fallback: 1),
      categorieId: parseStringOrNull(map['categorie_id']),
      categorieNom: parseStringOrNull(map['categorie_nom']),
      prestationId: parseStringOrNull(map['prestation_id']),
      prestationNom: parseStringOrNull(map['prestation_nom']),
      designation: parseStringOrNull(map['designation']),
      marque: parseStringOrNull(map['marque']),
      couleur: parseStringOrNull(map['couleur']),
      matiere: parseStringOrNull(map['matiere']),
      taille: parseStringOrNull(map['taille']),
      etatDepot: parseStringOrNull(map['etat_depot']),
      defauts: parseStringOrNull(map['defauts']),
      accessoires: parseStringOrNull(map['accessoires']),
      observations: parseStringOrNull(map['observations']),
      photos: photos,
      quantite: parseDouble(map['quantite'], fallback: 1),
      prixUnitaire: parseDouble(map['prix_unitaire']),
      prix: parseDouble(map['prix']),
      etapeCode: parseString(map['etape_code'], fallback: 'DEPOSE'),
      etapeLibelle: parseStringOrNull(map['etape_libelle']),
      estPrete: parseBool(map['est_prete']),
      debutTraitement: parseDateTimeOrNull(map['debut_traitement']),
      finTraitement: parseDateTimeOrNull(map['fin_traitement']),
      controleOk: map['controle_ok'] is bool
          ? map['controle_ok'] as bool
          : null,
      controleLe: parseDateTimeOrNull(map['controle_le']),
      controleNote: parseStringOrNull(map['controle_note']),
      remisLe: parseDateTimeOrNull(map['remis_le']),
      remisPar: parseStringOrNull(map['remis_par']),
    );
  }
}

/// Un versement encaissé sur une commande.
class PressingPaiement {
  const PressingPaiement({
    required this.id,
    this.montant = 0,
    this.mode = 'especes',
    this.reference,
    this.encaisseLe,
    this.annuleLe,
    this.motifAnnulation,
  });

  final String id;
  final double montant;
  final String mode;
  final String? reference;
  final DateTime? encaisseLe;
  final DateTime? annuleLe;
  final String? motifAnnulation;

  bool get estAnnule => annuleLe != null;

  String get libelleMode {
    switch (mode) {
      case 'especes':
        return 'Espèces';
      case 'mobile_money':
        return 'Mobile Money';
      case 'carte':
        return 'Carte';
      default:
        return mode;
    }
  }

  factory PressingPaiement.fromMap(Map<String, dynamic> map) {
    return PressingPaiement(
      id: parseString(map['id']),
      montant: parseDouble(map['montant']),
      mode: parseString(map['mode'], fallback: 'especes'),
      reference: parseStringOrNull(map['reference']),
      encaisseLe: parseDateTimeOrNull(map['encaisse_le']),
      annuleLe: parseDateTimeOrNull(map['annule_le']),
      motifAnnulation: parseStringOrNull(map['motif_annulation']),
    );
  }
}

/// Une entrée de l'historique de traitement d'un vêtement.
class PressingEtapeHistorique {
  const PressingEtapeHistorique({
    required this.ligneId,
    required this.etapeCode,
    this.etapeAvant,
    this.agentId,
    this.note,
    this.date,
  });

  final String ligneId;
  final String etapeCode;
  final String? etapeAvant;
  final String? agentId;
  final String? note;
  final DateTime? date;

  factory PressingEtapeHistorique.fromMap(Map<String, dynamic> map) {
    return PressingEtapeHistorique(
      ligneId: parseString(map['ligne_id']),
      etapeCode: parseString(map['etape_code']),
      etapeAvant: parseStringOrNull(map['etape_avant']),
      agentId: parseStringOrNull(map['agent_id']),
      note: parseStringOrNull(map['note']),
      date: parseDateTimeOrNull(map['created_at']),
    );
  }
}

/// Une opération de remise (un passage du client).
class PressingRetrait {
  const PressingRetrait({
    required this.id,
    this.date,
    this.montantEncaisse = 0,
    this.modePaiement,
    this.reference,
    this.observations,
    this.signataire,
    this.agentId,
    this.lignes = const <PressingLigne>[],
  });

  final String id;
  final DateTime? date;
  final double montantEncaisse;
  final String? modePaiement;
  final String? reference;
  final String? observations;
  final String? signataire;
  final String? agentId;
  final List<PressingLigne> lignes;

  factory PressingRetrait.fromMap(Map<String, dynamic> map) {
    final List<PressingLigne> lignes = <PressingLigne>[];
    for (final Map<String, dynamic> l in parseMapList(map['lignes'])) {
      lignes.add(
        PressingLigne(
          id: parseString(l['ligne_id']),
          position: parseInt(l['position'], fallback: 1),
          designation: parseStringOrNull(l['designation']),
        ),
      );
    }

    return PressingRetrait(
      id: parseString(map['id']),
      date: parseDateTimeOrNull(map['created_at']),
      montantEncaisse: parseDouble(map['montant_encaisse']),
      modePaiement: parseStringOrNull(map['mode_paiement']),
      reference: parseStringOrNull(map['reference']),
      observations: parseStringOrNull(map['observations']),
      signataire: parseStringOrNull(map['signataire']),
      agentId: parseStringOrNull(map['agent_id']),
      lignes: lignes,
    );
  }
}

/// Le dossier complet : commande + vêtements + paiements + historique.
class PressingCommande {
  const PressingCommande({
    required this.id,
    this.numero = '',
    this.clientId,
    this.clientNom,
    this.clientTelephone,
    this.statut = StatutCommandePressing.enTraitement,
    this.urgence = false,
    this.dateDepot,
    this.datePrevue,
    this.devise = 'CDF',
    this.total = 0,
    this.remise = 0,
    this.supplement = 0,
    this.montantPaye = 0,
    this.solde = 0,
    this.observations,
    this.qrToken,
    this.qrVersion = 1,
    this.annuleLe,
    this.motifAnnulation,
    this.lignes = const <PressingLigne>[],
    this.paiements = const <PressingPaiement>[],
    this.historique = const <PressingEtapeHistorique>[],
  });

  final String id;
  final String numero;
  final String? clientId;
  final String? clientNom;
  final String? clientTelephone;
  final StatutCommandePressing statut;
  final bool urgence;
  final DateTime? dateDepot;
  final DateTime? datePrevue;
  final String devise;
  final double total;
  final double remise;
  final double supplement;
  final double montantPaye;
  final double solde;
  final String? observations;

  /// Jeton du QR code : aléatoire, sans lien avec la base.
  final String? qrToken;
  final int qrVersion;
  final DateTime? annuleLe;
  final String? motifAnnulation;
  final List<PressingLigne> lignes;
  final List<PressingPaiement> paiements;
  final List<PressingEtapeHistorique> historique;

  int get nbLignes => lignes.length;

  int get nbPrets => lignes.where((PressingLigne l) => l.estPrete && !l.estRemis).length;

  int get nbRemis => lignes.where((PressingLigne l) => l.estRemis).length;

  int get nbEnTraitement =>
      lignes.where((PressingLigne l) => !l.estPrete && !l.estRemis).length;

  List<PressingLigne> get lignesPretes => lignes
      .where((PressingLigne l) => l.estPrete && !l.estRemis)
      .toList(growable: false);

  bool get estAnnulee => statut == StatutCommandePressing.annulee;

  bool get estEnRetard {
    if (estAnnulee || statut == StatutCommandePressing.remise) return false;
    final DateTime? prevue = datePrevue;
    return prevue != null && prevue.isBefore(DateTime.now());
  }

  /// « 3 vêtements · 2 prêts · 1 remis ».
  String get resume {
    final String vetements = nbLignes > 1
        ? "$nbLignes vêtements"
        : "$nbLignes vêtement";
    final String prets = nbPrets > 1 ? "$nbPrets prêts" : "$nbPrets prêt";
    final String remis = nbRemis > 1 ? "$nbRemis remis" : "$nbRemis remis";
    final List<String> morceaux = <String>[
      vetements,
      if (nbPrets > 0) prets,
      if (nbRemis > 0) remis,
    ];
    return morceaux.join(' · ');
  }

  factory PressingCommande.fromMap(Map<String, dynamic> map) {
    return PressingCommande(
      id: parseString(map['id']),
      numero: parseString(map['numero']),
      clientId: parseStringOrNull(map['client_id']),
      clientNom: parseStringOrNull(map['client_nom']),
      clientTelephone: parseStringOrNull(map['client_telephone']),
      statut: StatutCommandePressing.fromCode(
        parseStringOrNull(map['statut']),
      ),
      urgence: parseBool(map['urgence']),
      dateDepot: parseDateTimeOrNull(map['date_depot']),
      datePrevue: parseDateTimeOrNull(map['date_prevue']),
      devise: parseString(map['devise'], fallback: 'CDF'),
      total: parseDouble(map['total']),
      remise: parseDouble(map['remise']),
      supplement: parseDouble(map['supplement']),
      montantPaye: parseDouble(map['montant_paye']),
      solde: parseDouble(map['solde']),
      observations: parseStringOrNull(map['observations']),
      qrToken: parseStringOrNull(map['qr_token']),
      qrVersion: parseInt(map['qr_version'], fallback: 1),
      annuleLe: parseDateTimeOrNull(map['annule_le']),
      motifAnnulation: parseStringOrNull(map['motif_annulation']),
      lignes: parseMapList(map['lignes'])
          .map(PressingLigne.fromMap)
          .toList(growable: false),
      paiements: parseMapList(map['paiements'])
          .map(PressingPaiement.fromMap)
          .toList(growable: false),
      historique: parseMapList(map['historique'])
          .map(PressingEtapeHistorique.fromMap)
          .toList(growable: false),
    );
  }
}

/// Ligne de liste (sans le détail des vêtements) — plus légère.
class PressingCommandeResume {
  const PressingCommandeResume({
    required this.id,
    this.numero = '',
    this.clientNom,
    this.clientTelephone,
    this.statut = StatutCommandePressing.enTraitement,
    this.urgence = false,
    this.dateDepot,
    this.datePrevue,
    this.total = 0,
    this.montantPaye = 0,
    this.solde = 0,
    this.devise = 'CDF',
    this.nbLignes = 0,
    this.nbPrets = 0,
    this.nbRemis = 0,
    this.enRetard = false,
  });

  final String id;
  final String numero;
  final String? clientNom;
  final String? clientTelephone;
  final StatutCommandePressing statut;
  final bool urgence;
  final DateTime? dateDepot;
  final DateTime? datePrevue;
  final double total;
  final double montantPaye;
  final double solde;
  final String devise;
  final int nbLignes;
  final int nbPrets;
  final int nbRemis;
  final bool enRetard;

  factory PressingCommandeResume.fromMap(Map<String, dynamic> map) {
    return PressingCommandeResume(
      id: parseString(map['id']),
      numero: parseString(map['numero']),
      clientNom: parseStringOrNull(map['client_nom']),
      clientTelephone: parseStringOrNull(map['client_telephone']),
      statut: StatutCommandePressing.fromCode(
        parseStringOrNull(map['statut']),
      ),
      urgence: parseBool(map['urgence']),
      dateDepot: parseDateTimeOrNull(map['date_depot']),
      datePrevue: parseDateTimeOrNull(map['date_prevue']),
      total: parseDouble(map['total']),
      montantPaye: parseDouble(map['montant_paye']),
      solde: parseDouble(map['solde']),
      devise: parseString(map['devise'], fallback: 'CDF'),
      nbLignes: parseInt(map['nb_lignes']),
      nbPrets: parseInt(map['nb_prets']),
      nbRemis: parseInt(map['nb_remis']),
      enRetard: parseBool(map['en_retard']),
    );
  }
}

/// Indicateurs du tableau de bord (facturé ≠ encaissé, toujours).
class PressingTableauBord {
  const PressingTableauBord({
    this.commandesAujourdhui = 0,
    this.commandesEnCours = 0,
    this.vetementsEnTraitement = 0,
    this.vetementsPrets = 0,
    this.commandesPartielles = 0,
    this.commandesRemises = 0,
    this.commandesEnRetard = 0,
    this.commandesNonRecuperees = 0,
    this.montantFacture = 0,
    this.montantEncaisse = 0,
    this.montantDu = 0,
  });

  final int commandesAujourdhui;
  final int commandesEnCours;
  final int vetementsEnTraitement;
  final int vetementsPrets;
  final int commandesPartielles;
  final int commandesRemises;
  final int commandesEnRetard;
  final int commandesNonRecuperees;
  final double montantFacture;
  final double montantEncaisse;
  final double montantDu;

  factory PressingTableauBord.fromMap(Map<String, dynamic> map) {
    return PressingTableauBord(
      commandesAujourdhui: parseInt(map['commandes_aujourdhui']),
      commandesEnCours: parseInt(map['commandes_en_cours']),
      vetementsEnTraitement: parseInt(map['vetements_en_traitement']),
      vetementsPrets: parseInt(map['vetements_prets']),
      commandesPartielles: parseInt(map['commandes_partiales']),
      commandesRemises: parseInt(map['commandes_remises']),
      commandesEnRetard: parseInt(map['commandes_en_retard']),
      commandesNonRecuperees: parseInt(map['commandes_non_recuperees']),
      montantFacture: parseDouble(map['montant_facture']),
      montantEncaisse: parseDouble(map['montant_encaisse']),
      montantDu: parseDouble(map['montant_du']),
    );
  }
}

/// Un vêtement vu par l'ATELIER : la file de travail, pas le dossier.
///
/// Le tableau de bord raisonne en commandes ; l'atelier raisonne en
/// vêtements. Un agent traite « cette chemise », pas « la commande 12 ».
class PressingLigneAtelier {
  const PressingLigneAtelier({
    required this.ligneId,
    required this.commandeId,
    this.numero = '',
    this.position = 1,
    this.designation,
    this.categorieNom,
    this.prestationNom,
    this.clientNom,
    this.clientTelephone,
    this.marque,
    this.couleur,
    this.taille,
    this.defauts,
    this.etatDepot,
    this.etapeCode = 'DEPOSE',
    this.etapeLibelle,
    this.estPrete = false,
    this.agentId,
    this.controleOk,
    this.controleNote,
    this.urgence = false,
    this.enRetard = false,
    this.dateDepot,
    this.datePrevue,
  });

  final String ligneId;
  final String commandeId;
  final String numero;
  final int position;
  final String? designation;
  final String? categorieNom;
  final String? prestationNom;
  final String? clientNom;
  final String? clientTelephone;
  final String? marque;
  final String? couleur;
  final String? taille;
  final String? defauts;
  final String? etatDepot;
  final String etapeCode;
  final String? etapeLibelle;
  final bool estPrete;
  final String? agentId;
  final bool? controleOk;
  final String? controleNote;
  final bool urgence;
  final bool enRetard;
  final DateTime? dateDepot;
  final DateTime? datePrevue;

  /// « Chemise blanche » (ou le type de vêtement à défaut).
  String get titre => (designation ?? categorieNom ?? 'Vêtement').trim();

  /// « Costume · Bleu · taille L ».
  String get details {
    final List<String> morceaux = <String>[
      if ((categorieNom ?? '').trim().isNotEmpty) categorieNom!.trim(),
      if ((marque ?? '').trim().isNotEmpty) marque!.trim(),
      if ((couleur ?? '').trim().isNotEmpty) couleur!.trim(),
      if ((taille ?? '').trim().isNotEmpty) 'taille ${taille!.trim()}',
    ];
    return morceaux.join(' · ');
  }

  bool get aDefauts => (defauts ?? '').trim().isNotEmpty;

  factory PressingLigneAtelier.fromMap(Map<String, dynamic> map) {
    return PressingLigneAtelier(
      ligneId: parseString(map['ligne_id']),
      commandeId: parseString(map['commande_id']),
      numero: parseString(map['numero']),
      position: parseInt(map['position'], fallback: 1),
      designation: parseStringOrNull(map['designation']),
      categorieNom: parseStringOrNull(map['categorie_nom']),
      prestationNom: parseStringOrNull(map['prestation_nom']),
      clientNom: parseStringOrNull(map['client_nom']),
      clientTelephone: parseStringOrNull(map['client_telephone']),
      marque: parseStringOrNull(map['marque']),
      couleur: parseStringOrNull(map['couleur']),
      taille: parseStringOrNull(map['taille']),
      defauts: parseStringOrNull(map['defauts']),
      etatDepot: parseStringOrNull(map['etat_depot']),
      etapeCode: parseString(map['etape_code'], fallback: 'DEPOSE'),
      etapeLibelle: parseStringOrNull(map['etape_libelle']),
      estPrete: parseBool(map['est_prete']),
      agentId: parseStringOrNull(map['agent_id']),
      controleOk:
          map['controle_ok'] is bool ? map['controle_ok'] as bool : null,
      controleNote: parseStringOrNull(map['controle_note']),
      urgence: parseBool(map['urgence']),
      enRetard: parseBool(map['en_retard']),
      dateDepot: parseDateTimeOrNull(map['date_depot']),
      datePrevue: parseDateTimeOrNull(map['date_prevue']),
    );
  }
}

/// Ce que l'agent saisit pour un vêtement lors du dépôt.
class LigneDepot {
  const LigneDepot({
    this.categorieId,
    this.prestationId,
    this.designation,
    this.marque,
    this.couleur,
    this.matiere,
    this.taille,
    this.quantite = 1,
    this.etatDepot,
    this.defauts,
    this.accessoires,
    this.observations,
    this.photos = const <String>[],
    this.prixUnitaire,
  });

  final String? categorieId;
  final String? prestationId;
  final String? designation;
  final String? marque;
  final String? couleur;
  final String? matiere;
  final String? taille;
  final double quantite;
  final String? etatDepot;
  final String? defauts;
  final String? accessoires;
  final String? observations;
  final List<String> photos;

  /// `null` = le serveur applique le tarif du catalogue.
  final double? prixUnitaire;

  Map<String, dynamic> toJson() => <String, dynamic>{
        if (categorieId != null) 'categorie_id': categorieId,
        if (prestationId != null) 'prestation_id': prestationId,
        if ((designation ?? '').trim().isNotEmpty)
          'designation': designation!.trim(),
        if ((marque ?? '').trim().isNotEmpty) 'marque': marque!.trim(),
        if ((couleur ?? '').trim().isNotEmpty) 'couleur': couleur!.trim(),
        if ((matiere ?? '').trim().isNotEmpty) 'matiere': matiere!.trim(),
        if ((taille ?? '').trim().isNotEmpty) 'taille': taille!.trim(),
        'quantite': quantite,
        if ((etatDepot ?? '').trim().isNotEmpty)
          'etat_depot': etatDepot!.trim(),
        if ((defauts ?? '').trim().isNotEmpty) 'defauts': defauts!.trim(),
        if ((accessoires ?? '').trim().isNotEmpty)
          'accessoires': accessoires!.trim(),
        if ((observations ?? '').trim().isNotEmpty)
          'observations': observations!.trim(),
        if (photos.isNotEmpty) 'photos': photos,
        if (prixUnitaire != null) 'prix_unitaire': prixUnitaire,
      };
}
