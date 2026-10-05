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

  test('app action channel delivers and consumes one PDF request', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(appActionProvider), isNull);
    container
        .read(appActionProvider.notifier)
        .request(AppActionType.openMonthlyPdf);

    final request = container.read(appActionProvider);
    expect(request, isNotNull);
    expect(request!.action, AppActionType.openMonthlyPdf);

    container.read(appActionProvider.notifier).consume(request.id);
    expect(container.read(appActionProvider), isNull);
  });

}
