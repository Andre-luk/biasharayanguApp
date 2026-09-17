// test/agent_ia_test.dart
//
// Tests unitaires du MODULE 13 — Assistant IA DeepSeek & quotas.
//
// Tout est PUR (aucun réseau, aucun Supabase) :
//   • modèles (`AgentIaConfig`, `PackQuotas`, `EtatAgentIa`, `AchatQuotas`,
//     `ReponseAgent`, `MessageAgent`) ;
//   • outils statiques du service (`mapDepuis`, `exceptionDepuis`,
//     `messageErreur`) — le pont entre l'Edge Function et l'interface ;
//   • catalogue des libellés d'outils (35 outils, chiffre du cahier des
//     charges).
//
//     flutter test test/agent_ia_test.dart
//
// Les tests d'intégration (RPC, Edge Function) sont couverts par les
// migrations SQL validées (`check3.js`) et le déploiement.

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/models/agent_ia.dart';
import 'package:biashara_yangu/services/agent_service.dart';

// =============================================================================
// Données de test
// =============================================================================

Map<String, dynamic> _configJson() => <String, dynamic>{
      'tarif_par_quota': 150,
      'caracteres_par_quota': 20,
      'prix_pack_10_quotas': 1000,
      'quotas_offerts_inscription': 5,
      'actif': true,
    };

Map<String, dynamic> _etatJson() => <String, dynamic>{
      'config': _configJson(),
      'pool': <String, dynamic>{
        'quotas_disponibles': 18,
        'quotas_utilises_total': 12,
        'quotas_achetes_total': 30,
      },
      'moi': <String, dynamic>{
        'quotas_disponibles': 7,
        'quotas_utilises_total': 3,
        'quotas_achetes_total': 10,
      },
      'role': 'PROPRIETAIRE',
      'est_proprietaire': true,
      'est_plateforme': false,
      'est_super_admin': false,
      'collaborateurs': <dynamic>[
        <String, dynamic>{'id': 'u-1', 'nom': 'Nadine', 'role': 'VENDEUR'},
        <String, dynamic>{'id': 'u-2', 'nom': 'Josué', 'role': 'MAGASINIER'},
      ],
    };

// =============================================================================
// 1. AGENT IA CONFIG
// =============================================================================

