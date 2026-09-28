import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:student_expense_manager/models/debt_model.dart';
import 'package:student_expense_manager/models/expense_model.dart';
import 'package:student_expense_manager/models/wallet_model.dart';
import 'package:student_expense_manager/providers/expense_provider.dart';
import 'package:student_expense_manager/services/udhar_ledger_link_service.dart';

void main() {
  late Directory directory;
  late Box<DebtEntry> debts;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('likhlo_udhar_test_');
    Hive.init(directory.path);
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(ExpenseAdapter());
    if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(DebtEntryAdapter());
    if (!Hive.isAdapterRegistered(8)) Hive.registerAdapter(WalletAdapter());
    await Hive.openBox<Wallet>('wallets');
    await Hive.openBox<Expense>('expenses');
    debts = await Hive.openBox<DebtEntry>('debts');
  });

  setUp(() async {
    await Hive.box<Wallet>('wallets').clear();
    await Hive.box<Expense>('expenses').clear();
    await debts.clear();
    await Hive.box<Wallet>('wallets').put(
      'cash',
      Wallet(
        id: 'cash',
        name: 'Cash',
        balance: 1000,
        colorValue: 0xff00ff00,
      ),
    );
  });

  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  Expense movement(String id, double amount, String type, String title) =>
      Expense(
        id: id,
        title: title,
        amount: amount,
        category: 'Udhaar',
        date: DateTime.now(),
        colorValue: 0xff000000,
        type: type,
        walletId: 'cash',
      );

  test('borrowed money changes the wallet without counting as earnings', () async {
    await debts.add(DebtEntry(
      id: 'borrow-1',
      borrowerName: 'Sara',
      amount: 600,
      type: 'borrowed',
      walletId: 'cash',
    ));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final ledger = container.read(expenseProvider.notifier);
    expect(await ledger.addExpense(
      movement('borrow-1', 600, 'income', 'Borrowed from Sara'),
    ), isTrue);
    expect(container.read(walletMovementsProvider)['cash'], 600);
    expect(container.read(monthlyLedgerProvider(DateTime.now())).income, 0);

    final settlementId = UdharLedgerLinkService.settlementId('borrow-1');
    expect(await ledger.addExpense(
      movement(settlementId, 600, 'expense', 'Udhaar repaid: Sara'),
    ), isTrue);
    final debt = debts.values.single;
    await debts.put(debt.key, debt.copyWith(settledAt: DateTime.now()));
    expect(container.read(walletMovementsProvider)['cash'], 0);
    expect(container.read(monthlyLedgerProvider(DateTime.now())).spent, 0);

    expect(await ledger.deleteExpense(settlementId), isTrue);
    expect(debts.values.single.settledAt, isNull);
    expect(container.read(walletMovementsProvider)['cash'], 600);
    expect(await ledger.restoreExpense(settlementId), isTrue);
    expect(debts.values.single.settledAt, isNotNull);
    expect(container.read(walletMovementsProvider)['cash'], 0);
  });

  test('Main edits, deletes, restores and removes linked Udhar entries', () async {
    await debts.add(DebtEntry(
      id: 'lend-1',
      borrowerName: 'Ali',
      amount: 200,
      type: 'lent',
      walletId: 'cash',
    ));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final ledger = container.read(expenseProvider.notifier);
    expect(await ledger.addExpense(
      movement('lend-1', 200, 'expense', 'Udhaar: Ali'),
    ), isTrue);
    expect(container.read(walletMovementsProvider)['cash'], -200);
    expect(container.read(monthlyLedgerProvider(DateTime.now())).spent, 0);

    expect(await ledger.editExpense(
      'lend-1',
      movement('lend-1', 150, 'expense', 'Udhaar: Bilal'),
    ), isTrue);
    expect(debts.values.single.borrowerName, 'Bilal');
    expect(debts.values.single.amount, 150);
    expect(container.read(walletMovementsProvider)['cash'], -150);

    expect(await ledger.deleteExpense('lend-1'), isTrue);
    expect(debts.values.single.deletedAt, isNotNull);
    expect(container.read(walletMovementsProvider)['cash'], isNull);
    expect(await ledger.restoreExpense('lend-1'), isTrue);
    expect(debts.values.single.deletedAt, isNull);

    final settlementId = UdharLedgerLinkService.settlementId('lend-1');
    expect(await ledger.addExpense(
      movement(settlementId, 150, 'income', 'Udhaar returned: Bilal'),
    ), isTrue);
    final debt = debts.values.single;
    await debts.put(debt.key, debt.copyWith(settledAt: DateTime.now()));
    expect(await ledger.editExpense(
      'lend-1',
      movement('lend-1', 120, 'expense', 'Udhaar: Kareem'),
    ), isTrue);
    expect(debts.values.single.borrowerName, 'Kareem');
    expect(debts.values.single.amount, 120);
    expect(ledger.findById(settlementId)?.amount, 120);
    expect(ledger.findById(settlementId)?.title, 'Udhaar returned: Kareem');
    expect(await ledger.deleteExpense('lend-1'), isTrue);
    expect(ledger.findDeletedById(settlementId), isNotNull);
    expect(debts.values.single.deletedAt, isNotNull);
    expect(await ledger.restoreExpense('lend-1'), isTrue);
    expect(ledger.findById(settlementId), isNotNull);
    expect(debts.values.single.settledAt, isNotNull);
    expect(await ledger.deleteExpense('lend-1'), isTrue);
    expect(await ledger.permanentlyDelete('lend-1'), isTrue);
    expect(debts.values, isEmpty);
    expect(ledger.findDeletedById(settlementId), isNull);
  });

  test('a borrowed loan cannot be deleted when its money is already spent', () async {
    await debts.add(DebtEntry(
      id: 'borrow-spent',
      borrowerName: 'Sara',
      amount: 600,
      type: 'borrowed',
      walletId: 'cash',
    ));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final ledger = container.read(expenseProvider.notifier);
    expect(await ledger.addExpense(
      movement('borrow-spent', 600, 'income', 'Borrowed from Sara'),
    ), isTrue);
    expect(await ledger.addExpense(Expense(
      id: 'spent-money',
      title: 'Groceries',
      amount: 1200,
      category: 'Food',
      date: DateTime.now(),
      colorValue: 0xff000000,
      walletId: 'cash',
    )), isTrue);
    expect(await ledger.deleteExpense('borrow-spent'), isFalse);
    expect(debts.values.single.deletedAt, isNull);
    expect(ledger.findById('borrow-spent'), isNotNull);
  });
}
