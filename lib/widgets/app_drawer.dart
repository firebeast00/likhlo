import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/settings_provider.dart';

class AppDrawer extends ConsumerWidget {
  final String currentView;
  final Function(String) onViewChanged;

  const AppDrawer(
      {super.key, required this.currentView, required this.onViewChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final primaryColor =
        Color(settings.profileColorValue); // 🛡️ Guaranteed theme color support
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // ✅ SAFE FALLBACKS
    final String displayName =
        (settings.userName.isNotEmpty) ? settings.userName : "Welcome!";
    final String displayProf = (settings.userProfession.isNotEmpty)
        ? settings.userProfession
        : "Student";

    return Drawer(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        children: [
          // 🌟 Elegant Profile Header with Gradient
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.only(top: 60, bottom: 24, left: 24, right: 24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [primaryColor, primaryColor.withValues(alpha: 0.75)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: primaryColor.withValues(alpha: isDark ? 0.3 : 0.35),
                  blurRadius: 15,
                  offset: const Offset(0, 8),
                )
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: CircleAvatar(
                    radius: 30,
                    backgroundColor: primaryColor.withValues(alpha: 0.1),
                    child: Icon(Icons.person_rounded,
                        size: 36, color: primaryColor),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        displayProf,
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 13,
                            fontWeight: FontWeight.w500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Navigation Items List
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              children: [
                _buildDrawerItem(context, 'Workspaces', Icons.workspaces_outline,
                    primaryColor, isDark),
                _buildDrawerItem(context, 'Settings', Icons.settings_rounded,
                    primaryColor, isDark),
                _buildDrawerItem(context, 'Trash', Icons.delete_outline_rounded,
                    primaryColor, isDark),
                _buildDrawerItem(context, 'About', Icons.info_outline_rounded,
                    primaryColor, isDark),
              ],
            ),
          ),

          // 🌙 Bottom Dark Mode Toggle Container
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color:
                  isDark ? Colors.black26 : Colors.grey.withValues(alpha: 0.04),
              border: Border(
                  top: BorderSide(color: Colors.grey.withValues(alpha: 0.1))),
            ),
            child: SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              title: const Text("Dark Mode",
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              secondary: Icon(
                  isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                  color: primaryColor),
              activeThumbColor: primaryColor,
              value: settings.themeMode == 'dark',
              onChanged: (val) {
                final notifier = ref.read(settingsProvider.notifier);
                Navigator.pop(context);
                Future<void>.delayed(const Duration(milliseconds: 180), () {
                  notifier.updateThemeMode(val ? 'dark' : 'light');
                });
              },
            ),
          )
        ],
      ),
    );
  }

  Widget _buildDrawerItem(BuildContext context, String title, IconData icon,
      Color primaryColor, bool isDark) {
    bool isSelected = currentView == title;
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: isSelected
            ? primaryColor.withValues(alpha: isDark ? 0.25 : 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        leading: Icon(
          icon,
          color: isSelected ? primaryColor : Colors.grey.shade500,
          size: 22,
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
            color: isSelected
                ? primaryColor
                : (isDark ? Colors.white70 : Colors.black87),
            fontSize: 14,
          ),
        ),
        trailing: isSelected
            ? Container(
                width: 6,
                height: 6,
                decoration:
                    BoxDecoration(color: primaryColor, shape: BoxShape.circle))
            : null,
        onTap: () {
          Navigator.pop(context);
          Future<void>.delayed(const Duration(milliseconds: 180), () {
            onViewChanged(title);
          });
        },
      ),
    );
  }
}
