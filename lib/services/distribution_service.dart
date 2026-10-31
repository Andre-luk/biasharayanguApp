// lib/services/distribution_service.dart
//
// 🚚 MODULE 23 — SERVICE DE DISTRIBUTION TERRAIN.
//
// Toutes les écritures passent par les RPC du module (aucune écriture directe
// sur les tables : les droits sont révoqués côté serveur). Le service ne lève
// que [DistributionException], dont le message est toujours en français.

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:biashara_yangu/models/distribution_terrain.dart';
import 'package:biashara_yangu/services/article_service.dart';
import 'package:biashara_yangu/services/supabase_service.dart';
import 'package:biashara_yangu/utils/json_parsing.dart';

/// Erreur métier du module distribution.
class DistributionException implements Exception {
  const DistributionException(this.message, {this.code = ''});

  final String message;
  final String code;

  @override
  String toString() => message;
}

/// Accès Supabase aux tournées, consignes et bonus.
class DistributionService {
  DistributionService._();

  static final DistributionService instance = DistributionService._();

  SupabaseClient get _client => SupabaseService.instance.client;

  // ---------------------------------------------------------------------------
  // OUTILS
  // ---------------------------------------------------------------------------

  /// Traduit un message serveur « CODE|texte » en message lisible.
  static String messageErreur(String? brut) {
    final String texte = (brut ?? '').trim();
    if (texte.isEmpty) {
      return 'Opération impossible : réessayez dans quelques instants.';
    }

    final int separateur = texte.indexOf('|');
    final String message =
        separateur >= 0 ? texte.substring(separateur + 1).trim() : texte;

    const Map<String, String> complements = <String, String>{
      'AUCUNE_TOURNEE':
          'Aucune tournée en cours. Demandez au patron de démarrer votre tournée.',
      'TOURNEE_ACTIVE':
          'Cet agent a déjà une tournée en cours : clôturez-la avant d\'en préparer une nouvelle.',
      'TOURNEE_INTROUVABLE': 'Cette tournée n\'existe plus.',
      'AGENT_INVALIDE': 'Cet agent n\'appartient pas à votre entreprise.',
      'AGENT_REQUIS': 'Choisissez l\'agent qui part en tournée.',
      'LIGNES_VIDES': 'Ajoutez au moins un produit à la dotation.',
      'PRODUIT_NON_ATTRIBUE':
          'Cet article ne fait pas partie de votre dotation du jour.',
      'ATTRIBUTION_EPUISEE': 'Il ne vous reste plus assez de ce produit.',
      'RETOUR_SUPERIEUR':
          'Le retour déclaré dépasse ce qui restait pour cet article.',
      'CONSIGNE_INTROUVABLE': 'Cette consigne n\'existe plus.',
      'QUANTITE_INVALIDE': 'Quantité invalide.',
      'CLIENT_INTROUVABLE': 'Ce client n\'existe plus.',
      'DROIT_REFUSE': 'Votre rôle ne permet pas cette opération.',
      'STATUT_INVALIDE': 'Cette tournée n\'est plus dans un état modifiable.',
      'TAUX_INVALIDE': 'La commission doit être comprise entre 0 et 100 %.',
      'OBJECTIF_INVALIDE': 'L\'objectif ne peut pas être négatif.',
      'TYPE_INVALIDE': 'Type d\'écart inconnu (casse ou bonus).',
      'ECART_SUPERIEUR':
          'La quantité déclarée dépasse ce qui reste dans la dotation.',
      'SESSION_ABSENTE': 'Session expirée : reconnectez-vous.',
      'PGRST202':
          'Le module Distribution n\'est pas encore installé sur le serveur. '
              'Exécutez la migration 20260916000080_module23_distribution_terrain.sql.',
    };

    for (final MapEntry<String, String> e in complements.entries) {
      if (texte.contains(e.key)) return e.value;
    }

    // Message déjà rédigé en français par la base.
    return message.isEmpty ? 'Opération impossible.' : message;
  }

