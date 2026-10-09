// test/facture_abonnement_test.dart
//
// 🧾 CORRECTIF 67 — TESTS DES FACTURES D'ABONNEMENT.
//
// Tout ce qui est testé ici est PUR : aucun réseau, aucune base de données,
// aucun lanceur d'URL. C'est volontaire — ce sont les règles qui décident de
// ce qu'on montre au client (et donc de ce qu'on peut lui opposer) qui
// doivent être vérifiables sans dépendre d'une connexion.
//
// LE SCÉNARIO DE RÉFÉRENCE est celui décrit par le patron :
//   installation 30 000 CDF (le 1er mois est inclus), abonnement mensuel
//   5 000 CDF, le client verse une AVANCE de 10 000 à l'installation puis
//   COMPLÈTE 20 000 dans les 7 jours.
// La facture doit démontrer ces quatre choses : prix d'installation, prix
// mensuel, avance versée, et ce qui reste à payer.

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/models/facture_abonnement.dart';
import 'package:biashara_yangu/services/facture_abonnement_service.dart';

/// Construit une facture de référence, surchargeable champ par champ.
///
/// Par défaut : une installation de 30 000 CDF réglée EN UNE FOIS à
/// l'installation (aucune avance, donc rien à compléter). Les tests qui
/// portent sur l'avance et le complément surchargent [avance], [regle] et
/// [solde] — c'est le scénario du patron.
FactureAbonnement _facture({
  String typeCode = 'AVANCE',
  String statut = 'EMISE',
  double installation = 30000,
  double mensuel = 5000,
  double total = 30000,
  double avance = 0,
  double regle = 30000,
  double? paye,
  double? solde,
  String telephone = '+243 970 000 000',
  String origine = 'AUTO',
  String? nomAuteur = 'Andre Lukengu',
  String? roleAuteur = 'AGENT_TERRAIN',
  DateTime? genereLe,
}) {
  final double payeEffectif = paye ?? (avance + regle);
  final double soldeEffectif = solde ?? (total - payeEffectif);

  return FactureAbonnement(
    id: 'f1',
    numero: 'FA-2026-000001',
    entrepriseId: 'e1',
    clientNom: 'Boutique Jambo',
    clientTelephone: telephone,
    typeCode: typeCode,
    type: TypeFactureAbonnement.fromCode(typeCode),
    statut: StatutFactureAbonnement.fromCode(statut),
    origine: origine,
    moisCouverts: 1,
    montantInstallation: installation,
    montantMensuel: mensuel,
    montantTotal: total,
    montantAvance: avance,
    montantRegle: regle,
    montantPaye: payeEffectif,
    soldeRestant: soldeEffectif,
    genereParNom: nomAuteur,
    genereParRole: roleAuteur,
    genereLe: genereLe,
  );
}

