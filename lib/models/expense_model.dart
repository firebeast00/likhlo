import 'package:hive/hive.dart';

@HiveType(typeId: 1)
class Expense extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String title;

  @HiveField(2)
  final double amount;

  @HiveField(3)
  final DateTime date;

  @HiveField(4)
  final String category;

  @HiveField(5)
  final int colorValue;

  @HiveField(6)
  final String type; // 'expense' or 'income' (allowance)

  @HiveField(7)
  final String walletId; // Links to a Wallet

  @HiveField(8)
  final String workspaceId;

  @HiveField(9)
  final DateTime? deletedAt;

  Expense({
    required this.id,
    required this.title,
    required this.amount,
    required this.date,
    required this.category,
    required this.colorValue,
    this.type = 'expense',
    this.walletId = 'default_cash',
    this.workspaceId = 'personal',
    this.deletedAt,
  });

  Expense copyWith({
    String? id,
    String? title,
    double? amount,
    DateTime? date,
    String? category,
    int? colorValue,
    String? type,
    String? walletId,
    String? workspaceId,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
  }) {
    return Expense(
      id: id ?? this.id,
      title: title ?? this.title,
      amount: amount ?? this.amount,
      date: date ?? this.date,
      category: category ?? this.category,
      colorValue: colorValue ?? this.colorValue,
      type: type ?? this.type,
      walletId: walletId ?? this.walletId,
      workspaceId: workspaceId ?? this.workspaceId,
      deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
    );
  }
}

// 🛠️ BACKWARD-COMPATIBLE HIVE ADAPTER (TypeId 1)
class ExpenseAdapter extends TypeAdapter<Expense> {
  @override
  final int typeId = 1;

  @override
  Expense read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Expense(
      id: fields[0] as String,
      title: fields[1] as String,
      amount: (fields[2] as num).toDouble(),
      date: fields[3] as DateTime,
      category: fields[4] as String,
      colorValue: fields[5] as int,
      type: fields[6] as String? ?? 'expense',
      walletId: fields[7] as String? ?? 'default_cash',
      workspaceId: fields[8] as String? ?? 'personal',
      deletedAt: fields[9] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, Expense obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.amount)
      ..writeByte(3)
      ..write(obj.date)
      ..writeByte(4)
      ..write(obj.category)
      ..writeByte(5)
      ..write(obj.colorValue)
      ..writeByte(6)
      ..write(obj.type)
      ..writeByte(7)
      ..write(obj.walletId)
      ..writeByte(8)
      ..write(obj.workspaceId)
      ..writeByte(9)
      ..write(obj.deletedAt);
  }
}
