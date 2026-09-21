import 'dart:math';

enum SmartEntryIntent {
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

enum SmartEntryQueryMetric {
  spending,
  income,
  balance,
  net,
  transactionCount,
}

enum SmartEntryTimeRange {
  today,
  yesterday,
  thisWeek,
  lastWeek,
  thisMonth,
  lastMonth,
  allTime,
}

bool matchesSmartEntryTimeRange(
  DateTime date,
  SmartEntryTimeRange range, {
  DateTime? now,
}) {
  final reference = now ?? DateTime.now();
  final day = DateTime(date.year, date.month, date.day);
  final today = DateTime(reference.year, reference.month, reference.day);
  switch (range) {
    case SmartEntryTimeRange.today:
      return day == today;
    case SmartEntryTimeRange.yesterday:
      return day == today.subtract(const Duration(days: 1));
    case SmartEntryTimeRange.thisWeek:
      final thisWeekStart = today.subtract(Duration(days: today.weekday - 1));
      return !day.isBefore(thisWeekStart) &&
          day.isBefore(thisWeekStart.add(const Duration(days: 7)));
    case SmartEntryTimeRange.lastWeek:
      final thisWeek = today.subtract(Duration(days: today.weekday - 1));
      final lastWeekStart = thisWeek.subtract(const Duration(days: 7));
      return !day.isBefore(lastWeekStart) && day.isBefore(thisWeek);
    case SmartEntryTimeRange.thisMonth:
      return day.year == today.year && day.month == today.month;
    case SmartEntryTimeRange.lastMonth:
      final previous = DateTime(today.year, today.month - 1);
      return day.year == previous.year && day.month == previous.month;
    case SmartEntryTimeRange.allTime:
      return true;
  }
}

extension SmartEntryIntentDetails on SmartEntryIntent {
  String get wireName {
    switch (this) {
      case SmartEntryIntent.addExpense:
        return 'add_expense';
      case SmartEntryIntent.addIncome:
        return 'add_income';
      case SmartEntryIntent.deleteEntry:
        return 'delete_entry';
      case SmartEntryIntent.editEntry:
        return 'edit_entry';
      case SmartEntryIntent.transfer:
        return 'transfer';
      case SmartEntryIntent.repeatEntry:
        return 'repeat_entry';
      case SmartEntryIntent.query:
        return 'query';
      case SmartEntryIntent.searchEntries:
        return 'search_entries';
      case SmartEntryIntent.navigate:
        return 'navigate';
      case SmartEntryIntent.unknown:
        return 'unknown';
    }
  }

  bool get isTransactionAddition {
    return this == SmartEntryIntent.addExpense ||
        this == SmartEntryIntent.addIncome;
  }
}

class ParsedSmartEntryCommand {
  final String rawInput;
  final SmartEntryIntent intent;
  final double amount;
  final String title;
  final String category;
  final DateTime date;
  final bool hasExplicitDate;
  final double confidence;
  final Map<String, double> confidenceByField;
  final List<String> clarificationReasons;
  final SmartEntryQueryMetric? queryMetric;
  final SmartEntryTimeRange timeRange;
  final String? navigationTarget;
  final String? entryTypeFilter;

  const ParsedSmartEntryCommand({
    required this.rawInput,
    required this.intent,
    required this.amount,
    required this.title,
    required this.category,
    required this.date,
    required this.hasExplicitDate,
    required this.confidence,
    required this.confidenceByField,
    required this.clarificationReasons,
    this.queryMetric,
    this.timeRange = SmartEntryTimeRange.allTime,
    this.navigationTarget,
    this.entryTypeFilter,
  });

  bool get needsClarification => clarificationReasons.isNotEmpty;

  Map<String, dynamic> toLegacyMap() {
    final transactionType = intent == SmartEntryIntent.addIncome
        ? 'income'
        : intent == SmartEntryIntent.addExpense
            ? 'expense'
            : intent.wireName;

    return {
      'amount': amount,
      'category': category,
      'title': title,
      'date': date,
      'hasExplicitDate': hasExplicitDate,
      'type': transactionType,
      'intent': intent.wireName,
      'confidence': confidence,
      'fieldConfidence':
          Map<String, double>.unmodifiable(confidenceByField),
      'clarificationReasons':
          List<String>.unmodifiable(clarificationReasons),
      'queryMetric': queryMetric?.name,
      'timeRange': timeRange.name,
      'navigationTarget': navigationTarget,
      'entryTypeFilter': entryTypeFilter,
      'needsReview': needsClarification || confidence < 0.75,
    };
  }
}

enum SmartEntryMatchStatus { unique, ambiguous, notFound }

class SmartEntryTransaction {
  final String id;
  final String title;
  final double amount;
  final String category;
  final String type;
  final DateTime date;
  final String walletId;

  const SmartEntryTransaction({
    required this.id,
    required this.title,
    required this.amount,
    required this.category,
    required this.type,
    required this.date,
    required this.walletId,
  });
}

class SmartEntryMatchResult {
  final SmartEntryMatchStatus status;
  final List<SmartEntryTransaction> matches;
  final double confidence;

