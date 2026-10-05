import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:student_expense_manager/l10n/app_strings.dart';
import 'package:student_expense_manager/l10n/material_strings.dart';
import 'package:student_expense_manager/providers/settings_provider.dart';
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
    expect(container.read(settingsProvider).smartEntryLanguage, 'english');
    expect(container.read(settingsProvider).themeMode, 'dark');
    expect(ledger.toMap(), before);
    await notifier.updateAppLanguage('invalid');
    expect(container.read(settingsProvider).appLanguage, 'romanUrdu');
    container.invalidate(settingsProvider);
    expect(container.read(settingsProvider).appLanguage, 'romanUrdu');
    await container.read(settingsProvider.notifier).updateAppLanguage('english');
    expect(AppLanguage.read(), AppLanguage.english);
  });

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
  });
}