  Future<dynamic> _rpcAppel(String nom, Map<String, dynamic> params) async {
    try {
      return await _client.rpc(nom, params: params);
    } on PostgrestException catch (e) {
      final String codeBrut = (e.message.split('|').first).trim().toUpperCase();
      final bool nonDeploye = (e.code ?? '').toUpperCase() == 'PGRST202' ||
          codeBrut == 'PGRST202' ||
          e.message.contains('Could not find the function');
      throw DistributionException(
        nonDeploye ? messageErreur('PGRST202|') : messageErreur(e.message),
        code: nonDeploye ? 'NON_DEPLOYE' : codeBrut,
      );
    } catch (e) {
      debugPrint('DistributionService.$nom : $e');
      throw const DistributionException(
        'Connexion impossible : vérifiez votre réseau puis réessayez.',
        code: 'RESEAU',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // AGENTS & CLIENTS
  // ---------------------------------------------------------------------------

  /// Agents possibles : le propriétaire lui-même et ses collaborateurs.
  Future<List<AgentDistribution>> listerAgents() async {
    try {
      final String? proprietaire =
          await ArticleService.instance.proprietaireCourant();
      if (proprietaire == null || proprietaire.isEmpty) {
        return const <AgentDistribution>[];
      }

      final List<dynamic> reponse = await _client
          .from('utilisateurs')
          .select('id, nom, prenom, new_role, role, parent_id, valide')
          .or('id.eq.$proprietaire,parent_id.eq.$proprietaire')
          .order('nom', ascending: true);

      final List<AgentDistribution> agents = parseMapList(reponse)
          .where((Map<String, dynamic> u) =>
              parseInt(u['valide'], fallback: 1) != 0)
          .map((Map<String, dynamic> u) {
            final String nom = parseString(u['nom']);
            final String prenom = parseString(u['prenom']);
            final String complet = <String>[nom, prenom]
                .where((String s) => s.trim().isNotEmpty)
                .join(' ');
            return AgentDistribution(
              id: parseString(u['id']),
              nom: complet,
              role:
                  parseString(u['new_role'], fallback: parseString(u['role'])),
            );
          })
          .where((AgentDistribution a) => a.id.isNotEmpty)
          .toList(growable: false);

      return agents;
    } catch (e) {
      debugPrint('DistributionService.listerAgents : $e');
      return const <AgentDistribution>[];
    }
  }

  /// Clients de la boutique (identifiant, nom, zone) pour les consignes.
  Future<List<Map<String, dynamic>>> listerClients() async {
    try {
      final String? proprietaire =
          await ArticleService.instance.proprietaireCourant();
      if (proprietaire == null || proprietaire.isEmpty) {
        return const <Map<String, dynamic>>[];
      }

      final List<dynamic> reponse = await _client
          .from('clients')
          .select('id, nom, telephone')
          .eq('owner_id', proprietaire)
          .order('nom', ascending: true)
          .limit(300);

      return parseMapList(reponse);
    } catch (e) {
      debugPrint('DistributionService.listerClients : $e');
      return const <Map<String, dynamic>>[];
    }
  }

  // ---------------------------------------------------------------------------
  // TOURNÉES
  // ---------------------------------------------------------------------------

  /// Prépare une dotation. [lignes] = `[{produit_id, quantite}]`.
  Future<Map<String, dynamic>> creerTournee({
    required String agentId,
    required List<Map<String, dynamic>> lignes,
    DateTime? date,
    String? zone,
    String? note,
  }) async {
    final DateTime jour = date ?? DateTime.now();
    final Map<String, dynamic>? resultat = parseMap(await _rpcAppel(
      'rpc_tournee_creer',
      <String, dynamic>{
        'p_agent': agentId,
        'p_date': _isoJour(jour),
        'p_zone': _videOuNull(zone),
        'p_note': _videOuNull(note),
        'p_lignes': lignes,
      },
    ));

    if (resultat == null || resultat['ok'] != true) {
      throw const DistributionException(
        'Le serveur n\'a pas confirmé la tournée : réessayez.',
      );
    }
    return resultat;
  }

  Future<void> demarrerTournee(String tourneeId) async {
    await _rpcAppel('rpc_tournee_demarrer', <String, dynamic>{
      'p_tournee': tourneeId,
    });
  }

  /// Fixe l'objectif de chiffre d'affaires et la commission d'une tournée.
  ///
  /// Réservé au propriétaire (contrôle serveur) et refusé après clôture :
  /// la commission ne se renégocie pas une fois les comptes arrêtés.
  Future<void> parametrerTournee(
    String tourneeId, {
    double? objectifMontant,
    double? commissionTaux,
    String? zoneCouverte,
  }) async {
    await _rpcAppel('rpc_tournee_parametrer', <String, dynamic>{
      'p_tournee': tourneeId,
      'p_objectif': objectifMontant,
      'p_commission': commissionTaux,
      'p_zone_couverte': _videOuNull(zoneCouverte),
    });
  }

  /// Déclare une casse ou un bonus sur une ligne de dotation.
  ///
  /// Ces quantités sortent de la dotation **sans** créer de chiffre d'affaires :
  /// un article offert n'est pas une vente, et une bouteille cassée n'en est
  /// pas une non plus. L'écart final reste donc lisible et nommé.
  Future<void> declarerEcart({
    required String tourneeId,
    required int produitId,
    required String type,
    required double quantite,
    String? note,
  }) async {
    await _rpcAppel('rpc_tournee_declarer_ecart', <String, dynamic>{
      'p_tournee': tourneeId,
      'p_produit_id': produitId,
      'p_type': type,
      'p_quantite': quantite,
      'p_note': _videOuNull(note),
    });
  }

  /// Clôture avec les retours déclarés (`[{produit_id, quantite}]`).
  Future<ResultatCloture> cloturerTournee(
    String tourneeId, {
    required List<Map<String, dynamic>> retours,
    TourneeDistribution? modele,
  }) async {
    final Map<String, dynamic>? json = parseMap(await _rpcAppel(
      'rpc_tournee_cloturer',
      <String, dynamic>{
        'p_tournee': tourneeId,
        'p_retours': retours,
      },
    ));

    if (json == null || json['ok'] != true) {
      throw const DistributionException(
        'Le serveur n\'a pas confirmé la clôture : réessayez.',
      );
    }

    final List<LigneTournee> lignes = parseMapList(json['lignes'])
        .map(LigneTournee.depuisCloture)
        .toList(growable: false);

    // Les écarts sont renvoyés NOMMÉS : on les garde pour l'écran de clôture.
    final List<LigneTournee> ecarts = parseMapList(json['ecarts'])
        .map(LigneTournee.depuisCloture)
        .toList(growable: false);

    return ResultatCloture(
      tournee: TourneeDistribution.depuisCloture(json, modele: modele),
      lignes: lignes,
      ecarts: ecarts,
    );
  }

  // ---------------------------------------------------------------------------
  // RADAR (phase 6) — ce qui manque, quoi charger, qui relancer
  // ---------------------------------------------------------------------------

  /// Radar d'une tournée.
  ///
  /// [tourneeId] à `null` : on demande seulement les recommandations de
  /// chargement pour [zone] (utile AVANT de préparer la tournée).
  Future<RadarTournee> radarTournee({String? tourneeId, String? zone}) async {
    final Map<String, dynamic>? json = parseMap(await _rpcAppel(
      'rpc_radar_tournee',
      <String, dynamic>{
        'p_tournee': _videOuNull(tourneeId),
        'p_zone': _videOuNull(zone),
      },
    ));
    if (json == null || json['ok'] != true) return RadarTournee.vide;
    return RadarTournee.depuisJson(json);
  }

  /// Score d'anomalie d'un agent, avec ses motifs chiffrés.
  Future<RadarAgent> radarAgent({String? agentId, int jours = 30}) async {
    final Map<String, dynamic>? json = parseMap(await _rpcAppel(
      'rpc_radar_agent',
      <String, dynamic>{
        'p_agent': _videOuNull(agentId),
        'p_jours': jours,
      },
    ));
    if (json == null || json['ok'] != true) return RadarAgent.vide;
    return RadarAgent.depuisJson(json);
  }

  /// Rapport consolidé par agent.
  Future<RapportDistribution> rapport({
    DateTime? debut,
    DateTime? fin,
    String? agentId,
  }) async {
    final DateTime aujourdhui = DateTime.now();
    final Map<String, dynamic>? json = parseMap(await _rpcAppel(
      'rpc_tournee_rapport',
      <String, dynamic>{
        'p_debut':
            _isoJour(debut ?? aujourdhui.subtract(const Duration(days: 30))),
        'p_fin': _isoJour(fin ?? aujourdhui),
        'p_agent': _videOuNull(agentId),
      },
    ));

    if (json == null) return const RapportDistribution();
    return RapportDistribution.depuisJson(json);
  }

  /// Tournée active de l'agent connecté (`null` s'il n'en a pas).
  Future<MaTournee?> maTournee() async {
    final Map<String, dynamic>? json =
        parseMap(await _rpcAppel('rpc_ma_tournee', const <String, dynamic>{}));
    if (json == null) return null;
    return MaTournee.depuisJson(json);
  }

  /// Vente de l'agent, plafonnée par sa dotation.
  ///
  /// [lignes] = `[{produit_id, quantite}]` (unités de base).
  Future<Map<String, dynamic>> vendre({
    required List<Map<String, dynamic>> lignes,
    String modePaiement = 'especes',
    double? montantRecu,
    String? numeroTransaction,
    int? clientId,
  }) async {
    final Map<String, dynamic>? json = parseMap(await _rpcAppel(
      'rpc_tournee_vente',
      <String, dynamic>{
        'p_lignes': lignes,
        'p_mode_paiement': modePaiement,
        'p_montant_recu': montantRecu,
        'p_numero_transaction': _videOuNull(numeroTransaction),
        'p_client_id': clientId,
      },
    ));

    if (json == null) {
      throw const DistributionException(
        'Réponse inattendue du serveur : la vente n\'est pas confirmée.',
      );
    }
    return json;
  }

  // ---------------------------------------------------------------------------
  // CONSIGNES & BONUS
  // ---------------------------------------------------------------------------

  Future<void> enregistrerConsigne({
    int? clientId,
    String? clientNom,
    String? zone,
    String libelle = 'Récipient',
    required int quantite,
    String? note,
  }) async {
    await _rpcAppel('rpc_consigne_enregistrer', <String, dynamic>{
      'p_client_id': clientId,
      'p_client_nom': _videOuNull(clientNom),
      'p_zone': _videOuNull(zone),
      'p_libelle': libelle,
      'p_quantite': quantite,
      'p_note': _videOuNull(note),
    });
  }

  Future<int> recupererConsigne(String consigneId, int quantite) async {
    final Map<String, dynamic>? json = parseMap(await _rpcAppel(
      'rpc_consigne_recuperer',
      <String, dynamic>{
        'p_consigne': consigneId,
        'p_quantite': quantite,
      },
    ));
    return parseInt(json?['restant']);
  }

  Future<void> enregistrerBonus({
    int? clientId,
    String? clientNom,
    String nature = 'remise',
    double montant = 0,
    String? description,
  }) async {
    await _rpcAppel('rpc_bonus_enregistrer', <String, dynamic>{
      'p_client_id': clientId,
      'p_client_nom': _videOuNull(clientNom),
      'p_nature': nature,
      'p_montant': montant,
      'p_description': _videOuNull(description),
    });
  }

  /// Compteurs de la carte d'accueil (best-effort).
  Future<CompteursDistribution> compteurs() async {
    try {
      final Map<String, dynamic>? json = parseMap(
        await _client.rpc('rpc_distribution_accueil'),
      );
      if (json == null) return CompteursDistribution.vide;
      return CompteursDistribution.depuisJson(json);
    } catch (e) {
      debugPrint('DistributionService.compteurs (ignoré) : $e');
      return CompteursDistribution.vide;
    }
  }

  /// Détail des lignes d'une tournée (lecture directe, RLS du module).
  Future<List<LigneTournee>> lignesTournee(String tourneeId) async {
    try {
      final List<dynamic> reponse = await _client
          .from('tournee_lignes')
          .select('produit_id, nom_produit, unite, quantite_attribuee, '
              'quantite_vendue, quantite_retournee, prix_vente')
          .eq('tournee_id', tourneeId)
          .order('nom_produit', ascending: true);

      return parseMapList(reponse).map((Map<String, dynamic> l) {
        final double attribuee = parseDouble(l['quantite_attribuee']);
        final double vendue = parseDouble(l['quantite_vendue']);
        final double retournee = parseDouble(l['quantite_retournee']);
        return LigneTournee(
          produitId: parseInt(l['produit_id']),
          nom: parseString(l['nom_produit']),
          unite: parseString(l['unite']),
          attribuee: attribuee,
          vendue: vendue,
          retournee: retournee,
          restante: attribuee - vendue - retournee,
          prixVente: parseDouble(l['prix_vente']),
        );
      }).toList(growable: false);
    } catch (e) {
      debugPrint('DistributionService.lignesTournee : $e');
      return const <LigneTournee>[];
    }
  }

  /// Consignes rattachées à une tournée.
  Future<List<ConsigneRecipient>> consignesDeTournee(String tourneeId) async {
    try {
      final List<dynamic> reponse = await _client
          .from('consignes')
          .select('id, client_id, client_nom, zone, libelle_contenant, '
              'quantite, quantite_recuperee, statut, date_consigne')
          .eq('tournee_id', tourneeId)
          .order('date_consigne', ascending: false);

      return parseMapList(reponse).map((Map<String, dynamic> c) {
        return ConsigneRecipient(
          id: parseString(c['id']),
          clientId: int.tryParse('${c['client_id']}'),
          clientNom: parseString(c['client_nom']),
          zone: parseString(c['zone']),
          libelle: parseString(c['libelle_contenant'], fallback: 'Récipient'),
          quantite: parseInt(c['quantite']),
          recuperee: parseInt(c['quantite_recuperee']),
          statut: parseString(c['statut'], fallback: 'chez_client'),
          date: parseDateTimeOrNull(c['date_consigne']),
        );
      }).toList(growable: false);
    } catch (e) {
      debugPrint('DistributionService.consignesDeTournee : $e');
      return const <ConsigneRecipient>[];
    }
  }

  /// Bonus rattachés à une tournée.
  Future<List<BonusClient>> bonusDeTournee(String tourneeId) async {
    try {
      final List<dynamic> reponse = await _client
          .from('bonus_clients')
          .select('id, client_nom, nature, montant, description, date_bonus')
          .eq('tournee_id', tourneeId)
          .order('date_bonus', ascending: false);

      return parseMapList(reponse).map((Map<String, dynamic> b) {
        return BonusClient(
          id: parseString(b['id']),
          clientNom: parseString(b['client_nom']),
          nature: parseString(b['nature'], fallback: 'remise'),
          montant: parseDouble(b['montant']),
          description: parseString(b['description']),
          date: parseDateTimeOrNull(b['date_bonus']),
        );
      }).toList(growable: false);
    } catch (e) {
      debugPrint('DistributionService.bonusDeTournee : $e');
      return const <BonusClient>[];
    }
  }

  // ---------------------------------------------------------------------------
  // TEMPS RÉEL
  // ---------------------------------------------------------------------------

  /// Écoute les changements des tables du module pour [ownerId].
  ///
  /// Renvoie le canal : l'appelant doit le libérer avec [arreterEcoute].
  RealtimeChannel ecouterChangements(String ownerId, void Function() onChange) {
    final RealtimeChannel canal = _client.channel(
      'distribution-$ownerId-${DateTime.now().microsecondsSinceEpoch}',
    );

    void notifier(PostgresChangePayload payload) => onChange();

    canal
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'tournees',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'owner_id',
            value: ownerId,
          ),
          callback: notifier,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'consignes',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'owner_id',
            value: ownerId,
          ),
          callback: notifier,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'bonus_clients',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'owner_id',
            value: ownerId,
          ),
          callback: notifier,
        )
        .subscribe();

    return canal;
  }

  Future<void> arreterEcoute(RealtimeChannel canal) async {
    try {
      await _client.removeChannel(canal);
    } catch (e) {
      debugPrint('DistributionService.arreterEcoute : $e');
    }
  }

  static String _isoJour(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  static String? _videOuNull(String? valeur) {
    final String t = (valeur ?? '').trim();
    return t.isEmpty ? null : t;
  }
}
