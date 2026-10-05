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
  appControl,
  unknown,
}

enum RoutedSmartAppAction {
  darkModeOn,
  darkModeOff,
  darkModeToggle,
  openMonthlyPdf,
  scanReceipt,
}

class PrimaryIntentRoute {
  final RoutedSmartIntent intent;
  final double confidence;
  final String rule;
  final String? navigationTarget;
  final RoutedSmartAppAction? appAction;

  const PrimaryIntentRoute({
    required this.intent,
    required this.confidence,
    required this.rule,
    this.navigationTarget,
    this.appAction,
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

    final appAction = _appAction(text);
    if (appAction != null) {
      return PrimaryIntentRoute(
        intent: RoutedSmartIntent.appControl,
        confidence: 0.995,
        rule: 'explicit_app_control',
        appAction: appAction,
      );
    }

    final navigationTarget = _navigationTarget(text);
    final hasStrongNavigationTrigger = has(
      r'\b(open|goto|go\s+to|take\s+me\s+to|khol|kholo|jao|le\s+chalo)\b',
    );
    final isBareNavigationCommand = _isBareNavigationCommand(text);
    final hasShowMeTrigger = has(
      r'\b(show\s+me|show|mujhe\s+dikhao|dikhao|dikhado|dikhaye)\b',
    );
    final hasFinancialSubject = has(
      r'\b(expense|expenses|spent|spending|income|earned|received|balance|total|count|net|summary|overview|hisaab|kharch|kamai|transactions?|entries)\b',
    );
    final showCanNavigate =
        !hasFinancialSubject || navigationTarget == 'Trash';
    if (navigationTarget != null &&
        (hasStrongNavigationTrigger ||
            isBareNavigationCommand ||
            (hasShowMeTrigger && showCanNavigate))) {
      return PrimaryIntentRoute(
        intent: RoutedSmartIntent.navigate,
        confidence: 0.99,
        rule: 'navigation_trigger_and_target',
        navigationTarget: navigationTarget,
      );
    }

    // Udhar amounts must never fall through to a normal expense.
    if (_hasAmountSignal(text) &&
        has(r'\b(udhar|udhaar|debt|loan)\b')) {
      return const PrimaryIntentRoute(
        intent: RoutedSmartIntent.navigate,
        confidence: 0.995,
        rule: 'udhar_amount_requires_udhar_flow',
        navigationTarget: 'Udhaar',
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

    final hasTimeScopedFinancialNoun =
        !_hasAmountSignal(text) &&
        has(
          r'\b(today|aaj|aj|yesterday|kal|this\s+week|is\s+haftay|is\s+hafte|this\s+month|is\s+mahine|is\s+month|last\s+month|pichlay\s+mahine|pichle\s+mahine)\b',
        ) &&
        has(
          r'\b(spending|expense|expenses|income|kamai|kharch|kharcha|summary|hisaab)\b',
        );
    final asksForTransactionList =
        has(r'\b(list|entries|transactions)\b') &&
        has(
          r'\b(expense|expenses|income|kharch|kamai)\b',
        );
    if (asksForTransactionList) {
      return const PrimaryIntentRoute(
        intent: RoutedSmartIntent.searchEntries,
        confidence: 0.985,
        rule: 'explicit_transaction_list',
      );
    }

    final asksFinancialQuestion = has(
          r'\b(how\s+much|how\s+many|kitna|kitni|kitne|balance|total|count|remaining|net|summary|overview|hisaab)\b',
        ) ||
        hasTimeScopedFinancialNoun ||
        has(
          r'\bwhat\b.{0,30}\b(spend|spent|income|earned|received|balance|remaining|net)\b',
        ) ||
        has(
          r'\b(mere\s+paas|paas\s+mere)\b.{0,30}\b(paisa|paise|balance)\b',
        ) ||
        has(r'\bwho\s+owes\s+me\b') ||
        (has(r'\b(show|tell|calculate|summary|overview|report|dikhao|batao)\b') &&
            has(
              r'\b(spent|spending|expense|expenses|income|earned|received|kamai|kharch|hisaab|balance)\b',
            ));
    if (asksFinancialQuestion) {
      return const PrimaryIntentRoute(
        intent: RoutedSmartIntent.query,
        confidence: 0.98,
        rule: 'financial_question',
      );
    }
    if (has(r'\b(show|list|find|search|dhoondo|dhundho|dikhao)\b')) {
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
    if (RegExp(
      r'(^|\s)(?:rs\.?|pkr)?\s*(?:\d{1,3}(?:,\d{3})+|\d+(?:\.\d+)?)(?:\s*(?:sau|hundred|k|thousand|hazar|hazaar|lakh|lac|lak|million|crore|krore|cr))?\b',
    ).hasMatch(input)) {
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

  RoutedSmartAppAction? _appAction(String input) {
    if (RegExp(
      r'\b(?:monthly\s+pdf|pdf\s+(?:report|statement|summary)|monthly\s+report|financial\s+statement|mahine\s+(?:ki|ka)\s+pdf|is\s+mahine\s+(?:ki|ka)\s+pdf)\b',
      caseSensitive: false,
    ).hasMatch(input)) {
      return RoutedSmartAppAction.openMonthlyPdf;
    }

    if (RegExp(
      r'\b(?:scan\s+(?:a\s+)?receipt|receipt\s+scan|scan\s+bill|bill\s+scan|receipt\s+(?:camera|photo)|camera\s+receipt|receipt\s+karo|receipt\s+scan\s+karo)\b',
      caseSensitive: false,
    ).hasMatch(input)) {
      return RoutedSmartAppAction.scanReceipt;
    }

    if (RegExp(
      r'\b(?:toggle\s+(?:dark\s+)?mode|toggle\s+theme|change\s+theme|theme\s+change\s+karo|theme\s+badlo|mode\s+badlo)\b',
      caseSensitive: false,
    ).hasMatch(input)) {
      return RoutedSmartAppAction.darkModeToggle;
    }
    if (RegExp(
      r'\b(?:dark\s*(?:mode|theme)\s*(?:off|band)|(?:turn\s+off|disable)\s+dark\s*(?:mode|theme)|light\s*(?:mode|theme)(?:\s+(?:on|karo|kar\s+do|lagao|laga\s+do))?|normal\s+mode\s+karo|light\s+karo|light\s+kar\s+do|day\s+mode)\b',
      caseSensitive: false,
    ).hasMatch(input)) {
      return RoutedSmartAppAction.darkModeOff;
    }
    if (RegExp(
      r'\b(?:dark\s*(?:mode|theme)(?:\s+(?:on|karo|kar\s+do|lagao|laga\s+do|chalao))?|(?:turn\s+on|enable)\s+dark\s*(?:mode|theme)|theme\s+dark\s+karo|dark\s+karo|dark\s+kar\s+do|night\s+mode)\b',
      caseSensitive: false,
    ).hasMatch(input)) {
      return RoutedSmartAppAction.darkModeOn;
    }
    return null;
  }

  bool _isBareNavigationCommand(String input) {
    return RegExp(
      r'^(?:home|dashboard|main|main\s+screen|main\s+page|wallet|wallets|accounts|income\s+accounts|udhar|udhaar|debt|loan|monthly\s+plan|smart\s+plan|budget\s+plan|budget|stats|statistics|analytics|spending\s+trends|settings|setting|preferences|trash|deleted\s+(?:entries|transactions|items)|about|about\s+app)$',
      caseSensitive: false,
    ).hasMatch(input.trim());
  }

  String? _navigationTarget(String input) {
    if (RegExp(
      r'\b(monthly\s+pdf|pdf\s+(?:report|statement)|financial\s+statement|pdf)\b',
    ).hasMatch(input)) {
      return 'Settings';
    }
    if (RegExp(r'\b(monthly\s+plan|smart\s+plan|budget\s+plan|budget|mahine\s+ka\s+plan)\b')
        .hasMatch(input)) {
      return 'Monthly Plan';
    }
    if (RegExp(r'\b(trash|deleted\s+(?:entries|transactions|items))\b')
        .hasMatch(input)) {
      return 'Trash';
    }
    if (RegExp(r'\b(wallet|wallets|accounts|income\s+accounts)\b')
        .hasMatch(input)) {
      return 'Wallets';
    }
    if (RegExp(r'\b(stats|statistics|analytics|spending\s+trends)\b')
        .hasMatch(input)) {
      return 'Stats';
    }
    if (RegExp(r'\b(udhaar|udhar|debt|loan)\b').hasMatch(input)) {
      return 'Udhaar';
    }
    if (RegExp(r'\b(settings|setting|preferences)\b').hasMatch(input)) {
      return 'Settings';
    }
    if (RegExp(r'\babout(?:\s+app)?\b').hasMatch(input)) return 'About';
    if (RegExp(r'\b(home|dashboard|main\s+screen|main\s+page)\b')
        .hasMatch(input)) {
      return 'Dashboard';
    }
    return null;
  }
}
