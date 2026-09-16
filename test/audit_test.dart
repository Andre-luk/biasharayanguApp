// test/audit_test.dart
//
// Tests unitaires du MODULE 12 — Journal d'audit & sécurité.
//
// Aucun accès réseau : ces tests vérifient le parsing des réponses des RPC
// (`rpc_audit_lister`, `rpc_audit_verifier`, `rpc_securite_connexions`,
// `rpc_securite_alertes`), le catalogue des actions, les références et
// empreintes d'export, et le formatage des dates.
//
//     flutter test test/audit_test.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/models/audit.dart';
import 'package:biashara_yangu/services/audit_service.dart';

/// Entrée de journal représentative (prix modifié, niveau CRITIQUE).
EntreeAudit _entreePrix() => EntreeAudit(
      id: '11111111-2222-3333-4444-555555555555',
      seq: 42,
      utilisateurId: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
      utilisateur: 'Patron Test',
      email: 'patron@exemple.cd',
      entrepriseId: '99999999-8888-7777-6666-555555555555',
      action: 'PRIX_MODIFIE',
      niveau: NiveauAudit.critique,
      details: const <String, dynamic>{
        'ancien': 1500,
        'nouveau': 2000,
        'article': 'Sucre 1kg',
      },
      ipAddress: '41.243.10.5',
      userAgent: 'Dart/3.0 (dart:io)',
      createdAt: DateTime.utc(2026, 9, 17, 10, 30),
    );

