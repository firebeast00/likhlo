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
      expect(plan.normalization.appliedRules, isNot(contains('pen_asr_context')));
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
    expect(confidence.reasons, contains('A specific expense title is required.'));
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
