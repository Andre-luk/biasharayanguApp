// test/notification_test.dart
//
// 🔔 Tests des parties PURES du service de notifications (sans greffon) :
// formats des messages, horaires et anti-doublon du rapport quotidien.

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/services/notification_service.dart';

void main() {
  group('NotificationService — horaires', () {
    test('libelleHeure formate HH:mm', () {
      expect(NotificationService.libelleHeure(1140), '19:00');
      expect(NotificationService.libelleHeure(0), '00:00');
      expect(NotificationService.libelleHeure(8 * 60 + 5), '08:05');
      expect(NotificationService.libelleHeure(23 * 60 + 59), '23:59');
    });

    test('cleJour au format AAAA-MM-JJ', () {
      expect(NotificationService.cleJour(DateTime(2026, 9, 8)), '2026-09-08');
      expect(NotificationService.cleJour(DateTime(2026, 12, 31)), '2026-12-31');
    });
  });

  group('NotificationService — message de vente', () {
    test('vente complète (numéro, total, 2 articles, mode)', () {
      final String corps = NotificationService.messageVente(
        numero: 'VTE-20260918-0007',
        total: 11500,
        nbArticles: 2,
        modePaiement: 'especes',
      );
      expect(corps, contains('VTE-20260918-0007'));
      expect(corps, contains('2 articles'));
      expect(corps, contains('especes'));
    });

    test('1 article, sans mode de paiement', () {
      final String corps = NotificationService.messageVente(
        numero: 'VTE-1',
        total: 1000,
        nbArticles: 1,
      );
      expect(corps, contains('(1 article)'));
      expect(corps.contains('especes'), isFalse);
    });

    test('titre : numéro affiché, ou repli si vide', () {
      expect(
        NotificationService.titreVente('VTE-20260918-0001'),
        contains('VTE-20260918-0001'),
      );
      expect(NotificationService.titreVente('  '), contains('Vente'));
    });
  });

  group('NotificationService — rapport du jour', () {
    test('journée vide', () {
      const ResumeVentesJour vide =
          ResumeVentesJour(ca: 0, nbVentes: 0, nbArticles: 0);
      expect(vide.estVide, isTrue);
      expect(
        NotificationService.messageRapport(vide, DateTime(2026, 9, 18)),
        contains('Aucune vente'),
      );
    });

    test('journée avec ventes : nombre de ventes et articles visibles', () {
      const ResumeVentesJour resume =
          ResumeVentesJour(ca: 11500, nbVentes: 2, nbArticles: 10);
      final String message =
          NotificationService.messageRapport(resume, DateTime(2026, 9, 18));
      expect(resume.estVide, isFalse);
      expect(message, contains('Ventes : 2'));
      expect(message, contains('10'));
    });

    test('titre du rapport daté JJ/MM/AAAA', () {
      expect(
        NotificationService.titreRapport(DateTime(2026, 9, 8)),
        contains('08/09/2026'),
      );
    });
  });

  group('NotificationService — décision d\'envoi (anti-doublon)', () {
    test('avant l\'heure → pas d\'envoi', () {
      expect(
        NotificationService.doitEnvoyerRapport(
          maintenant: DateTime(2026, 9, 18, 18, 59),
          heureMinutes: 19 * 60,
          dernierEnvoi: null,
        ),
        isFalse,
      );
    });

    test('heure atteinte, jamais envoyé → envoi', () {
      expect(
        NotificationService.doitEnvoyerRapport(
          maintenant: DateTime(2026, 9, 18, 19, 0),
          heureMinutes: 19 * 60,
          dernierEnvoi: null,
        ),
        isTrue,
      );
    });

    test('déjà envoyé aujourd\'hui → pas de doublon', () {
      expect(
        NotificationService.doitEnvoyerRapport(
          maintenant: DateTime(2026, 9, 18, 21, 30),
          heureMinutes: 19 * 60,
          dernierEnvoi: '2026-09-18',
        ),
        isFalse,
      );
    });

    test('lendemain → nouvel envoi', () {
      expect(
        NotificationService.doitEnvoyerRapport(
          maintenant: DateTime(2026, 9, 19, 19, 1),
          heureMinutes: 19 * 60,
          dernierEnvoi: '2026-09-18',
        ),
        isTrue,
      );
    });

    test('heure personnalisée (ex. 22 h 15)', () {
      expect(
        NotificationService.doitEnvoyerRapport(
          maintenant: DateTime(2026, 9, 18, 22, 14),
          heureMinutes: 22 * 60 + 15,
          dernierEnvoi: null,
        ),
        isFalse,
      );
      expect(
        NotificationService.doitEnvoyerRapport(
          maintenant: DateTime(2026, 9, 18, 22, 15),
          heureMinutes: 22 * 60 + 15,
          dernierEnvoi: null,
        ),
        isTrue,
      );
    });
  });
}
