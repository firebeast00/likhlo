import 'package:flutter_test/flutter_test.dart';
import 'package:student_expense_manager/features/smart_entry/smart_entry_controller.dart';
import 'package:student_expense_manager/services/explicit_expense_category.dart';
import 'package:student_expense_manager/services/home_category_speech_policy.dart';
import 'package:student_expense_manager/services/local_nlp_service.dart';
import 'package:student_expense_manager/services/smart_command.dart';
import 'package:student_expense_manager/services/smart_input_engine.dart';
import 'package:student_expense_manager/services/speech_category_matcher.dart';
import 'package:student_expense_manager/services/category_vocabulary.dart';
import 'package:student_expense_manager/services/confidence_evaluator.dart';
import 'package:student_expense_manager/services/speech_session_controller.dart';
import 'package:student_expense_manager/services/speech_timing_policy.dart';

void main() {
  const names = ['General', 'Food', 'Dinner', 'Family Dinner', 'Zong Package', 'Food 2', 'C++', 'Mess'];
  final controller = SmartEntryController();
  const matcher = SpeechCategoryMatcher();
  const policy = HomeCategorySpeechPolicy();

  group('phone category review and parse reuse', () {
    const active = ['General', 'Food', 'Mess', 'Health', 'Ghar Ka Saman', 'Karobar'];
    const wallets = [SmartEntryAccount(id: 'jazz', name: 'JazzCash', type: 'jazzcash', availableBalance: 10000)];
    SmartInputPlan voice(SmartEntryController parser, String text,
        {List<String> categories = active, Iterable<SmartEntryAccount> accounts = wallets,
        Map<String, String> aliases = const {}}) => parser.parse(text, categories,
        source: SmartInputSource.voice, accounts: accounts,
        enableHomeExpenseCategories: true, enableRomanUrduCategories: true,
        voiceCategoryAliases: aliases);

    for (final category in ['Karobar', 'Karobarr']) {
      test('category $category cannot consume the following wallet', () {
        final plan = voice(SmartEntryController(),
            '8000 rakshe pe kharch hue category $category wallet jazzcash');
        expect(plan.normalizedText, '8000 rakshe pe kharch hue wallet jazzcash');
        expect(plan.parsed.amount, 8000);
        expect(plan.parsed.title.toLowerCase(), contains('rakshe'));
        expect(findMentionedSmartEntryAccountId(plan.normalizedText, wallets), 'jazz');
        expect(resolveSmartEntryAccount(input: plan.normalizedText, accounts: wallets,
            transactionType: 'expense', amount: 8000), 'jazz');
        if (category == 'Karobar') {
          expect(plan.parsed.category, 'Karobar');
          expect(plan.expenseCategory!.needsClarification, false);
          expect(const ConfidenceEvaluator().evaluate(plan.command,
              context: const ConfidenceContext(hasExactAmount: true, hasResolvedWallet: true))
              .canAutoExecute, true);
        } else {
          expect(plan.expenseCategory!.requestedNames, ['karobarr']);
          expect(plan.expenseCategory!.needsClarification, true);
        }
      });
    }

    test('wallet inside an exact full category name remains part of that name', () {
      final plan = voice(SmartEntryController(),
          '120 milk category Karobar Wallet Plan wallet jazzcash',
          categories: [...active, 'Karobar Wallet Plan']);
      expect(plan.parsed.category, 'Karobar Wallet Plan');
      expect(plan.normalizedText, '120 milk wallet jazzcash');
    });

    test('observed categrate anchor is scoped to Roman Urdu Home voice', () {
      const input = '250 ki shakkar categrate ghar ka saman';
      final plan = voice(SmartEntryController(), input);
      expect(plan.parsed.amount, 250);
      expect(plan.parsed.title, 'Shakkar');
      expect(plan.parsed.category, 'Ghar Ka Saman');
      expect(plan.normalizedText, '250 ki shakkar');
      for (final source in SmartInputSource.values) {
        final legacy = SmartEntryController().parse(input, active, source: source,
            enableHomeExpenseCategories: true);
        expect(legacy.expenseCategory, isNull);
      }
    });

    test('category-only partials and final processing reuse an unchanged body', () {
      final engine = _CountingEngine();
      final parser = SmartEntryController(engine: engine);
      voice(parser, '120 milk');
      expect(engine.calls, 1);
      for (final input in ['120 milk category', '120 milk category off',
          '120 milk category office', '120 milk category office lunch']) {
        final plan = voice(parser, input);
        expect(plan.parsed.amount, 120);
        expect(plan.parsed.title, 'Milk');
      }
      expect(engine.calls, 1);
      final resolved = voice(parser, '120 milk category Mess');
      expect(resolved.parsed.category, 'Mess');
      expect(engine.calls, 2);
      final finalPlan = voice(parser, '120 milk category Mess');
      expect(finalPlan.expenseCategory!.matchedPhrases, resolved.expenseCategory!.matchedPhrases);
      expect(engine.calls, 2);
    });

    test('amount, title and wallet changes must be parsed again', () {
      final engine = _CountingEngine();
      final parser = SmartEntryController(engine: engine);
      final first = voice(parser, '120 milk category Mess');
      expect(first.parsed.amount, 120);
      expect(voice(parser, '250 milk category Mess').parsed.amount, 250);
      expect(voice(parser, '250 bread category Mess').parsed.title, 'Bread');
      final wallet = voice(parser, '250 bread category Mess wallet jazzcash');
      expect(wallet.normalizedText, contains('wallet jazzcash'));
      expect(engine.calls, 4);
    });

    test('active names, balances, aliases and session reset invalidate reuse', () {
      final engine = _CountingEngine();
      final parser = SmartEntryController(engine: engine);
      const raw = '120 milk category match';
      voice(parser, raw);
      voice(parser, raw, aliases: {'match': 'Mess'});
      expect(engine.calls, 2);
      final changedBalance = voice(parser, raw, aliases: {'match': 'Mess'}, accounts: const [
        SmartEntryAccount(id: 'jazz', name: 'JazzCash', type: 'jazzcash', availableBalance: 0)]);
      expect(changedBalance.parsed.category, 'Mess');
      expect(engine.calls, 3);
      final exact = voice(parser, raw, categories: [...active, 'match'], aliases: {'match': 'Mess'});
      expect(exact.parsed.category, 'match');
      expect(engine.calls, 4);
      parser.clearHomeVoiceCache();
      voice(parser, raw, categories: [...active, 'match'], aliases: {'match': 'Mess'});
      expect(engine.calls, 5);
    });

    test('reused body retains primary transcript ASR review and calendar date', () {
      final parser = SmartEntryController();
      final plain = voice(parser, '120 milk category office yesterday');
      final corrected = voice(parser, '120:00 milk category office yesterday');
      expect(corrected.originalText, '120:00 milk category office yesterday');
      expect(corrected.requiresAsrReview, true);
      expect(corrected.parsed.date.year, plain.parsed.date.year);
      expect(corrected.parsed.date.month, plain.parsed.date.month);
      expect(corrected.parsed.date.day, plain.parsed.date.day);
    });

    test('word amount confidence and unresolved wallet still require review', () {
      final plan = voice(SmartEntryController(), 'dhai sau ki shakkar category ghar ka saman');
      expect(plan.parsed.amount, 250);
      final confidence = const ConfidenceEvaluator().evaluate(plan.command,
          context: ConfidenceContext(hasResolvedWallet: true,
              hasExactAmount: (plan.parsed.confidenceByField['amount'] ?? 0) >= .9));
      expect(confidence.canAutoExecute, false);
      final unknown = voice(SmartEntryController(), '250 shakkar category gharr');
      expect(unknown.expenseCategory!.needsClarification, true);
      expect(const ConfidenceEvaluator().evaluate(unknown.command,
          context: const ConfidenceContext(hasResolvedWallet: false, hasExactAmount: true))
          .canAutoExecute, false);
    });

    test('partial stream latency reports cold body parsing separately from reuse', () {
      final parser = SmartEntryController();
      final watch = Stopwatch()..start();
      voice(parser, '120 milk');
      watch.stop();
      final cold = watch.elapsedMicroseconds;
      watch.reset();
      watch.start();
      for (final suffix in ['category', 'category off', 'category office',
          'category office lunch', 'category office lunch']) {
        voice(parser, '120 milk $suffix');
      }
      watch.stop();
      print('Phone-flow latency sample: cold_body_us=$cold category_update_mean_us=${watch.elapsedMicroseconds / 5}');
    });
  });

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

  group('Roman Urdu Home category vocabulary', () {
    const active = ['General', 'Food', 'Transport', 'Shopping', 'Entertainment',
      'Health', 'Education', 'Mess', 'Office Lunch', 'Ghar ka kharch'];
    SmartInputPlan parse(String input, {List<String> categories = active,
        Map<String, String> aliases = const {}}) => controller.parse(input, categories,
        source: SmartInputSource.voice, enableHomeExpenseCategories: true,
        enableRomanUrduCategories: true, voiceCategoryAliases: aliases);

    for (final pair in [
      ['Aam', 'General'], ['Khana', 'Food'], ['Safar', 'Transport'],
      ['Khareedari', 'Shopping'], ['kharidari', 'Shopping'],
      ['Tafreeh', 'Entertainment'], ['Sehat', 'Health'], ['Taleem', 'Education'],
    ]) {
      for (final input in [
        '200 ka charger category ${pair.first}',
        '200 ka charger ko ${pair.first} category mein add karo',
      ]) {
        test('$input resolves the active canonical category instantly', () {
          final plan = parse(input);
          expect(plan.parsed.amount, 200);
          expect(plan.parsed.title, 'Charger');
          expect(plan.parsed.category, pair.last);
          expect(plan.expenseCategory!.needsClarification, false);
          expect(plan.expenseCategory!.resolution, 'translated_alias');
          expect(policy.evaluate(plan).isComplete, true);
          final confidence = const ConfidenceEvaluator().evaluate(plan.command,
              context: const ConfidenceContext(hasExactAmount: true, hasResolvedWallet: true));
          expect(confidence.canAutoExecute, true);
        });
      }
    }

    for (final name in ['Sehat', 'Office Lunch', 'Ghar ka kharch', 'C++', 'Food 2']) {
      test('new custom $name remains an exact canonical name', () {
        final plan = parse('milk 120 category $name', categories: [...active, name],
            aliases: {name.toLowerCase(): 'Food'});
        expect(plan.parsed.category, name);
        expect(plan.expenseCategory!.resolution, 'exact');
        expect(plan.expenseCategory!.needsClarification, false);
      });
    }

    test('translation and learned-alias disagreement cannot silently win', () {
      final plan = parse('milk 120 category sehat', aliases: {'sehat': 'Food'});
      expect(plan.expenseCategory!.category, isNull);
      expect(plan.expenseCategory!.needsClarification, true);
    });

    for (final aliases in [{' SEHAT  ': 'Deleted'}, {'sehat': 'Medical'}]) {
      test('inactive learned alias ${aliases.values.single} does not replace Health', () {
        expect(parse('milk 120 category sehat', aliases: aliases).parsed.category, 'Health');
      });
    }

    test('inactive built-in names are never restored by translation', () {
      final plan = parse('milk 120 category sehat', categories: ['General', 'Food']);
      expect(plan.expenseCategory!.category, isNull);
      expect(plan.expenseCategory!.needsClarification, true);
      expect(plan.expenseCategory!.requestedNames, ['sehat']);
    });

    test('a stale vocabulary snapshot cannot resolve a removed category', () {
      const request = ExplicitExpenseCategory(cleanedText: 'milk 120',
          issue: 'Choose an existing category; the requested category was not found.',
          requestedNames: ['sehat'], hasCategoryLabel: true);
      final result = matcher.match(request, ['General'],
          vocabulary: CategoryVocabulary.build(active), allowSplitWords: true);
      expect(result.category, isNull);
      expect(result.suggestions, isEmpty);
    });

    for (final pair in [['the free', 'Entertainment'], ['match', 'Mess'], ['set', 'Health']]) {
      test('confirmed ${pair.first} alias handles prefix and suffix without guessing', () {
        for (final input in ['120 milk category ${pair.first}',
            '120 milk ko ${pair.first} category mein add karo']) {
          final plan = parse(input, aliases: {'  ${pair.first.toUpperCase()}  ': pair.last});
          expect(plan.parsed.amount, 120);
          expect(plan.parsed.title, 'Milk');
          expect(plan.parsed.category, pair.last);
          expect(plan.expenseCategory!.resolution, 'confirmed_alias');
        }
      });
    }

    test('unknown suffix after ko retains the item and clean learnable phrase', () {
      final plan = parse('200 ka charger ko set category mein add karo');
      expect(plan.expenseCategory!.requestedNames, ['set']);
      expect(plan.expenseCategory!.cleanedText, '200 ka charger ko');
      expect(plan.parsed.amount, 200);
      expect(plan.parsed.title, 'Charger');
      expect(plan.expenseCategory!.category, isNull);
      expect(plan.expenseCategory!.canConfirmVoice, true);
      expect(plan.expenseCategory!.suggestions, isEmpty);
    });

    for (final input in ['milk 120 category office lunch',
        '120 milk office lunch category mein add karo']) {
      test('$input offers a joined-name suggestion without selecting it', () {
        final plan = parse(input, categories: ['General', 'OfficeLunch']);
        expect(plan.parsed.amount, 120);
        expect(plan.parsed.title, 'Milk');
        expect(plan.expenseCategory!.requestedNames, ['office lunch']);
        expect(plan.expenseCategory!.suggestions, ['OfficeLunch']);
        expect(plan.expenseCategory!.category, isNull);
        expect(plan.expenseCategory!.needsClarification, true);
      });
    }

    test('fuzzy matching compares localized labels but returns canonical suggestions', () {
      final plan = parse('milk 120 category sehatt');
      expect(plan.expenseCategory!.suggestions, ['Health']);
      expect(plan.expenseCategory!.category, isNull);
      expect(plan.expenseCategory!.needsClarification, true);
    });

    test('split-word recovery does not weaken the edit budget', () {
      final plan = parse('milk 120 category the free');
      expect(plan.expenseCategory!.category, isNull);
      expect(plan.expenseCategory!.suggestions, isEmpty);
      expect(plan.expenseCategory!.canConfirmVoice, true);
    });

    for (final input in ['120 milk category', '120 ka milk category',
        '120 milk catagory', '120 category']) {
      test('$input cannot lose its only item through new suffix recovery', () {
        final plan = parse(input, categories: [...active, 'Milk']);
        expect(plan.expenseCategory!.isInstructionIncomplete, true);
        expect(plan.expenseCategory!.category, isNull);
        if (input.contains('milk')) expect(plan.parsed.title, 'Milk');
        expect(policy.canRecoverCategory(plan), input.contains('120') && input.contains('milk'));
      });
    }

    test('a missing amount cannot be repaired by choosing a category', () {
      final plan = parse('milk category', categories: [...active, 'Milk']);
      expect(plan.parsed.amount, 0);
      expect(plan.expenseCategory?.category, isNull);
      expect(policy.canRecoverCategory(plan), false);
    });

    for (final ordered in [['Milk', 'Mess', ...active], ['Mess', 'Milk', ...active]]) {
      test('prefix reservation survives vocabulary ordering ${ordered.first}', () {
        final plan = parse('120 milk category mess', categories: ordered);
        expect(plan.parsed.title, 'Milk');
        expect(plan.parsed.amount, 120);
        expect(plan.parsed.category, 'Mess');
      });
    }

    test('ambiguous suffix boundaries retain the draft instead of learning item text', () {
      final plan = parse('120 milk family lunchh category',
          categories: ['General', 'Family Lunch', 'Lunch']);
      expect(plan.expenseCategory!.isInstructionIncomplete, false);
      expect(plan.expenseCategory!.needsClarification, true);
      expect(policy.canRecoverCategory(plan), false);
      expect(plan.expenseCategory!.requestedNames, isEmpty);
      expect(plan.expenseCategory!.category, isNull);
      expect(plan.expenseCategory!.cleanedText, contains('milk family lunchh'));
    });

    test('ordinary item synonyms are not approved category translations', () {
      final vocabulary = CategoryVocabulary.build(active);
      for (final word in ['dinner', 'movie', 'medical', 'clothes', 'school']) {
        expect(vocabulary.targets(word), isEmpty);
      }
    });

    test('digits and punctuation remain protected even in learned aliases', () {
      final vocabulary = CategoryVocabulary.build(['Food 2', 'C++', 'Health'],
          confirmedAliases: {'food 3': 'Food 2', 'c+': 'C++', 'sehat': 'Health'});
      expect(vocabulary.targets('food 3'), isEmpty);
      expect(vocabulary.targets('c+'), isEmpty);
      expect(vocabulary.targets('sehat'), ['Health']);
    });

    for (final input in [
      'salary 5000 category sehat', 'delete milk 120 category sehat',
      'change milk 120 category sehat', 'search category sehat',
      'total spent in march', 'send 120 from cash to jazzcash',
      'udhar 120 category sehat', 'milk 120 and bread 80 category sehat',
      'milk 120 category sehat nahi',
    ]) {
      test('$input remains outside new Roman Urdu recovery', () {
        expect(controller.resolveHomeExpenseCategory(input, active,
            source: SmartInputSource.voice, enableRomanUrduCategories: true), isNull);
      });
    }

    test('typed callers ignore Roman Urdu recovery even when explicitly enabled', () {
      Map<String, dynamic> comparable(ParsedSmartEntryCommand parsed) =>
          parsed.toLegacyMap()..['date'] = DateTime(
              parsed.date.year, parsed.date.month, parsed.date.day);
      for (final input in ['120 milk category mess', 'milk 120 category sehat',
          '120 ka milk category', 'milk 120 category office lunch']) {
        // The parser retains clock time even for yesterday. Compare calendar
        // dates and every other field, rather than two separate now() values.
        final previous = controller.parse('$input yesterday', [...active, 'Milk'],
            source: SmartInputSource.typed, enableHomeExpenseCategories: true);
        final current = controller.parse('$input yesterday', [...active, 'Milk'],
            source: SmartInputSource.typed, enableHomeExpenseCategories: true,
            enableRomanUrduCategories: true);
        expect(comparable(current.parsed), comparable(previous.parsed));
        expect(current.expenseCategory!.cleanedText, previous.expenseCategory!.cleanedText);
        expect(current.expenseCategory!.issue, previous.expenseCategory!.issue);
      }
    });

    test('English/default and opted-out callers keep translation recovery disabled', () {
      final english = controller.parse('milk 120 category sehat', active,
          source: SmartInputSource.voice, enableHomeExpenseCategories: true);
      expect(english.expenseCategory!.category, isNull);
      final optedOut = controller.parse('milk 120 category sehat', active,
          source: SmartInputSource.voice, enableRomanUrduCategories: true);
      expect(optedOut.expenseCategory, isNull);
    });

    test('translated category leaves wallet and date clauses untouched', () {
      const raw = 'milk 120 category sehat from JazzCash yesterday';
      final selection = const ExplicitExpenseCategoryExtractor().extract(raw, active,
          voice: true, vocabulary: CategoryVocabulary.build(active))!;
      expect(selection.cleanedText, 'milk 120 from JazzCash yesterday');
      expect(selection.category, 'Health');
      expect(selection.matchedPhrases.single.toLowerCase(), 'category sehat');
    });

    test('new category path latency sample uses the unchanged parser and timing', () {
      final samples = ['milk 120 category Mess', '200 ka charger category sehat',
        '200 ka charger ko set category mein add karo'];
      for (final enabled in [false, true]) {
        final watch = Stopwatch()..start();
        for (var i = 0; i < 30; i++) {
          for (final input in samples) {
            controller.parse(input, active, source: SmartInputSource.voice,
                enableHomeExpenseCategories: true, enableRomanUrduCategories: enabled);
          }
        }
        watch.stop();
        print('Category latency sample: enabled=$enabled '
            'mean_us=${watch.elapsedMicroseconds / 90} (not an endpoint delay)');
      }
    });
  });
}

class _CountingEngine extends SmartInputEngine {
  int calls = 0;
  @override
  SmartInputPlan parse(String input, List<String> activeCategories, {
    SmartInputSource source = SmartInputSource.typed,
    Iterable<SmartEntryAccount> accounts = const [],
    ExplicitExpenseCategory? expenseCategory,
  }) {
    calls++;
    return super.parse(input, activeCategories, source: source,
        accounts: accounts, expenseCategory: expenseCategory);
  }
}
