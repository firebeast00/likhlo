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
    '۰': '0', '۱': '1', '۲': '2', '۳': '3', '۴': '4',
    '۵': '5', '۶': '6', '۷': '7', '۸': '8', '۹': '9',
    '٠': '0', '١': '1', '٢': '2', '٣': '3', '٤': '4',
    '٥': '5', '٦': '6', '٧': '7', '٨': '8', '٩': '9',
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
  };

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

    final phrases = _urduPhrases.entries.toList()
      ..sort((a, b) => b.key.length.compareTo(a.key.length));
    for (final entry in phrases) {
      if (value.contains(entry.key)) {
        value = value.replaceAll(entry.key, ' ${entry.value} ');
        if (!applied.contains('urdu_script')) applied.add('urdu_script');
      }
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

    final hasAmountContext = RegExp(
      r'\b(?:\d+(?:[,.]\d+)?|aik|ek|do|teen|tin|chaar|char|paanch|panch|chhay|saat|aath|nau|das|bees|tees|chalees|pachas|saath|sattar|assi|nabbe|hundred|sau|hazar|hazaar|thousand|lakh|crore)\b',
    ).hasMatch(value);
    final hasRetailContext = RegExp(
      r'\b(?:pen|pencil|marker|book|books|milk|food|burger|biryani|petrol|fuel|grocery|groceries|medicine|fee|fees|bill|ticket|shoes|jute)\b',
    ).hasMatch(value);
    if (enableContextualAsrRepairs &&
        hasAmountContext &&
        hasRetailContext) {
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
        .replaceAll(RegExp(r'[^a-z0-9\u0600-\u06ff.]+'), ' ')
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
