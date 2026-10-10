import 'package:flutter_test/flutter_test.dart';
import 'package:student_expense_manager/features/smart_entry/smart_entry_controller.dart';
import 'package:student_expense_manager/services/explicit_expense_category.dart';
import 'package:student_expense_manager/services/home_category_speech_policy.dart';
import 'package:student_expense_manager/services/local_nlp_service.dart';
import 'package:student_expense_manager/services/smart_command.dart';
import 'package:student_expense_manager/services/smart_input_engine.dart';
import 'package:student_expense_manager/services/speech_category_matcher.dart';

void main() {
  const names = ['General', 'Food', 'Dinner', 'Family Dinner', 'Zong Package', 'Food 2', 'C++', 'Mess'];
  final controller = SmartEntryController();
  const matcher = SpeechCategoryMatcher();
  const policy = HomeCategorySpeechPolicy();

  for (final input in [
    'milk 120 category diner',
    'milk 120 catagory diner',
    'milk 120 in diner category',
    'milk 120 diner category',
    'milk 120 into diner',
    'milk 120 in diner',
    'milk 120 diner mein add karo',
    'milk 120 khurch ka diner me add karo',
    'milk 120 category diner add karo',
  ]) {
    test('$input suggests Dinner without executing it', () {
      final plan = controller.parse(input, names, source: SmartInputSource.voice,
          enableHomeExpenseCategories: true);
      final category = plan.expenseCategory!;
      expect(category.needsClarification, true);
      expect(category.category, isNull);
      expect(category.requestedNames, ['diner']);
      expect(category.suggestions, ['Dinner']);
      expect(plan.originalText, input);
      expect(plan.parsed.amount, 120);
      expect(plan.parsed.title, 'Milk');
      expect(policy.evaluate(plan).isComplete, true);
      final confirmed = controller.parse(input, names,
          source: SmartInputSource.voice, expenseCategory: category.confirmed('Dinner'));
      expect(confirmed.parsed.category, 'Dinner');
      expect(confirmed.parsed.title, 'Milk');
      expect(confirmed.parsed.amount, 120);
      expect(confirmed.expenseCategory!.resolution, 'confirmed');
    });
  }

  test('multi-word spelling mistakes use conservative edit and Dice agreement', () {
    const requested = ExplicitExpenseCategory(cleanedText: 'milk 120',
        issue: 'Choose an existing category; the requested category was not found.',
        requestedNames: ['song pakage'], hasCategoryLabel: true);
    final result = matcher.match(requested, names);
    expect(result.suggestions, ['Zong Package']);
    expect(result.needsClarification, true);
    expect(result.category, isNull);
  });

  test('two close names remain alternatives without a selected category', () {
    final result = controller.resolveHomeExpenseCategory('milk 120 category diner',
        ['Dinner', 'Diners'], source: SmartInputSource.voice)!;
    expect(result.suggestions.toSet(), {'Dinner', 'Diners'});
    expect(result.category, isNull);
  });

  for (final pair in [
    ['gas', 'Gym'], ['match', 'Mess'], ['dinner2', 'Dinner'],
    ['food 3', 'Food 2'], ['c+', 'C++'], ['trans', 'Transport'],
    ['other', 'Udhar'], ['send', 'Dinner'], ['dinner party', 'Dinner'],
  ]) {
    test('${pair.first} never gets a fuzzy auto-match to ${pair.last}', () {
      final result = matcher.match(ExplicitExpenseCategory(cleanedText: 'milk 120',
          issue: 'Choose an existing category; the requested category was not found.',
          requestedNames: [pair.first], hasCategoryLabel: true), [pair.last]);
      expect(result.suggestions, isEmpty);
      expect(result.category, isNull);
      expect(result.needsClarification, true);
    });
  }

  test('a confirmed hallucination alias can resolve the isolated category', () {
    const input = 'milk 120 category match';
    final result = controller.parse(input, names, source: SmartInputSource.voice,
        enableHomeExpenseCategories: true, voiceCategoryAliases: {'match': 'Mess'});
    expect(result.expenseCategory!.resolution, 'confirmed_alias');
    expect(result.parsed.category, 'Mess');
    expect(result.parsed.title, 'Milk');
    expect(result.originalText, input);
  });

  test('adding an exact category supersedes a remembered alias', () {
    final plan = controller.parse('milk 120 category match', [...names, 'Match'],
        source: SmartInputSource.voice, enableHomeExpenseCategories: true,
        voiceCategoryAliases: {'match': 'Mess'});
    expect(plan.parsed.category, 'Match');
    expect(plan.expenseCategory!.resolution, 'exact');
  });

  test('aliases for deleted or renamed categories cannot execute', () {
    final result = controller.resolveHomeExpenseCategory('milk 120 category match',
        ['General', 'New Mess'], source: SmartInputSource.voice,
        voiceCategoryAliases: {'match': 'Mess'})!;
    expect(result.category, isNull);
    expect(result.needsClarification, true);
  });

  test('even remembered aliases cannot substitute digits or punctuation', () {
    final result = matcher.match(const ExplicitExpenseCategory(cleanedText: 'milk 120',
        issue: 'Choose an existing category; the requested category was not found.',
        requestedNames: ['food 3'], hasCategoryLabel: true), names,
        confirmedAliases: {'food 3': 'Food 2'});
    expect(result.category, isNull);
    expect(result.suggestions, isEmpty);
  });

  test('missing category differs from an unknown but fully spoken name', () {
    final missing = controller.parse('milk 120 category', names,
        source: SmartInputSource.voice, enableHomeExpenseCategories: true);
    final unknown = controller.parse('milk 120 category match', names,
        source: SmartInputSource.voice, enableHomeExpenseCategories: true);
    expect(policy.evaluate(missing).reason, 'category_instruction_incomplete');
    expect(policy.evaluate(missing).isComplete, false);
    expect(policy.evaluate(unknown).isComplete, true);
    expect(unknown.expenseCategory!.needsClarification, true);
  });

  for (final input in ['milk 120 catagory', 'milk 120 category me add karo',
      'milk 120 into', 'milk 120 in']) {
    test('$input retains an unfinished category slot', () {
      final plan = controller.parse(input, names, source: SmartInputSource.voice,
          enableHomeExpenseCategories: true);
      expect(plan.expenseCategory!.isInstructionIncomplete, true);
      expect(plan.expenseCategory!.canSuggest, false);
      expect(policy.evaluate(plan).isComplete, false);
    });
  }

  test('unknown categories cannot bypass missing amount or item checks', () {
    for (final input in ['milk category diner', '120 category diner']) {
      final plan = controller.parse(input, names, source: SmartInputSource.voice,
          enableHomeExpenseCategories: true);
      expect(policy.evaluate(plan).isComplete, false);
    }
  });

  for (final input in [
    'milk 120 category diner category food',
    'milk 120 category diner category missing',
    'milk 120 catagory diner catagory missing',
    'milk 120 category dinner catagory food',
    'milk 120 category dinner category food',
  ]) {
    test('$input rejects alias learning and fuzzy selection on conflicts', () {
      final result = controller.resolveHomeExpenseCategory(input, names,
          source: SmartInputSource.voice, voiceCategoryAliases: {'diner': 'Dinner'})!;
      expect(result.canSuggest, false);
      expect(result.category, isNull);
      expect(result.suggestions, isEmpty);
      expect(result.isInstructionIncomplete, false);
    });
  }

  test('unqualified fuzzy matches cannot pick a wallet category', () {
    final plan = controller.parse('milk 120 in diner', names,
        source: SmartInputSource.voice, enableHomeExpenseCategories: true,
        accounts: const [SmartEntryAccount(id: 'd', name: 'Dinner', type: 'cash', availableBalance: 500)],
        voiceCategoryAliases: {'diner': 'Dinner'});
    expect(plan.expenseCategory!.category, isNull);
    expect(plan.expenseCategory!.suggestions, isEmpty);
  });

  test('typed input and opted-out callers never get fuzzy or alias matching', () {
    final typed = controller.parse('milk 120 category diner', names,
        source: SmartInputSource.typed, enableHomeExpenseCategories: true,
        voiceCategoryAliases: {'diner': 'Dinner'});
    expect(typed.expenseCategory!.suggestions, isEmpty);
    expect(typed.expenseCategory!.category, isNull);
    final optedOut = controller.parse('milk 120 category diner', names,
        source: SmartInputSource.voice, voiceCategoryAliases: {'diner': 'Dinner'});
    expect(optedOut.expenseCategory, isNull);
  });

  test('exact General stays locked even with a conflicting alias', () {
    final plan = controller.parse('milk 120 category General', names,
        source: SmartInputSource.voice, enableHomeExpenseCategories: true,
        voiceCategoryAliases: {'general': 'Food'});
    expect(plan.parsed.category, 'General');
    expect(plan.expenseCategory!.needsClarification, false);
  });

  for (final input in [
    'salary 5000 category diner', 'delete milk 120 category diner',
    'change milk 120 category diner', 'search category diner',
    'total spent in march', 'send 120 from cash to jazzcash',
    'udhar 120 category diner', 'milk 120 and bread 80 category diner',
    'milk 120 category diner nahi',
  ]) {
    test('$input stays outside the voice correction path', () {
      final result = controller.resolveHomeExpenseCategory(input, names,
          source: SmartInputSource.voice, voiceCategoryAliases: {'diner': 'Dinner'});
      expect(result, isNull);
    });
  }

  test('an unknown numeric span cannot erase a second expense through confirmation', () {
    final result = controller.resolveHomeExpenseCategory(
        'milk 120 category diner bread 80', names, source: SmartInputSource.voice)!;
    expect(result.needsClarification, true);
    expect(result.canConfirmVoice, false);
    expect(result.category, isNull);
  });

  test('no hallucination map rewrites title, date or wallet text', () {
    const raw = 'march other send 120 category diner from JazzCash yesterday';
    final selection = const ExplicitExpenseCategoryExtractor().extract(raw, names, voice: true)!;
    expect(selection.cleanedText, contains('march other send 120'));
    expect(selection.cleanedText, contains('JazzCash'));
    expect(selection.cleanedText, contains('yesterday'));
    expect(selection.requestedNames, ['diner']);
  });
}
