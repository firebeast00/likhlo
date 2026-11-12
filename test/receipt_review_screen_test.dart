import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:student_expense_manager/models/expense_model.dart';
import 'package:student_expense_manager/models/wallet_model.dart';
import 'package:student_expense_manager/screens/receipt_review_screen.dart';
import 'package:student_expense_manager/services/ocr_scanner_service.dart';
import 'package:student_expense_manager/services/transaction_executor.dart';
import 'fixtures/jazzcash_receipt.dart';

class _ReceiptStore implements TransactionStore {
  final List<Expense> entries = [];
  @override
  Future<bool> add(Expense entry) async {
    entries.add(entry);
    return true;
  }

  @override
  Future<bool> addAll(Iterable<Expense> additions) async {
    entries.addAll(additions);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late ProviderContainer container;
  late _ReceiptStore store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('likhlo_receipt_');
    Hive.init(directory.path);
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(ExpenseAdapter());
    if (!Hive.isAdapterRegistered(8)) Hive.registerAdapter(WalletAdapter());
    await Hive.openBox('preferences');
    await Hive.openBox<Expense>('expenses');
    store = _ReceiptStore();
    final wallets = await Hive.openBox<Wallet>('wallets');
    await wallets.put(
      'cash',
      Wallet(id: 'cash', name: 'Cash', balance: 10000, colorValue: 0),
    );
    container = ProviderContainer(
      overrides: [
        transactionExecutorProvider.overrideWith(
          (ref) => TransactionExecutor(store, enableAudio: false),
        ),
      ],
    );
  });
  tearDown(() async {
    container.dispose();
    await Hive.close();
    await directory.delete(recursive: true);
  });
  Future<void> show(
    WidgetTester tester,
    ScannedReceipt receipt, {
    Future<ScannedReceipt?> Function()? adjust,
  }) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ReceiptReviewScreen(
                      receipt: receipt,
                      onAdjustSelection: adjust,
                    ),
                  ),
                ),
                child: const Text('Scan'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Scan'));
    await tester.pumpAndSettle();
  }

  const parser = ReceiptOcrParser();

  testWidgets(
    'JazzCash saves one 570 Food expense using the purchase purpose',
    (tester) async {
      await show(tester, parser.parseRows(jazzcashRows));
      expect(find.text('Save Rs. 570.00'), findsOneWidget);
      expect(find.textContaining('7632'), findsNothing);
      await tester.tap(find.text('Save Rs. 570.00'));
      await tester.pumpAndSettle();
      expect(store.entries, hasLength(1));
      expect(store.entries.single.amount, 570);
      expect(store.entries.single.title, 'Food Groceries Purchases');
      expect(store.entries.single.category, 'Food');
    },
  );
  testWidgets('adjusting to amount and To does not reset 570 to zero', (
    tester,
  ) async {
    await show(
      tester,
      parser.parseRows(jazzcashRows),
      adjust: () async => parser.parseSelection(
        allRows: jazzcashRows.map(
          (text) => ReceiptOcrRow([ReceiptOcrCell(text)]),
        ),
        selectedRows: [
          const ReceiptOcrRow([ReceiptOcrCell('Rs. 570.00')]),
          const ReceiptOcrRow([ReceiptOcrCell('To')]),
        ],
      ),
    );
    await tester.tap(find.text('Adjust selection'));
    await tester.pumpAndSettle();
    expect(find.text('Save Rs. 570.00'), findsOneWidget);
    await tester.tap(find.text('Save Rs. 570.00'));
    await tester.pumpAndSettle();
    expect(store.entries.single.amount, 570);
  });
  testWidgets('no usable receipt amount disables saving zero', (tester) async {
    await show(
      tester,
      parser.parseRows([
        'Transaction Successful',
        'Fee Rs. 0.00',
        'To Test Recipient',
        '*******7632',
      ]),
    );
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(store.entries, isEmpty);
  });

  testWidgets(
    'clear products save in one tap with inferred categories and no total duplicate',
    (tester) async {
      await show(
        tester,
        parser.parseRows([
          'SHOP',
          'Items',
          'Milk 2 150 300',
          'Notebook 150',
          'Total 450',
        ]),
      );
      expect(find.text('Milk'), findsOneWidget);
      expect(find.text('Notebook'), findsOneWidget);
      await tester.tap(find.text('Save Rs. 450.00'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(store.entries.map((e) => e.title).toSet(), {'Milk', 'Notebook'});
      expect(store.entries.map((e) => e.category).toSet(), {
        'Food',
        'Education',
      });
      expect(store.entries.fold<double>(0, (sum, e) => sum + e.amount), 450);
      expect(store.entries.length, 2);
    },
  );
  testWidgets('uncertain amount requires a targeted check before saving', (
    tester,
  ) async {
    await show(
      tester,
      parser.parseRows(['SHOP', 'Items', 'Milk 2 150 200', 'Total 200']),
    );
    await tester.tap(find.text('Save Rs. 200.00'));
    await tester.pumpAndSettle();
    expect(store.entries, isEmpty);
    expect(find.text('I checked this amount'), findsOneWidget);
  });
  testWidgets(
    'tax and discount receipt saves payable total once with product title',
    (tester) async {
      await show(
        tester,
        parser.parseRows([
          'SHOP',
          'Items',
          'Burger 700',
          'Tax 70',
          'Discount 20',
          'Total 750',
        ]),
      );
      await tester.tap(find.text('Save Rs. 750.00'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(store.entries.length, 1);
      expect(store.entries.single.title, 'Burger');
      expect(store.entries.single.amount, 750);
    },
  );
  testWidgets('optional selection replaces parsed fields without saving', (
    tester,
  ) async {
    await show(
      tester,
      parser.parseRows(['SHOP', 'Items', 'Milk 300', 'Total 300']),
      adjust: () async =>
          parser.parseRows(['SHOP', 'Items', 'Bread 180', 'Total 180']),
    );
    await tester.tap(find.text('Adjust selection'));
    await tester.pumpAndSettle();
    expect(find.text('Bread'), findsOneWidget);
    expect(find.text('Milk'), findsNothing);
    expect(find.text('Save Rs. 180.00'), findsOneWidget);
    expect(store.entries, isEmpty);
  });
  testWidgets(
    'changing an item resets an earlier total-difference confirmation',
    (tester) async {
      await show(
        tester,
        parser.parseRows(['SHOP', 'Items', 'Milk 300', 'Total 500']),
      );
      final confirm = find.text('Save despite this difference');
      await tester.scrollUntilVisible(
        confirm,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Milk'),
        -250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Milk'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '350');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save Rs. 350.00'));
      await tester.pumpAndSettle();
      expect(store.entries, isEmpty);
    },
  );
}
