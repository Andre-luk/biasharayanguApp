import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sqflite/sqflite.dart';
import '../models/subscription.dart';

final supabase = Supabase.instance.client;

class SubscriptionSyncService {
  final Database db;

  SubscriptionSyncService({required this.db});

  /// 📤 LOCAL VERS DISTANT (Upload)
  /// Synchronise tous les abonnements créés localement (offline) vers Supabase
  Future<void> syncSubscriptions(String currentUserId) async {
    final rows = await db.query(
      'subscriptions',
      where: 'synced = 0',
    );

    for (var row in rows) {
      final sub = Subscription.fromMap(row);

      try {
        await supabase.from('subscriptions').upsert({
          'id': sub.id,
          'user_id': sub.userId,
          'plan': sub.plan,
          'period_months': sub.periodMonths,
          'start_date': sub.startDate.toIso8601String(),
          'end_date': sub.endDate.toIso8601String(),
          'active': sub.active,
          'activated_by': sub.activatedBy,
          'activated_at': sub.activatedAt.toIso8601String(),
          'transaction_id': sub.transactionId,
          'note': sub.note,
          'created_at': sub.createdAt.toIso8601String(),
          'updated_at': sub.updatedAt.toIso8601String(),
        });

        // Marquer comme synchronisé en local
        await db.update(
          'subscriptions',
          {'synced': 1},
          where: 'id = ?',
          whereArgs: [sub.id],
        );
      } catch (e) {
        print('Erreur upload subscription ${sub.id}: $e');
      }
    }
  }

  /// 📥 DISTANT VERS LOCAL (Download)
  /// Télécharge les abonnements depuis Supabase et met à jour SQLite
  Future<void> downloadAndSaveSubscriptions(String userId) async {
    try {
      // 1. Récupérer les données depuis Supabase
      final List<dynamic> data = await supabase
          .from('subscriptions')
          .select()
          .eq('user_id', userId);

      if (data.isEmpty) return;

      // 2. Préparer l'insertion en masse (Batch) pour la performance
      final batch = db.batch();

      for (var item in data) {
        // On convertit le JSON Supabase en Map pour SQLite
        // Note: Assurez-vous que les noms de colonnes Supabase correspondent
        // à ceux attendus par Subscription.fromMap ou faites le mapping ici.
        final map = Map<String, dynamic>.from(item);

        // IMPORTANT : On marque ces données comme "synced = 1" car elles viennent du serveur
        map['synced'] = 1;

        // SQLite attend souvent 0/1 pour les booléens, Supabase renvoie true/false
        if (map['active'] is bool) {
          map['active'] = (map['active'] == true) ? 1 : 0;
        }

        batch.insert(
          'subscriptions',
          map,
          conflictAlgorithm: ConflictAlgorithm.replace, // Écrase la version locale obsolète
        );
      }

      // 3. Exécuter les insertions
      await batch.commit(noResult: true);
      print("✅ ${data.length} abonnements synchronisés depuis le cloud.");

    } catch (e) {
      print('❌ Erreur download subscriptions: $e');
      // On ne rethrow pas forcément pour ne pas bloquer le login si offline,
      // mais ici le but est de déboguer.
      rethrow;
    }
  }
}