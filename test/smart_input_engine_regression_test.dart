import 'package:flutter_test/flutter_test.dart';
import 'package:student_expense_manager/models/expense_model.dart';
import 'package:student_expense_manager/services/confidence_evaluator.dart';
import 'package:student_expense_manager/services/local_nlp_service.dart';
import 'package:student_expense_manager/services/smart_command.dart';
import 'package:student_expense_manager/services/smart_input_engine.dart';

void main() {
  const categories = [
    'General',
    'Food',
    'Transport',
    'Education',
    'Shopping',
  ];
  final engine = SmartInputEngine();

  group('primary intent routing', () {
    test('routes navigation before transaction extraction', () {
      for (final input in ['Go to stats tab', 'Show me stats']) {
        final plan = engine.parse(input, categories);

        expect(plan.parsed.intent, SmartEntryIntent.navigate);
        expect(plan.parsed.navigationTarget, 'Stats');
        expect(plan.command, isA<ReadOnlySmartCommand>());
        expect(plan.parsed.amount, 0);
      }
    });

    test('keeps a financial show command as a query', () {
      final plan = engine.parse('Show me food expenses', categories);

      expect(plan.parsed.intent, SmartEntryIntent.query);
      expect(plan.parsed.queryMetric, SmartEntryQueryMetric.spending);
    });

    test('explicit add wins over accidental edit inference', () {
      final plan = engine.parse('150 ka jute add karo', categories);

      expect(plan.command, isA<AddSmartTransactionCommand>());
      expect(plan.parsed.intent, SmartEntryIntent.addExpense);
      expect(plan.parsed.amount, 150);
      expect(plan.parsed.title, 'Jute');
    });

    test('text without financial evidence stays unknown', () {
      final plan = engine.parse('hello there', categories);

      expect(plan.command, isA<UnknownSmartCommand>());
      expect(plan.parsed.intent, SmartEntryIntent.unknown);
    });
  });

  group('daily read-only commands', () {
    test('routes dark mode controls without creating transactions', () {
      final on = engine.parse('dark mode on', categories);
      final off = engine.parse('dark mode band krdo', categories);
      final light = engine.parse('light mode karo', categories);
      final toggle = engine.parse('toggle dark mode', categories);

      expect(on.parsed.intent, SmartEntryIntent.appControl);
      expect(on.parsed.appAction, SmartEntryAppAction.darkModeOn);
      expect(on.command, isA<ReadOnlySmartCommand>());
      expect(on.parsed.amount, 0);

      expect(off.parsed.intent, SmartEntryIntent.appControl);
      expect(off.parsed.appAction, SmartEntryAppAction.darkModeOff);
      expect(off.command, isA<ReadOnlySmartCommand>());

      expect(light.parsed.intent, SmartEntryIntent.appControl);
      expect(light.parsed.appAction, SmartEntryAppAction.darkModeOff);
      expect(toggle.parsed.intent, SmartEntryIntent.appControl);
      expect(toggle.parsed.appAction, SmartEntryAppAction.darkModeToggle);
    });

    test('understands monthly and daily summary phrases', () {
      final roman =
          engine.parse('is mahine ka hisaab dikhao', categories);
      final english =
          engine.parse('show total summary of month', categories);
      final today = engine.parse('aaj ka summary', categories);

      expect(roman.parsed.intent, SmartEntryIntent.query);
      expect(roman.parsed.queryMetric, SmartEntryQueryMetric.summary);
      expect(roman.parsed.timeRange, SmartEntryTimeRange.thisMonth);

      expect(english.parsed.queryMetric, SmartEntryQueryMetric.summary);
      expect(english.parsed.timeRange, SmartEntryTimeRange.thisMonth);

      expect(today.parsed.queryMetric, SmartEntryQueryMetric.summary);
      expect(today.parsed.timeRange, SmartEntryTimeRange.today);
    });

    test('understands common Roman Urdu balance and income questions', () {
      final balance =
          engine.parse('mere paas kitne paise hain', categories);
      final income =
          engine.parse('is mahine kitna paisa aya', categories);

      expect(balance.parsed.intent, SmartEntryIntent.query);
      expect(balance.parsed.queryMetric, SmartEntryQueryMetric.balance);

      expect(income.parsed.intent, SmartEntryIntent.query);
      expect(income.parsed.queryMetric, SmartEntryQueryMetric.income);
      expect(income.parsed.timeRange, SmartEntryTimeRange.thisMonth);
    });

    test('treats amount-free daily finance phrases as queries', () {
      final spending = engine.parse('aaj ka kharcha', categories);
      final income = engine.parse('aaj ki income', categories);
      final expenseEntry = engine.parse('aaj 500 petrol', categories);

      expect(spending.parsed.intent, SmartEntryIntent.query);
      expect(spending.parsed.queryMetric, SmartEntryQueryMetric.spending);
      expect(spending.parsed.timeRange, SmartEntryTimeRange.today);

      expect(income.parsed.intent, SmartEntryIntent.query);
      expect(income.parsed.queryMetric, SmartEntryQueryMetric.income);
      expect(income.parsed.timeRange, SmartEntryTimeRange.today);

      expect(expenseEntry.parsed.intent, SmartEntryIntent.addExpense);
      expect(expenseEntry.parsed.amount, 500);
    });

    test('understands generic spoken balance questions', () {
      final generic = engine.parse('kitne paise hain', categories);
      final account = engine.parse('account mein kitne paise hain', categories);
      final spending =
          engine.parse('aaj kitne paise kharch hue', categories);

      expect(generic.parsed.intent, SmartEntryIntent.query);
      expect(generic.parsed.queryMetric, SmartEntryQueryMetric.balance);

      expect(account.parsed.intent, SmartEntryIntent.query);
      expect(account.parsed.queryMetric, SmartEntryQueryMetric.balance);

      expect(spending.parsed.intent, SmartEntryIntent.query);
      expect(spending.parsed.queryMetric, SmartEntryQueryMetric.spending);
    });

    test('understands wallet and category questions used daily', () {
      final wallet = engine.parse('cash me kitna hai', categories);
      final category =
          engine.parse('pichlay month shopping kitni thi', categories);

      expect(wallet.parsed.intent, SmartEntryIntent.query);
      expect(wallet.parsed.queryMetric, SmartEntryQueryMetric.balance);

      expect(category.parsed.intent, SmartEntryIntent.query);
      expect(category.parsed.queryMetric, SmartEntryQueryMetric.spending);
      expect(category.parsed.category, 'Shopping');
      expect(category.parsed.timeRange, SmartEntryTimeRange.lastMonth);
    });

    test('opens new navigation targets with Roman Urdu aliases', () {
      final plan =
          engine.parse('mahine ka plan dikhado', categories);
      final trash =
          engine.parse('deleted entries dikhado', categories);
      final wallets = engine.parse('accounts dikhao', categories);

      expect(plan.parsed.intent, SmartEntryIntent.navigate);
      expect(plan.parsed.navigationTarget, 'Monthly Plan');
      expect(trash.parsed.intent, SmartEntryIntent.navigate);
      expect(trash.parsed.navigationTarget, 'Trash');
      expect(wallets.parsed.intent, SmartEntryIntent.navigate);
      expect(wallets.parsed.navigationTarget, 'Wallets');
    });

    test('routes Udhar questions to dedicated read-only metrics', () {
      final summary =
          engine.parse('udhar ka hisaab batao', categories);
      final receive =
          engine.parse('mujhe kitna udhar wapas lena hai', categories);
      final pay =
          engine.parse('mujhe kitna udhar wapas dena hai', categories);

      expect(summary.parsed.intent, SmartEntryIntent.query);
      expect(summary.parsed.queryMetric, SmartEntryQueryMetric.udharSummary);
      expect(receive.parsed.queryMetric,
          SmartEntryQueryMetric.udharReceivable);
      expect(pay.parsed.queryMetric, SmartEntryQueryMetric.udharPayable);
    });

    test('repairs live voice aliases and routes observed commands safely', () {
      const accounts = [
        SmartEntryAccount(
          id: 'jazz',
          name: 'JazzCash',
          type: 'jazzcash',
          availableBalance: 10000,
        ),
        SmartEntryAccount(
          id: 'bank',
          name: 'Bank Account',
          type: 'custom',
          availableBalance: 10000,
        ),
      ];

      final transfer = engine.parse(
        '5000 JSK se bank account mein transfer karo',
        categories,
        source: SmartInputSource.voice,
        accounts: accounts,
      );
      final pdf = engine.parse('show monthly PDF', categories);
      final monthlyList =
          engine.parse('mahine ke kharcho ki list dikhao', categories);
      final summaryPdf =
          engine.parse('mahine ke kharcho ki samri PDF', categories);
      final udhar =
          engine.parse('Jawad ko 2000 Udhar Diye', categories);

      expect(transfer.parsed.intent, SmartEntryIntent.transfer);
      expect(transfer.normalizedText, contains('jazzcash'));
      expect(transfer.command, isA<TransferCommand>());

      expect(pdf.parsed.intent, SmartEntryIntent.navigate);
      expect(pdf.parsed.navigationTarget, 'Settings');

      expect(monthlyList.parsed.intent, SmartEntryIntent.searchEntries);
      expect(monthlyList.parsed.timeRange, SmartEntryTimeRange.thisMonth);
      expect(monthlyList.parsed.entryTypeFilter, 'expense');

      expect(summaryPdf.parsed.intent, SmartEntryIntent.query);
      expect(summaryPdf.parsed.queryMetric, SmartEntryQueryMetric.summary);
      expect(summaryPdf.parsed.timeRange, SmartEntryTimeRange.thisMonth);

      expect(udhar.parsed.intent, SmartEntryIntent.navigate);
      expect(udhar.parsed.navigationTarget, 'Udhaar');
      expect(udhar.command, isA<ReadOnlySmartCommand>());
    });

    test('existing transaction and search commands keep their paths', () {
      final expense = engine.parse('500 petrol', categories);
      final deletion = engine.parse('delete burger', categories);
      final search = engine.parse('petrol wali entries dikhao', categories);

      expect(expense.parsed.intent, SmartEntryIntent.addExpense);
      expect(expense.command, isA<AddSmartTransactionCommand>());
      expect(deletion.parsed.intent, SmartEntryIntent.deleteEntry);
      expect(search.parsed.intent, SmartEntryIntent.searchEntries);
    });
  });

  group('field-specific edits', () {
    test('title edits create only a title patch', () {
      final cases = <String, List<String>>{
        'Change milk name to doodh': ['milk', 'Doodh'],
        'Update banana name to food': ['banana', 'Food'],
        'Update title pen to marker': ['pen', 'Marker'],
        'milk ka naam doodh karo': ['milk', 'Doodh'],
        'pen ko marker kar do': ['pen', 'Marker'],
      };

      for (final entry in cases.entries) {
        final plan = engine.parse(entry.key, categories);
        final command = plan.command as MutationCommand;

        expect(command.parsed.intent, SmartEntryIntent.editEntry);
        expect(command.selector.title, entry.value.first);
        expect(command.patch.title, entry.value.last);
        expect(command.patch.amount, isNull);
      }
    });

    test('a title-only patch preserves the stored amount', () {
      final plan = engine.parse('Change milk name to doodh', categories);
      final command = plan.command as MutationCommand;
      final original = Expense(
        id: 'milk-entry',
        title: 'Milk',
        amount: 240,
        date: DateTime(2026, 9, 21),
        category: 'Food',
        colorValue: 0,
        walletId: 'cash',
      );

      final updated = original.copyWith(
        title: command.patch.title,
        amount: command.patch.amount,
      );

      expect(updated.title, 'Doodh');
      expect(updated.amount, 240);
    });

    test('amount edits keep selector and patch amounts separate', () {
      final plan = engine.parse(
        'change 500 burger amount to 600',
        categories,
      );
      final command = plan.command as MutationCommand;

      expect(command.selector.title, 'burger');
      expect(command.selector.amount, 500);
      expect(command.patch.amount, 600);
      expect(command.patch.title, isNull);
    });
  });

  group('conversational entity extraction', () {
    test('isolates the purchased item from an English narrative', () {
      final plan = engine.parse(
        'When I go to university I bought a pen for 50 rupees',
        categories,
      );

      expect(plan.parsed.intent, SmartEntryIntent.addExpense);
      expect(plan.parsed.amount, 50);
      expect(plan.parsed.title, 'Pen');
      expect(plan.parsed.category, 'Education');
    });

    test('isolates the item after spent amount wording', () {
      final plan = engine.parse('I spent 200 on a pen', categories);

      expect(plan.parsed.amount, 200);
      expect(plan.parsed.title, 'Pen');
    });

    test('limits an extracted title to three core words', () {
      final plan = engine.parse(
        'I bought a blue gel ink pen for 250 rupees',
        categories,
      );

      expect(plan.parsed.amount, 250);
      expect(plan.parsed.title, 'Blue Gel Ink');
      expect(plan.parsed.title.split(' '), hasLength(3));
    });
  });

  group('contextual ASR repair', () {
    test('does not apply voice-only repairs to typed text', () {
      final plan = engine.parse('Spain pen 200', categories);

      expect(plan.normalizedText, 'spain pen 200');
      expect(plan.requiresAsrReview, isFalse);
    });

    test('repairs spent misheard as Spain only in retail amount context', () {
      final plan = engine.parse(
        'Spain pen 200',
        categories,
        source: SmartInputSource.voice,
      );

      expect(plan.normalizedText, 'spent pen 200');
      expect(plan.normalization.appliedRules, contains('spent_asr_context'));
      expect(plan.parsed.intent, SmartEntryIntent.addExpense);
      expect(plan.parsed.amount, 200);
      expect(plan.parsed.title, 'Pen');
      expect(plan.requiresAsrReview, isTrue);
    });

    test('repairs pen misheard as pain beside a purchase action', () {
      final plan = engine.parse(
        '200 pain khareeda',
        categories,
        source: SmartInputSource.voice,
      );

      expect(plan.normalizedText, '200 pen khareeda');
      expect(plan.normalization.appliedRules, contains('pen_asr_context'));
      expect(plan.parsed.title, 'Pen');
      expect(plan.requiresAsrReview, isTrue);
    });

    test('does not rewrite legitimate medical pain wording', () {
      final plan = engine.parse(
        '200 pain medicine',
        categories,
        source: SmartInputSource.voice,
      );

      expect(plan.normalizedText, '200 pain medicine');
      expect(
          plan.normalization.appliedRules, isNot(contains('pen_asr_context')));
    });
  });

  test('generic expense title cannot auto-execute', () {
    final plan = engine.parse('500', categories);
    final confidence = const ConfidenceEvaluator().evaluate(
      plan.command,
      context: const ConfidenceContext(
        hasExactAmount: true,
        hasResolvedWallet: true,
      ),
    );

    expect(plan.parsed.title, 'Quick Expense');
    expect(confidence.canAutoExecute, isFalse);
    expect(
        confidence.reasons, contains('A specific expense title is required.'));
    expect(
      shouldAutoSaveSmartEntry(
        plan.parsed.toLegacyMap(),
        hasResolvedWallet: true,
        semanticConfidence: 1,
      ),
      isFalse,
    );
  });

  test('clear amount plus item can pass the semantic add gate', () {
    final plan = engine.parse('500 biryani', categories);
    final confidence = const ConfidenceEvaluator().evaluate(
      plan.command,
      context: const ConfidenceContext(
        hasExactAmount: true,
        hasResolvedWallet: true,
      ),
    );

    expect(plan.parsed.intent, SmartEntryIntent.addExpense);
    expect(plan.parsed.title, 'Biryani');
    expect(confidence.canAutoExecute, isTrue);
  });
}
