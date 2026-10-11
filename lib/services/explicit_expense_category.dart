import 'category_vocabulary.dart';

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
    CategoryVocabulary? vocabulary,
    bool Function(String name)? supportsCategory,
  }) {
    // The new vocabulary is opt-in and cannot change typed extraction.
    final lexicon = voice ? vocabulary : null;
    final names = (lexicon?.names ?? categories)
        .where((name) => name.trim().isNotEmpty).toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    final spans = <_CategorySpan>[];
    final selected = <String>{};
    final issues = <String>[];
    final requested = <String>{};
    final pendingPrefixes = <RegExpMatch>[];
    final label = lexicon != null ? r'(?:category|catagory|categrate)'
        : voice ? r'(?:category|catagory)' : 'category';
    // A following wallet instruction is a separate slot, not part of an
    // unknown category name. Exact full saved names are still tried first.
    final boundary = lexicon != null
        ? _end.replaceFirst('category|', 'category|catagory|categrate|wallet|')
        : voice ? _end.replaceFirst('category|', 'category|catagory|') : _end;
    RegExp compile(String expression) => lexicon == null
        ? RegExp(expression, caseSensitive: false) : _cachedExpression(expression);
    var hasAddInstruction = false;
    var resolution = 'exact';
    var ambiguousSuffix = false;
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
        ? compile(r'\b' + label + r'\s+(.+?)' + boundary).allMatches(input)
            .where((match) => !_missingNames.contains(_key(match.group(1)!)))
            .map((match) => _CategorySpan(match.start, match.end)).toList()
        : const <_CategorySpan>[];
    bool preservesSuffix(RegExpMatch match) => preservesExpense == null ||
        preservesExpense(subtract([...spans, _CategorySpan(match.start, match.end)]));

    for (final name in names) {
      final escaped = pattern(name);
      final patterns = <RegExp>[
        compile(r'\b(?:in\s+|into\s+)?' + label + r'\s+' + escaped +
            boundary + _optionalInstruction),
        compile(r'\b(?:in\s+|into\s+)?' + escaped +
            r'\s+' + label + r'\b(?:\s+(?:mein|me)\b)?' + _optionalInstruction),
        compile(r'\b' + escaped + r'\s+(?:mein|me)\b\s+' + _addInstruction),
        compile(r'\b(?:in|into)\s+' + escaped + boundary +
            r'(?:\s+' + label + r')?' + _optionalInstruction),
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
              !compile(r'\b' + label + r'\b').hasMatch(clause) &&
              (wallets.contains(_key(name)) ||
                  (lexicon?.targets(name).any((target) => wallets.contains(_key(target))) ?? false))) {
            issues.add('Name both the category and wallet explicitly.');
          }
          spans.add(_CategorySpan(match.start, match.end));
          selected.addAll(lexicon?.targets(name) ?? [name]);
          if (lexicon != null && lexicon.provenance(name) != 'exact') {
            resolution = lexicon.provenance(name);
          }
          hasAddInstruction |= compile(_addInstruction)
              .hasMatch(clause);
        }
      }
    }

    // A named category instruction must not disappear into keyword fallback
    // just because the requested category is absent from the dynamic lexicon.
    final unknownPatterns = <RegExp>[
      compile(r'\b' + label + r'\s+(.+?)' + boundary +
          (voice ? _optionalInstruction : '')),
      compile(r'\b(?:in|into)\s+(.+?)\s+' + label + r'\b' +
          (voice ? _optionalInstruction : '')),
      compile((voice ? r'\b(?:in|into)\s+(.+?)' : r'\binto\s+(.+?)') + boundary +
          (voice ? _optionalInstruction : '')),
      compile(r'\b([a-z][\w&/+-]*(?:\s+[a-z][\w&/+-]*){0,3})\s+'
          r'(?:mein|me)\b\s+' + _addInstruction),
      if (voice) compile(r'\b([a-z][\w&/+-]*(?:\s+[a-z][\w&/+-]*){0,3})\s+' +
          label + r'\b' + _optionalInstruction),
    ];
    for (final expression in unknownPatterns) {
      for (final match in expression.allMatches(input)) {
        if (covered(match.start, match.end)) continue;
        var start = match.start;
        var requestedName = _key(match.group(1)!);
        // A suffix may supply the name before "category mein add karo".
        // Defer this instruction-only prefix until suffix recovery has run.
        if (lexicon != null && expression == unknownPatterns.first &&
            _missingNames.contains(requestedName)) {
          pendingPrefixes.add(match);
          continue;
        }
        // "X category mein add karo" belongs to the category suffix pattern,
        // not the unqualified "X mein add karo" wallet/category pattern.
        if (lexicon != null && expression == unknownPatterns[3] &&
            RegExp(r'\b' + label + r'\b', caseSensitive: false).hasMatch(requestedName)) continue;
        if (voice && expression == unknownPatterns.last) {
          if (lexicon != null && preservesExpense != null) {
            final tokens = RegExp(r'[a-z][\w&/+-]*', caseSensitive: false)
                .allMatches(match.group(1)!).toList();
            final candidates = <MapEntry<int, String>>[];
            final separator = tokens.lastIndexWhere((token) => _key(token.group(0)!) == 'ko');
            for (var i = 0; i < tokens.length; i++) {
              if (separator >= 0 && i != separator + 1) continue;
              final name = _key(match.group(1)!.substring(tokens[i].start));
              if (RegExp(r'^(?:ka|ki|ke|ko|me|mein|in|into)\b').hasMatch(name)) continue;
              final candidateStart = match.start + tokens[i].start;
              // With no grammatical boundary, shortening needs evidence from
              // the active vocabulary. Never learn an arbitrary item suffix.
              if (i > 0 && separator < 0 && supportsCategory?.call(name) != true) continue;
              if (preservesExpense(subtract([...spans,
                  _CategorySpan(candidateStart, match.end)]))) {
                candidates.add(MapEntry(candidateStart, name));
              }
            }
            if (candidates.length != 1) {
              ambiguousSuffix |= candidates.length > 1;
              continue;
            }
            start = candidates.single.key;
            requestedName = candidates.single.value;
          } else if (!preservesSuffix(match)) {
            continue;
          }
        }
        if (voice && RegExp(r'\b(?:mein|me)\b\s+' + _addInstruction,
            caseSensitive: false).hasMatch(match.group(0)!)) {
          requestedName = requestedName.replaceFirst(
              RegExp(r'^(?:kharch|khurch|expense)\s+ka\s+'), '');
        }
        if (wallets.contains(requestedName)) continue;
        final missing = voice && _missingNames.contains(requestedName);
        if (!missing) requested.add(requestedName);
        spans.add(_CategorySpan(start, match.end));
        hasAddInstruction |= RegExp(_addInstruction, caseSensitive: false)
            .hasMatch(match.group(0)!);
        issues.add(missing ? 'Complete the category name before saving.'
            : 'Choose an existing category; the requested category was not found.');
      }
    }
    for (final match in pendingPrefixes) {
      if (covered(match.start, match.end)) continue;
      spans.add(_CategorySpan(match.start, match.end));
      issues.add('Complete the category name before saving.');
      hasAddInstruction |= RegExp(_addInstruction, caseSensitive: false)
          .hasMatch(match.group(0)!);
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
    if (ambiguousSuffix || selected.length > 1 || (voice &&
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
      resolution: resolution,
      matchedPhrases: spans.map((span) => input.substring(span.start, span.end)).toList(),
    );
  }

  static final _compiledExpressions = <String, RegExp>{};
  static RegExp _cachedExpression(String expression) {
    final cached = _compiledExpressions[expression];
    if (cached != null) return cached;
    if (_compiledExpressions.length >= 256) {
      _compiledExpressions.remove(_compiledExpressions.keys.first);
    }
    return _compiledExpressions[expression] = RegExp(expression, caseSensitive: false);
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
