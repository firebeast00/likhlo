// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mess_entry_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class MessEntryAdapter extends TypeAdapter<MessEntry> {
  @override
  final int typeId = 7;

  @override
  MessEntry read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return MessEntry(
      id: fields[0] as String,
      title: fields[1] as String,
      totalAmount: (fields[2] as num).toDouble(),
      paidBy: fields[3] as String,
      splitCount: fields[4] as int,
      date: fields[5] as DateTime,
      deletedAt: fields[6] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, MessEntry obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.totalAmount)
      ..writeByte(3)
      ..write(obj.paidBy)
      ..writeByte(4)
      ..write(obj.splitCount)
      ..writeByte(5)
      ..write(obj.date)
      ..writeByte(6)
      ..write(obj.deletedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MessEntryAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
