import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:hive/hive.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../providers/settings_provider.dart';
import '../providers/category_provider.dart';
import '../providers/expense_provider.dart';
import '../services/notification_service.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String? _ringtoneName;
  final List<IconData> _profileIcons = const [
    Icons.person_rounded, Icons.school_rounded, Icons.work_rounded, Icons.face_rounded, Icons.emoji_emotions_rounded, Icons.sports_esports_rounded
  ];

  // 🎨 DESIGNER'S CHOICE: Expanded Premium Color Palette
  final Map<String, Color> _premiumThemes = {
    // Classics
    "Royal Blue": const Color(0xFF2563EB),    // Trust & Professionalism (Default)
    "Emerald": const Color(0xFF059669),       // Growth & Money
    "Sunset Orange": const Color(0xFFEA580C), // Energy & Warmth

    // Vibrant
    "Berry Fusion": const Color(0xFFBE185D),  // Creativity & Passion
    "Deep Violet": const Color(0xFF7C3AED),   // Luxury & Wisdom
    "Ocean Teal": const Color(0xFF0D9488),    // Calm & Balance

    // ✨ NEW DARK THEMES
    "Midnight Slate": const Color(0xFF475569), // Minimalist & Sleek
    "Crimson Ruby": const Color(0xFFE11D48),   // Bold & Exclusive
    "Electric Cyan": const Color(0xFF0891B2),  // Modern & Tech-focused
    "Golden Amber": const Color(0xFFCA8A04),   // Rich & High Contrast
  };

  @override
  void initState() { super.initState(); _loadRingtone(); }

  void _loadRingtone() { final path = Hive.box('preferences').get('custom_ringtone'); if (path != null) setState(() => _ringtoneName = path.split('/').last); }

  Future<void> _pickRingtone() async {
    if (await Permission.audio.request().isGranted || await Permission.storage.request().isGranted) {
      FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.audio);
      if (result != null && result.files.single.path != null) {
        String path = result.files.single.path!;
        await Hive.box('preferences').put('custom_ringtone', path);
        setState(() => _ringtoneName = result.files.single.name);
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ Ringtone updated!")));
      }
    }
  }

  Future<void> _generatePdf() async {
    final expenses = ref.read(expenseProvider).allExpenses;
    final pdf = pw.Document();
    pdf.addPage(pw.Page(build: (pw.Context context) => pw.Column(children: [pw.Header(level: 0, child: pw.Text("Expense Report")), pw.Table.fromTextArray(context: context, data: <List<String>>[<String>['Date', 'Title', 'Amt'], ...expenses.map((e) => [e.date.toString().substring(0, 10), e.title, e.amount.toString()])])])));
    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final categories = ref.watch(categoryProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text("Profile", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 10),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: Colors.grey.withOpacity(0.1))),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => _pickIcon(context, notifier),
                    child: CircleAvatar(radius: 32, backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1), child: Icon(_profileIcons[settings.profileIconIndex], size: 32, color: Theme.of(context).primaryColor)),
                  ),
                  const SizedBox(width: 15),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(settings.userName.isEmpty ? "Set Name" : settings.userName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), Text(settings.userProfession.isEmpty ? "Set Profession" : settings.userProfession, style: const TextStyle(color: Colors.grey))])),
                  IconButton(icon: const Icon(Icons.edit_rounded, color: Colors.blue), onPressed: () => _startProfileWizard(context, notifier, settings.userName, settings.userProfession))
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),
          const Text("Theme Appearance", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 15),

          // 🎨 Premium Theme Selector
          Wrap(
            spacing: 16,
            runSpacing: 16,
            alignment: WrapAlignment.center,
            children: _premiumThemes.entries.map((entry) {
              return _themeBubble(context, notifier, entry.value, entry.key, settings.profileColorValue);
            }).toList(),
          ),

          const Divider(height: 40),
          const Text("Preferences", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 13)),

          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.notifications_active_rounded, color: Colors.orange)),
            title: const Text("Notification Sound", style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(_ringtoneName ?? "Default System"),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                    onPressed: () => NotificationService().showInstantNotification("Test", "This is how your ringtone sounds!"),
                    child: const Text("TEST")
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
            onTap: _pickRingtone,
          ),

          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.analytics_rounded, color: Colors.red)),
            title: const Text("Export Monthly Report", style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text("Download PDF"),
            onTap: _generatePdf,
          ),

          const Divider(height: 30),
          const Text("Categories", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 13)),
          ...categories.map((c) => ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: const Icon(Icons.label_important_outline_rounded, size: 20),
            title: Text(c, style: const TextStyle(fontWeight: FontWeight.w500)),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [IconButton(icon: const Icon(Icons.edit_rounded, size: 18), onPressed: () => _editCategory(context, ref, c)), IconButton(icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red), onPressed: () => ref.read(categoryProvider.notifier).deleteCategory(c))]),
          )),
          TextButton.icon(icon: const Icon(Icons.add_rounded), label: const Text("Add New Category"), onPressed: () => _addCategory(context, ref)),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  // 🎨 Beautiful Color Bubble with Selection State
  Widget _themeBubble(BuildContext context, SettingsNotifier notifier, Color color, String name, int currentColorValue) {
    bool isSelected = color.value == currentColorValue;
    return GestureDetector(
      onTap: () {
        notifier.updateThemeColor(color.value);
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.palette_rounded, color: Colors.white),
                  const SizedBox(width: 10),
                  Text("Theme applied: $name", style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              backgroundColor: color,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              duration: const Duration(seconds: 1),
            )
        );
      },
      child: Column(
        children: [
          Container(
            width: 45,
            height: 45,
            decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                    color: isSelected ? Theme.of(context).iconTheme.color! : Colors.transparent,
                    width: isSelected ? 3 : 0
                ),
                boxShadow: [
                  if (isSelected) BoxShadow(color: color.withOpacity(0.4), blurRadius: 10, spreadRadius: 2)
                ]
            ),
            child: isSelected ? const Icon(Icons.check, color: Colors.white, size: 20) : null,
          ),
          const SizedBox(height: 6),
          Text(name, style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
        ],
      ),
    );
  }

  void _startProfileWizard(BuildContext context, SettingsNotifier notifier, String n, String p) { final nc=TextEditingController(text:n); showDialog(context: context, builder: (ctx)=>AlertDialog(title: const Text("Name"), content: TextField(controller: nc), actions: [TextButton(onPressed: (){Navigator.pop(ctx); _askProfession(context, notifier, nc.text, p);}, child: const Text("Next"))])); }
  void _askProfession(BuildContext context, SettingsNotifier notifier, String n, String p) { final pc=TextEditingController(text:p); showDialog(context: context, builder: (ctx)=>AlertDialog(title: const Text("Profession"), content: TextField(controller: pc), actions: [TextButton(onPressed: (){notifier.updateProfile(n, pc.text); Navigator.pop(ctx);}, child: const Text("Save"))])); }
  void _pickIcon(BuildContext context, SettingsNotifier notifier) { showDialog(context: context, builder: (ctx)=>AlertDialog(content: Wrap(spacing:15, runSpacing:15, children: List.generate(_profileIcons.length, (i)=>GestureDetector(onTap:(){notifier.updateProfileIcon(i); Navigator.pop(ctx);}, child: CircleAvatar(child: Icon(_profileIcons[i]))))))); }
  void _editCategory(BuildContext context, WidgetRef ref, String old) { final c=TextEditingController(text:old); showDialog(context: context, builder: (ctx)=>AlertDialog(title: const Text("Edit"), content: TextField(controller: c), actions: [TextButton(onPressed: (){ref.read(categoryProvider.notifier).editCategory(old, c.text); Navigator.pop(ctx);}, child: const Text("Save"))])); }
  void _addCategory(BuildContext context, WidgetRef ref) { final c=TextEditingController(); showDialog(context: context, builder: (ctx)=>AlertDialog(title: const Text("New"), content: TextField(controller: c), actions: [TextButton(onPressed: (){ref.read(categoryProvider.notifier).addCategory(c.text); Navigator.pop(ctx);}, child: const Text("Add"))])); }
}