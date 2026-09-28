import 'package:flutter_test/flutter_test.dart';
import 'package:student_expense_manager/models/debt_model.dart';
import 'package:student_expense_manager/services/udhar_entry_filter.dart';

void main() {
  test('search and direction filters exclude settled and deleted records', () {
    final entries = [
      DebtEntry(id: '1', borrowerName: 'Ali Khan', amount: 500, type: 'lent'),
      DebtEntry(id: '2', borrowerName: 'Alina', amount: 200, type: 'borrowed'),
      DebtEntry(id: '3', borrowerName: 'Ali', amount: 100, type: 'lent',
          settledAt: DateTime(2026)),
      DebtEntry(id: '4', borrowerName: 'Ali', amount: 90, type: 'lent',
          deletedAt: DateTime(2026)),
    ];

    expect(filterActiveUdharEntries(entries, query: ' ALI ')
        .map((entry) => entry.id), ['1', '2']);
    expect(filterActiveUdharEntries(entries, query: 'ali', direction: 'lent')
        .map((entry) => entry.id), ['1']);
    expect(filterActiveUdharEntries(entries, query: 'ali', direction: 'borrowed')
        .map((entry) => entry.id), ['2']);
    expect(filterActiveUdharEntries(entries, query: 'sara'), isEmpty);
  });
}
