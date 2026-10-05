import '../l10n/app_strings.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'package:quick_actions/quick_actions.dart';

import '../app/app_action.dart';
import '../providers/settings_provider.dart';
import '../providers/expense_provider.dart';
import '../providers/wallet_provider.dart';
import '../models/debt_model.dart';
import '../services/biometric_service.dart';
import '../services/notification_service.dart';
import '../services/monthly_financial_summary_service.dart';
import '../services/voice_privacy_service.dart';
import '../services/audio_feedback_service.dart';
import '../services/udhar_ledger_link_service.dart';
import '../widgets/month_selector_control.dart';
import 'backup_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late Box _prefBox;
  late DateTime _selectedPdfMonth;
  int? _handledAppActionId;

  @override
  void initState() {
    super.initState();
    _prefBox = Hive.box('preferences');
    final now = DateTime.now();
    _selectedPdfMonth = DateTime(now.year, now.month);
  }

  bool _changingAppLanguage = false;

  Future<void> _setAppLanguage(String value) async {
    if (_changingAppLanguage) return;
    setState(() => _changingAppLanguage = true);
    try {
      await AudioFeedbackService().stop();
      await ref.read(settingsProvider.notifier).updateAppLanguage(value);
      if (!mounted) return;
      final confirmation = value == 'romanUrdu'
          ? 'App language is now Roman Urdu.'
          : 'App language is now English.';
      _showNlpSettingsResult(confirmation);
      unawaited(AudioFeedbackService().announceMessage(confirmation));
      // Notification/plugin work is best effort and cannot change saved data.
      unawaited(NotificationService().refreshLocalizedContent());
      unawaited(const QuickActions().setShortcutItems([
        ShortcutItem(type: 'action_voice_log',
          localizedTitle: AppStrings.current.display('Voice Log'), icon: 'ic_mic'),
        ShortcutItem(type: 'action_add_expense',
          localizedTitle: AppStrings.current.display('Add Transaction'), icon: 'ic_add'),
      ]).catchError((Object error) {
        debugPrint('Localized shortcuts unavailable: $error');
      }));
    } finally {
      if (mounted) setState(() => _changingAppLanguage = false);
    }
  }

  Future<void> _previewVoice() async {
    if (!VoicePrivacySettings.read(_prefBox).spokenFeedbackEnabled) {
      _showNlpSettingsResult('Enable Spoken Confirmations to preview the voice.');
      return;
    }
    await AudioFeedbackService().stop();
    await AudioFeedbackService().announceMessage('This is your spoken feedback voice.');
  }

  Future<void> _setPersistentQuickLog(bool enabled) async {
    final preferenceWrite =
        _prefBox.put('persistent_bar_enabled', enabled);
    if (mounted) setState(() {});
    await preferenceWrite;
    await NotificationService().setPersistentStatusBarEnabled(enabled);
  }

  Future<void> _setAppLock(bool enabled, {bool spokenFeedback = false}) async {
    final result = await BiometricService().authenticate(
      reason: enabled
          ? 'Confirm your identity to enable Likhlo App Lock.'
          : 'Confirm your identity to disable Likhlo App Lock.',
      biometricOnly: false,
    );
    if (!mounted) return;
    if (!result.authenticated) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(AppStrings.current.display(result.message))));
      if (spokenFeedback) {
        unawaited(AudioFeedbackService().announceMessage(result.message));
      }
      setState(() {});
      return;
    }
    await _prefBox.put(BiometricService.preferenceKey, enabled);
    if (mounted && spokenFeedback) {
      unawaited(AudioFeedbackService().announceMessage(
        enabled ? 'Likhlo App Lock is enabled.' : 'Likhlo App Lock is disabled.',
      ));
    }
    if (mounted) setState(() {});
  }

  Future<void> _setSmartReminders(bool enabled) async {
    await _prefBox.put('daily_reminder_enabled', enabled);
    if (enabled) {
      await NotificationService().scheduleSmartEntryReminders();
    } else {
      await Future.wait([
        NotificationService().cancelNotification(
          NotificationService.middayReminderId,
        ),
        NotificationService().cancelNotification(
          NotificationService.eveningReminderId,
        ),
        NotificationService().cancelNotification(
          NotificationService.weekendReviewId,
        ),
      ]);
    }
    if (mounted) setState(() {});
  }

  Future<void> _setVoicePreference(String key, bool enabled) async {
    await _prefBox.put(key, enabled);
    if (mounted) setState(() {});
  }

  Future<void> _handlePendingAppAction(AppActionRequest request) async {
    ref.read(appActionProvider.notifier).consume(request.id);
    if (!mounted) return;

    void showResult(String message) {
      _showNlpSettingsResult(message);
      if (mounted && request.spokenFeedback) {
        unawaited(AudioFeedbackService().announceMessage(message));
      }
    }

    switch (request.action) {
      case AppActionType.openMonthlyPdf:
        final requestedMonth = request.month;
        if (requestedMonth == null) {
          if (request.spokenFeedback) {
            unawaited(AudioFeedbackService().announceMessage(
              'Choose a month for the PDF report.',
            ));
          }
          await _choosePdfMonthAndGenerate(context, ref);
          return;
        }
        _selectedPdfMonth = DateTime(
          requestedMonth.year,
          requestedMonth.month,
        );
        if (mounted) setState(() {});
        if (request.spokenFeedback) {
          unawaited(AudioFeedbackService().announceMessage(
            'Opening ${DateFormat('MMMM yyyy').format(_selectedPdfMonth)} PDF report.',
          ));
        }
        await _generatePdf(context, ref, _selectedPdfMonth);
        return;
      case AppActionType.openBackup:
        if (request.spokenFeedback) {
          unawaited(AudioFeedbackService().announceMessage('Opening Backup.'));
        }
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const BackupScreen()),
        );
        return;
      case AppActionType.openStatsMonth:
      case AppActionType.openMonthlyPlan:
      case AppActionType.runMonthlyPlanCommand:
        // These actions are handled by their destination screens.
        return;
      case AppActionType.persistentQuickEntryOn:
      case AppActionType.persistentQuickEntryOff:
        final persistentEnabled =
            request.action == AppActionType.persistentQuickEntryOn;
        final persistentCurrent =
            _prefBox.get('persistent_bar_enabled', defaultValue: true) == true;
        if (persistentCurrent != persistentEnabled) {
          await _setPersistentQuickLog(persistentEnabled);
        }
        showResult(
          persistentEnabled
              ? 'Persistent Quick Entry is enabled.'
              : 'Persistent Quick Entry is disabled.',
        );
        return;
      case AppActionType.smartRemindersOn:
      case AppActionType.smartRemindersOff:
        final remindersEnabled =
            request.action == AppActionType.smartRemindersOn;
        final remindersCurrent =
            _prefBox.get('daily_reminder_enabled', defaultValue: true) == true;
        if (remindersCurrent != remindersEnabled) {
          await _setSmartReminders(remindersEnabled);
        }
        showResult(
          remindersEnabled
              ? 'Smart Entry reminders are enabled.'
              : 'Smart Entry reminders are disabled.',
        );
        return;
      case AppActionType.spokenConfirmationsOn:
      case AppActionType.spokenConfirmationsOff:
        final spokenEnabled =
            request.action == AppActionType.spokenConfirmationsOn;
        final spokenCurrent =
            VoicePrivacySettings.read(_prefBox).spokenFeedbackEnabled;
        if (spokenCurrent != spokenEnabled) {
          await _setVoicePreference(
            VoicePrivacySettings.spokenFeedbackKey,
            spokenEnabled,
          );
        }
        if (!spokenEnabled) await AudioFeedbackService().stop();
        showResult(
          spokenEnabled
              ? 'Spoken confirmations are enabled.'
              : 'Spoken confirmations are disabled.',
        );
        return;
      case AppActionType.smartEntryLanguageRomanUrdu:
      case AppActionType.smartEntryLanguageEnglish:
        final language =
            request.action == AppActionType.smartEntryLanguageRomanUrdu
                ? 'romanUrdu'
                : 'english';
        if (ref.read(settingsProvider).smartEntryLanguage != language) {
          await ref
              .read(settingsProvider.notifier)
              .updateSmartEntryLanguage(language);
        }
        showResult(
          language == 'romanUrdu'
              ? 'Smart Entry language is now Roman Urdu.'
              : 'Smart Entry language is now English.',
        );
        return;
      case AppActionType.appLockOn:
      case AppActionType.appLockOff:
        final lockEnabled = request.action == AppActionType.appLockOn;
        final lockCurrent = _prefBox.get(
              BiometricService.preferenceKey,
              defaultValue: false,
            ) ==
            true;
        if (lockCurrent != lockEnabled) {
          await _setAppLock(
            lockEnabled,
            spokenFeedback: request.spokenFeedback,
          );
        } else {
          showResult(
            lockEnabled
                ? 'Likhlo App Lock is already enabled.'
                : 'Likhlo App Lock is already disabled.',
          );
        }
        return;
    }
  }

  void _showNlpSettingsResult(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(AppStrings.current.display(message)),
        ),
      );
  }

  // --- PROFILE EDIT DIALOG ---
  void _showEditProfileDialog(String currentName, String currentProfession) {
    final nameCtrl = TextEditingController(text: currentName);
    final profCtrl = TextEditingController(text: currentProfession);
    final primaryColor = Color(ref.read(settingsProvider).profileColorValue);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: Text(AppStrings.current.text('edit_profile_cd280a'),
            style: TextStyle(fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: AppStrings.current.text('full_name_64346b'),
                prefixIcon: Icon(Icons.person_rounded, color: primaryColor),
                filled: true,
                fillColor: Theme.of(context).scaffoldBackgroundColor,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: profCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: AppStrings.current.text('profession_role_467818'),
                prefixIcon: Icon(Icons.work_rounded, color: primaryColor),
                filled: true,
                fillColor: Theme.of(context).scaffoldBackgroundColor,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none),
              ),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        actions: [
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(AppStrings.current.text('cancel_77dfd2'),
                      style: TextStyle(
                          color: Colors.grey, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  onPressed: () {
                    ref
                        .read(settingsProvider.notifier)
                        .updateUserName(nameCtrl.text);
                    ref
                        .read(settingsProvider.notifier)
                        .updateUserProfession(profCtrl.text);
                    Navigator.pop(ctx);
                  },
                  child: Text(AppStrings.current.text('save_efc007'),
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  // --- THEME COLOR PICKER DIALOG ---
  void _showColorPicker(int activeColor) {
    final colors = [
      0xFF3B82F6, // Blue
      0xFF10B981, // Emerald
      0xFFF59E0B, // Amber
      0xFFEF4444, // Red
      0xFF8B5CF6, // Violet
      0xFFEC4899, // Pink
      0xFF009688, // Teal
      0xFF0F172A, // Slate
    ];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: Text(AppStrings.current.text('theme_color_29ddb7'),
            style: TextStyle(fontWeight: FontWeight.w800)),
        content: Wrap(
          spacing: 16,
          runSpacing: 16,
          alignment: WrapAlignment.center,
          children: colors.map((colorValue) {
            final isSelected = colorValue == activeColor;
            return GestureDetector(
              onTap: () {
                ref
                    .read(settingsProvider.notifier)
                    .updateProfileColor(colorValue);
                Navigator.pop(ctx);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 55,
                height: 55,
                decoration: BoxDecoration(
                  color: Color(colorValue),
                  shape: BoxShape.circle,
                  border: isSelected
                      ? Border.all(color: Colors.white, width: 3)
                      : null,
                ),
                child: isSelected
                    ? const Icon(Icons.check_rounded,
                        color: Colors.white, size: 28)
                    : null,
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    AppStrings.of(context);
    final settings = ref.watch(settingsProvider);
    final pendingAction = ref.watch(appActionProvider);
    if (pendingAction != null && _handledAppActionId != pendingAction.id) {
      _handledAppActionId = pendingAction.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_handlePendingAppAction(pendingAction));
      });
    }

    final primaryColor = Color(settings.profileColorValue);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final String displayName =
        (settings.userName.isNotEmpty) ? settings.userName : AppStrings.current.display('Set up profile');
    final String displayProf = (settings.userProfession.isNotEmpty)
        ? settings.userProfession
        : AppStrings.current.display('Tap to add details');

    // Read Hive states for Notification toggles
    final bool persistentEnabled =
        _prefBox.get('persistent_bar_enabled', defaultValue: true);
    final bool remindersEnabled =
        _prefBox.get('daily_reminder_enabled', defaultValue: true);
    final bool appLockEnabled = _prefBox.get(
      BiometricService.preferenceKey,
      defaultValue: false,
    );
    final voicePrivacy = VoicePrivacySettings.read(_prefBox);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        children: [
          Text(AppStrings.current.text('preferences_9dfd34'),
              style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5)),
          const SizedBox(height: 24),

          // 1. 🌟 PREMIUM PROFILE HERO CARD
          GestureDetector(
            onTap: () => _showEditProfileDialog(
                settings.userName, settings.userProfession),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [primaryColor, primaryColor.withValues(alpha: 0.75)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(32),
              ),
              child: Row(
                children: [
                  Container(
                    width: 65,
                    height: 65,
                    decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle),
                    child: Center(
                      child: Text(
                        displayName.isNotEmpty
                            ? displayName[0].toUpperCase()
                            : "?",
                        style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            color: primaryColor),
                      ),
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(displayName,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 4),
                        Text(displayProf,
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.85),
                                fontSize: 14,
                                fontWeight: FontWeight.w500),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle),
                    child: const Icon(Icons.edit_rounded,
                        color: Colors.white, size: 20),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),

          // 2. 🎨 APPEARANCE
          Padding(
            padding: EdgeInsets.only(left: 8, bottom: 12),
            child: Text(AppStrings.current.text('appearance_41def7'),
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Colors.grey)),
          ),
          _buildSettingsGroup(
            isDark: isDark,
            children: [
              _buildSwitchTile(
                title: AppStrings.current.text('dark_mode_e7f8b9'),
                subtitle: AppStrings.current.text('sleek_theme_for_night_use_8d3602'),
                icon:
                    isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                iconColor: Colors.indigo,
                value: settings.themeMode == 'dark',
                onChanged: (val) => ref
                    .read(settingsProvider.notifier)
                    .updateThemeMode(val ? 'dark' : 'light'),
              ),
              _buildDivider(),
              ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                leading: _buildIconBox(Icons.color_lens_rounded, primaryColor),
                title: Text(AppStrings.current.text('theme_color_29ddb7'),
                    style:
                        TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                subtitle: Text(AppStrings.current.text('customize_app_accent_0c03d5'),
                    style: TextStyle(fontSize: 13, color: Colors.grey)),
                trailing: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                      color: primaryColor,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: isDark ? Colors.white24 : Colors.black12,
                          width: 2)),
                ),
                onTap: () => _showColorPicker(settings.profileColorValue),
              ),
              _buildDivider(),

              // REFINED BRIGHTNESS SLIDER
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _buildIconBox(
                            Icons.brightness_medium_rounded, Colors.orange),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(AppStrings.current.text('screen_dimmer_732fed'),
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15)),
                              Text(AppStrings.current.text('dims_the_entire_app_interface_50aa9f'),
                                  style: TextStyle(
                                      fontSize: 13, color: Colors.grey)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(Icons.brightness_7_rounded,
                            size: 18, color: Colors.grey.shade400),
                        Expanded(
                          child: Slider(
                            value: settings.brightnessLevel,
                            min: 0.0,
                            max: 0.75, // Prevents pitch black screen
                            activeColor: primaryColor,
                            inactiveColor: primaryColor.withValues(alpha: 0.2),
                            onChanged: (val) => ref
                                .read(settingsProvider.notifier)
                                .updateBrightness(val),
                          ),
                        ),
                        Icon(Icons.brightness_3_rounded,
                            size: 18, color: Colors.grey.shade600),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),

          // 3. 🔔 NOTIFICATIONS & ALERTS
          Padding(
            padding: EdgeInsets.only(left: 8, bottom: 12),
            child: Text(AppStrings.current.text('notifications_alerts_8ac4aa'),
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Colors.grey)),
          ),
          _buildSettingsGroup(
            isDark: isDark,
            children: [
              _buildSwitchTile(
                title: AppStrings.current.text('persistent_quick_entry_f95553'),
                subtitle: AppStrings.current.text('voice_and_direct_text_entry_from_the_status_bar_e28e69'),
                icon: Icons.space_dashboard_rounded,
                iconColor: Colors.teal,
                value: persistentEnabled,
                onChanged: (val) => _setPersistentQuickLog(val),
              ),
              _buildDivider(),
              _buildSwitchTile(
                title: AppStrings.current.text('smart_entry_reminders_e9e662'),
                subtitle: AppStrings.current.text('receive_daily_nudges_to_log_your_expenses_0dba02'),
                icon: Icons.notifications_active_rounded,
                iconColor: Colors.amber.shade600,
                value: remindersEnabled,
                onChanged: (val) => _setSmartReminders(val),
              ),
            ],
          ),
          const SizedBox(height: 32),

          Padding(
            padding: EdgeInsets.only(left: 8, bottom: 12),
            child: Text(
              AppStrings.current.text('voice_privacy_d87a87'),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
          ),
          _buildSettingsGroup(
            isDark: isDark,
            children: [
              ListTile(
                leading: const Icon(Icons.language_rounded),
                title: Text(AppStrings.current.display('App language')),
                subtitle: Text(AppStrings.current.display(
                  'English or Roman Urdu for app text and notifications')),
                trailing: DropdownButton<String>(
                  value: settings.appLanguage,
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(value: 'english', child: Text('English')),
                    DropdownMenuItem(value: 'romanUrdu', child: Text('Roman Urdu')),
                  ],
                  onChanged: _changingAppLanguage ? null : (value) {
                    if (value != null) unawaited(_setAppLanguage(value));
                  },
                ),
              ),
              ListTile(
                leading: const Icon(Icons.volume_up_rounded),
                title: Text(AppStrings.current.display('Preview voice')),
                subtitle: Text(AppStrings.current.display(
                  'English voice is used if an Urdu voice or spoken translation is unavailable.')),
                onTap: _previewVoice,
              ),
              _buildDivider(),
              ListTile(
                leading: const Icon(Icons.language_rounded, color: Colors.teal),
                title: Text(AppStrings.current.text('smart_entry_language_ca86c2')),
                subtitle: Text(AppStrings.current.text('typing_aur_voice_ki_zaban_both_languages_remain__5e25cb')),
                trailing: DropdownButton<String>(
                  value: ref.watch(settingsProvider).smartEntryLanguage,
                  underline: const SizedBox.shrink(),
                  items: [
                    DropdownMenuItem(value: 'romanUrdu', child: Text(AppStrings.current.text('roman_urdu_24aeea'))),
                    DropdownMenuItem(value: 'english', child: Text(AppStrings.current.text('english_649df0'))),
                  ],
                  onChanged: (value) async {
                    if (value == null) return;
                    await ref.read(settingsProvider.notifier).updateSmartEntryLanguage(value);
                  },
                ),
              ),
              _buildDivider(),
              _buildSwitchTile(
                title: AppStrings.current.text('likhlo_app_lock_2ef137'),
                subtitle:
                    AppStrings.current.text('require_fingerprint_face_id_or_device_passcode_a_eee4b0'),
                icon: Icons.lock_outline_rounded,
                iconColor: Colors.indigo,
                value: appLockEnabled,
                onChanged: _setAppLock,
              ),
              _buildDivider(),
              _buildSwitchTile(
                title: AppStrings.current.text('cloud_voice_pilot_fcb911'),
                subtitle:
                    AppStrings.current.text('allow_cloud_speech_only_when_a_secure_gateway_is_60fcf1'),
                icon: Icons.cloud_outlined,
                iconColor: Colors.blue,
                value: voicePrivacy.cloudSpeechEnabled,
                onChanged: (value) => _setVoicePreference(
                  VoicePrivacySettings.cloudSpeechKey,
                  value,
                ),
              ),
              _buildDivider(),
              _buildSwitchTile(
                title: AppStrings.current.text('anonymous_voice_diagnostics_4da485'),
                subtitle:
                    AppStrings.current.text('share_timing_and_error_categories_never_audio_or_f7281d'),
                icon: Icons.analytics_outlined,
                iconColor: Colors.purple,
                value: voicePrivacy.diagnosticsOptIn,
                onChanged: (value) => _setVoicePreference(
                  VoicePrivacySettings.diagnosticsKey,
                  value,
                ),
              ),
              _buildDivider(),
              _buildSwitchTile(
                title: AppStrings.current.text('spoken_confirmations_8da677'),
                subtitle:
                    AppStrings.current.text('use_fixed_transaction_wording_when_voice_feedbac_c1498b'),
                icon: Icons.volume_up_outlined,
                iconColor: Colors.green,
                value: voicePrivacy.spokenFeedbackEnabled,
                onChanged: (value) => _setVoicePreference(
                  VoicePrivacySettings.spokenFeedbackKey,
                  value,
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),

          // 4. 📂 EXPORT REPORT
          Padding(
            padding: EdgeInsets.only(left: 8, bottom: 12),
            child: Text(AppStrings.current.text('data_reports_386d2e'),
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Colors.grey)),
          ),
          _buildSettingsGroup(
            isDark: isDark,
            children: [
              ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                leading: _buildIconBox(
                  Icons.backup_rounded,
                  Colors.blue.shade600,
                ),
                title: Text(
                  AppStrings.current.text('backup_restore_3bdd40'),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                subtitle: Text(
                  AppStrings.current.text('create_or_restore_an_encrypted_likhlo_backup_2ad7ac'),
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const BackupScreen(),
                  ),
                ),
              ),
              _buildDivider(),
              ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                leading: _buildIconBox(
                    Icons.picture_as_pdf_rounded, Colors.red.shade400),
                title: Text(AppStrings.current.text('export_monthly_pdf_f024ee'),
                    style:
                        TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                subtitle: Text(
                    AppStrings.current.text('choose_month_and_export_ccb888', {'p0': DateFormat.yMMMM().format(_selectedPdfMonth)}),
                    style: const TextStyle(fontSize: 13, color: Colors.grey)),
                trailing: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10)),
                  child: Icon(Icons.download_rounded,
                      size: 20, color: Colors.red.shade400),
                ),
                onTap: () => _choosePdfMonthAndGenerate(context, ref),
              ),
            ],
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  // --- UI HELPERS ---
  Widget _buildSettingsGroup(
      {required List<Widget> children, required bool isDark}) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.grey.withValues(alpha: 0.1)),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildDivider() {
    return Divider(
        height: 1,
        thickness: 1,
        color: Colors.grey.withValues(alpha: 0.1),
        indent: 70,
        endIndent: 20);
  }

  Widget _buildIconBox(IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12)),
      child: Icon(icon, color: color, size: 22),
    );
  }

  Widget _buildSwitchTile(
      {required String title,
      required String subtitle,
      required IconData icon,
      required Color iconColor,
      required bool value,
      required Function(bool) onChanged}) {
    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      secondary: _buildIconBox(icon, iconColor),
      title: Text(AppStrings.current.display(title),
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
      subtitle: Text(AppStrings.current.display(subtitle),
          style: const TextStyle(fontSize: 13, color: Colors.grey)),
      activeThumbColor: Color(ref.read(settingsProvider).profileColorValue),
      value: value,
      onChanged: onChanged,
    );
  }

  Future<void> _choosePdfMonthAndGenerate(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final picked = await showMonthYearPickerDialog(
      context,
      initialMonth: _selectedPdfMonth,
      maxMonth: DateTime.now(),
    );
    if (picked == null || !mounted) return;
    setState(() => _selectedPdfMonth = DateTime(picked.year, picked.month));
    await _generatePdf(context, ref, _selectedPdfMonth);
  }

  // --- PROFESSIONAL PDF GENERATOR ---
  Future<void> _generatePdf(
    BuildContext context,
    WidgetRef ref,
    DateTime selectedMonth,
  ) async {
    try {
      if (!Hive.isBoxOpen('debts')) {
        await Hive.openBox<DebtEntry>('debts');
      }

      final allRecords = ref
          .read(expenseProvider)
          .allExpenses
          .toList(growable: false);
      final wallets = ref.read(walletProvider);
      final settings = ref.read(settingsProvider);
      final linkedUdhaarIds = linkedUdharLedgerIds();
      final summary = buildMonthlyFinancialSummary(
        month: selectedMonth,
        transactions: allRecords,
        wallets: wallets,
        linkedUdharIds: linkedUdhaarIds,
      );
      final records = summary.rawTransactions;
      final expenses = summary.reportTransactions;
      final totalSpent = summary.spent;
      final totalIncome = summary.income;
      final netFlow = summary.netFlow;
      final categories = summary.categories;

      final debtBox = Hive.box<DebtEntry>('debts');
      final monthLedgerIds = records.map((entry) => entry.id).toSet();
      final udharEntries = debtBox.values
          .where((entry) => entry.deletedAt == null)
          .where(
            (entry) =>
                monthLedgerIds.contains(entry.id) ||
                monthLedgerIds.contains(
                  UdharLedgerLinkService.settlementId(entry.id),
                ),
          )
          .toList(growable: true);

      final regularFont = pw.Font.ttf(
        await rootBundle.load('assets/fonts/DejaVuSans.ttf'),
      );
      final boldFont = pw.Font.ttf(
        await rootBundle.load('assets/fonts/DejaVuSans-Bold.ttf'),
      );
      final pdf = pw.Document(
        theme: pw.ThemeData.withFont(base: regularFont, bold: boldFont),
      );

      final recordsById = {
        for (final entry in allRecords) entry.id: entry,
      };
      final walletNames = {for (final wallet in wallets) wallet.id: wallet.name};
      final activeUdhar =
          udharEntries.where((entry) => entry.settledAt == null).toList();
      final udharReceivable = activeUdhar
          .where((entry) => entry.type == 'lent')
          .fold<double>(0, (sum, entry) => sum + entry.amount);
      final udharPayable = activeUdhar
          .where((entry) => entry.type == 'borrowed')
          .fold<double>(0, (sum, entry) => sum + entry.amount);

      udharEntries.sort((a, b) {
        final aActive = a.settledAt == null;
        final bActive = b.settledAt == null;
        if (aActive != bActive) return aActive ? -1 : 1;
        final aDue = a.dueDate;
        final bDue = b.dueDate;
        if (aDue != null && bDue != null) return aDue.compareTo(bDue);
        if (aDue != null) return -1;
        if (bDue != null) return 1;
        return a.borrowerName.compareTo(b.borrowerName);
      });

      final dateStr = DateFormat.yMMMM().format(selectedMonth);

      const pdfPrimaryColor = PdfColor.fromInt(0xFF1E3A8A);
      const pageText = PdfColor.fromInt(0xFF0F172A);
      const mutedText = PdfColor.fromInt(0xFF64748B);
      const softBorder = PdfColor.fromInt(0xFFE2E8F0);
      const softSurface = PdfColor.fromInt(0xFFF8FAFC);
      const alternateRow = PdfColor.fromInt(0xFFFAFCFF);

      const expenseColor = PdfColor.fromInt(0xFFDC2626);
      const expenseBg = PdfColor.fromInt(0xFFFEF2F2);
      const incomeColor = PdfColor.fromInt(0xFF15803D);
      const incomeBg = PdfColor.fromInt(0xFFF0FDF4);
      const transferColor = PdfColor.fromInt(0xFF2563EB);
      const transferBg = PdfColor.fromInt(0xFFEFF6FF);
      const receiveColor = PdfColor.fromInt(0xFF047857);
      const receiveBg = PdfColor.fromInt(0xFFECFDF5);
      const payableColor = PdfColor.fromInt(0xFFB91C1C);
      const payableBg = PdfColor.fromInt(0xFFFEF2F2);
      const activeColor = PdfColor.fromInt(0xFFB45309);
      const activeBg = PdfColor.fromInt(0xFFFFFBEB);
      const settledColor = PdfColor.fromInt(0xFF475569);
      const settledBg = PdfColor.fromInt(0xFFF1F5F9);
      const overdueColor = PdfColor.fromInt(0xFFB91C1C);
      const overdueBg = PdfColor.fromInt(0xFFFEF2F2);

      const categoryForeground = <PdfColor>[
        PdfColor.fromInt(0xFFC2410C), // orange
        PdfColor.fromInt(0xFF0369A1), // sky
        PdfColor.fromInt(0xFF6D28D9), // violet
        PdfColor.fromInt(0xFFBE185D), // pink
        PdfColor.fromInt(0xFF047857), // emerald
        PdfColor.fromInt(0xFF4338CA), // indigo
        PdfColor.fromInt(0xFF0F766E), // teal
        PdfColor.fromInt(0xFFB45309), // amber
        PdfColor.fromInt(0xFF334155), // slate
        PdfColor.fromInt(0xFF9F1239), // rose
      ];
      const categoryBackground = <PdfColor>[
        PdfColor.fromInt(0xFFFFF7ED),
        PdfColor.fromInt(0xFFF0F9FF),
        PdfColor.fromInt(0xFFF5F3FF),
        PdfColor.fromInt(0xFFFDF2F8),
        PdfColor.fromInt(0xFFECFDF5),
        PdfColor.fromInt(0xFFEEF2FF),
        PdfColor.fromInt(0xFFF0FDFA),
        PdfColor.fromInt(0xFFFFFBEB),
        PdfColor.fromInt(0xFFF1F5F9),
        PdfColor.fromInt(0xFFFFF1F2),
      ];

      String shortTitle(String value, {int max = 25}) {
        final text = value.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (text.runes.length <= max) return text;
        return '${String.fromCharCodes(text.runes.take(max - 3)).trimRight()}...';
      }

      int categoryIndex(String category) {
        final normalized = category.trim().toLowerCase();
        const known = <String, int>{
          'food': 0,
          'transport': 1,
          'shopping': 2,
          'entertainment': 3,
          'health': 4,
          'education': 5,
          'general': 8,
          'udhaar': 7,
          'debt': 7,
        };
        final fixed = known[normalized];
        if (fixed != null) return fixed;
        var hash = 17;
        for (final unit in normalized.codeUnits) {
          hash = ((hash * 31) + unit) & 0x7fffffff;
        }
        return hash % categoryForeground.length;
      }

      PdfColor categoryColor(String category) =>
          categoryForeground[categoryIndex(category)];
      PdfColor categoryBg(String category) =>
          categoryBackground[categoryIndex(category)];

      String transactionTypeLabel(dynamic entry) {
        if (entry.category.toString().trim().toLowerCase() == 'transfer') {
          return 'Transfer';
        }
        return entry.type == 'income' ? 'Income' : 'Expense';
      }

      PdfColor typeColor(String type) {
        switch (type) {
          case 'Income':
            return incomeColor;
          case 'Transfer':
            return transferColor;
          default:
            return expenseColor;
        }
      }

      PdfColor typeBackground(String type) {
        switch (type) {
          case 'Income':
            return incomeBg;
          case 'Transfer':
            return transferBg;
          default:
            return expenseBg;
        }
      }

      String udharWallet(DebtEntry entry) {
        final directId = entry.walletId;
        if (directId != null && walletNames.containsKey(directId)) {
          return walletNames[directId]!;
        }
        final ledgerWallet = recordsById[entry.id]?.walletId;
        if (ledgerWallet != null && walletNames.containsKey(ledgerWallet)) {
          return walletNames[ledgerWallet]!;
        }
        return 'Legacy';
      }

      String dueLabel(DebtEntry entry) {
        if (entry.settledAt != null) return '-';
        final due = entry.dueDate;
        if (due == null) return 'No due date';
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final dueDay = DateTime(due.year, due.month, due.day);
        final days = dueDay.difference(today).inDays;
        if (days < 0) return '${days.abs()}d overdue';
        if (days == 0) return 'Today';
        if (days == 1) return 'Tomorrow';
        return DateFormat('dd MMM yy').format(due);
      }

      String udharStatus(DebtEntry entry) {
        if (entry.settledAt != null) return 'Settled';
        final due = entry.dueDate;
        if (due == null) return 'Active';
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final dueDay = DateTime(due.year, due.month, due.day);
        if (dueDay.isBefore(today)) return 'Overdue';
        return 'Active';
      }

      PdfColor statusColor(String status) {
        switch (status) {
          case 'Overdue':
            return overdueColor;
          case 'Settled':
            return settledColor;
          default:
            return activeColor;
        }
      }

      PdfColor statusBackground(String status) {
        switch (status) {
          case 'Overdue':
            return overdueBg;
          case 'Settled':
            return settledBg;
          default:
            return activeBg;
        }
      }

      pw.Widget metricCard(
        String title,
        String value,
        PdfColor color, {
        String? subtitle,
      }) {
        return pw.Expanded(
          child: pw.Container(
            padding: const pw.EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 11,
            ),
            decoration: pw.BoxDecoration(
              color: softSurface,
              border: pw.Border(
                left: pw.BorderSide(color: color, width: 3),
              ),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  AppStrings.current.display(title),
                  style: const pw.TextStyle(
                    fontSize: 8.5,
                    color: mutedText,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  value,
                  style: pw.TextStyle(
                    fontSize: 11.5,
                    fontWeight: pw.FontWeight.bold,
                    color: color,
                  ),
                ),
                if (subtitle != null) ...[
                  pw.SizedBox(height: 2),
                  pw.Text(
                    AppStrings.current.display(subtitle),
                    style: const pw.TextStyle(
                      fontSize: 7.5,
                      color: mutedText,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      }

      pw.Widget amountCard(String title, double value, PdfColor color) =>
          metricCard(title, 'Rs. ${value.toStringAsFixed(2)}', color);

      pw.Widget pill(
        String label,
        PdfColor foreground,
        PdfColor background, {
        double fontSize = 7.5,
      }) {
        return pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: pw.BoxDecoration(
            color: background,
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
          ),
          child: pw.Text(
            AppStrings.current.display(label),
            style: pw.TextStyle(
              color: foreground,
              fontSize: fontSize,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        );
      }

      pw.Widget tableHeaderCell(
        String text, {
        pw.TextAlign align = pw.TextAlign.left,
      }) {
        return pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 7),
          child: pw.Text(
            AppStrings.current.display(text),
            textAlign: align,
            style: pw.TextStyle(
              color: PdfColors.white,
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        );
      }

      pw.Widget bodyCell(
        String text, {
        PdfColor color = pageText,
        pw.TextAlign align = pw.TextAlign.left,
        bool bold = false,
      }) {
        return pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 7),
          child: pw.Text(
            text,
            textAlign: align,
            maxLines: 2,
            overflow: pw.TextOverflow.clip,
            style: pw.TextStyle(
              fontSize: 8,
              color: color,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        );
      }

      pw.Widget transactionTable() {
        final rows = <pw.TableRow>[
          pw.TableRow(
            repeat: true,
            decoration: const pw.BoxDecoration(color: pdfPrimaryColor),
            children: [
              tableHeaderCell('Date'),
              tableHeaderCell('Title'),
              tableHeaderCell('Type'),
              tableHeaderCell('Category'),
              tableHeaderCell('Amount', align: pw.TextAlign.right),
            ],
          ),
        ];

        for (var index = 0; index < expenses.length; index++) {
          final entry = expenses[index];
          final type = transactionTypeLabel(entry);
          final catColor = categoryColor(entry.category);
          final catBg = categoryBg(entry.category);
          rows.add(
            pw.TableRow(
              decoration: pw.BoxDecoration(
                color: index.isEven ? PdfColors.white : alternateRow,
                border: const pw.Border(
                  bottom: pw.BorderSide(color: softBorder, width: 0.5),
                ),
              ),
              children: [
                bodyCell(DateFormat('dd MMM yy').format(entry.date)),
                bodyCell(shortTitle(entry.title, max: 30), bold: true),
                pw.Padding(
                  padding:
                      const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 6),
                  child: pill(
                    type,
                    typeColor(type),
                    typeBackground(type),
                  ),
                ),
                pw.Padding(
                  padding:
                      const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 6),
                  child: pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    decoration: pw.BoxDecoration(
                      color: catBg,
                      borderRadius:
                          const pw.BorderRadius.all(pw.Radius.circular(10)),
                    ),
                    child: pw.Row(
                      mainAxisSize: pw.MainAxisSize.min,
                      children: [
                        pw.Container(
                          width: 5,
                          height: 5,
                          decoration: pw.BoxDecoration(
                            color: catColor,
                            shape: pw.BoxShape.circle,
                          ),
                        ),
                        pw.SizedBox(width: 4),
                        pw.Flexible(
                          child: pw.Text(
                            shortTitle(AppStrings.current.display(entry.category), max: 18),
                            maxLines: 1,
                            style: pw.TextStyle(
                              color: catColor,
                              fontSize: 7.5,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                bodyCell(
                  entry.amount.toStringAsFixed(2),
                  color: typeColor(type),
                  align: pw.TextAlign.right,
                  bold: true,
                ),
              ],
            ),
          );
        }

        return pw.Table(
          columnWidths: const {
            0: pw.FixedColumnWidth(62),
            1: pw.FlexColumnWidth(2.1),
            2: pw.FixedColumnWidth(62),
            3: pw.FlexColumnWidth(1.45),
            4: pw.FixedColumnWidth(68),
          },
          defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
          children: rows,
        );
      }

      pw.Widget udharTable() {
        final rows = <pw.TableRow>[
          pw.TableRow(
            repeat: true,
            decoration: const pw.BoxDecoration(color: pdfPrimaryColor),
            children: [
              tableHeaderCell('Person'),
              tableHeaderCell('Direction'),
              tableHeaderCell('Wallet'),
              tableHeaderCell('Due'),
              tableHeaderCell('Status'),
              tableHeaderCell('Amount', align: pw.TextAlign.right),
            ],
          ),
        ];

        for (var index = 0; index < udharEntries.length; index++) {
          final entry = udharEntries[index];
          final isReceive = entry.type == 'lent';
          final direction = isReceive ? 'To receive' : 'To pay';
          final directionColor = isReceive ? receiveColor : payableColor;
          final directionBg = isReceive ? receiveBg : payableBg;
          final status = udharStatus(entry);
          rows.add(
            pw.TableRow(
              decoration: pw.BoxDecoration(
                color: index.isEven ? PdfColors.white : alternateRow,
                border: const pw.Border(
                  bottom: pw.BorderSide(color: softBorder, width: 0.5),
                ),
              ),
              children: [
                bodyCell(shortTitle(entry.borrowerName, max: 24), bold: true),
                pw.Padding(
                  padding:
                      const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 6),
                  child: pill(direction, directionColor, directionBg),
                ),
                bodyCell(shortTitle(udharWallet(entry), max: 18)),
                bodyCell(dueLabel(entry)),
                pw.Padding(
                  padding:
                      const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 6),
                  child: pill(
                    status,
                    statusColor(status),
                    statusBackground(status),
                  ),
                ),
                bodyCell(
                  entry.amount.toStringAsFixed(2),
                  color: directionColor,
                  align: pw.TextAlign.right,
                  bold: true,
                ),
              ],
            ),
          );
        }

        return pw.Table(
          columnWidths: const {
            0: pw.FlexColumnWidth(1.6),
            1: pw.FixedColumnWidth(70),
            2: pw.FlexColumnWidth(1.2),
            3: pw.FixedColumnWidth(70),
            4: pw.FixedColumnWidth(60),
            5: pw.FixedColumnWidth(66),
          },
          defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
          children: rows,
        );
      }

      pdf.addPage(
        pw.MultiPage(
          maxPages: 1000,
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(34, 34, 34, 30),
          footer: (context) => pw.Container(
            margin: const pw.EdgeInsets.only(top: 10),
            padding: const pw.EdgeInsets.only(top: 6),
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                top: pw.BorderSide(color: softBorder, width: 0.5),
              ),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  AppStrings.current.text('likhlo_monthly_summary_3c9ad8'),
                  style: const pw.TextStyle(fontSize: 7.5, color: mutedText),
                ),
                pw.Text(
                  AppStrings.current.text('page_of_6e848e', {'p0': context.pageNumber, 'p1': context.pagesCount}),
                  style: const pw.TextStyle(fontSize: 7.5, color: mutedText),
                ),
              ],
            ),
          ),
          build: (pw.Context context) {
            return [
              pw.Container(
                padding: const pw.EdgeInsets.only(bottom: 12),
                decoration: const pw.BoxDecoration(
                  border: pw.Border(
                    bottom: pw.BorderSide(color: softBorder, width: 1),
                  ),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          AppStrings.current.text('likhlo_b062c4'),
                          style: pw.TextStyle(
                            fontSize: 27,
                            fontWeight: pw.FontWeight.bold,
                            color: pdfPrimaryColor,
                          ),
                        ),
                        pw.SizedBox(height: 3),
                        pw.Text(
                          AppStrings.current.text('monthly_financial_summary_29a988'),
                          style: const pw.TextStyle(
                            fontSize: 13,
                            color: pageText,
                          ),
                        ),
                        pw.SizedBox(height: 3),
                        pw.Text(
                          AppStrings.current.text('ledger_entries_3f5f01', {'p0': expenses.length, 'p1': udharEntries.isNotEmpty ? ' + ${udharEntries.length} Udhar records' : '', 'p2': udharEntries.length}),
                          style: const pw.TextStyle(
                            fontSize: 8.5,
                            color: mutedText,
                          ),
                        ),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(
                          settings.userName.isNotEmpty
                              ? settings.userName
                              : AppStrings.current.text('student_account_78d744'),
                          style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 12,
                            color: pageText,
                          ),
                        ),
                        pw.SizedBox(height: 3),
                        pw.Text(
                          dateStr,
                          style: const pw.TextStyle(
                            fontSize: 9,
                            color: mutedText,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 14),
              pw.Row(
                children: [
                  amountCard('Income', totalIncome, incomeColor),
                  pw.SizedBox(width: 7),
                  amountCard('Expenses', totalSpent, expenseColor),
                  pw.SizedBox(width: 7),
                  amountCard(
                    'Net flow',
                    netFlow,
                    netFlow >= 0 ? incomeColor : expenseColor,
                  ),
                  pw.SizedBox(width: 7),
                  metricCard(
                    'Entries',
                    '${summary.transactionCount}',
                    pdfPrimaryColor,
                  ),
                ],
              ),
              if (categories.isNotEmpty) ...[
                pw.SizedBox(height: 18),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      AppStrings.current.text('spending_by_category_d4aadf'),
                      style: pw.TextStyle(
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                        color: pageText,
                      ),
                    ),
                    pw.Text(
                      AppStrings.current.text('categories_7326ba', {'p0': categories.length}),
                      style: const pw.TextStyle(
                        fontSize: 8,
                        color: mutedText,
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 8),
                pw.Wrap(
                  spacing: 7,
                  runSpacing: 6,
                  children: [
                    for (final category in categories)
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 4,
                        ),
                        decoration: pw.BoxDecoration(
                          color: categoryBg(category.key),
                          borderRadius: const pw.BorderRadius.all(
                            pw.Radius.circular(10),
                          ),
                        ),
                        child: pw.Row(
                          mainAxisSize: pw.MainAxisSize.min,
                          children: [
                            pw.Container(
                              width: 6,
                              height: 6,
                              decoration: pw.BoxDecoration(
                                color: categoryColor(category.key),
                                shape: pw.BoxShape.circle,
                              ),
                            ),
                            pw.SizedBox(width: 4),
                            pw.Text(
                              AppStrings.current.text('rs_3921b4', {'p0': AppLabel(shortTitle(category.key, max: 18)), 'p1': category.value.toStringAsFixed(0)}),
                              style: pw.TextStyle(
                                fontSize: 7.5,
                                color: categoryColor(category.key),
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
              pw.SizedBox(height: 20),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    AppStrings.current.text('transaction_history_4ed32a'),
                    style: pw.TextStyle(
                      fontSize: 15,
                      fontWeight: pw.FontWeight.bold,
                      color: pageText,
                    ),
                  ),
                  pw.Text(
                    AppStrings.current.text('entries_f8a4e0', {'p0': expenses.length}),
                    style: const pw.TextStyle(
                      fontSize: 8,
                      color: mutedText,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 5),
              pw.Wrap(
                spacing: 9,
                runSpacing: 4,
                children: [
                  pill('Expense', expenseColor, expenseBg),
                  pill('Income', incomeColor, incomeBg),
                  pill('Transfer', transferColor, transferBg),
                ],
              ),
              pw.SizedBox(height: 9),
              if (expenses.isEmpty)
                pw.Container(
                  padding: const pw.EdgeInsets.all(14),
                  color: softSurface,
                  child: pw.Text(
                    AppStrings.current.text('no_ledger_transactions_available_1abd8e'),
                    style: const pw.TextStyle(fontSize: 9, color: mutedText),
                  ),
                )
              else
                transactionTable(),
              if (udharEntries.isNotEmpty) ...[
                pw.SizedBox(height: 22),
                pw.Container(
                  padding: const pw.EdgeInsets.fromLTRB(11, 10, 11, 10),
                  decoration: const pw.BoxDecoration(
                    color: PdfColor.fromInt(0xFFFFFBEB),
                    border: pw.Border(
                      left: pw.BorderSide(color: activeColor, width: 3),
                    ),
                  ),
                  child: pw.Row(
                    children: [
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              AppStrings.current.text('udhar_debt_44bce8'),
                              style: pw.TextStyle(
                                fontSize: 14,
                                fontWeight: pw.FontWeight.bold,
                                color: pageText,
                              ),
                            ),
                            pw.SizedBox(height: 2),
                            pw.Text(
                              AppStrings.current.text('udhar_activity_linked_to_this_month_status_refle_1265dd'),
                              style: const pw.TextStyle(
                                fontSize: 8,
                                color: mutedText,
                              ),
                            ),
                          ],
                        ),
                      ),
                      pw.Text(
                        AppStrings.current.text('active_c24984', {'p0': activeUdhar.length}),
                        style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                          color: activeColor,
                        ),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 9),
                pw.Row(
                  children: [
                    amountCard('To receive', udharReceivable, receiveColor),
                    pw.SizedBox(width: 7),
                    amountCard('To pay', udharPayable, payableColor),
                    pw.SizedBox(width: 7),
                    metricCard(
                      'Udhar records',
                      '${udharEntries.length}',
                      activeColor,
                      subtitle:
                          '${udharEntries.where((entry) => entry.settledAt != null).length} settled',
                    ),
                  ],
                ),
                pw.SizedBox(height: 9),
                udharTable(),
              ],
              pw.SizedBox(height: 14),
              pw.Center(
                child: pw.Text(
                  AppStrings.current.text('generated_securely_via_likhlo_expense_manager_686e4a'),
                  style: const pw.TextStyle(
                    fontSize: 8,
                    color: mutedText,
                  ),
                ),
              ),
            ];
          },
        ),
      );

      final bytes = await pdf.save();
      await Printing.layoutPdf(
        onLayout: (format) async => bytes,
        name: "Likhlo_Monthly_Summary_${DateFormat('yyyy-MM').format(selectedMonth)}.pdf",
      );
    } catch (error) {
      debugPrint('PDF export failed: $error');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.current.text('could_not_export_the_report_please_try_again_1182f1')),
        ),
      );
    }
  }

}
