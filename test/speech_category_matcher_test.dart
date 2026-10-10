import 'package:flutter_test/flutter_test.dart';
import 'package:student_expense_manager/features/smart_entry/smart_entry_controller.dart';
import 'package:student_expense_manager/services/explicit_expense_category.dart';
import 'package:student_expense_manager/services/home_category_speech_policy.dart';
import 'package:student_expense_manager/services/local_nlp_service.dart';
import 'package:student_expense_manager/services/smart_command.dart';
import 'package:student_expense_manager/services/smart_input_engine.dart';
import 'package:student_expense_manager/services/speech_category_matcher.dart';
import 'package:student_expense_manager/services/confidence_evaluator.dart';
import 'package:student_expense_manager/services/speech_session_controller.dart';
import 'package:student_expense_manager/services/speech_timing_policy.dart';

void main() {
  const names = ['General', 'Food', 'Dinner', 'Family Dinner', 'Zong Package', 'Food 2', 'C++', 'Mess'];
  final controller = SmartEntryController();
  const matcher = SpeechCategoryMatcher();
  const policy = HomeCategorySpeechPolicy();

  for (final input in [
    '120 milk category mess',
    '120 ka milk category mess',
    '120 milk category mess.',
    'milk 120 category mess',
    '120 milk catagory mess',
    '120 ka milk category mess me add karo',
  ]) {
    for (final ordered in [
      ['Milk', 'Mess', ...names.where((name) => name != 'Mess')],
      ['Mess', 'Milk', ...names.where((name) => name != 'Mess')],
    ]) {
      test('$input / ${ordered.take(2).join(",")} preserves instant entry', () {
        final plan = controller.parse(input, ordered,
            source: SmartInputSource.voice, enableHomeExpenseCategories: true);
        expect(plan.parsed.amount, 120);
        expect(plan.parsed.title, 'Milk');
        expect(plan.parsed.category, 'Mess');
        expect(plan.expenseCategory!.needsClarification, false);
        expect(plan.expenseCategory!.matchedPhrases.single.toLowerCase(), contains('mess'));
        expect(policy.evaluate(plan).isComplete, true);
        final confidence = const ConfidenceEvaluator().evaluate(plan.command,
            context: const ConfidenceContext(hasExactAmount: true, hasResolvedWallet: true));
        expect(confidence.canAutoExecute, true);
        expect(shouldAutoSaveSmartEntry(plan.parsed.toLegacyMap(),
            hasResolvedWallet: true, semanticConfidence: confidence.score), true);
      });
    }
  }

  test('a longer item category cannot shadow a complete category prefix', () {
    final plan = controller.parse('500 biryani category mess',
        ['Biryani', ...names], source: SmartInputSource.voice,
        enableHomeExpenseCategories: true);
    expect(plan.parsed.title, 'Biryani');
    expect(plan.parsed.amount, 500);
    expect(plan.parsed.category, 'Mess');
  });

  for (final input in [
    '120 milk category', '120 ka milk category', '120 ka milk catagory',
    '120 ka milk category.', '50 ka Cup category', '50 ka gilas category',
    '120 milk category me add karo', 'milk 120 category',
  ]) {
    for (final withItemCategory in [false, true]) {
      test('$input keeps the expense body (item category=$withItemCategory)', () {
        final plan = controller.parse(input,
            [...names, if (withItemCategory) 'Milk', if (withItemCategory) 'Cup',
              if (withItemCategory) 'Gilas'], source: SmartInputSource.voice,
            enableHomeExpenseCategories: true);
        final expectedAmount = input.startsWith('50') ? 50 : 120;
        final expectedTitle = input.contains('Cup') ? 'Cup'
            : input.contains('gilas') ? 'Gilas' : 'Milk';
        expect(plan.parsed.amount, expectedAmount);
        expect(plan.parsed.title, expectedTitle);
        expect(plan.expenseCategory!.category, isNull);
        expect(plan.expenseCategory!.requestedNames, isEmpty);
        expect(policy.evaluate(plan).reason, 'category_instruction_incomplete');
        expect(policy.canRecoverCategory(plan), true);
        final confirmed = controller.parse(input, names, source: SmartInputSource.voice,
            expenseCategory: plan.expenseCategory!.confirmed('Mess'));
        expect(confirmed.parsed.title, expectedTitle);
        expect(confirmed.parsed.amount, expectedAmount);
        expect(confirmed.parsed.category, 'Mess');
      });
    }
  }

  for (final input in ['120 category', 'milk category', 'category',
      '120 from Cash category']) {
    test('$input cannot be recovered by choosing only a category', () {
      final plan = controller.parse(input, names, source: SmartInputSource.voice,
          enableHomeExpenseCategories: true);
      expect(policy.canRecoverCategory(plan), false);
    });
  }

  for (final input in ['120 milk mess category', '120 ka milk in mess category',
      'milk 120 dinner category mein daal do']) {
    test('$input retains an unambiguous saved-name suffix', () {
      final plan = controller.parse(input, [...names, 'Milk'],
          source: SmartInputSource.voice, enableHomeExpenseCategories: true);
      expect(plan.parsed.title, 'Milk');
      expect(plan.parsed.amount, 120);
      expect(plan.parsed.category, input.contains('dinner') ? 'Dinner' : 'Mess');
      expect(plan.expenseCategory!.needsClarification, false);
    });
  }

  test('unknown prefix wins over an overlapping saved item category', () {
    final plan = controller.parse('120 milk category diner', [...names, 'Milk'],
        source: SmartInputSource.voice, enableHomeExpenseCategories: true);
    expect(plan.expenseCategory!.requestedNames, ['diner']);
    expect(plan.expenseCategory!.suggestions, ['Dinner']);
    expect(plan.expenseCategory!.category, isNull);
    expect(plan.parsed.title, 'Milk');
    expect(plan.parsed.amount, 120);
  });

  test('prefix priority preserves conflicts, longest names, General and wallets', () {
    final conflict = controller.parse('120 milk category mess category dinner',
        [...names, 'Milk'], source: SmartInputSource.voice, enableHomeExpenseCategories: true);
    expect(conflict.expenseCategory!.category, isNull);
    expect(conflict.expenseCategory!.issue, 'Choose one category for this expense.');
    final longest = controller.parse('120 milk category family dinner', names,
        source: SmartInputSource.voice, enableHomeExpenseCategories: true);
    expect(longest.parsed.category, 'Family Dinner');
    final general = controller.parse('120 milk category General', [...names, 'Milk'],
        source: SmartInputSource.voice, enableHomeExpenseCategories: true);
    expect(general.parsed.category, 'General');
    final wallet = controller.resolveHomeExpenseCategory('120 milk in mess', names,
        source: SmartInputSource.voice,
        accounts: const [SmartEntryAccount(id: 'mess', name: 'Mess', type: 'cash', availableBalance: 0)]);
    expect(wallet!.needsClarification, true);
  });

  test('amount-first confirmed aliases still isolate only the category', () {
    final plan = controller.parse('120 milk category match', [...names, 'Milk'],
        source: SmartInputSource.voice, enableHomeExpenseCategories: true,
        voiceCategoryAliases: {'match': 'Mess'});
    expect(plan.parsed.title, 'Milk');
    expect(plan.parsed.amount, 120);
    expect(plan.parsed.category, 'Mess');
    expect(plan.expenseCategory!.resolution, 'confirmed_alias');
  });

  test('pending category survives duplicate partials and a long pause', () {
    var now = Duration.zero;
    final timing = SpeechTimingTracker(elapsed: () => now)..start();
    final session = SpeechSessionController()..start();
    for (final text in ['120', '120 ka milk', '120 ka milk category',
        '120 ka milk category']) {
      final plan = controller.parse(text, [...names, 'Milk'],
          source: SmartInputSource.voice, enableHomeExpenseCategories: true);
      final complete = policy.evaluate(plan);
      timing.recordTranscript(text, isFinal: false);
      session.recordTranscript(text, isFinal: false, isComplete: complete.isComplete);
    }
    now = const Duration(seconds: 4);
    expect(timing.waitFor(isComplete: false, kind: SpeechTimingKind.transaction), isNull);
    expect(session.latestDraft, '120 ka milk category');
    final completed = controller.parse('120 ka milk category mess', [...names, 'Milk'],
        source: SmartInputSource.voice, enableHomeExpenseCategories: true);
    expect(policy.evaluate(completed).isComplete, true);
    expect(completed.parsed.title, 'Milk');
    expect(completed.parsed.category, 'Mess');
  });

  for (final endedWithError in [false, true]) {
    test('missing category ends once and keeps raw draft (error=$endedWithError)', () {
      final session = SpeechSessionController()..start();
      const text = '120 ka milk category';
      final plan = controller.parse(text, names, source: SmartInputSource.voice,
          enableHomeExpenseCategories: true);
      session.recordTranscript(text, isFinal: false, isComplete: false);
      final decision = endedWithError
          ? session.onRecognizerError(retryable: true)
          : session.onRecognizerStopped(isComplete: false);
      expect(decision.action, SpeechSessionAction.processFinal);
      expect(decision.transcript, text);
      expect(policy.canRecoverCategory(plan), true);
      expect(session.onRecognizerError(retryable: true).action, SpeechSessionAction.none);
      expect(session.onRecognizerStopped().action, SpeechSessionAction.none);
      // Clarification belongs to Home; the shared session emits once and the
      // category remains unresolved until the user explicitly selects a name.
      expect(plan.expenseCategory!.category, isNull);
    });
  }

  for (final pair in [
    ['120 milk category mess', '120 mess'],
    ['120 ka milk category', '120 ka'],
    ['120 milk category diner', '120 diner'],
  ]) {
    test('${pair.first} retains the pre-fix typed interpretation', () {
      final typed = controller.parse(pair.first, ['Milk', 'Mess', 'Dinner'],
          source: SmartInputSource.typed, enableHomeExpenseCategories: true);
      expect(typed.expenseCategory!.category, 'Milk');
      expect(typed.expenseCategory!.cleanedText, pair.last);
      expect(typed.expenseCategory!.issue, isNull);
    });
  }

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
