class DomainLexicon {
  final List<String> walletNames;
  final List<String> categories;
  final List<String> frequentTitles;

  const DomainLexicon({
    this.walletNames = const [],
    this.categories = const [],
    this.frequentTitles = const [],
  });
}

class AsrHintBuilder {
  final int maxHints;

  const AsrHintBuilder({this.maxHints = 200});

  static const _baseHints = [
    'JazzCash',
    'Jazz Cash',
    'Easypaisa',
    'Easy Paisa',
    'Meezan Bank',
    'HBL',
    'UBL',
    'Bank Alfalah',
    'Cash',
    'Bank Account',
    'hazaar',
    'hazar',
    'sau',
    'lakh',
    'kharch',
    'spent',
    'expense',
    'jama',
    'bhejo',
    'transfer',
    'nikalo',
    'dalo',
    'udhaar',
    'tankhwa',
    'pen',
    'pencil',
    'marker',
    'petrol',
    'groceries',
  ];

  List<String> build(DomainLexicon lexicon) {
    final seen = <String>{};
    final hints = <String>[];

    void add(String value) {
      final trimmed = value.trim();
      if (trimmed.isEmpty || trimmed.length > 80) return;
      final key = trimmed.toLowerCase();
      if (seen.add(key)) hints.add(trimmed);
    }

    for (final hint in _baseHints) {
      add(hint);
    }
    for (final wallet in lexicon.walletNames) {
      add(wallet);
    }
    for (final category in lexicon.categories) {
      add(category);
    }
    for (final title in lexicon.frequentTitles.take(50)) {
      add(title);
    }
    return hints.take(maxHints).toList(growable: false);
  }
}
