import 'explicit_expense_category.dart';

/// Suggestions apply only to an isolated, explicitly requested category.
/// Scores rank candidates; they are not execution confidence or probabilities.
class SpeechCategoryMatcher {
  const SpeechCategoryMatcher();

  static String aliasKey(String name) => name.trim().toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ');

  ExplicitExpenseCategory match(ExplicitExpenseCategory extracted,
      Iterable<String> categories, {Map<String, String> confirmedAliases = const {},
      Iterable<String> walletNames = const []}) {
    // Exact matches, unfinished instructions and conflicting instructions win.
    if (!extracted.canSuggest) return extracted;
    final requested = aliasKey(extracted.requestedNames.single);
    if (requested.isEmpty || requested.length > 80) return extracted;
    final names = categories.toList(growable: false);
    bool allowed(String name) => extracted.hasCategoryLabel ||
        !{'cash', 'jazzcash', 'easypaisa', ...walletNames.map(aliasKey)}
            .contains(aliasKey(name));

    // User-confirmed aliases only. A new exact category always supersedes one.
    final exact = names.where((name) => aliasKey(name) == requested);
    if (exact.length == 1 && allowed(exact.single)) {
      return extracted.confirmed(exact.single, provenance: 'exact');
    }
    if (exact.length > 1) return extracted;
    final alias = confirmedAliases[requested];
    if (alias != null && names.contains(alias) && allowed(alias) &&
        _identifiers(requested) == _identifiers(aliasKey(alias))) {
      return extracted.confirmed(alias, provenance: 'confirmed_alias');
    }

    // Short names are especially collision-prone; never fuzzy-match them.
    final compact = requested.replaceAll(' ', '');
    if (compact.length < 5) return extracted;
    final ranked = <MapEntry<String, double>>[];
    for (final name in names) {
      if (!allowed(name)) continue;
      final target = aliasKey(name);
      final targetCompact = target.replaceAll(' ', '');
      if (targetCompact.length < 5 || targetCompact.length > 80 ||
          requested.split(' ').length != target.split(' ').length ||
          _identifiers(requested) != _identifiers(target)) continue;
      final maxLength = compact.length > targetCompact.length
          ? compact.length : targetCompact.length;
      final budget = maxLength >= 9 ? 2 : 1;
      if ((compact.length - targetCompact.length).abs() > budget) continue;
      final edits = _distance(compact, targetCompact);
      if (edits > budget) continue;
      final lexical = 1 - edits / maxLength;
      final dice = _dice(compact, targetCompact);
      final score = .7 * lexical + .3 * dice;
      if (lexical >= .8 && dice >= .65 && score >= .78) {
        ranked.add(MapEntry(name, score));
      }
    }
    ranked.sort((a, b) {
      final score = b.value.compareTo(a.value);
      return score == 0 ? a.key.compareTo(b.key) : score;
    });
    // Keep close alternatives visible; no top-one automatic selection.
    if (ranked.isEmpty) return extracted;
    final candidates = ranked.where((entry) =>
        entry.value >= ranked.first.value - .12).take(3).toList();
    return extracted.withVoiceMatches(
        candidates.map((entry) => entry.key).toList(growable: false),
        {for (final entry in candidates) entry.key: entry.value});
  }

  // Digits and punctuation are identifiers, not spelling mistakes.
  static String _identifiers(String text) =>
      RegExp(r'\d+|[^\w\s\u0600-\u06ff]').allMatches(text)
          .map((match) => match.group(0)).join('|');

  static int _distance(String a, String b) {
    var previous = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 0; i < a.length; i++) {
      final row = List<int>.filled(b.length + 1, 0)..[0] = i + 1;
      for (var j = 0; j < b.length; j++) {
        final insertion = row[j] + 1;
        final deletion = previous[j + 1] + 1;
        final substitution = previous[j] + (a[i] == b[j] ? 0 : 1);
        row[j + 1] = insertion < deletion ? insertion : deletion;
        if (substitution < row[j + 1]) row[j + 1] = substitution;
      }
      previous = row;
    }
    return previous.last;
  }

  static double _dice(String a, String b) {
    final pairs = <String, int>{};
    for (var i = 0; i < a.length - 1; i++) {
      final pair = a.substring(i, i + 2);
      pairs[pair] = (pairs[pair] ?? 0) + 1;
    }
    var overlap = 0;
    for (var i = 0; i < b.length - 1; i++) {
      final pair = b.substring(i, i + 2);
      final count = pairs[pair] ?? 0;
      if (count > 0) {
        overlap++;
        pairs[pair] = count - 1;
      }
    }
    return 2 * overlap / (a.length + b.length - 2);
  }
}
