import '../l10n/app_strings.dart';
import 'package:flutter/material.dart';

import '../features/budget_predictor/budget_planner_screen.dart';
import '../screens/about_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/stats_screen.dart';
import '../screens/trash_screen.dart';
import '../widgets/app_drawer.dart';

/// Top-level destinations owned by the application shell.
///
/// Main/Udhar remain secondary ledger tabs inside the dashboard and are not
/// represented here.
enum AppSection {
  dashboard('Dashboard'),
  budget('Monthly Plan'),
  stats('Stats'),
  settings('Settings'),
  trash('Trash'),
  about('About');

  const AppSection(this.label);

  final String label;

  static AppSection? fromLabel(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'budget planner') return AppSection.budget;
    for (final section in AppSection.values) {
      if (section.label.toLowerCase() == normalized) return section;
    }
    return null;
  }
}

AppSection? systemBackDestination(AppSection currentSection) {
  return currentSection == AppSection.dashboard ? null : AppSection.dashboard;
}

/// Owns the global Scaffold, drawer and top-level section chrome.
///
/// Feature state and business logic deliberately stay outside this widget.
/// This keeps the AppShell a structural navigation boundary only.
class AppShell extends StatelessWidget {
  final AppSection currentSection;
  final ValueChanged<AppSection> onSectionChanged;
  final PreferredSizeWidget? dashboardAppBar;
  final Widget? dashboardBody;
  final Widget? dashboardFloatingActionButton;

  const AppShell({
    super.key,
    required this.currentSection,
    required this.onSectionChanged,
    this.dashboardAppBar,
    this.dashboardBody,
    this.dashboardFloatingActionButton,
  });

  bool get _isDashboard => currentSection == AppSection.dashboard;

  Widget _sectionBody() {
    switch (currentSection) {
      case AppSection.budget:
        return const BudgetPlannerScreen();
      case AppSection.stats:
        return const StatsScreen();
      case AppSection.settings:
        return const SettingsScreen();
      case AppSection.trash:
        return const TrashScreen();
      case AppSection.about:
        return const AboutScreen();
      case AppSection.dashboard:
        return dashboardBody ?? const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    AppStrings.of(context);
    return PopScope(
      canPop: systemBackDestination(currentSection) == null,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        final destination = systemBackDestination(currentSection);
        if (destination != null) onSectionChanged(destination);
      },
      child: Scaffold(
        drawer: AppDrawer(
          currentView: currentSection.label,
          onViewChanged: (view) {
            final section = AppSection.fromLabel(view);
            if (section != null) onSectionChanged(section);
          },
        ),
        appBar: _isDashboard
            ? dashboardAppBar
            : AppBar(
                elevation: 0,
                scrolledUnderElevation: 0,
                title: Text(
                  currentSection.label,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                  ),
                ),
                centerTitle: true,
                leading: IconButton(
                  tooltip: AppStrings.current.text('back_to_dashboard_b3963d'),
                  icon: const Icon(Icons.arrow_back_rounded, size: 24),
                  onPressed: () => onSectionChanged(AppSection.dashboard),
                ),
              ),
        body: _isDashboard ? dashboardBody : _sectionBody(),
        floatingActionButtonLocation:
            _isDashboard ? FloatingActionButtonLocation.centerFloat : null,
        floatingActionButton:
            _isDashboard ? dashboardFloatingActionButton : null,
      ),
    );
  }
}
