// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'debt_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class DebtEntryAdapter extends TypeAdapter<DebtEntry> {
  @override
  final int typeId = 3;

  @override
  DebtEntry read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return DebtEntry(
      id: fields[0] as String,
      borrowerName: fields[1] as String,
      amount: (fields[2] as num).toDouble(),
      type: fields[3] as String,
      dueDate: fields[4] as DateTime?,
      deletedAt: fields[5] as DateTime?,
      walletId: fields[6] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, DebtEntry obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.borrowerName)
      ..writeByte(2)
      ..write(obj.amount)
      ..writeByte(3)
      ..write(obj.type)
      ..writeByte(4)
      ..write(obj.dueDate)
      ..writeByte(5)
      ..write(obj.deletedAt)
      ..writeByte(6)
      ..write(obj.walletId);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DebtEntryAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
