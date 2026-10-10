/// Result of extracting category instructions, never item keywords.
class ExplicitExpenseCategory {
  final String cleanedText;
  final String? category;
  final String? issue;
  final bool hasAddInstruction;
  final List<String> requestedNames;
  final bool hasCategoryLabel;
  final List<String> suggestions;
  final Map<String, double> suggestionScores;
  final String resolution;
  final List<String> matchedPhrases;

  const ExplicitExpenseCategory({
    required this.cleanedText,
    this.category,
    this.issue,
    this.hasAddInstruction = false,
    this.requestedNames = const [],
    this.hasCategoryLabel = false,
    this.suggestions = const [],
    this.suggestionScores = const {},
    this.resolution = 'exact',
    this.matchedPhrases = const [],
  });

  bool get needsClarification => issue != null;
  bool get isInstructionIncomplete =>
      issue == 'Complete the category name before saving.';
  bool get canSuggest => requestedNames.length == 1 &&
      issue == 'Choose an existing category; the requested category was not found.';
  // Without a matching saved name, a number may be a second expense amount.
  // Keep the original draft for editing instead of subtracting that amount.
  bool get canConfirmVoice => canSuggest && (suggestions.isNotEmpty ||
      !RegExp(r'\d').hasMatch(requestedNames.single));

  ExplicitExpenseCategory withVoiceMatches(List<String> names,
      Map<String, double> scores) => ExplicitExpenseCategory(
    cleanedText: cleanedText, category: category, issue: issue,
    hasAddInstruction: hasAddInstruction, requestedNames: requestedNames,
    hasCategoryLabel: hasCategoryLabel, suggestions: names,
    suggestionScores: scores, resolution: 'suggestion',
    matchedPhrases: matchedPhrases,
  );

  ExplicitExpenseCategory confirmed(String name, {String provenance = 'confirmed'}) =>
      ExplicitExpenseCategory(cleanedText: cleanedText, category: name,
        hasAddInstruction: hasAddInstruction, requestedNames: requestedNames,
        hasCategoryLabel: hasCategoryLabel, suggestions: suggestions,
        suggestionScores: suggestionScores, resolution: provenance,
        matchedPhrases: matchedPhrases);

  ExplicitExpenseCategory withCleanedText(String text) => ExplicitExpenseCategory(
    cleanedText: text, category: category, issue: issue,
    hasAddInstruction: hasAddInstruction, requestedNames: requestedNames,
    hasCategoryLabel: hasCategoryLabel, suggestions: suggestions,
    suggestionScores: suggestionScores, resolution: resolution,
    matchedPhrases: matchedPhrases,
  );
}

class ExplicitExpenseCategoryExtractor {
  const ExplicitExpenseCategoryExtractor();

