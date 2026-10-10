import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../l10n/app_strings.dart';

class SettingsState {
  final String themeMode;
  final String smartEntryLanguage;
  final String appLanguage;
  final double brightnessLevel;
  final String userName;
  final String userProfession;
  final int profileColorValue;

  SettingsState({
    this.themeMode = 'light',
    this.smartEntryLanguage = 'romanUrdu',
    this.appLanguage = 'english',
    this.brightnessLevel = 0.0,
    this.userName = '',
    this.userProfession = '',
    this.profileColorValue = 0xFF009688, // Default Teal
  });

  SettingsState copyWith({
    String? themeMode,
    String? smartEntryLanguage,
    String? appLanguage,
    double? brightnessLevel,
    String? userName,
    String? userProfession,
    int? profileColorValue,
  }) {
    return SettingsState(
      themeMode: themeMode ?? this.themeMode,
      smartEntryLanguage: smartEntryLanguage ?? this.smartEntryLanguage,
      appLanguage: appLanguage ?? this.appLanguage,
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
      appLanguage: AppLanguage.parse(_box.get('appLanguage')).name,
      smartEntryLanguage: _box.get('smartEntryLanguage') == 'english'
          ? 'english' : 'romanUrdu',
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

  /// One selection for app text/feedback and Smart NLP's input preference.
  /// Keep both storage keys and setters compatible with existing callers/backups.
  Future<void> updateLanguage(String language) async {
    if (language != 'romanUrdu' && language != 'english') return;
    await _box.putAll({
      'appLanguage': language,
      'smartEntryLanguage': language,
    });
    state = state.copyWith(
      appLanguage: language,
      smartEntryLanguage: language,
    );
  }

  Future<void> updateSmartEntryLanguage(String language) =>
      updateLanguage(language);

  Future<void> updateAppLanguage(String language) => updateLanguage(language);

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
