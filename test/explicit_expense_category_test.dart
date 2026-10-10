import 'package:flutter_test/flutter_test.dart';
import 'package:student_expense_manager/features/smart_entry/smart_entry_controller.dart';
import 'package:student_expense_manager/features/smart_entry/multi_entry_parser.dart';
import 'package:student_expense_manager/services/explicit_expense_category.dart';
import 'package:student_expense_manager/services/confidence_evaluator.dart';
import 'package:student_expense_manager/services/local_nlp_service.dart';
import 'package:student_expense_manager/services/smart_command.dart';
import 'package:student_expense_manager/services/smart_input_engine.dart';
import 'package:student_expense_manager/services/speech_command_completeness.dart';

void main() {
  const categories = ['General', 'Food', 'Dinner', 'Family Dinner', 'Food 2', 'C++'];
  const extractor = ExplicitExpenseCategoryExtractor();
  final controller = SmartEntryController();

  for (final input in [
    'milk 120 rs category dinner',
    'milk 120 rs category dinner.',
    'milk 120 khurch ka dinner me add karo',
    'milk 120 in dinner category',
    'milk 120 into dinner',
    'milk 120 dinner category mein daal do',
    'milk 120 category dinner add karo',
  ]) {
    for (final source in SmartInputSource.values.where(
        (source) => source == SmartInputSource.typed || source == SmartInputSource.voice)) {
      test('$input (${source.name}) saves the explicit Dinner fields instantly', () {
        final plan = controller.parse(input, categories,
            source: source, enableHomeExpenseCategories: true);
        expect(plan.parsed.intent, SmartEntryIntent.addExpense);
        expect(plan.parsed.title, 'Milk');
        expect(plan.parsed.amount, 120);
        expect(plan.parsed.category, 'Dinner');
        expect(plan.expenseCategory?.needsClarification, false);
        expect(plan.originalText, input);
        expect(plan.normalization.normalized, contains('dinner'));
        expect(plan.normalizedText, isNot(contains('dinner')));
        final confidence = const ConfidenceEvaluator().evaluate(plan.command,
            context: const ConfidenceContext(hasExactAmount: true, hasResolvedWallet: true));
        expect(confidence.canAutoExecute, true);
        expect(shouldAutoSaveSmartEntry(plan.parsed.toLegacyMap(),
            hasResolvedWallet: true, semanticConfidence: confidence.score), true);
        expect(const SpeechCommandCompletenessEvaluator().evaluate(plan).isComplete, true);
      });
    }
  }

  test('longest category wins and instruction spans do not leak into the title', () {
    final plan = controller.parse('milk 120 in family dinner category', categories,
        source: SmartInputSource.typed, enableHomeExpenseCategories: true);
    expect(plan.parsed.category, 'Family Dinner');
    expect(plan.parsed.title, 'Milk');
    expect(plan.normalizedText, 'milk 120');
  });

  test('General is explicit even when milk implies Food', () {
    final plan = controller.parse('milk 120 in general category', categories,
        source: SmartInputSource.voice, enableHomeExpenseCategories: true);
    expect(plan.parsed.category, 'General');
    expect(plan.expenseCategory?.category, 'General');
    expect(plan.parsed.title, 'Milk');
  });

  test('case and whitespace match the exact saved category spelling', () {
    final result = extractor.extract('milk 120 CATEGORY family   DINNER', categories);
    expect(result?.category, 'Family Dinner');
    expect(result?.cleanedText, 'milk 120');
  });

  test('repeated references to the same category are not conflicts', () {
    final result = extractor.extract('milk 120 category dinner category Dinner', categories);
    expect(result?.needsClarification, false);
    expect(result?.category, 'Dinner');
    expect(result?.cleanedText, 'milk 120');
  });

  for (final input in [
    'milk 120 category diner',
    'milk 120 category dinner party',
    'milk 120 category dinner2',
    'milk 120 category Food 3',
    'category Food 3, milk 120',
    'milk 120 category dinner category food',
    'milk 120 category dinner category missing',
    'milk 120 category',
    'milk 120 into missing category',
    'milk 120 into missing',
    'milk 120 missing mein add karo',
  ]) {
    test('$input requires category clarification', () {
      final plan = controller.parse(input, categories,
          source: SmartInputSource.voice, enableHomeExpenseCategories: true);
      expect(plan.expenseCategory?.needsClarification, true);
      expect(plan.expenseCategory?.category, isNull);
    });
  }

  test('a numeric category is not another expense amount', () {
    final selection = controller.resolveHomeExpenseCategory('category Food 2, milk 120', categories,
        source: SmartInputSource.typed);
    // A category instruction before the item must stop at its known name.
    expect(selection?.category, 'Food 2');
    expect(const MultiEntryParser().tryParseBatch(selection!.cleanedText), isNull);
    final plan = controller.parse('milk 120 category Food 2', categories,
        source: SmartInputSource.typed, enableHomeExpenseCategories: true);
    expect(plan.parsed.amount, 120);
    expect(plan.parsed.category, 'Food 2');
    expect(plan.parsed.title, 'Milk');
  });

  test('punctuation in category names is escaped', () {
    final plan = controller.parse('milk 120 category C++', categories,
        source: SmartInputSource.typed, enableHomeExpenseCategories: true);
    expect(plan.parsed.category, 'C++');
    expect(plan.parsed.title, 'Milk');
  });

  test('wallet and date instructions remain available after subtraction', () {
    final result = extractor.extract('milk 120 category dinner from JazzCash yesterday', categories);
    expect(result?.cleanedText, 'milk 120 from JazzCash yesterday');
  });

  test('unqualified category and wallet name collisions require clarification', () {
    expect(extractor.extract('milk 120 in dinner', categories,
        walletNames: ['Dinner'])?.needsClarification, true);
    expect(extractor.extract('milk 120 dinner me add karo', categories,
        walletNames: ['Dinner'])?.needsClarification, true);
    expect(extractor.extract('milk 120 category dinner', categories,
        walletNames: ['Dinner'])?.category, 'Dinner');
  });

  for (final input in [
    'milk 120', 'dinner 120', 'biryani 500',
    'received salary 5000 category dinner',
    'salary 5000 dinner me add karo',
    'cash me 5000 add karo',
    'milk 120 cash me add karo',
    'milk 120 jazzcash mein dalo',
    'udhar 120 category dinner',
    'repeat milk 120 category dinner',
    'open settings category dinner',
    'delete milk 120', 'change milk 120 category dinner',
    'milk ki category dinner karo',
    'search milk in dinner category', 'how much spent in dinner category',
    'transfer 120 from Cash to JazzCash',
    'milk 120 category dinner nahi',
    'milk 120 category dinner or food',
    'milk 120 and bread 50',
    'milk 120 category dinner and bread 50',
    'milk 120 category missing and bread 50',
  ]) {
    test('$input keeps the original NLP result', () {
      final original = controller.parse(input, categories, source: SmartInputSource.typed);
      final enabled = controller.parse(input, categories,
          source: SmartInputSource.typed, enableHomeExpenseCategories: true);
      expect(enabled.expenseCategory, isNull);
      final before = original.parsed.toLegacyMap()..remove('date');
      final after = enabled.parsed.toLegacyMap()..remove('date');
      expect(after, before);
      expect(enabled.normalizedText, original.normalizedText);
      expect(enabled.parsed.date.year, original.parsed.date.year);
      expect(enabled.parsed.date.month, original.parsed.date.month);
      expect(enabled.parsed.date.day, original.parsed.date.day);
    });
  }

  test('feature is disabled for existing engine/controller callers', () {
    const input = 'milk 120 category dinner';
    final original = SmartInputEngine().parse(input, categories);
    final unchanged = controller.parse(input, categories, source: SmartInputSource.typed);
    expect(unchanged.expenseCategory, isNull);
    expect(unchanged.parsed.category, original.parsed.category);
    expect(unchanged.parsed.title, original.parsed.title);
  });
}
