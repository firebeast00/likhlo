import '../l10n/app_catalog.g.dart';

/// A snapshot of active names. Aliases never create or rename a category.
class CategoryVocabulary {
  final Map<String, String> _exact;
  final Map<String, Set<String>> _aliases;
  final Set<String> _learned;

  CategoryVocabulary._(this._exact, this._aliases, this._learned);

  static String key(String value) => value.trim().toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ');

  factory CategoryVocabulary.build(Iterable<String> categories,
      {Map<String, String> confirmedAliases = const {}}) {
    final active = categories.where((name) => name.trim().isNotEmpty).toSet();
    final exact = {for (final name in active) key(name): name};
    final aliases = <String, Set<String>>{};
    final learned = <String>{};
    void add(String heard, String target, {bool confirmed = false}) {
      final normalized = key(heard);
      if (normalized.isEmpty || normalized.length > 80 ||
          !active.contains(target) || exact.containsKey(normalized) ||
          _identifiers(normalized) != _identifiers(key(target))) return;
      aliases.putIfAbsent(normalized, () => <String>{}).add(target);
      if (confirmed) learned.add(normalized);
    }
    // Use the same approved labels as the UI, not semantic item keywords.
    const labels = {
      'General': 'general_9239ee', 'Food': 'food_35b259',
      'Transport': 'transport_c10d76', 'Shopping': 'shopping_96a0dc',
      'Entertainment': 'entertainment_8c520b', 'Health': 'health_3703cd',
      'Education': 'education_aaf87f',
    };
    for (final entry in labels.entries) {
      if (active.contains(entry.key)) {
        final label = romanUrduMessages[entry.value];
        if (label != null) add(label, entry.key);
      }
    }
    // A spelling variant, not a new semantic synonym or an ASR guess.
    add('kharidari', 'Shopping');
    for (final entry in confirmedAliases.entries) {
      add(entry.key, entry.value, confirmed: true);
    }
    return CategoryVocabulary._(exact, aliases, learned);
  }

  Iterable<String> get names => {..._exact.keys, ..._aliases.keys};

  List<String> targets(String name) {
    final normalized = key(name);
    final exact = _exact[normalized];
    if (exact != null) return [exact];
    return (_aliases[normalized]?.toList() ?? <String>[])..sort();
  }

  String provenance(String name) => _exact.containsKey(key(name)) ? 'exact'
      : _learned.contains(key(name)) ? 'confirmed_alias' : 'translated_alias';

  Iterable<MapEntry<String, String>> get entries sync* {
    for (final name in names) {
      for (final target in targets(name)) {
        yield MapEntry(name, target);
      }
    }
  }

  static String _identifiers(String text) =>
      RegExp(r'\d+|[^\w\s\u0600-\u06ff]').allMatches(text)
          .map((match) => match.group(0)).join('|');
}
