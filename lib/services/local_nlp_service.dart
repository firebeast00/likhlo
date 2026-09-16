import 'dart:math';

class LocalNlpService {
  // Singleton pattern
  static final LocalNlpService _instance = LocalNlpService._internal();
  factory LocalNlpService() => _instance;

  final Map<String, String> _optimizedLexicon = {};
  final Map<String, String> _normalizedLexicon = {};
  late final List<String> _sortedLexiconKeys;

  late final Map<String, int> _numberWordIndex;
  late final Map<String, int> _normalizedUnitsOnly;
  late final Map<String, int> _normalizedMultipliers;
  late final Map<String, double> _normalizedFusedOverrides;

  List<String> _lastUnmatchedTokens = [];

  List<String> get lastUnmatchedTokens => _lastUnmatchedTokens;

  LocalNlpService._internal() {
    _groupedLexicon.forEach((category, words) {
      for (var word in words) {
        final w = word.toLowerCase();
        _optimizedLexicon[w] = category;
        _normalizedLexicon[_normalize(w)] = category;
      }
    });

    _sortedLexiconKeys = _optimizedLexicon.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));

    _normalizedUnitsOnly = {
      for (final e in _units.entries) _normalize(e.key): e.value,
    };
    final teensTens = {..._units, ..._teens, ..._tens};
    _numberWordIndex = {
      for (final e in teensTens.entries) _normalize(e.key): e.value,
    };
    _normalizedMultipliers = {
      for (final e in _multipliers.entries) _normalize(e.key): e.value,
    };
    _normalizedFusedOverrides = {
      for (final e in _fusedOverrides.entries) _normalize(e.key): e.value,
    };
  }

  // ==========================================
  // 📚 EXPANDED ROMAN URDU DATASET
  // ==========================================
  final Map<String, List<String>> _groupedLexicon = {
    'Food': [
      'biryani', 'burger', 'burgers', 'kfc', 'mcdonalds', 'shawarma', 'roll', 'pizza',
      'fries', 'chips', 'samosa', 'pakora', 'nimko', 'biscuit', 'cake', 'ice cream',
      'zinger', 'broast', 'sandwich', 'patties', 'gol gappay', 'chaat', 'kachori',
      'lunch', 'dinner', 'breakfast', 'nashta', 'khana', 'roti', 'naan', 'salan',
      'karahi', 'daal', 'chawal', 'sabzi', 'gosht', 'mutton', 'beef', 'chicken', 'anda',
      'chai', 'tea', 'coffee', 'water', 'pani', 'juice', 'shake', 'cold drink',
      'pepsi', 'coke', 'sting', 'redbull', 'bottle', 'doodh', 'milk', 'lassi',
      'groceries', 'rashan', 'fruit', 'phal', 'dahi', 'mithai', 'baking', 'masala'
    ],
    'Transport': [
      'uber', 'careem', 'indrive', 'bykea', 'yango', 'rickshaw', 'auto', 'bike',
      'bus', 'wagon', 'train', 'car', 'taxi', 'qinqi', 'chingchi',
      'petrol', 'fuel', 'cng', 'diesel', 'fare', 'ticket', 'rent', 'kiraya',
      'parking', 'toll', 'challan', 'mechanic', 'puncture', 'oil change', 'tuning'
    ],
    'Shopping': [
      'shirt', 'shoes', 'clothes', 'shopping', 'jacket', 'pant', 'watch', 'glasses',
      'bag', 'perfume', 'gift', 'tohfa', 'kapre', 'suit', 'kurta', 'shalwar',
      'jootay', 'chappal', 'sneakers', 'wallet', 'belt', 'makeup', 'jewelry'
    ],
    'Bills': [
      'bill', 'bijli', 'electric', 'electricity', 'gas', 'water bill', 'wapda',
      'k-electric', 'k electric', 'ptcl', 'sui gas', 'maintenance', 'trash', 'kachra',
      'recharge', 'easyload', 'balance', 'data plan', 'package', 'wifi', 'internet',
      'cable', 'jazz', 'zong', 'telenor', 'ufone', 'card'
    ],
    'Health': [
      'medicine', 'doctor', 'clinic', 'hospital', 'pharmacy', 'pills', 'dawa',
      'dawai', 'test', 'lab', 'xray', 'blood', 'panadol', 'bandage', 'medical',
      'checkup', 'dentist', 'fee', 'emergency'
    ],
    'Education': [
      'fees', 'fee', 'book', 'books', 'pen', 'stationery', 'copy', 'register',
      'tuition', 'print', 'photostat', 'assignment', 'project', 'notes',
      'calculator', 'pencil', 'marker', 'paper', 'hostel', 'mess', 'canteen'
    ]
  };

  // 🚀 FIXED: Removed 'kal' and 'aaj' from here so we can parse them as dates
  final List<String> _stopWords = [
    'ki', 'ka', 'ke', 'liye', 'for', 'on', 'aur', 'the', 'a', 'an', 'to', 'mein',
    'pe', 'jo', 'k', 'se', 'tak', 'par', 'wala', 'wali', 'wale',
    'spent', 'paid', 'gave', 'khaye', 'diye', 'bought', 'purchased', 'khaan',
    'lag', 'gaye', 'ho', 'gaya', 'kar', 'karo', 'kardiye', 'karwa', 'liya', 'liye',
    'kha', 'pee', 'diya', 'kharida',
    'rs', 'rupees', 'rupee', 'amount', 'kharch', 'kharcha', 'pese', 'paise',
    'paisa', 'mani', 'money', 'subah', 'shaam', 'raat', 'rupay', 'pkr',
    'received', 'receive', 'credited', 'credit', 'deposit', 'aayi', 'ayi',
    'aya', 'mila', 'mili', 'hui', 'hue', 'from', 'via', 'using', 'through',
    'account', 'wallet'
  ];

  // ==========================================
  // 🔢 ROMAN URDU NUMBER WORDS
  // ==========================================
  static const Map<String, int> _units = {
    'ek': 1, 'aik': 1, 'do': 2, 'teen': 3, 'tin': 3, 'char': 4, 'chaar': 4,
    'panch': 5, 'paanch': 5, 'che': 6, 'choh': 6, 'chhay': 6, 'saat': 7,
    'aath': 8, 'ath': 8, 'nau': 9,
  };

  static const Map<String, int> _teens = {
    'das': 10, 'dus': 10, 'gyarah': 11, 'barah': 12, 'terah': 13, 'chaudah': 14,
    'pandrah': 15, 'solah': 16, 'satrah': 17, 'atharah': 18, 'unnees': 19,
  };

  static const Map<String, int> _tens = {
    'bees': 20, 'tees': 30, 'chalees': 40, 'pachas': 50,
    'saath': 60, 'sattar': 70, 'assi': 80, 'nabbe': 90,
  };

  static const Map<String, int> _multipliers = {
    'sau': 100, 'so': 100, 'sou': 100, 'saw': 100,
    'hazar': 1000, 'hazaar': 1000, 'k': 1000,
    'lakh': 100000, 'lac': 100000,
    'crore': 10000000,
  };

  static const Map<String, double> _fusedOverrides = {
    'sou': 100, 'sow': 100, 'dosou': 200, 'doso': 200, 'tinsou': 300, 'teenso': 300,
    'charsou': 400, 'chaarso': 400, 'panso': 500, 'paanso': 500, 'passo': 500, 'pansou': 500,
    'chesou': 600, 'chhesou': 600, 'saatsou': 700, 'saatso': 700, 'aathsou': 800, 'aathso': 800,
    'nosou': 900, 'nauso': 900,
  };

  // ==========================================
  // 🧠 NORMALIZATION + FUZZY MATCHING
  // ==========================================

  String _normalize(String input) {
    var s = input.toLowerCase().trim();
    s = s.replaceAll('ee', 'i');
    s = s.replaceAll('oo', 'u');
    s = s.replaceAll('aa', 'a');
    s = s.replaceAllMapped(RegExp(r'(.)\1+'), (m) => m.group(1)!);
    return s;
  }

  // 🚀 FIXED: Highly optimized 1D Array Levenshtein for 10k+ word scaling
  int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    List<int> v0 = List.generate(b.length + 1, (i) => i);
    List<int> v1 = List.filled(b.length + 1, 0);

    for (int i = 0; i < a.length; i++) {
      v1[0] = i + 1;
      for (int j = 0; j < b.length; j++) {
        final cost = (a[i] == b[j]) ? 0 : 1;
        v1[j + 1] = min(v1[j] + 1, min(v0[j + 1] + 1, v0[j] + cost));
      }
      for (int j = 0; j <= b.length; j++) v0[j] = v1[j];
    }
    return v1[b.length];
  }

  T? _fuzzyLookup<T>(
      String normalizedToken,
      Map<String, T> index, {
        int? forceBudget,
      }) {
    final exact = index[normalizedToken];
    if (exact != null) return exact;

    final budget = forceBudget ?? (normalizedToken.length <= 4 ? 1 : 2);
    String? best;
    int bestDist = budget + 1;
    for (final key in index.keys) {
      if ((key.length - normalizedToken.length).abs() > budget) continue;
      final d = _levenshtein(normalizedToken, key);
      if (d < bestDist) {
        bestDist = d;
        best = key;
      }
    }
    return (best != null && bestDist <= budget) ? index[best] : null;
  }

  double? _trySuffixSplitHundred(String normToken) {
    const suffixes = ['sau', 'sou', 'so'];
    for (final suf in suffixes) {
      if (normToken.length > suf.length && normToken.endsWith(suf)) {
        final prefix = normToken.substring(0, normToken.length - suf.length);
        final unitVal = _normalizedUnitsOnly[prefix];
        if (unitVal != null) return unitVal * 100.0;
      }
    }
    return null;
  }

  // ==========================================
  // 🔢 WORD-AMOUNT PARSER
  // ==========================================

  _WordAmountResult? _parseWordAmount(List<String> tokens) {
    final consumed = <String>[];
    double amount = 0;
    int? pendingUnit;
    String? pendingUnitToken;
    bool matchedAnyScale = false;

    int i = 0;
    while (i < tokens.length) {
      final raw = tokens[i];
      final norm = _normalize(raw);

      if ((norm == 'dhai' || norm == 'adhai') && i + 1 < tokens.length) {
        final mult = _normalizedMultipliers[_normalize(tokens[i + 1])];
        if (mult != null) {
          amount += 2.5 * mult;
          consumed.addAll([raw, tokens[i + 1]]);
          matchedAnyScale = true;
          i += 2;
          continue;
        }
      }

      if (norm == 'sawa' && i + 1 < tokens.length) {
        final nextNorm = _normalize(tokens[i + 1]);
        final directMult = _normalizedMultipliers[nextNorm];
        if (directMult != null) {
          amount += 1.25 * directMult;
          consumed.addAll([raw, tokens[i + 1]]);
          matchedAnyScale = true;
          i += 2;
          continue;
        }
        final unitVal = _numberWordIndex[nextNorm];
        if (unitVal != null && i + 2 < tokens.length) {
          final mult = _normalizedMultipliers[_normalize(tokens[i + 2])];
          if (mult != null) {
            amount += (unitVal + 0.25) * mult;
            consumed.addAll([raw, tokens[i + 1], tokens[i + 2]]);
            matchedAnyScale = true;
            i += 3;
            continue;
          }
        }
      }

      if (norm == 'paune' && i + 2 < tokens.length) {
        final unitVal = _normalizedUnitsOnly[_normalize(tokens[i + 1])];
        final mult = _normalizedMultipliers[_normalize(tokens[i + 2])];
        if (unitVal != null && mult != null) {
          amount += (unitVal - 0.25) * mult;
          consumed.addAll([raw, tokens[i + 1], tokens[i + 2]]);
          matchedAnyScale = true;
          i += 3;
          continue;
        }
      }

      final overrideVal = _fuzzyLookup(norm, _normalizedFusedOverrides, forceBudget: 1);
      if (overrideVal != null) {
        amount += overrideVal;
        consumed.add(raw);
        matchedAnyScale = true;
        i++;
        continue;
      }

      final multVal = _normalizedMultipliers[norm];
      if (multVal != null) {
        amount += (pendingUnit ?? 1) * multVal;
        if (pendingUnitToken != null) consumed.add(pendingUnitToken);
        consumed.add(raw);
        pendingUnit = null;
        pendingUnitToken = null;
        matchedAnyScale = true;
        i++;
        continue;
      }

      final splitVal = _trySuffixSplitHundred(norm);
      if (splitVal != null) {
        amount += splitVal;
        consumed.add(raw);
        matchedAnyScale = true;
        i++;
        continue;
      }

      final numVal = _numberWordIndex[norm];
      if (numVal != null) {
        if (numVal >= 10) matchedAnyScale = true;
        pendingUnit = numVal;
        pendingUnitToken = raw;
        i++;
        continue;
      }

      i++;
    }

    if (pendingUnit != null) {
      amount += pendingUnit;
      if (pendingUnitToken != null) consumed.add(pendingUnitToken);
    }

    if (!matchedAnyScale || amount <= 0) return null;
    return _WordAmountResult(amount, consumed);
  }

  // ==========================================
  // 🧠 MAIN PARSING ENGINE
  // ==========================================
  Map<String, dynamic> parseExpense(String input, List<String> activeCategories) {
    String lowerInput = input.toLowerCase();
    double amount = 0.0;
    String category = 'General';
    DateTime transactionDate = DateTime.now();
    List<String> consumedTokens = [];
    final isIncome = RegExp(
      r'\b(income|salary|allowance|received|credited|deposit|kamai|earning|earned|bonus|refund|aayi|ayi|aya|mila|mili|jama)\b',
    ).hasMatch(lowerInput);
    final transactionType = isIncome ? 'income' : 'expense';

    // 1. Extract Temporal Elements (Dates)
    if (RegExp(r'\b(aaj|today)\b').hasMatch(lowerInput)) {
      consumedTokens.addAll(['aaj', 'today']);
    } else if (RegExp(r'\b(kal|yesterday)\b').hasMatch(lowerInput)) {
      transactionDate = transactionDate.subtract(const Duration(days: 1));
      consumedTokens.addAll(['kal', 'yesterday']);
    } else if (RegExp(r'\b(parso|parson)\b').hasMatch(lowerInput)) {
      transactionDate = transactionDate.subtract(const Duration(days: 2));
      consumedTokens.addAll(['parso', 'parson']);
    }

    // 2. Extract Amount
    final amountRegExp = RegExp(
      r'\b(\d{1,3}(?:,\d{3})+|\d+(?:\.\d+)?)\s*(k|thousand|hazar|hazaar|lakh|lac)?\b',
    );
    final digitMatch = amountRegExp.firstMatch(lowerInput);
    if (digitMatch != null) {
      final base = double.tryParse(
            digitMatch.group(1)!.replaceAll(',', ''),
          ) ??
          0.0;
      final scale = digitMatch.group(2);
      var multiplier = 1.0;
      if (scale == 'k' || scale == 'thousand' ||
          scale == 'hazar' || scale == 'hazaar') {
        multiplier = 1000;
      } else if (scale == 'lakh' || scale == 'lac') {
        multiplier = 100000;
      }
      amount = base * multiplier;
    } else {
      final tokens = lowerInput.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
      final wordResult = _parseWordAmount(tokens);
      if (wordResult != null) {
        amount = wordResult.amount;
        consumedTokens.addAll(wordResult.consumedTokens);
      }
    }

    final lowerActiveCategories = activeCategories.map((c) => c.toLowerCase()).toList();

    // 3. Extract Category
    bool categoryFound = false;
    List<String> matchedCategoryTokens = [];
    final words = lowerInput.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

    final candidates = <String>[];
    for (var i = 0; i < words.length - 1; i++) {
      candidates.add('${words[i]} ${words[i + 1]}');
    }
    candidates.addAll(words);

    for (final candidate in candidates) {
      final norm = _normalize(candidate);
      String? mappedCategory = _normalizedLexicon[norm];
      mappedCategory ??= candidate.length >= 4 ? _fuzzyLookup(norm, _normalizedLexicon) : null;

      if (mappedCategory != null && lowerActiveCategories.contains(mappedCategory.toLowerCase())) {
        category = activeCategories.firstWhere((c) => c.toLowerCase() == mappedCategory!.toLowerCase());
        categoryFound = true;
        matchedCategoryTokens = candidate.split(' ');
        break;
      }
    }

    if (!categoryFound) {
      for (var cat in activeCategories) {
        if (RegExp(r'\b' + RegExp.escape(cat.toLowerCase()) + r'\b').hasMatch(lowerInput)) {
          category = cat;
          break;
        }
      }
    }

    // 4. Clean Title
    String cleanTitle = lowerInput.replaceAll(amountRegExp, '');

    // 🚀 FIXED: Strict word boundary replacement to prevent mutilation
    for (final token in consumedTokens) {
      cleanTitle = cleanTitle.replaceFirst(RegExp(r'\b' + RegExp.escape(token) + r'\b'), ' ');
    }
    for (String stopWord in _stopWords) {
      cleanTitle = cleanTitle.replaceAll(RegExp(r'\b' + RegExp.escape(stopWord) + r'\b'), '');
    }

    cleanTitle = cleanTitle.replaceAll(RegExp(r'[^\w\s]'), '').trim();
    cleanTitle = cleanTitle.replaceAll(RegExp(r'\s+'), ' ');

    cleanTitle = cleanTitle.split(' ').where((w) => w.length > 1).join(' ').trim();

    _lastUnmatchedTokens = words.where((w) {
      return !_stopWords.contains(w) &&
          !consumedTokens.contains(w) &&
          !matchedCategoryTokens.contains(w) &&
          w.length > 1;
    }).toList();

    if (cleanTitle.isEmpty) {
      cleanTitle = categoryFound ? category : 'Quick Expense';
    } else {
      cleanTitle = cleanTitle.split(' ').map((word) {
        if (word.isEmpty) return '';
        return word[0].toUpperCase() + word.substring(1).toLowerCase();
      }).join(' ');
    }

    var confidence = 0.25;
    if (amount > 0) confidence += 0.4;
    if (categoryFound) confidence += 0.2;
    if (cleanTitle != 'Quick Expense') confidence += 0.1;
    if (isIncome) confidence += 0.05;

    return {
      'amount': amount,
      'category': isIncome ? 'Income / Allowance' : category,
      'title': cleanTitle,
      'date': transactionDate,
      'type': transactionType,
      'confidence': confidence.clamp(0.0, 1.0).toDouble(),
      'needsReview': confidence < 0.75,
    };
  }
}

