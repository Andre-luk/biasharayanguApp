// lib/services/distribution_hors_ligne_service.dart
//
// 🚚 MODULE 24 §12 — HORS-LIGNE DU COMMERCIAL.
//
// Principe : les opérations sont D'ABORD écrites dans une file locale
// (persistée), puis rejouées au serveur dès que la connexion revient.
//
//   file locale  →  synchronisation  →  RPC `dist_*`
//
// Garanties :
//   • chaque opération porte un identifiant unique généré sur l'appareil
//     (`reference_locale`) ; le serveur refuse de créer deux fois la même
//     (index unique partiel + retour de l'existant, migration 0105) ;
//   • une opération dont l'envoi a échoué en cours de route passe en
//     « à vérifier » et n'est JAMAIS rejouée automatiquement : mieux vaut
//     demander au commercial de contrôler que de vendre deux fois ;
//   • une erreur métier (stock insuffisant, produit inconnu…) place
//     l'opération en « conflit » avec son message, et la file s'arrête
//     (les opérations suivantes peuvent en dépendre) ;
//   • le serveur reste la source de vérité : la file ne fait que rejouer.
//
// Le stock local n'est JAMAIS décrémenté en double : la vente hors ligne est
// une intention ; c'est le serveur qui débite le stock à la synchronisation.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'package:biashara_yangu/models/distribution_gestion.dart';
import 'package:biashara_yangu/services/distribution_gestion_service.dart';

/// Nature d'une opération mise en file.
enum TypeOperationHorsLigne {
  vente('vente', 'Vente'),
  bonus('bonus', 'Bonus / dommage');

  const TypeOperationHorsLigne(this.code, this.libelle);

  final String code;
  final String libelle;

  static TypeOperationHorsLigne depuisCode(String? code) {
    for (final TypeOperationHorsLigne t in values) {
      if (t.code == (code ?? '').trim()) return t;
    }
    return TypeOperationHorsLigne.vente;
  }
}

/// État d'une opération en file.
enum StatutHorsLigne {
  /// Attend la connexion : sera rejouée automatiquement.
  enAttente('en_attente', 'En attente'),

  /// Envoi interrompu (réponse perdue) : à contrôler avant de rejouer.
  aVerifier('a_verifier', 'À vérifier'),

  /// Refusée par le serveur (stock, produit…) : l'utilisateur doit trancher.
  conflit('conflit', 'Conflit');

  const StatutHorsLigne(this.code, this.libelle);

  final String code;
  final String libelle;

  static StatutHorsLigne depuisCode(String? code) {
    for (final StatutHorsLigne s in values) {
      if (s.code == (code ?? '').trim()) return s;
    }
    return StatutHorsLigne.enAttente;
  }
}

/// Une opération en attente de synchronisation.
class OperationHorsLigne {
  OperationHorsLigne({
    required this.id,
    required this.type,
    required this.donnees,
    DateTime? creeLe,
    this.tentatives = 0,
    this.statut = StatutHorsLigne.enAttente,
    this.erreur,
  }) : creeLe = creeLe ?? DateTime.now();

  /// Identifiant unique de l'appareil — envoyé comme `reference_locale`.
  final String id;
  final TypeOperationHorsLigne type;
  final Map<String, dynamic> donnees;
  final DateTime creeLe;
  int tentatives;
  StatutHorsLigne statut;
  String? erreur;

  bool get enAttente => statut == StatutHorsLigne.enAttente;

  String get resume {
    if (type == TypeOperationHorsLigne.vente) {
      final int nb = (donnees['lignes'] as List<dynamic>?)?.length ?? 0;
      final num total = (donnees['total'] ?? 0) as num;
      return 'Vente · $nb ligne(s) · $total';
    }
    return 'Bonus · ${donnees['nature'] ?? ''} · ${donnees['quantite'] ?? ''}';
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'id': id,
        'type': type.code,
        'donnees': donnees,
        'cree_le': creeLe.toIso8601String(),
        'tentatives': tentatives,
        'statut': statut.code,
        'erreur': erreur,
      };

