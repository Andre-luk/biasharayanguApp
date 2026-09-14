// lib/services/sync_service.dart
import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vibration/vibration.dart';

import 'package:biashara_yangu/db_helper.dart';
import 'package:biashara_yangu/models/client.dart';
import 'package:biashara_yangu/models/produit.dart';
import 'package:biashara_yangu/models/utilisateur.dart';
import 'package:biashara_yangu/models/vente.dart';
import 'package:biashara_yangu/models/depense.dart';
import 'package:biashara_yangu/models/dette.dart';
import 'package:biashara_yangu/models/paiement_dette.dart';
import 'package:biashara_yangu/models/inventaire_quotidien.dart';
import 'package:biashara_yangu/models/ajustement.dart';
import 'package:biashara_yangu/services/supabase_service.dart';

class SyncService {
  SyncService._private();
  static final SyncService instance = SyncService._private();

  final DBHelper _db = DBHelper.instance;
  final SupabaseService _sup = SupabaseService.instance;

  final AudioPlayer _audioPlayer = AudioPlayer();

  bool _isSyncing = false;
  RealtimeChannel? _realtimeChannel;
  final Set<String> _seenRealtimeEvents = {};

  String? currentOwnerId;

  Future<void> _notifyNewSale() async {
    try {
      await Vibration.vibrate(duration: 500);
      await _audioPlayer.play(AssetSource('sounds/cash_register.mp3'));
      debugPrint("🔔 Notification de vente réussie (Son + Vibreur)");
    } catch (e) {
      debugPrint("SyncService: Erreur alerte sonore/vibration : $e");
    }
  }

  Future<T> _withRetry<T>(Future<T> Function() fn, {int retries = 2}) async {
    int attempt = 0;
    while (true) {
      try {
        return await fn();
      } catch (e) {
        attempt++;
        if (attempt > retries) rethrow;
        await Future.delayed(Duration(milliseconds: 300 * attempt));
      }
    }
  }

  Future<List<Map<String, dynamic>>> _fetchAllVentesFromSupabase(String ownerId) async {
    const int pageSize = 500;
    int offset = 0;
    final List<Map<String, dynamic>> all = [];

    while (true) {
      final page = await _sup.client
          .from('ventes')
          .select()
          .eq('owner_id', ownerId)
          .order('date', ascending: false)
          .range(offset, offset + pageSize - 1);

      if (page is! List) {
        break;
      }

      final items = page
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      all.addAll(items);

      if (items.length < pageSize) {
        break;
      }

      offset += pageSize;
    }

    return all;
  }

  // ------------------ Synchronisation du profil ------------------

  Future<void> syncUserProfile(String userId) async {
    if (userId.isEmpty) return;
    try {
      final data = await _sup.client
          .from('utilisateurs')
          .select()
          .eq('id', userId)
          .maybeSingle();

      if (data == null) return;

      final user = Utilisateur(
        id: data['id']?.toString() ?? userId,
        nom: data['nom']?.toString() ?? '',
        email: data['email']?.toString() ?? '',
        avatar: data['avatar']?.toString(),
        role: data['role']?.toString() ?? 'vendor',
        parentId: data['parent_id']?.toString(),
        valide: (data['valide'] is int)
            ? data['valide'] as int
            : (int.tryParse(data['valide']?.toString() ?? '') ?? 1),
      );

      final existing = await _db.getUtilisateurById(userId);
      if (existing == null) {
        await _db.insertUtilisateur(user);
      } else {
        await _db.updateUtilisateur(user);
      }
    } catch (e) {
      debugPrint('SyncService Error Profile: $e');
    }
  }

  // ------------------ Realtime handlers (Cloud -> Local) ------------------

