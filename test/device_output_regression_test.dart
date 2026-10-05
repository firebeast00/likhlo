import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:student_expense_manager/l10n/app_strings.dart';
import 'package:student_expense_manager/l10n/material_strings.dart';
import 'package:student_expense_manager/providers/stats_provider.dart';
import 'package:student_expense_manager/screens/stats_screen.dart';
import 'package:student_expense_manager/widgets/app_dimmer_slider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late Box settings;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('likhlo_device_log_');
    Hive.init(directory.path);
    settings = await Hive.openBox('settings');
  });

  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  for (final language in AppLanguage.values) {
    for (final width in [320.0, 360.0, 800.0]) {
      for (final scale in [1.0, 1.5]) {
        testWidgets('Stats fits ${language.name} at $width with text scale $scale', (tester) async {
          await tester.runAsync(() => settings.put('appLanguage', language.name));
          await tester.binding.setSurfaceSize(Size(width, 772));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await tester.pumpWidget(ProviderScope(
            overrides: [statsProvider.overrideWith((ref, month) => ExpenseStats(
              selectedMonth: month,
              monthlyTotals: const [100, 200, 300, 400, 500, 15200],
              monthLabels: const ['May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct'],
              maxMonthTotal: 15200,
              totalSpent: 15200,
              totalIncome: 20000,
              netFlow: 4800,
              sortedCategories: const [MapEntry('Food', 15200)],
              walletActivity: const [],
            ))],
            child: MaterialApp(
              locale: language.locale,
              supportedLocales: AppStrings.supportedLocales,
              localizationsDelegates: const [
                AppStrings.delegate, AppMaterialDelegate(),
                AppCupertinoDelegate(), AppWidgetsDelegate(),
              ],
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: const StatsScreen(),
            ),
          ));
          await tester.pumpAndSettle();
          final error = tester.takeException();
          expect(error, isNull, reason: error is FlutterError ? error.toStringDeep() : '$error');
          final title = find.text(AppStrings(language).text('spending_by_category_d4aadf'));
          expect(title, findsOneWidget);
          final header = find.ancestor(of: title, matching: find.byType(Wrap));
          expect(header, findsOneWidget);
          expect(find.descendant(of: header, matching: find.text('Rs. 15200')), findsOneWidget);
          await tester.pumpWidget(const SizedBox());
        }, timeout: const Timeout(Duration(seconds: 30)));
      }
    }
  }

  testWidgets('dimmer exports one laid-out accessible node and can be adjusted', (tester) async {
    final handle = tester.ensureSemantics();

    var value = 0.0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: StatefulBuilder(
      builder: (context, setState) => AppDimmerSlider(
        value: value, color: Colors.teal, label: 'Screen Dimmer',
        onChanged: (next) => setState(() => value = next),
      ),
    ))));
    var node = tester.getSemantics(find.byType(AppDimmerSlider));
    expect(node.getSemanticsData().hasFlag(SemanticsFlag.isSlider), isTrue);
    expect(node.rect.isEmpty, isFalse);
    expect(node.childrenCount, 0);
    expect(node.getSemanticsData().label, 'Screen Dimmer');
    expect(node.getSemanticsData().value, '0%');
    tester.binding.pipelineOwner.semanticsOwner!.performAction(node.id, SemanticsAction.increase);
    await tester.pump();
    expect(value, greaterThan(0));
    node = tester.getSemantics(find.byType(AppDimmerSlider));
    tester.binding.pipelineOwner.semanticsOwner!.performAction(node.id, SemanticsAction.decrease);
    await tester.pump();
    expect(value, 0);
    await tester.tap(find.byType(Slider));
    await tester.pump();
    expect(value, greaterThan(0));
    expect(value, lessThanOrEqualTo(0.75));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    handle.dispose();
  });
}
