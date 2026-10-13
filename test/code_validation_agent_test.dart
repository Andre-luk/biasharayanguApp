// test/code_validation_agent_test.dart
//
// 🔐 CORRECTIF 69 — TESTS DU CODE DE VALIDATION DE L'AGENT.
//
// Tout ce qui est testé ici est PUR : aucun réseau, aucune base. Ce sont les
// règles qui décident si un agent peut saisir un code, si la Finance doit
// confirmer, et à qui l'application a le droit de MONTRER le code.
//
// Le point le plus important est le dernier groupe : `responsabilite`
// distingue « l'agent n'a rien demandé » de « la Finance n'a pas répondu ».
// Les confondre rendrait la liste des dossiers inexploitable.

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/models/code_validation_agent.dart';
import 'package:biashara_yangu/services/code_validation_agent_service.dart';

/// Une ligne de code de référence, surchargeable.
Map<String, dynamic> _ligne({
  String statut = 'EMIS',
  int minutesRestantes = 3,
  String? code = '482913',
}) {
  return <String, dynamic>{
    'id': 'd1',
    'entreprise_id': 'e1',
    'entreprise_nom': 'Boutique Jambo',
    'motif': 'Création du compte',
    'statut': statut,
    'demande_par_nom': 'Andre Lukengu',
    'demande_le': '2026-10-09T09:00:00Z',
    'emis_le': '2026-10-09T09:01:00Z',
    'emis_par_nom': 'Finance La Perle',
    'expire_le': '2026-10-09T09:06:00Z',
    'minutes_restantes': minutesRestantes,
    'code': code,
  };
}

