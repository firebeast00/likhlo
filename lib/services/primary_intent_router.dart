enum RoutedSmartIntent {
  addExpense,
  addIncome,
  deleteEntry,
  editEntry,
  transfer,
  repeatEntry,
  query,
  searchEntries,
  navigate,
  unknown,
}

class PrimaryIntentRoute {
  final RoutedSmartIntent intent;
  final double confidence;
  final String rule;
  final String? navigationTarget;

  const PrimaryIntentRoute({
    required this.intent,
    required this.confidence,
    required this.rule,
    this.navigationTarget,
  });
}

/// Resolves the command family before transaction fields are extracted.
///
/// This prevents a missing amount from turning navigation or search text into
/// an expense, and prevents an existing-title match from turning an explicit
/// add command into an edit.
class PrimaryIntentRouter {
  const PrimaryIntentRouter();

  PrimaryIntentRoute classify(String input) {
    final text = input.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty) {
      return const PrimaryIntentRoute(
        intent: RoutedSmartIntent.unknown,
        confidence: 0,
        rule: 'empty',
      );
    }

    bool has(String pattern) => RegExp(pattern).hasMatch(text);

    final navigationTarget = _navigationTarget(text);
    final hasStrongNavigationTrigger = has(
      r'\b(open|goto|go\s+to|take\s+me\s+to|khol|kholo)\b',
    );
    final hasShowMeTrigger = has(r'\b(show\s+me|mujhe\s+dikhao|dikhao)\b');
    final hasFinancialSubject = has(
      r'\b(expense|expenses|spent|spending|income|earned|received|balance|total|count|net|kharch|kamai|transactions?|entries)\b',
    );
    if (navigationTarget != null &&
        (hasStrongNavigationTrigger ||
            (hasShowMeTrigger && !hasFinancialSubject))) {
      return PrimaryIntentRoute(
        intent: RoutedSmartIntent.navigate,
        confidence: 0.99,
        rule: 'navigation_trigger_and_target',
        navigationTarget: navigationTarget,
      );
    }

    if (has(r'\b(delete|remove|erase|hata|hatao|nikal|nikalo)\b')) {
      return const PrimaryIntentRoute(
        intent: RoutedSmartIntent.deleteEntry,
        confidence: 0.99,
        rule: 'delete_verb',
      );
    }
    if (has(r'\b(transfer|move|shift|send|bhej|bhejo)\b')) {
      return const PrimaryIntentRoute(
        intent: RoutedSmartIntent.transfer,
        confidence: 0.99,
        rule: 'transfer_verb',
      );
    }
    if (has(r'\b(repeat|again|dobara)\b') ||
        has(r'\b(same|wahi|wohi)\b.{0,30}\b(phir|again|dobara)\b') ||
        has(r'\b(phir\s+se)\b')) {
      return const PrimaryIntentRoute(
        intent: RoutedSmartIntent.repeatEntry,
        confidence: 0.98,
        rule: 'repeat_verb',
      );
    }

    final hasExplicitEdit = has(
      r'\b(edit|change|update|modify|correct|badal|badlo|theek)\b',
    );
    final hasFieldMutation = has(
      r'\b(naam|name|title|amount|category)\b.{0,50}\b(karo|kar\s+do|badlo|change|update|to)\b',
    );
    final hasKoRename = has(
      r'^.{1,50}\s+ko\s+.{1,50}\s+kar\s+do$',
    );
    if (hasExplicitEdit || hasFieldMutation || hasKoRename) {
      return const PrimaryIntentRoute(
        intent: RoutedSmartIntent.editEntry,
        confidence: 0.98,
        rule: 'edit_evidence',
      );
    }

    final asksFinancialQuestion = has(
            r'\b(how\s+much|how\s+many|kitna|kitni|kitne|balance|total|count|remaining|net)\b') ||
        has(
            r'\bwhat\b.{0,30}\b(spend|spent|income|earned|received|balance|remaining|net)\b') ||
        (has(r'\b(show|tell|calculate|summary|report|dikhao|batao)\b') &&
            has(r'\b(spent|spending|expense|expenses|income|earned|received|kamai)\b'));
    if (asksFinancialQuestion) {
      return const PrimaryIntentRoute(
        intent: RoutedSmartIntent.query,
        confidence: 0.98,
        rule: 'financial_question',
      );
    }
    if (has(r'\b(show|list|find|search|dhoondo|dikhao)\b')) {
      return const PrimaryIntentRoute(
        intent: RoutedSmartIntent.searchEntries,
        confidence: 0.96,
        rule: 'search_verb',
      );
    }