  ExplicitExpenseCategory? extract(
    String input,
    Iterable<String> categories, {
    Iterable<String> walletNames = const [],
    bool voice = false,
    bool Function(String cleanedText)? preservesExpense,
  }) {
    final names = categories.where((name) => name.trim().isNotEmpty).toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    final spans = <_CategorySpan>[];
    final selected = <String>{};
    final issues = <String>[];
    final requested = <String>{};
    final label = voice ? r'(?:category|catagory)' : 'category';
    final boundary = voice ? _end.replaceFirst('category|', 'category|catagory|') : _end;
    var hasAddInstruction = false;
    final wallets = {'cash', 'jazzcash', 'easypaisa', ...walletNames.map(_key)};

    String pattern(String name) => name.trim().split(RegExp(r'\s+'))
        .map(RegExp.escape).join(r'\s+');
    bool covered(int start, int end) => spans.any(
        (span) => start < span.end && end > span.start);

    String subtract(Iterable<_CategorySpan> removing) {
      final ordered = removing.toList()..sort((a, b) => a.start.compareTo(b.start));
      final cleaned = StringBuffer();
      var cursor = 0;
      for (final span in ordered) {
        if (span.start < cursor) continue;
        cleaned.write(input.substring(cursor, span.start));
        cleaned.write(' ');
        cursor = span.end;
      }
      cleaned.write(input.substring(cursor));
      return cleaned.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    }

    // Reserve complete prefix clauses before any saved-name suffix scan.
    // "milk category mess" must not depend on whether Milk precedes Mess
    // in the dynamic lexicon. Empty/instruction-only values are not prefixes.
    final prefixSpans = voice
        ? RegExp(r'\b' + label + r'\s+(.+?)' + boundary,
            caseSensitive: false).allMatches(input)
            .where((match) => !_missingNames.contains(_key(match.group(1)!)))
            .map((match) => _CategorySpan(match.start, match.end)).toList()
        : const <_CategorySpan>[];
    bool preservesSuffix(RegExpMatch match) => preservesExpense == null ||
        preservesExpense(subtract([...spans, _CategorySpan(match.start, match.end)]));

    for (final name in names) {
      final escaped = pattern(name);
      final patterns = <RegExp>[
        RegExp(r'\b(?:in\s+|into\s+)?' + label + r'\s+' + escaped +
            boundary + _optionalInstruction, caseSensitive: false),
        RegExp(r'\b(?:in\s+|into\s+)?' + escaped +
            r'\s+' + label + r'\b(?:\s+(?:mein|me)\b)?' + _optionalInstruction,
            caseSensitive: false),
        RegExp(r'\b' + escaped + r'\s+(?:mein|me)\b\s+' + _addInstruction,
            caseSensitive: false),
        RegExp(r'\b(?:in|into)\s+' + escaped + boundary +
            r'(?:\s+' + label + r')?' + _optionalInstruction, caseSensitive: false),
      ];
      for (var index = 0; index < patterns.length; index++) {
        for (final match in patterns[index].allMatches(input)) {
          if (covered(match.start, match.end)) continue;
          if (voice && index != 0 && prefixSpans.any(
              (span) => match.start < span.end && match.end > span.start)) continue;
          // Subtraction is tentative: a suffix cannot consume the only item
          // in an amount-first partial such as "120 ka milk category".
          if (voice && index == 1 && !preservesSuffix(match)) continue;
          final clause = match.group(0)!;
          // Unqualified "in X" / "X mein add karo" can also name a wallet.
          if ((index == 2 || index == 3) &&
              !RegExp(r'\b' + label + r'\b', caseSensitive: false).hasMatch(clause) &&
              wallets.contains(_key(name))) {
            issues.add('Name both the category and wallet explicitly.');
          }
          spans.add(_CategorySpan(match.start, match.end));
          selected.add(name);
          hasAddInstruction |= RegExp(_addInstruction, caseSensitive: false)
              .hasMatch(clause);
        }
      }
    }

    // A named category instruction must not disappear into keyword fallback
    // just because the requested category is absent from the dynamic lexicon.
    final unknownPatterns = <RegExp>[
      RegExp(r'\b' + label + r'\s+(.+?)' + boundary +
          (voice ? _optionalInstruction : ''), caseSensitive: false),
      RegExp(r'\b(?:in|into)\s+(.+?)\s+' + label + r'\b' +
          (voice ? _optionalInstruction : ''), caseSensitive: false),
      RegExp((voice ? r'\b(?:in|into)\s+(.+?)' : r'\binto\s+(.+?)') + boundary +
          (voice ? _optionalInstruction : ''), caseSensitive: false),
      RegExp(r'\b([a-z][\w&/+-]*(?:\s+[a-z][\w&/+-]*){0,3})\s+'
          r'(?:mein|me)\b\s+' + _addInstruction, caseSensitive: false),
      if (voice) RegExp(r'\b([a-z][\w&/+-]*(?:\s+[a-z][\w&/+-]*){0,3})\s+' +
          label + r'\b' + _optionalInstruction, caseSensitive: false),
    ];
    for (final expression in unknownPatterns) {
      for (final match in expression.allMatches(input)) {
        if (covered(match.start, match.end)) continue;
        if (voice && expression == unknownPatterns.last && !preservesSuffix(match)) continue;
        var requestedName = _key(match.group(1)!);
        if (voice && RegExp(r'\b(?:mein|me)\b\s+' + _addInstruction,
            caseSensitive: false).hasMatch(match.group(0)!)) {
          requestedName = requestedName.replaceFirst(
              RegExp(r'^(?:kharch|khurch|expense)\s+ka\s+'), '');
        }
        if (wallets.contains(requestedName)) continue;
        final missing = voice && _missingNames.contains(requestedName);
        if (!missing) requested.add(requestedName);
        spans.add(_CategorySpan(match.start, match.end));
        hasAddInstruction |= RegExp(_addInstruction, caseSensitive: false)
            .hasMatch(match.group(0)!);
        issues.add(missing ? 'Complete the category name before saving.'
            : 'Choose an existing category; the requested category was not found.');
      }
    }
    // A bare/trailing anchor is an unfinished instruction, not an implicit item.
    for (final match in RegExp(r'\b' + label + r'\b', caseSensitive: false).allMatches(input)) {
      if (!covered(match.start, match.end)) {
        spans.add(_CategorySpan(match.start, match.end));
        issues.add('Complete the category name before saving.');
      }
    }
    if (voice) {
      final trailing = RegExp(r'\b(?:in|into)\s*[.!?]*$', caseSensitive: false).firstMatch(input);
      if (trailing != null && !covered(trailing.start, trailing.end)) {
        spans.add(_CategorySpan(trailing.start, trailing.end));
        issues.add('Complete the category name before saving.');
      }
    }
    if (spans.isEmpty) return null;
    if (selected.length > 1 || (voice &&
        (requested.length > 1 || (selected.isNotEmpty && requested.isNotEmpty)))) {
      issues.add('Choose one category for this expense.');
    }
    spans.sort((a, b) => a.start.compareTo(b.start));
    return ExplicitExpenseCategory(
      cleanedText: subtract(spans),
      category: issues.isEmpty && selected.length == 1 ? selected.single : null,
      issue: issues.isEmpty ? null : issues.last,
      hasAddInstruction: hasAddInstruction,
      requestedNames: requested.toList(growable: false),
      hasCategoryLabel: RegExp(r'\b' + label + r'\b', caseSensitive: false).hasMatch(input),
      matchedPhrases: spans.map((span) => input.substring(span.start, span.end)).toList(),
    );
  }

  static String _key(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  static const _missingNames = {'me', 'mein', 'add', 'save', 'karo', 'add karo'};

  static const _addInstruction =
      r'(?:add(?:\s+karo|\s+kar\s+do)?|save(?:\s+karo)?|(?:daal|dalo|daalo)(?:\s+do)?)\b';
  static const _optionalInstruction =
      r'(?:\s+(?:mein|me)\b)?(?:\s+' + _addInstruction + r')?';
  // Keep wallet/date/amount clauses available to the existing parser. A word
  // continuing a category name is not a boundary (Dinner != Dinner Party).
  static const _end =
      r'(?![\w\u0600-\u06ff]|\.[\w\u0600-\u06ff])(?=\s*(?:$|[.,;!?]|\b(?:category|in|into|and|aur|then|phir|plus|next|from|se|sy|say|on|today|yesterday|aaj|kal|parso|parson|add|save|daal|dalo|daalo|me|mein)\b))';
}

class _CategorySpan {
  final int start;
  final int end;
  const _CategorySpan(this.start, this.end);
}
