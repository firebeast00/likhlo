import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:student_expense_manager/models/debt_model.dart';
import 'package:student_expense_manager/models/expense_model.dart';
import 'package:student_expense_manager/models/wallet_model.dart';
import 'package:student_expense_manager/screens/debt_screen.dart';

void main() {
  late Directory hiveDirectory;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('likhlo_test_');
    Hive.init(hiveDirectory.path);
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(ExpenseAdapter());
    if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(DebtEntryAdapter());
    if (!Hive.isAdapterRegistered(8)) Hive.registerAdapter(WalletAdapter());
    await Hive.openBox<Expense>('expenses');
    await Hive.openBox<DebtEntry>('debts');
    await Hive.openBox<Wallet>('wallets');
    await Hive.openBox('settings');
    await Hive.openBox('preferences');
  });

  tearDownAll(() async {
    await Hive.close();
    await hiveDirectory.delete(recursive: true);
  });

  testWidgets('Udhar screen and account selector fit a small landscape phone',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(640, 360);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await Hive.box<Wallet>('wallets').put(
      'very_long_wallet',
      Wallet(
        id: 'very_long_wallet',
        name: 'A very long mobile banking account name',
        balance: 25000,
        isBackup: false,
        colorValue: 0xFF1565C0,
        walletType: 'bank',
      ),
    );

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: DebtScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Add Record'));
    await tester.pumpAndSettle();

    expect(find.text('Money sent from'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
