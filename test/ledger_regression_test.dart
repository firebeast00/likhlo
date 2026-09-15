import 'package:flutter_test/flutter_test.dart';
import 'package:student_expense_manager/models/expense_model.dart';
import 'package:student_expense_manager/providers/expense_provider.dart';

Expense entry(String id, String type, String wallet, {double amount = 100}) =>
    Expense(id: id, title: id, amount: amount, date: DateTime(2026, 9, 15),
      category: 'Transfer', colorValue: 0, type: type, walletId: wallet);

void main() {
  test('global history collapses a pair without changing account movements', () {
    final records = [entry('a_in', 'income', 'bank'),
      entry('a_out', 'expense', 'cash')];
    expect(visibleTransactions(records).map((e) => e.id), ['a_out']);
    expect(records.length, 2);
    expect(records.fold<double>(0, (v, e) =>
        v + (e.type == 'income' ? e.amount : -e.amount)), 0);
  });

  test('unpaired or mismatched transfers remain visible', () {
    final records = [entry('a_in', 'income', 'bank'),
      entry('b_out', 'expense', 'cash'),
      entry('b_in', 'income', 'bank', amount: 50)];
    expect(visibleTransactions(records).length, 3);
  });

}
