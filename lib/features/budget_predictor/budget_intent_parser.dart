import '../../services/local_nlp_service.dart';
import '../../services/pakistani_language_normalizer.dart';

enum BudgetIntentAction {
  setBudget,
  setSavingsGoal,
  setBuffer,
  setItemAmount,
  rememberRecurring,
  markOneTime,
  reduceItem,
  increaseItem,
  queryRecommended,
  queryDailySafe,
  queryCanSpend,
  queryWhy,
  unknown,
}

class BudgetIntent {
  final BudgetIntentAction action;
  final String original;
  final String normalized;
  final double? amount;
  final String? target;

  const BudgetIntent({
    required this.action,
    required this.original,
    required this.normalized,
    this.amount,
    this.target,
  });

  bool get isQuery => {
        BudgetIntentAction.queryRecommended,
        BudgetIntentAction.queryDailySafe,
        BudgetIntentAction.queryCanSpend,
        BudgetIntentAction.queryWhy,
      }.contains(action);
}

class BudgetIntentParser {
  final PakistaniLanguageNormalizer normalizer;
  final LocalNlpService nlp;

  BudgetIntentParser({
    PakistaniLanguageNormalizer? normalizer,
    LocalNlpService? nlp,
  })  : normalizer = normalizer ?? PakistaniLanguageNormalizer(),
        nlp = nlp ?? LocalNlpService();

  List<BudgetIntent> parseMany(String input) {
    final normalized = normalizer.normalize(input).normalized;
    final parts = normalized
        .split(RegExp(r'\s*(?:,|\baur\b|\band\b)\s*'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (parts.length <= 1) return [parse(input)];
    return [
      for (final part in parts)
        _parseNormalized(part, original: part),
    ];
  }

  BudgetIntent parse(String input) {
    final normalized = normalizer.normalize(input).normalized;
    return _parseNormalized(normalized, original: input);
  }

  BudgetIntent _parseNormalized(
    String normalized, {
    required String original,
  }) {
    final amount = _amount(normalized);

    if (_has(normalized, r'\b(can i|can me|kya me|kya main)\b') &&
        _has(normalized, r'\b(spend|kharch)\b')) {
      return BudgetIntent(
        action: BudgetIntentAction.queryCanSpend,
        original: original,
        normalized: normalized,
        amount: amount,
        target: _target(normalized),
      );
    }

    if (_has(normalized, r'\b(daily|roz|rozana|per day)\b') &&
        _has(normalized, r'\b(spend|kharch|kitna|safe)\b')) {
      return BudgetIntent(
        action: BudgetIntentAction.queryDailySafe,
        original: original,
        normalized: normalized,
      );
    }

    if (_has(normalized, r'\b(why|kyun|kiun|reason)\b') &&
        _has(normalized, r'\bbudget\b')) {
      return BudgetIntent(
        action: BudgetIntentAction.queryWhy,
        original: original,
        normalized: normalized,
      );
    }

    if (_has(normalized, r'\b(safe|recommended|suggest|kitna)\b') &&
        _has(normalized, r'\bbudget\b')) {
      return BudgetIntent(
        action: BudgetIntentAction.queryRecommended,
        original: original,
        normalized: normalized,
      );
    }

    if (_has(
      normalized,
      r'\b(save|saving|savings|bachat|bacha(?:na|ne)|save karni)\b',
    )) {
      return BudgetIntent(
        action: BudgetIntentAction.setSavingsGoal,
        original: original,
        normalized: normalized,
        amount: amount,
      );
    }

    if (_has(normalized, r'\b(buffer|safety|reserve|emergency)\b') &&
        amount != null) {
      return BudgetIntent(
        action: BudgetIntentAction.setBuffer,
        original: original,
        normalized: normalized,
        amount: amount,
      );
    }

    if (_has(
      normalized,
      r'\b(one time|one-time|sirf is month|sirf iss month|dobara nahi|repeat nahi)\b',
    )) {
      return BudgetIntent(
        action: BudgetIntentAction.markOneTime,
        original: original,
        normalized: normalized,
        target: _target(normalized),
      );
    }

    if (_has(
      normalized,
      r'\b(recurring|repeat|har month|har mahina|monthly|yaad rakh|remember)\b',
    )) {
      return BudgetIntent(
        action: BudgetIntentAction.rememberRecurring,
        original: original,
        normalized: normalized,
        target: _target(normalized),
      );
    }

    if (_has(normalized, r'\bbudget\b') && amount != null) {
      return BudgetIntent(
        action: BudgetIntentAction.setBudget,
        original: original,
        normalized: normalized,
        amount: amount,
      );
    }

    if (_has(normalized, r'\b(kam|reduce|lower|less)\b')) {
      return BudgetIntent(
        action: BudgetIntentAction.reduceItem,
        original: original,
        normalized: normalized,
        target: _target(normalized),
      );
    }

    if (_has(normalized, r'\b(zyada|increase|raise|more)\b')) {
      return BudgetIntent(
        action: BudgetIntentAction.increaseItem,
        original: original,
        normalized: normalized,
        target: _target(normalized),
      );
    }

    if (amount != null &&
        _has(
          normalized,
          r'\b(max|maximum|limit|rakho|rakhna|set|target)\b',
        )) {
      return BudgetIntent(
        action: BudgetIntentAction.setItemAmount,
        original: original,
        normalized: normalized,
        amount: amount,
        target: _target(normalized),
      );
    }

    if (amount != null) {
      final target = _target(normalized);
      if (target != null && target.isNotEmpty) {
        return BudgetIntent(
          action: BudgetIntentAction.setItemAmount,
          original: original,
          normalized: normalized,
          amount: amount,
          target: target,
        );
      }
    }

    return BudgetIntent(
      action: BudgetIntentAction.unknown,
      original: original,
      normalized: normalized,
      amount: amount,
      target: _target(normalized),
    );
  }

  double? _amount(String input) {
    final parsed = nlp.parseCommand(input, const <String>[]);
    if (parsed.amount.isFinite && parsed.amount > 0) return parsed.amount;

    final match = RegExp(
      r'\b(\d+(?:\.\d+)?)\s*(k|thousand|hazar|hazaar|lakh|lac|million|crore|cr)?\b',
    ).firstMatch(input);
    if (match == null) return null;
    final base = double.tryParse(match.group(1)!);
    if (base == null || !base.isFinite || base <= 0) return null;
    switch (match.group(2)) {
      case 'k':
      case 'thousand':
      case 'hazar':
      case 'hazaar':
        return base * 1000;
      case 'lakh':
      case 'lac':
        return base * 100000;
      case 'million':
        return base * 1000000;
      case 'crore':
      case 'cr':
        return base * 10000000;
      default:
        return base;
    }
  }

  String? _target(String input) {
    var value = input
        .replaceAll(
          RegExp(
            r'\b\d+(?:\.\d+)?\s*(?:k|thousand|hazar|hazaar|lakh|lac|million|crore|cr)?\b',
          ),
          ' ',
        )
        .replaceAll(
          RegExp(
            r'\b(budget|save|saving|savings|bachat|buffer|safety|reserve|emergency|max|maximum|limit|rakho|rakhna|set|target|kam|reduce|lower|less|zyada|increase|raise|more|one time|one-time|sirf|is|iss|month|dobara|nahi|recurring|repeat|har|mahina|monthly|yaad|rakh|remember|karo|karni|karna|hai|me|main|can|i|kya|spend|kharch|please)\b',
          ),
          ' ',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (value.isEmpty) return null;
    return value;
  }

  bool _has(String input, String pattern) =>
      RegExp(pattern, caseSensitive: false).hasMatch(input);
}
