import 'package:hive/hive.dart';

part 'settings_model.g.dart';

@HiveType(typeId: 4)
class AppSettings extends HiveObject {
  // ✅ FIX 1: Added defaultValue to tell Hive how to handle nulls
  @HiveField(0, defaultValue: 'system')
  String themeMode;

  @HiveField(1, defaultValue: '')
  String userName;

  @HiveField(2, defaultValue: 'Student')
  String userProfession;

  @HiveField(3, defaultValue: 0xFF00BFA5)
  int profileColorValue;

  @HiveField(4, defaultValue: 0)
  int profileIconIndex;

  @HiveField(5, defaultValue: 0.0)
  double brightnessLevel;

  @HiveField(6)
  String? customRingtonePath;

  AppSettings({
    this.themeMode = 'system',
    this.userName = '',
    this.userProfession = 'Student',
    this.profileColorValue = 0xFF00BFA5,
    this.profileIconIndex = 0,
    this.brightnessLevel = 0.0,
    this.customRingtonePath,
  });

  // ✅ FIX 2: Added copyWith so Riverpod can update the state properly
  AppSettings copyWith({
    String? themeMode,
    String? userName,
    String? userProfession,
    int? profileColorValue,
    int? profileIconIndex,
    double? brightnessLevel,
    String? customRingtonePath,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      userName: userName ?? this.userName,
      userProfession: userProfession ?? this.userProfession,
      profileColorValue: profileColorValue ?? this.profileColorValue,
      profileIconIndex: profileIconIndex ?? this.profileIconIndex,
      brightnessLevel: brightnessLevel ?? this.brightnessLevel,
      customRingtonePath: customRingtonePath ?? this.customRingtonePath,
    );
  }
}