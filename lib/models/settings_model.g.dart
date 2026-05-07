// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'settings_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class AppSettingsAdapter extends TypeAdapter<AppSettings> {
  @override
  final int typeId = 4;

  @override
  AppSettings read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return AppSettings(
      themeMode: fields[0] == null ? 'system' : fields[0] as String,
      userName: fields[1] == null ? '' : fields[1] as String,
      userProfession: fields[2] == null ? 'Student' : fields[2] as String,
      profileColorValue: fields[3] == null ? 4278239141 : fields[3] as int,
      profileIconIndex: fields[4] == null ? 0 : fields[4] as int,
      brightnessLevel: fields[5] == null ? 0.0 : fields[5] as double,
      customRingtonePath: fields[6] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, AppSettings obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.themeMode)
      ..writeByte(1)
      ..write(obj.userName)
      ..writeByte(2)
      ..write(obj.userProfession)
      ..writeByte(3)
      ..write(obj.profileColorValue)
      ..writeByte(4)
      ..write(obj.profileIconIndex)
      ..writeByte(5)
      ..write(obj.brightnessLevel)
      ..writeByte(6)
      ..write(obj.customRingtonePath);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppSettingsAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
