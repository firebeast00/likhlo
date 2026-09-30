import 'package:flutter_test/flutter_test.dart';
import 'package:student_expense_manager/features/smart_entry/multi_entry_parser.dart';
import 'package:student_expense_manager/features/smart_entry/smart_entry_batch_controller.dart';
import 'package:student_expense_manager/features/smart_entry/transaction_batch_draft.dart';
import 'package:student_expense_manager/services/local_nlp_service.dart';
import 'package:student_expense_manager/services/smart_command.dart';

void main() {
  group('MultiEntryParser', () {
    const parser = MultiEntryParser();

    test('segments multiple numeric transactions', () {
      final result = parser.tryParseBatch(
        '500 petrol, 200 chai and 1200 zong package',
      );

      expect(result, ['500 petrol', '200 chai', '1200 zong package']);
    });

    test('supports scaled numeric amounts behind the intent gate', () {
      final result = parser.tryParseBatch(
        '1.5k petrol aur 2k chai',
      );

      expect(result, ['1.5k petrol', '2k chai']);
    });

    test('keeps comma-formatted large amounts as one anchor', () {
      final result = parser.tryParseBatch(
        '1200000 hostel fee and 1,200,000 tuition fee',
      );

      expect(result, ['1200000 hostel fee', '1,200,000 tuition fee']);
    });

    test('does not split one amount with conjunctions in title', () {
      expect(parser.tryParseBatch('tea and biscuits 300'), isNull);
    });

    test('ignores a date number as an amount anchor', () {
      final result = parser.tryParseBatch(
        '500 petrol on 20 September and 200 chai',
      );

      expect(result, ['500 petrol on 20 September', '200 chai']);
    });

    test('non-add command bypasses batch mode', () {
      expect(parser.tryParseBatch('delete burger'), isNull);
      expect(parser.tryParseBatch('search jawad'), isNull);
      expect(parser.tryParseBatch('transfer 1000 cash to jazzcash'), isNull);
    });
  });

  group('SmartEntryBatchController', () {
    final accounts = [
      const SmartEntryAccount(
        id: 'cash',
        name: 'Cash',
        type: 'cash',
        availableBalance: 100000,
      ),
      const SmartEntryAccount(
        id: 'jazz',
        name: 'JazzCash',
        type: 'jazzcash',
        availableBalance: 100000,
      ),
    ];

    test('inherits one explicit wallet across otherwise implicit rows', () {
      final controller = SmartEntryBatchController();
      final attempt = controller.tryBuild(
        rawText: '500 petrol and 200 chai from JazzCash',
        categories: const ['General', 'Food', 'Transport', 'Bills'],
        source: SmartInputSource.typed,
        accounts: accounts,
        preferredAccountId: 'cash',
      );

      expect(attempt.status, SmartEntryBatchStatus.ready);
      final entries = attempt.draft!.entries;
      expect(entries, hasLength(2));
      expect(entries.every((entry) => entry.walletId == 'jazz'), isTrue);
      expect(entries[0].hasExplicitWallet, isFalse);
      expect(entries[1].hasExplicitWallet, isTrue);
    });

    test('inherits one explicit date across otherwise implicit rows', () {
      final controller = SmartEntryBatchController();
      final attempt = controller.tryBuild(
        rawText: '500 petrol and 200 chai kal',
        categories: const ['General', 'Food', 'Transport'],
        source: SmartInputSource.typed,
        accounts: accounts,
        preferredAccountId: 'cash',
      );

      expect(attempt.status, SmartEntryBatchStatus.ready);
      final entries = attempt.draft!.entries;
      expect(entries, hasLength(2));
      expect(entries[0].date.year, entries[1].date.year);
      expect(entries[0].date.month, entries[1].date.month);
      expect(entries[0].date.day, entries[1].date.day);
      expect(entries[0].hasExplicitDate, isFalse);
      expect(entries[1].hasExplicitDate, isTrue);
    });

    test('keeps different explicit wallets separate', () {
      final controller = SmartEntryBatchController();
      final attempt = controller.tryBuild(
        rawText: '500 petrol from Cash and 200 chai from JazzCash',
        categories: const ['General', 'Food', 'Transport'],
        source: SmartInputSource.typed,
        accounts: accounts,
        preferredAccountId: 'cash',
      );

      expect(attempt.status, SmartEntryBatchStatus.ready);
      final entries = attempt.draft!.entries;
      expect(entries.map((entry) => entry.walletId).toList(), ['cash', 'jazz']);
      expect(entries.every((entry) => entry.hasExplicitWallet), isTrue);
    });

    test('does not inherit transaction type across entries', () {
      final controller = SmartEntryBatchController();
      final attempt = controller.tryBuild(
        rawText: '30000 allowance and 500 petrol',
        categories: const ['General', 'Food', 'Transport', 'Bills'],
        source: SmartInputSource.typed,
        accounts: accounts,
        preferredAccountId: 'cash',
      );

      expect(attempt.status, SmartEntryBatchStatus.ready);
      expect(attempt.draft!.entries.map((entry) => entry.type).toList(), [
        'income',
        'expense',
      ]);
    });

    test('zero amount poisons an otherwise detected batch', () {
      final controller = SmartEntryBatchController();
      final attempt = controller.tryBuild(
        rawText: '500 petrol and 0 chai',
        categories: const ['General', 'Food', 'Transport'],
        source: SmartInputSource.typed,
        accounts: accounts,
        preferredAccountId: 'cash',
      );

      expect(attempt.status, SmartEntryBatchStatus.poisoned);
      expect(attempt.draft, isNull);
    });

    test('single transaction stays on legacy path', () {
      final controller = SmartEntryBatchController();
      final attempt = controller.tryBuild(
        rawText: '500 petrol',
        categories: const ['General', 'Transport'],
        source: SmartInputSource.typed,
        accounts: accounts,
        preferredAccountId: 'cash',
      );

      expect(attempt.status, SmartEntryBatchStatus.none);
    });
  });
}
