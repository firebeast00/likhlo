import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/month_reference_parser.dart';

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
  final reference = normalizeReferencedMonth(now ?? DateTime.now());
  final text = input.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  if (RegExp(r'\bmonthly\s+pdf\b').hasMatch(text)) {
    return reference;
  }

  final parsed = parseReferencedMonth(text, now: reference);
  if (parsed == null) return null;

  final hasExplicitYear = RegExp(r'\b20\d{2}\b').hasMatch(text);
  final hasNamedMonth = RegExp(
    r'\b(january|jan|february|feb|march|mar|april|apr|may|june|jun|july|jul|august|aug|september|sept|sep|october|oct|november|nov|december|dec)\b',
  ).hasMatch(text);

  if (!hasExplicitYear &&
      hasNamedMonth &&
      isReferencedMonthAfter(parsed, reference)) {
    return DateTime(parsed.year - 1, parsed.month);
  }
  if (isReferencedMonthAfter(parsed, reference)) {
    return reference;
  }
  return parsed;
}
