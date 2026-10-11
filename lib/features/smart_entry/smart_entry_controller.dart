import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/local_nlp_service.dart';
import '../../services/smart_command.dart';
import '../../services/smart_input_engine.dart';
import '../../services/explicit_expense_category.dart';
import '../../services/speech_category_matcher.dart';
import '../../services/home_voice_parse_cache.dart';
import '../../services/primary_intent_router.dart';
import 'multi_entry_parser.dart';


/// Feature-level entry point for Smart Entry interpretation.
///
/// Execution remains in the existing transaction layer. This controller owns
/// normalization/parsing so UI widgets do not construct SmartInputEngine
/// directly.
class SmartEntryController {
  final SmartInputEngine _engine;
  late final HomeVoiceParseCache _voiceCache = HomeVoiceParseCache(_engine);

  SmartEntryController({SmartInputEngine? engine})
      : _engine = engine ?? SmartInputEngine();

  void clearHomeVoiceCache() => _voiceCache.clear();

  SmartInputPlan parse(
    String input,
    List<String> categories, {
    required SmartInputSource source,
    Iterable<SmartEntryAccount> accounts = const [],
    ExplicitExpenseCategory? expenseCategory,
    bool enableHomeExpenseCategories = false,
    Map<String, String> voiceCategoryAliases = const {},
    bool enableRomanUrduCategories = false,
  }) {
    final homeVoice = enableHomeExpenseCategories && source == SmartInputSource.voice;
    final accountList = homeVoice ? accounts.toList(growable: false) : accounts;
    if (homeVoice) {
      _voiceCache.prepare(categories, accountList, voiceCategoryAliases, enableRomanUrduCategories);
    }
    final category = expenseCategory ?? (enableHomeExpenseCategories
        ? resolveHomeExpenseCategory(input, categories, source: source, accounts: accountList,
            voiceCategoryAliases: voiceCategoryAliases,
            enableRomanUrduCategories: enableRomanUrduCategories)
        : null);
    if (homeVoice) return _voiceCache.parse(input, categories, accountList, category);
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
    bool enableRomanUrduCategories = false,
  }) {
    final voice = source == SmartInputSource.voice;
    if (!_categoryAnchor.hasMatch(input) &&
        !(voice && RegExp(enableRomanUrduCategories ? r'\b(?:catagory|categrate)\b'
            : r'\bcatagory\b', caseSensitive: false).hasMatch(input))) return null;
    if (voice) _voiceCache.prepare(categories, accounts, voiceCategoryAliases, enableRomanUrduCategories);
    final text = voice ? _voiceCache.normalize(input).normalized
        : _engine.normalizer.normalize(input, enableContextualAsrRepairs: false).normalized;
    if (RegExp(r'\b(nahi|nahin|mat|dont|don\x27t|ya|or)\b').hasMatch(text)) return null;
    final route = const PrimaryIntentRouter().classify(text);
    if (route.intent != RoutedSmartIntent.addExpense &&
        route.intent != RoutedSmartIntent.editEntry &&
        route.intent != RoutedSmartIntent.addIncome) return null;
    const extractor = ExplicitExpenseCategoryExtractor();
    final wallets = accounts.map((account) => account.name);
    final vocabulary = voice && enableRomanUrduCategories ? _voiceCache.vocabulary : null;
    bool supportsCategory(String name) {
      if (vocabulary!.targets(name).isNotEmpty ||
          vocabulary.spellingTargets(name).isNotEmpty) return true;
      return const SpeechCategoryMatcher().match(ExplicitExpenseCategory(
          cleanedText: '', requestedNames: [name], hasCategoryLabel: true,
          issue: 'Choose an existing category; the requested category was not found.'),
          categories, vocabulary: vocabulary, allowSplitWords: true)
          .suggestions.isNotEmpty;
    }
    final checkedBodies = <String, bool>{};
    bool preservesExpense(String candidate) => checkedBodies.putIfAbsent(candidate, () {
      // Numeric-only subtraction cannot retain a specific expense item.
      if (voice && !RegExp(r'[a-z\u0600-\u06ff]', caseSensitive: false).hasMatch(candidate)) return false;
      final parsed = (voice ? _voiceCache.parse(candidate, categories, accounts, null,
          validatingBody: true) : _engine.parse(candidate, categories,
          source: source, accounts: accounts)).parsed;
      return parsed.intent == SmartEntryIntent.addExpense && parsed.amount > 0 &&
          hasSpecificSmartEntryTitle(parsed.title);
    });
    // Match saved names before normalization can remove punctuation from them.
    final raw = extractor.extract(input, categories, walletNames: wallets, voice: voice,
        preservesExpense: voice ? preservesExpense : null, vocabulary: vocabulary,
        supportsCategory: vocabulary == null ? null : supportsCategory) ??
        extractor.extract(text, categories, walletNames: wallets, voice: voice,
            preservesExpense: voice ? preservesExpense : null, vocabulary: vocabulary,
            supportsCategory: vocabulary == null ? null : supportsCategory);
    final extracted = raw == null ? null : raw.withCleanedText(voice
        ? _voiceCache.normalize(raw.cleanedText).normalized
        : _engine.normalizer.normalize(raw.cleanedText, enableContextualAsrRepairs: false).normalized);
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
        confirmedAliases: voiceCategoryAliases, walletNames: wallets,
        vocabulary: vocabulary, allowSplitWords: vocabulary != null,
        allowTrustedRecovery: vocabulary != null) : extracted;
  }
}

final smartEntryControllerProvider = Provider<SmartEntryController>(
  (ref) => SmartEntryController(),
);
