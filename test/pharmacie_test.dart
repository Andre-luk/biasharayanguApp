// test/pharmacie_test.dart
//
// 🧩 MODULE 16 (phase C1) — Tests PURS du module Pharmacie :
//   • statut d'expiration (calcul, jours restants, libellés, tri) ;
//   • champs lot / date d'expiration du modèle Article ;
//   • rapport « Expirations » (type + statuts lisibles) ;
//   • carte d'accueil conditionnée au module lots_expiration ;
//   • ligne « expirations » du rapport de fin de journée.
// Aucun réseau.

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/models/article.dart';
import 'package:biashara_yangu/models/module_activite.dart';
import 'package:biashara_yangu/models/permission.dart';
import 'package:biashara_yangu/models/rapport.dart';
import 'package:biashara_yangu/models/statut_expiration.dart';
import 'package:biashara_yangu/services/modules_service.dart';
import 'package:biashara_yangu/services/notification_service.dart';
import 'package:biashara_yangu/ui/accueil/cartes_accueil.dart';

Article _article({
  required int id,
  required String nom,
  DateTime? dateExpiration,
  String? lot,
}) {
  return Article(
    id: id,
    nom: nom,
    dateExpiration: dateExpiration,
    lotNumero: lot,
  );
}

void main() {
  final DateTime reference = DateTime(2026, 9, 18);

  group('StatutExpiration — calcul', () {
    test('aucune date => aucun statut', () {
      expect(StatutExpiration.depuis(null), isNull);
      expect(StatutExpiration.joursRestants(null), isNull);
    });

    test('hier => expiré, aujourd\'hui => proche, +31 j => valide', () {
      expect(
        StatutExpiration.depuis(DateTime(2026, 9, 17), reference: reference),
        StatutExpiration.expire,
      );
      expect(
        StatutExpiration.depuis(DateTime(2026, 9, 18), reference: reference),
        StatutExpiration.proche,
      );
      expect(
        StatutExpiration.depuis(DateTime(2026, 10, 18), reference: reference),
        StatutExpiration.proche,
      );
      expect(
        StatutExpiration.depuis(DateTime(2026, 10, 19), reference: reference),
        StatutExpiration.valide,
      );
    });

    test('l\'heure de la journée ne change pas le statut', () {
      expect(
        StatutExpiration.depuis(
          DateTime(2026, 9, 18, 23, 59),
          reference: reference.add(const Duration(hours: 8)),
        ),
        StatutExpiration.proche,
      );
    });

    test('seuil « proche » personnalisable', () {
      expect(
        StatutExpiration.depuis(
          DateTime(2026, 10, 10),
          reference: reference,
          joursProches: 60,
        ),
        StatutExpiration.proche,
      );
    });

    test('jours restants : négatif si expiré, 0 aujourd\'hui', () {
      expect(
        StatutExpiration.joursRestants(DateTime(2026, 9, 15),
            reference: reference),
        -3,
      );
      expect(
        StatutExpiration.joursRestants(DateTime(2026, 9, 18),
            reference: reference),
        0,
      );
      expect(
        StatutExpiration.joursRestants(DateTime(2026, 9, 28),
            reference: reference),
        10,
      );
    });

    test('libellés des jours restants', () {
      expect(StatutExpiration.libelleJours(null), '—');
      expect(StatutExpiration.libelleJours(-3), 'Expiré depuis 3 j');
      expect(StatutExpiration.libelleJours(0), "Expire aujourd'hui");
      expect(StatutExpiration.libelleJours(1), 'Expire demain');
      expect(StatutExpiration.libelleJours(12), 'Dans 12 j');
    });

    test('estUrgent : expiré et proche uniquement', () {
      expect(StatutExpiration.expire.estUrgent, isTrue);
      expect(StatutExpiration.proche.estUrgent, isTrue);
      expect(StatutExpiration.valide.estUrgent, isFalse);
    });
  });

  group('StatutExpiration — tri par urgence', () {
    test('expirés d\'abord (par date), sans date en dernier', () {
      final List<Article> tries = StatutExpiration.trierParUrgence(
        <Article>[
          _article(id: 1, nom: 'Zinc', dateExpiration: DateTime(2027, 1, 1)),
          _article(id: 2, nom: 'Sans date'),
          _article(id: 3, nom: 'Amoxi', dateExpiration: DateTime(2026, 9, 10)),
          _article(id: 4, nom: 'Para', dateExpiration: DateTime(2026, 10, 1)),
        ],
        reference: reference,
      );

      expect(
        tries.map((Article a) => a.nom).toList(),
        <String>['Amoxi', 'Para', 'Zinc', 'Sans date'],
      );
    });
  });

  group('Article — champs lot & péremption', () {
    test('fromMap lit lot_numero et date_expiration', () {
      final Article article = Article.fromMap(<String, dynamic>{
        'id': 501,
        'nom': 'Paracétamol 500 mg',
        'quantite': 120,
        'lot_numero': 'LOT-2026-A17',
        'date_expiration': '2027-03-15',
      });

      expect(article.lotNumero, 'LOT-2026-A17');
      expect(article.dateExpiration, DateTime(2027, 3, 15));
      expect(article.aDateExpiration, isTrue);
      expect(article.estExpire, isFalse);
    });

    test('absence des colonnes => nulles (compatibilité avant migration)', () {
      final Article article = Article.fromMap(<String, dynamic>{
        'id': 1,
        'nom': 'Article',
      });

      expect(article.lotNumero, isNull);
      expect(article.dateExpiration, isNull);
      expect(article.statutExpiration, isNull);
      expect(article.estExpire, isFalse);
    });

    test('toMap : date au format AAAA-MM-JJ, clés toujours présentes', () {
      final Map<String, dynamic> map = _article(
        id: 1,
        nom: 'X',
        dateExpiration: DateTime(2027, 3, 5),
        lot: 'L1',
      ).toMap();

      expect(map['lot_numero'], 'L1');
      expect(map['date_expiration'], '2027-03-05');

      final Map<String, dynamic> vide = _article(id: 2, nom: 'Y').toMap();
      expect(vide.containsKey('lot_numero'), isTrue);
      expect(vide['lot_numero'], isNull);
      expect(vide['date_expiration'], isNull);
    });

    test('statutExpiration : expiré', () {
      final Article article = _article(
        id: 3,
        nom: 'Vieux sirop',
        dateExpiration: DateTime.now().subtract(const Duration(days: 2)),
      );

      expect(article.estExpire, isTrue);
      expect(article.expireBientot, isFalse);
    });
  });

  group('Rapport « Expirations »', () {
    test('type connu : code, libellé, espace entreprise', () {
      expect(TypeRapport.fromCode('expirations'), TypeRapport.expirations);
      expect(TypeRapport.expirations.libelle, contains('Expirations'));
      expect(TypeRapport.expirations.estPlateforme, isFalse);
      expect(
        TypeRapport.deEspace(EspaceRapport.entreprise),
        contains(TypeRapport.expirations),
      );
    });

    test('statuts lisibles dans les exports', () {
      expect(libelleStatutRapport('expire'), 'Expiré');
      expect(libelleStatutRapport('proche'), 'Expire bientôt');
      expect(libelleStatutRapport('valide'), 'Valide');
    });
  });

  group('Carte d\'accueil « Expirations » (module lots_expiration)', () {
    final Set<PageAccess> toutesPages = PageAccess.values.toSet();

    List<String> idsAvec(Set<String> modules) {
      final List<CarteAccueil> cartes = CarteAccueil.visibles(
        modules: modules,
        profilCharge: true,
        autorise: (PageAccess page, ActionAccess action) =>
            toutesPages.contains(page),
      );
      return cartes.map((CarteAccueil c) => c.id).toList(growable: false);
    }

    test('présente seulement si le module lots_expiration est actif', () {
      final Set<String> avecModule = <String>{
        ...ModulesService.modulesBase,
        ModuleCode.lotsExpiration,
      };

      final List<String> presentes = idsAvec(avecModule);
      expect(presentes, contains('expirations'));
      // Position : après « stock » et les trois cartes de distribution
      // (tournées 22, ma tournée 23, consignes 24), avant « ventes » (30).
      expect(presentes.indexOf('expirations'), presentes.indexOf('stock') + 4);
      expect(presentes, isNot(equals(idsAvec(ModulesService.modulesBase))));

      final List<String> absentes = idsAvec(ModulesService.modulesBase);
      expect(absentes, isNot(contains('expirations')));
    });

    test('la carte affiche « À jour » à zéro et le compte sinon', () {
      final CarteAccueil carte = CarteAccueil.registre
          .firstWhere((CarteAccueil c) => c.id == 'expirations');

      expect(carte.module, ModuleCode.lotsExpiration);
      expect(carte.route, '/main/articles/expirations');
      expect(carte.alerte!(const DonneesAccueil(expirationsCount: 0)), isFalse);
      expect(carte.alerte!(const DonneesAccueil(expirationsCount: 2)), isTrue);
    });
  });

  group('Notification du soir — ligne expirations', () {
    const ResumeVentesJour resume =
        ResumeVentesJour(ca: 11500, nbVentes: 2, nbArticles: 10);

    test('sans compteurs : message inchangé', () {
      final String message =
          NotificationService.messageRapport(resume, DateTime(2026, 9, 18));
      expect(message.contains('Expirations'), isFalse);
    });

    test('avec compteurs : ligne 💊 (pluriels corrects)', () {
      final String message = NotificationService.messageRapport(
        resume,
        DateTime(2026, 9, 18),
        produitsExpires: 2,
        produitsProches: 1,
      );

      expect(message, contains('💊 Expirations'));
      expect(message, contains('2 expirés'));
      expect(message, contains('1 bientôt (≤ 30 j)'));
    });

    test('journée vide mais produits expirés : la ligne apparaît quand même',
        () {
      const ResumeVentesJour vide =
          ResumeVentesJour(ca: 0, nbVentes: 0, nbArticles: 0);
      final String message = NotificationService.messageRapport(
        vide,
        DateTime(2026, 9, 18),
        produitsExpires: 1,
      );

      expect(message, contains('Aucune vente'));
      expect(message, contains('1 expiré'));
    });
  });
}
