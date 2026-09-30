import '../../services/primary_intent_router.dart';

class MultiEntryParser {
  final PrimaryIntentRouter intentRouter;

  const MultiEntryParser({
    this.intentRouter = const PrimaryIntentRouter(),
  });

  List<String>? tryParseBatch(String rawText) {
    final input = rawText.trim();
    if (input.isEmpty) return null;

    final route = intentRouter.classify(input);
    if (route.intent != RoutedSmartIntent.addExpense &&
        route.intent != RoutedSmartIntent.addIncome) {
      return null;
    }

    final anchors = _amountAnchors(input);
    if (anchors.length < 2) return null;

    final segments = <String>[];
    var segmentStart = 0;

    for (var index = 0; index < anchors.length - 1; index++) {
      final current = anchors[index];
      final next = anchors[index + 1];
      final between = input.substring(current.end, next.start);
      final delimiter = _lastDelimiter(between);
      if (delimiter == null) return null;

      final delimiterStart = current.end + delimiter.start;
      final delimiterEnd = current.end + delimiter.end;
      final segment = input.substring(segmentStart, delimiterStart).trim();
      if (segment.isEmpty || _amountAnchors(segment).length != 1) {
        return null;
      }
      segments.add(_cleanSegment(segment));
      segmentStart = delimiterEnd;
    }

    final tail = input.substring(segmentStart).trim();
    if (tail.isEmpty || _amountAnchors(tail).length != 1) return null;
    segments.add(_cleanSegment(tail));

    return segments.length > 1 ? segments : null;
  }

  List<_AmountAnchor> _amountAnchors(String input) {
    final matches = _numericAmountPattern.allMatches(input);
    final anchors = <_AmountAnchor>[];

    for (final match in matches) {
      final value = match.group(0);
      if (value == null || value.trim().isEmpty) continue;
      if (_looksLikeDateOrTime(input, match.start, match.end, value)) {
        continue;
      }
      anchors.add(
        _AmountAnchor(
          start: match.start,
          end: match.end,
        ),
      );
    }
    return anchors;
  }

  _DelimiterMatch? _lastDelimiter(String between) {
    _DelimiterMatch? result;
    for (final match in _delimiterPattern.allMatches(between)) {
      result = _DelimiterMatch(match.start, match.end);
    }
    return result;
  }

  bool _looksLikeDateOrTime(
    String input,
    int start,
    int end,
    String value,
  ) {
    final numeric = value
        .toLowerCase()
        .replaceAll(RegExp(r'(rs\.?|pkr)'), '')
        .replaceAll(',', '')
        .replaceAll(
          RegExp(
            r'\s*(k|thousand|hazar|hazaar|lakh|lac|lak|million|crore|krore|cr)\s*$',
          ),
          '',
        )
        .trim();

    final number = double.tryParse(numeric);
    final hasMoneyMarker = RegExp(
      r'\b(rs\.?|pkr)\b|(?:\d)\s*(k|thousand|hazar|hazaar|lakh|lac|lak|million|crore|krore|cr)\b',
      caseSensitive: false,
    ).hasMatch(value);

    final before = input.substring(start > 18 ? start - 18 : 0, start);
    final after = input.substring(end, end + 18 < input.length ? end + 18 : input.length);

    if (RegExp(r'[/:-]\s*$').hasMatch(before) ||
        RegExp(r'^\s*[/:-]').hasMatch(after)) {
      return true;
    }

    if (number != null &&
        number >= 1 &&
        number <= 31 &&
        RegExp(
          r'^\s*(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:tember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\b',
          caseSensitive: false,
        ).hasMatch(after)) {
      return true;
    }

    if (!hasMoneyMarker &&
        number != null &&
        number >= 1 &&
        number <= 24 &&
        (RegExp(r'\b(at|time)\s*$', caseSensitive: false).hasMatch(before) ||
            RegExp(r'^\s*(am|pm)\b', caseSensitive: false).hasMatch(after))) {
      return true;
    }

    return false;
  }

  String _cleanSegment(String value) {
    return value
        .replaceAll(RegExp(r'^[,;:\s]+'), '')
        .replaceAll(RegExp(r'[,;:\s]+$'), '')
        .trim();
  }

  static final RegExp _numericAmountPattern = RegExp(
    r'(?:(?:rs\.?|pkr)\s*)?\d+(?:[,.]\d+)?(?:\s*(?:k|thousand|hazar|hazaar|lakh|lac|lak|million|crore|krore|cr))?',
    caseSensitive: false,
  );

  static final RegExp _delimiterPattern = RegExp(
    r'(?:[,;]|\b(?:and|aur|phir|then|plus|next)\b)',
    caseSensitive: false,
  );
}

class _AmountAnchor {
  final int start;
  final int end;

  const _AmountAnchor({
    required this.start,
    required this.end,
  });
}

class _DelimiterMatch {
  final int start;
  final int end;

  const _DelimiterMatch(this.start, this.end);
}
