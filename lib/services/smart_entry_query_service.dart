import '../models/expense_model.dart';
import 'local_nlp_service.dart';
import 'voice_diagnostics_service.dart';

/// Selects existing ledger entries for read-only financial questions.
List<Expense> selectSmartEntryQueryEntries(
  Iterable<Expense> entries,
  ParsedSmartEntryCommand command, {
  DateTime? referencedMonth,
  String? walletId,
  DateTime? now,
}) {
  final reference = now ?? DateTime.now();
  VoiceDiagnosticsService.instance.stage('query_filter', {
    'reference_local': reference.toIso8601String(),
    'utc_offset_minutes': reference.timeZoneOffset.inMinutes,
    'time_range': command.timeRange.name,
    'referenced_month': referencedMonth?.toIso8601String(),
    'wallet_id': walletId, 'entry_type': command.entryTypeFilter,
    'category': command.category, 'date_semantics': 'local_calendar_days_week_starts_monday',
  });
  final hasCategory = command.category != 'General' &&
      (command.confidenceByField['category'] ?? 0) >= 0.8;
  var title = command.title.trim();
  if (const {
    '', 'Transaction', 'Quick Expense', 'Income Allowance', 'Income / Allowance',
  }.contains(title)) {
    title = '';
  }
  if (referencedMonth != null) {
    title = title
        .replaceAll(
          RegExp(
            r'\b(january|jan|february|feb|march|mar|april|apr|may|june|jun|july|jul|august|aug|september|sept|sep|october|oct|november|nov|december|dec)\b',
            caseSensitive: false,
          ),
          ' ',
        )
        .replaceAll(RegExp(r'\b20\d{2}\b'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  return entries.where((entry) {
    if (entry.deletedAt != null || entry.category == 'Transfer') return false;
    if (referencedMonth != null) {
      if (entry.date.year != referencedMonth.year ||
          entry.date.month != referencedMonth.month) return false;
    } else if (!matchesSmartEntryTimeRange(
      entry.date, command.timeRange, now: reference,
    )) {
      return false;
    }
    if (walletId != null && entry.walletId != walletId) return false;
    if (hasCategory) return entry.category == command.category;
    return command.queryMetric == SmartEntryQueryMetric.summary ||
        title.isEmpty ||
        entry.title.toLowerCase().contains(title.toLowerCase());
  }).toList(growable: false);
}
