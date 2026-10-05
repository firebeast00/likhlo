DateTime normalizeReferencedMonth(DateTime value) =>
    DateTime(value.year, value.month);

DateTime? parseReferencedMonth(
  String input, {
  DateTime? now,
}) {
  final reference = normalizeReferencedMonth(now ?? DateTime.now());
  final text = input.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  if (text.isEmpty) return null;

  if (RegExp(
    r'\b(this\s+month|current\s+month|is\s+mahine|iss\s+mahine|is\s+month)\b',
  ).hasMatch(text)) {
    return reference;
  }
  if (RegExp(
    r'\b(last\s+month|previous\s+month|pichl(?:a|ay|e)\s+mahina|pichl(?:ay|e)\s+mahine|guzra\s+mahina)\b',
  ).hasMatch(text)) {
    return DateTime(reference.year, reference.month - 1);
  }
  if (RegExp(
    r'\b(next\s+month|agla\s+mahina|aglay\s+mahine|agle\s+mahine)\b',
  ).hasMatch(text)) {
    return DateTime(reference.year, reference.month + 1);
  }

  const months = <String, int>{
    'january': 1,
    'jan': 1,
    'february': 2,
    'feb': 2,
    'march': 3,
    'mar': 3,
    'april': 4,
    'apr': 4,
    'may': 5,
    'june': 6,
    'jun': 6,
    'july': 7,
    'jul': 7,
    'august': 8,
    'aug': 8,
    'september': 9,
    'sep': 9,
    'sept': 9,
    'october': 10,
    'oct': 10,
    'november': 11,
    'nov': 11,
    'december': 12,
    'dec': 12,
  };

  final match = RegExp(
    r'\b(january|jan|february|feb|march|mar|april|apr|may|june|jun|july|jul|august|aug|september|sept|sep|october|oct|november|nov|december|dec)\b(?:\s+(20\d{2}))?',
  ).firstMatch(text);
  if (match == null) return null;

  final month = months[match.group(1)]!;
  final explicitYear = int.tryParse(match.group(2) ?? '');
  return DateTime(explicitYear ?? reference.year, month);
}

bool isReferencedMonthAfter(
  DateTime month,
  DateTime other,
) {
  final a = month.year * 12 + month.month;
  final b = other.year * 12 + other.month;
  return a > b;
}
