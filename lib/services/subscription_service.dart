// services/subscription_service.dart
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../models/subscription.dart';
import '../utils/date_utils.dart';

final _uuid = Uuid();

Future<void> activateSubscription({
  required Database db,
  required String userId,
  required String plan,
  required String adminId,
  int periodMonths = 1,
  String? transactionId,
  String? note,
}) async {
  final now = DateTime.now();
  final subscription = Subscription(
    id: _uuid.v4(),
    userId: userId,
    plan: plan,
    periodMonths: periodMonths,
    startDate: now,
    endDate: addMonths(now, periodMonths),
    active: true,
    activatedBy: adminId,
    activatedAt: now,
    transactionId: transactionId,
    note: note,
    synced: false,
  );

  await db.insert(
    'subscriptions',
    subscription.toMap(),
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}

/// Retourne le dernier abonnement actif pour un utilisateur donné, ou null si aucun.
Future<Subscription?> _getLatestSubscriptionForUser(Database db, String userId) async {
  final rows = await db.query(
    'subscriptions',
    where: 'user_id = ?',
    whereArgs: [userId],
    orderBy: 'end_date DESC',
    limit: 1,
  );

  if (rows.isEmpty) return null;
  try {
    return Subscription.fromMap(rows.first);
  } catch (_) {
    return null;
  }
}

/// Vérifie si l'utilisateur ou son parent (vendor/admin) a un abonnement actif
Future<bool> isUserSubscribed(Database db, String userId) async {
  // 1) Vérifier l'abonnement de l'utilisateur
  final ownSub = await _getLatestSubscriptionForUser(db, userId);
  if (ownSub != null && ownSub.isActive) return true;

  // 2) Récupérer le parentId si l'utilisateur est collaborateur
  final rows = await db.query(
    'utilisateurs',
    columns: ['parent_id', 'role'],
    where: 'id = ?',
    whereArgs: [userId],
    limit: 1,
  );

  if (rows.isEmpty) return false;

  final row = rows.first;
  final parentId = row['parent_id'] as String?;
  final role = row['role'] as String? ?? 'vendor';

  // Si c'est un collaborateur avec parentId, vérifier l'abonnement du parent
  if (parentId != null && parentId.isNotEmpty) {
    final parentSub = await _getLatestSubscriptionForUser(db, parentId);
    if (parentSub != null && parentSub.isActive) return true;
  }

  // Si l'utilisateur est vendor/admin, son propre abonnement est déjà vérifié
  // Sinon aucun abonnement actif trouvé
  return false;
}
