import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';

import '../providers/settings_provider.dart';
import '../providers/expense_provider.dart';
import '../providers/wallet_provider.dart';
import '../models/debt_model.dart';
import '../services/biometric_service.dart';
import '../services/notification_service.dart';
import '../services/voice_privacy_service.dart';
import '../services/udhar_ledger_link_service.dart';
import 'backup_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late Box _prefBox;

  @override
  void initState() {
    super.initState();
    _prefBox = Hive.box('preferences');
  }

  Future<void> _setPersistentQuickLog(bool enabled) async {
    final preferenceWrite =
        _prefBox.put('persistent_bar_enabled', enabled);
    if (mounted) setState(() {});
    await preferenceWrite;
    await NotificationService().setPersistentStatusBarEnabled(enabled);
  }

  Future<void> _setAppLock(bool enabled) async {
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
        ..showSnackBar(SnackBar(content: Text(result.message)));
      setState(() {});
      return;
    }
    await _prefBox.put(BiometricService.preferenceKey, enabled);
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
        title: const Text("Edit Profile",
            style: TextStyle(fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: "Full Name",
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
                labelText: "Profession / Role",
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
                  child: const Text("Cancel",
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
                  child: const Text("Save",
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
        title: const Text("Theme Color",
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
    final settings = ref.watch(settingsProvider);
    final primaryColor = Color(settings.profileColorValue);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final String displayName =
        (settings.userName.isNotEmpty) ? settings.userName : "Set up profile";
    final String displayProf = (settings.userProfession.isNotEmpty)
        ? settings.userProfession
        : "Tap to add details";

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
          const Text("Preferences",
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
          const Padding(
            padding: EdgeInsets.only(left: 8, bottom: 12),
            child: Text("Appearance",
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Colors.grey)),
          ),
          _buildSettingsGroup(
            isDark: isDark,
            children: [
              _buildSwitchTile(
                title: "Dark Mode",
                subtitle: "Sleek theme for night use",
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
                title: const Text("Theme Color",
                    style:
                        TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                subtitle: const Text("Customize app accent",
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
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("Screen Dimmer",
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15)),
                              Text("Dims the entire app interface",
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
          const Padding(
            padding: EdgeInsets.only(left: 8, bottom: 12),
            child: Text("Notifications & Alerts",
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Colors.grey)),
          ),
          _buildSettingsGroup(
            isDark: isDark,
            children: [
              _buildSwitchTile(
                title: "Persistent Quick Entry",
                subtitle: "Voice and direct text entry from the status bar",
                icon: Icons.space_dashboard_rounded,
                iconColor: Colors.teal,
                value: persistentEnabled,
                onChanged: (val) => _setPersistentQuickLog(val),
              ),
              _buildDivider(),
              _buildSwitchTile(
                title: "Smart Entry Reminders",
                subtitle: "Receive daily nudges to log your expenses",
                icon: Icons.notifications_active_rounded,
                iconColor: Colors.amber.shade600,
                value: remindersEnabled,
                onChanged: (val) => _setSmartReminders(val),
              ),
            ],
          ),
          const SizedBox(height: 32),

          const Padding(
            padding: EdgeInsets.only(left: 8, bottom: 12),
            child: Text(
              "Voice & Privacy",
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
                leading: const Icon(Icons.language_rounded, color: Colors.teal),
                title: const Text('Smart Entry language'),
                subtitle: const Text('Typing aur voice ki zaban. Both languages remain supported.'),
                trailing: DropdownButton<String>(
                  value: ref.watch(settingsProvider).smartEntryLanguage,
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(value: 'romanUrdu', child: Text('Roman Urdu')),
                    DropdownMenuItem(value: 'english', child: Text('English')),
                  ],
                  onChanged: (value) async {
                    if (value == null) return;
                    await ref.read(settingsProvider.notifier).updateSmartEntryLanguage(value);
                  },
                ),
              ),
              _buildDivider(),
              _buildSwitchTile(
                title: "Likhlo App Lock",
                subtitle:
                    "Require fingerprint, Face ID, or device passcode after leaving the app",
                icon: Icons.lock_outline_rounded,
                iconColor: Colors.indigo,
                value: appLockEnabled,
                onChanged: _setAppLock,
              ),
              _buildDivider(),
              _buildSwitchTile(
                title: "Cloud Voice Pilot",
                subtitle:
                    "Allow cloud speech only when a secure gateway is configured",
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
                title: "Anonymous Voice Diagnostics",
                subtitle:
                    "Share timing and error categories, never audio or transcripts",
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
                title: "Spoken Confirmations",
                subtitle:
                    "Use fixed transaction wording when voice feedback is available",
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
          const Padding(
            padding: EdgeInsets.only(left: 8, bottom: 12),
            child: Text("Data & Reports",
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
                title: const Text(
                  "Backup & Restore",
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                subtitle: const Text(
                  "Create or restore an encrypted Likhlo backup",
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
                title: const Text("Export Monthly PDF",
                    style:
                        TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                subtitle: const Text("Generate a professional statement",
                    style: TextStyle(fontSize: 13, color: Colors.grey)),
                trailing: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10)),
                  child: Icon(Icons.download_rounded,
                      size: 20, color: Colors.red.shade400),
                ),
                onTap: () => _generatePdf(context, ref),
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
      title: Text(title,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
      subtitle: Text(subtitle,
          style: const TextStyle(fontSize: 13, color: Colors.grey)),
      activeThumbColor: Color(ref.read(settingsProvider).profileColorValue),
      value: value,
      onChanged: onChanged,
    );
  }

  // --- PROFESSIONAL PDF GENERATOR ---
  Future<void> _generatePdf(BuildContext context, WidgetRef ref) async {
    try {
      if (!Hive.isBoxOpen('debts')) {
        await Hive.openBox<DebtEntry>('debts');
      }

      final records = ref
          .read(expenseProvider)
          .allExpenses
          .toList(growable: false);
      final wallets = ref.read(walletProvider);
      final settings = ref.read(settingsProvider);
      final debtBox = Hive.box<DebtEntry>('debts');
      final udharEntries = debtBox.values
          .where((entry) => entry.deletedAt == null)
          .toList(growable: false);

      final linkedUdhaarIds = linkedUdharLedgerIds();
      final expenses = visibleTransactions(records)
          .where((entry) => !linkedUdhaarIds.contains(entry.id))
          .toList(growable: false);

      final regularFont = pw.Font.ttf(
        await rootBundle.load('assets/fonts/DejaVuSans.ttf'),
      );
      final boldFont = pw.Font.ttf(
        await rootBundle.load('assets/fonts/DejaVuSans-Bold.ttf'),
      );
      final pdf = pw.Document(
        theme: pw.ThemeData.withFont(base: regularFont, bold: boldFont),
      );

      final totalSpent = records
          .where(
            (entry) =>
                entry.type == 'expense' &&
                entry.category != 'Transfer' &&
                !linkedUdhaarIds.contains(entry.id),
          )
          .fold<double>(0, (sum, item) => sum + item.amount);
      final totalIncome = records
          .where(
            (entry) =>
                entry.type == 'income' &&
                entry.category != 'Transfer' &&
                !linkedUdhaarIds.contains(entry.id),
          )
          .fold<double>(0, (sum, item) => sum + item.amount);
      final remaining = wallets.fold<double>(
        0,
        (sum, wallet) =>
            sum + ref.read(walletProvider.notifier).getBalanceForWallet(wallet.id),
      );
      // Preserve the existing report definition so historical exports reconcile.
      final totalAmount = remaining + totalSpent;

      final byCategory = <String, double>{};
      for (final entry in records.where(
        (entry) =>
            entry.type == 'expense' &&
            entry.category != 'Transfer' &&
            !linkedUdhaarIds.contains(entry.id),
      )) {
        byCategory.update(
          entry.category,
          (sum) => sum + entry.amount,
          ifAbsent: () => entry.amount,
        );
      }
      final categories = byCategory.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      final recordsById = {for (final entry in records) entry.id: entry};
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

      final dateStr = DateFormat.yMMMM().format(DateTime.now());

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
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  title,
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
                    subtitle,
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
            label,
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
            text,
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
                            shortTitle(entry.category, max: 18),
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
                  'Likhlo Financial Statement',
                  style: const pw.TextStyle(fontSize: 7.5, color: mutedText),
                ),
                pw.Text(
                  'Page ${context.pageNumber} of ${context.pagesCount}',
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
                          'LIKHLO',
                          style: pw.TextStyle(
                            fontSize: 27,
                            fontWeight: pw.FontWeight.bold,
                            color: pdfPrimaryColor,
                          ),
                        ),
                        pw.SizedBox(height: 3),
                        pw.Text(
                          'Financial Statement',
                          style: const pw.TextStyle(
                            fontSize: 13,
                            color: pageText,
                          ),
                        ),
                        pw.SizedBox(height: 3),
                        pw.Text(
                          '${expenses.length} ledger entries'
                          '${udharEntries.isNotEmpty ? ' + ${udharEntries.length} Udhar records' : ''}',
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
                              : 'Student Account',
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
                  amountCard('Total amount', totalAmount, pdfPrimaryColor),
                  pw.SizedBox(width: 7),
                  amountCard('Expenses', totalSpent, expenseColor),
                  pw.SizedBox(width: 7),
                  amountCard('Income', totalIncome, incomeColor),
                  pw.SizedBox(width: 7),
                  amountCard('Remaining', remaining, incomeColor),
                ],
              ),
              if (categories.isNotEmpty) ...[
                pw.SizedBox(height: 18),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'Spending by category',
                      style: pw.TextStyle(
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                        color: pageText,
                      ),
                    ),
                    pw.Text(
                      '${categories.length} categories',
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
                              '${shortTitle(category.key, max: 18)}  Rs. ${category.value.toStringAsFixed(0)}',
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
                    'Transaction History',
                    style: pw.TextStyle(
                      fontSize: 15,
                      fontWeight: pw.FontWeight.bold,
                      color: pageText,
                    ),
                  ),
                  pw.Text(
                    '${expenses.length} entries',
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
                    'No ledger transactions available.',
                    style: const pw.TextStyle(fontSize: 9, color: mutedText),
                  ),
                )
              else
                transactionTable(),
              if (udharEntries.isNotEmpty) ...[
                pw.SizedBox(height: 22),
                pw.Container(
                  padding: const pw.EdgeInsets.fromLTRB(11, 10, 11, 10),
                  decoration: pw.BoxDecoration(
                    color: const PdfColor.fromInt(0xFFFFFBEB),
                    borderRadius:
                        const pw.BorderRadius.all(pw.Radius.circular(5)),
                    border: const pw.Border(
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
                              'Udhar / Debt',
                              style: pw.TextStyle(
                                fontSize: 14,
                                fontWeight: pw.FontWeight.bold,
                                color: pageText,
                              ),
                            ),
                            pw.SizedBox(height: 2),
                            pw.Text(
                              'Tracked separately from normal spending so debt movements are not counted twice.',
                              style: const pw.TextStyle(
                                fontSize: 8,
                                color: mutedText,
                              ),
                            ),
                          ],
                        ),
                      ),
                      pw.Text(
                        '${activeUdhar.length} active',
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
                  'Generated securely via Likhlo Expense Manager.',
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
        name: 'Likhlo_Statement_$dateStr.pdf',
      );
    } catch (error) {
      debugPrint('PDF export failed: $error');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not export the report. Please try again.'),
        ),
      );
    }
  }

}
