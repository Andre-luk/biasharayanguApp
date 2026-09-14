// lib/services/supabase_service.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:biashara_yangu/models/utilisateur.dart';
import 'package:biashara_yangu/services/sync_service.dart';

/// SupabaseService
/// Singleton centralisant l'accès à Supabase (Auth, PostgREST, Realtime, RPC)
class SupabaseService {
  SupabaseService._privateConstructor();
  static final SupabaseService instance = SupabaseService._privateConstructor();

  // Utilise directement le client singleton de Supabase
  SupabaseClient get _client => Supabase.instance.client;

  // Stockage des channels Realtime
  final Map<String, RealtimeChannel> _channels = {};

  // ---------------------------------------------------------------------------
  // EXPOSITIONS (Getters)
  // ---------------------------------------------------------------------------

  SupabaseClient get client => _client;
  GoTrueClient get auth => _client.auth;
  String? get currentUserId => _client.auth.currentUser?.id;

  // ---------------------------------------------------------------------------
  // REALTIME HELPERS
  // ---------------------------------------------------------------------------

  void initializeRealtime() {
    _setupRealtimeListeners();
  }

  void _setupRealtimeListeners() {
    final tables = ['produits', 'ventes', 'clients', 'utilisateurs'];
    final syncService = SyncService.instance;

    for (final table in tables) {
      if (_channels.containsKey(table)) continue;

      final channel = _client.channel('public:$table');

      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        callback: (payload) {
          try {
            debugPrint('Realtime Event sur $table: ${payload.eventType}');

            final currentUserId = auth.currentUser?.id;
            if (currentUserId == null) return;

            switch (payload.eventType) {
              case PostgresChangeEvent.insert:
                syncService.handleRealtimeInsert(
                  table,
                  Map<String, dynamic>.from(payload.newRecord ?? {}),
                );
                break;
              case PostgresChangeEvent.update:
                syncService.handleRealtimeUpdate(
                  table,
                  Map<String, dynamic>.from(payload.newRecord ?? {}),
                );
                break;
              case PostgresChangeEvent.delete:
                syncService.handleRealtimeDelete(
                  table,
                  Map<String, dynamic>.from(payload.oldRecord ?? {}),
                );
                break;
              default:
                break;
            }
          } catch (e, st) {
            debugPrint('Erreur dans le callback Realtime pour $table: $e\n$st');
          }
        },
      ).subscribe();

      _channels[table] = channel;
    }
  }

  void unsubscribeAll() {
    for (var channel in _channels.values) {
      try {
        _client.removeChannel(channel);
      } catch (e) {
        debugPrint('Erreur removeChannel: $e');
      }
    }
    _channels.clear();
  }

  // ---------------------------------------------------------------------------
  // HELPERS: attendre le profil distant (utilisateurs) — utilisé par signUp/signIn
  // ---------------------------------------------------------------------------
  Future<Map<String, dynamic>?> _waitForRemoteUtilisateur(
      String userId, {
        int maxAttempts = 8,
        int delayMs = 400,
      }) async {
    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        final data = await _client
            .from('utilisateurs')
            .select()
            .eq('id', userId)
            .maybeSingle();
        if (data != null) {
          return Map<String, dynamic>.from(data as Map);
        }
      } catch (e) {
        // ignore and retry
      }
      await Future.delayed(Duration(milliseconds: delayMs));
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // AUTHENTICATION
  // ---------------------------------------------------------------------------

  Future<Utilisateur> signUpUser({
    required String email,
    required String password,
    required String nom,
    String role = 'vendor',
    String? parentId, // AJOUT : Permet au vendeur de s'attacher au patron
    String? prenom,
    String? avatar,
  }) async {
    try {
      // Build metadata we want the trigger to use
      final Map<String, dynamic> metadata = {
        'nom': nom,
        'role': role,
        if (prenom != null && prenom.isNotEmpty) 'prenom': prenom,
        if (parentId != null && parentId.isNotEmpty) 'parent_id': parentId,
        if (avatar != null && avatar.isNotEmpty) 'avatar': avatar,
      };

      // Call signUp in a way that tolerates different SDK signatures
      final authDynamic = _client.auth as dynamic;
      dynamic res;
      try {
        // Try newer/older SDK signatures with metadata where supported
        // 1) try data parameter (Supabase SDK v2+)
        try {
          res = await authDynamic.signUp(email: email, password: password, data: metadata);
        } catch (_) {
          // 2) try userMetadata param (older versions)
          try {
            res = await authDynamic.signUp(email: email, password: password, userMetadata: metadata);
          } catch (_) {
            // 3) fallback: plain signUp without metadata (trigger won't get metadata)
            res = await authDynamic.signUp(email: email, password: password);
          }
        }
      } catch (e) {
        // As a last attempt, call signUp without named args (some sdk older)
        try {
          res = await authDynamic.signUp(email, password);
        } catch (e2) {
          debugPrint('signUp invocation failed: $e / $e2');
          rethrow;
        }
      }

      // Normalize user object from response (various sdk shapes)
      final dynamic authUser = (res is Map) ? (res['user'] ?? res['data']?['user']) : (res?.user ?? (res as dynamic)?['user']);

      if (authUser == null) {
        throw Exception('Échec création compte : réponse inattendue de Supabase.');
      }

      final String authUserId = authUser.id;

      // 1) Check if utilisateurs row already exists (to avoid duplicate key)
      try {
        final existing = await _client.from('utilisateurs').select().eq('id', authUserId).maybeSingle();
        if (existing != null) {
          return Utilisateur.fromMap(Map<String, dynamic>.from(existing as Map));
        }
      } catch (e) {
        // ignore and continue to insert attempt
        debugPrint('Erreur lecture utilisateurs avant insert: $e');
      }

      // Prepare new user data
      final newUserData = {
        'id': authUserId,
        'nom': nom,
        'email': email,
        'role': role,
        'valide': 1,
        if (parentId != null && parentId.isNotEmpty) 'parent_id': parentId,
        if (prenom != null) 'prenom': prenom,
        if (avatar != null) 'avatar': avatar,
      };

      // 2) Try to insert (or upsert if supported), handle duplicate-key race gracefully
      try {
        // Prefer upsert if available
        final table = _client.from('utilisateurs') as dynamic;
        try {
          final upsertRes = await table.upsert(newUserData).select();
          if (upsertRes != null && (upsertRes is List) && upsertRes.isNotEmpty) {
            return Utilisateur.fromMap(Map<String, dynamic>.from(upsertRes.first as Map));
          }
        } catch (eUpsert) {
          // upsert not supported or failed => try insert
          debugPrint('Upsert non supporté ou a échoué: $eUpsert');
          try {
            final inserted = await _client.from('utilisateurs').insert(newUserData).select();
            if (inserted != null && (inserted is List) && inserted.isNotEmpty) {
              return Utilisateur.fromMap(Map<String, dynamic>.from(inserted.first as Map));
            }
          } catch (eInsert) {
            final err = eInsert.toString().toLowerCase();
            // If duplicate key (race with trigger), ignore and fetch remote
            if (err.contains('duplicate') || err.contains('23505') || err.contains('unique')) {
              debugPrint('Insert ignored because duplicate (probable trigger insertion).');
            } else {
              debugPrint('Erreur insert utilisateurs: $eInsert');
            }
          }
        }
      } catch (e) {
        debugPrint('Erreur upsert/insert utilisateurs: $e');
      }

      // 3) If insert didn't produce a row (likely trigger created it), wait a bit and fetch
      final remote = await _waitForRemoteUtilisateur(authUserId);
      if (remote != null) return Utilisateur.fromMap(remote);

      // 4) Fallback: return minimal profile based on auth (do not attempt further server inserts)
      return Utilisateur(
        id: authUserId,
        prenom: prenom ?? '',
        nom: nom,
        email: authUser.email ?? email,
        avatar: avatar,
        role: role,
        valide: 1,
        parentId: parentId,
      );
    } catch (e, st) {
      debugPrint('signUpUser error: $e\n$st');
      rethrow;
    }
  }

  /// Sign in user via Supabase Auth, then fetch metadata from `utilisateurs`.
  Future<Utilisateur?> signInUser({
    required String email,
    required String password,
  }) async {
    try {
      final authDynamic = _client.auth as dynamic;
      dynamic res;

      // Try modern signInWithPassword first, fallback to older signIn signature
      try {
        res = await authDynamic.signInWithPassword(email: email, password: password);
      } catch (_) {
        try {
          res = await authDynamic.signIn(email: email, password: password);
        } catch (e2) {
          debugPrint('Les appels signIn ont échoué: $e2');
          rethrow;
        }
      }

      final dynamic authUser = (res is Map) ? (res['user'] ?? res['data']?['user']) : (res?.user ?? (res as dynamic)?['user']);

      if (authUser == null) {
        debugPrint('signInUser: auth returned null user');
        return null;
      }

      final authUserId = authUser.id;

      // Fetch metadata from utilisateurs
      try {
        final data = await _client
            .from('utilisateurs')
            .select('*')
            .eq('id', authUserId)
            .limit(1);
        if (data.isNotEmpty) {
          return Utilisateur.fromMap(Map<String, dynamic>.from(data.first as Map));
        }
      } catch (e) {
        debugPrint('signInUser: lecture utilisateurs initiale failed: $e');
      }

      // If not present yet (trigger), wait a bit
      final remote = await _waitForRemoteUtilisateur(authUserId);
      if (remote != null) {
        return Utilisateur.fromMap(remote);
      }

      // fallback : minimal profile from Auth
      return Utilisateur(
        id: authUserId,
        prenom: '',
        nom: authUser.email?.split('@').first ?? 'Utilisateur',
        email: authUser.email ?? '',
        avatar: null,
        role: 'vendor',
        valide: 1,
        parentId: null,
        passwordHash: null,
      );
    } catch (e) {
      debugPrint('signInUser error: $e');
      return null;
    }
  }

  Future<void> signOut() async {
    try {
      unsubscribeAll();
    } catch (_) {}
    await _client.auth.signOut();
  }

  // ---------------------------------------------------------------------------
  // UTILISATEURS (CRUD)
  // ---------------------------------------------------------------------------

  Future<Utilisateur?> getUtilisateurData(String userId) async {
    try {
      final data = await _client
          .from('utilisateurs')
          .select('*')
          .eq('id', userId)
          .maybeSingle();

      if (data == null) return null;
      return Utilisateur.fromMap(Map<String, dynamic>.from(data as Map));
    } catch (e) {
      debugPrint('getUtilisateurData error: $e');
      return null;
    }
  }

  Future<void> updateUtilisateurData(String userId, Map<String, dynamic> updatedData) async {
    if (userId.isEmpty) throw Exception('ID utilisateur requis.');
    await _client.from('utilisateurs').update(updatedData).eq('id', userId);
  }

  Future<List<Utilisateur>> getAllUtilisateurs() async {
    try {
      final List<dynamic> data = await _client
          .from('utilisateurs')
          .select('*')
          .order('nom', ascending: true);

      return (data as List)
          .map((m) => Utilisateur.fromMap(Map<String, dynamic>.from(m as Map)))
          .toList();
    } catch (e) {
      debugPrint('getAllUtilisateurs error: $e');
      return [];
    }
  }

  // AJOUT : Pour récupérer uniquement les collaborateurs d'un patron spécifique
  Future<List<Utilisateur>> getCollaborateursByPatron(String patronId) async {
    try {
      final List<dynamic> data = await _client
          .from('utilisateurs')
          .select('*')
          .eq('parent_id', patronId)
          .order('nom', ascending: true);

      return (data as List)
          .map((m) => Utilisateur.fromMap(Map<String, dynamic>.from(m as Map)))
          .toList();
    } catch (e) {
      debugPrint('getCollaborateursByPatron error: $e');
      return [];
    }
  }

  // AJOUT : Pour supprimer l'accès d'un collaborateur via Supabase
  Future<void> deleteUtilisateur(String userId) async {
    await _client.from('utilisateurs').delete().eq('id', userId);
  }

  Future<double> getSolde(String userId) async {
    final data = await _client
        .from('utilisateurs')
        .select('solde')
        .eq('id', userId)
        .single();

    return (data['solde'] ?? 0).toDouble();
  }

  // ---------------------------------------------------------------------------
  // PRODUITS
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> insertProduit(Map<String, dynamic> produitData) async {
    final List<dynamic> data = await _client
        .from('produits')
        .insert(produitData)
        .select('id, created_at');

    if (data.isEmpty) throw Exception("Échec de l'insertion du produit.");
    return Map<String, dynamic>.from(data.first as Map);
  }

  Future<void> updateProduit(String supabaseId, Map<String, dynamic> updatedData) async {
    await _client.from('produits').update(updatedData).eq('id', supabaseId);
  }

  Future<void> deleteProduit(String supabaseId) async {
    await _client.from('produits').delete().eq('id', supabaseId);
  }

  Future<List<Map<String, dynamic>>> getProduitsForOwner() async {
    final ownerId = currentUserId;
    if (ownerId == null) throw Exception('Aucun utilisateur connecté.');
    return getProduitsByOwner(ownerId);
  }

  Future<List<Map<String, dynamic>>> getProduitsByOwner(String ownerId) async {
    final List<dynamic> data = await _client
        .from('produits')
        .select('*')
        .eq('owner_id', ownerId)
        .order('nom', ascending: true);

    return (data as List).map((m) => Map<String, dynamic>.from(m as Map)).toList();
  }

  // ---------------------------------------------------------------------------
  // VENTES
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> insertVente(Map<String, dynamic> venteData) async {
    final List<dynamic> data = await _client
        .from('ventes')
        .insert(venteData)
        .select('id, date');

    if (data.isEmpty) throw Exception("Échec de l'insertion de la vente.");
    return Map<String, dynamic>.from(data.first as Map);
  }

  Future<void> updateVente(String supabaseId, Map<String, dynamic> updatedData) async {
    await _client.from('ventes').update(updatedData).eq('id', supabaseId);
  }

  Future<void> deleteVente(String supabaseId) async {
    await _client.from('ventes').delete().eq('id', supabaseId);
  }

  Future<List<Map<String, dynamic>>> getVentesForOwner() async {
    final ownerId = currentUserId;
    if (ownerId == null) throw Exception('Aucun utilisateur connecté.');

    final List<dynamic> data = await _client
        .from('ventes')
        .select('*, produit:produit_id(nom), client:client_id(nom)')
        .eq('owner_id', ownerId)
        .order('date', ascending: false);

    return (data as List).map((m) => Map<String, dynamic>.from(m as Map)).toList();
  }

  Future<List<Map<String, dynamic>>> getVentesByOwner(String ownerId) async {
    final List<dynamic> data = await _client
        .from('ventes')
        .select('*')
        .eq('owner_id', ownerId)
        .order('date', ascending: false);

    return (data as List).map((m) => Map<String, dynamic>.from(m as Map)).toList();
  }

  // ---------------------------------------------------------------------------
  // CLIENTS
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> insertClient(Map<String, dynamic> clientData) async {
    final List<dynamic> data = await _client.from('clients').insert(clientData).select('id');
    if (data.isEmpty) throw Exception("Échec de l'insertion du client.");
    return Map<String, dynamic>.from(data.first as Map);
  }

  Future<void> updateClient(String supabaseId, Map<String, dynamic> updatedData) async {
    await _client.from('clients').update(updatedData).eq('id', supabaseId);
  }

  Future<void> deleteClient(String supabaseId) async {
    await _client.from('clients').delete().eq('id', supabaseId);
  }

  Future<List<Map<String, dynamic>>> getClientsForOwner() async {
    final ownerId = currentUserId;
    if (ownerId == null) throw Exception('Aucun utilisateur connecté.');
    return getClientsByOwner(ownerId);
  }

  Future<List<Map<String, dynamic>>> getClientsByOwner(String ownerId) async {
    final List<dynamic> data = await _client
        .from('clients')
        .select('*')
        .eq('owner_id', ownerId)
        .order('nom', ascending: true);

    return (data as List).map((m) => Map<String, dynamic>.from(m as Map)).toList();
  }


  // ---------------------------------------------------------------------------
  // RPC / REPORTS HELPERS
  // ---------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> getSalesSeries({
    required String ownerId,
    required DateTime from,
    required DateTime to,
    required String period,
  }) async {
    try {
      // S'assurer de couvrir jusqu'à la dernière milliseconde de la journée de fin
      final toEndOfDay = DateTime(to.year, to.month, to.day, 23, 59, 59, 999);

      final response = await _client.rpc('rpc_get_sales_series', params: {
        'owner_id_param': ownerId,
        'start_date_param': from.toUtc().toIso8601String(),
        'end_date_param': toEndOfDay.toUtc().toIso8601String(),
        'period_param': period,
      });

      if (response is List) {
        return List<Map<String, dynamic>>.from(response).map((item) {
          if (item.containsKey('total') && item['total'] is num) {
            item['total'] = (item['total'] as num).toDouble();
          }
          if (item.containsKey('qty') && item['qty'] is num) {
            item['qty'] = (item['qty'] as num).toInt();
          }
          return item;
        }).toList();
      }
      return [];
    } catch (e) {
      debugPrint("Erreur Supabase getSalesSeries: $e");
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getTopProducts({
    required String ownerId,
    required DateTime from,
    required DateTime to,
    int limit = 10,
  }) async {
    try {
      // Couvrir la fin de la journée
      final toEndOfDay = DateTime(to.year, to.month, to.day, 23, 59, 59, 999);

      final response = await _client.rpc('rpc_get_top_products', params: {
        'owner_id_param': ownerId,
        'start_date_param': from.toUtc().toIso8601String(),
        'end_date_param': toEndOfDay.toUtc().toIso8601String(),
        'limit_param': limit,
      });
      if (response is List) {
        return List<Map<String, dynamic>>.from(response);
      }
      return [];
    } catch (e) {
      debugPrint("Erreur Supabase getTopProducts: $e");
      return [];
    }
  }

  Future<Map<String, dynamic>> getDailyReportDetails({
    required String ownerId,
    required DateTime date,
  }) async {
    try {
      // Utilisation du format YYYY-MM-DD strict pour forcer Postgres à lire la date correcte
      // indépendamment du fuseau horaire du serveur.
      final dateString = "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";

      final response = await _client.rpc('rpc_get_daily_report_details', params: {
        'owner_id_param': ownerId,
        'date_param': dateString,
      });

      Map<String, dynamic>? result;
      if (response is List && response.isNotEmpty && response.first is Map) {
        result = Map<String, dynamic>.from(response.first as Map);
      } else if (response is Map) {
        result = Map<String, dynamic>.from(response as Map);
      }

      if (result != null) return result;

      return _emptyReport();
    } catch (e) {
      debugPrint("Erreur Supabase getDailyReportDetails: $e");
      return _emptyReport();
    }
  }

  Map<String, dynamic> _emptyReport() {
    return {
      'total_revenue': 0.0,
      'total_quantity': 0.0,
      'total_profit': 0.0,
      'qty_by_category': {},
      'detailed_sales': [],
      'top_products': [],
    };
  }
}