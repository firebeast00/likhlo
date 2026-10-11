import 'dart:convert';

import 'category_vocabulary.dart';
import 'explicit_expense_category.dart';
import 'local_nlp_service.dart';
import 'pakistani_language_normalizer.dart';
import 'smart_command.dart';
import 'smart_input_engine.dart';
import 'voice_diagnostic_observer.dart';

/// Bounded reuse for Home voice category updates, never a save decision.
/// A category-only partial must not reparse an unchanged expense body.
class HomeVoiceParseCache {
  final SmartInputEngine engine;
  String? _context;
  final _age = Stopwatch()..start();
  final _normalizations = <String, PakistaniNormalizationResult>{};
  final _bodies = <String, SmartInputPlan>{};
  CategoryVocabulary? vocabulary;

  HomeVoiceParseCache(this.engine);

  void clear() {
    _context = null;
    vocabulary = null;
    _normalizations.clear();
    _bodies.clear();
    _age.reset();
  }

  void prepare(List<String> categories, Iterable<SmartEntryAccount> accounts,
      Map<String, String> aliases, bool romanUrdu) {
    final now = DateTime.now();
    final context = jsonEncode([
      categories, aliases, romanUrdu, now.year, now.month, now.day,
      for (final account in accounts)
        [account.id, account.name, account.type, account.availableBalance.toString(),
          account.isBackup],
    ]);
    if (_context == context && _age.elapsed < const Duration(seconds: 30)) return;
    clear();
    _context = context;
    vocabulary = romanUrdu
        ? CategoryVocabulary.build(categories, confirmedAliases: aliases) : null;
  }

  PakistaniNormalizationResult normalize(String input) {
    final cached = _normalizations[input];
    if (cached != null) return cached;
    final value = engine.normalizer.normalize(input, enableContextualAsrRepairs: true);
    if (_normalizations.length >= 16) _normalizations.remove(_normalizations.keys.first);
    _normalizations[input] = value;
    return value;
  }

  SmartInputPlan parse(String input, List<String> categories,
      Iterable<SmartEntryAccount> accounts, ExplicitExpenseCategory? category,
      {bool validatingBody = false}) {
    // Ordinary voice commands continue through the original engine. Reuse is
    // limited to an explicit category or its tentative subtraction validator.
    final key = category != null || validatingBody
        ? jsonEncode([category?.cleanedText ?? normalize(input).normalized,
            category?.category]) : null;
    final cached = key == null ? null : _bodies[key];
    if (cached != null) {
      final parsed = cached.parsed;
      final now = DateTime.now();
      // The original parser uses today's clock for today/yesterday/parso.
      // Preserve the parsed calendar date while refreshing that clock.
      final refreshed = ParsedSmartEntryCommand(
        rawInput: parsed.rawInput, intent: parsed.intent, amount: parsed.amount,
        title: parsed.title, category: parsed.category,
        date: DateTime(parsed.date.year, parsed.date.month, parsed.date.day,
            now.hour, now.minute, now.second, now.millisecond, now.microsecond),
        hasExplicitDate: parsed.hasExplicitDate, confidence: parsed.confidence,
        confidenceByField: parsed.confidenceByField,
        clarificationReasons: parsed.clarificationReasons,
        queryMetric: parsed.queryMetric, timeRange: parsed.timeRange,
        navigationTarget: parsed.navigationTarget, appAction: parsed.appAction,
        entryTypeFilter: parsed.entryTypeFilter,
      );
      final normalization = normalize(input);
      if (VoiceDiagnosticObserver.active) {
        VoiceDiagnosticObserver.stage('normalization', {
          'original': input, 'normalized': normalization.normalized,
          'applied_rules': normalization.appliedRules,
        });
        VoiceDiagnosticObserver.stage('parse', {
          'intent': refreshed.intent.wireName, ...refreshed.toLegacyMap(),
          'reused_expense_body': true,
          'explicit_category': {
            'category': category?.category, 'issue': category?.issue,
            'parsing_text': category?.cleanedText,
            'requested_names': category?.requestedNames,
            'resolution': category?.resolution,
            'suggestions': category?.suggestions,
          },
        });
      }
      return SmartInputPlan(originalText: input, normalization: normalization,
          command: AddSmartTransactionCommand(parsed: refreshed, source: SmartInputSource.voice),
          expenseCategory: category);
    }
    final plan = engine.parse(input, categories, source: SmartInputSource.voice,
        accounts: accounts, expenseCategory: category);
    if (_normalizations.length >= 16) _normalizations.remove(_normalizations.keys.first);
    _normalizations[input] = plan.normalization;
    if (plan.parsed.intent == SmartEntryIntent.addExpense) {
      if (_bodies.length >= 8) _bodies.remove(_bodies.keys.first);
      _bodies[jsonEncode([category?.cleanedText ?? plan.normalization.normalized,
          category?.category])] = plan;
    }
    return plan;
  }
}
