import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../providers/settings_provider.dart';
import '../providers/expense_provider.dart'; // Needed for PDF data
import '../utils/app_colors.dart';

class ProfileTab extends ConsumerWidget {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text("Profile & Settings")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Profile Header
          const Center(
            child: CircleAvatar(radius: 40, backgroundColor: AppColors.primaryTeal, child: Icon(Icons.person, size: 40, color: Colors.white)),
          ),
          const SizedBox(height: 10),
          Center(child: Text(settings.userName ?? "Student", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
          const SizedBox(height: 30),

          // 1. Theme Settings
          const Text("Appearance", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
          SwitchListTile(
            title: const Text("Dark Mode"),
            value: settings.themeMode == 'dark',
            onChanged: (val) {
              ref.read(settingsProvider.notifier).updateThemeMode(val ? 'dark' : 'light');
            },
          ),

          // 2. Brightness Dimmer (Slider)
          const Text("Screen Dimmer (Night Mode)", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
          Slider(
            value: settings.brightnessLevel,
            min: 0.0,
            max: 0.7, // Don't let it go fully black
            activeColor: Colors.black,
            onChanged: (val) {
              ref.read(settingsProvider.notifier).updateBrightness(val);
            },
          ),
          const Text("Move slider to dim screen overlay", style: TextStyle(fontSize: 12, color: Colors.grey), textAlign: TextAlign.center),

          const Divider(height: 40),

          // 3. Export Data
          ListTile(
            leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
            title: const Text("Export Monthly Report"),
            subtitle: const Text("Generate PDF of all expenses"),
            onTap: () => _generatePdf(context, ref),
          ),

          // 4. About
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text("About Likhlo"),
            subtitle: Text("Version 2.0.0 (Pro Upgrade)"),
          ),
        ],
      ),
    );
  }

  Future<void> _generatePdf(BuildContext context, WidgetRef ref) async {
    final expenses = ref.read(expenseProvider).allExpenses;
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        build: (pw.Context context) {
          return pw.Column(
            children: [
              pw.Header(level: 0, child: pw.Text("Likhlo Expense Report", style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold))),
              pw.SizedBox(height: 20),
              pw.Table.fromTextArray(
                context: context,
                data: <List<String>>[
                  <String>['Date', 'Title', 'Category', 'Amount'],
                  ...expenses.map((e) => [e.date.toString().substring(0, 10), e.title, e.category, e.amount.toStringAsFixed(0)]),
                ],
              ),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }
}