void main() {
  group('TypeFactureAbonnement', () {
    test('reconnaît tous les codes écrits par la base', () {
      expect(TypeFactureAbonnement.fromCode('INSTALLATION'),
          TypeFactureAbonnement.installation);
      expect(TypeFactureAbonnement.fromCode('AVANCE'),
          TypeFactureAbonnement.avance);
      expect(TypeFactureAbonnement.fromCode('COMPLEMENT'),
          TypeFactureAbonnement.complement);
      expect(TypeFactureAbonnement.fromCode('RENOUVELLEMENT'),
          TypeFactureAbonnement.renouvellement);
      expect(TypeFactureAbonnement.fromCode('ECHEANCE'),
          TypeFactureAbonnement.echeance);
      expect(TypeFactureAbonnement.fromCode('MANUELLE'),
          TypeFactureAbonnement.manuelle);
      expect(TypeFactureAbonnement.fromCode('ENCAISSEMENT'),
          TypeFactureAbonnement.encaissement);
    });

    test('un code inconnu ne casse rien (base plus récente que l\'app)', () {
      // ⚠️ Une base migrée avant l'application ne doit JAMAIS provoquer une
      // exception : on affiche le code brut plutôt que de perdre la facture.
      expect(TypeFactureAbonnement.fromCode('TARIF_SPECIAL'), isNull);
      expect(TypeFactureAbonnement.fromCode(null), isNull);
      expect(TypeFactureAbonnement.fromCode(''), isNull);
    });

    test('seules les natures encaissées attestent un versement', () {
      expect(TypeFactureAbonnement.avance.attesteUnVersement, isTrue);
      expect(TypeFactureAbonnement.installation.attesteUnVersement, isTrue);
      expect(TypeFactureAbonnement.complement.attesteUnVersement, isTrue);
      expect(TypeFactureAbonnement.renouvellement.attesteUnVersement, isTrue);
      // Un état de compte ou une échéance ne prouve aucun encaissement : ils
      // peuvent donc être annulés.
      expect(TypeFactureAbonnement.manuelle.attesteUnVersement, isFalse);
      expect(TypeFactureAbonnement.echeance.attesteUnVersement, isFalse);
    });
  });

  group('StatutFactureAbonnement', () {
    test('un statut inconnu retombe sur « émise » (fail-safe)', () {
      expect(StatutFactureAbonnement.fromCode('ENVOYEE'),
          StatutFactureAbonnement.envoyee);
      expect(StatutFactureAbonnement.fromCode('ANNULEE'),
          StatutFactureAbonnement.annulee);
      // Ne jamais considérer une facture comme envoyée sur un doute.
      expect(StatutFactureAbonnement.fromCode('PERDUE'),
          StatutFactureAbonnement.emise);
      expect(StatutFactureAbonnement.fromCode(null),
          StatutFactureAbonnement.emise);
    });
  });

  group('FactureAbonnement.fromMap', () {
    test('lit tous les champs renvoyés par la RPC', () {
      final FactureAbonnement f = FactureAbonnement.fromMap(<String, dynamic>{
        'id': 'abc',
        'numero': 'FA-2026-000042',
        'entreprise_id': 'ent-1',
        'client_nom': 'Boutique LUMUMBA',
        'client_telephone': '+243970000000',
        'devise': 'CDF',
        'type_facture': 'COMPLEMENT',
        'statut': 'ENVOYEE',
        'origine': 'AUTO',
        'mois_couverts': 1,
        'montant_installation': 30000,
        'montant_mensuel': 5000,
        'montant_total': 30000,
        'montant_avance': 10000,
        'montant_regle': 20000,
        'montant_paye': 30000,
        'solde_restant': 0,
        'genere_par_nom': 'Andre Lukengu',
        'genere_par_role': 'FINANCE_LAPERLE',
        'nb_envois': 2,
        'canal_envoi': 'whatsapp',
      });

      expect(f.numero, 'FA-2026-000042');
      expect(f.clientNom, 'Boutique LUMUMBA');
      expect(f.type, TypeFactureAbonnement.complement);
      expect(f.statut, StatutFactureAbonnement.envoyee);
      expect(f.montantAvance, 10000);
      expect(f.montantRegle, 20000);
      expect(f.montantPaye, 30000);
      expect(f.soldeRestant, 0);
      expect(f.nbEnvois, 2);
      expect(f.canalEnvoi, 'whatsapp');
    });

    test('tolère une carte vide sans lever', () {
      final FactureAbonnement f = FactureAbonnement.fromMap(<String, dynamic>{});
      expect(f.numero, '');
      expect(f.devise, 'CDF');
      expect(f.statut, StatutFactureAbonnement.emise);
      expect(f.type, isNull);
      expect(f.montantTotal, 0);
    });
  });

  group('Lectures pures — la situation du client', () {
    test('installation soldée : plus rien à payer', () {
      final FactureAbonnement f = _facture();
      expect(f.estSoldee, isTrue);
      expect(f.soldeRestant, 0);
      expect(f.aEnvoyer, isTrue);
    });

    test('avance seule : il reste le complément', () {
      final FactureAbonnement f =
          _facture(avance: 0, regle: 10000, solde: 20000);
      expect(f.estSoldee, isFalse);
      expect(f.soldeRestant, 20000);
    });

    test('l\'addition payé = avance + versement est vérifiée', () {
      // Le cas demandé par le patron : 10 000 d'avance, puis 20 000.
      final FactureAbonnement f =
          _facture(avance: 10000, regle: 20000, solde: 0);
      expect(f.montantPaye, 30000);
      expect(f.additionJuste, isTrue);
    });

    test('une addition fausse est détectée (garde-fou de preuve)', () {
      // 10 000 + 20 000 devrait donner 30 000 : ici la base annonce 25 000.
      final FactureAbonnement f = _facture(
        avance: 10000,
        regle: 20000,
        paye: 25000,
        solde: 5000,
      );
      expect(f.additionJuste, isFalse);
    });

    test('l\'addition tolère les arrondis flottants', () {
      final FactureAbonnement f = _facture(
        avance: 0.1,
        regle: 0.2,
        paye: 0.3,
        solde: 29999.7,
      );
      expect(f.additionJuste, isTrue);
    });

    test('une facture qui atteste un versement ne s\'annule pas', () {
      expect(_facture(avance: 0, regle: 10000).attesteUnVersement, isTrue);
      // État de compte : aucun versement, donc annulable.
      expect(
        _facture(typeCode: 'MANUELLE', avance: 0, regle: 0, paye: 0, solde: 0)
            .attesteUnVersement,
        isFalse,
      );
    });
  });

  group('Date limite du complément (règle des 7 jours)', () {
    test('annoncée UNIQUEMENT sur une facture d\'avance non soldée', () {
      final DateTime emise = DateTime(2026, 9, 21, 10);
      final FactureAbonnement avance = _facture(
        typeCode: 'AVANCE',
        regle: 10000,
        solde: 20000,
        genereLe: emise,
      );

      expect(avance.dateLimiteComplement, DateTime(2026, 9, 28, 10));
    });

    test('pas de date sur un complément (on n\'invente pas)', () {
      // Le complément peut arriver le 7e jour : annoncer une nouvelle
      // échéance de 7 jours donnerait au client un délai qui n'existe pas.
      final FactureAbonnement complement = _facture(
        typeCode: 'COMPLEMENT',
        avance: 10000,
        regle: 10000,
        solde: 10000,
        genereLe: DateTime(2026, 9, 25),
      );

      expect(complement.dateLimiteComplement, isNull);
    });

    test('pas de date quand le cycle est déjà soldé', () {
      final FactureAbonnement soldee = _facture(
        typeCode: 'AVANCE',
        regle: 10000,
        solde: 0,
        genereLe: DateTime(2026, 9, 21),
      );

      expect(soldee.dateLimiteComplement, isNull);
    });

    test('le délai annoncé vient de la constante métier', () {
      expect(delaiComplementJours, 7);
    });
  });

  group('Traçabilité — « celui qui génère cette facture »', () {
    test('un encaissement automatique est nommé comme tel', () {
      final FactureAbonnement f = _facture();
      expect(f.resumeEmetteur, contains('Andre Lukengu'));
      expect(f.resumeEmetteur, contains('AGENT_TERRAIN'));
      expect(f.resumeEmetteur, contains('automatiquement'));
    });

    test('une facture éditée à la main est distinguée', () {
      final FactureAbonnement f =
          _facture(origine: 'MANUEL', roleAuteur: 'FINANCE_LAPERLE');
      expect(f.resumeEmetteur, contains('éditée à la main'));
      expect(f.resumeEmetteur, contains('FINANCE_LAPERLE'));
    });

    test('un auteur inconnu est dit honnêtement', () {
      final FactureAbonnement f =
          _facture(nomAuteur: null, roleAuteur: null);
      expect(f.resumeEmetteur, contains('Auteur inconnu'));
    });

    test('l\'envoi est tracé (canal, numéro, nombre de fois)', () {
      final FactureAbonnement jamais = _facture();
      expect(jamais.resumeEnvoi, 'Pas encore envoyée');

      final FactureAbonnement envoyee = FactureAbonnement(
        id: 'f',
        numero: 'FA-2026-000001',
        entrepriseId: 'e',
        envoyeeLe: DateTime(2026, 9, 21, 14, 5),
        envoyeeA: '+243970000000',
        canalEnvoi: 'whatsapp',
        nbEnvois: 3,
      );
      expect(envoyee.resumeEnvoi, contains('whatsapp'));
      expect(envoyee.resumeEnvoi, contains('+243970000000'));
      expect(envoyee.resumeEnvoi, contains('3 envois'));
    });
  });

  group('Numéro WhatsApp', () {
    test('un numéro trop court est refusé', () {
      expect(_facture(telephone: '12345').joignableParWhatsApp, isFalse);
      expect(_facture(telephone: '').joignableParWhatsApp, isFalse);
    });

    test('les espaces et indicatifs ne gênent pas', () {
      expect(_facture(telephone: '+243 970 000 000').joignableParWhatsApp,
          isTrue);
      expect(_facture(telephone: '0970-000-000').joignableParWhatsApp, isTrue);
    });
  });

  group('Message WhatsApp — ce que le client doit pouvoir lire', () {
    test('contient le prix d\'installation ET le prix mensuel', () {
      final String message = messageWhatsAppFacture(
        _facture(avance: 10000, regle: 20000),
      );

      expect(message, contains('30 000 CDF'));
      expect(message, contains('5 000 CDF'));
      expect(message, contains('Installation'));
      expect(message, contains('Abonnement mensuel'));
      expect(message, contains('1er mois inclus'));
    });

    test('démontre l\'avance ET le versement du premier mois', () {
      final String message = messageWhatsAppFacture(
        _facture(avance: 10000, regle: 20000, solde: 0),
      );

      expect(message, contains('Avance déjà versée : 10 000 CDF'));
      expect(message, contains('Versement reçu : 20 000 CDF'));
      expect(message, contains('Total payé à ce jour : 30 000 CDF'));
    });

    test('annonce le reste à payer et la règle des 7 jours sur une avance', () {
      final String message = messageWhatsAppFacture(
        _facture(
          regle: 10000,
          solde: 20000,
          genereLe: DateTime(2026, 9, 21, 9),
        ),
      );

      expect(message, contains('Reste à payer : 20 000 CDF'));
      expect(message, contains('7 jours'));
      expect(message, contains('28/09/2026'));
      expect(message, isNot(contains('entièrement réglé')));
    });

    test('dit clairement quand tout est payé', () {
      final String message = messageWhatsAppFacture(
        _facture(avance: 10000, regle: 20000, solde: 0),
      );

      expect(message, contains('entièrement réglé'));
      expect(message, contains('Reste à payer : 0 CDF'));
    });

    test('porte le numéro de facture, le client et l\'auteur', () {
      final String message = messageWhatsAppFacture(
        _facture(),
        nomEtablissement: 'Biashara Yangu',
      );

      expect(message, contains('FA-2026-000001'));
      expect(message, contains('Boutique Jambo'));
      expect(message, contains('Biashara Yangu'));
      expect(message, contains('Andre Lukengu'));
    });

    test('n\'affiche pas de ligne vide en tête ni en queue', () {
      final String message = messageWhatsAppFacture(_facture());
      expect(message, message.trim());
      expect(message.startsWith('*FACTURE'), isTrue);
    });
  });

  group('Nom de fichier du PDF', () {
    test('reprend le numéro de facture', () {
      expect(
        FactureAbonnementService.nomFichierFacture(_facture()),
        'facture_FA-2026-000001.pdf',
      );
    });

    test('neutralise les caractères interdits', () {
      final FactureAbonnement f = FactureAbonnement(
        id: 'f',
        numero: 'FA 2026/000001',
        entrepriseId: 'e',
      );
      expect(
        FactureAbonnementService.nomFichierFacture(f),
        'facture_FA-2026-000001.pdf',
      );
    });

    test('retombe sur l\'identifiant si le numéro est vide', () {
      final FactureAbonnement f =
          FactureAbonnement(id: 'abc-123', numero: '', entrepriseId: 'e');
      expect(
        FactureAbonnementService.nomFichierFacture(f),
        'facture_abc-123.pdf',
      );
    });
  });

  group('Erreurs serveur', () {
    test('extrait le texte après « CODE| »', () {
      expect(
        FactureAbonnementService.messageErreur(
          'ACCES_REFUSE|Seule la Finance peut annuler une facture.',
          repli: 'repli',
        ),
        'Seule la Finance peut annuler une facture.',
      );
    });

    test('utilise le repli quand il n\'y a pas de texte utile', () {
      expect(
        FactureAbonnementService.messageErreur('ACCES_REFUSE', repli: 'repli'),
        'repli',
      );
      expect(
        FactureAbonnementService.messageErreur('ACCES_REFUSE|', repli: 'repli'),
        'repli',
      );
      expect(
        FactureAbonnementService.messageErreur('', repli: 'repli'),
        'repli',
      );
    });

    test('classe chaque code serveur dans la bonne nature d\'erreur', () {
      expect(
        FactureAbonnementService.typeDepuisMessage('ACCES_REFUSE|x'),
        TypeErreurFacture.droits,
      );
      expect(
        FactureAbonnementService.typeDepuisMessage('SANS_TELEPHONE|x'),
        TypeErreurFacture.telephone,
      );
      expect(
        FactureAbonnementService.typeDepuisMessage(
            'FACTURE_ATTESTE_UN_VERSEMENT|x'),
        TypeErreurFacture.verrouillee,
      );
      expect(
        FactureAbonnementService.typeDepuisMessage('DEJA_ANNULEE|x'),
        TypeErreurFacture.verrouillee,
      );
      expect(
        FactureAbonnementService.typeDepuisMessage('MOTIF_REQUIS|x'),
        TypeErreurFacture.validation,
      );
      expect(
        FactureAbonnementService.typeDepuisMessage('FACTURE_INTROUVABLE|x'),
        TypeErreurFacture.introuvable,
      );
    });

    test('reconnaît une base non migrée (PGRST202)', () {
      // Le serveur répond « function not found » tant que la migration 67
      // n'est pas exécutée : l'écran doit pouvoir le dire clairement.
      expect(
        FactureAbonnementService.typeDepuisMessage(
            'PGRST202|Could not find the function'),
        TypeErreurFacture.nonDeploye,
      );
    });
  });

  group('Divers', () {
    test('un client sans nom n\'est jamais vide à l\'affichage', () {
      final FactureAbonnement f = FactureAbonnement(
        id: 'f',
        numero: 'FA-1',
        entrepriseId: 'e',
        clientNom: '   ',
      );
      expect(f.nomAffiche, 'Client');
    });

    test('la nature inconnue s\'affiche en clair, pas en vide', () {
      final FactureAbonnement f = FactureAbonnement(
        id: 'f',
        numero: 'FA-1',
        entrepriseId: 'e',
        typeCode: 'TARIF_SPECIAL',
      );
      expect(f.libelleType, 'TARIF_SPECIAL');
    });

    test('les montants portent la devise de la facture', () {
      final FactureAbonnement f = FactureAbonnement(
        id: 'f',
        numero: 'FA-1',
        entrepriseId: 'e',
        devise: r'$',
        montantInstallation: 12.5,
      );
      expect(f.installationAffichee, contains(r'$'));
      expect(f.installationAffichee, contains('12,50'));
    });

    test('la période s\'écrit en clair', () {
      final FactureAbonnement f = FactureAbonnement(
        id: 'f',
        numero: 'FA-1',
        entrepriseId: 'e',
        periodeDebut: DateTime(2026, 9, 21),
        periodeFin: DateTime(2026, 10, 21),
      );
      expect(f.libellePeriode, 'du 21/09/2026 au 21/10/2026');
    });
  });
}