  factory OperationHorsLigne.depuisMap(Map<String, dynamic> map) {
    return OperationHorsLigne(
      id: (map['id'] ?? '').toString(),
      type: TypeOperationHorsLigne.depuisCode(map['type'] as String?),
      donnees: (map['donnees'] as Map?)?.map<String, dynamic>(
            (dynamic k, dynamic v) =>
                MapEntry<String, dynamic>(k.toString(), v),
          ) ??
          const <String, dynamic>{},
      creeLe: DateTime.tryParse('${map['cree_le']}'),
      tentatives: (map['tentatives'] as num?)?.toInt() ?? 0,
      statut: StatutHorsLigne.depuisCode(map['statut'] as String?),
      erreur: map['erreur'] as String?,
    );
  }
}

/// Résultat d'une tentative de synchronisation.
class ResultatSynchronisation {
  const ResultatSynchronisation({
    this.envoyees = 0,
    this.restantes = 0,
    this.conflits = 0,
    this.message = '',
    this.reseauIndisponible = false,
  });

  final int envoyees;
  final int restantes;
  final int conflits;
  final String message;
  final bool reseauIndisponible;

  bool get toutEnvoye => restantes == 0 && conflits == 0;
}

/// Exécuteur d'une opération côté serveur (injectable pour les tests).
typedef ExecuteurHorsLigne = Future<void> Function(OperationHorsLigne operation);

/// File d'attente hors ligne du commercial.
class DistributionHorsLigne {
  DistributionHorsLigne._();

  static final DistributionHorsLigne instance = DistributionHorsLigne._();

  static const String _cleFile = 'dist_hors_ligne_file_v1';
  static const String _cleHistorique = 'dist_hors_ligne_historique_v1';
  static const String _cleCache = 'dist_hors_ligne_cache_v1';

  /// Nombre d'opérations en attente (bandeau de l'écran commercial).
  final ValueNotifier<int> enAttente = ValueNotifier<int>(0);

  /// Une synchronisation est-elle en cours ?
  final ValueNotifier<bool> synchronisation = ValueNotifier<bool>(false);

  final List<OperationHorsLigne> _file = <OperationHorsLigne>[];
  bool _charge = false;

  /// Remplaçable dans les tests (`executeur = (op) async { ... }`).
  ExecuteurHorsLigne? executeur;

  /// Opérations actuellement en file (copie défensive).
  List<OperationHorsLigne> get file =>
      List<OperationHorsLigne>.unmodifiable(_file);

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  // ---------------------------------------------------------------------------
  // CHARGEMENT / PERSISTANCE
  // ---------------------------------------------------------------------------

  /// Relit la file depuis le stockage local (appelé au démarrage de l'écran).
  Future<void> initialiser() async {
    if (_charge) return;
    final SharedPreferences prefs = await _prefs;
    final String? brut = prefs.getString(_cleFile);
    _file.clear();
    if (brut != null && brut.isNotEmpty) {
      try {
        final List<dynamic> liste = jsonDecode(brut) as List<dynamic>;
        for (final dynamic item in liste) {
          if (item is Map) {
            _file.add(
              OperationHorsLigne.depuisMap(
                item.map<String, dynamic>(
                  (dynamic k, dynamic v) =>
                      MapEntry<String, dynamic>(k.toString(), v),
                ),
              ),
            );
          }
        }
      } catch (e) {
        debugPrint('DistributionHorsLigne.initialiser : $e');
      }
    }
    _charge = true;
    enAttente.value = _file.where((OperationHorsLigne o) => o.enAttente).length;
  }

  Future<void> _enregistrer() async {
    final SharedPreferences prefs = await _prefs;
    await prefs.setString(
      _cleFile,
      jsonEncode(_file.map((OperationHorsLigne o) => o.toMap()).toList()),
    );
    enAttente.value = _file.where((OperationHorsLigne o) => o.enAttente).length;
  }