class SmartEntryAccount {
  final String id;
  final String name;
  final String type;
  final double availableBalance;
  final bool isBackup;

  const SmartEntryAccount({
    required this.id,
    required this.name,
    required this.type,
    required this.availableBalance,
    this.isBackup = false,
  });
}

String _normalizeAccountText(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();
}

bool _accountMentioned(String input, SmartEntryAccount account) {
  final normalizedInput = _normalizeAccountText(input);
  final normalizedName = _normalizeAccountText(account.name);
  final normalizedType = _normalizeAccountText(account.type);
  // Do not interpret the "cash" part of "Jazz Cash" as the Cash account.
  final searchableInput = normalizedType == 'cash'
      ? normalizedInput.replaceAll(RegExp(r'\bjazz\s*cash\b'), ' ')
      : normalizedInput;
  final compactInput = searchableInput.replaceAll(' ', '');
  final aliases = <String>{
    normalizedName,
    normalizedType,
    if (normalizedType == 'cash') 'cash',
    if (normalizedType == 'jazzcash') ...['jazzcash', 'jazz cash'],
  }..removeWhere((alias) => alias.isEmpty);

  for (final alias in aliases) {
    final exact = RegExp(
      '(^|\\s)${RegExp.escape(alias)}(\\s|\$)',
    );
    if (exact.hasMatch(searchableInput)) return true;

    final compactAlias = alias.replaceAll(' ', '');
    if (compactAlias.length >= 5 && compactInput.contains(compactAlias)) {
      return true;
    }
  }
  return false;
}