void main() {
  group('AgentIaConfig', () {
    test('les défauts respectent le cahier des charges (150 CDF / 20 car.)',
        () {
      expect(AgentIaConfig.defaut.tarifParQuota, 150);
      expect(AgentIaConfig.defaut.caracteresParQuota, 20);
      expect(AgentIaConfig.defaut.prixPack10Quotas, 1000);
      expect(AgentIaConfig.defaut.quotasOffertsInscription, 5);
      expect(AgentIaConfig.defaut.actif, isTrue);
    });

    test('depuisJson lit la ligne de `agent_ia_config`', () {
      final AgentIaConfig config = AgentIaConfig.depuisJson(_configJson())!;

      expect(config.tarifParQuota, 150);
      expect(config.caracteresParQuota, 20);
      expect(config.prixPack10Quotas, 1000);
      expect(config.quotasOffertsInscription, 5);
      expect(config.actif, isTrue);
    });

    test('les colonnes absentes retombent sur les valeurs par défaut', () {
      final AgentIaConfig config =
          AgentIaConfig.depuisJson(<String, dynamic>{})!;

      expect(config.tarifParQuota, AgentIaConfig.defaut.tarifParQuota);
      expect(config.caracteresParQuota, AgentIaConfig.defaut.caracteresParQuota);
      expect(config.prixPack10Quotas, AgentIaConfig.defaut.prixPack10Quotas);
      // `actif` absent ≠ désactivé : l'assistant reste actif par défaut.
      expect(config.actif, isTrue);
    });

    test('actif: false désactive explicitement l\'assistant', () {
      final AgentIaConfig config = AgentIaConfig.depuisJson(
        <String, dynamic>{'actif': false},
      )!;
      expect(config.actif, isFalse);
    });

    test('une valeur illisible renvoie null (jamais une exception)', () {
      expect(AgentIaConfig.depuisJson(null), isNull);
      expect(AgentIaConfig.depuisJson('pas un objet'), isNull);
      expect(AgentIaConfig.depuisJson(42), isNull);
    });
  });

  // ===========================================================================
  // 2. PACKS DE QUOTAS
  // ===========================================================================

  group('PackQuotas', () {
    test('les 4 packs officiels : 10 · 20 · 50 · 100 quotas', () {
      final List<PackQuotas> packs =
          PackQuotas.depuisConfig(AgentIaConfig.defaut);

      expect(packs.map((PackQuotas p) => p.quotas).toList(),
          <int>[10, 20, 50, 100]);
      // Packs du cahier des charges : 1000 · 2000 · 5000 · 10000 CDF.
      expect(packs.map((PackQuotas p) => p.prix).toList(),
          <double>[1000, 2000, 5000, 10000]);
    });

    test('le prix est proportionnel au pack de 10 (défaut 100 CDF/quota)', () {
      final List<PackQuotas> packs =
          PackQuotas.depuisConfig(AgentIaConfig.defaut);

      for (final PackQuotas pack in packs) {
        expect(pack.prixParQuota, 100, reason: 'pack ${pack.quotas}');
      }
    });

    test('un prix de pack personnalisé se répercute proportionnellement', () {
      const AgentIaConfig config = AgentIaConfig(
        tarifParQuota: 120,
        caracteresParQuota: 25,
        prixPack10Quotas: 1200,
        quotasOffertsInscription: 10,
        actif: true,
      );

      final List<PackQuotas> packs = PackQuotas.depuisConfig(config);
      expect(packs.first.prix, 1200);
      expect(packs.last.quotas, 100);
      expect(packs.last.prix, 12000);
      expect(packs.last.prixParQuota, 120);
    });

    test('prixParQuota ne divise jamais par zéro', () {
      const PackQuotas pack = PackQuotas(quotas: 0, prix: 500);
      expect(pack.prixParQuota, 0);
    });
  });

  // ===========================================================================
  // 3. SOLDES & ÉTAT
  // ===========================================================================

  group('SoldeQuotas', () {
    test('lit les trois compteurs', () {
      final SoldeQuotas solde = SoldeQuotas.depuisJson(<String, dynamic>{
        'quotas_disponibles': 25,
        'quotas_utilises_total': 5,
        'quotas_achetes_total': 30,
      })!;

      expect(solde.quotasDisponibles, 25);
      expect(solde.quotasUtilisesTotal, 5);
      expect(solde.quotasAchetesTotal, 30);
    });

    test('les compteurs absents valent zéro', () {
      final SoldeQuotas solde =
          SoldeQuotas.depuisJson(<String, dynamic>{})!;

      expect(solde.quotasDisponibles, 0);
      expect(solde.quotasUtilisesTotal, 0);
      expect(solde.quotasAchetesTotal, 0);
    });

    test('vide et les valeurs illisibles', () {
      expect(SoldeQuotas.vide.quotasDisponibles, 0);
      expect(SoldeQuotas.depuisJson(null), isNull);
    });
  });

  group('MembreQuota', () {
    test('lit un collaborateur', () {
      final MembreQuota membre = MembreQuota.depuisJson(<String, dynamic>{
        'id': 'u-9',
        'nom': 'Grâce',
        'role': 'MAGASINIER',
      })!;

      expect(membre.id, 'u-9');
      expect(membre.nom, 'Grâce');
      expect(membre.role, 'MAGASINIER');
    });

    test('le nom manquant est remplacé (jamais vide à l\'écran)', () {
      final MembreQuota membre = MembreQuota.depuisJson(
        <String, dynamic>{'id': 'u-9'},
      )!;
      expect(membre.nom, 'Collaborateur');
    });
  });

  group('EtatAgentIa', () {
    test('depuisRpc lit la réponse complète de `rpc_agent_ia_etat`', () {
      final EtatAgentIa etat = EtatAgentIa.depuisRpc(_etatJson())!;

      expect(etat.config.tarifParQuota, 150);
      expect(etat.pool!.quotasDisponibles, 18);
      expect(etat.moi.quotasDisponibles, 7);
      expect(etat.role, 'PROPRIETAIRE');
      expect(etat.estProprietaire, isTrue);
      expect(etat.estPlateforme, isFalse);
      expect(etat.estSuperAdmin, isFalse);
      expect(etat.collaborateurs.length, 2);
      expect(etat.collaborateurs.first.nom, 'Nadine');
      expect(etat.collaborateurs.last.role, 'MAGASINIER');
    });

    test('sans config ni soldes : replis sûrs (jamais null)', () {
      final EtatAgentIa etat = EtatAgentIa.depuisRpc(
        <String, dynamic>{'role': 'VENDEUR'},
      )!;

      expect(etat.config.tarifParQuota, AgentIaConfig.defaut.tarifParQuota);
      expect(etat.pool, isNull); // personnel plateforme ou entreprise sans pool
      expect(etat.moi.quotasDisponibles, 0);
      expect(etat.estProprietaire, isFalse);
      expect(etat.collaborateurs, isEmpty);
    });

    test('les drapeaux ne sont vrais que si le serveur le dit', () {
      final EtatAgentIa etat = EtatAgentIa.depuisRpc(<String, dynamic>{
        'est_proprietaire': true,
        'est_super_admin': false,
        'est_plateforme': false,
      })!;

      expect(etat.estProprietaire, isTrue);
      expect(etat.estSuperAdmin, isFalse);
      expect(etat.estPlateforme, isFalse);
    });

    test('une réponse illisible renvoie null', () {
      expect(EtatAgentIa.depuisRpc(null), isNull);
      expect(EtatAgentIa.depuisRpc('oops'), isNull);
      expect(EtatAgentIa.defaut.moi.quotasDisponibles, 0);
    });
  });

  // ===========================================================================
  // 4. ACHATS / DEMANDES DE QUOTAS
  // ===========================================================================

  group('AchatQuotas', () {
    test('une demande en attente, impayée, avec son MONTANT affiché', () {
      final AchatQuotas achat = AchatQuotas.depuisJson(<String, dynamic>{
        'id': 'a-1',
        'utilisateur_id': 'u-1',
        'nombre_quotas': 20,
        'montant_cdf': 2000,
        'mode_paiement': 'mobile_money',
        'statut': 'demande',
        'statut_paiement': 'impaye',
        'note': 'Via M-Pesa',
        'created_at': '2026-09-16T10:30:00Z',
      })!;

      expect(achat.enAttente, isTrue);
      expect(achat.approuve, isFalse);
      expect(achat.refuse, isFalse);
      expect(achat.impaye, isTrue);
      expect(achat.paye, isFalse);
      // ⚠️ Exigence métier : le montant est TOUJOURS visible.
      expect(achat.montantCdf, 2000);
      expect(achat.nombreQuotas, 20);
      expect(achat.modePaiement, 'mobile_money');
      expect(achat.note, 'Via M-Pesa');
      expect(achat.createdAt, isNotNull);
      expect(achat.valideLe, isNull);
    });

    test('un achat approuvé et payé', () {
      final AchatQuotas achat = AchatQuotas.depuisJson(<String, dynamic>{
        'id': 'a-2',
        'utilisateur_id': 'u-1',
        'nombre_quotas': 50,
        'montant_cdf': 5000,
        'statut': 'approuve',
        'statut_paiement': 'paye',
        'valide_le': '2026-09-16T12:00:00Z',
      })!;

      expect(achat.approuve, isTrue);
      expect(achat.paye, isTrue);
      expect(achat.impaye, isFalse);
      expect(achat.valideLe, isNotNull);
      // Les défauts serveur s'appliquent aux colonnes absentes.
      expect(achat.modePaiement, 'especes');
    });

    test('une demande refusée n\'est ni en attente ni approuvée', () {
      final AchatQuotas achat = AchatQuotas.depuisJson(<String, dynamic>{
        'id': 'a-3',
        'statut': 'refuse',
        'statut_paiement': 'impaye',
      })!;

      expect(achat.refuse, isTrue);
      expect(achat.enAttente, isFalse);
      expect(achat.approuve, isFalse);
    });

    test('avecDemandeur renseigne le nom sans rien perdre', () {
      final AchatQuotas achat = AchatQuotas.depuisJson(<String, dynamic>{
        'id': 'a-4',
        'utilisateur_id': 'u-7',
        'nombre_quotas': 10,
        'montant_cdf': 1000,
        'statut': 'demande',
        'statut_paiement': 'impaye',
      })!;

      final AchatQuotas nomme = achat.avecDemandeur('Nadine');

      expect(nomme.id, achat.id);
      expect(nomme.utilisateurId, 'u-7');
      expect(nomme.utilisateurNom, 'Nadine');
      expect(nomme.montantCdf, 1000);
      expect(nomme.statut, 'demande');
    });

    test('une valeur illisible renvoie null', () {
      expect(AchatQuotas.depuisJson(null), isNull);
      expect(AchatQuotas.depuisJson('nope'), isNull);
    });
  });

  // ===========================================================================
  // 5. RÉPONSE DE L'AGENT
  // ===========================================================================

  group('ReponseAgent', () {
    test('lit la réponse complète de l\'Edge Function', () {
      final ReponseAgent reponse =
          ReponseAgent.depuisJson(<String, dynamic>{
        'reponse': 'Vous avez vendu 12 articles aujourd\'hui pour 45 000 CDF.',
        'quotas_consommes': 3,
        'montant_cdf': 450,
        'solde_restant': 97,
        'caracteres_reponse': 55,
        'actions': <dynamic>[
          <String, dynamic>{'outil': 'lister_ventes_du_jour', 'succes': true},
        ],
      })!;

      expect(reponse.quotasConsommes, 3);
      expect(reponse.montantCdf, 450);
      expect(reponse.soldeRestant, 97);
      expect(reponse.caracteresReponse, 55);
      expect(reponse.actions.length, 1);
      expect(reponse.actions.first.outil, 'lister_ventes_du_jour');
      expect(reponse.actions.first.succes, isTrue);
    });

    test('sans actions : liste vide, jamais null', () {
      final ReponseAgent reponse = ReponseAgent.depuisJson(<String, dynamic>{
        'reponse': 'Bonjour !',
      })!;

      expect(reponse.actions, isEmpty);
      expect(reponse.quotasConsommes, 0);
      expect(reponse.montantCdf, 0);
    });

    test('une réponse illisible renvoie null', () {
      expect(ReponseAgent.depuisJson(null), isNull);
      expect(ReponseAgent.depuisJson(123), isNull);
    });
  });

  group('ActionAgent', () {
    test('succes vaut true par défaut (le serveur ne l\'omet qu\'en erreur)',
        () {
      final ActionAgent action =
          ActionAgent.depuisJson(<String, dynamic>{'outil': 'creer_vente'})!;
      expect(action.succes, isTrue);
    });

    test('un échec est honoré', () {
      final ActionAgent action =
          ActionAgent.depuisJson(<String, dynamic>{
        'outil': 'supprimer_produit',
        'succes': false,
      })!;
      expect(action.succes, isFalse);
    });

    test('le libellé français est celui du catalogue', () {
      final ActionAgent action =
          ActionAgent.depuisJson(<String, dynamic>{'outil': 'creer_vente'})!;
      expect(action.libelle, 'Vente enregistrée');
    });
  });

  // ===========================================================================
  // 6. CATALOGUE DES 35 OUTILS
  // ===========================================================================

  group('Libellés des outils', () {
    // Les 35 outils exposés à DeepSeek (Étapes 5 & 8 du Module 13).
    const List<String> outils = <String>[
      // VENTES
      'rechercher_produit', 'creer_vente', 'annuler_vente',
      'lister_ventes_du_jour', 'lister_ventes_periode',
      // PRODUITS & STOCK
      'ajouter_produit', 'modifier_produit', 'supprimer_produit',
      'consulter_stock', 'lister_stock_faible', 'ajouter_stock',
      'ajuster_stock', 'rechercher_produit_par_qr',
      // FINANCE
      'consulter_caisse', 'ajouter_depense', 'lister_depenses_periode',
      'consulter_dettes_client', 'enregistrer_paiement_dette',
      // CLIENTS
      'ajouter_client', 'rechercher_client', 'lister_clients',
      // RAPPORTS
      'generer_rapport_ventes', 'rapport_top_produits',
      'rapport_chiffre_affaires', 'rapport_stock',
      // COLLABORATEURS
      'lister_collaborateurs', 'ajouter_collaborateur',
      'modifier_role_collaborateur',
      // ABONNEMENT
      'consulter_abonnement', 'voir_jours_restants',
      'enregistrer_paiement_abonnement',
      // QR
      'generer_qr_produit', 'imprimer_etiquettes',
      // INFO
      'informations_entreprise', 'statistiques_globales',
    ];

    test('le catalogue compte bien 35 outils', () {
      expect(outils.length, 35);
      expect(outils.toSet().length, 35); // aucun doublon
    });

    test('chaque outil possède un libellé français dédié', () {
      for (final String outil in outils) {
        final String libelle = libelleOutil(outil);
        expect(libelle, isNotEmpty, reason: outil);
        expect(libelle, isNot(contains('_')), reason: outil);
        // Un libellé brut « rechercher produit » signerait une entrée
        // manquante dans le catalogue.
        expect(libelle.replaceAll('\'', ' '),
            isNot(outil.replaceAll('_', ' ')),
            reason: outil);
      }
    });

    test('un outil inconnu retombe proprement sur son code lisible', () {
      expect(libelleOutil('outil_du_futur'), 'outil du futur');
      expect(libelleOutil(''), '');
    });

    test('quelques libellés vérifiés au mot près', () {
      expect(libelleOutil('creer_vente'), 'Vente enregistrée');
      expect(libelleOutil('annuler_vente'), 'Annulation de vente');
      expect(libelleOutil('supprimer_produit'), 'Article supprimé');
      expect(libelleOutil('consulter_caisse'), 'Caisse');
      expect(libelleOutil('statistiques_globales'), 'Statistiques plateforme');
    });
  });

  // ===========================================================================
  // 7. OUTILS STATIQUES DU SERVICE
  // ===========================================================================

  group('AgentService.mapDepuis', () {
    test('accepte une Map déjà construite', () {
      final Map<String, dynamic> map = <String, dynamic>{'erreur': 'X'};
      final Map<String, dynamic>? lu = AgentService.mapDepuis(map);
      expect(lu, isNotNull);
      expect(lu!['erreur'], 'X');
      expect(lu, equals(map));
    });

    test('accepte une chaîne JSON (détails de FunctionException)', () {
      final Map<String, dynamic>? map = AgentService.mapDepuis(
        '{"erreur":"QUOTAS_EPUISES","solde":0}',
      );
      expect(map, isNotNull);
      expect(map!['erreur'], 'QUOTAS_EPUISES');
      expect(map['solde'], 0);
    });

    test('renvoie null pour tout le reste', () {
      expect(AgentService.mapDepuis(null), isNull);
      expect(AgentService.mapDepuis(''), isNull);
      expect(AgentService.mapDepuis('   '), isNull);
      expect(AgentService.mapDepuis('{ pas du json'), isNull);
      expect(AgentService.mapDepuis(42), isNull);
      // Une chaîne JSON qui n'est pas un objet JSON.
      expect(AgentService.mapDepuis('[1,2,3]'), isNull);
    });
  });

  group('AgentService.exceptionDepuis', () {
    test('QUOTAS_EPUISES transporte le solde et les tarifs d\'achat', () {
      final AgentServiceException e = AgentService.exceptionDepuis(
        <String, dynamic>{
          'erreur': 'QUOTAS_EPUISES',
          'message': 'Vos quotas sont épuisés.',
          'solde': 0,
          'tarif_par_quota': 150,
          'prix_pack_10_quotas': 1000,
        },
      );

      expect(e.type, TypeErreurAgent.quotas);
      expect(e.code, 'QUOTAS_EPUISES');
      expect(e.message, 'Vos quotas sont épuisés.');
      expect(e.solde, 0);
      expect(e.tarifParQuota, 150);
      expect(e.prixPack10Quotas, 1000);
    });

    test('chaque code serveur tombe dans la bonne famille', () {
      const Map<String, TypeErreurAgent> attendus = <String, TypeErreurAgent>{
        'SESSION_ABSENTE': TypeErreurAgent.session,
        'QUOTAS_EPUISES': TypeErreurAgent.quotas,
        'ABONNEMENT_EXPIRE': TypeErreurAgent.abonnement,
        'ABONNEMENT_BLOQUE': TypeErreurAgent.abonnement,
        'LIMITE_MESSAGES': TypeErreurAgent.limite,
        'LIMITE_CARACTERES': TypeErreurAgent.limite,
        'ASSISTANT_DESACTIVE': TypeErreurAgent.assistant,
        'ASSISTANT_INDISPONIBLE': TypeErreurAgent.assistant,
        'SECRET_MANQUANT': TypeErreurAgent.assistant,
        'NON_DEPLOYE': TypeErreurAgent.assistant,
        'DROIT_REFUSE': TypeErreurAgent.droits,
        'ACCES_REFUSE': TypeErreurAgent.droits,
        'CODE_INCONNU': TypeErreurAgent.inconnu,
      };

      attendus.forEach((String code, TypeErreurAgent type) {
        final AgentServiceException e = AgentService.exceptionDepuis(
          <String, dynamic>{'erreur': code, 'message': 'msg'},
        );
        expect(e.type, type, reason: code);
        expect(e.code, code);
      });
    });

    test('le code est normalisé en majuscules et le message a un repli', () {
      final AgentServiceException e = AgentService.exceptionDepuis(
        <String, dynamic>{'erreur': 'droits_insuffisants'},
      );

      expect(e.code, 'DROITS_INSUFFISANTS');
      expect(e.type, TypeErreurAgent.inconnu);
      expect(e.message, 'L\'assistant a refusé la demande.');
      expect(e.solde, isNull);
      expect(e.tarifParQuota, isNull);
    });
  });

  group('AgentService.messageErreur', () {
    test('extrait le message après `CODE|` (convention du projet)', () {
      expect(
        AgentService.messageErreur('DROIT_REFUSE|Votre rôle ne permet pas.'),
        'Votre rôle ne permet pas.',
      );
      expect(
        AgentService.messageErreur('QUOTAS_EPUISES|Soldes insuffisants.'),
        'Soldes insuffisants.',
      );
    });

    test('renvoie le texte tel quel sans séparateur exploitable', () {
      expect(AgentService.messageErreur('Erreur réseau'), 'Erreur réseau');
      expect(AgentService.messageErreur('  espaces  '), 'espaces');
      // Un `|` final ne doit pas produire un message vide.
      expect(AgentService.messageErreur('CODE|'), 'CODE|');
    });
  });

  // ===========================================================================
  // 8. MESSAGES DU CHAT (état local de l'écran)
  // ===========================================================================

  group('MessageAgent', () {
    test('distingue l\'utilisateur de l\'assistant', () {
      const MessageAgent utilisateur =
          MessageAgent(role: 'user', contenu: 'Combien de ventes ?');
      const MessageAgent assistant =
          MessageAgent(role: 'assistant', contenu: '12 ventes.');

      expect(utilisateur.deUtilisateur, isTrue);
      expect(assistant.deUtilisateur, isFalse);
    });

    test('les valeurs par défaut d\'une bulle simple', () {
      const MessageAgent message =
          MessageAgent(role: 'assistant', contenu: 'Bonjour');

      expect(message.actions, isEmpty);
      expect(message.quotasConsommes, 0);
      expect(message.montantCdf, 0);
      expect(message.erreur, isFalse);
      expect(message.codeErreur, isNull);
    });

    test('une bulle d\'erreur typée (blocage quotas) est décrite', () {
      const MessageAgent message = MessageAgent(
        role: 'assistant',
        contenu: 'Quotas épuisés.',
        erreur: true,
        codeErreur: 'QUOTAS_EPUISES',
        quotasConsommes: 0,
        montantCdf: 0,
      );

      expect(message.erreur, isTrue);
      expect(message.codeErreur, 'QUOTAS_EPUISES');
    });
  });
}