  // ---------------------------------------------------------------------------
  // MISE EN FILE
  // ---------------------------------------------------------------------------

  /// Met une vente en file (elle sera enregistrée au retour du réseau).
  Future<OperationHorsLigne> ajouterVente({
    required List<Map<String, dynamic>> lignes,
    String? clientId,
    String? nomClient,
    double? montantPaye,
    String mode = 'especes',
    TypeOperationTarif typeOperation = TypeOperationTarif.standard,
  }) async {
    await initialiser();
    double total = 0;
    for (final Map<String, dynamic> l in lignes) {
      final double q = ((l['quantite'] ?? 0) as num).toDouble();
      final double p = ((l['prix_unitaire'] ?? 0) as num).toDouble();
      total += q * p;
    }

    final OperationHorsLigne op = OperationHorsLigne(
      id: const Uuid().v4(),
      type: TypeOperationHorsLigne.vente,
      donnees: <String, dynamic>{
        'lignes': lignes,
        'client_id': clientId,
        'client': nomClient,
        'montant_paye': montantPaye,
        'mode': mode,
        'type_operation': typeOperation.code,
        'total': total,
      },
    );
    _file.add(op);
    await _enregistrer();
    return op;
  }

  /// Met une déclaration de bonus / dommage en file.
  Future<OperationHorsLigne> ajouterBonus({
    required String produitId,
    required NatureBonus nature,
    required double quantite,
    required String motif,
    String? justificatif,
  }) async {
    await initialiser();
    final OperationHorsLigne op = OperationHorsLigne(
      id: const Uuid().v4(),
      type: TypeOperationHorsLigne.bonus,
      donnees: <String, dynamic>{
        'produit_id': produitId,
        'nature': nature.code,
        'quantite': quantite,
        'motif': motif,
        'justificatif': justificatif,
      },
    );
    _file.add(op);
    await _enregistrer();
    return op;
  }

  /// Retire une opération (conflit résolu à la main, ou doublon constaté).
  Future<void> retirer(String id) async {
    _file.removeWhere((OperationHorsLigne o) => o.id == id);
    await _enregistrer();
  }

  /// Autorise à rejouer une opération « à vérifier » (l'utilisateur a contrôlé).
  Future<void> relancer(String id) async {
    for (final OperationHorsLigne o in _file) {
      if (o.id == id) {
        o.statut = StatutHorsLigne.enAttente;
        o.erreur = null;
      }
    }
    await _enregistrer();
  }

  // ---------------------------------------------------------------------------
  // SYNCHRONISATION
  // ---------------------------------------------------------------------------

  /// Applique la file au serveur, dans l'ordre.
  ///
  /// S'arrête à la première opération non aboutie : les suivantes peuvent en
  /// dépendre (une vente après une création de client, par exemple).
  Future<ResultatSynchronisation> synchroniser() async {
    await initialiser();
    if (synchronisation.value) {
      return ResultatSynchronisation(
        restantes: enAttente.value,
        message: 'Synchronisation déjà en cours.',
      );
    }

    final List<OperationHorsLigne> aTraiter = _file
        .where((OperationHorsLigne o) => o.statut == StatutHorsLigne.enAttente)
        .toList(growable: false);

    if (aTraiter.isEmpty) {
      return const ResultatSynchronisation(message: 'Aucune opération à envoyer.');
    }

    synchronisation.value = true;
    int envoyees = 0;
    int conflits = 0;
    bool reseau = false;
    String message = '';

    try {
      for (final OperationHorsLigne op in aTraiter) {
        op.tentatives += 1;
        try {
          await (executeur ?? _executerParDefaut)(op);
          _file.remove(op);
          envoyees += 1;
          await _enregistrer();
        } on DistributionGestionException catch (e) {
          // Refus métier : on garde l'opération, l'utilisateur doit trancher.
          op.statut = StatutHorsLigne.conflit;
          op.erreur = e.message;
          conflits += 1;
          message = e.message;
          await _enregistrer();
          break;
        } catch (e) {
          // Réseau coupé pendant l'envoi : on ne sait pas si le serveur a
          // enregistré. On passe en « à vérifier » et on n'y touche plus.
          op.statut = StatutHorsLigne.aVerifier;
          op.erreur = 'Envoi interrompu : vérifiez la liste avant de relancer.';
          reseau = true;
          message = 'Réseau interrompu pendant l\'envoi. '
              'L\'opération a été mise de côté pour vérification.';
          await _enregistrer();
          break;
        }
      }
    } finally {
      synchronisation.value = false;
    }

    final ResultatSynchronisation resultat = ResultatSynchronisation(
      envoyees: envoyees,
      restantes: enAttente.value,
      conflits: conflits,
      message: message.isEmpty
          ? (envoyees > 0
              ? '$envoyees opération(s) synchronisée(s).'
              : 'Rien à synchroniser.')
          : message,
      reseauIndisponible: reseau,
    );

    await _journaliser(resultat);
    return resultat;
  }

