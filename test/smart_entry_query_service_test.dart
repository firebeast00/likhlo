import 'package:flutter_test/flutter_test.dart';
import 'package:student_expense_manager/models/expense_model.dart';
import 'package:student_expense_manager/services/local_nlp_service.dart';
import 'package:student_expense_manager/services/smart_command.dart';
import 'package:student_expense_manager/services/smart_entry_query_service.dart';
import 'package:student_expense_manager/services/smart_input_engine.dart';

void main() {
  final engine = SmartInputEngine();
  final now = DateTime(2026, 10, 7);
  const categories = ['General', 'Food', 'Transport', 'Shopping', 'Education'];

  Expense entry(String id, double amount, String category, DateTime date, {
    String type = 'expense',
    String walletId = 'cash',
    bool deleted = false,
  }) => Expense(
    id: id, title: id, amount: amount, category: category, date: date,
    colorValue: 0, type: type, walletId: walletId,
    deletedAt: deleted ? now : null,
  );

  final ledger = [
    entry('Biryani', 100, 'Food', DateTime(2026, 10, 5)),
    entry('Bus', 200, 'Transport', now, walletId: 'jazzcash'),
    entry('Breakfast', 300, 'Food', DateTime(2026, 10, 4)),
    entry('Shoes', 400, 'Shopping', DateTime(2026, 10, 1)),
    entry('September lunch', 800, 'Food', DateTime(2026, 9, 30)),
    entry('September bus', 100, 'Transport', DateTime(2026, 9, 29)),
    entry('Allowance', 5000, 'Income / Allowance', now, type: 'income'),
    entry('Wallet transfer', 700, 'Transfer', now),
    entry('Deleted food', 9000, 'Food', now, deleted: true),
  ];

  double spending(String text, {
    DateTime? month,
    String? walletId,
    SmartEntryTimeRange? expectedRange,
  }) {
    final command = engine.parse(
      text, categories, source: SmartInputSource.voice,
    ).parsed;
    expect(command.intent, SmartEntryIntent.query, reason: text);
    expect(command.queryMetric, SmartEntryQueryMetric.spending, reason: text);
    if (expectedRange != null) {
      expect(command.timeRange, expectedRange, reason: text);
    }
    return selectSmartEntryQueryEntries(
      ledger, command, referencedMonth: month, walletId: walletId, now: now,
    ).where((item) => item.type == 'expense')
        .fold<double>(0, (sum, item) => sum + item.amount);
  }

  test('generic monthly spending includes all active expense categories', () {
    for (final text in [
      'is mahine kitne kharch hue',
      'es mahiny kitny khurch huwy',
      'how much did I spend this month',
    ]) {
      expect(spending(text, expectedRange: SmartEntryTimeRange.thisMonth), 1000);
      expect(spending(text, month: DateTime(2026, 10)), 1000);
    }
  });

  test('weekly wording and the exact phone ASR error do not filter titles', () {
    for (final text in [
      'is hafte kitne kharch hue',
      'is Hafte ki be kharch hue',
      'es haftay kitny khurch huwy',
      'es hasty kitny khurch huwy',
    ]) {
      expect(spending(text, expectedRange: SmartEntryTimeRange.thisWeek), 300);
      final command = engine.parse(
        text, categories, source: SmartInputSource.voice,
      ).parsed;
      expect(command.title, 'Transaction', reason: text);
      expect(command.category, 'General', reason: text);
    }
  });

  test('daily and explicit category questions retain their scopes', () {
    expect(spending('Aaj kitne kharch hue',
      expectedRange: SmartEntryTimeRange.today), 200);
    expect(spending('is mahine food per kitne kharch hue'), 400);
    expect(spending('transport per kitne kharch hue'), 300);
    expect(spending('is mahine transport per kitne kharch hue'), 200);
  });

  test('historical months and wallet filters stay independent', () {
    expect(spending('September kitne kharch hue',
      month: DateTime(2026, 9)), 900);
    expect(spending('is mahine kitne kharch hue', walletId: 'cash'), 800);
    expect(spending('is mahine kitne kharch hue', walletId: 'jazzcash'), 200);
  });

  test('week boundaries, year boundaries and explicit counts remain intact', () {
    expect(matchesSmartEntryTimeRange(
      DateTime(2026, 10, 4), SmartEntryTimeRange.thisWeek, now: now), isFalse);
    expect(matchesSmartEntryTimeRange(
      DateTime(2026, 10, 5), SmartEntryTimeRange.thisWeek, now: now), isTrue);
    expect(matchesSmartEntryTimeRange(
      DateTime(2026, 10, 12), SmartEntryTimeRange.thisWeek, now: now), isFalse);
    expect(matchesSmartEntryTimeRange(
      DateTime(2025, 12, 31), SmartEntryTimeRange.lastMonth,
      now: DateTime(2026, 1, 2)), isTrue);
    expect(engine.parse('how many expenses this month', categories)
      .parsed.queryMetric, SmartEntryQueryMetric.transactionCount);
  });

  test('income questions and transaction additions retain their behavior', () {
    final income = engine.parse('is mahine kitni income aayi', categories).parsed;
    expect(income.queryMetric, SmartEntryQueryMetric.income);
    final incomeEntries = selectSmartEntryQueryEntries(ledger, income, now: now)
        .where((item) => item.type == 'income');
    expect(incomeEntries.fold<double>(0, (sum, item) => sum + item.amount), 5000);
    final addition = engine.parse('500 biryani', categories).parsed;
    expect(addition.intent, SmartEntryIntent.addExpense);
    expect(addition.amount, 500);
    expect(addition.title, 'Biryani');
  });
}
