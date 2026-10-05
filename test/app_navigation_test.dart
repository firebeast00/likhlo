import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:student_expense_manager/app/app_action.dart';
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

  test('system back policy returns secondary sections to Dashboard first', () {
    for (final section in AppSection.values) {
      if (section == AppSection.dashboard) {
        expect(systemBackDestination(section), isNull);
      } else {
        expect(systemBackDestination(section), AppSection.dashboard);
      }
    }
  });

  test('app action channel delivers and consumes supported requests', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(appActionProvider), isNull);

    for (final action in AppActionType.values) {
      container.read(appActionProvider.notifier).request(action);
      final request = container.read(appActionProvider);
      expect(request, isNotNull);
      expect(request!.action, action);

      container.read(appActionProvider.notifier).consume(request.id);
      expect(container.read(appActionProvider), isNull);
    }
  });

  test('PDF action channel preserves a normalized requested month', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(appActionProvider.notifier).request(
      AppActionType.openMonthlyPdf,
      month: DateTime(2026, 9, 18, 22, 45),
    );
    final request = container.read(appActionProvider);

    expect(request?.action, AppActionType.openMonthlyPdf);
    expect(request?.month, DateTime(2026, 9));
  });

  test('cross-screen NLP actions preserve month and command text', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(appActionProvider.notifier).request(
      AppActionType.runMonthlyPlanCommand,
      month: DateTime(2026, 11, 18),
      text: 'November petrol max 4000',
    );
    final planRequest = container.read(appActionProvider);

    expect(planRequest?.action, AppActionType.runMonthlyPlanCommand);
    expect(planRequest?.month, DateTime(2026, 11));
    expect(planRequest?.text, 'November petrol max 4000');

    container.read(appActionProvider.notifier).request(
      AppActionType.openStatsMonth,
      month: DateTime(2026, 9, 12),
    );
    final statsRequest = container.read(appActionProvider);

    expect(statsRequest?.action, AppActionType.openStatsMonth);
    expect(statsRequest?.month, DateTime(2026, 9));
  });

  test('monthly PDF month resolver understands relative and named months', () {
    final now = DateTime(2026, 10, 5);

    expect(
      resolveMonthlyPdfTargetMonth('show monthly PDF', now: now),
      DateTime(2026, 10),
    );
    expect(
      resolveMonthlyPdfTargetMonth('last month PDF', now: now),
      DateTime(2026, 9),
    );
    expect(
      resolveMonthlyPdfTargetMonth('September PDF', now: now),
      DateTime(2026, 9),
    );
    expect(
      resolveMonthlyPdfTargetMonth('December PDF', now: now),
      DateTime(2025, 12),
    );
    expect(
      resolveMonthlyPdfTargetMonth('open PDF', now: now),
      isNull,
    );
  });

}
