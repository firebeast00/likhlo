import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:student_expense_manager/l10n/app_strings.dart';
import 'package:student_expense_manager/l10n/material_strings.dart';
import 'package:student_expense_manager/providers/settings_provider.dart';
import 'package:student_expense_manager/screens/settings_screen.dart';
import 'package:student_expense_manager/services/deterministic_feedback_service.dart';

class _LanguageView extends StatelessWidget {
  const _LanguageView();
  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Scaffold(body: Column(children: [
      Text(strings.display('App language')),
      const TextField(key: ValueKey('unchanged-form')),
    ]));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late Box settings;
  late ProviderContainer container;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('likhlo_language_');
    Hive.init(directory.path);
    settings = await Hive.openBox('settings');
    await Hive.openBox('preferences');
    container = ProviderContainer();
  });
  tearDown(() async {
    container.dispose();
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test('old settings keep English UI and the existing input preference', () async {
    await settings.put('smartEntryLanguage', 'romanUrdu');
    final state = container.read(settingsProvider);
    expect(state.appLanguage, 'english');
    expect(state.smartEntryLanguage, 'romanUrdu');
    expect(AppLanguage.parse('unknown'), AppLanguage.english);
  });

  test('language persists without changing other settings or ledger data', () async {
    await settings.putAll({'smartEntryLanguage': 'english', 'themeMode': 'dark'});
    final ledger = await Hive.openBox('language_test_ledger');
    await ledger.put('entry', {'amount': 1000, 'category': 'Food', 'title': 'Cash'});
    final before = Map.from(ledger.toMap());
    final notifier = container.read(settingsProvider.notifier);
    await notifier.updateAppLanguage('romanUrdu');
    expect(container.read(settingsProvider).smartEntryLanguage, 'romanUrdu');
    expect(container.read(settingsProvider).themeMode, 'dark');
    expect(ledger.toMap(), before);
    await notifier.updateAppLanguage('invalid');
    expect(container.read(settingsProvider).appLanguage, 'romanUrdu');
    container.invalidate(settingsProvider);
    expect(container.read(settingsProvider).appLanguage, 'romanUrdu');
    await container.read(settingsProvider.notifier).updateAppLanguage('english');
    expect(AppLanguage.read(), AppLanguage.english);
    expect(container.read(settingsProvider).smartEntryLanguage, 'english');
    expect(settings.get('smartEntryLanguage'), 'english');
  });

  test('one language selection updates both preferences and survives reload', () async {
    final notifier = container.read(settingsProvider.notifier);
    for (final language in ['romanUrdu', 'english']) {
      await notifier.updateLanguage(language);
      expect(container.read(settingsProvider).appLanguage, language);
      expect(container.read(settingsProvider).smartEntryLanguage, language);
      expect(settings.get('appLanguage'), language);
      expect(settings.get('smartEntryLanguage'), language);
      expect(AppLanguage.read().name, language);
    }
    container.invalidate(settingsProvider);
    expect(container.read(settingsProvider).appLanguage, 'english');
    expect(container.read(settingsProvider).smartEntryLanguage, 'english');
  });

  test('existing Smart NLP language callers use the shared selection', () async {
    await container.read(settingsProvider.notifier)
        .updateSmartEntryLanguage('romanUrdu');
    expect(container.read(settingsProvider).appLanguage, 'romanUrdu');
    expect(container.read(settingsProvider).smartEntryLanguage, 'romanUrdu');
    expect(AppLanguage.read(), AppLanguage.romanUrdu);
    expect(settings.get('appLanguage'), 'romanUrdu');
    expect(settings.get('smartEntryLanguage'), 'romanUrdu');
  });

  test('choosing the displayed legacy language synchronizes Smart NLP', () async {
    await settings.putAll({
      'appLanguage': 'english', 'smartEntryLanguage': 'romanUrdu',
    });
    final language = container.read(settingsProvider).appLanguage;
    await container.read(settingsProvider.notifier).updateLanguage(language);
    expect(container.read(settingsProvider).smartEntryLanguage, 'english');
    expect(settings.get('smartEntryLanguage'), 'english');
  });

  test('invalid shared language leaves both preferences untouched', () async {
    final notifier = container.read(settingsProvider.notifier);
    await notifier.updateLanguage('romanUrdu');
    final before = Map.from(settings.toMap());
    for (final invalid in ['', 'unknown', 'ur']) {
      await notifier.updateLanguage(invalid);
      await notifier.updateSmartEntryLanguage(invalid);
      await notifier.updateAppLanguage(invalid);
    }
    expect(settings.toMap(), before);
    expect(container.read(settingsProvider).appLanguage, 'romanUrdu');
    expect(container.read(settingsProvider).smartEntryLanguage, 'romanUrdu');
  });

  for (final language in AppLanguage.values) {
    testWidgets('Settings has one language control in ${language.name} on a narrow phone', (tester) async {
      await tester.runAsync(() =>
          container.read(settingsProvider.notifier).updateLanguage(language.name));
      tester.view.physicalSize = const Size(320, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: language.locale,
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: const [AppStrings.delegate, AppMaterialDelegate(), AppCupertinoDelegate(), AppWidgetsDelegate()],
          home: const SettingsScreen(),
        ),
      ));
      final selector = find.byKey(const ValueKey('settings-language'));
      await tester.scrollUntilVisible(selector, 250);
      await tester.pumpAndSettle();
      expect(find.byType(DropdownButton<String>), findsOneWidget);
      expect(tester.widget<DropdownButton<String>>(selector).value, language.name);
      expect(find.text(AppStrings(language).text('settings_language')), findsOneWidget);
      expect(find.text(AppStrings(language).text('settings_language_hint')), findsOneWidget);
      expect(find.text(AppStrings(language).text('smart_entry_language_ca86c2')), findsNothing);
      expect(tester.takeException(), isNull);
      final next = language == AppLanguage.english
          ? AppLanguage.romanUrdu : AppLanguage.english;
      await tester.tap(selector);
      await tester.pumpAndSettle();
      await tester.tap(find.text(next == AppLanguage.english ? 'English' : 'Roman Urdu').last);
      await tester.pumpAndSettle();
      // Hive writes run outside the widget test's fake async clock.
      await tester.runAsync(() async {
        await settings.flush();
      });
      await tester.pumpAndSettle();
      expect(container.read(settingsProvider).appLanguage, next.name);
      expect(container.read(settingsProvider).smartEntryLanguage, next.name);
      expect(settings.get('appLanguage'), next.name);
      expect(settings.get('smartEntryLanguage'), next.name);
      expect(tester.widget<DropdownButton<String>>(selector).value, next.name);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  test('committed finance values and user names remain opaque parameters', () {
    const data = FinancialFeedbackData(
      action: FinancialFeedbackAction.transfer, title: 'Food', amount: 1000.5,
      source: 'Food', destination: 'Cash {p0}',
    );
    const service = DeterministicFeedbackService();
    final message = service.localizedMessage(data);
    expect(message.render(AppLanguage.english), service.message(data));
    expect(message.render(AppLanguage.romanUrdu),
        'Food se Cash {p0} mein 1000.50 rupay transfer hue.');
    expect(message.render(AppLanguage.romanUrdu, spoken: true),
        'Food سے Cash {p0} میں 1000.50 روپے ٹرانسفر ہوئے۔');
  });

  test('query uses the same amount, count and period in both channels', () {
    const title = AppMessage('rs_spent_3fb486', {
      'p0': '1000', 'p1': AppLabel('this month'),
    });
    const body = AppMessage('expense_2a0b6d', {
      'p0': 4, 'p1': AppEnglishSuffix('s'), 'p2': '',
    });
    expect(title.render(AppLanguage.english), 'Rs. 1000 spent · this month');
    expect(title.render(AppLanguage.romanUrdu), 'Rs. 1000 kharch hue · is mahine');
    expect(title.render(AppLanguage.romanUrdu, spoken: true), '1000 روپے خرچ ہوئے، اس مہینے');
    expect(body.render(AppLanguage.english), '4 expenses.');
    expect(body.render(AppLanguage.romanUrdu), '4 kharch ki entries.');
    expect(body.render(AppLanguage.romanUrdu, spoken: true), 'خرچ کی 4 انٹریاں۔');
  });

  testWidgets('locale change preserves an open form and uses LTR controls', (tester) async {
    Widget app(AppLanguage language) => MaterialApp(
      locale: language.locale,
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: const [AppStrings.delegate, AppMaterialDelegate(), AppCupertinoDelegate(), AppWidgetsDelegate()],
      home: const _LanguageView(),
    );
    await tester.pumpWidget(app(AppLanguage.english));
    await tester.enterText(find.byKey(const ValueKey('unchanged-form')), 'Biryani 500');
    await tester.pumpWidget(app(AppLanguage.romanUrdu));
    await tester.pumpAndSettle();
    expect(find.text('App ki zaban'), findsOneWidget);
    expect(find.text('Biryani 500'), findsOneWidget);
    final context = tester.element(find.byType(TextField));
    expect(Directionality.of(context), TextDirection.ltr);
    expect(MaterialLocalizations.of(context).datePickerHelpText, 'Tareekh chunen');
    expect(MaterialLocalizations.of(context).formatMonthYear(DateTime(2026, 1)), 'Janwari 2026');
    expect(MaterialLocalizations.of(context).parseCompactDate('01/05/2026'), DateTime(2026, 1, 5));
  });
}
