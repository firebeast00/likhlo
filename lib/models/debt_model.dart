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

  DebtEntry({
    required this.id,
    required this.borrowerName,
    required this.amount,
    required this.type,
    this.dueDate,
    this.deletedAt,
  });

  DebtEntry copyWith({DateTime? deletedAt, bool clearDeletedAt = false}) {
    return DebtEntry(
      id: id,
      borrowerName: borrowerName,
      amount: amount,
      type: type,
      dueDate: dueDate,
      deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
    );
  }
}
