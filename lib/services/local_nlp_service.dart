import 'dart:math';

import 'primary_intent_router.dart';
import 'pakistani_language_normalizer.dart';
import 'transaction_title_policy.dart';

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
  appControl,
  unknown,
}

enum SmartEntryAppAction {
  darkModeOn,
  darkModeOff,
  darkModeToggle,
  openMonthlyPdf,
  scanReceipt,
}

enum SmartEntryQueryMetric {
  spending,
  income,
  balance,
  net,
  transactionCount,
  summary,
  udharSummary,
  udharReceivable,
  udharPayable,
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
      case SmartEntryIntent.appControl:
        return 'app_control';
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
  final SmartEntryAppAction? appAction;
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
    this.appAction,
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
      'fieldConfidence': Map<String, double>.unmodifiable(confidenceByField),
      'clarificationReasons': List<String>.unmodifiable(clarificationReasons),
      'queryMetric': queryMetric?.name,
      'timeRange': timeRange.name,
      'navigationTarget': navigationTarget,
      'appAction': appAction?.name,
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
  for (var firstIndex = 0; firstIndex < first.length; firstIndex++) {
    current[0] = firstIndex + 1;
    for (var secondIndex = 0; secondIndex < second.length; secondIndex++) {
      final substitution = first[firstIndex] == second[secondIndex] ? 0 : 1;
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
    final isTransfer = entry.category.trim().toLowerCase() == 'transfer' ||
        entry.id.endsWith('_out') ||
        entry.id.endsWith('_in');
    if (isTransfer) continue;
    if (walletId != null && entry.walletId != walletId) continue;
    if (requestedType != null && entry.type != requestedType) continue;
    final requestedDate =
        selectorDate ?? (command.hasExplicitDate ? command.date : null);
    if (requestedDate != null && !_sameCalendarDay(entry.date, requestedDate)) {
      continue;
    }
    final requestedAmount = selectorAmount ??
        ((command.intent == SmartEntryIntent.deleteEntry ||
                command.intent == SmartEntryIntent.repeatEntry)
            ? command.amount
            : 0.0);
    if (requestedAmount > 0 && (entry.amount - requestedAmount).abs() > 0.005) {
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
      'biryani',
      'burger',
      'burgers',
      'kfc',
      'mcdonalds',
      'shawarma',
      'roll',
      'pizza',
      'fries',
      'chips',
      'samosa',
      'pakora',
      'nimko',
      'biscuit',
      'cake',
      'ice cream',
      'zinger',
      'broast',
      'sandwich',
      'patties',
      'gol gappay',
      'chaat',
      'kachori',
      'lunch',
      'dinner',
      'breakfast',
      'nashta',
      'khana',
      'roti',
      'naan',
      'salan',
      'karahi',
      'daal',
      'chawal',
      'sabzi',
      'gosht',
      'mutton',
      'beef',
      'chicken',
      'anda',
      'chai',
      'tea',
      'coffee',
      'water',
      'pani',
      'juice',
      'shake',
      'cold drink',
      'pepsi',
      'coke',
      'sting',
      'redbull',
      'bottle',
      'doodh',
      'milk',
      'lassi',
      'groceries',
      'rashan',
      'fruit',
      'phal',
      'dahi',
      'mithai',
      'baking',
      'masala'
    ],
    'Transport': [
      'uber',
      'careem',
      'indrive',
      'bykea',
      'yango',
      'rickshaw',
      'auto',
      'bike',
      'bus',
      'wagon',
      'train',
      'car',
      'taxi',
      'qinqi',
      'chingchi',
      'petrol',
      'fuel',
      'cng',
      'diesel',
      'fare',
      'ticket',
      'rent',
      'kiraya',
      'parking',
      'toll',
      'challan',
      'mechanic',
      'puncture',
      'oil change',
      'tuning'
    ],
    'Shopping': [
      'shirt',
      'shoes',
      'clothes',
      'shopping',
      'jacket',
      'pant',
      'watch',
      'glasses',
      'bag',
      'perfume',
      'gift',
      'tohfa',
      'kapre',
      'suit',
      'kurta',
      'shalwar',
      'jootay',
      'chappal',
      'sneakers',
      'wallet',
      'belt',
      'makeup',
      'jewelry'
    ],
    'Bills': [
      'bill',
      'bijli',
      'electric',
      'electricity',
      'gas',
      'water bill',
      'wapda',
      'k-electric',
      'k electric',
      'ptcl',
      'sui gas',
      'maintenance',
      'trash',
      'kachra',
      'recharge',
      'easyload',
      'balance',
      'data plan',
      'package',
      'wifi',
      'internet',
      'cable',
      'jazz',
      'zong',
      'telenor',
      'ufone',
      'card'
    ],
    'Health': [
      'medicine',
      'doctor',
      'clinic',
      'hospital',
      'pharmacy',
      'pills',
      'dawa',
      'dawai',
      'test',
      'lab',
      'xray',
      'blood',
      'panadol',
      'bandage',
      'medical',
      'checkup',
      'dentist',
      'fee',
      'emergency'
    ],
    'Education': [
      'fees',
      'fee',
      'book',
      'books',
      'pen',
      'stationery',
      'copy',
      'register',
      'tuition',
      'print',
      'photostat',
      'assignment',
      'project',
      'notes',
      'calculator',
      'pencil',
      'marker',
      'paper',
      'hostel',
      'mess',
      'canteen'
    ]
  };

  // 🚀 FIXED: Removed 'kal' and 'aaj' from here so we can parse them as dates
  final Set<String> _stopWords = {
    'ki',
    'ka',
    'ke',
    'liye',
    'for',
    'on',
    'aur',
    'the',
    'a',
    'an',
    'to',
    'mein',
    'pe',
    'jo',
    'k',
    'se',
    'tak',
    'par',
    'wala',
    'wali',
    'wale',
    'spend',
    'spent',
    'paid',
    'gave',
    'khaye',
    'diye',
    'bought',
    'purchase',
    'purchased',
    'khaan',
    'khareed',
    'khareeda',
    'khareedi',
    'when',
    'went',
    'lag',
    'gaye',
    'ho',
    'gaya',
    'kar',
    'karo',
    'kiya',
    'jama',
    'kardiye',
    'karwa',
    'liya',
    'kha',
    'pee',
    'diya',
    'kharida',
    'rs',
    'rupees',
    'rupee',
    'amount',
    'kharch',
    'kharcha',
    'pese',
    'paise',
    'paisa',
    'mani',
    'money',
    'subah',
    'shaam',
    'raat',
    'rupay',
    'pkr',
    'received',
    'receive',
    'credited',
    'credit',
    'deposit',
    'aayi',
    'ayi',
    'aya',
    'mila',
    'mili',
    'hui',
    'hue',
    'from',
    'via',
    'using',
    'through',
    'account',
    'wallet',
    'add',
    'save',
    'record',
    'note',
    'enter',
    'expense',
    'income',
    'transaction',
    'entry',
    'delete',
    'remove',
    'hatao',
    'hata',
    'nikalo',
    'edit',
    'change',
    'update',
    'modify',
    'badlo',
    'badal',
    'transfer',
    'move',
    'shift',
    'send',
    'bhejo',
    'show',
    'list',
    'find',
    'search',
    'please',
    'plz',
    'last',
    'latest',
    'recent',
    'previous',
    'akhri',
    'pichli',
    'me',
    'ko',
    'ye',
    'yeh',
    'isko',
    'usko',
    'iss',
    'is',
    'wo',
    'woh',
    'dalo',
    'daalo',
    'daldo',
    'daaldo',
    'repeat',
    'again',
    'same',
    'dobara',
    'phir',
    'open',
    'goto',
    'go',
    'take',
    'screen',
    'page',
    'dashboard',
    'home',
    'stats',
    'statistics',
    'wallets',
    'settings',
    'about',
    'udhaar',
    'udhar',
    'mess',
    'khata',
    'entries',
    'transactions',
    'expenses',
    'spending',
    'total',
    'today',
    'yesterday',
    'week',
    'month',
    'this',
    'current',
    'pichlay',
    'pichle',
    'mahine',
    'haftay',
    'din',
    'aaj',
    'kal',
    'how',
    'much',
    'many',
    'tell',
    'calculate',
    'summary',
    'report',
    'dikhao',
    'batao',
    'dhoondo',
    'kitna',
    'kitni',
    'kitne',
    'did',
    'what',
    'balance',
    'available',
    'remaining',
    'count'
  };

  // ==========================================
  // 🔢 ROMAN URDU NUMBER WORDS
  // ==========================================
  static const Map<String, int> _units = {
    'ek': 1,
    'aik': 1,
    'one': 1,
    'do': 2,
    'two': 2,
    'teen': 3,
    'tin': 3,
    'three': 3,
    'char': 4,
    'chaar': 4,
    'four': 4,
    'panch': 5,
    'paanch': 5,
    'five': 5,
    'che': 6,
    'choh': 6,
    'chhay': 6,
    'six': 6,
    'saat': 7,
    'seven': 7,
    'aath': 8,
    'ath': 8,
    'eight': 8,
    'nau': 9,
    'nine': 9,
  };

  static const Map<String, int> _teens = {
    'das': 10,
    'dus': 10,
    'ten': 10,
    'gyarah': 11,
    'eleven': 11,
    'barah': 12,
    'twelve': 12,
    'terah': 13,
    'thirteen': 13,
    'chaudah': 14,
    'fourteen': 14,
    'pandrah': 15,
    'fifteen': 15,
    'solah': 16,
    'sixteen': 16,
    'satrah': 17,
    'seventeen': 17,
    'atharah': 18,
    'eighteen': 18,
    'unnees': 19,
    'nineteen': 19,
  };

  static const Map<String, int> _tens = {
    'ikkees': 21, 'ikkis': 21,
    'baees': 22, 'bais': 22,
    'taees': 23, 'teis': 23,
    'chobees': 24, 'chaubees': 24,
    'pachees': 25, 'pachis': 25,
    'chhabbees': 26, 'chabbis': 26,
    'sattaees': 27, 'sattais': 27,
    'atthaees': 28, 'atthais': 28,
    'untees': 29,
    'iktees': 31, 'battees': 32, 'tentees': 33,
    'chauntees': 34, 'paintees': 35, 'chhattees': 36,
    'saintees': 37, 'arthees': 38, 'untalees': 39,
    'iktalees': 41, 'bayalees': 42, 'taintalees': 43,
    'chawalees': 44, 'paintalees': 45, 'chiyalees': 46,
    'saintalees': 47, 'artalees': 48, 'unchas': 49,
    'ikyawan': 51, 'bawan': 52, 'tirpan': 53,
    'chauwan': 54, 'pachpan': 55, 'chhappan': 56,
    'sattawan': 57, 'atthawan': 58, 'unsath': 59,
    'iksath': 61, 'basath': 62, 'tirsath': 63,
    'chausath': 64, 'painsath': 65, 'chiyasath': 66,
    'sarsath': 67, 'arsath': 68, 'unhattar': 69,
    'ikhattar': 71, 'bahattar': 72, 'tihattar': 73,
    'chauhattar': 74, 'pachattar': 75, 'chihattar': 76,
    'sathattar': 77, 'athattar': 78, 'unasi': 79,
    'ikyasi': 81, 'bayasi': 82, 'tirasi': 83,
    'chaurasi': 84, 'pachasi': 85, 'chiyasi': 86,
    'satasi': 87, 'athasi': 88, 'navasi': 89,
    'ikyanwe': 91, 'bayanwe': 92, 'tiranwe': 93,
    'chauranwe': 94, 'pachanwe': 95, 'chiyanwe': 96,
    'sattanwe': 97, 'atthanwe': 98, 'ninyanwe': 99,
    'bees': 20,
    'twenty': 20,
    'tees': 30,
    'thirty': 30,
    'chalees': 40,
    'forty': 40,
    'pachas': 50,
    'fifty': 50,
    'saath': 60,
    'sixty': 60,
    'sattar': 70,
    'seventy': 70,
    'assi': 80,
    'eighty': 80,
    'nabbe': 90,
    'ninety': 90,
  };

  static const Map<String, int> _multipliers = {
    'sau': 100,
    'so': 100,
    'sou': 100,
    'saw': 100,
    'hundred': 100,
    'hazar': 1000,
    'hazaar': 1000,
    'k': 1000,
    'thousand': 1000,
    'lakh': 100000,
    'lac': 100000,
    'lak': 100000,
    'million': 1000000,
    'crore': 10000000,
    'krore': 10000000,
    'cr': 10000000,
  };

  static const Map<String, double> _fusedOverrides = {
    'sou': 100,
    'sow': 100,
    'dosou': 200,
    'doso': 200,
    'tinsou': 300,
    'teenso': 300,
    'charsou': 400,
    'chaarso': 400,
    'panso': 500,
    'paanso': 500,
    'passo': 500,
    'pansou': 500,
    'chesou': 600,
    'chhesou': 600,
    'saatsou': 700,
    'saatso': 700,
    'aathsou': 800,
    'aathso': 800,
    'nosou': 900,
    'nauso': 900,
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
      if (norm == 'do' && i > 0 &&
          const ['kar', 'daal', 'dalo', 'jama', 'bhej'].contains(tokens[i - 1])) {
        i++;
        continue;
      }

      if (const ['dhai', 'adhai', 'derh', 'dedh'].contains(norm) &&
          i + 1 < tokens.length) {
        final mult = _normalizedMultipliers[_normalize(tokens[i + 1])];
        if (mult != null) {
          amount += (norm == 'derh' || norm == 'dedh' ? 1.5 : 2.5) * mult;
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

      // Short relational words (se, to, do) must not fuzzy-match "so/sou".
      final overrideVal = _normalizedFusedOverrides[norm] ??
          (norm.length >= 5
              ? _fuzzyLookup(norm, _normalizedFusedOverrides, forceBudget: 1)
              : null);
      if (overrideVal != null) {
        amount += overrideVal;
        consumed.add(raw);
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

  String _stripConversationalContext(
    String input,
    SmartEntryIntent intent,
  ) {
    if (!intent.isTransactionAddition) return input;

    var value = input;
    final narrativePrefixes = [
      RegExp(
        r'^\s*when\b.+?(?=\b(?:i\s+)?(?:bought|purchased|paid|spent)\b)',
      ),
      RegExp(
        r'^\s*i\s+(?:went|go|was\s+going)\s+to\s+.+?(?=\b(?:and\s+)?(?:i\s+)?(?:bought|purchased|paid|spent)\b)',
      ),
      RegExp(
        r'^\s*(?:jab|main)\b.+?(?=\b(?:maine|main\s+ne)\s+)',
      ),
      RegExp(r'^\s*.+?\bke\s+paa?s\s+gaya\s+tha\b'),
    ];
    for (final pattern in narrativePrefixes) {
      value = value.replaceFirst(pattern, ' ');
    }

    return value
        .replaceAll(
          RegExp(r'\b(?:and\s+)?i\s+(?:bought|purchased|paid\s+for)\b'),
          ' ',
        )
        .replaceAll(
          RegExp(
            r'\b(?:maine|main\s+ne)\s+(?:kharida|khareeda|khareed|liya)\b',
          ),
          ' ',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  // ==========================================
  // 🧠 MAIN PARSING ENGINE
  // ==========================================
  SmartEntryIntent _intentFromRoute(RoutedSmartIntent intent) {
    switch (intent) {
      case RoutedSmartIntent.addExpense:
        return SmartEntryIntent.addExpense;
      case RoutedSmartIntent.addIncome:
        return SmartEntryIntent.addIncome;
      case RoutedSmartIntent.deleteEntry:
        return SmartEntryIntent.deleteEntry;
      case RoutedSmartIntent.editEntry:
        return SmartEntryIntent.editEntry;
      case RoutedSmartIntent.transfer:
        return SmartEntryIntent.transfer;
      case RoutedSmartIntent.repeatEntry:
        return SmartEntryIntent.repeatEntry;
      case RoutedSmartIntent.query:
        return SmartEntryIntent.query;
      case RoutedSmartIntent.searchEntries:
        return SmartEntryIntent.searchEntries;
      case RoutedSmartIntent.navigate:
        return SmartEntryIntent.navigate;
      case RoutedSmartIntent.appControl:
        return SmartEntryIntent.appControl;
      case RoutedSmartIntent.unknown:
        return SmartEntryIntent.unknown;
    }
  }

  SmartEntryQueryMetric? _queryMetric(String input) {
    final hasUdhar = RegExp(r'\b(udhar|udhaar|debt|loan)\b').hasMatch(input);
    if (hasUdhar &&
        RegExp(
          r'\b(wapas\s+lena|to\s+receive|receivable|who\s+owes\s+me|mujhe\s+milna|lena\s+hai)\b',
        ).hasMatch(input)) {
      return SmartEntryQueryMetric.udharReceivable;
    }
    if (hasUdhar &&
        RegExp(
          r'\b(wapas\s+dena|to\s+pay|payable|i\s+owe|owe|dena\s+hai)\b',
        ).hasMatch(input)) {
      return SmartEntryQueryMetric.udharPayable;
    }
    if (hasUdhar &&
        RegExp(
          r'\b(summary|overview|hisaab|hisab|total|kitna|kitni|kitne)\b',
        ).hasMatch(input)) {
      return SmartEntryQueryMetric.udharSummary;
    }
    if (RegExp(
      r'\b(summary|overview|hisaab|hisab)\b|\b(?:month|mahine|mahina)\b.{0,25}\btotal\b|\btotal\b.{0,25}\b(?:month|mahine|mahina)\b',
    ).hasMatch(input)) {
      return SmartEntryQueryMetric.summary;
    }
    final asksGenericMoneyBalance = RegExp(
          r'\b(?:kitna|kitne)\s+(?:paisa|paise|rupay|rupees?)\b',
        ).hasMatch(input) &&
        !RegExp(
          r'\b(kharch|kharcha|spend|spent|expense|income|kamai|earned|received|aaya|aya|aayi|ayi|mila|mili)\b',
        ).hasMatch(input);
    if (asksGenericMoneyBalance ||
        RegExp(
          r'\b(balance|available|bachay|bacha)\b|\bmere\s+paas\b.{0,30}\b(?:paisa|paise|rupay|rupees?)\b|\b(?:cash|jazzcash|bank|wallet|account)\b.{0,25}\b(?:kitna|kitne|available)\b|\b(?:kitna|kitne)\b.{0,25}\b(?:cash|jazzcash|bank|wallet|account)\b',
        ).hasMatch(input)) {
      return SmartEntryQueryMetric.balance;
    }
    if (RegExp(r'\b(net|difference|remaining|bacha\s+kitna)\b')
        .hasMatch(input)) {
      return SmartEntryQueryMetric.net;
    }
    if (RegExp(
      r'\b(how\s+many|count|kitni\s+entries|kitne\s+transactions|kitne\s+expense|kitni\s+income\s+entries)\b',
    ).hasMatch(input)) {
      return SmartEntryQueryMetric.transactionCount;
    }
    if (RegExp(
      r'\b(income|earned|received|salary|kamai|aayi|ayi|aaya|aya|aaye|aye|mili|mila)\b',
    ).hasMatch(input)) {
      return SmartEntryQueryMetric.income;
    }
    if (RegExp(
      r'\b(spend|spent|spending|expense|expenses|kharch|kharcha|kharach)\b',
    ).hasMatch(input)) {
      return SmartEntryQueryMetric.spending;
    }
    return null;
  }

  SmartEntryTimeRange _timeRange(String input) {
    if (RegExp(
      r'\b(last\s+month|previous\s+month|pichlay\s+mahine|pichle\s+mahine|pichla\s+mahina|last\s+mahina)\b',
    ).hasMatch(input)) {
      return SmartEntryTimeRange.lastMonth;
    }
    if (RegExp(
      r'\b(last\s+week|previous\s+week|pichlay\s+haftay|pichle\s+haftay|pichlay\s+hafte|pichle\s+hafte)\b',
    ).hasMatch(input)) {
      return SmartEntryTimeRange.lastWeek;
    }
    if (RegExp(
      r'\b(this\s+week|current\s+week|is\s+haftay|iss\s+haftay|is\s+hafte|iss\s+hafte|is\s+week|week|haftay|hafte)\b',
    ).hasMatch(input)) {
      return SmartEntryTimeRange.thisWeek;
    }
    if (RegExp(
      r'\b(this\s+month|current\s+month|is\s+mahine|iss\s+mahine|is\s+month|iss\s+month|mahine\s+ka|month\s+ka|month|mahine|mahina)\b',
    ).hasMatch(input)) {
      return SmartEntryTimeRange.thisMonth;
    }
    if (RegExp(r'\b(yesterday|kal|guzra\s+kal)\b').hasMatch(input)) {
      return SmartEntryTimeRange.yesterday;
    }
    if (RegExp(r'\b(today|aaj|aj)\b').hasMatch(input)) {
      return SmartEntryTimeRange.today;
    }
    return SmartEntryTimeRange.allTime;
  }

  String? _navigationTarget(String input) {
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

  SmartEntryAppAction? _appActionFromRoute(
    RoutedSmartAppAction? action,
  ) {
    switch (action) {
      case RoutedSmartAppAction.darkModeOn:
        return SmartEntryAppAction.darkModeOn;
      case RoutedSmartAppAction.darkModeOff:
        return SmartEntryAppAction.darkModeOff;
      case RoutedSmartAppAction.darkModeToggle:
        return SmartEntryAppAction.darkModeToggle;
      case RoutedSmartAppAction.openMonthlyPdf:
        return SmartEntryAppAction.openMonthlyPdf;
      case RoutedSmartAppAction.scanReceipt:
        return SmartEntryAppAction.scanReceipt;
      case null:
        return null;
    }
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

  ParsedSmartEntryCommand parseCommand(
    String input,
    List<String> activeCategories, {
    Iterable<SmartEntryAccount> accounts = const [],
  }) {
    final rawInput = PakistaniLanguageNormalizer().normalize(input).normalized;
    String lowerInput = rawInput.toLowerCase().replaceAll(
          RegExp(r'\s+'),
          ' ',
        );
    final intentRoute = const PrimaryIntentRouter().classify(lowerInput);
    var intent = _intentFromRoute(intentRoute.intent);
    if (intent == SmartEntryIntent.transfer) {
      final transferAccounts = resolveSmartEntryTransferAccounts(
        lowerInput,
        accounts,
        requireDirection: false,
      );
      if (transferAccounts == null) {
        intent = SmartEntryIntent.addExpense; // Downgrade to Expense!
      }
    }
    if (intent.isTransactionAddition || intent == SmartEntryIntent.unknown) {

      final transfer = resolveSmartEntryTransferAccounts(
        lowerInput, accounts, requireDirection: true,
      );
      if (transfer != null) {
        intent = SmartEntryIntent.transfer;
      } else if (RegExp(r'\b(from|se|sy|say)\b').hasMatch(lowerInput) &&
          RegExp(r'\b(to|me|mein|ko)\b').hasMatch(lowerInput) &&
          RegExp(r'\b(jama|add|dalo|daalo|deposit)\b').hasMatch(lowerInput)) {
        intent = SmartEntryIntent.unknown;
      }
    }
    // Negation and alternative commands must never silently write a ledger entry.
    if (RegExp(r'\b(nahi|nahin|mat|dont|don\x27t|ya|or)\b').hasMatch(lowerInput)) {
      intent = SmartEntryIntent.unknown;
    }
    final isIncome = intent == SmartEntryIntent.addIncome;
    var queryMetric =
        intent == SmartEntryIntent.query ? _queryMetric(lowerInput) : null;
    var timeRange = _timeRange(lowerInput);
    if (queryMetric == SmartEntryQueryMetric.summary &&
        timeRange == SmartEntryTimeRange.allTime) {
      timeRange = SmartEntryTimeRange.thisMonth;
    }
    final navigationTarget = intent == SmartEntryIntent.navigate
        ? intentRoute.navigationTarget ?? _navigationTarget(lowerInput)
        : null;
    final appAction = intent == SmartEntryIntent.appControl
        ? _appActionFromRoute(intentRoute.appAction)
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
      r'\b(\d{1,3}(?:,\d{3})+|\d+(?:\.\d+)?)\s*(sau|hundred|k|thousand|hazar|hazaar|lakh|lac|lak|million|crore|krore|cr)?\b',
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
      if (scale == 'sau' || scale == 'hundred') {
        multiplier = 100;
      } else if (scale == 'k' ||
          scale == 'thousand' ||
          scale == 'hazar' ||
          scale == 'hazaar') {
        multiplier = 1000;
      } else if (scale == 'lakh' || scale == 'lac' || scale == 'lak') {
        multiplier = 100000;
      } else if (scale == 'million') {
        multiplier = 1000000;
      } else if (scale == 'crore' || scale == 'krore' || scale == 'cr') {
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
        (active) => active.toLowerCase() == mappedCategory.toLowerCase(),
      );
      categoryFound = true;
      matchedCategoryTokens.addAll(candidate.split(' '));
    }

    for (final candidate in candidates) {
      final mappedCategory = _normalizedLexicon[_normalize(candidate)];
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

    if (intent == SmartEntryIntent.query &&
        queryMetric == null &&
        categoryFound) {
      queryMetric = SmartEntryQueryMetric.spending;
    }

    final titleSource = _stripConversationalContext(lowerInput, intent);
    String cleanTitle = titleSource.replaceAll(amountRegExp, ' ');
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
        .replaceAll(RegExp(r'[^\w\s\u0600-\u06ff]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    cleanTitle =
        cleanTitle.split(' ').where((word) => word.length > 1).join(' ').trim();

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
      cleanTitle = coreTransactionTitle(cleanTitle);
    }

    final intentConfidence = intent == SmartEntryIntent.unknown
        ? 0.0 : intent == SmartEntryIntent.transfer ? 0.99 : intentRoute.confidence;
    final categoryConfidence = isIncome
        ? 0.98
        : categoryFound
            ? 0.94
            : 0.35;
    final titleConfidence = usedFallbackTitle ? 0.35 : 0.9;
    final dateConfidence = explicitDate ? 0.98 : 0.85;
    final fieldConfidence = <String, double>{
      'intent': intentConfidence,
      'amount': amountConfidence,
      'title': titleConfidence,
      'category': categoryConfidence,
      'date': dateConfidence,
    };

    final confidence = (intentConfidence * 0.30 +
            amountConfidence * 0.35 +
            titleConfidence * 0.15 +
            categoryConfidence * 0.10 +
            dateConfidence * 0.10)
        .clamp(0.0, 1.0)
        .toDouble();

    final clarificationReasons = <String>[];
    if (containsNegativeAmount || (intent.isTransactionAddition && amount <= 0)) {
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
    if (intent == SmartEntryIntent.appControl && appAction == null) {
      clarificationReasons.add('The app control was not recognized.');
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
      appAction: appAction,
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
  return PakistaniLanguageNormalizer().normalize(value).normalized
      .replaceAll(RegExp(r'[^a-z0-9\u0600-\u06ff]+'), ' ').trim();
}

// lib/services/local_nlp_service.dart

Set<String> _smartEntryAccountAliases(SmartEntryAccount account) {
  final normalizedName = _normalizeAccountText(account.name);
  final normalizedType = _normalizeAccountText(account.type);

  final aliases = <String>{
    normalizedName,
    // Keep colliding aliases as multiple matches so callers request review.
    if (normalizedName.contains(' ') && normalizedName.split(' ').first.length >= 4)
      normalizedName.split(' ').first,
    if (normalizedType == 'cash') 'cash',
    if (normalizedType == 'jazzcash') ...['jazzcash', 'jazz cash', 'jskesh'],
    if (normalizedType == 'easypaisa') ...['easypaisa', 'easy paisa', 'paise'],
    if (normalizedType == 'cash') ...['cash', 'case'],
    if (normalizedType == 'jazzcash') ...['jazzcash', 'jazz cash','jez', 'jaz', 'jack cake', 'jail cale', 'jazz case', 'jaz cash', 'jskesh'],
    if (normalizedType == 'easypaisa') ...['easypaisa', 'easy paisa', 'paise', 'paisa'],
  }..removeWhere((alias) => alias.isEmpty);

  // Add individual words from multi-word accounts
  for (final word in normalizedName.split(' ')) {
    if (word.length >= 3) {
      aliases.add(word);
      // Catch common Urdu transliteration swaps (z <-> j, s <-> c)
      if (word.contains('roj') || word.contains('roz')) {
        aliases.addAll(['roj', 'roz', 'rose']);
      }
    }
  }

  aliases.removeWhere((alias) => alias.isEmpty);
  return aliases;
}

/// Udhaar uses the same wallet names and speech aliases as Main Smart Entry.
Set<String> smartEntryAccountAliases(SmartEntryAccount account) =>
    _smartEntryAccountAliases(account);

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
  Iterable<SmartEntryAccount> accounts, {
  bool requireDirection = false,
}) {
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
            (mention.start == best.start && mention.end > best.end)) {
          best = mention;
        }
      }
    }
    if (best != null) mentions.add(best);
  }

  // A complete wallet name wins over another wallet's short prefix.
  final contained = mentions.where((mention) => mentions.any((other) =>
      other.account.id != mention.account.id &&
      other.start <= mention.start && other.end >= mention.end &&
      other.end - other.start > mention.end - mention.start)).toSet();
  mentions.removeWhere(contained.contains);
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
        hasAfter(mention, const ['se', 'sy', 'say', 'to'])) {
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
    if (requireDirection) return null;
    resolvedSource = uniqueMentions.first;
    resolvedDestination = uniqueMentions.last;
  }
  if (resolvedSource.account.id == resolvedDestination.account.id) {
    return null;
  }

  final directional = hasBefore(resolvedSource, 'from') ||
      hasAfter(resolvedSource, const ['se', 'sy', 'say', 'to']) ||
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
  final mentionedId = mentionedIds.length == 1 ? mentionedIds.single : null;

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
      return canUse(preferred, explicitlySelected: true) ? preferred.id : null;
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
  final title = parsed['title']?.toString() ?? '';

  return hasResolvedWallet &&
      amount is num &&
      amount.isFinite &&
      amount > 0 &&
      (type != 'expense' || hasSpecificSmartEntryTitle(title)) &&
      (semanticConfidence == null || semanticConfidence >= 0.94) &&
      (type == 'expense' || type == 'income');
}

bool hasSpecificSmartEntryTitle(String title) {
  final normalized = title.trim().toLowerCase();
  return normalized.isNotEmpty &&
      normalized != 'transaction' &&
      normalized != 'quick expense';
}

class _WordAmountResult {
  final double amount;
  final List<String> consumedTokens;
  _WordAmountResult(this.amount, this.consumedTokens);
}
