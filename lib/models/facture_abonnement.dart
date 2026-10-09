// lib/models/facture_abonnement.dart
//
// CORRECTIF 67 — Facture d'abonnement traçable.
// Table `public.factures_abonnement` (migration 20260916000067).
//
// POURQUOI CE MODÈLE EST PLUS QU'UN DTO
// ------------------------------------
// Le patron a été clair : « c'est pour la véracité sur ce que le client paie
// et ce que l'agent demande ». Une facture qui n'affiche que le dernier
// encaissement ne prouve rien : le litige porte toujours sur le TOTAL DÛ, sur
// l'AVANCE versée et sur ce qui RESTE.
//
// Chaque ligne de `factures_abonnement` est donc un INSTANTANÉ figé au moment
// du fait (le nom, le téléphone, les prix et la devise sont recopiés : même si
// l'entreprise est renommée ou ses prix corrigés demain, la facture reste
// celle d'hier).
//
// Toute la logique de lecture (est-ce soldé ? l'addition est-elle juste ?
// que dit-on au client ?) est écrite ici en méthodes PURES, afin d'être
// testable sans réseau ni base de données.

import 'package:biashara_yangu/utils/format_utils.dart';
import 'package:biashara_yangu/utils/json_parsing.dart';

/// Délai accordé au client pour compléter l'avance de son installation.
///
/// C'est une règle métier annoncée par le patron : « le client complète après
/// 7 jours ». Le texte de la facture l'affiche, il n'est pas stocké en base.
const int delaiComplementJours = 7;

/// Nature d'une facture d'abonnement.
///
/// ⚠️ [code] est la valeur stockée dans `factures_abonnement.type_facture`.
enum TypeFactureAbonnement {
  /// Premier cycle réglé : le prix d'installation (le 1er mois est inclus).
  installation('INSTALLATION', 'Installation'),

  /// Acompte versé sur l'installation, le cycle n'est pas soldé.
  avance('AVANCE', 'Avance'),

  /// Deuxième versement (ou plus) sur un cycle encore ouvert.
  complement('COMPLEMENT', 'Complément'),

  /// Cycle suivant entièrement réglé : le prix mensuel seul.
  renouvellement('RENOUVELLEMENT', 'Renouvellement'),

  /// Facture d'échéance émise à la main (information, pas un encaissement).
  echeance('ECHEANCE', 'Échéance'),

  /// État de compte édité à la main par la Finance.
  manuelle('MANUELLE', 'État de compte'),

  /// Encaissement dont l'historique ne permet pas de trancher la nature.
  encaissement('ENCAISSEMENT', 'Encaissement');

  const TypeFactureAbonnement(this.code, this.libelle);

  /// Valeur enregistrée en base.
  final String code;

  /// Libellé affiché à l'utilisateur.
  final String libelle;

  /// Vrai si la facture correspond à un versement réellement encaissé.
  bool get attesteUnVersement => this != TypeFactureAbonnement.echeance &&
      this != TypeFactureAbonnement.manuelle;

  /// Convertit un code SQL en nature applicative, ou `null` si inconnu
  /// (une base plus récente que l'application ne doit jamais la casser).
  static TypeFactureAbonnement? fromCode(String? code) {
    if (code == null || code.isEmpty) return null;

    for (final TypeFactureAbonnement type in values) {
      if (type.code == code) return type;
    }
    return null;
  }
}

/// État d'ENVOI d'une facture (et non état de paiement : le règlement est
/// décrit par `soldeRestant`, qui ne ment pas).
enum StatutFactureAbonnement {
  emise('EMISE', 'Émise'),
  envoyee('ENVOYEE', 'Envoyée'),
  annulee('ANNULEE', 'Annulée');

  const StatutFactureAbonnement(this.code, this.libelle);

  final String code;
  final String libelle;

  static StatutFactureAbonnement fromCode(String? code) {
    for (final StatutFactureAbonnement statut in values) {
      if (statut.code == code) return statut;
    }
    return StatutFactureAbonnement.emise;
  }
}

