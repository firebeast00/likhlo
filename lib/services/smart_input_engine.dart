import 'local_nlp_service.dart';
import 'pakistani_language_normalizer.dart';
import 'smart_command.dart';

class SmartInputPlan {
  final String originalText;
  final PakistaniNormalizationResult normalization;
  final SmartCommand command;

  const SmartInputPlan({
    required this.originalText,
    required this.normalization,
    required this.command,
  });

  String get normalizedText => normalization.normalized;
  ParsedSmartEntryCommand get parsed => command.parsed;

  bool get requiresAsrReview =>
      command.source == SmartInputSource.voice &&
      (RegExp(r'\d\s*:\s*\d').hasMatch(originalText) ||
          normalization.appliedRules.any(
            (rule) =>
                const {'spent_asr_context', 'pen_asr_context'}.contains(rule),
          ));
}

class SmartInputEngine {
  final PakistaniLanguageNormalizer normalizer;
  final LocalNlpService nlp;

  SmartInputEngine({
    PakistaniLanguageNormalizer? normalizer,
    LocalNlpService? nlp,
  }) : normalizer = normalizer ?? PakistaniLanguageNormalizer(),
       nlp = nlp ?? LocalNlpService();

  SmartInputPlan parse(
    String input,
    List<String> activeCategories, {
    SmartInputSource source = SmartInputSource.typed,
    Iterable<SmartEntryAccount> accounts = const [],
  }) {
    final normalization = normalizer.normalize(
      input,
      enableContextualAsrRepairs: source == SmartInputSource.voice,
    );
    final parsed = nlp.parseCommand(
      normalization.normalized,
      activeCategories,
      accounts: accounts,
    );
    final command = _toTypedCommand(parsed, source);
    return SmartInputPlan(
      originalText: input,
      normalization: normalization,
      command: command,
    );
  }

  SmartCommand _toTypedCommand(
    ParsedSmartEntryCommand parsed,
    SmartInputSource source,
  ) {
    switch (parsed.intent) {
      case SmartEntryIntent.addExpense:
      case SmartEntryIntent.addIncome:
        return AddSmartTransactionCommand(parsed: parsed, source: source);
      case SmartEntryIntent.transfer:
        return TransferCommand(parsed: parsed, source: source);
      case SmartEntryIntent.deleteEntry:
      case SmartEntryIntent.editEntry:
        final interpretation = _interpretMutation(parsed);
        return MutationCommand(
          parsed: parsed,
          source: source,
          selector: interpretation.selector,
          patch: interpretation.patch,
          deleting: parsed.intent == SmartEntryIntent.deleteEntry,
        );
      case SmartEntryIntent.repeatEntry:
        return RepeatCommand(
          parsed: parsed,
          source: source,
          selector: TransactionSelector(
            title: _usefulTitle(parsed.title),
            amount: parsed.amount > 0 ? parsed.amount : null,
            date: parsed.hasExplicitDate ? parsed.date : null,
            transactionType: parsed.entryTypeFilter,
          ),
        );
      case SmartEntryIntent.query:
      case SmartEntryIntent.searchEntries:
      case SmartEntryIntent.navigate:
        return ReadOnlySmartCommand(parsed: parsed, source: source);
      case SmartEntryIntent.unknown:
        return UnknownSmartCommand(parsed: parsed, source: source);
    }
  }

