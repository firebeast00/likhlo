import 'package:flutter_test/flutter_test.dart';
import 'package:student_expense_manager/models/expense_model.dart';
import 'package:student_expense_manager/providers/expense_provider.dart';

Expense entry(String id, String type, String wallet, {double amount = 100}) =>
    Expense(
        id: id,
        title: id,
        amount: amount,
        date: DateTime(2026, 9, 15),
        category: 'Transfer',
        colorValue: 0,
        type: type,
        walletId: wallet);

void main() {
  test('global history collapses a pair without changing account movements',
      () {
    final records = [
      entry('a_in', 'income', 'bank'),
      entry('a_out', 'expense', 'cash')
    ];
    expect(visibleTransactions(records).map((e) => e.id), ['a_out']);
    expect(records.length, 2);
    expect(
        records.fold<double>(
            0, (v, e) => v + (e.type == 'income' ? e.amount : -e.amount)),
        0);
  });

  test('transaction batches reject invalid and duplicate records', () {
    final valid = Expense(
        id: 'one',
        title: 'Food',
        amount: 100,
        date: DateTime(2026, 9, 15),
        category: 'Food',
        colorValue: 0);
    final duplicate = Expense(
        id: 'one',
        title: 'Travel',
        amount: 200,
        date: DateTime(2026, 9, 15),
        category: 'Travel',
        colorValue: 0);
    final invalid = Expense(
        id: 'invalid',
        title: 'Invalid',
        amount: 0,
        date: DateTime(2026, 9, 15),
        category: 'Food',
        colorValue: 0);

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
      Expense(
          id: 'expense',
          title: 'Food',
          amount: 120,
          date: DateTime(2026, 9, 15),
          category: 'Food',
          colorValue: 0,
          type: 'expense',
          walletId: 'cash'),
      Expense(
          id: 'income',
          title: 'Salary',
          amount: 500,
          date: DateTime(2026, 9, 15),
          category: 'Income',
          colorValue: 0,
          type: 'income',
          walletId: 'cash'),
    ];
    expect(calculateWalletMovements(records)['cash'], 380);
  });

  test('unpaired or mismatched transfers remain visible', () {
    final records = [
      entry('a_in', 'income', 'bank'),
      entry('b_out', 'expense', 'cash'),
      entry('b_in', 'income', 'bank', amount: 50)
    ];
    expect(visibleTransactions(records).length, 3);
  });

  test('wallet guard rejects overdrafts and accepts exact available amount',
      () {
    final existing = [
      Expense(
          id: 'old',
          title: 'Food',
          amount: 200,
          date: DateTime(2026, 9, 15),
          category: 'Food',
          colorValue: 0,
          type: 'expense',
          walletId: 'cash'),
    ];
    final exact = Expense(
        id: 'exact',
        title: 'Travel',
        amount: 300,
        date: DateTime(2026, 9, 15),
        category: 'Travel',
        colorValue: 0,
        type: 'expense',
        walletId: 'cash');
    final tooMuch = exact.copyWith(id: 'too-much', amount: 301);

    expect(
        keepsWalletBalancesNonNegative(
          openingBalances: {'cash': 500},
          existingEntries: existing,
          proposedEntries: [exact],
        ),
        isTrue);
    expect(
        keepsWalletBalancesNonNegative(
          openingBalances: {'cash': 500},
          existingEntries: existing,
          proposedEntries: [tooMuch],
        ),
        isFalse);
  });

  test('editing income cannot create a negative account balance', () {
    final income = Expense(
        id: 'income',
        title: 'Income',
        amount: 100,
        date: DateTime(2026, 9, 15),
        category: 'Income',
        colorValue: 0,
        type: 'income',
        walletId: 'cash');
    final spending = Expense(
        id: 'spending',
        title: 'Spending',
        amount: 100,
        date: DateTime(2026, 9, 15),
        category: 'Food',
        colorValue: 0,
        type: 'expense',
        walletId: 'cash');

    expect(
        keepsWalletBalancesNonNegative(
          openingBalances: {'cash': 0},
          existingEntries: [income, spending],
          proposedEntries: [income.copyWith(amount: 50)],
          replacedIds: {'income'},
        ),
        isFalse);
  });

  test('legacy negative balance can improve but cannot get worse', () {
    final income = Expense(
        id: 'income',
        title: 'Income',
        amount: 50,
        date: DateTime(2026, 9, 15),
        category: 'Income',
        colorValue: 0,
        type: 'income',
        walletId: 'cash');
    final expense =
        income.copyWith(id: 'expense', title: 'Expense', type: 'expense');

    expect(
        keepsWalletBalancesNonNegative(
          openingBalances: {'cash': -100},
          existingEntries: const [],
          proposedEntries: [income],
        ),
        isTrue);
    expect(
        keepsWalletBalancesNonNegative(
          openingBalances: {'cash': -100},
          existingEntries: const [],
          proposedEntries: [expense],
        ),
        isFalse);
  });

  test('wallet guard credits the old expense while editing', () {
    final old = Expense(
        id: 'edit',
        title: 'Food',
        amount: 400,
        date: DateTime(2026, 9, 15),
        category: 'Food',
        colorValue: 0,
        type: 'expense',
        walletId: 'cash');
    final updated = old.copyWith(amount: 450);

    expect(
        keepsWalletBalancesNonNegative(
          openingBalances: {'cash': 500},
          existingEntries: [old],
          proposedEntries: [updated],
          replacedIds: {'edit'},
        ),
        isTrue);
  });

  test('ledger index caches month buckets and wallet movements', () {
    final september = Expense(
      id: 'sep-food',
      title: 'Food',
      amount: 200,
      date: DateTime(2026, 9, 15),
      category: 'Food',
      colorValue: 0,
      type: 'expense',
      walletId: 'cash',
    );
    final august = Expense(
      id: 'aug-income',
      title: 'Salary',
      amount: 1000,
      date: DateTime(2026, 8, 1),
      category: 'Income',
      colorValue: 0,
      type: 'income',
      walletId: 'bank',
    );

    final index = LedgerIndex.rebuild([september, august]);
    final septemberBucket = index.bucketFor(DateTime(2026, 9));

    expect(index.byId['sep-food'], same(september));
    expect(septemberBucket?.spent, 200);
    expect(septemberBucket?.income, 0);
    expect(index.walletMovements['cash'], -200);
    expect(index.walletMovements['bank'], 1000);
  });

  test('ledger index preserves untouched month bucket identity', () {
    final august = Expense(
      id: 'aug',
      title: 'August',
      amount: 100,
      date: DateTime(2026, 8, 10),
      category: 'Food',
      colorValue: 0,
      walletId: 'cash',
    );
    final september = Expense(
      id: 'sep',
      title: 'September',
      amount: 200,
      date: DateTime(2026, 9, 10),
      category: 'Food',
      colorValue: 0,
      walletId: 'cash',
    );
    final previous = LedgerIndex.rebuild([september, august]);
    final augustBucket = previous.bucketFor(DateTime(2026, 8));

    final october = Expense(
      id: 'oct',
      title: 'October',
      amount: 300,
      date: DateTime(2026, 10, 1),
      category: 'Food',
      colorValue: 0,
      walletId: 'cash',
    );
    final next = previous.withAdded([october]);

    expect(next.bucketFor(DateTime(2026, 8)), same(augustBucket));
    expect(next.bucketFor(DateTime(2026, 10))?.spent, 300);
    expect(next.walletMovements['cash'], -600);
  });

  test('cached add guard matches full-ledger overdraft behavior', () {
    final existing = Expense(
      id: 'old',
      title: 'Old expense',
      amount: 200,
      date: DateTime(2026, 9, 1),
      category: 'Food',
      colorValue: 0,
      walletId: 'cash',
    );
    final proposed = Expense(
      id: 'new',
      title: 'New expense',
      amount: 301,
      date: DateTime(2026, 9, 2),
      category: 'Food',
      colorValue: 0,
      walletId: 'cash',
    );
    final movements = calculateWalletMovements([existing]);

    final cached = keepsCachedWalletBalancesNonNegative(
      openingBalances: {'cash': 500},
      currentMovements: movements,
      proposedEntries: [proposed],
    );
    final full = keepsWalletBalancesNonNegative(
      openingBalances: {'cash': 500},
      existingEntries: [existing],
      proposedEntries: [proposed],
    );

    expect(cached, full);
    expect(cached, isFalse);
  });

  test(
      'PDF report totals count transfer pairs once and exclude them from income',
      () {
    final records = [
      entry('move_out', 'expense', 'cash', amount: 350),
      entry('move_in', 'income', 'bank', amount: 350),
      Expense(
        id: 'salary',
        title: 'Salary',
        amount: 5000,
        date: DateTime(2026, 9, 15),
        category: 'Income / Allowance',
        colorValue: 0,
        type: 'income',
        walletId: 'bank',
      ),
      Expense(
        id: 'food',
        title: 'Food',
        amount: 250,
        date: DateTime(2026, 9, 15),
        category: 'Food',
        colorValue: 0,
        type: 'expense',
        walletId: 'cash',
      ),
    ];

    final report = calculateLedgerReportSummary(records);

    expect(report.transactions.length, 3);
    expect(report.transferCount, 1);
    expect(report.transferTotal, 350);
    expect(report.incomeCount, 1);
    expect(report.incomeTotal, 5000);
    expect(report.expenseCount, 1);
    expect(report.expenseTotal, 250);
  });
}