void main() {
  group('StatutCodeAgent', () {
    test('reconnaît les cinq états écrits par la base', () {
      expect(StatutCodeAgent.fromCode('EN_ATTENTE'), StatutCodeAgent.enAttente);
      expect(StatutCodeAgent.fromCode('EMIS'), StatutCodeAgent.emis);
      expect(StatutCodeAgent.fromCode('UTILISE'), StatutCodeAgent.utilise);
      expect(StatutCodeAgent.fromCode('EXPIRE'), StatutCodeAgent.expire);
      expect(StatutCodeAgent.fromCode('REVOQUE'), StatutCodeAgent.revoque);
    });

    test('un statut inconnu n\'est JAMAIS considéré comme utilisable', () {
      //  Sur un doute, on ne dit pas qu'un code est bon : on dit qu'il est
      //  encore en attente.
      expect(StatutCodeAgent.fromCode('BIDON'), StatutCodeAgent.enAttente);
      expect(StatutCodeAgent.fromCode(null), StatutCodeAgent.enAttente);
      expect(StatutCodeAgent.fromCode(''), StatutCodeAgent.enAttente);
    });
  });

  group('CodeValidationAgent — lecture', () {
    test('lit une demande complète', () {
      final CodeValidationAgent? c =
          CodeValidationAgent.depuisJson(_ligne());

      expect(c, isNotNull);
      expect(c!.entrepriseNom, 'Boutique Jambo');
      expect(c.statut, StatutCodeAgent.emis);
      expect(c.minutesRestantes, 3);
      expect(c.codeDisponible, isTrue);
      expect(c.estOuverte, isTrue);
    });

    test('sans identifiant, la ligne est ignorée', () {
      expect(CodeValidationAgent.depuisJson(<String, dynamic>{'statut': 'EMIS'}),
          isNull);
      expect(CodeValidationAgent.depuisJson('pas un objet'), isNull);
    });

    test('le code absent signifie « le serveur ne me l\'a pas donné »', () {
      //  C'est le cas NORMAL pour un agent : le serveur ne transmet le code
      //  qu'à la Finance et au Super Admin.
      final CodeValidationAgent? c =
          CodeValidationAgent.depuisJson(_ligne(code: null));

      expect(c!.codeDisponible, isFalse);
      expect(c.code, isNull);
    });

    test('un code vide compte comme absent', () {
      final CodeValidationAgent? c =
          CodeValidationAgent.depuisJson(_ligne(code: '   '));
      expect(c!.codeDisponible, isFalse);
    });

    test('nom et motif ne sont jamais vides à l\'écran', () {
      final CodeValidationAgent? c = CodeValidationAgent.depuisJson(
        <String, dynamic>{'id': 'd1', 'entreprise_nom': '  ', 'motif': ''},
      );

      expect(c!.nomAffiche, 'Compte sans nom');
      expect(c.motifAffiche, 'Non précisé');
    });

    test('une liste vide ne lève pas', () {
      expect(CodeValidationAgent.listeDepuisJson(null), isEmpty);
      expect(CodeValidationAgent.listeDepuisJson(<dynamic>[]), isEmpty);
    });
  });

  group('CodeValidationAgent — qui peut faire quoi', () {
    test('l\'agent peut saisir un code émis et encore valable', () {
      final CodeValidationAgent c =
          CodeValidationAgent.depuisJson(_ligne(minutesRestantes: 2))!;
      expect(c.peutEtreSaisi, isTrue);
      expect(c.delaiEcoule, isFalse);
      expect(c.peutContinuerSansCode, isFalse);
    });

    test('un code émis mais dont le délai est écoulé n\'est plus saisissable', () {
      final CodeValidationAgent c =
          CodeValidationAgent.depuisJson(_ligne(minutesRestantes: 0))!;
      expect(c.peutEtreSaisi, isFalse);
      expect(c.delaiEcoule, isTrue);
      //  ⚠️ LA RÈGLE DU PATRON : passé les 5 minutes, l'agent CONTINUE.
      //  Le dispositif n'est pas un verrou.
      expect(c.peutContinuerSansCode, isTrue);
    });

    test('la Finance peut émettre tant que la demande est ouverte', () {
      expect(
        CodeValidationAgent.depuisJson(_ligne(statut: 'EN_ATTENTE', code: null))!
            .peutEtreEmise,
        isTrue,
      );
      expect(
        CodeValidationAgent.depuisJson(_ligne(statut: 'EMIS'))!.peutEtreEmise,
        isTrue,
      );
      expect(
        CodeValidationAgent.depuisJson(_ligne(statut: 'UTILISE'))!.peutEtreEmise,
        isFalse,
      );
      expect(
        CodeValidationAgent.depuisJson(_ligne(statut: 'REVOQUE'))!.peutEtreEmise,
        isFalse,
      );
    });

    test('une demande close n\'est plus ouverte', () {
      for (final String statut in <String>['UTILISE', 'EXPIRE', 'REVOQUE']) {
        expect(
          CodeValidationAgent.depuisJson(_ligne(statut: statut))!.estOuverte,
          isFalse,
          reason: 'statut $statut',
        );
      }
    });

    test('le compte à rebours est lisible, et muet quand c\'est fini', () {
      expect(
        CodeValidationAgent.depuisJson(_ligne(minutesRestantes: 4))!.libelleDelai,
        '4 min restantes',
      );
      expect(
        CodeValidationAgent.depuisJson(_ligne(minutesRestantes: 0))!.libelleDelai,
        'délai écoulé',
      );
      expect(
        CodeValidationAgent.depuisJson(_ligne(statut: 'UTILISE'))!.libelleDelai,
        '',
      );
    });
  });

  group('CodeValidationAgent — traçabilité lisible', () {
    test('les trois étapes sont racontées', () {
      final CodeValidationAgent c = CodeValidationAgent.depuisJson(
        <String, dynamic>{
          ..._ligne(),
          'valide_le': '2026-10-09T09:02:00Z',
          'valide_par_nom': 'Andre Lukengu',
        },
      )!;

      expect(c.resumeDemande, contains('Andre Lukengu'));
      expect(c.resumeEmission, contains('Finance La Perle'));
      expect(c.resumeValidation, contains('Andre Lukengu'));
    });

    test('ce qui n\'est pas encore arrivé est dit clairement', () {
      final CodeValidationAgent c = CodeValidationAgent.depuisJson(
        <String, dynamic>{..._ligne(statut: 'EN_ATTENTE', code: null)},
      )!;

      //  `emis_le` reste renseigné dans la fixture : on teste le cas réel.
      final CodeValidationAgent vierge = CodeValidationAgent.depuisJson(
        <String, dynamic>{'id': 'd1', 'statut': 'EN_ATTENTE'},
      )!;

      expect(vierge.resumeEmission, 'Pas encore émis par la Finance');
      expect(vierge.resumeValidation, 'Pas encore saisi');
      expect(c.nomAffiche, isNotEmpty);
    });

    test('un auteur inconnu est dit honnêtement', () {
      final CodeValidationAgent c = CodeValidationAgent.depuisJson(
        <String, dynamic>{'id': 'd1', 'demande_le': '2026-10-09T09:00:00Z'},
      )!;

      expect(c.resumeDemande, contains('Auteur inconnu'));
    });
  });

  group('DemandeCodeAgent', () {
    test('signale qu\'une demande était déjà ouverte', () {
      final DemandeCodeAgent? d = DemandeCodeAgent.depuisJson(<String, dynamic>{
        'demande_id': 'd1',
        'statut': 'EMIS',
        'deja_ouverte': true,
        'code_emis': true,
      });

      expect(d!.dejaOuverte, isTrue);
      expect(d.codeEmis, isTrue);
      expect(d.statut, StatutCodeAgent.emis);
    });

    test('sans identifiant de demande, rien n\'est renvoyé', () {
      expect(DemandeCodeAgent.depuisJson(<String, dynamic>{'statut': 'EMIS'}),
          isNull);
    });
  });

  group('EmissionCodeAgent', () {
    test('lit le code à transmettre à l\'agent', () {
      final EmissionCodeAgent? e = EmissionCodeAgent.depuisJson(<String, dynamic>{
        'demande_id': 'd1',
        'code': '482913',
      });

      expect(e!.code, '482913');
      expect(e.demandeId, 'd1');
    });

    test('une réponse sans code exploitable est refusée', () {
      //  Sans code, l'écran n'aurait rien à montrer à la Finance — donc rien à
      //  transmettre à l'agent. Mieux vaut l'erreur qu'un écran vide.
      expect(
        EmissionCodeAgent.depuisJson(<String, dynamic>{'demande_id': 'd1'}),
        isNull,
      );
      expect(
        EmissionCodeAgent.depuisJson(<String, dynamic>{'code': '   '}),
        isNull,
      );
    });
  });

  group('DossierSansCode — QUI doit agir', () {
    test('la Finance n\'a pas répondu', () {
      const DossierSansCode d = DossierSansCode(
        entrepriseId: 'e1',
        aDemandeUnCode: true,
        demandeEnAttente: true,
      );
      expect(d.responsabilite, 'La Finance n\'a pas encore répondu');
    });

    test('un code a été demandé mais jamais saisi', () {
      const DossierSansCode d =
          DossierSansCode(entrepriseId: 'e1', aDemandeUnCode: true);
      expect(d.responsabilite, 'Code jamais saisi — à vérifier');
    });

    test('l\'agent n\'a rien demandé', () {
      //  ⚠️ C'est la distinction qui rend la liste exploitable : reprocher à la
      //  Finance de ne pas avoir répondu à une demande qui n'a jamais été
      //  faite enverrait le contrôle au mauvais endroit.
      const DossierSansCode d = DossierSansCode(entrepriseId: 'e1');
      expect(d.responsabilite, 'Aucun code demandé par l\'agent');
    });

    test('sans identifiant, la ligne est ignorée', () {
      expect(DossierSansCode.depuisJson(<String, dynamic>{'nom': 'X'}), isNull);
    });
  });

  group('DossiersSansCode', () {
    test('lit le total du serveur même si la liste est tronquée', () {
      final DossiersSansCode d = DossiersSansCode.depuisJson(<String, dynamic>{
        'total': 12,
        'dossiers': <dynamic>[
          <String, dynamic>{'entreprise_id': 'e1', 'nom': 'A'},
          <String, dynamic>{'entreprise_id': 'e2', 'nom': 'B'},
        ],
      });

      //  Le compte vient du serveur : il reste juste au-delà de la limite.
      expect(d.total, 12);
      expect(d.dossiers.length, 2);
      expect(d.estVide, isFalse);
    });

    test('un tableau vide est reconnu sans lever', () {
      expect(DossiersSansCode.depuisJson(null).estVide, isTrue);
      expect(DossiersSansCode.vide.total, 0);
    });
  });

  group('Erreurs serveur', () {
    test('extrait la raison ET la marche à suivre du refus de code', () {
      //  Le serveur met déjà tout dans le message : on ne reformule pas.
      final String message = CodeValidationAgentService.messageErreur(
        'CODE_REFUSE|Code refuse (CODE_INCORRECT). Verifiez les 6 chiffres '
        'communiques par la Finance.',
        repli: 'repli',
      );

      expect(message, contains('CODE_INCORRECT'));
      expect(message, contains('6 chiffres'));
    });

    test('retombe sur le repli quand il n\'y a pas de texte utile', () {
      expect(CodeValidationAgentService.messageErreur('', repli: 'repli'),
          'repli');
      expect(CodeValidationAgentService.messageErreur('DROIT_REFUSE|',
          repli: 'repli'), 'repli');
    });

    test('classe chaque code serveur dans la bonne nature', () {
      expect(CodeValidationAgentService.typeDepuisMessage('CODE_REFUSE|x'),
          TypeErreurCodeAgent.codeRefuse);
      expect(CodeValidationAgentService.typeDepuisMessage('DROIT_REFUSE|x'),
          TypeErreurCodeAgent.droits);
      expect(CodeValidationAgentService.typeDepuisMessage('SESSION_ABSENTE|x'),
          TypeErreurCodeAgent.session);
      expect(
        CodeValidationAgentService.typeDepuisMessage('CODE_DEJA_UTILISE|x'),
        TypeErreurCodeAgent.close,
      );
      expect(
        CodeValidationAgentService.typeDepuisMessage('DEMANDE_REVOQUEE|x'),
        TypeErreurCodeAgent.close,
      );
      expect(
        CodeValidationAgentService.typeDepuisMessage('DEMANDE_INTROUVABLE|x'),
        TypeErreurCodeAgent.introuvable,
      );
      expect(CodeValidationAgentService.typeDepuisMessage('CODE_REQUIS|x'),
          TypeErreurCodeAgent.validation);
    });

    test('reconnaît une base non migrée (PGRST202)', () {
      //  Tant que la migration 69 n'est pas exécutée, l'écran doit pouvoir le
      //  DIRE au lieu d'afficher une erreur générique.
      expect(
        CodeValidationAgentService.typeDepuisMessage(
            'PGRST202|Could not find the function'),
        TypeErreurCodeAgent.nonDeploye,
      );
    });
  });

  // =========================================================================
  //  CORRECTIF 75 — L'ÉMISSION DU CODE OUVRE LE COMPTE
  // =========================================================================
  //  Le geste de la Finance suffit : le serveur active le compte (essai de
  //  7 jours) et renvoie le résultat. On vérifie la lecture de cette réponse,
  //  y compris ses cas limites, car c'est ce que l'opératrice lit à l'écran.

  group('ActivationParCode', () {
    test('activation réussie : phrase d\'essai', () {
      final EmissionCodeAgent? emission = EmissionCodeAgent.depuisJson(
        <String, dynamic>{
          'ok': true,
          'demande_id': 'd-1',
          'code': '123456',
          'expire_le': '2026-10-13T10:05:00Z',
          'activation': <String, dynamic>{
            'ok': true,
            'deja_actif': false,
            'activation_etape': 'actif',
            'statut': 'ESSAI_7J',
            'essai_jours': 7,
            'date_expiration': '2026-10-20T10:00:00Z',
          },
        },
      );

      expect(emission, isNotNull);
      expect(emission!.code, '123456');
      expect(emission.activation, isNotNull);
      expect(emission.activation!.ok, isTrue);
      expect(emission.activation!.dejaActif, isFalse);
      expect(emission.activation!.etape, 'actif');
      expect(emission.activation!.statut, 'ESSAI_7J');
      expect(emission.activation!.essaiJours, 7);
      expect(emission.activation!.dateExpiration, isNotNull);
      expect(emission.activation!.resume,
          'Compte ACTIVÉ automatiquement — essai de 7 jour(s).');
    });

    test('compte déjà ouvert : rien n\'a changé', () {
      final ActivationParCode? act = ActivationParCode.depuisJson(
        <String, dynamic>{'ok': true, 'deja_actif': true, 'activation_etape': 'actif'},
      );

      expect(act, isNotNull);
      expect(act!.dejaActif, isTrue);
      expect(act.resume, 'Ce compte était déjà ouvert : rien n\'a changé.');
    });

    test('activation refusée : le message du serveur est repris', () {
      final ActivationParCode? act = ActivationParCode.depuisJson(
        <String, dynamic>{
          'ok': false,
          'motif': 'COMPTE_RESTREINT',
          'message': 'Ce compte est restreint : réglez le solde avant de l\'ouvrir.',
        },
      );

      expect(act, isNotNull);
      expect(act!.ok, isFalse);
      expect(act.resume,
          'Ce compte est restreint : réglez le solde avant de l\'ouvrir.');
    });

    test('activation refusée sans message : repli explicite', () {
      final ActivationParCode? act =
          ActivationParCode.depuisJson(<String, dynamic>{'ok': false});

      expect(act, isNotNull);
      expect(act!.resume, contains('n\'a pas pu être ouvert automatiquement'));
    });

    test('essai sans durée connue : phrase sans chiffre', () {
      final ActivationParCode? act = ActivationParCode.depuisJson(
        <String, dynamic>{'ok': true, 'deja_actif': false},
      );

      expect(act!.resume, 'Compte ACTIVÉ automatiquement.');
    });

    test('absence de section activation : champ nul, code toujours lu', () {
      final EmissionCodeAgent? emission = EmissionCodeAgent.depuisJson(
        <String, dynamic>{'demande_id': 'd-2', 'code': '000123'},
      );

      expect(emission, isNotNull);
      expect(emission!.activation, isNull);
      expect(emission.code, '000123');
    });

    test('ActivationParCode.depuisJson tolère une valeur inattendue', () {
      expect(ActivationParCode.depuisJson(null), isNull);
      expect(ActivationParCode.depuisJson('texte'), isNull);
    });
  });
}