    final addsMoneyToWallet = has(
          r'\b(me|mein|ko)\s+(add|jama|deposit|dalo|daalo|daldo|daaldo)\b',
        ) ||
        has(
          r'\b(add|jama|deposit)\b.{0,30}\b(to|me|mein|ko)\s+(cash|jazz\s*cash|wallet|account)\b',
        );
    final hasIncomeEvidence = has(
      r'\b(income|salary|allowance|received|receive|credited|credit|deposit|kamai|earning|earned|bonus|refund|cashback|profit|aayi|ayi|aya|mila|mili|jama|wasool)\b',
    );
    if (addsMoneyToWallet || hasIncomeEvidence) {
      return const PrimaryIntentRoute(
        intent: RoutedSmartIntent.addIncome,
        confidence: 0.98,
        rule: 'income_evidence',
      );
    }

    final hasExplicitAdd = has(
      r'\b(add|save|record|note|enter|dalo|daalo|daldo|daaldo|likho)\b',
    );
    final hasExpenseAction = has(
      r'\b(expense|spent|spend|paid|gave|bought|purchase|purchased|kharch|kharcha|diye|diya|kharida|khareeda|khareed|liya)\b',
    );
    if (hasExplicitAdd || hasExpenseAction) {
      return const PrimaryIntentRoute(
        intent: RoutedSmartIntent.addExpense,
        confidence: 0.97,
        rule: 'creation_evidence',
      );
    }
    if (_hasAmountSignal(text) && _hasCandidateItem(text)) {
      return const PrimaryIntentRoute(
        intent: RoutedSmartIntent.addExpense,
        confidence: 0.96,
        rule: 'amount_and_candidate_item',
      );
    }
    if (_hasAmountSignal(text)) {
      return const PrimaryIntentRoute(
        intent: RoutedSmartIntent.addExpense,
        confidence: 0.86,
        rule: 'amount_only_review',
      );
    }

    return const PrimaryIntentRoute(
      intent: RoutedSmartIntent.unknown,
      confidence: 0,
      rule: 'insufficient_evidence',
    );
  }

  bool _hasAmountSignal(String input) {
    if (RegExp(r'(^|\s)(?:rs\.?|pkr)?\s*\d+(?:[,.]\d+)?\b').hasMatch(input)) {
      return true;
    }
    return RegExp(
      r'\b(aik|ek|do|teen|tin|chaar|char|paanch|panch|chhay|saat|aath|nau|das|bees|tees|chalees|pachas|saath|sattar|assi|nabbe|one|two|three|four|five|six|seven|eight|nine|ten|twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety|hundred|sau|hazar|hazaar|thousand|lakh|lac|crore|million|paanso|paso)\b',
    ).hasMatch(input);
  }

  bool _hasCandidateItem(String input) {
    const nonItemWords = {
      'rs',
      'pkr',
      'rupee',
      'rupees',
      'paisa',
      'paise',
      'rupay',
      'aik',
      'ek',
      'do',
      'teen',
      'tin',
      'chaar',
      'char',
      'paanch',
      'panch',
      'chhay',
      'saat',
      'aath',
      'nau',
      'das',
      'bees',
      'tees',
      'chalees',
      'pachas',
      'saath',
      'sattar',
      'assi',
      'nabbe',
      'one',
      'two',
      'three',
      'four',
      'five',
      'six',
      'seven',
      'eight',
      'nine',
      'ten',
      'twenty',
      'thirty',
      'forty',
      'fifty',
      'sixty',
      'seventy',
      'eighty',
      'ninety',
      'hundred',
      'sau',
      'hazar',
      'hazaar',
      'thousand',
      'lakh',
      'lac',
      'crore',
      'million',
      'paanso',
      'paso',
      'k',
      'for',
      'on',
      'at',
      'to',
      'from',
      'se',
      'me',
      'mein',
      'ko',
      'ka',
      'ki',
      'ke',
      'cash',
      'wallet',
      'account',
      'jazzcash',
      'easypaisa',
      'today',
      'yesterday',
      'aaj',
      'kal',
    };
    return input
        .split(RegExp(r'\s+'))
        .map((token) => token.replaceAll(RegExp(r'[^a-z]'), ''))
        .any((token) => token.length > 1 && !nonItemWords.contains(token));
  }

  String? _navigationTarget(String input) {
    if (RegExp(r'\b(wallet|wallets)\b').hasMatch(input)) return 'Wallets';
    if (RegExp(r'\b(stats|statistics)\b').hasMatch(input)) return 'Stats';
    if (RegExp(r'\b(udhaar|udhar)\b').hasMatch(input)) return 'Udhaar';
    if (RegExp(r'\b(settings|setting)\b').hasMatch(input)) return 'Settings';
    if (RegExp(r'\babout\b').hasMatch(input)) return 'About';
    if (RegExp(r'\b(home|dashboard)\b').hasMatch(input)) return 'Dashboard';
    return null;
  }
}