/// Une facture d'abonnement, telle qu'elle a été figée.
class FactureAbonnement {
  final String id;
  final String numero;
  final String entrepriseId;

  // ── Identité FIGÉE du client au moment du fait.
  final String clientNom;
  final String? clientTelephone;
  final String devise;

  final String typeCode;
  final TypeFactureAbonnement? type;
  final StatutFactureAbonnement statut;

  /// `AUTO` (déclencheur d'encaissement) ou `MANUEL` (éditée à la main).
  final String origine;

  final DateTime? periodeDebut;
  final DateTime? periodeFin;
  final int moisCouverts;

  /// Prix d'installation du compte — le premier mois est INCLUS.
  final double montantInstallation;

  /// Prix d'un mois d'abonnement, appliqué aux renouvellements.
  final double montantMensuel;

  /// Montant dû du cycle couvert par cette facture.
  final double montantTotal;

  /// Ce qui avait été versé sur ce cycle AVANT le versement de cette facture.
  final double montantAvance;

  /// Le versement encaissé au moment de l'émission (0 pour un état de compte).
  final double montantRegle;

  /// Cumul encaissé après ce versement.
  final double montantPaye;

  /// Ce qui reste à payer APRÈS ce versement : le complément à venir.
  final double soldeRestant;

  // ── Traçabilité de l'émetteur (« celui qui génère cette facture »).
  final String? genereParNom;
  final String? genereParRole;
  final DateTime? genereLe;

  // ── Traçabilité de l'envoi.
  final DateTime? envoyeeLe;
  final String? envoyeeA;
  final String? canalEnvoi;
  final int nbEnvois;

  final String? note;

  const FactureAbonnement({
    required this.id,
    required this.numero,
    required this.entrepriseId,
    this.clientNom = '',
    this.clientTelephone,
    this.devise = deviseParDefaut,
    this.typeCode = '',
    this.type,
    this.statut = StatutFactureAbonnement.emise,
    this.origine = 'AUTO',
    this.periodeDebut,
    this.periodeFin,
    this.moisCouverts = 0,
    this.montantInstallation = 0,
    this.montantMensuel = 0,
    this.montantTotal = 0,
    this.montantAvance = 0,
    this.montantRegle = 0,
    this.montantPaye = 0,
    this.soldeRestant = 0,
    this.genereParNom,
    this.genereParRole,
    this.genereLe,
    this.envoyeeLe,
    this.envoyeeA,
    this.canalEnvoi,
    this.nbEnvois = 0,
    this.note,
  });

  factory FactureAbonnement.fromMap(Map<String, dynamic> map) {
    final String typeCode = parseString(map['type_facture']);
    return FactureAbonnement(
      id: parseString(map['id']),
      numero: parseString(map['numero']),
      entrepriseId: parseString(map['entreprise_id']),
      clientNom: parseString(map['client_nom']),
      clientTelephone: parseStringOrNull(map['client_telephone']),
      devise: parseString(map['devise'], fallback: deviseParDefaut),
      typeCode: typeCode,
      type: TypeFactureAbonnement.fromCode(typeCode),
      statut: StatutFactureAbonnement.fromCode(parseStringOrNull(map['statut'])),
      origine: parseString(map['origine'], fallback: 'AUTO'),
      periodeDebut: parseDateTimeOrNull(map['periode_debut']),
      periodeFin: parseDateTimeOrNull(map['periode_fin']),
      moisCouverts: parseInt(map['mois_couverts']),
      montantInstallation: parseDouble(map['montant_installation']),
      montantMensuel: parseDouble(map['montant_mensuel']),
      montantTotal: parseDouble(map['montant_total']),
      montantAvance: parseDouble(map['montant_avance']),
      montantRegle: parseDouble(map['montant_regle']),
      montantPaye: parseDouble(map['montant_paye']),
      soldeRestant: parseDouble(map['solde_restant']),
      genereParNom: parseStringOrNull(map['genere_par_nom']),
      genereParRole: parseStringOrNull(map['genere_par_role']),
      genereLe: parseDateTimeOrNull(map['genere_le']),
      envoyeeLe: parseDateTimeOrNull(map['envoyee_le']),
      envoyeeA: parseStringOrNull(map['envoyee_a']),
      canalEnvoi: parseStringOrNull(map['canal_envoi']),
      nbEnvois: parseInt(map['nb_envois']),
      note: parseStringOrNull(map['note']),
    );
  }

