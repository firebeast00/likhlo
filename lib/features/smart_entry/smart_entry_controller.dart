import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/local_nlp_service.dart';
import '../../services/smart_command.dart';
import '../../services/smart_input_engine.dart';
import '../../services/explicit_expense_category.dart';
import '../../services/speech_category_matcher.dart';
import '../../services/primary_intent_router.dart';
import 'multi_entry_parser.dart';


/// Feature-level entry point for Smart Entry interpretation.
///
/// Execution remains in the existing transaction layer. This controller owns
/// normalization/parsing so UI widgets do not construct SmartInputEngine
/// directly.
class SmartEntryController {
  final SmartInputEngine _engine;

  SmartEntryController({SmartInputEngine? engine})
      : _engine = engine ?? SmartInputEngine();

  SmartInputPlan parse(
    String input,
    List<String> categories, {
    required SmartInputSource source,
    Iterable<SmartEntryAccount> accounts = const [],
    ExplicitExpenseCategory? expenseCategory,
    bool enableHomeExpenseCategories = false,
    Map<String, String> voiceCategoryAliases = const {},
  }) {
    final category = expenseCategory ?? (enableHomeExpenseCategories
        ? resolveHomeExpenseCategory(input, categories, source: source, accounts: accounts,
            voiceCategoryAliases: voiceCategoryAliases)
        : null);
    return _engine.parse(
      input,
      categories,
      source: source,
      accounts: accounts,
      expenseCategory: category,
    );
  }

  static final _categoryAnchor = RegExp(
    r'\b(?:category|in|into|me|mein)\b|میں', caseSensitive: false);

  /// Opt-in only for Home single expenses; batch and other intent paths stay
  /// on the original engine. Full-text routing/negation precedes subtraction.
  ExplicitExpenseCategory? resolveHomeExpenseCategory(
    String input,
    List<String> categories, {
    required SmartInputSource source,
    Iterable<SmartEntryAccount> accounts = const [],
    Map<String, String> voiceCategoryAliases = const {},
  }) {
    final voice = source == SmartInputSource.voice;
    if (!_categoryAnchor.hasMatch(input) &&
        !(voice && RegExp(r'\bcatagory\b', caseSensitive: false).hasMatch(input))) return null;
    final text = _engine.normalizer.normalize(input,
        enableContextualAsrRepairs: source == SmartInputSource.voice).normalized;
    if (RegExp(r'\b(nahi|nahin|mat|dont|don\x27t|ya|or)\b').hasMatch(text)) return null;
    final route = const PrimaryIntentRouter().classify(text);
    if (route.intent != RoutedSmartIntent.addExpense &&
        route.intent != RoutedSmartIntent.editEntry &&
        route.intent != RoutedSmartIntent.addIncome) return null;
    const extractor = ExplicitExpenseCategoryExtractor();
    final wallets = accounts.map((account) => account.name);
    bool preservesExpense(String candidate) {
      final parsed = _engine.parse(candidate, categories,
          source: source, accounts: accounts).parsed;
      return parsed.intent == SmartEntryIntent.addExpense && parsed.amount > 0 &&
          hasSpecificSmartEntryTitle(parsed.title);
    }
    // Match saved names before normalization can remove punctuation from them.
    final raw = extractor.extract(input, categories, walletNames: wallets, voice: voice,
        preservesExpense: voice ? preservesExpense : null) ??
        extractor.extract(text, categories, walletNames: wallets, voice: voice,
            preservesExpense: voice ? preservesExpense : null);
    final extracted = raw == null ? null : raw.withCleanedText(_engine.normalizer.normalize(raw.cleanedText,
        enableContextualAsrRepairs: voice).normalized);
    if (extracted == null) return null;
    if (route.intent == RoutedSmartIntent.editEntry ||
        route.intent == RoutedSmartIntent.addIncome) {
      if (!extracted.hasAddInstruction ||
          RegExp(r'\b(edit|change|update|modify|correct|badal|badlo|theek)\b').hasMatch(text) ||
          const PrimaryIntentRouter().classify(extracted.cleanedText).intent !=
              RoutedSmartIntent.addExpense) return null;
    }
    if (const MultiEntryParser().tryParseBatch(extracted.cleanedText) != null) return null;
    return voice ? const SpeechCategoryMatcher().match(extracted, categories,
        confirmedAliases: voiceCategoryAliases, walletNames: wallets) : extracted;
  }
}

final smartEntryControllerProvider = Provider<SmartEntryController>(
  (ref) => SmartEntryController(),
);
