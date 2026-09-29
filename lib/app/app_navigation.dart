import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_shell.dart';

/// Global navigation state for top-level AppShell destinations.
///
/// Main/Udhar remain feature-level navigation inside the dashboard.
class AppNavigationController extends Notifier<AppSection> {
  @override
  AppSection build() => AppSection.dashboard;

  void open(AppSection section) {
    if (state == section) return;
    state = section;
  }

  void openDashboard() => open(AppSection.dashboard);
}

final appNavigationProvider =
    NotifierProvider<AppNavigationController, AppSection>(
  AppNavigationController.new,
);
