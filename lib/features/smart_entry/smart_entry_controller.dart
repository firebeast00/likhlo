import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/local_nlp_service.dart';
import '../../services/smart_command.dart';
import '../../services/smart_input_engine.dart';
import '../../services/explicit_expense_category.dart';
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
  }) {
    final category = expenseCategory ?? (enableHomeExpenseCategories
        ? resolveHomeExpenseCategory(input, categories, source: source, accounts: accounts)
        : null);
    return _engine.parse(
      input,
      categories,
      source: source,
      accounts: accounts,
      expenseCategory: category,
    );
  }

  /// Opt-in only for Home single expenses; batch and other intent paths stay
  /// on the original engine. Full-text routing/negation precedes subtraction.
  ExplicitExpenseCategory? resolveHomeExpenseCategory(
    String input,
    List<String> categories, {
    required SmartInputSource source,
    Iterable<SmartEntryAccount> accounts = const [],
  }) {
    final text = _engine.normalizer.normalize(input,
        enableContextualAsrRepairs: source == SmartInputSource.voice).normalized;
    if (RegExp(r'\b(nahi|nahin|mat|dont|don\x27t|ya|or)\b').hasMatch(text)) return null;
    final route = const PrimaryIntentRouter().classify(text);
    if (route.intent != RoutedSmartIntent.addExpense &&
        route.intent != RoutedSmartIntent.editEntry &&
        route.intent != RoutedSmartIntent.addIncome) return null;
    const extractor = ExplicitExpenseCategoryExtractor();
    final wallets = accounts.map((account) => account.name);
    // Match saved names before normalization can remove punctuation from them.
    final raw = extractor.extract(input, categories, walletNames: wallets) ??
        extractor.extract(text, categories, walletNames: wallets);
    final extracted = raw == null ? null : ExplicitExpenseCategory(
      cleanedText: _engine.normalizer.normalize(raw.cleanedText,
          enableContextualAsrRepairs: source == SmartInputSource.voice).normalized,
      category: raw.category, issue: raw.issue,
      hasAddInstruction: raw.hasAddInstruction,
    );
    if (extracted == null) return null;
    if (route.intent == RoutedSmartIntent.editEntry ||
        route.intent == RoutedSmartIntent.addIncome) {
      if (!extracted.hasAddInstruction ||
          RegExp(r'\b(edit|change|update|modify|correct|badal|badlo|theek)\b').hasMatch(text) ||
          const PrimaryIntentRouter().classify(extracted.cleanedText).intent !=
              RoutedSmartIntent.addExpense) return null;
    }
    if (const MultiEntryParser().tryParseBatch(extracted.cleanedText) != null ||
        (extracted.needsClarification &&
            const MultiEntryParser().tryParseBatch(text) != null)) return null;
    return extracted;
  }
}

final smartEntryControllerProvider = Provider<SmartEntryController>(
  (ref) => SmartEntryController(),
);
