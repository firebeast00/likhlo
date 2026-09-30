class PakistaniNormalizationResult {
  final String original;
  final String normalized;
  final List<String> appliedRules;

  const PakistaniNormalizationResult({
    required this.original,
    required this.normalized,
    required this.appliedRules,
  });
}

/// Canonicalizes Urdu script, Roman Urdu, English code-switching, Pakistani
/// wallet spellings, and common ASR mistakes without applying broad unsafe
/// substitutions such as replacing every occurrence of "show" with "so".
class PakistaniLanguageNormalizer {
  static const _urduDigits = {
    '۰': '0',
    '۱': '1',
    '۲': '2',
    '۳': '3',
    '۴': '4',
    '۵': '5',
    '۶': '6',
    '۷': '7',
    '۸': '8',
    '۹': '9',
    '٠': '0',
    '١': '1',
    '٢': '2',
    '٣': '3',
    '٤': '4',
    '٥': '5',
    '٦': '6',
    '٧': '7',
    '٨': '8',
    '٩': '9',
  };

  static const _urduPhrases = <String, String>{
    'جاز کیش': 'jazzcash',
    'جازکیش': 'jazzcash',
    'ایزی پیسہ': 'easypaisa',
    'میزان بینک': 'meezan bank',
    'بینک اکاؤنٹ': 'bank account',
    'بینک': 'bank',
    'نقد': 'cash',
    'کیش': 'cash',
    'ٹرانسفر': 'transfer',
    'منتقل': 'transfer',
    'بھیجو': 'bhejo',
    'ڈالو': 'dalo',
    'نکالو': 'nikalo',
    'سے': 'se',
    'میں': 'me',
    'کو': 'ko',
    'خرچ': 'kharch',
    'جمع': 'jama',
    'آمدنی': 'income',
    'تنخواہ': 'salary',
    'حذف': 'delete',
    'مٹاؤ': 'delete',
    'نام': 'naam',
    'رقم': 'amount',
    'بدلو': 'badlo',
    'کرو': 'karo',
    'کر دو': 'karo',
    'کر': 'kar',
    'پر': 'par',
    'کے': 'ke',
    'کی': 'ki',
    'کا': 'ka',
    'آج': 'aaj',
    'کل': 'kal',
    'پرسوں': 'parso',
    'ایک': 'aik',
    'دو': 'do',
    'تین': 'teen',
    'چار': 'chaar',
    'پانچ': 'paanch',
    'چھ': 'chhay',
    'سات': 'saat',
    'آٹھ': 'aath',
    'نو': 'nau',
    'دس': 'das',
    'بیس': 'bees',
    'تیس': 'tees',
    'چالیس': 'chalees',
    'پچاس': 'pachas',
    'ساٹھ': 'saath',
    'ستر': 'sattar',
    'اسی': 'assi',
    'نوے': 'nabbe',
    'سو': 'sau',
    'ہزار': 'hazar',
    'لاکھ': 'lakh',
    'کروڑ': 'crore',
    'ڈیڑھ': 'derh',
    'ڈھائی': 'dhai',
    'سوا': 'sawa',
    'پونے': 'paune',
    'روپے': 'rupees',
    'روپیہ': 'rupees',
    'کیا': 'kiya',
    'نہیں': 'nahi',
    'مت': 'mat',
    'یا': 'ya',
    'ڈیلی': 'daily',
    'خریدا': 'kharida',
    'ملے': 'mila',
    'دکھاؤ': 'show',
    'کتنا': 'kitna',
    'بیلنس': 'balance',
    'بریانی': 'biryani',
    'پٹرول': 'petrol',
    'پیٹرول': 'petrol',
    'دودھ': 'doodh',
    'روٹی': 'roti',
    'چائے': 'chai',
    'کرایہ': 'kiraya',
    'گیارہ': '11',
    'بارہ': '12',
    'تیرہ': '13',
    'چودہ': '14',
    'پندرہ': '15',
    'سولہ': '16',
    'سترہ': '17',
    'اٹھارہ': '18',
    'انیس': '19',
    'پچیس': '25',
    'پینتیس': '35',
    'پینتالیس': '45',
    'پچپن': '55',
    'پینسٹھ': '65',
    'پچھتر': '75',
    'پچاسی': '85',
    'پچانوے': '95',
  };

  static final List<MapEntry<String, String>> _sortedUrduPhrases = _urduPhrases
      .entries
      .toList(growable: false)
    ..sort((first, second) => second.key.length.compareTo(first.key.length));

