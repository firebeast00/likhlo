const int maxTransactionTitleWords = 3;

const Set<String> _transactionTitleNoiseWords = {
  'a',
  'an',
  'the',
  'i',
  'my',
  'main',
  'maine',
  'please',
  'plz',
  'add',
  'save',
  'record',
  'note',
  'enter',
  'entry',
  'transaction',
  'expense',
  'spent',
  'spend',
  'paid',
  'pay',
  'bought',
  'purchase',
  'purchased',
  'khareed',
  'khareeda',
  'khareedi',
  'kharida',
  'dalo',
  'daalo',
  'daldo',
  'daaldo',
  'karo',
  'kar',
  'do',
  'rs',
  'pkr',
  'rupee',
  'rupees',
  'rupay',
  'paisa',
  'paise',
  'pese',
  'amount',
  'for',
  'and',
  'in',
  'of',
  'on',
  'at',
  'from',
  'to',
  'via',
  'using',
  'through',
  'ka',
  'ki',
  'ke',
  'ko',
  'me',
  'mein',
  'se',
  'par',
  'pe',
  'liye',
};

/// Produces the compact title stored in the ledger.
///
/// Command/currency filler is removed first, then only the first three useful
/// words are retained. A title made entirely from command filler is rejected
/// as empty so it cannot be stored as a misleading transaction name.
String coreTransactionTitle(String value) {
  final rawWords = RegExp(
    r"[A-Za-z0-9\u0600-\u06FF]+(?:['’-][A-Za-z0-9\u0600-\u06FF]+)?",
  )
      .allMatches(value.trim())
      .map((match) => match.group(0)!)
      .where((word) => word.isNotEmpty)
      .toList(growable: false);
  if (rawWords.isEmpty) return '';

  final coreWords = rawWords
      .where(
        (word) => !_transactionTitleNoiseWords.contains(word.toLowerCase()),
      )
      .toList(growable: false);
  if (coreWords.isEmpty) return '';
  return coreWords.take(maxTransactionTitleWords).join(' ');
}