  Future<void> handleRealtimeDelete(
      String table,
      Map<String, dynamic> oldRecord,
      ) async {
    final supabaseId = oldRecord['id']?.toString();
    final ownerId = oldRecord['owner_id']?.toString();

    debugPrint('🗑️ DELETE reçu: $table / $supabaseId');

    if (supabaseId == null) return;
    if (ownerId != currentOwnerId) return;

    try {
      switch (table) {
        case 'produits':
          await _db.deleteProduitBySupabaseId(supabaseId);
          break;

        case 'ventes':
          await _db.deleteVenteBySupabaseId(supabaseId);
          break;

        case 'clients':
          await _db.deleteClientBySupabaseId(supabaseId);
          break;

        case 'depenses':
          await _db.deleteDepenseBySupabaseId(supabaseId);
          break;

        case 'dettes':
          await _db.deleteDetteBySupabaseId(supabaseId);
          break;

        case 'inventaires_quotidiens':
          await _db.deleteInventaireQuotidienBySupabaseId(supabaseId);
          break;

        case 'ajustements':
          await _db.deleteAjustementBySupabaseId(supabaseId);
          break;

        case 'utilisateurs':
          await _db.deleteUtilisateurById(supabaseId);
          break;
      }
    } catch (e) {
      debugPrint('SyncService Delete Error: $e');
    }
  }

  Future<void> handleRealtimeInsert(
      String table,
      Map<String, dynamic> newRecord,
      ) async {
    final supabaseId = newRecord['id']?.toString();
    final ownerId = newRecord['owner_id']?.toString();

    if (supabaseId == null) return;
    if (ownerId != currentOwnerId) return;

    try {
      switch (table) {
        case 'produits':
          final p = Produit.fromMap(newRecord)..supabaseId = supabaseId;
          await _db.upsertProduitFromSupabase(p);
          break;

        case 'ventes':
          final v = Vente.fromMap(newRecord)..supabaseId = supabaseId;

          // ✅ Vérifier que le client existe
          if (v.clientId != null) {
            final client = await _db.getClientBySupabaseId(v.clientId.toString());

            if (client == null) {
              debugPrint("⚠️ Client manquant → sync forcée");
              await initialDownload(_sup.currentUserId!);
            }
          }

          await _db.upsertVenteFromSupabase(v);

          if (v.sellerId != _sup.currentUserId) {
            await _notifyNewSale();
          }
          break;

        case 'clients':
          final c = Client.fromMap(newRecord)..supabaseId = supabaseId;
          await _db.upsertClientFromSupabase(c);
          break;

        case 'depenses':
          final d = Depense.fromMap(newRecord)..supabaseId = supabaseId;
          await _db.upsertDepenseFromSupabase(d);
          break;

        case 'dettes':
          final dt = Dette.fromMap(newRecord)..supabaseId = supabaseId;
          await _db.upsertDetteFromSupabase(dt);
          break;

        case 'inventaires_quotidiens':
          final i = InventaireQuotidien.fromMap(newRecord)..supabaseId = supabaseId;
          await _db.upsertInventaireQuotidienFromSupabase(i);
          break;

        case 'ajustements':
          final a = Ajustement.fromMap(newRecord)..supabaseId = supabaseId;
          await _db.upsertAjustementFromSupabase(a);
          break;

        case 'utilisateurs':
          await syncUserProfile(supabaseId);
          break;
      }
    } catch (e) {
      debugPrint('SyncService Insert Error: $e');
    }
  }

  Future<void> handleRealtimeUpdate(
      String table,
      Map<String, dynamic> newRecord,
      ) async {
    final supabaseId = newRecord['id']?.toString();
    final ownerId = newRecord['owner_id']?.toString();

    if (supabaseId == null) return;
    if (ownerId != currentOwnerId) return;

    try {
      switch (table) {
        case 'produits':
          final remoteProduit = Produit.fromMap(newRecord)..supabaseId = supabaseId;

          final localProduit = await _db.getProduitBySupabaseId(supabaseId);

          if (localProduit != null) {
            final remoteUpdated =
            DateTime.tryParse(newRecord['updated_at']?.toString() ?? '');
            final localUpdated = localProduit.updatedAtDate;

            if (localUpdated != null &&
                remoteUpdated != null &&
                localUpdated.isAfter(remoteUpdated)) {
              debugPrint("SyncService: local plus récent → ignore serveur");
              return;
            }

            if (localProduit.quantite == remoteProduit.quantite) return;

            if (localProduit.isSynced == 0) {
              debugPrint("SyncService: local non sync → ignoré");
              return;
            }

            if (remoteProduit.quantite < localProduit.quantite) {
              debugPrint("SyncService: stock serveur < local → ignoré");
              return;
            }
          }

          await _db.upsertProduitFromSupabase(remoteProduit);

          debugPrint(
            'SyncService Realtime: ✅ ${remoteProduit.nom} = ${remoteProduit.quantite}',
          );
          break;

        case 'ventes':
          final v = Vente.fromMap(newRecord)..supabaseId = supabaseId;
          await _db.upsertVenteFromSupabase(v);
          break;

        case 'clients':
          final c = Client.fromMap(newRecord)..supabaseId = supabaseId;
          await _db.upsertClientFromSupabase(c);
          break;

        case 'depenses':
          final d = Depense.fromMap(newRecord)..supabaseId = supabaseId;
          await _db.upsertDepenseFromSupabase(d);
          break;

        case 'dettes':
          final dt = Dette.fromMap(newRecord)..supabaseId = supabaseId;
          await _db.upsertDetteFromSupabase(dt);
          break;

        case 'inventaires_quotidiens':
          final i = InventaireQuotidien.fromMap(newRecord)..supabaseId = supabaseId;
          await _db.upsertInventaireQuotidienFromSupabase(i);
          break;

        case 'ajustements':
          final a = Ajustement.fromMap(newRecord)..supabaseId = supabaseId;
          await _db.upsertAjustementFromSupabase(a);
          break;
      }
    } catch (e) {
      debugPrint('SyncService Update Error: $e');
    }
  }

