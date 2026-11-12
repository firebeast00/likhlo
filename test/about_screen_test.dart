import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:student_expense_manager/l10n/app_strings.dart';
import 'package:student_expense_manager/l10n/material_strings.dart';
import 'package:student_expense_manager/screens/about_screen.dart';

void main() {
  for (final language in AppLanguage.values) {
    for (final brightness in Brightness.values) {
      for (final width in [320.0, 360.0, 800.0]) {
        for (final scale in [1.0, 1.6]) {
          testWidgets(
              'About fits ${language.name} $brightness width $width scale $scale',
              (tester) async {
            await tester.binding.setSurfaceSize(Size(width, 800));
            addTearDown(() => tester.binding.setSurfaceSize(null));
            await tester.pumpWidget(MaterialApp(
              locale: language.locale,
              supportedLocales: AppStrings.supportedLocales,
              localizationsDelegates: const [
                AppStrings.delegate,
                AppMaterialDelegate(),
                AppCupertinoDelegate(),
                AppWidgetsDelegate()
              ],
              theme: ThemeData(
                  useMaterial3: true,
                  brightness: brightness,
                  colorScheme: ColorScheme.fromSeed(
                      seedColor: Colors.amber, brightness: brightness)),
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!),
              home: const AboutScreen(),
            ));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            for (final name in ['Jawad Rajper', 'Fayaz Ahmed', 'Saira']) {
              expect(find.text(name), findsOneWidget);
            }
            for (final roll in ['23BSIT-08', '23BSIT-03', '23BSIT-43']) {
              expect(
                  find.byWidgetPredicate((widget) =>
                      widget is SelectableText &&
                      widget.data == 'Roll No. $roll'),
                  findsOneWidget);
            }
            expect(find.text(AppStrings(language).text('about_description')),
                findsOneWidget);
            expect(find.text('Version 2.5.0 (Stable)'), findsNothing);
            await tester.drag(
                find.byType(SingleChildScrollView), const Offset(0, -600));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          });
        }
      }
    }
  }
}