String? findMentionedSmartEntryAccountId(
  String input,
  Iterable<SmartEntryAccount> accounts,
) {
  final matches = accounts
      .where((account) => _accountMentioned(input, account))
      .map((account) => account.id)
      .toSet();
  return matches.length == 1 ? matches.single : null;
}

String? resolveSmartEntryAccount({
  required String input,
  required Iterable<SmartEntryAccount> accounts,
  required String transactionType,
  required double amount,
  String? preferredAccountId,
}) {
  final availableAccounts = accounts.toList(growable: false);
  final mentionedId =
      findMentionedSmartEntryAccountId(input, availableAccounts);

  bool canUse(SmartEntryAccount account, {required bool explicitlySelected}) {
    if (transactionType == 'income') {
      // An explicit account can receive its first deposit. For an implicit
      // choice, an empty Cash/JazzCash pair is intentionally sent to review.
      return explicitlySelected || account.availableBalance > 0;
    }
    return account.availableBalance + 0.000001 >= amount;
  }

  if (mentionedId != null) {
    final mentioned =
        availableAccounts.firstWhere((account) => account.id == mentionedId);
    return canUse(mentioned, explicitlySelected: true) ? mentioned.id : null;
  }

  if (preferredAccountId != null) {
    SmartEntryAccount? preferred;
    for (final account in availableAccounts) {
      if (account.id == preferredAccountId) {
        preferred = account;
        break;
      }
    }
    if (preferred != null) {
      return canUse(preferred, explicitlySelected: true)
          ? preferred.id
          : null;
    }
  }

  int defaultPriority(SmartEntryAccount account) {
    final type = _normalizeAccountText(account.type).replaceAll(' ', '');
    final name = _normalizeAccountText(account.name).replaceAll(' ', '');
    if (type == 'cash' || name == 'cash' || name == 'cashinhand') return 0;
    if (type == 'jazzcash' || name == 'jazzcash') return 1;
    return 2;
  }

  final defaults = availableAccounts
      .where((account) => !account.isBackup && defaultPriority(account) < 2)
      .toList()
    ..sort((a, b) => defaultPriority(a).compareTo(defaultPriority(b)));

  for (final account in defaults) {
    if (canUse(account, explicitlySelected: false)) return account.id;
  }
  return null;
}

bool shouldAutoSaveSmartEntry(
  Map<String, dynamic> parsed, {
  required bool hasResolvedWallet,
}) {
  final amount = parsed['amount'];
  final type = parsed['type'];

  return hasResolvedWallet &&
      amount is num &&
      amount.isFinite &&
      amount > 0 &&
      (type == 'expense' || type == 'income');
}

class _WordAmountResult {
  final double amount;
  final List<String> consumedTokens;
  _WordAmountResult(this.amount, this.consumedTokens);
}