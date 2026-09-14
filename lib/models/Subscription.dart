class Subscription {
  final String id;
  final String userId;
  final String plan;
  final int periodMonths;
  final DateTime startDate;
  final DateTime endDate;
  final bool active;
  final String activatedBy;
  final DateTime activatedAt;
  final String? transactionId;
  final String? note;
  final bool synced;
  final DateTime createdAt;
  final DateTime updatedAt;

  Subscription({
    required this.id,
    required this.userId,
    required this.plan,
    this.periodMonths = 1,
    required this.startDate,
    required this.endDate,
    this.active = true,
    required this.activatedBy,
    required this.activatedAt,
    this.transactionId,
    this.note,
    this.synced = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// 🔎 Vérifie si l’abonnement est encore valide
  bool get isActive {
    return active && DateTime.now().isBefore(endDate);
  }

  /// 🔄 SQLite → Dart
  factory Subscription.fromMap(Map<String, dynamic> map) {
    return Subscription(
      id: map['id'],
      userId: map['user_id'],
      plan: map['plan'],
      periodMonths: map['period_months'],
      startDate: DateTime.parse(map['start_date']),
      endDate: DateTime.parse(map['end_date']),
      active: map['active'] == 1,
      activatedBy: map['activated_by'],
      activatedAt: DateTime.parse(map['activated_at']),
      transactionId: map['transaction_id'],
      note: map['note'],
      synced: map['synced'] == 1,
      createdAt: DateTime.parse(map['created_at']),
      updatedAt: DateTime.parse(map['updated_at']),
    );
  }

  /// 🔄 Dart → SQLite
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'plan': plan,
      'period_months': periodMonths,
      'start_date': startDate.toIso8601String(),
      'end_date': endDate.toIso8601String(),
      'active': active ? 1 : 0,
      'activated_by': activatedBy,
      'activated_at': activatedAt.toIso8601String(),
      'transaction_id': transactionId,
      'note': note,
      'synced': synced ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}