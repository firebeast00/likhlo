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

  test('transaction batches reject invalid and duplicate records', () {
    final valid = Expense(id: 'one', title: 'Food', amount: 100,
      date: DateTime(2026, 9, 15), category: 'Food', colorValue: 0);
    final duplicate = Expense(id: 'one', title: 'Travel', amount: 200,
      date: DateTime(2026, 9, 15), category: 'Travel', colorValue: 0);
    final invalid = Expense(id: 'invalid', title: 'Invalid', amount: 0,
      date: DateTime(2026, 9, 15), category: 'Food', colorValue: 0);

    expect(isValidTransactionBatch([valid]), isTrue);
    expect(isValidTransactionBatch([valid, duplicate]), isFalse);
    expect(isValidTransactionBatch([invalid]), isFalse);
    expect(isValidTransactionBatch([valid], existingIds: {'one'}), isFalse);
  });

  test('wallet movements preserve total during transfers', () {
    final records = [
      entry('transfer_out', 'expense', 'cash', amount: 350),
      entry('transfer_in', 'income', 'bank', amount: 350),
    ];
    final movements = calculateWalletMovements(records);
    expect(movements['cash'], -350);
    expect(movements['bank'], 350);
    expect(movements.values.fold<double>(0, (a, b) => a + b), 0);
  });

  test('expense and income produce correct wallet deltas', () {
    final records = [
      Expense(id: 'expense', title: 'Food', amount: 120,
        date: DateTime(2026, 9, 15), category: 'Food', colorValue: 0,
        type: 'expense', walletId: 'cash'),
      Expense(id: 'income', title: 'Salary', amount: 500,
        date: DateTime(2026, 9, 15), category: 'Income', colorValue: 0,
        type: 'income', walletId: 'cash'),
    ];
    expect(calculateWalletMovements(records)['cash'], 380);
  });

  test('unpaired or mismatched transfers remain visible', () {
    final records = [entry('a_in', 'income', 'bank'),
      entry('b_out', 'expense', 'cash'),
      entry('b_in', 'income', 'bank', amount: 50)];
    expect(visibleTransactions(records).length, 3);
  });

}
