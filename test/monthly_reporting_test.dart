import 'package:flutter_test/flutter_test.dart';
import 'package:student_expense_manager/models/expense_model.dart';
import 'package:student_expense_manager/models/wallet_model.dart';
import 'package:student_expense_manager/services/backup_service.dart';
import 'package:student_expense_manager/services/monthly_financial_summary_service.dart';

Expense tx({
  required String id,
  required double amount,
  required DateTime date,
  required String type,
  required String wallet,
  required String category,
  String? title,
}) {
  return Expense(
    id: id,
    title: title ?? id,
    amount: amount,
    date: date,
    category: category,
    colorValue: 0,
    type: type,
    walletId: wallet,
  );
}

void main() {
  final cash = Wallet(
    id: 'cash',
    name: 'Cash',
    balance: 0,
    colorValue: 0,
    walletType: 'cash',
  );
  final bank = Wallet(
    id: 'bank',
    name: 'Bank',
    balance: 0,
    colorValue: 0,
    walletType: 'bank',
  );

  test('monthly summary excludes other months, transfers and Udhar from spend',
      () {
    final transferDate = DateTime(2026, 9, 12, 12);
    final summary = buildMonthlyFinancialSummary(
      month: DateTime(2026, 9),
      wallets: [cash, bank],
      linkedUdharIds: const {'debt-1'},
      transactions: [
        tx(
          id: 'salary',
          amount: 1000,
          date: DateTime(2026, 9, 1),
          type: 'income',
          wallet: 'bank',
          category: 'Income',
        ),
        tx(
          id: 'food',
          amount: 200,
          date: DateTime(2026, 9, 2),
          type: 'expense',
          wallet: 'cash',
          category: 'Food',
        ),
        tx(
          id: 'move_out',
          amount: 300,
          date: transferDate,
          type: 'expense',
          wallet: 'cash',
          category: 'Transfer',
        ),
        tx(
          id: 'move_in',
          amount: 300,
          date: transferDate,
          type: 'income',
          wallet: 'bank',
          category: 'Transfer',
        ),
        tx(
          id: 'debt-1',
          amount: 150,
          date: DateTime(2026, 9, 15),
          type: 'expense',
          wallet: 'cash',
          category: 'Udhaar',
        ),
        tx(
          id: 'august',
          amount: 999,
          date: DateTime(2026, 8, 31),
          type: 'expense',
          wallet: 'cash',
          category: 'Food',
        ),
      ],
    );

    expect(summary.rawTransactions.length, 5);
    expect(summary.income, 1000);
    expect(summary.spent, 200);
    expect(summary.netFlow, 800);
    expect(summary.categories, hasLength(1));
    expect(summary.categories.single.key, 'Food');
    expect(summary.categories.single.value, 200);

    // Transfer pair collapses to one visible row, linked Udhar is separate.
    expect(summary.reportTransactions.map((e) => e.id).toSet(), {
      'salary',
      'food',
      'move_out',
    });
  });

  test('wallet activity preserves raw transfer and Udhar legs', () {
    final transferDate = DateTime(2026, 9, 12, 12);
    final summary = buildMonthlyFinancialSummary(
      month: DateTime(2026, 9),
      wallets: [cash, bank],
      linkedUdharIds: const {'debt-1'},
      transactions: [
        tx(
          id: 'salary',
          amount: 1000,
          date: DateTime(2026, 9, 1),
          type: 'income',
          wallet: 'bank',
          category: 'Income',
        ),
        tx(
          id: 'food',
          amount: 200,
          date: DateTime(2026, 9, 2),
          type: 'expense',
          wallet: 'cash',
          category: 'Food',
        ),
        tx(
          id: 'move_out',
          amount: 300,
          date: transferDate,
          type: 'expense',
          wallet: 'cash',
          category: 'Transfer',
        ),
        tx(
          id: 'move_in',
          amount: 300,
          date: transferDate,
          type: 'income',
          wallet: 'bank',
          category: 'Transfer',
        ),
        tx(
          id: 'debt-1',
          amount: 150,
          date: DateTime(2026, 9, 15),
          type: 'expense',
          wallet: 'cash',
          category: 'Udhaar',
        ),
      ],
    );

    final cashStats =
        summary.walletActivity.firstWhere((item) => item.walletId == 'cash');
    final bankStats =
        summary.walletActivity.firstWhere((item) => item.walletId == 'bank');

    expect(cashStats.entryCount, 3);
    expect(cashStats.expense, 200);
    expect(cashStats.transferOut, 300);
    expect(cashStats.udharOut, 150);
    expect(cashStats.netFlow, -650);

    expect(bankStats.entryCount, 2);
    expect(bankStats.income, 1000);
    expect(bankStats.transferIn, 300);
    expect(bankStats.netFlow, 1300);
  });

  test('backup fingerprint ignores creation time but changes with backup data',
      () {
    final first = {
      'createdAt': '2026-10-01T00:00:00Z',
      'data': {
        'expenses': [
          {'id': 'one', 'amount': 100}
        ],
      },
    };
    final later = {
      'createdAt': '2026-10-02T00:00:00Z',
      'data': {
        'expenses': [
          {'id': 'one', 'amount': 100}
        ],
      },
    };
    final changed = {
      'createdAt': '2026-10-02T00:00:00Z',
      'data': {
        'expenses': [
          {'id': 'one', 'amount': 101}
        ],
      },
    };

    expect(
      BackupService.contentFingerprint(first),
      BackupService.contentFingerprint(later),
    );
    expect(
      BackupService.contentFingerprint(first),
      isNot(BackupService.contentFingerprint(changed)),
    );
  });
}