  _MutationInterpretation _interpretMutation(ParsedSmartEntryCommand parsed) {
    final input = parsed.rawInput.toLowerCase();
    final numberPattern = RegExp(
      r'\b\d+(?:\.\d+)?(?:\s*(?:k|thousand|hazar|hazaar|lakh|lac|lak|million|crore|krore|cr))?\b',
    );
    final numbers = numberPattern.allMatches(input).toList();
    double? selectorAmount;
    if (numbers.length > 1) {
      selectorAmount = _numericAmount(numbers.first.group(0)!);
    } else if (parsed.intent == SmartEntryIntent.deleteEntry &&
        parsed.amount > 0) {
      selectorAmount = parsed.amount;
    }

    String? targetTitle = _usefulTitle(parsed.title);
    String? newTitle;
    double? newAmount;
    String? newCategory;

    final titlePatterns = [
      RegExp(
        r'^(?:change|edit|update)\s+(?:the\s+)?(?:title|name|naam)\s+(?:of\s+)?(.+?)\s+(?:to\s+)?(.+?)\s*(?:karo|kar\s+do|badlo)?$',
      ),
      RegExp(
        r'^(?:change|edit|update)?\s*(?:\d+(?:\.\d+)?\s+(?:ki|ka|ke)\s+)?(.+?)\s+(?:ka|ki|ke)?\s*(?:naam|name)\s+(?:to\s+)?(.+?)\s+(?:karo|kar\s+do|badlo|change|update)$',
      ),
      RegExp(r'^(?:change|edit|update)\s+(.+?)\s+(?:name|naam)\s+to\s+(.+)$'),
      RegExp(r'^(.+?)\s+ko\s+(.+?)\s+kar\s+do$'),
    ];
    for (final pattern in titlePatterns) {
      final match = pattern.firstMatch(input);
      if (match == null) continue;
      targetTitle = _cleanMutationText(match.group(1)!);
      newTitle = _titleCase(_cleanMutationText(match.group(2)!));
      if (numbers.isNotEmpty) {
        selectorAmount = _numericAmount(numbers.first.group(0)!);
      }
      break;
    }

    final amountMatch = RegExp(
      r'^(?:change|edit|update)?\s*(.+?)\s+(?:ka|ki|ke)?\s*amount\s+(?:to\s+)?(\d+(?:\.\d+)?(?:\s*(?:k|thousand|hazar|hazaar|lakh|lac|lak|million|crore|krore|cr))?)\s*(?:karo|kar\s+do|change|update)?$',
    ).firstMatch(input);
    if (amountMatch != null) {
      targetTitle = _cleanMutationText(
        amountMatch.group(1)!.replaceFirst(numberPattern, ' '),
      );
      newAmount = _numericAmount(amountMatch.group(2)!);
    } else if (parsed.intent == SmartEntryIntent.editEntry &&
        newTitle == null &&
        parsed.amount > 0) {
      newAmount = parsed.amount;
    }

    final categoryMatch = RegExp(
      r'^(?:change|edit|update)?\s*(.+?)\s+(?:ki|ka|ke)?\s*category\s+(?:to\s+)?(.+?)\s+(?:karo|kar\s+do|badlo|change|update)$',
    ).firstMatch(input);
    if (categoryMatch != null) {
      targetTitle = _cleanMutationText(categoryMatch.group(1)!);
      newCategory = _titleCase(_cleanMutationText(categoryMatch.group(2)!));
    }

    return _MutationInterpretation(
      selector: TransactionSelector(
        title: targetTitle,
        amount: selectorAmount,
        date: parsed.hasExplicitDate ? parsed.date : null,
        transactionType: parsed.entryTypeFilter,
      ),
      patch: parsed.intent == SmartEntryIntent.deleteEntry
          ? const TransactionPatch()
          : TransactionPatch(
              title: newTitle?.isEmpty == true ? null : newTitle,
              amount: newAmount,
              category: newCategory?.isEmpty == true ? null : newCategory,
            ),
    );
  }

  double? _numericAmount(String value) {
    final match = RegExp(
      r'(\d+(?:\.\d+)?)\s*(k|thousand|hazar|hazaar|lakh|lac|lak|million|crore|krore|cr)?\b',
    ).firstMatch(value);
    if (match == null) return null;
    final base = double.tryParse(match.group(1)!);
    if (base == null) return null;
    final scale = match.group(2);
    if (scale == 'k' ||
        scale == 'thousand' ||
        scale == 'hazar' ||
        scale == 'hazaar') {
      return base * 1000;
    }
    if (scale == 'lakh' || scale == 'lac' || scale == 'lak')
      return base * 100000;
    if (scale == 'million') return base * 1000000;
    if (scale == 'crore' || scale == 'krore' || scale == 'cr')
      return base * 10000000;
    return base;
  }

  String? _usefulTitle(String value) {
    final normalized = value.trim();
    const ignored = {'', 'Transaction', 'Quick Expense', 'Income / Allowance'};
    return ignored.contains(normalized) ? null : normalized;
  }

  String _cleanMutationText(String value) {
    return value
        .replaceAll(
          RegExp(
            r'\b(change|edit|update|delete|remove|hatao|karo|kar|do|please)\b',
          ),
          ' ',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _titleCase(String value) {
    return value
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map((part) => part[0].toUpperCase() + part.substring(1))
        .join(' ');
  }
}

class _MutationInterpretation {
  final TransactionSelector selector;
  final TransactionPatch patch;

  const _MutationInterpretation({required this.selector, required this.patch});
}
