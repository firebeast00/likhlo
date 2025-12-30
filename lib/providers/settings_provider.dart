import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/settings_model.dart';

class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier() : super(AppSettings(
      userName: '',
      themeMode: 'system',
      profileColorValue: 0xFF2563EB,
      userProfession: '', // ✅ Added
      profileIconIndex: 0 // ✅ Added
  )) {
    _loadSettings();
  }

  void _loadSettings() {
    if (!Hive.isBoxOpen('settings')) return;

    final box = Hive.box<AppSettings>('settings');
    final stored = box.get('user_settings');
    if (stored != null) {
      state = stored;
    }
  }

  Future<void> updateProfile(String name, String profession) async {
    final newState = AppSettings(
      userName: name,
      userProfession: profession, // ✅ Added
      themeMode: state.themeMode,
      profileColorValue: state.profileColorValue,
      profileIconIndex: state.profileIconIndex, // ✅ Added
    );
    state = newState;
    await _saveToHive();
  }

  Future<void> updateThemeMode(String mode) async {
    final newState = AppSettings(
      userName: state.userName,
      userProfession: state.userProfession,
      themeMode: mode,
      profileColorValue: state.profileColorValue,
      profileIconIndex: state.profileIconIndex,
    );
    state = newState;
    await _saveToHive();
  }

  Future<void> updateProfileIcon(int index) async {
    final newState = AppSettings(
      userName: state.userName,
      userProfession: state.userProfession,
      themeMode: state.themeMode,
      profileColorValue: state.profileColorValue,
      profileIconIndex: index, // ✅ Updating this
    );
    state = newState;
    await _saveToHive();
  }

  Future<void> updateThemeColor(int colorValue) async {
    final newState = AppSettings(
      userName: state.userName,
      userProfession: state.userProfession,
      themeMode: state.themeMode,
      profileColorValue: colorValue,
      profileIconIndex: state.profileIconIndex,
    );
    state = newState;
    await _saveToHive();
  }

  Future<void> _saveToHive() async {
    if (!Hive.isBoxOpen('settings')) return;
    final box = Hive.box<AppSettings>('settings');
    await box.put('user_settings', state);
  }
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
  return SettingsNotifier();
});