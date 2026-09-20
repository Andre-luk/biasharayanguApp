// test/devise_test.dart
//
// 🪙 MODULE 18 — DEVISES DE TRAVAIL & TAUX DE CONVERSION.
//
// Vérifie les règles PURES (sans réseau) :
//   • le modèle de devise et l'analyse de `rpc_devise_etat()` ;
//   • les conversions « 1 USD = X CDF » dans les deux sens ;
//   • le formatage des montants (CDF entier / USD avec cents) et sa
//     propagation globale à toute l'application via `FormatMonetaire`.

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/models/devise.dart';
import 'package:biashara_yangu/services/devise_service.dart';
import 'package:biashara_yangu/utils/format_utils.dart';

void main() {
  tearDown(() {
    FormatMonetaire.reinitialiser();
    DeviseService.instance.etat.value = null;
  });

  // =========================================================================
  //  1. MODÈLE
  // =========================================================================

  group('Devise — modèle', () {
    test('les codes connus sont reconnus (insensible à la casse)', () {
      expect(Devise.fromCode('CDF'), Devise.cdf);
      expect(Devise.fromCode('usd'), Devise.usd);
      expect(Devise.fromCode(' USD '), Devise.usd);
    });

    test('un code inconnu retombe sur le franc congolais (comportement actuel)',
        () {
      expect(Devise.fromCode(null), Devise.cdf);
      expect(Devise.fromCode(''), Devise.cdf);
      expect(Devise.fromCode('EUR'), Devise.cdf);
    });

    test('libellés et symboles du métier', () {
      expect(Devise.cdf.libelle, 'Franc congolais');
      expect(Devise.cdf.symbole, 'CDF');
      expect(Devise.usd.libelle, 'Dollar américain');
      expect(Devise.usd.symbole, r'$');
    });

    test('EtatDevise.fromMap lit la réponse de rpc_devise_etat', () {
      final EtatDevise etat = EtatDevise.fromMap(<String, dynamic>{
        'devise': 'USD',
        'taux_usd_cdf': 2850,
        'taux_entreprise': 2850,
        'taux_plateforme': 2800,
        'devise_plateforme': 'CDF',
        'entreprise_id': 'ent-1',
        'peut_modifier': true,
        'devises': <dynamic>[
          <String, dynamic>{'code': 'CDF', 'libelle': 'Franc congolais'},
          <String, dynamic>{'code': 'USD', 'libelle': 'Dollar américain'},
        ],
      });

      expect(etat.devise, Devise.usd);
      expect(etat.tauxUsdCdf, 2850);
      expect(etat.tauxPropreEntreprise, isTrue);
      expect(etat.entrepriseId, 'ent-1');
      expect(etat.peutModifier, isTrue);
      expect(etat.devises, <Devise>[Devise.cdf, Devise.usd]);
      expect(etat.deviseOpposee, Devise.cdf);
    });

    test('réponse minimale : CDF + taux par défaut, non modifiable', () {
      final EtatDevise etat = EtatDevise.fromMap(<String, dynamic>{});

      expect(etat.devise, Devise.cdf);
      expect(etat.tauxUsdCdf, tauxUsdCdfParDefaut);
      expect(etat.tauxPropreEntreprise, isFalse);
      expect(etat.peutModifier, isFalse);
      expect(etat.devises.length, 2);
    });
  });

  // =========================================================================
  //  2. CONVERSIONS
  // =========================================================================

  group('Devise — taux de conversion', () {
    const EtatDevise etat = EtatDevise(tauxUsdCdf: 2800);

    test('CDF → USD', () {
      expect(
        etat.convertir(28000,
            deviseSource: Devise.cdf, deviseCible: Devise.usd),
        closeTo(10, 1e-9),
      );
      expect(
        etat.convertir(15000,
            deviseSource: Devise.cdf, deviseCible: Devise.usd),
        closeTo(5.357, 1e-3),
      );
    });

    test('USD → CDF', () {
      expect(
        etat.convertir(10, deviseSource: Devise.usd, deviseCible: Devise.cdf),
        closeTo(28000, 1e-9),
      );
    });

    test('même devise : montant inchangé', () {
      expect(
        etat.convertir(1234.5,
            deviseSource: Devise.cdf, deviseCible: Devise.cdf),
        1234.5,
      );
    });

    test('taux nul : garde-fou (taux par défaut, jamais de division par zéro)',
        () {
      const EtatDevise sansTaux = EtatDevise(tauxUsdCdf: 0);
      expect(
        sansTaux.convertir(tauxUsdCdfParDefaut * 2,
            deviseSource: Devise.cdf, deviseCible: Devise.usd),
        closeTo(2, 1e-9),
      );
    });

    test('equivalent() vise toujours l\'autre devise', () {
      const EtatDevise enUsd = EtatDevise(devise: Devise.usd, tauxUsdCdf: 2800);
      expect(enUsd.equivalent(10), closeTo(28000, 1e-9));
      expect(etat.equivalent(28000), closeTo(10, 1e-9));
    });

    test('un taux d\'entreprise prime sur celui de la plateforme', () {
      final EtatDevise etat2 = EtatDevise.fromMap(<String, dynamic>{
        'devise': 'CDF',
        'taux_usd_cdf': 2900,
        'taux_entreprise': 2900,
        'taux_plateforme': 2800,
      });

      expect(etat2.tauxUsdCdf, 2900);
      expect(etat2.tauxPropreEntreprise, isTrue);
      expect(etat2.tauxPlateforme, 2800);
    });
  });

  // =========================================================================
  //  3. FORMATAGE (propagation globale)
  // =========================================================================

  group('FormatMonetaire — devise de l\'application', () {
    test('par défaut : franc congolais, montant entier', () {
      expect(formatMontant(15000), '15 000 CDF');
      expect(formatMontant(1234567), '1 234 567 CDF');
      expect(formatMontant(-500), '-500 CDF');
      expect(formatMontant(0), '0 CDF');
    });

    test('en dollars : deux décimales (les cents comptent)', () {
      FormatMonetaire.definir(code: 'USD', symbole: r'$');

      expect(formatMontant(12.5), r'12,50 $');
      expect(formatMontant(1500), r'1 500,00 $');
      expect(formatMontant(-3.25), r'-3,25 $');
      expect(FormatMonetaire.code, 'USD');
      expect(FormatMonetaire.symbole, r'$');
    });

    test('l\'unité peut être forcée (back-office plateforme en CDF)', () {
      FormatMonetaire.definir(code: 'USD', symbole: r'$');
      expect(formatMontant(20000, devise: deviseParDefaut), '20 000 CDF');
    });

    test('reinitialiser() revient au comportement historique', () {
      FormatMonetaire.definir(code: 'USD', symbole: r'$');
      FormatMonetaire.reinitialiser();
      expect(formatMontant(1000), '1 000 CDF');
    });
  });

  // =========================================================================
  //  4. SERVICE (façade, sans réseau)
  // =========================================================================

  group('DeviseService', () {
    test('sans état chargé : CDF, unité CDF, taux par défaut', () {
      DeviseService.instance.etat.value = null;

      expect(DeviseService.instance.devise, Devise.cdf);
      expect(DeviseService.instance.code, 'CDF');
      expect(DeviseService.instance.symbole, 'CDF');
      expect(DeviseService.instance.taux, tauxUsdCdfParDefaut);
      expect(DeviseService.instance.charge, isFalse);
    });

    test('formater() suit la devise active', () {
      DeviseService.instance.etat.value =
          const EtatDevise(devise: Devise.usd, tauxUsdCdf: 2800);
      FormatMonetaire.definir(code: 'USD', symbole: r'$');

      expect(DeviseService.instance.formater(9.9), r'9,90 $');
      expect(DeviseService.instance.formater(null), '—');
    });

    test('equivalent() affiche l\'équivalent dans l\'autre devise', () {
      DeviseService.instance.etat.value =
          const EtatDevise(devise: Devise.cdf, tauxUsdCdf: 2800);

      expect(DeviseService.instance.equivalent(28000), r'≈ 10,00 $');
      expect(DeviseService.instance.equivalent(0), '');
      expect(DeviseService.instance.equivalent(null), '');
    });

    test('reinitialiser() remet la devise par défaut', () {
      DeviseService.instance.etat.value =
          const EtatDevise(devise: Devise.usd, tauxUsdCdf: 3000);
      FormatMonetaire.definir(code: 'USD', symbole: r'$');

      DeviseService.instance.reinitialiser();

      expect(DeviseService.instance.devise, Devise.cdf);
      expect(FormatMonetaire.symbole, 'CDF');
    });

    test('les messages serveur « CODE|texte » sont nettoyés', () {
      expect(
        DeviseService.messageErreur(
            'DEVISE_INCONNUE|Devise inconnue : choisissez CDF ou USD.'),
        'Devise inconnue : choisissez CDF ou USD.',
      );
      expect(DeviseService.messageErreur('Erreur brute'), 'Erreur brute');
    });
  });
}
