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
    testWidgets('${language.name}: inline category controls select explicitly and do not open another form', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() => Hive.box('settings').put('appLanguage', language.name));
      String? chosen;
      var remember = false;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: StatefulBuilder(
        builder: (context, update) => SpeechCategoryReview(heardName: 'diner',
          suggestions: const ['Dinner', 'Family Dinner'], selectedCategory: chosen,
          remember: remember,
          onCategoryChanged: (name) => update(() => chosen = name),
          onRememberChanged: (value) => update(() => remember = value))))));
      expect(chosen, isNull);
      expect(remember, false);
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value, false);
      await tester.tap(find.byType(ChoiceChip).first);
      await tester.pumpAndSettle();
      expect(chosen, 'Dinner');
      expect(remember, false);
      expect(find.byType(AlertDialog), findsNothing);
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      expect(remember, true);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('inline missing-category review cannot remember an absent spoken name', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SpeechCategoryReview(
      heardName: '', onCategoryChanged: (_) {}, onRememberChanged: (_) {}))));
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
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

  for (final language in AppLanguage.values) {
    testWidgets('${language.name}: missing name needs selection and cannot create an alias', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() => Hive.box('settings').put('appLanguage', language.name));
      SpeechCategoryChoice? result;
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) =>
          Scaffold(body: TextButton(onPressed: () async {
            result = await showDialog<SpeechCategoryChoice>(context: context,
                builder: (_) => const SpeechCategoryDialog(heardName: '',
                  categories: ['General', 'Mess']));
          }, child: const Text('Open'))))));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byType(CheckboxListTile), findsNothing);
      expect(find.text(AppStrings.current.text('expense_category_incomplete')), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mess').last);
      await tester.pumpAndSettle();
      expect(result, isNull);
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(result!.category, 'Mess');
      expect(result!.remember, false);
      expect(tester.takeException(), isNull);
    });
  }
}