  // ------------------ Synchronisation montante (Local -> Cloud) ------------------

  Future<void> syncAll({String? ownerId}) async {
    if (_isSyncing) return;
    _isSyncing = true;

    try {
      final userId = _sup.currentUserId;
      if (userId == null) return;

      final resolvedOwnerId =
          ownerId ?? await _db.resolveEffectiveOwnerId(userId) ?? userId;

      currentOwnerId = resolvedOwnerId;

      await _syncClients(ownerId: resolvedOwnerId);
      await _syncProduits(ownerId: resolvedOwnerId);
      await _syncVentes(ownerId: resolvedOwnerId);
      await _syncApprovisionnements(ownerId: resolvedOwnerId);
      await _syncAjustements(ownerId: resolvedOwnerId);
      await _syncDepenses(ownerId: resolvedOwnerId);
      await _syncDettes(ownerId: resolvedOwnerId);
      await _syncInventaires(ownerId: resolvedOwnerId);
      await syncPaiementsDette();
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _syncProduits({required String ownerId}) async {
    final unsynced = await _db.getUnsyncedProduits(ownerId: ownerId);

    for (final p in unsynced) {
      try {
        final isExistingOnSupabase = p.supabaseId != null && p.supabaseId!.isNotEmpty;
        final m = p.toMap();

        // On synchronise TOUT sauf la quantité
        final Map<String, dynamic> dataMap = {
          'nom': m['nom'],
          'categorie': m['categorie'],
          'prix_achat': m['prix_achat'],
          'prix_vente': m['prix_vente'],
          'unite_mesure': m['unite_mesure'],
          'photo': m['photo'],
          'owner_id': ownerId,
          // 🛡️ ON NE MET PAS 'quantite' ICI
        };

        if (isExistingOnSupabase) {
          await _withRetry(() => _sup.updateProduit(p.supabaseId!, dataMap));
        } else {
          // Uniquement à la création, on peut mettre 0 ou la quantité initiale
          dataMap['quantite'] = m['quantite'] ?? 0;
          final res = await _withRetry(() => _sup.insertProduit(dataMap));
          final newSupId = res['id']?.toString();
          if (newSupId != null) {
            await _db.markProduitAsSynced(p.id!, newSupId);
          }
        }
        // On marque comme synchronisé en local
        await _db.markProduitAsSynced(p.id!, p.supabaseId ?? "");
      } catch (e) {
        debugPrint('Erreur sync produit: $e');
      }
    }
  }

  Future<void> _syncAjustements({required String ownerId}) async {
    final unsynced = await _db.getUnsyncedAjustements(ownerId: ownerId);

    for (final a in unsynced) {
      try {
        final localProduct = await _db.getProduitById(a.produitId);

        if (localProduct == null || localProduct.supabaseId == null) {
          // Le produit doit être synchronisé avant de pouvoir envoyer son ajustement
          continue;
        }

        if (a.supabaseId != null && a.supabaseId!.isNotEmpty) {
          continue;
        }

        // On insère le delta (-2, +5, etc.)
        // Ce mouvement déclenchera le calcul automatique du stock sur Supabase
        final res = await _sup.client
            .from('ajustements')
            .insert({
          'produit_id': localProduct.supabaseId,
          'quantite': a.quantite,
          'raison': a.raison,
          'date': a.date,
          'owner_id': ownerId,
        })
            .select()
            .single();

        final supabaseId = res['id']?.toString();

        if (supabaseId != null) {
          await _db.markAjustementAsSynced(a.id!, supabaseId);
        }
      } catch (e) {
        debugPrint('Sync ajustement error: $e');
      }
    }
  }

  Future<void> _syncVentes({required String ownerId}) async {
    final unsynced = await _db.getUnsyncedVentes(ownerId: ownerId);
    if (unsynced.isEmpty) return;

    final localProducts = await _db.getProduits(ownerId: ownerId);
    final productMap = {for (var p in localProducts) p.id: p};

    final localClients = await _db.getClients(ownerId: ownerId);
    final clientMap = {for (var c in localClients) c.id: c};

    for (final v in unsynced) {
      try {
        final p = productMap[v.produitId];
        if (p == null || p.supabaseId == null) continue;

        final client = v.clientId != null ? clientMap[v.clientId] : null;

        final Map<String, dynamic> map = {
          'produit_id': int.tryParse(p.supabaseId!) ?? p.supabaseId,
          'quantite': v.quantite,
          'prix': v.prix,
          'mode_paiement': v.modePaiement ?? 'cash',
          'date': v.createdAt,
          'owner_id': ownerId,
          'seller_id': _sup.currentUserId,
        };

        // ✅ AJOUT IMPORTANT
        if (client != null && client.supabaseId != null) {
          map['client_id'] =
              int.tryParse(client.supabaseId!) ?? client.supabaseId;
        }

        final res = await _withRetry(() => _sup.insertVente(map));

        final supabaseId = res['id']?.toString();
        if (supabaseId != null) {
          await _db.markVenteAsSynced(v.id!, supabaseId);
        }
      } catch (e) {
        debugPrint('SyncService: Erreur sync vente: $e');
      }
    }
  }

  Future<void> _syncClients({required String ownerId}) async {
    final unsynced = await _db.getUnsyncedClients(ownerId: ownerId);

    for (final c in unsynced) {
      try {
        final isExistingOnSupabase =
            c.supabaseId != null && c.supabaseId!.isNotEmpty;
        final m = c.toMap();
        final Map<String, dynamic> dataMap = {
          'nom': m['nom'] ?? '',
          'telephone': m['telephone'] ?? '',
          'email': m['email'] ?? '',
          if (!isExistingOnSupabase) 'owner_id': ownerId,
        };

        if (isExistingOnSupabase) {
          await _withRetry(() => _sup.updateClient(c.supabaseId!, dataMap));
          await _db.markClientAsSynced(c.id!, c.supabaseId!);
        } else {
          final res = await _withRetry(() => _sup.insertClient(dataMap));
          final newId = res['id']?.toString();
          if (newId != null) await _db.markClientAsSynced(c.id!, newId);
        }
      } catch (_) {}
    }
  }

  Future<void> _syncApprovisionnements({required String ownerId}) async {
    final unsynced = await _db.getUnsyncedApprovisionnements(ownerId: ownerId);

    for (final app in unsynced) {
      try {
        final localProduct = await _db.getProduitById(app.produitId);
        if (localProduct == null || localProduct.supabaseId == null) continue;

        final Map<String, dynamic> map = {
          'produit_id': int.tryParse(localProduct.supabaseId!) ?? localProduct.supabaseId,
          'quantite_ajoutee': app.quantiteAjoutee,
          'prix_achat_unitaire': app.prixAchatUnitaire,
          'date_approvisionnement': app.dateApprovisionnement,
          'owner_id': ownerId,
        };

        final res = await _withRetry(
              () => _sup.client.from('approvisionnements').insert(map).select().single(),
        );

        final supabaseId = res['id']?.toString();
        if (supabaseId != null) {
          await _db.markApprovisionnementAsSynced(app.id!, supabaseId);
          debugPrint('SyncService: ✅ Approv synchronisé avec succès !');
        }
      } catch (e) {
        debugPrint('SyncService: ❌ Erreur sync approvisionnement: $e');
      }
    }
  }

  Future<void> _syncDepenses({required String ownerId}) async {
    final unsynced = await _db.getUnsyncedDepenses(ownerId: ownerId);

    for (final d in unsynced) {
      try {
        final map = {
          'owner_id': ownerId,
          'motif': d.motif,
          'montant': d.montant,
          'date': d.date,
        };

        if (d.supabaseId != null && d.supabaseId!.isNotEmpty) {
          final res = await _withRetry(() =>
              _sup.client.from('depenses').update(map).eq('id', d.supabaseId!).select().single());
          final supabaseId = res['id']?.toString();
          if (supabaseId != null) {
            await _db.markDepenseAsSynced(d.id!, supabaseId);
          }
        } else {
          final res = await _withRetry(() =>
              _sup.client.from('depenses').insert(map).select().single());
          final supabaseId = res['id']?.toString();
          if (supabaseId != null) {
            await _db.markDepenseAsSynced(d.id!, supabaseId);
          }
        }
      } catch (e) {
        debugPrint('SyncService: erreur sync dépense: $e');
      }
    }
  }

  Future<void> _syncDettes({required String ownerId}) async {
    final unsynced = await _db.getUnsyncedDettes(ownerId: ownerId);

    for (final d in unsynced) {
      try {
        final client = await _db.getClientById(d.clientId);
        if (client == null || client.supabaseId == null) continue;

        String? venteSupabaseId;
        if (d.venteId != null) {
          final vente = await _db.getVenteById(d.venteId!);
          venteSupabaseId = vente?.supabaseId;
        }

        final map = {
          'owner_id': ownerId,
          'client_id': int.tryParse(client.supabaseId!) ?? client.supabaseId,
          if (venteSupabaseId != null)
            'vente_id': int.tryParse(venteSupabaseId) ?? venteSupabaseId,
          'montant_total': d.montantTotal,
          'montant_paye': d.montantPaye,
          'date_creation': d.dateCreation,
          'statut': d.statut,
        };

        if (d.supabaseId != null && d.supabaseId!.isNotEmpty) {
          final res = await _withRetry(() =>
              _sup.client.from('dettes').update(map).eq('id', d.supabaseId!).select().single());
          final supabaseId = res['id']?.toString();
          if (supabaseId != null) {
            await _db.markDetteAsSynced(d.id!, supabaseId);
          }
        } else {
          final res = await _withRetry(() =>
              _sup.client.from('dettes').insert(map).select().single());
          final supabaseId = res['id']?.toString();
          if (supabaseId != null) {
            await _db.markDetteAsSynced(d.id!, supabaseId);
          }
        }
      } catch (e) {
        debugPrint('SyncService: erreur sync dette: $e');
      }
    }
  }

  Future<void> syncPaiementsDette() async {
    final supabase = Supabase.instance.client;

    final paiements = await DBHelper.instance.getUnsyncedPaiements();

    for (var p in paiements) {
      try {
        final response = await supabase.from('paiements_dette').insert({
          'dette_id': p['dette_id'],
          'montant': p['montant'],
          'date_paiement': p['date_paiement'],
          'owner_id': p['owner_id'],
        }).select().single();

        await DBHelper.instance.markPaiementAsSynced(
          p['id'],
          response['id'].toString(),
        );
      } catch (e) {
        debugPrint("Erreur sync paiement: $e");
      }
    }
  }

  Future<void> _syncInventaires({required String ownerId}) async {
    final unsynced = await _db.getUnsyncedInventairesQuotidiens(ownerId: ownerId);

    for (final i in unsynced) {
      try {
        final produit = await _db.getProduitById(i.produitId);
        if (produit == null || produit.supabaseId == null) continue;

        final map = {
          'owner_id': ownerId,
          'produit_id': int.tryParse(produit.supabaseId!) ?? produit.supabaseId,
          'quantite_theorique': i.quantiteTheorique,
          'quantite_physique': i.quantitePhysique,
          'date_cloture': i.dateCloture,
        };

        if (i.supabaseId != null && i.supabaseId!.isNotEmpty) {
          final res = await _withRetry(() =>
              _sup.client.from('inventaires_quotidiens').update(map).eq('id', i.supabaseId!).select().single());
          final supabaseId = res['id']?.toString();
          if (supabaseId != null) {
            await _db.markInventaireQuotidienAsSynced(i.id!, supabaseId);
          }
        } else {
          final res = await _withRetry(() =>
              _sup.client.from('inventaires_quotidiens').insert(map).select().single());
          final supabaseId = res['id']?.toString();
          if (supabaseId != null) {
            await _db.markInventaireQuotidienAsSynced(i.id!, supabaseId);
          }
        }
      } catch (e) {
        debugPrint('SyncService: erreur sync inventaire: $e');
      }
    }
  }

  Future<void> startRealtimeSync({String? ownerId}) async {
    final userId = _sup.currentUserId;
    if (userId == null) return;

    if (_realtimeChannel != null) {
      await _realtimeChannel!.unsubscribe();
      _realtimeChannel = null;
    }

    final resolvedOwnerId =
        ownerId ?? await _db.resolveEffectiveOwnerId(userId) ?? userId;

    currentOwnerId = resolvedOwnerId;

    try {
      _realtimeChannel = _sup.client.channel('realtime-all-$userId');

      final tables = [
        'produits',
        'ventes',
        'clients',
        'utilisateurs',
        'depenses',
        'dettes',
        'inventaires_quotidiens',
        'ajustements',
      ];

      for (var table in tables) {
        _realtimeChannel!.onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: table,
          callback: (payload) async {
            final recordId = payload.newRecord?['id'] ?? payload.oldRecord?['id'];
            if (recordId == null) return;

            final ownerIdFromRecord =
                payload.oldRecord?['owner_id'] ?? payload.newRecord?['owner_id'];

            if (ownerIdFromRecord != null && ownerIdFromRecord != resolvedOwnerId) {
              return;
            }

            final eventKey = '${payload.eventType}:$table:$recordId';
            if (_seenRealtimeEvents.contains(eventKey)) return;

            _seenRealtimeEvents.add(eventKey);
            if (_seenRealtimeEvents.length > 1000) {
              _seenRealtimeEvents.clear();
            }

            try {
              if (payload.eventType == PostgresChangeEvent.insert) {
                await handleRealtimeInsert(table, payload.newRecord);
              } else if (payload.eventType == PostgresChangeEvent.update) {
                await handleRealtimeUpdate(table, payload.newRecord);
              } else if (payload.eventType == PostgresChangeEvent.delete) {
                await handleRealtimeDelete(table, payload.oldRecord);
              }
            } catch (e) {
              debugPrint('Realtime handler error ($table): $e');
            }
          },
        );
      }

      _realtimeChannel!.subscribe();
    } catch (e) {
      debugPrint('SyncService Realtime Error: $e');
    }
  }

  Future<void> initialDownload(String userId) async {
    try {
      String? ownerId = await _db.resolveEffectiveOwnerId(userId);

      if (ownerId == null) {
        debugPrint("SyncService: Local vide, récupération du profil sur Supabase...");
        final userCloud = await _sup.client
            .from('utilisateurs')
            .select('parent_id')
            .eq('id', userId)
            .maybeSingle();

        ownerId = userCloud?['parent_id']?.toString() ?? userId;
      }

      final String effectiveOwnerId = ownerId!;
      currentOwnerId = effectiveOwnerId;
      debugPrint("📥 Sync initial pour owner_id: $effectiveOwnerId");

      // ---------------- PRODUITS ----------------
      final remoteProduits = await _sup.client
          .from('produits')
          .select()
          .eq('owner_id', effectiveOwnerId);

      debugPrint("📦 Produits: ${remoteProduits.length}");

      for (final pMap in remoteProduits) {
        try {
          final supabaseId = pMap['id']?.toString();
          if (supabaseId == null) continue;

          final produit = Produit.fromMap({
            ...Map<String, dynamic>.from(pMap),
            'supabase_id': supabaseId,
            'is_synced': 1,
          });

          await _db.upsertProduitFromSupabase(produit);
        } catch (e) {
          debugPrint("❌ Produit erreur: $e");
        }
      }

      // ---------------- AJUSTEMENTS ----------------
      final remoteAjustements = await _sup.client
          .from('ajustements')
          .select()
          .eq('owner_id', effectiveOwnerId);

      debugPrint("🛠 Ajustements: ${remoteAjustements.length}");

      for (final aMap in remoteAjustements) {
        try {
          final supabaseId = aMap['id']?.toString();
          if (supabaseId == null) continue;

          final ajustement = Ajustement.fromMap({
            ...Map<String, dynamic>.from(aMap),
            'supabase_id': supabaseId,
            'is_synced': 1,
          });

          await _db.upsertAjustementFromSupabase(ajustement);
        } catch (e) {
          debugPrint("❌ Ajustement erreur: $e");
        }
      }

      // ---------------- CLIENTS ----------------
      final remoteClients = await _sup.client
          .from('clients')
          .select()
          .eq('owner_id', effectiveOwnerId);

      debugPrint("👤 Clients: ${remoteClients.length}");

      for (final cMap in remoteClients) {
        try {
          final supabaseId = cMap['id']?.toString();
          if (supabaseId == null) continue;

          final client = Client.fromMap({
            ...Map<String, dynamic>.from(cMap),
            'supabase_id': supabaseId,
            'is_synced': 1,
          });

          await _db.upsertClientFromSupabase(client);
        } catch (e) {
          debugPrint("❌ Client erreur: $e");
        }
      }

      // ---------------- VENTES ----------------
      final remoteVentes = await _fetchAllVentesFromSupabase(effectiveOwnerId);

      debugPrint("💰 Ventes: ${remoteVentes.length}");

      for (final vMap in remoteVentes) {
        try {
          final supabaseId = vMap['id']?.toString();
          if (supabaseId == null) continue;

          final vente = Vente.fromMap({
            ...Map<String, dynamic>.from(vMap),
            'supabase_id': supabaseId,
            'is_synced': 1,
          });

          await _db.upsertVenteFromSupabase(vente);
        } catch (e) {
          debugPrint("❌ Vente erreur: $e");
        }
      }

      // ---------------- DEPENSES ----------------
      final remoteDepenses = await _sup.client
          .from('depenses')
          .select()
          .eq('owner_id', effectiveOwnerId);

      debugPrint("💸 Dépenses: ${remoteDepenses.length}");

      for (final dMap in remoteDepenses) {
        try {
          final supabaseId = dMap['id']?.toString();
          if (supabaseId == null) continue;

          final depense = Depense.fromMap({
            ...Map<String, dynamic>.from(dMap),
            'supabase_id': supabaseId,
            'is_synced': 1,
          });

          await _db.upsertDepenseFromSupabase(depense);
        } catch (e) {
          debugPrint("❌ Dépense erreur: $e");
        }
      }

      // ---------------- DETTES ----------------
      final remoteDettes = await _sup.client
          .from('dettes')
          .select()
          .eq('owner_id', effectiveOwnerId);

      debugPrint("💳 Dettes: ${remoteDettes.length}");

      for (final dMap in remoteDettes) {
        try {
          final supabaseId = dMap['id']?.toString();
          if (supabaseId == null) continue;

          final dette = Dette.fromMap({
            ...Map<String, dynamic>.from(dMap),
            'supabase_id': supabaseId,
            'is_synced': 1,
          });

          await _db.upsertDetteFromSupabase(dette);
        } catch (e) {
          debugPrint("❌ Dette erreur: $e");
        }
      }

      // ---------------- INVENTAIRES ----------------
      final remoteInventaires = await _sup.client
          .from('inventaires_quotidiens')
          .select()
          .eq('owner_id', effectiveOwnerId);

      debugPrint("📊 Inventaires: ${remoteInventaires.length}");

      for (final iMap in remoteInventaires) {
        try {
          final supabaseId = iMap['id']?.toString();
          if (supabaseId == null) continue;

          final inv = InventaireQuotidien.fromMap({
            ...Map<String, dynamic>.from(iMap),
            'supabase_id': supabaseId,
            'is_synced': 1,
          });

          await _db.upsertInventaireQuotidienFromSupabase(inv);
        } catch (e) {
          debugPrint("❌ Inventaire erreur: $e");
        }
      }

      debugPrint("✅ Sync initial COMPLET terminé avec succès !");
    } catch (e) {
      debugPrint("❌ Erreur critique initialDownload: $e");
    }
  }

  Future<void> ensureLocalUserAndStart(String userId) async {
    if (userId.isEmpty) return;
    await syncUserProfile(userId);
    unawaited(_runBackgroundSync(userId));
  }

  Future<void> _runBackgroundSync(String userId) async {
    await initialDownload(userId);
    await syncAll(ownerId: currentOwnerId);
    await startRealtimeSync(ownerId: currentOwnerId);
  }
}