  Future<void> _executerParDefaut(OperationHorsLigne op) async {
    final DistributionGestionService service =
        DistributionGestionService.instance;
    switch (op.type) {
      case TypeOperationHorsLigne.vente:
        await service.enregistrerVente(
          clientId: op.donnees['client_id'] as String?,
          lignes: (op.donnees['lignes'] as List<dynamic>)
              .cast<Map<String, dynamic>>(),
          montantPaye: (op.donnees['montant_paye'] as num?)?.toDouble(),
          mode: (op.donnees['mode'] ?? 'especes') as String,
          typeOperation:
              TypeOperationTarif.depuisCode(op.donnees['type_operation'] as String?),
          referenceLocale: op.id,
        );
        break;
      case TypeOperationHorsLigne.bonus:
        await service.declarerBonus(
          produitId: op.donnees['produit_id'] as String,
          nature: NatureBonus.depuisCode(op.donnees['nature'] as String?),
          quantite: (op.donnees['quantite'] as num).toDouble(),
          motif: op.donnees['motif'] as String? ?? '',
          justificatif: op.donnees['justificatif'] as String?,
          referenceLocale: op.id,
        );
        break;
    }
  }

  // ---------------------------------------------------------------------------
  // HISTORIQUE DES SYNCHRONISATIONS
  // ---------------------------------------------------------------------------

  Future<void> _journaliser(ResultatSynchronisation r) async {
    try {
      final SharedPreferences prefs = await _prefs;
      final String? brut = prefs.getString(_cleHistorique);
      final List<dynamic> liste =
          brut == null || brut.isEmpty ? <dynamic>[] : jsonDecode(brut) as List<dynamic>;
      liste.insert(0, <String, dynamic>{
        'date': DateTime.now().toIso8601String(),
        'envoyees': r.envoyees,
        'restantes': r.restantes,
        'conflits': r.conflits,
        'message': r.message,
      });
      await prefs.setString(
        _cleHistorique,
        jsonEncode(liste.take(20).toList()),
      );
    } catch (e) {
      debugPrint('DistributionHorsLigne._journaliser : $e');
    }
  }

