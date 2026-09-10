// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'recurring_bill_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class RecurringBillAdapter extends TypeAdapter<RecurringBill> {
  @override
  final int typeId = 6;

  @override
  RecurringBill read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return RecurringBill(
      id: fields[0] as String,
      title: fields[1] as String,
      amount: (fields[2] as num).toDouble(),
      frequency: fields[3] as String,
      nextDueDate: fields[4] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, RecurringBill obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.amount)
      ..writeByte(3)
      ..write(obj.frequency)
      ..writeByte(4)
      ..write(obj.nextDueDate);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RecurringBillAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
