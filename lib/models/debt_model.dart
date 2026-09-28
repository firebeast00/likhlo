import 'package:hive/hive.dart';

part 'debt_model.g.dart';

@HiveType(typeId: 3)
class DebtEntry extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String borrowerName;

  @HiveField(2)
  double amount;

  @HiveField(3)
  String type; // 'lent' or 'borrowed'

  @HiveField(4)
  DateTime? dueDate;

  @HiveField(5)
  DateTime? deletedAt;

  @HiveField(6)
  String? walletId;

  @HiveField(7)
  DateTime? settledAt;

  DebtEntry({
    required this.id,
    required this.borrowerName,
    required this.amount,
    required this.type,
    this.dueDate,
    this.deletedAt,
    this.walletId,
    this.settledAt,
  });

  DebtEntry copyWith({
    String? borrowerName,
    double? amount,
    String? type,
    String? walletId,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
    DateTime? settledAt,
    bool clearSettledAt = false,
  }) {
    return DebtEntry(
      id: id,
      borrowerName: borrowerName ?? this.borrowerName,
      amount: amount ?? this.amount,
      type: type ?? this.type,
      dueDate: dueDate,
      deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
      walletId: walletId ?? this.walletId,
      settledAt: clearSettledAt ? null : (settledAt ?? this.settledAt),
    );
  }
}