  const SmartEntryMatchResult({
    required this.status,
    required this.matches,
    required this.confidence,
  });

  const SmartEntryMatchResult.notFound()
      : status = SmartEntryMatchStatus.notFound,
        matches = const [],
        confidence = 0;
}

class _ScoredSmartEntryTransaction {
  final SmartEntryTransaction transaction;
  final double score;

  const _ScoredSmartEntryTransaction(this.transaction, this.score);
}

String _normalizeMatchText(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

bool _sameCalendarDay(DateTime first, DateTime second) {
  return first.year == second.year &&
      first.month == second.month &&
      first.day == second.day;
}

int _smartEntryMatchDistance(String first, String second) {
  if (first == second) return 0;
  if (first.isEmpty) return second.length;
  if (second.isEmpty) return first.length;

  var previous = List<int>.generate(second.length + 1, (index) => index);
  var current = List<int>.filled(second.length + 1, 0);
  for (var firstIndex = 0;
      firstIndex < first.length;
      firstIndex++) {
    current[0] = firstIndex + 1;
    for (var secondIndex = 0;
        secondIndex < second.length;
        secondIndex++) {
      final substitution =
          first[firstIndex] == second[secondIndex] ? 0 : 1;
      current[secondIndex + 1] = min(
        current[secondIndex] + 1,
        min(
          previous[secondIndex + 1] + 1,
          previous[secondIndex] + substitution,
        ),
      );
    }
    final swap = previous;
    previous = current;
    current = swap;
  }
  return previous[second.length];
}

double _smartEntryTitleScore(
  String target,
  SmartEntryTransaction transaction,
) {
  final title = _normalizeMatchText(transaction.title);
  final category = _normalizeMatchText(transaction.category);
  if (target.isEmpty) return 0.80;
  if (title == target) return 1.0;
  if (title.contains(target) || target.contains(title)) return 0.96;
  if (category == target) return 0.84;

  final targetTokens =
      target.split(' ').where((token) => token.isNotEmpty).toSet();
  final titleTokens =
      title.split(' ').where((token) => token.isNotEmpty).toSet();
  if (targetTokens.isNotEmpty && titleTokens.isNotEmpty) {
    if (targetTokens.length == titleTokens.length &&
        targetTokens.containsAll(titleTokens)) {
      return 0.98;
    }
    final shared = targetTokens.intersection(titleTokens).length;
    final ratio = shared / max(targetTokens.length, titleTokens.length);
    if (ratio >= 0.5) return 0.78 + (0.16 * ratio);
  }

  final longest = max(target.length, title.length);
  if (longest > 0) {
    final distance = _smartEntryMatchDistance(target, title);
    final allowedDistance = max(1, (longest * 0.20).floor());
    if (distance <= allowedDistance) return 0.86;
  }
  return 0;
}

SmartEntryMatchResult matchSmartEntryTransaction({
  required ParsedSmartEntryCommand command,
  required Iterable<SmartEntryTransaction> entries,
  String? walletId,
  Iterable<String> ignoredTitlePhrases = const [],
  String? selectorTitle,
  double? selectorAmount,
  DateTime? selectorDate,
}) {
  var target = _normalizeMatchText(selectorTitle ?? command.title);
  for (final phrase in ignoredTitlePhrases) {
    final normalizedPhrase = _normalizeMatchText(phrase);
    if (normalizedPhrase.isEmpty) continue;
    target = target
        .replaceAll(
          RegExp(
            '(^|\\s)${RegExp.escape(normalizedPhrase)}(\\s|\$)',
          ),
          ' ',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
  if (target == 'transaction' ||
      target == 'quick expense' ||
      target == 'income allowance') {
    target = '';
  }

  final normalizedRaw = _normalizeMatchText(command.rawInput);
  String? requestedType;
  if (RegExp(
    r'\b(income|salary|allowance|received|credited|bonus|refund|aayi|mili|jama)\b',
  ).hasMatch(normalizedRaw)) {
    requestedType = 'income';
  } else if (RegExp(
    r'\b(expense|spent|paid|kharch)\b',
  ).hasMatch(normalizedRaw)) {
    requestedType = 'expense';
  }

  final scored = <_ScoredSmartEntryTransaction>[];
  for (final entry in entries) {
    final isTransfer =
        entry.category.trim().toLowerCase() == 'transfer' ||
        entry.id.endsWith('_out') ||
        entry.id.endsWith('_in');
    if (isTransfer) continue;
    if (walletId != null && entry.walletId != walletId) continue;
    if (requestedType != null && entry.type != requestedType) continue;
    final requestedDate = selectorDate ??
        (command.hasExplicitDate ? command.date : null);
    if (requestedDate != null &&
        !_sameCalendarDay(entry.date, requestedDate)) {
      continue;
    }
    final requestedAmount = selectorAmount ??
        ((command.intent == SmartEntryIntent.deleteEntry ||
                command.intent == SmartEntryIntent.repeatEntry)
            ? command.amount
            : 0.0);
    if (requestedAmount > 0 &&
        (entry.amount - requestedAmount).abs() > 0.005) {
      continue;
    }

    final score = _smartEntryTitleScore(target, entry);
    if (score >= 0.78) {
      scored.add(_ScoredSmartEntryTransaction(entry, score));
    }
  }

  if (scored.isEmpty) return const SmartEntryMatchResult.notFound();

  scored.sort((first, second) {
    final byScore = second.score.compareTo(first.score);
    if (byScore != 0) return byScore;
    return second.transaction.date.compareTo(first.transaction.date);
  });

  final strongMatches =
      scored.where((candidate) => candidate.score >= 0.95).toList();
  final prefersLatest = RegExp(
    r'\b(last|latest|recent|previous|akhri|pichli|repeat|again|dobara)\b',
  ).hasMatch(normalizedRaw);

  if (command.intent == SmartEntryIntent.repeatEntry && target.isEmpty) {
    return SmartEntryMatchResult(
      status: SmartEntryMatchStatus.unique,
      matches: [scored.first.transaction],
      confidence: 0.96,
    );
  }

  if (strongMatches.length == 1) {
    return SmartEntryMatchResult(
      status: SmartEntryMatchStatus.unique,
      matches: [strongMatches.single.transaction],
      confidence: strongMatches.single.score,
    );
  }
  if (prefersLatest && scored.first.score >= 0.86) {
    return SmartEntryMatchResult(
      status: SmartEntryMatchStatus.unique,
      matches: [scored.first.transaction],
      confidence: scored.first.score,
    );
  }

  return SmartEntryMatchResult(
    status: SmartEntryMatchStatus.ambiguous,
    matches: scored
        .take(6)
        .map((candidate) => candidate.transaction)
        .toList(growable: false),
    confidence: scored.first.score,
  );
}

class LocalNlpService {
  // Singleton pattern
  static final LocalNlpService _instance = LocalNlpService._internal();
  factory LocalNlpService() => _instance;

  final Map<String, String> _optimizedLexicon = {};
  final Map<String, String> _normalizedLexicon = {};

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
    'spend', 'spent', 'paid', 'gave', 'khaye', 'diye', 'bought', 'purchased', 'khaan',
    'lag', 'gaye', 'ho', 'gaya', 'kar', 'karo', 'kardiye', 'karwa', 'liya', 'liye',
    'kha', 'pee', 'diya', 'kharida',
    'rs', 'rupees', 'rupee', 'amount', 'kharch', 'kharcha', 'pese', 'paise',
    'paisa', 'mani', 'money', 'subah', 'shaam', 'raat', 'rupay', 'pkr',
    'received', 'receive', 'credited', 'credit', 'deposit', 'aayi', 'ayi',
    'aya', 'mila', 'mili', 'hui', 'hue', 'from', 'via', 'using', 'through',
    'account', 'wallet', 'add', 'save', 'record', 'note', 'enter',
    'expense', 'income', 'transaction', 'entry', 'delete', 'remove',
    'hatao', 'hata', 'nikalo', 'edit', 'change', 'update', 'modify',
    'badlo', 'badal', 'transfer', 'move', 'shift', 'send', 'bhejo',
    'show', 'list', 'find', 'search', 'please', 'plz', 'last', 'latest',
    'recent', 'previous', 'akhri', 'pichli', 'me', 'ko', 'ye', 'yeh',
    'isko', 'usko', 'iss', 'is', 'wo', 'woh', 'dalo', 'daalo', 'daldo',
    'daaldo', 'repeat', 'again', 'same', 'dobara', 'phir', 'open', 'goto',
    'go', 'take', 'screen', 'page', 'dashboard', 'home', 'stats',
    'statistics', 'wallets', 'settings', 'about', 'udhaar', 'udhar', 'mess',
    'khata', 'entries', 'entry', 'transactions', 'expenses', 'spending',
    'total', 'today', 'yesterday', 'week', 'month', 'this', 'current',
    'pichlay', 'pichle', 'mahine', 'haftay', 'din', 'aaj', 'kal',
    'how', 'much', 'many', 'tell', 'calculate', 'summary', 'report',
    'dikhao', 'batao', 'dhoondo', 'kitna', 'kitni', 'kitne', 'did',
    'what', 'balance', 'available', 'remaining', 'count'
  ];

  // ==========================================
  // 🔢 ROMAN URDU NUMBER WORDS
  // ==========================================
  static const Map<String, int> _units = {
    'ek': 1, 'aik': 1, 'one': 1, 'do': 2, 'two': 2,
    'teen': 3, 'tin': 3, 'three': 3, 'char': 4, 'chaar': 4, 'four': 4,
    'panch': 5, 'paanch': 5, 'five': 5, 'che': 6, 'choh': 6, 'chhay': 6,
    'six': 6, 'saat': 7, 'seven': 7, 'aath': 8, 'ath': 8, 'eight': 8,
    'nau': 9, 'nine': 9,
  };

  static const Map<String, int> _teens = {
    'das': 10, 'dus': 10, 'ten': 10, 'gyarah': 11, 'eleven': 11,
    'barah': 12, 'twelve': 12, 'terah': 13, 'thirteen': 13,
    'chaudah': 14, 'fourteen': 14, 'pandrah': 15, 'fifteen': 15,
    'solah': 16, 'sixteen': 16, 'satrah': 17, 'seventeen': 17,
    'atharah': 18, 'eighteen': 18, 'unnees': 19, 'nineteen': 19,
  };

  static const Map<String, int> _tens = {
    'bees': 20, 'twenty': 20, 'tees': 30, 'thirty': 30,
    'chalees': 40, 'forty': 40, 'pachas': 50, 'fifty': 50,
    'saath': 60, 'sixty': 60, 'sattar': 70, 'seventy': 70,
    'assi': 80, 'eighty': 80, 'nabbe': 90, 'ninety': 90,
  };

  static const Map<String, int> _multipliers = {
    'sau': 100, 'so': 100, 'sou': 100, 'saw': 100, 'hundred': 100,
    'hazar': 1000, 'hazaar': 1000, 'k': 1000, 'thousand': 1000,
    'lakh': 100000, 'lac': 100000,
    'million': 1000000, 'crore': 10000000,
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
      for (int j = 0; j <= b.length; j++) {
        v0[j] = v1[j];
      }
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

    int i = 0;
    while (i < tokens.length) {
      final raw = tokens[i];
      final norm = _normalize(raw);

      if ((norm == 'dhai' || norm == 'adhai') && i + 1 < tokens.length) {
        final mult = _normalizedMultipliers[_normalize(tokens[i + 1])];
        if (mult != null) {
          amount += 2.5 * mult;
          consumed.addAll([raw, tokens[i + 1]]);
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
          i += 2;
          continue;
        }
        final unitVal = _numberWordIndex[nextNorm];
        if (unitVal != null && i + 2 < tokens.length) {
          final mult = _normalizedMultipliers[_normalize(tokens[i + 2])];
          if (mult != null) {
            amount += (unitVal + 0.25) * mult;
            consumed.addAll([raw, tokens[i + 1], tokens[i + 2]]);
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
          i += 3;
          continue;
        }
      }

      final overrideVal = _fuzzyLookup(norm, _normalizedFusedOverrides, forceBudget: 1);
      if (overrideVal != null) {
        amount += overrideVal;
        consumed.add(raw);
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
        i++;
        continue;
      }

      final splitVal = _trySuffixSplitHundred(norm);
      if (splitVal != null) {
        amount += splitVal;
        consumed.add(raw);
        i++;
        continue;
      }

      final numVal = _numberWordIndex[norm];
      if (numVal != null) {
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

    if (consumed.isEmpty || amount <= 0) return null;
    return _WordAmountResult(amount, consumed);
  }

  // ==========================================
  // 🧠 MAIN PARSING ENGINE
  // ==========================================
  SmartEntryIntent _detectIntent(String input) {
    bool has(String pattern) => RegExp(pattern).hasMatch(input);

    if (has(r'\b(delete|remove|erase|hata|hatao|nikal|nikalo)\b')) {
      return SmartEntryIntent.deleteEntry;
    }
    if (has(r'\b(edit|change|update|modify|correct|badal|badlo|theek)\b')) {
      return SmartEntryIntent.editEntry;
    }
    if (has(r'\b(transfer|move|shift|send|bhej|bhejo)\b')) {
      return SmartEntryIntent.transfer;
    }
    if (has(r'\b(repeat|again|dobara)\b') ||
        has(r'\b(same|wahi|wohi)\b.{0,30}\b(phir|again|dobara)\b') ||
        has(r'\b(phir\s+se)\b')) {
      return SmartEntryIntent.repeatEntry;
    }
    if (has(r'\b(open|goto|go\s+to|take\s+me\s+to|khol|kholo)\b') &&
        has(r'\b(home|dashboard|stats|statistics|wallet|wallets|udhaar|udhar|mess|khata|settings|about)\b')) {
      return SmartEntryIntent.navigate;
    }
    final asksFinancialQuestion =
        has(r'\b(how\s+much|how\s+many|kitna|kitni|kitne|balance|total|count|remaining|net)\b') ||
        has(r'\bwhat\b.{0,30}\b(spend|spent|income|earned|received|balance|remaining|net)\b') ||
        (has(r'\b(show|tell|calculate|summary|report|dikhao|batao)\b') &&
            has(r'\b(spent|spending|expense|expenses|income|earned|received|kamai)\b'));
    if (asksFinancialQuestion) {
      return SmartEntryIntent.query;
    }
    if (has(r'\b(show|list|find|search|dhoondo|dikhao)\b')) {
      return SmartEntryIntent.searchEntries;
    }
    final addsMoneyToWallet = has(
          r'\b(me|mein|ko)\s+(add|jama|deposit|dalo|daalo|daldo|daaldo)\b',
        ) ||
        has(
          r'\b(add|jama|deposit)\b.{0,30}\b(to|me|mein|ko)\s+(cash|jazz\s*cash|wallet|account)\b',
        );
    if (addsMoneyToWallet) {
      return SmartEntryIntent.addIncome;
    }
    if (has(
      r'\b(income|salary|allowance|received|receive|credited|credit|deposit|kamai|earning|earned|bonus|refund|cashback|profit|aayi|ayi|aya|mila|mili|jama|wasool)\b',
    )) {
      return SmartEntryIntent.addIncome;
    }
    return input.trim().isEmpty
        ? SmartEntryIntent.unknown
        : SmartEntryIntent.addExpense;
  }

  SmartEntryQueryMetric? _queryMetric(String input) {
    if (RegExp(r'\b(balance|available|bachay|bacha)\b').hasMatch(input)) {
      return SmartEntryQueryMetric.balance;
    }
    if (RegExp(r'\b(net|difference|remaining|bacha\s+kitna)\b')
        .hasMatch(input)) {
      return SmartEntryQueryMetric.net;
    }
    if (RegExp(r'\b(how\s+many|count|kitni\s+entries|kitne\s+transactions)\b')
        .hasMatch(input)) {
      return SmartEntryQueryMetric.transactionCount;
    }
    if (RegExp(r'\b(income|earned|received|salary|kamai|aayi|mili)\b')
        .hasMatch(input)) {
      return SmartEntryQueryMetric.income;
    }
    if (RegExp(r'\b(spend|spent|spending|expense|expenses|kharch|kharcha)\b')
        .hasMatch(input)) {
      return SmartEntryQueryMetric.spending;
    }
    return null;
  }

  SmartEntryTimeRange _timeRange(String input) {
    if (RegExp(r'\b(last\s+month|previous\s+month|pichlay\s+mahine|pichle\s+mahine)\b')
        .hasMatch(input)) {
      return SmartEntryTimeRange.lastMonth;
    }
    if (RegExp(r'\b(last\s+week|previous\s+week|pichlay\s+haftay|pichle\s+haftay)\b')
        .hasMatch(input)) {
      return SmartEntryTimeRange.lastWeek;
    }
    if (RegExp(r'\b(this\s+week|current\s+week|is\s+haftay)\b')
        .hasMatch(input)) {
      return SmartEntryTimeRange.thisWeek;
    }
    if (RegExp(r'\b(this\s+month|current\s+month|is\s+mahine)\b')
        .hasMatch(input)) {
      return SmartEntryTimeRange.thisMonth;
    }
    if (RegExp(r'\b(yesterday|kal)\b').hasMatch(input)) {
      return SmartEntryTimeRange.yesterday;
    }
    if (RegExp(r'\b(today|aaj)\b').hasMatch(input)) {
      return SmartEntryTimeRange.today;
    }
    return SmartEntryTimeRange.allTime;
  }

  String? _navigationTarget(String input) {
    if (RegExp(r'\b(wallet|wallets)\b').hasMatch(input)) return 'Wallets';
    if (RegExp(r'\b(stats|statistics)\b').hasMatch(input)) return 'Stats';
    if (RegExp(r'\b(udhaar|udhar)\b').hasMatch(input)) return 'Udhaar';
    if (RegExp(r'\b(mess|khata)\b').hasMatch(input)) return 'Mess Khata';
    if (RegExp(r'\b(settings|setting)\b').hasMatch(input)) return 'Settings';
    if (RegExp(r'\babout\b').hasMatch(input)) return 'About';
    if (RegExp(r'\b(home|dashboard)\b').hasMatch(input)) return 'Dashboard';
    return null;
  }

  String? _entryTypeFilter(String input) {
    if (RegExp(r'\b(income|salary|received|kamai|aayi|mili)\b')
        .hasMatch(input)) {
      return 'income';
    }
    if (RegExp(r'\b(expense|expenses|spend|spent|spending|kharch)\b')
        .hasMatch(input)) {
      return 'expense';
    }
    return null;
  }

  double _intentConfidence(String input, SmartEntryIntent intent) {
    if (intent == SmartEntryIntent.unknown) return 0.0;
    if (intent != SmartEntryIntent.addExpense) return 0.98;

    final explicitExpense = RegExp(
      r'\b(expense|spent|paid|bought|purchased|kharch|kharcha|diye|diya|kharida)\b',
    ).hasMatch(input);
    return explicitExpense ? 0.96 : 0.84;
  }

  ParsedSmartEntryCommand parseCommand(
    String input,
    List<String> activeCategories,
  ) {
    final rawInput = input.trim();
    String lowerInput = rawInput.toLowerCase().replaceAll(
          RegExp(r'\s+'),
          ' ',
        );
    final intent = _detectIntent(lowerInput);
    final isIncome = intent == SmartEntryIntent.addIncome;
    final queryMetric = intent == SmartEntryIntent.query
        ? _queryMetric(lowerInput)
        : null;
    final timeRange = _timeRange(lowerInput);
    final navigationTarget = intent == SmartEntryIntent.navigate
        ? _navigationTarget(lowerInput)
        : null;
    final entryTypeFilter = _entryTypeFilter(lowerInput);

    double amount = 0.0;
    double amountConfidence = 0.0;
    String category = 'General';
    DateTime transactionDate = DateTime.now();
    final consumedTokens = <String>[];
    bool explicitDate = false;

    if (RegExp(r'\b(aaj|today)\b').hasMatch(lowerInput)) {
      consumedTokens.addAll(['aaj', 'today']);
      explicitDate = true;
    } else if (RegExp(r'\b(parso|parson|day before yesterday)\b')
        .hasMatch(lowerInput)) {
      transactionDate = transactionDate.subtract(const Duration(days: 2));
      consumedTokens.addAll(
        ['parso', 'parson', 'day', 'before', 'yesterday'],
      );
      explicitDate = true;
    } else if (RegExp(r'\b(kal|yesterday)\b').hasMatch(lowerInput)) {
      transactionDate = transactionDate.subtract(const Duration(days: 1));
      consumedTokens.addAll(['kal', 'yesterday']);
      explicitDate = true;
    }

    final amountRegExp = RegExp(
      r'\b(\d{1,3}(?:,\d{3})+|\d+(?:\.\d+)?)\s*(k|thousand|hazar|hazaar|lakh|lac|million|crore)?\b',
    );
    final containsNegativeAmount = RegExp(
      r'(^|\s)(-|minus)\s*\d',
    ).hasMatch(lowerInput);
    final digitMatches = amountRegExp.allMatches(lowerInput).toList();
    final digitMatch = digitMatches.isEmpty
        ? null
        : intent == SmartEntryIntent.editEntry
            ? digitMatches.last
            : digitMatches.first;
    if (digitMatch != null && !containsNegativeAmount) {
      final base = double.tryParse(
            digitMatch.group(1)!.replaceAll(',', ''),
          ) ??
          0.0;
      final scale = digitMatch.group(2);
      var multiplier = 1.0;
      if (scale == 'k' ||
          scale == 'thousand' ||
          scale == 'hazar' ||
          scale == 'hazaar') {
        multiplier = 1000;
      } else if (scale == 'lakh' || scale == 'lac') {
        multiplier = 100000;
      } else if (scale == 'million') {
        multiplier = 1000000;
      } else if (scale == 'crore') {
        multiplier = 10000000;
      }
      amount = base * multiplier;
      amountConfidence = amount > 0 ? 0.99 : 0.0;
    } else if (!containsNegativeAmount) {
      final tokens = lowerInput
          .split(RegExp(r'\s+'))
          .where((token) => token.isNotEmpty)
          .toList();
      final wordResult = _parseWordAmount(tokens);
      if (wordResult != null) {
        amount = wordResult.amount;
        amountConfidence = 0.92;
        consumedTokens.addAll(wordResult.consumedTokens);
      }
    }

    final lowerActiveCategories =
        activeCategories.map((category) => category.toLowerCase()).toList();
    bool categoryFound = false;
    final matchedCategoryTokens = <String>[];
    final words = lowerInput
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();

    final candidates = <String>[];
    for (var index = 0; index < words.length - 1; index++) {
      candidates.add('${words[index]} ${words[index + 1]}');
    }
    candidates.addAll(words);

    void applyCategory(String mappedCategory, String candidate) {
      category = activeCategories.firstWhere(
        (active) =>
            active.toLowerCase() == mappedCategory.toLowerCase(),
      );
      categoryFound = true;
      matchedCategoryTokens.addAll(candidate.split(' '));
    }

    for (final candidate in candidates) {
      final mappedCategory =
          _normalizedLexicon[_normalize(candidate)];
      if (mappedCategory != null &&
          lowerActiveCategories.contains(mappedCategory.toLowerCase())) {
        applyCategory(mappedCategory, candidate);
        break;
      }
    }

    if (!categoryFound) {
      for (final activeCategory in activeCategories) {
        if (RegExp(
          '\\b${RegExp.escape(activeCategory.toLowerCase())}\\b',
        ).hasMatch(lowerInput)) {
          applyCategory(activeCategory, activeCategory.toLowerCase());
          break;
        }
      }
    }

    if (!categoryFound) {
      final fuzzyCandidates = words
          .where((word) =>
              word.length >= 4 &&
              !_stopWords.contains(word) &&
              !RegExp(r'^\d').hasMatch(word))
          .toSet()
          .take(8);
      for (final candidate in fuzzyCandidates) {
        final mappedCategory =
            _fuzzyLookup(_normalize(candidate), _normalizedLexicon);
        if (mappedCategory != null &&
            lowerActiveCategories.contains(mappedCategory.toLowerCase())) {
          applyCategory(mappedCategory, candidate);
          break;
        }
      }
    }

    String cleanTitle = lowerInput.replaceAll(amountRegExp, ' ');
    for (final token in consumedTokens) {
      cleanTitle = cleanTitle.replaceFirst(
        RegExp('\\b${RegExp.escape(token)}\\b'),
        ' ',
      );
    }
    for (final stopWord in _stopWords) {
      cleanTitle = cleanTitle.replaceAll(
        RegExp('\\b${RegExp.escape(stopWord)}\\b'),
        ' ',
      );
    }

    cleanTitle = cleanTitle
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    cleanTitle = cleanTitle
        .split(' ')
        .where((word) => word.length > 1)
        .join(' ')
        .trim();

    _lastUnmatchedTokens = words.where((word) {
      return !_stopWords.contains(word) &&
          !consumedTokens.contains(word) &&
          !matchedCategoryTokens.contains(word) &&
          word.length > 1;
    }).toList();

    final usedFallbackTitle = cleanTitle.isEmpty;
    if (cleanTitle.isEmpty) {
      if (isIncome) {
        cleanTitle = 'Income / Allowance';
      } else if (intent == SmartEntryIntent.addExpense) {
        cleanTitle = categoryFound ? category : 'Quick Expense';
      } else {
        cleanTitle = 'Transaction';
      }
    } else {
      cleanTitle = cleanTitle.split(' ').map((word) {
        return word[0].toUpperCase() + word.substring(1).toLowerCase();
      }).join(' ');
    }

    final intentConfidence = _intentConfidence(lowerInput, intent);
    final categoryConfidence =
        isIncome ? 0.98 : categoryFound ? 0.94 : 0.35;
    final titleConfidence = usedFallbackTitle ? 0.35 : 0.9;
    final dateConfidence = explicitDate ? 0.98 : 0.85;
    final fieldConfidence = <String, double>{
      'intent': intentConfidence,
      'amount': amountConfidence,
      'title': titleConfidence,
      'category': categoryConfidence,
      'date': dateConfidence,
    };

    final confidence = (
      intentConfidence * 0.30 +
      amountConfidence * 0.35 +
      titleConfidence * 0.15 +
      categoryConfidence * 0.10 +
      dateConfidence * 0.10
    ).clamp(0.0, 1.0).toDouble();

    final clarificationReasons = <String>[];
    if (intent.isTransactionAddition && amount <= 0) {
      clarificationReasons.add(
        containsNegativeAmount
            ? 'Amount must be greater than zero.'
            : 'A positive amount is required.',
      );
    }
    if (intent == SmartEntryIntent.unknown) {
      clarificationReasons.add('The command intent was not recognized.');
    }
    if (intent == SmartEntryIntent.query && queryMetric == null) {
      clarificationReasons.add('The financial question is incomplete.');
    }
    if (intent == SmartEntryIntent.navigate && navigationTarget == null) {
      clarificationReasons.add('The destination was not recognized.');
    }

    return ParsedSmartEntryCommand(
      rawInput: rawInput,
      intent: intent,
      amount: amount,
      title: cleanTitle,
      category: isIncome ? 'Income / Allowance' : category,
      date: transactionDate,
      hasExplicitDate: explicitDate,
      confidence: confidence,
      confidenceByField: fieldConfidence,
      clarificationReasons: clarificationReasons,
      queryMetric: queryMetric,
      timeRange: timeRange,
      navigationTarget: navigationTarget,
      entryTypeFilter: entryTypeFilter,
    );
  }

  Map<String, dynamic> parseExpense(
    String input,
    List<String> activeCategories,
  ) {
    return parseCommand(input, activeCategories).toLegacyMap();
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

Set<String> _smartEntryAccountAliases(SmartEntryAccount account) {
  final normalizedName = _normalizeAccountText(account.name);
  final normalizedType = _normalizeAccountText(account.type);
  return <String>{
    normalizedName,
    if (normalizedType == 'cash') 'cash',
    if (normalizedType == 'jazzcash') ...['jazzcash', 'jazz cash'],
  }..removeWhere((alias) => alias.isEmpty);
}

bool _isCashInsideJazzCash(String input, int start, String alias) {
  if (alias != 'cash' || start < 5) return false;
  return input.substring(start - 5, start) == 'jazz ';
}

bool _accountMentioned(String input, SmartEntryAccount account) {
  final normalizedInput = _normalizeAccountText(input);
  final compactInput = normalizedInput.replaceAll(' ', '');

  for (final alias in _smartEntryAccountAliases(account)) {
    final exact = RegExp(
      '(^|\\s)${RegExp.escape(alias)}(\\s|\$)',
    );
    for (final match in exact.allMatches(normalizedInput)) {
      final start = match.start + (match.group(1)?.length ?? 0);
      if (!_isCashInsideJazzCash(normalizedInput, start, alias)) {
        return true;
      }
    }

    final compactAlias = alias.replaceAll(' ', '');
    if (alias != 'cash' &&
        compactAlias.length >= 5 &&
        compactInput.contains(compactAlias)) {
      return true;
    }
  }
  return false;
}

class SmartEntryTransferAccounts {
  final String sourceAccountId;
  final String destinationAccountId;
  final double confidence;

  const SmartEntryTransferAccounts({
    required this.sourceAccountId,
    required this.destinationAccountId,
    required this.confidence,
  });
}

class _SmartEntryAccountMention {
  final SmartEntryAccount account;
  final int start;
  final int end;

  const _SmartEntryAccountMention(this.account, this.start, this.end);
}

SmartEntryTransferAccounts? resolveSmartEntryTransferAccounts(
  String input,
  Iterable<SmartEntryAccount> accounts,
) {
  final normalizedInput = _normalizeAccountText(input);
  final mentions = <_SmartEntryAccountMention>[];

  for (final account in accounts) {
    _SmartEntryAccountMention? best;
    final aliases = _smartEntryAccountAliases(account).toList()
      ..sort((first, second) => second.length.compareTo(first.length));
    for (final alias in aliases) {
      final pattern = RegExp(
        '(^|\\s)${RegExp.escape(alias)}(\\s|\$)',
      );
      for (final match in pattern.allMatches(normalizedInput)) {
        final leadingLength = match.group(1)?.length ?? 0;
        final start = match.start + leadingLength;
        if (_isCashInsideJazzCash(normalizedInput, start, alias)) {
          continue;
        }
        final mention = _SmartEntryAccountMention(
          account,
          start,
          start + alias.length,
        );
        if (best == null ||
            mention.start < best.start ||
            (mention.start == best.start &&
                mention.end > best.end)) {
          best = mention;
        }
      }
    }
    if (best != null) mentions.add(best);
  }

  mentions.sort((first, second) => first.start.compareTo(second.start));
  final uniqueMentions = <_SmartEntryAccountMention>[];
  final seenIds = <String>{};
  for (final mention in mentions) {
    if (seenIds.add(mention.account.id)) {
      uniqueMentions.add(mention);
    }
  }
  if (uniqueMentions.length != 2) return null;

  bool hasBefore(_SmartEntryAccountMention mention, String marker) {
    final before = normalizedInput.substring(0, mention.start).trimRight();
    return RegExp(
      '(^|\\s)${RegExp.escape(marker)}\$',
    ).hasMatch(before);
  }

  bool hasAfter(
    _SmartEntryAccountMention mention,
    Iterable<String> markers,
  ) {
    final after = normalizedInput.substring(mention.end).trimLeft();
    return markers.any(
      (marker) => RegExp(
        '^${RegExp.escape(marker)}(\\s|\$)',
      ).hasMatch(after),
    );
  }

  _SmartEntryAccountMention? source;
  _SmartEntryAccountMention? destination;
  for (final mention in uniqueMentions) {
    if (hasBefore(mention, 'from') ||
        hasAfter(mention, const ['se', 'say', 'to'])) {
      source ??= mention;
    }
    if (hasBefore(mention, 'to') ||
        hasAfter(mention, const ['me', 'mein', 'ko'])) {
      destination ??= mention;
    }
  }

  late final _SmartEntryAccountMention resolvedSource;
  late final _SmartEntryAccountMention resolvedDestination;
  if (source != null &&
      destination != null &&
      source.account.id != destination.account.id) {
    resolvedSource = source;
    resolvedDestination = destination;
  } else {
    resolvedSource = uniqueMentions.first;
    resolvedDestination = uniqueMentions.last;
  }
  if (resolvedSource.account.id == resolvedDestination.account.id) {
    return null;
  }

  final directional = hasBefore(resolvedSource, 'from') ||
      hasAfter(resolvedSource, const ['se', 'say', 'to']) ||
      hasBefore(resolvedDestination, 'to') ||
      hasAfter(resolvedDestination, const ['me', 'mein', 'ko']);

  return SmartEntryTransferAccounts(
    sourceAccountId: resolvedSource.account.id,
    destinationAccountId: resolvedDestination.account.id,
    confidence: directional ? 0.99 : 0.92,
  );
}

Set<String> findMentionedSmartEntryAccountIds(
  String input,
  Iterable<SmartEntryAccount> accounts,
) {
  return accounts
      .where((account) => _accountMentioned(input, account))
      .map((account) => account.id)
      .toSet();
}

String? findMentionedSmartEntryAccountId(
  String input,
  Iterable<SmartEntryAccount> accounts,
) {
  final matches = findMentionedSmartEntryAccountIds(input, accounts);
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
  final mentionedIds =
      findMentionedSmartEntryAccountIds(input, availableAccounts);
  if (mentionedIds.length > 1) return null;
  final mentionedId =
      mentionedIds.length == 1 ? mentionedIds.single : null;

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
  double? semanticConfidence,
}) {
  final amount = parsed['amount'];
  final type = parsed['type'];

  return hasResolvedWallet &&
      amount is num &&
      amount.isFinite &&
      amount > 0 &&
      (semanticConfidence == null || semanticConfidence >= 0.94) &&
      (type == 'expense' || type == 'income');
}

class _WordAmountResult {
  final double amount;
  final List<String> consumedTokens;
  _WordAmountResult(this.amount, this.consumedTokens);
}
