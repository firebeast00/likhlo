import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

class SettingsState {
  final String themeMode;
  final double brightnessLevel;
  final String userName;
  final String userProfession;
  final int profileColorValue;

  SettingsState({
    this.themeMode = 'light',
    this.brightnessLevel = 0.0,
    this.userName = '',
    this.userProfession = '',
    this.profileColorValue = 0xFF009688, // Default Teal
  });

  SettingsState copyWith({
    String? themeMode,
    double? brightnessLevel,
    String? userName,
    String? userProfession,
    int? profileColorValue,
  }) {
    return SettingsState(
      themeMode: themeMode ?? this.themeMode,
      brightnessLevel: brightnessLevel ?? this.brightnessLevel,
      userName: userName ?? this.userName,
      userProfession: userProfession ?? this.userProfession,
      profileColorValue: profileColorValue ?? this.profileColorValue,
    );
  }
}

class SettingsNotifier extends StateNotifier<SettingsState> {
  final Box _box = Hive.box('settings');

  SettingsNotifier() : super(SettingsState()) {
    _loadSettings();
  }

  void _loadSettings() {
    state = SettingsState(
      themeMode: _box.get('themeMode', defaultValue: 'light'),
      brightnessLevel:
          (_box.get('brightnessLevel', defaultValue: 0.0) as num).toDouble(),
      userName: _box.get('userName', defaultValue: ''),
      userProfession: _box.get('userProfession', defaultValue: ''),
      profileColorValue:
          _box.get('profileColorValue', defaultValue: 0xFF009688),
    );
  }

  void updateThemeMode(String mode) {
    _box.put('themeMode', mode);
    state = state.copyWith(themeMode: mode);
  }

  void updateBrightness(double level) {
    _box.put('brightnessLevel', level);
    state = state.copyWith(brightnessLevel: level);
  }

  void updateUserName(String name) {
    _box.put('userName', name);
    state = state.copyWith(userName: name);
  }

  void updateUserProfession(String prof) {
    _box.put('userProfession', prof);
    state = state.copyWith(userProfession: prof);
  }

  // ✅ Restored method for your Onboarding Screen
  void updateProfile(String name, String prof) {
    _box.put('userName', name);
    _box.put('userProfession', prof);
    state = state.copyWith(userName: name, userProfession: prof);
  }

  void updateProfileColor(int colorValue) {
    _box.put('profileColorValue', colorValue);
    state = state.copyWith(profileColorValue: colorValue);
  }
}

// ✅ Updated Provider definition to use SettingsState
final settingsProvider =
    StateNotifierProvider<SettingsNotifier, SettingsState>((ref) {
  return SettingsNotifier();
});
