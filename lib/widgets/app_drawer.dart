import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/settings_provider.dart';

class AppDrawer extends ConsumerWidget {
  final String currentView;
  final Function(String) onViewChanged;

  const AppDrawer({
    super.key,
    required this.currentView,
    required this.onViewChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final primaryColor = Color(settings.profileColorValue);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    final displayName =
        settings.userName.isNotEmpty ? settings.userName : 'Welcome!';
    final displayProfession = settings.userProfession.isNotEmpty
        ? settings.userProfession
        : 'Student';

    return SizedBox(
      width: (MediaQuery.sizeOf(context).width * 0.84)
          .clamp(0.0, 328.0)
          .toDouble(),
      child: Drawer(
        backgroundColor: Colors.transparent,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            topRight: Radius.circular(28),
            bottomRight: Radius.circular(28),
          ),
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.only(
            topRight: Radius.circular(28),
            bottomRight: Radius.circular(28),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colorScheme.surface.withValues(
                alpha: isDark ? 0.97 : 0.95,
              ),
              border: Border(
                right: BorderSide(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.10)
                      : colorScheme.outlineVariant.withValues(alpha: 0.55),
                ),
              ),
            ),
            child: SafeArea(
              child: Column(
                  children: [
                    _ProfileHeader(
                      displayName: displayName,
                      displayProfession: displayProfession,
                      primaryColor: primaryColor,
                      isDark: isDark,
                    ),
                    const SizedBox(height: 14),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Explore',
                          style: TextStyle(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.7,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 7),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        children: [
                          _buildDrawerItem(
                            context,
                            'Monthly Plan',
                            Icons.savings_outlined,
                            primaryColor,
                            isDark,
                          ),
                          _buildDrawerItem(
                            context,
                            'Stats',
                            Icons.insights_rounded,
                            primaryColor,
                            isDark,
                          ),
                          _buildDrawerItem(
                            context,
                            'Settings',
                            Icons.settings_rounded,
                            primaryColor,
                            isDark,
                          ),
                          _buildDrawerItem(
                            context,
                            'Trash',
                            Icons.delete_outline_rounded,
                            primaryColor,
                            isDark,
                          ),
                          _buildDrawerItem(
                            context,
                            'About',
                            Icons.info_outline_rounded,
                            primaryColor,
                            isDark,
                          ),
                        ],
                      ),
                    ),
                    _buildThemeControl(
                      context,
                      ref,
                      settings.themeMode == 'dark',
                      primaryColor,
                      isDark,
                    ),
                  ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDrawerItem(
    BuildContext context,
    String title,
    IconData icon,
    Color primaryColor,
    bool isDark,
  ) {
    final isSelected = currentView == title;
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Material(
        color: isSelected
            ? primaryColor.withValues(alpha: isDark ? 0.20 : 0.10)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(15),
        child: InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: () {
            Navigator.pop(context);
            Future<void>.delayed(const Duration(milliseconds: 180), () {
              onViewChanged(title);
            });
          },
          child: SizedBox(
            height: 52,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? primaryColor.withValues(
                              alpha: isDark ? 0.22 : 0.12,
                            )
                          : colorScheme.surfaceContainerHighest.withValues(
                              alpha: isDark ? 0.46 : 0.62,
                            ),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(
                      icon,
                      color: isSelected
                          ? primaryColor
                          : colorScheme.onSurfaceVariant,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
                        height: 1.1,
                        fontWeight:
                            isSelected ? FontWeight.w800 : FontWeight.w600,
                        color: isSelected
                            ? primaryColor
                            : colorScheme.onSurface,
                      ),
                    ),
                  ),
                  if (isSelected) ...[
                    const SizedBox(width: 8),
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: primaryColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildThemeControl(
    BuildContext context,
    WidgetRef ref,
    bool isDarkMode,
    Color primaryColor,
    bool isDark,
  ) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(
          alpha: isDark ? 0.42 : 0.58,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.07)
              : colorScheme.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: isDark ? 0.19 : 0.10),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              isDarkMode
                  ? Icons.dark_mode_rounded
                  : Icons.light_mode_rounded,
              color: primaryColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Dark Mode',
              maxLines: 1,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Switch(
            value: isDarkMode,
            activeThumbColor: primaryColor,
            onChanged: (value) {
              final notifier = ref.read(settingsProvider.notifier);
              Navigator.pop(context);
              Future<void>.delayed(
                const Duration(milliseconds: 180),
                () {
                  notifier.updateThemeMode(value ? 'dark' : 'light');
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final String displayName;
  final String displayProfession;
  final Color primaryColor;
  final bool isDark;

  const _ProfileHeader({
    required this.displayName,
    required this.displayProfession,
    required this.primaryColor,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: primaryColor.withValues(alpha: isDark ? 0.15 : 0.09),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: primaryColor.withValues(alpha: isDark ? 0.20 : 0.12),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: isDark ? 0.20 : 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.person_rounded,
              size: 27,
              color: primaryColor,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 16,
                    height: 1.15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  displayProfession,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
