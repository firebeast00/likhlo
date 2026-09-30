import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:student_expense_manager/app/app_navigation.dart';
import 'package:student_expense_manager/app/app_shell.dart';

void main() {
  test('AppSection resolves supported drawer labels', () {
    expect(AppSection.fromLabel('Monthly Plan'), AppSection.budget);
    expect(AppSection.fromLabel('Budget Planner'), AppSection.budget);
    expect(AppSection.fromLabel('Stats'), AppSection.stats);
    expect(AppSection.fromLabel('settings'), AppSection.settings);
    expect(AppSection.fromLabel('Trash'), AppSection.trash);
    expect(AppSection.fromLabel('About'), AppSection.about);
    expect(AppSection.fromLabel('unknown'), isNull);
  });

  test('AppNavigationController changes top-level shell section', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(appNavigationProvider), AppSection.dashboard);

    container.read(appNavigationProvider.notifier).open(AppSection.stats);
    expect(container.read(appNavigationProvider), AppSection.stats);

    container.read(appNavigationProvider.notifier).openDashboard();
    expect(container.read(appNavigationProvider), AppSection.dashboard);
  });

  testWidgets('system back returns top-level sections to Dashboard first',
      (tester) async {
    var section = AppSection.settings;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            return AppShell(
              currentSection: section,
              onSectionChanged: (next) {
                setState(() => section = next);
              },
            );
          },
        ),
      ),
    );

    expect(find.text('Settings'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(section, AppSection.dashboard);
  });
}