  // ---------------------------------------------------------------------------
  // LECTURES PURES — testables sans réseau
  // ---------------------------------------------------------------------------

  /// Libellé de la nature, avec repli honnête sur le code brut si la base
  /// connaît une nature plus récente que l'application.
  String get libelleType =>
      type?.libelle ?? (typeCode.isEmpty ? 'Facture' : typeCode);

  /// Vrai quand il n'y a plus rien à payer.
  bool get estSoldee => soldeRestant <= 0.001;

  /// Vrai quand la facture atteste d'un versement réellement encaissé.
  ///
  /// C'est ce qui interdit de l'annuler : faire disparaître la preuve d'un
  /// argent reçu est exactement le défaut que cette facture doit empêcher.
  /// Même règle que le serveur (`montant_regle > 0`), élargie au cumul déjà
  /// versé pour qu'un état de compte ne puisse pas effacer un encaissement.
  bool get attesteUnVersement =>
      montantRegle > 0.001 ||
      (montantPaye > 0.001 && (type?.attesteUnVersement ?? false));

  /// Vrai si la facture est encore à envoyer.
  bool get aEnvoyer => statut == StatutFactureAbonnement.emise;

  /// Vrai si la facture a été annulée (elle n'est alors plus envoyable).
  bool get estAnnulee => statut == StatutFactureAbonnement.annulee;

  /// Contrôle de l'addition affichée : payé = avance + versement.
  ///
  /// La migration pose cet invariant PAR CONSTRUCTION ; ce getter permet de
  /// le revérifier côté application avant d'imprimer un chiffre au client.
  /// Une addition fausse disqualifierait la facture comme preuve.
  bool get additionJuste =>
      (montantPaye - (montantAvance + montantRegle)).abs() <= 0.001;

  /// Le nom du client, jamais vide.
  String get nomAffiche => clientNom.trim().isEmpty ? 'Client' : clientNom;

  /// Vrai si un numéro WhatsApp utilisable est connu.
  bool get joignableParWhatsApp =>
      (clientTelephone ?? '').replaceAll(RegExp(r'[^0-9]'), '').length >= 8;

  /// Date limite de complément, ou `null` quand elle n'a pas de sens.
  ///
  /// Règle métier : le client complète son installation sous 7 jours APRÈS
  /// l'avance. On ne l'annonce donc que sur la facture d'AVANCE — c'est le
  /// seul document dont on sache qu'il a été émis le jour de l'avance. Sur un
  /// complément, annoncer une date serait une invention.
  DateTime? get dateLimiteComplement {
    if (type != TypeFactureAbonnement.avance) return null;
    if (estSoldee) return null;

    final DateTime? depart = genereLe ?? envoyeeLe;
    if (depart == null) return null;

    return depart.add(const Duration(days: delaiComplementJours));
  }

  /// Résumé d'une ligne de période (« du 21/09/2026 au 21/10/2026 »).
  String get libellePeriode {
    if (periodeDebut == null && periodeFin == null) return '—';
    if (periodeDebut != null && periodeFin != null) {
      return 'du ${formatDate(periodeDebut)} au ${formatDate(periodeFin)}';
    }
    return formatDate(periodeDebut ?? periodeFin);
  }

  /// Résumé de la traçabilité de l'émetteur.
  ///
  /// C'est la réponse à « celui qui génère cette facture » : le nom, le rôle
  /// réel, et si la facture est automatique ou éditée à la main.
  String get resumeEmetteur {
    final String nom = (genereParNom ?? '').trim();
    final String role = (genereParRole ?? '').trim();
    final String qui = nom.isEmpty ? 'Auteur inconnu' : nom;
    final String quelRole = role.isEmpty ? '' : ' ($role)';
    final String comment = origine == 'MANUEL'
        ? 'éditée à la main'
        : 'générée automatiquement à l\'encaissement';

    return '$qui$quelRole — $comment';
  }