void main() {
  // =========================================================================
  // 1. NIVEAUX
  // =========================================================================

  group('NiveauAudit', () {
    test('convertit les codes connus (insensible à la casse)', () {
      expect(NiveauAudit.fromCode('CRITIQUE'), NiveauAudit.critique);
      expect(NiveauAudit.fromCode('haut'), NiveauAudit.haut);
      expect(NiveauAudit.fromCode(' Moyen '), NiveauAudit.moyen);
      expect(NiveauAudit.fromCode('INFO'), NiveauAudit.info);
    });

    test('retombe sur INFO pour un code inconnu ou nul (jamais d\'erreur)', () {
      expect(NiveauAudit.fromCode('BIDON'), NiveauAudit.info);
      expect(NiveauAudit.fromCode(null), NiveauAudit.info);
      expect(NiveauAudit.fromCode(''), NiveauAudit.info);
    });

    test('expose un libellé français', () {
      expect(NiveauAudit.critique.libelle, 'Critique');
      expect(NiveauAudit.haut.libelle, 'Haut');
    });
  });

  // =========================================================================
  // 2. PARSING DES ENTRÉES
  // =========================================================================

  group('EntreeAudit.depuisJson', () {
    test('parse une entrée complète', () {
      final EntreeAudit? entree = EntreeAudit.depuisJson(<String, dynamic>{
        'id': 'id-1',
        'seq': 42,
        'utilisateur_id': 'user-1',
        'utilisateur': 'Patron Test',
        'email': 'patron@exemple.cd',
        'entreprise_id': 'ent-1',
        'action': 'PRIX_MODIFIE',
        'niveau': 'CRITIQUE',
        'details': <String, dynamic>{'ancien': 1500, 'nouveau': 2000},
        'ip_address': '41.243.10.5',
        'user_agent': 'Dart/3.0',
        'created_at': '2026-09-17T10:30:00Z',
      });

      expect(entree, isNotNull);
      expect(entree!.seq, 42);
      expect(entree.action, 'PRIX_MODIFIE');
      expect(entree.niveau, NiveauAudit.critique);
      expect(entree.details['ancien'], 1500);
      expect(entree.anonyme, isFalse);
      expect(entree.libelleAction, 'Prix modifié');
      expect(entree.createdAt?.toUtc().hour, 10);
    });

    test('accepte une entrée sans session (échec de connexion)', () {
      final EntreeAudit? entree = EntreeAudit.depuisJson(<String, dynamic>{
        'id': 'id-2',
        'action': 'CONNEXION_ECHEC',
        'niveau': 'MOYEN',
        'details': <String, dynamic>{'email': 'x@y.cd', 'anonyme': true},
      });

      expect(entree, isNotNull);
      expect(entree!.anonyme, isTrue);
      expect(entree.niveau, NiveauAudit.moyen);
      expect(entree.details['anonyme'], true);
    });

    test('rejette les formes non cartographiques', () {
      expect(EntreeAudit.depuisJson(null), isNull);
      expect(EntreeAudit.depuisJson('pas un objet'), isNull);
    });
  });

  group('PageAudit.depuisRpc', () {
    test('parse la page complète', () {
      final PageAudit page = PageAudit.depuisRpc(<String, dynamic>{
        'lignes': <Map<String, dynamic>>[
          <String, dynamic>{'id': 'a', 'seq': 2, 'action': 'VENTE'},
          <String, dynamic>{'id': 'b', 'seq': 1, 'action': 'CONNEXION'},
        ],
        'total': 123,
        'limite': 50,
        'offset': 50,
        'portee': 'plateforme',
      });

      expect(page.lignes, hasLength(2));
      expect(page.total, 123);
      expect(page.offset, 50);
      expect(page.portee, 'plateforme');
      expect(page.lignes.first.action, 'VENTE');
    });

    test('renvoie une page vide pour une réponse inattendue', () {
      final PageAudit page = PageAudit.depuisRpc(null);
      expect(page.lignes, isEmpty);
      expect(page.total, 0);
    });
  });

  // =========================================================================
  // 3. VÉRIFICATION D'INTÉGRITÉ
  // =========================================================================

  group('VerificationAudit.depuisRpc', () {
    test('chaîne intègre', () {
      final VerificationAudit resultat =
          VerificationAudit.depuisRpc(<String, dynamic>{
        'verifie': true,
        'nb_controle': 500,
        'nb_anomalies': 0,
        'premier_seq': 10,
        'dernier_seq': 509,
        'anomalies': <dynamic>[],
      });

      expect(resultat.verifie, isTrue);
      expect(resultat.nbControle, 500);
      expect(resultat.premierSeq, 10);
      expect(resultat.dernierSeq, 509);
    });

    test('anomalies listées', () {
      final VerificationAudit resultat =
          VerificationAudit.depuisRpc(<String, dynamic>{
        'verifie': false,
        'nb_controle': 3,
        'nb_anomalies': 1,
        'anomalies': <Map<String, dynamic>>[
          <String, dynamic>{'seq': 12, 'action': 'VENTE'},
        ],
      });

      expect(resultat.verifie, isFalse);
      expect(resultat.anomalies, hasLength(1));
      expect(resultat.anomalies.first['seq'], 12);
    });
  });

  // =========================================================================
  // 4. ÉCRAN SÉCURITÉ
  // =========================================================================

  group('Résultats connexions & alertes', () {
    test('ResultatConnexions parse lignes et compteurs', () {
      final ResultatConnexions resultat =
          ResultatConnexions.depuisRpc(<String, dynamic>{
        'connexions': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'c1',
            'action': 'CONNEXION',
            'utilisateur': 'Patron',
            'ip_address': '41.243.1.2',
            'created_at': '2026-09-17T09:00:00Z',
          },
        ],
        'resume': <String, dynamic>{
          'reussies_24h': 12,
          'echecs_24h': 4,
          'deconnexions_24h': 3,
          'echecs_7j': 9,
          'comptes_echoues_24h': 2,
          'ips_echouees_24h': 1,
        },
      });

      expect(resultat.lignes, hasLength(1));
      expect(resultat.lignes.first.action, 'CONNEXION');
      expect(resultat.resume.reussies24h, 12);
      expect(resultat.resume.ipsEchouees24h, 1);
    });

    test('AlerteSecurite parse une IP suspecte et ses emails', () {
      final AlerteSecurite? alerte = AlerteSecurite.depuisJson(<String, dynamic>{
        'type': 'IP_SUSPECTE',
        'gravite': 'HAUTE',
        'libelle': 'Adresse IP à échecs multiples',
        'ip': '198.51.100.7',
        'nombre': 11,
        'derniere': '2026-09-17T08:00:00Z',
        'emails': <String>['a@x.cd', 'b@x.cd'],
      });

      expect(alerte, isNotNull);
      expect(alerte!.type, 'IP_SUSPECTE');
      expect(alerte.gravite, 'HAUTE');
      expect(alerte.emails, hasLength(2));
      expect(alerte.nombre, 11);
    });

    test('ResultatAlertes parse le résumé et les seuils', () {
      final ResultatAlertes resultat =
          ResultatAlertes.depuisRpc(<String, dynamic>{
        'alertes': <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'TENTATIVES_ECHOUEES',
            'gravite': 'MOYENNE',
            'libelle': 'Tentatives répétées',
            'email': 'x@y.cd',
            'nombre': 3,
          },
        ],
        'resume': <String, dynamic>{
          'echecs_24h': 7,
          'echecs_7j': 20,
          'connexions_24h': 15,
          'dernier_echec': '2026-09-17T11:00:00Z',
          'nb_alertes': 1,
        },
        'seuils': <String, dynamic>{'email': 3, 'ip': 5, 'fenetre_heures': 24},
      });

      expect(resultat.alertes, hasLength(1));
      expect(resultat.nbAlertes, 1);
      expect(resultat.seuilEmail, 3);
      expect(resultat.seuilIp, 5);
      expect(resultat.fenetreHeures, 24);
      expect(resultat.dernierEchec, isNotNull);
    });
  });

  // =========================================================================
  // 5. CATALOGUE DES ACTIONS
  // =========================================================================

  group('CatalogueAudit', () {
    test('libellés connus', () {
      expect(CatalogueAudit.libelle('VENTE'), 'Vente');
      expect(CatalogueAudit.libelle('prix_modifie'), 'Prix modifié');
      expect(CatalogueAudit.libelle('IMPORT_PRODUITS'), 'Import d\'articles');
      expect(CatalogueAudit.libelle('CONNEXION_ECHEC'), 'Échec de connexion');
    });

    test('action inconnue « humanisée » plutôt que rejetée', () {
      expect(CatalogueAudit.libelle('NOUVELLE_ACTION'), 'Nouvelle action');
      expect(CatalogueAudit.libelle(null), 'Action inconnue');
    });

    test('le catalogue couvre les actions exigées par le cahier des charges',
        () {
      for (final String action in <String>[
        'CHANGEMENT_ROLE',
        'PRIX_MODIFIE',
        'ANNULATION_VENTE',
        'STOCK_MODIFIE',
        'PAIEMENT_ENREGISTRE',
        'CHANGEMENT_ACTIVATION',
        'CONNEXION',
        'DECONNEXION',
        'ARTICLE_MODIFIE',
      ]) {
        expect(CatalogueAudit.toutes, contains(action),
            reason: 'Action manquante : $action');
      }
    });
  });

  // =========================================================================
  // 6. RÉFÉRENCE, EMPREINTE, FORMATS
  // =========================================================================

  group('AuditService — outils purs', () {
    test('référence d\'export au format AUD-AAAAMMJJ-XXXXXX', () {
      final String reference = AuditService.genererReferenceExport(
        maintenant: DateTime(2026, 9, 17),
        suffixe: 'AB12CD',
      );

      expect(reference, 'AUD-20260917-AB12CD');
      expect(RegExp(r'^AUD-\d{8}-[0-9A-F]{6}$').hasMatch(reference), isTrue);
    });

    test('empreinte déterministe : même contenu, même empreinte', () {
      final List<EntreeAudit> lignes = <EntreeAudit>[_entreePrix()];

      final String a = AuditService.empreinteExport(lignes, 'AUD-1');
      final String b = AuditService.empreinteExport(lignes, 'AUD-1');
      final String c = AuditService.empreinteExport(lignes, 'AUD-2');

      expect(a, b);
      expect(a, isNot(c));
      expect(a, hasLength(64)); // SHA-256 hexadécimal
    });

    test('empreinte courte sur 12 caractères majuscules', () {
      expect(
        AuditService.empreinteCourte('abcdef0123456789'),
        'ABCDEF012345',
      );
    });

    test('formats de date du projet', () {
      final DateTime date = DateTime(2026, 9, 7);
      expect(AuditService.dateSeule(date), '2026-09-07');
      expect(AuditService.dateCompacte(date), '20260907');
    });

    test('messageErreur extrait la partie française des erreurs préfixées', () {
      expect(
        AuditService.messageErreur('DROIT_REFUSE|Votre rôle ne permet pas.'),
        'Votre rôle ne permet pas.',
      );
      expect(AuditService.messageErreur('Texte brut'), 'Texte brut');
    });
  });
}