  PakistaniNormalizationResult normalize(
    String input, {
    bool enableContextualAsrRepairs = false,
  }) {
    var value = input.trim().toLowerCase();
    final applied = <String>[];

    for (final entry in _urduDigits.entries) {
      if (value.contains(entry.key)) {
        value = value.replaceAll(entry.key, entry.value);
        if (!applied.contains('urdu_digits')) applied.add('urdu_digits');
      }
    }

    for (final entry in _sortedUrduPhrases) {
      final phrase = RegExp('(^|[^a-z0-9\\u0600-\\u06ff])${RegExp.escape(entry.key)}(?=\$|[^a-z0-9\\u0600-\\u06ff])');
      if (phrase.hasMatch(value)) {
        value = value.replaceAllMapped(phrase, (match) => '${match.group(1)}${entry.value}');
        if (!applied.contains('urdu_script')) applied.add('urdu_script');
      }
    }

    const romanAliases = {
      'sy': 'se', 'khurch': 'kharch', 'kharcha': 'kharch',
      'kharach': 'kharch', 'kharchay': 'kharch',
      'jamma': 'jama', 'bhejdo': 'bhejo', 'kardo': 'karo',
      'krdo': 'karo', 'karado': 'karo', 'dikhado': 'dikhao',
      'dikha do': 'dikhao', 'lagado': 'lagao', 'laga do': 'lagao',
      'hisab': 'hisaab', 'hissab': 'hisaab',
      'daaldo': 'dalo', 'daal': 'dalo',
      'lakhs': 'lakh', 'lacs': 'lac', 'crores': 'crore',
      'dairh': 'derh', 'deirh': 'derh',
    };
    for (final entry in romanAliases.entries) {
      value = _replace(value, RegExp('\\b${entry.key}\\b'),
          entry.value, applied, 'roman_urdu_alias');
    }
    value = _replace(
      value,
      RegExp(r'\b(jazz\s*(?:cash|cast)|jaz\s*cash)\b'),
      'jazzcash',
      applied,
      'jazzcash_alias',
    );
    value = _replace(
      value,
      RegExp(r'\b(easy\s*(?:paisa|pasa)|easypaisa)\b'),
      'easypaisa',
      applied,
      'easypaisa_alias',
    );
    value = _replace(
      value,
      RegExp(r'\bpaso\b'),
      'paanso',
      applied,
      'amount_alias',
    );
    // lib/services/pakistani_language_normalizer.dart

// 1. Repair ASR Jazzcash & Easypaisa spellings
    value = _replace(
      value,
      RegExp(r'\b(jskesh|jaz\s*cash|jazz\s*cast|jaz\s*kesh)\b'),
      'jazzcash',
      applied,
      'jazzcash_alias',
    );

// 2. Repair "transferred" -> "transfer" so intent router recognizes it
    value = _replace(
      value,
      RegExp(r'\b(transferred|transfered)\b'),
      'transfer',
      applied,
      'transfer_alias',
    );
    value = _replace(
      value,
      // 🚀 FIXED: Added case, jskesh, and jez kashmir to the regex
      RegExp(r'\b(jazz\s*(?:cash|cast|case)|jaz\s*(?:cash|case)|jskesh|jez\s*kashmir)\b'),
      'jazzcash',
      applied,
      'jazzcash_alias',
    );
    value = _replace(
      value,
      RegExp(r'\bfemi\b'),
      'fee me',
      applied,
      'asr_repair_femi',
    );

// 3. Fix clock-time format "3:30 lakh" -> "3.5 lakh" or "350000"
    value = value.replaceAllMapped(
      RegExp(r'\b(\d+):([0-5]\d)\s*(lakh|lac|hazar|k)?\b'),
          (match) {
        final whole = match.group(1)!;
        final mins = match.group(2)!;
        final scale = match.group(3) ?? '';
        if (mins == '30') {
          return '$whole.5 $scale'.trim();
        }
        return '$whole $mins $scale'.trim();
      },
    );

// 4. Map "sade" / "sadhe" to 1.5 multiplier
    value = _replace(
      value,
      RegExp(r'\b(sade|sadhe|saade)\s+lakh\b'),
      '1.5 lakh',
      applied,
      'sadhe_scale',
    );

    final hasAmountContext = RegExp(
      r'\b(?:\d+(?:[,.]\d+)?|aik|ek|do|teen|tin|chaar|char|paanch|panch|chhay|saat|aath|nau|das|bees|tees|chalees|pachas|saath|sattar|assi|nabbe|hundred|sau|hazar|hazaar|thousand|lakh|crore)\b',
    ).hasMatch(value);
    final hasRetailContext = RegExp(
      r'\b(?:pen|pencil|marker|book|books|milk|food|burger|biryani|petrol|fuel|grocery|groceries|medicine|fee|fees|bill|ticket|shoes|jute)\b',
    ).hasMatch(value);
    if (enableContextualAsrRepairs && hasAmountContext && hasRetailContext) {
      value = _replace(
        value,
        RegExp(r'\bspain\b'),
        'spent',
        applied,
        'spent_asr_context',
      );
    }
    if (enableContextualAsrRepairs &&
        hasAmountContext &&
        RegExp(
          r'\bpain\b\s+(?:kharida|khareeda|khareed|liya|bought|purchased|add|dalo|daalo|record)\b',
        ).hasMatch(value)) {
      value = _replace(
        value,
        RegExp(r'\bpain\b'),
        'pen',
        applied,
        'pen_asr_context',
      );
    }

    const amountLead =
        r'(aik|ek|do|teen|tin|chaar|char|paanch|panch|chhay|saat|aath|nau|\d+)';
    value = value.replaceAllMapped(
      RegExp('\\b$amountLead\\s+(gazaar|gazar)\\b'),
      (match) {
        if (!applied.contains('hazar_asr_context')) {
          applied.add('hazar_asr_context');
        }
        return '${match.group(1)} hazar';
      },
    );
    value = value.replaceAllMapped(
      RegExp('\\b$amountLead\\s+show\\b'),
      (match) {
        if (!applied.contains('sau_asr_context')) {
          applied.add('sau_asr_context');
        }
        return '${match.group(1)} sau';
      },
    );

    value = value
        .replaceAll(RegExp(r"[^a-z0-9\u0600-\u06ff.,'\-]+"), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    return PakistaniNormalizationResult(
      original: input,
      normalized: value,
      appliedRules: List.unmodifiable(applied),
    );
  }

  String _replace(
    String input,
    RegExp pattern,
    String replacement,
    List<String> applied,
    String rule,
  ) {
    if (!pattern.hasMatch(input)) return input;
    applied.add(rule);
    return input.replaceAll(pattern, replacement);
  }
}
