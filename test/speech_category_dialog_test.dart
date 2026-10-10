import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:student_expense_manager/l10n/app_strings.dart';
import 'package:student_expense_manager/widgets/speech_category_dialog.dart';

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('likhlo_category_');
    Hive.init(directory.path);
    await Hive.openBox('settings');
  });
  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  for (final language in AppLanguage.values) {
    testWidgets('${language.name}: selecting a suggestion requires explicit confirmation', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() => Hive.box('settings').put('appLanguage', language.name));
      SpeechCategoryChoice? result;
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) =>
          Scaffold(body: TextButton(onPressed: () async {
            result = await showDialog<SpeechCategoryChoice>(context: context,
                builder: (_) => const SpeechCategoryDialog(heardName: 'diner',
                  categories: ['General', 'Dinner', 'Family Dinner'], suggestions: ['Dinner']));
          }, child: const Text('Open'))))));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
      expect(tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value, false);
      await tester.tap(find.byType(ChoiceChip));
      await tester.pumpAndSettle();
      expect(result, isNull);
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(result!.category, 'Dinner');
      expect(result!.remember, false);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('cancel never produces a category selection', (tester) async {
    SpeechCategoryChoice? result;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) =>
        Scaffold(body: TextButton(onPressed: () async {
          result = await showDialog<SpeechCategoryChoice>(context: context,
              builder: (_) => const SpeechCategoryDialog(heardName: 'match',
                  categories: ['General', 'Mess']));
        }, child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });
}
