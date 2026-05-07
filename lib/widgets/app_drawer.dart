import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/settings_provider.dart';

class AppDrawer extends ConsumerWidget {
  final String currentView;
  final Function(String) onViewChanged;

  const AppDrawer({super.key, required this.currentView, required this.onViewChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final primaryColor = Theme.of(context).primaryColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // ✅ SAFE FALLBACKS
    final String displayName = (settings.userName.isNotEmpty) ? settings.userName : "Welcome!";
    final String displayProf = (settings.userProfession.isNotEmpty) ? settings.userProfession : "Student";

    return Drawer(
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.only(top: 50, bottom: 20, left: 20, right: 20),
            decoration: BoxDecoration(gradient: LinearGradient(colors: isDark ? [const Color(0xFF1E293B), const Color(0xFF0F172A)] : [primaryColor, primaryColor.withOpacity(0.8)], begin: Alignment.topLeft, end: Alignment.bottomRight)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CircleAvatar(radius: 35, backgroundColor: Colors.white, child: Icon(Icons.person_rounded, size: 40, color: primaryColor)),
              const SizedBox(height: 15),
              Text(displayName, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              Text(displayProf, style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14)),
            ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView(padding: const EdgeInsets.symmetric(horizontal: 10), children: [
              _buildDrawerItem(context, 'Dashboard', Icons.dashboard_rounded),
              _buildDrawerItem(context, 'Tasks', Icons.check_circle_outline_rounded),
              _buildDrawerItem(context, 'Tools', Icons.calculate_rounded),
              _buildDrawerItem(context, 'Udhaar', Icons.handshake_rounded),
              const Divider(height: 30, thickness: 0.5),
              _buildDrawerItem(context, 'Stats', Icons.bar_chart_rounded),
              _buildDrawerItem(context, 'Settings', Icons.settings_rounded),
              _buildDrawerItem(context, 'About', Icons.info_outline_rounded),
            ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            color: isDark ? Colors.black26 : Colors.grey.withOpacity(0.05),
            child: SwitchListTile(
              title: const Text("Dark Mode", style: TextStyle(fontWeight: FontWeight.w600)),
              secondary: Icon(isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded),
              activeColor: primaryColor,
              value: settings.themeMode == 'dark',
              onChanged: (val) { ref.read(settingsProvider.notifier).updateThemeMode(val ? 'dark' : 'light'); },
            ),
          )
        ],
      ),
    );
  }

  Widget _buildDrawerItem(BuildContext context, String title, IconData icon) {
    bool isSelected = currentView == title;
    return Container(
      margin: const EdgeInsets.only(bottom: 5),
      child: ListTile(
        selected: isSelected, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        leading: Icon(icon), title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        onTap: () { Navigator.pop(context); onViewChanged(title); },
      ),
    );
  }
}