  /// Les 20 dernières synchronisations (les plus récentes d'abord).
  Future<List<Map<String, dynamic>>> historique() async {
    final SharedPreferences prefs = await _prefs;
    final String? brut = prefs.getString(_cleHistorique);
    if (brut == null || brut.isEmpty) return const <Map<String, dynamic>>[];
    try {
      return (jsonDecode(brut) as List<dynamic>)
          .whereType<Map<dynamic, dynamic>>()
          .map((Map<dynamic, dynamic> m) => m.map<String, dynamic>(
                (dynamic k, dynamic v) =>
                    MapEntry<String, dynamic>(k.toString(), v),
              ))
          .toList(growable: false);
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }

  // ---------------------------------------------------------------------------
  // CACHE (consultation hors ligne)
  // ---------------------------------------------------------------------------

  /// Mémorise les données déjà reçues du serveur.
  Future<void> mettreEnCache({
    List<ProduitCommercial>? produits,
    List<ClientDistribution>? clients,
    List<TarifBidon>? tarifs,
  }) async {
    try {
      final SharedPreferences prefs = await _prefs;
      final Map<String, dynamic> cache = <String, dynamic>{
        'date': DateTime.now().toIso8601String(),
        'produits': produits
                ?.map((ProduitCommercial p) => <String, dynamic>{
                      'produit_id': p.produitId,
                      'nom': p.nom,
                      'unite': p.unite,
                      'quantite': p.quantite,
                      'prix_vente': p.prixVente,
                    })
                .toList() ??
            <Map<String, dynamic>>[],
        'clients': clients
                ?.map((ClientDistribution c) => <String, dynamic>{
                      'id': c.id,
                      'nom': c.nom,
                      'telephone': c.telephone,
                    })
                .toList() ??
            <Map<String, dynamic>>[],
        'tarifs': tarifs
                ?.map((TarifBidon t) => <String, dynamic>{
                      'produit_id': t.produitId,
                      'type_operation': t.type.code,
                      'prix': t.prix,
                    })
                .toList() ??
            <Map<String, dynamic>>[],
      };
      await prefs.setString(_cleCache, jsonEncode(cache));
    } catch (e) {
      debugPrint('DistributionHorsLigne.mettreEnCache : $e');
    }
  }

  /// Produits attribués mémorisés (0 si aucun cache).
  Future<List<ProduitCommercial>> produitsEnCache() async {
    final Map<String, dynamic> cache = await _cache();
    return ((cache['produits'] as List<dynamic>?) ?? <dynamic>[])
        .whereType<Map<dynamic, dynamic>>()
        .map((Map<dynamic, dynamic> m) => ProduitCommercial.depuisJson(
              m.map<String, dynamic>(
                (dynamic k, dynamic v) =>
                    MapEntry<String, dynamic>(k.toString(), v),
              ),
            ))
        .toList(growable: false);
  }

  /// Clients mémorisés.
  Future<List<ClientDistribution>> clientsEnCache() async {
    final Map<String, dynamic> cache = await _cache();
    return ((cache['clients'] as List<dynamic>?) ?? <dynamic>[])
        .whereType<Map<dynamic, dynamic>>()
        .map((Map<dynamic, dynamic> m) => ClientDistribution.depuisJson(
              m.map<String, dynamic>(
                (dynamic k, dynamic v) =>
                    MapEntry<String, dynamic>(k.toString(), v),
              ),
            ))
        .toList(growable: false);
  }

  /// Date du dernier cache (null si aucun).
  Future<DateTime?> dateCache() async {
    final Map<String, dynamic> cache = await _cache();
    return DateTime.tryParse('${cache['date'] ?? ''}');
  }

  Future<Map<String, dynamic>> _cache() async {
    try {
      final SharedPreferences prefs = await _prefs;
      final String? brut = prefs.getString(_cleCache);
      if (brut == null || brut.isEmpty) return const <String, dynamic>{};
      final dynamic decode = jsonDecode(brut);
      if (decode is Map) {
        return decode.map<String, dynamic>(
          (dynamic k, dynamic v) =>
              MapEntry<String, dynamic>(k.toString(), v),
        );
      }
    } catch (e) {
      debugPrint('DistributionHorsLigne._cache : $e');
    }
    return const <String, dynamic>{};
  }

  /// Efface file, cache et historique (déconnexion, changement de compte).
  Future<void> reinitialiser() async {
    final SharedPreferences prefs = await _prefs;
    await prefs.remove(_cleFile);
    await prefs.remove(_cleCache);
    await prefs.remove(_cleHistorique);
    _file.clear();
    _charge = false;
    enAttente.value = 0;
  }
}