  /// Résumé de l'envoi.
  String get resumeEnvoi {
    if (envoyeeLe == null) return 'Pas encore envoyée';

    final String canal = (canalEnvoi ?? '').isEmpty ? '' : ' par $canalEnvoi';
    final String numero = (envoyeeA ?? '').isEmpty ? '' : ' au $envoyeeA';
    final String fois =
        nbEnvois > 1 ? ' ($nbEnvois envois)' : '';

    return 'Envoyée le ${formatDateHeure(envoyeeLe)}$canal$numero$fois';
  }

  /// Montants formatés dans la devise de la facture.
  String montant(double valeur) => formatMontant(valeur, devise: devise);

  String get installationAffichee => montant(montantInstallation);
  String get mensuelAffiche => montant(montantMensuel);
  String get totalAffiche => montant(montantTotal);
  String get avanceAffichee => montant(montantAvance);
  String get regleAffiche => montant(montantRegle);
  String get payeAffiche => montant(montantPaye);
  String get soldeAffiche => montant(soldeRestant);
}

// -----------------------------------------------------------------------------
// MESSAGE WHATSAPP — fonction PURE, testable sans réseau ni lanceur d'URL
// -----------------------------------------------------------------------------

/// Compose le message WhatsApp récapitulatif d'une facture.
///
/// Il reprend EXACTEMENT ce que le patron a demandé de démontrer au client :
///   • le prix de l'installation (le premier mois est inclus) ;
///   • le prix de l'abonnement par mois ;
///   • ce que le client a payé au premier mois — avec l'avance et le
///     complément —, le cumul et ce qui reste.
///
/// Le message est volontairement en texte simple : WhatsApp n'affiche pas de
/// tableau, et le client doit pouvoir le lire d'un coup d'œil. Le PDF complet
/// l'accompagne, partagé séparément par le système.
String messageWhatsAppFacture(
  FactureAbonnement facture, {
  String? nomEtablissement,
}) {
  final StringBuffer b = StringBuffer();

  b.writeln('*FACTURE D\'ABONNEMENT ${facture.numero}*');
  if (nomEtablissement != null && nomEtablissement.trim().isNotEmpty) {
    b.writeln(nomEtablissement.trim());
  }
  b.writeln('Client : ${facture.nomAffiche}');
  b.writeln('Date : ${formatDate(facture.genereLe)}');
  b.writeln('Nature : ${facture.libelleType}');
  b.writeln();

  b.writeln('*_TARIFS_*');
  b.writeln('• Installation (1er mois inclus) : '
      '${facture.installationAffichee}');
  b.writeln('• Abonnement mensuel : ${facture.mensuelAffiche}');
  b.writeln();

  b.writeln('*_CE MOIS_*');
  b.writeln('• Montant dû : ${facture.totalAffiche}');
  b.writeln('• Avance déjà versée : ${facture.avanceAffichee}');
  b.writeln('• Versement reçu : ${facture.regleAffiche}');
  b.writeln('• Total payé à ce jour : ${facture.payeAffiche}');

  if (facture.estSoldee) {
    b.writeln('• Reste à payer : ${facture.soldeAffiche} ✅');
    b.writeln();
    b.writeln('Votre abonnement est entièrement réglé. Merci.');
  } else {
    b.writeln('• *Reste à payer : ${facture.soldeAffiche}*');
    b.writeln();
    final DateTime? limite = facture.dateLimiteComplement;
    if (limite != null) {
      b.writeln('Le complément est attendu sous $delaiComplementJours jours, '
          'soit avant le ${formatDate(limite)}.');
    } else {
      b.writeln('Le complément est attendu dans les meilleurs délais.');
    }
  }

  b.writeln();
  b.writeln('_Facture établie par ${facture.genereParNom ?? 'la plateforme'} '
      '(${facture.genereParRole ?? 'SYSTEME'})._');

  return b.toString().trim();
}
