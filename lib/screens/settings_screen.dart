import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';

import '../providers/settings_provider.dart';
import '../providers/expense_provider.dart';
import '../services/notification_service.dart';

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
        title: const Text("Edit Profile", style: TextStyle(fontWeight: FontWeight.w800)),
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
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
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
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
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
                  child: const Text("Cancel", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  onPressed: () {
                    ref.read(settingsProvider.notifier).updateUserName(nameCtrl.text);
                    ref.read(settingsProvider.notifier).updateUserProfession(profCtrl.text);
                    Navigator.pop(ctx);
                  },
                  child: const Text("Save", style: TextStyle(fontWeight: FontWeight.bold)),
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
        title: const Text("Theme Color", style: TextStyle(fontWeight: FontWeight.w800)),
        content: Wrap(
          spacing: 16,
          runSpacing: 16,
          alignment: WrapAlignment.center,
          children: colors.map((colorValue) {
            final isSelected = colorValue == activeColor;
            return GestureDetector(
              onTap: () {
                ref.read(settingsProvider.notifier).updateProfileColor(colorValue);
                Navigator.pop(ctx);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 55,
                height: 55,
                decoration: BoxDecoration(
                  color: Color(colorValue),
                  shape: BoxShape.circle,
                  border: isSelected ? Border.all(color: Colors.white, width: 3) : null,
                  boxShadow: [
                    BoxShadow(color: Color(colorValue).withValues(alpha: 0.4), blurRadius: isSelected ? 12 : 6, offset: const Offset(0, 4))
                  ],
                ),
                child: isSelected ? const Icon(Icons.check_rounded, color: Colors.white, size: 28) : null,
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

    final String displayName = (settings.userName.isNotEmpty) ? settings.userName : "Set up profile";
    final String displayProf = (settings.userProfession.isNotEmpty) ? settings.userProfession : "Tap to add details";

    // Read Hive states for Notification toggles
    final bool persistentEnabled = _prefBox.get('persistent_bar_enabled', defaultValue: true);
    final bool remindersEnabled = _prefBox.get('daily_reminder_enabled', defaultValue: true);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        children: [
          const Text("Preferences", style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
          const SizedBox(height: 24),

          // 1. 🌟 PREMIUM PROFILE HERO CARD
          GestureDetector(
            onTap: () => _showEditProfileDialog(settings.userName, settings.userProfession),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [primaryColor, primaryColor.withValues(alpha: 0.75)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(32),
                boxShadow: [BoxShadow(color: primaryColor.withValues(alpha: 0.35), blurRadius: 20, offset: const Offset(0, 10))],
              ),
              child: Row(
                children: [
                  Container(
                    width: 65, height: 65,
                    decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10)]),
                    child: Center(
                      child: Text(
                        displayName.isNotEmpty ? displayName[0].toUpperCase() : "?",
                        style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: primaryColor),
                      ),
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(displayName, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 4),
                        Text(displayProf, style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 14, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle),
                    child: const Icon(Icons.edit_rounded, color: Colors.white, size: 20),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),

          // 2. 🎨 APPEARANCE
          const Padding(
            padding: EdgeInsets.only(left: 8, bottom: 12),
            child: Text("Appearance", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey)),
          ),
          _buildSettingsGroup(
            isDark: isDark,
            children: [
              _buildSwitchTile(
                title: "Dark Mode",
                subtitle: "Sleek theme for night use",
                icon: isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                iconColor: Colors.indigo,
                value: settings.themeMode == 'dark',
                onChanged: (val) => ref.read(settingsProvider.notifier).updateThemeMode(val ? 'dark' : 'light'),
              ),
              _buildDivider(),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                leading: _buildIconBox(Icons.color_lens_rounded, primaryColor),
                title: const Text("Theme Color", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                subtitle: const Text("Customize app accent", style: TextStyle(fontSize: 13, color: Colors.grey)),
                trailing: Container(
                  width: 30, height: 30,
                  decoration: BoxDecoration(color: primaryColor, shape: BoxShape.circle, border: Border.all(color: isDark ? Colors.white24 : Colors.black12, width: 2)),
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
                        _buildIconBox(Icons.brightness_medium_rounded, Colors.orange),
                        const SizedBox(width: 16),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("Screen Dimmer", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                              Text("Dims the entire app interface", style: TextStyle(fontSize: 13, color: Colors.grey)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(Icons.brightness_7_rounded, size: 18, color: Colors.grey.shade400),
                        Expanded(
                          child: Slider(
                            value: settings.brightnessLevel,
                            min: 0.0,
                            max: 0.75, // Prevents pitch black screen
                            activeColor: primaryColor,
                            inactiveColor: primaryColor.withValues(alpha: 0.2),
                            onChanged: (val) => ref.read(settingsProvider.notifier).updateBrightness(val),
                          ),
                        ),
                        Icon(Icons.brightness_3_rounded, size: 18, color: Colors.grey.shade600),
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
            child: Text("Notifications & Alerts", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey)),
          ),
          _buildSettingsGroup(
            isDark: isDark,
            children: [
              _buildSwitchTile(
                title: "Persistent Quick-Log",
                subtitle: "Keep a live budget widget in status bar",
                icon: Icons.space_dashboard_rounded,
                iconColor: Colors.teal,
                value: persistentEnabled,
                onChanged: (val) {
                  setState(() => _prefBox.put('persistent_bar_enabled', val));
                  if (!val) {
                    NotificationService().cancelNotification(NotificationService.persistentBarId);
                  }
                  // Will auto-rebuild on home screen next load
                },
              ),
              _buildDivider(),
              _buildSwitchTile(
                title: "Smart Entry Reminders",
                subtitle: "Receive daily nudges to log your expenses",
                icon: Icons.notifications_active_rounded,
                iconColor: Colors.amber.shade600,
                value: remindersEnabled,
                onChanged: (val) {
                  setState(() => _prefBox.put('daily_reminder_enabled', val));
                  if (val) {
                    NotificationService().scheduleSmartEntryReminders();
                  } else {
                    NotificationService().cancelNotification(NotificationService.middayReminderId);
                    NotificationService().cancelNotification(NotificationService.eveningReminderId);
                    NotificationService().cancelNotification(NotificationService.weekendReviewId);
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 32),

          // 4. 📂 EXPORT REPORT
          const Padding(
            padding: EdgeInsets.only(left: 8, bottom: 12),
            child: Text("Data & Reports", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey)),
          ),
          _buildSettingsGroup(
            isDark: isDark,
            children: [
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                leading: _buildIconBox(Icons.picture_as_pdf_rounded, Colors.red.shade400),
                title: const Text("Export Monthly PDF", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                subtitle: const Text("Generate a professional statement", style: TextStyle(fontSize: 13, color: Colors.grey)),
                trailing: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                  child: Icon(Icons.download_rounded, size: 20, color: Colors.red.shade400),
                ),
                onTap: () => _generatePdf(context, ref, primaryColor),
              ),
            ],
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  // --- UI HELPERS ---
  Widget _buildSettingsGroup({required List<Widget> children, required bool isDark}) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.withValues(alpha: 0.1)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: Column(children: children),
    );
  }

  Widget _buildDivider() {
    return Divider(height: 1, thickness: 1, color: Colors.grey.withValues(alpha: 0.1), indent: 70, endIndent: 20);
  }

  Widget _buildIconBox(IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
      child: Icon(icon, color: color, size: 22),
    );
  }

  Widget _buildSwitchTile({required String title, required String subtitle, required IconData icon, required Color iconColor, required bool value, required Function(bool) onChanged}) {
    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      secondary: _buildIconBox(icon, iconColor),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 13, color: Colors.grey)),
      activeThumbColor: Color(ref.read(settingsProvider).profileColorValue),
      value: value,
      onChanged: onChanged,
    );
  }

  // --- PROFESSIONAL PDF GENERATOR ---
  Future<void> _generatePdf(BuildContext context, WidgetRef ref, Color primaryColor) async {
    final expenses = ref.read(expenseProvider).allExpenses;
    final settings = ref.read(settingsProvider);
    final pdf = pw.Document();

    final totalSpent = expenses.fold(0.0, (sum, item) => sum + item.amount);
    final dateStr = DateFormat.yMMMM().format(DateTime.now());

    final pdfPrimaryColor = PdfColor.fromInt(primaryColor.toARGB32());

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text("LIKHLO", style: pw.TextStyle(fontSize: 28, fontWeight: pw.FontWeight.bold, color: pdfPrimaryColor)),
                          pw.SizedBox(height: 4),
                          pw.Text("Financial Statement", style: const pw.TextStyle(fontSize: 14, color: PdfColors.grey700)),
                        ]
                    ),
                    pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          pw.Text(settings.userName.isNotEmpty ? settings.userName : "Student Account", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
                          pw.Text(dateStr, style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey600)),
                        ]
                    )
                  ]
              ),
              pw.SizedBox(height: 30),
              pw.Container(
                  padding: const pw.EdgeInsets.all(16),
                  decoration: pw.BoxDecoration(
                      color: PdfColors.grey100,
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12)),
                      border: pw.Border.all(color: PdfColors.grey300)
                  ),
                  child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text("Total Outflow:", style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                        pw.Text("Rs. ${totalSpent.toStringAsFixed(0)}", style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: pdfPrimaryColor)),
                      ]
                  )
              ),
              pw.SizedBox(height: 30),
              pw.Text("Transaction History", style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 10),
              pw.TableHelper.fromTextArray(
                context: context,
                border: const pw.TableBorder(
                  horizontalInside: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
                  bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
                ),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                headerDecoration: pw.BoxDecoration(color: pdfPrimaryColor),
                rowDecoration: const pw.BoxDecoration(color: PdfColors.white),
                cellPadding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                headers: ['Date', 'Title', 'Category', 'Amount (Rs)'],
                data: expenses.map((e) => [
                  DateFormat('dd MMM yyyy').format(e.date),
                  e.title,
                  e.category,
                  e.amount.toStringAsFixed(0)
                ]).toList(),
              ),
              pw.Spacer(),
              pw.Divider(color: PdfColors.grey400),
              pw.SizedBox(height: 8),
              pw.Center(
                  child: pw.Text("Generated securely via Likhlo Expense Manager.", style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600))
              )
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
        onLayout: (format) async => pdf.save(),
        name: 'Likhlo_Statement_$dateStr.pdf'
    );
  }
}
