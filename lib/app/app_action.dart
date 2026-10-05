import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AppActionType {
  openMonthlyPdf,
  openStatsMonth,
  openMonthlyPlan,
  runMonthlyPlanCommand,
  openBackup,
  persistentQuickEntryOn,
  persistentQuickEntryOff,
  smartRemindersOn,
  smartRemindersOff,
  spokenConfirmationsOn,
  spokenConfirmationsOff,
  smartEntryLanguageRomanUrdu,
  smartEntryLanguageEnglish,
  appLockOn,
  appLockOff,
}

class AppActionRequest {
  final int id;
  final AppActionType action;
  final DateTime? month;
  final String? text;

  DateTime? get targetMonth => month;

  const AppActionRequest({
    required this.id,
    required this.action,
    this.month,
    this.text,
  });
}

class AppActionController extends Notifier<AppActionRequest?> {
  int _nextId = 0;

  @override
  AppActionRequest? build() => null;

  void request(
    AppActionType action, {
    DateTime? month,
    DateTime? targetMonth,
    String? text,
  }) {
    _nextId++;
    state = AppActionRequest(
      id: _nextId,
      action: action,
      month: month ?? targetMonth,
      text: text,
    );
  }

  void consume(int id) {
    if (state?.id == id) state = null;
  }
}

final appActionProvider =
    NotifierProvider<AppActionController, AppActionRequest?>(
  AppActionController.new,
);


DateTime? resolveMonthlyPdfTargetMonth(
  String input, {
  DateTime? now,
}) {
  final reference = now ?? DateTime.now();
  final text = input.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  if (RegExp(
    r'\b(last\s+month|previous\s+month|pichlay\s+mahine|pichle\s+mahine|pichla\s+mahina|last\s+mahina)\b',
  ).hasMatch(text)) {
    return DateTime(reference.year, reference.month - 1);
  }

  if (RegExp(
    r'\b(this\s+month|current\s+month|is\s+mahine|iss\s+mahine|is\s+month|iss\s+month|monthly\s+pdf)\b',
  ).hasMatch(text)) {
    return DateTime(reference.year, reference.month);
  }

  const monthNumbers = <String, int>{
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
    r'\b(january|jan|february|feb|march|mar|april|apr|may|june|jun|july|jul|august|aug|september|sept|sep|october|oct|november|nov|december|dec)(?:\s+(20\d{2}))?\b',
  ).firstMatch(text);
  if (match == null) return null;

  final month = monthNumbers[match.group(1)]!;
  var year = int.tryParse(match.group(2) ?? '') ?? reference.year;
  if (match.group(2) == null && month > reference.month) {
    year--;
  }
  final candidate = DateTime(year, month);
  final currentMonth = DateTime(reference.year, reference.month);
  return candidate.isAfter(currentMonth) ? currentMonth : candidate;
}
