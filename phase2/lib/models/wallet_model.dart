import 'package:hive/hive.dart';

@HiveType(typeId: 8)
class Wallet extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String name;

  @HiveField(2)
  double balance;

  @HiveField(3)
  final bool
      isBackup; // If true, treated as backup reserve (isolated from daily burn rate)

  @HiveField(4)
  final int colorValue;

  @HiveField(5)
  final String walletType; // 'cash', 'jazzcash', 'bank', 'reserve'

  Wallet({
    required this.id,
    required this.name,
    required this.balance,
    this.isBackup = false,
    required this.colorValue,
    this.walletType = 'cash',
  });

  Wallet copyWith({
    String? id,
    String? name,
    double? balance,
    bool? isBackup,
    int? colorValue,
    String? walletType,
  }) {
    return Wallet(
      id: id ?? this.id,
      name: name ?? this.name,
      balance: balance ?? this.balance,
      isBackup: isBackup ?? this.isBackup,
      colorValue: colorValue ?? this.colorValue,
      walletType: walletType ?? this.walletType,
    );
  }
}

// 🛠️ MANUAL HIVE ADAPTER (TypeId 8)
class WalletAdapter extends TypeAdapter<Wallet> {
  @override
  final int typeId = 8;

  @override
  Wallet read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Wallet(
      id: fields[0] as String,
      name: fields[1] as String,
      balance: (fields[2] as num).toDouble(),
      isBackup: fields[3] as bool? ?? false,
      colorValue: fields[4] as int? ?? 0xFF009688,
      walletType: fields[5] as String? ?? 'cash',
    );
  }

  @override
  void write(BinaryWriter writer, Wallet obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.balance)
      ..writeByte(3)
      ..write(obj.isBackup)
      ..writeByte(4)
      ..write(obj.colorValue)
      ..writeByte(5)
      ..write(obj.walletType);
  }
}
