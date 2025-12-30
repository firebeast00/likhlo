import 'package:hive/hive.dart';

@HiveType(typeId: 4)
class AppSettings extends HiveObject {
  @HiveField(0)
  String userName;

  @HiveField(1)
  String themeMode; // 'system', 'light', 'dark'

  @HiveField(2)
  int profileColorValue;

  @HiveField(3)
  String userProfession; // ✅ NEW FIELD

  @HiveField(4)
  int profileIconIndex; // ✅ NEW FIELD

  AppSettings({
    required this.userName,
    required this.themeMode,
    required this.profileColorValue,
    this.userProfession = '', // Default empty
    this.profileIconIndex = 0, // Default first icon
  });
}

// ✅ MANUAL ADAPTER (Copy this exactly so you don't need build_runner)
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
      userName: fields[0] as String? ?? '',
      themeMode: fields[1] as String? ?? 'system',
      profileColorValue: fields[2] as int? ?? 0xFF2563EB,
      userProfession: fields[3] as String? ?? '',
      profileIconIndex: fields[4] as int? ?? 0,
    );
  }

  @override
  void write(BinaryWriter writer, AppSettings obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.userName)
      ..writeByte(1)
      ..write(obj.themeMode)
      ..writeByte(2)
      ..write(obj.profileColorValue)
      ..writeByte(3)
      ..write(obj.userProfession)
      ..writeByte(4)
      ..write(obj.profileIconIndex);
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