import 'package:flutter_test/flutter_test.dart';
import 'package:student_expense_manager/services/local_nlp_service.dart';

void main() {
  group('LocalNlpService', () {
    const categories = ['General', 'Food', 'Transport', 'Education'];

    test('extracts an amount and food category', () {
      final result =
          LocalNlpService().parseExpense('500 for biryani', categories);

      expect(result['amount'], 500);
      expect(result['category'], 'Food');
      expect(result['title'], 'Biryani');
    });

    test('uses an active category mentioned by the user', () {
      final result =
          LocalNlpService().parseExpense('1200 for education books', categories);

      expect(result['amount'], 1200);
      expect(result['category'], 'Education');
    });

    test('returns zero when no amount is present', () {
      final result =
          LocalNlpService().parseExpense('bought lunch', categories);

      expect(result['amount'], 0);
    });

    test('parses comma-formatted and shorthand amounts', () {
      final comma = LocalNlpService()
          .parseExpense('Rs 1,250 for groceries', categories);
      final shorthand =
          LocalNlpService().parseExpense('1.5k petrol', categories);

      expect(comma['amount'], 1250);
      expect(shorthand['amount'], 1500);
      expect(shorthand['category'], 'Transport');
    });

    test('parses Roman Urdu scaled amounts', () {
      final result =
          LocalNlpService().parseExpense('do hazar books', categories);

      expect(result['amount'], 2000);
      expect(result['category'], 'Education');
    });

    test('detects income intent without treating it as an expense', () {
      final result = LocalNlpService()
          .parseExpense('salary 50 hazar aayi', categories);

      expect(result['amount'], 50000);
      expect(result['type'], 'income');
      expect(result['category'], 'Income / Allowance');
    });

    test('routes yesterday entries to the previous date', () {
      final result =
          LocalNlpService().parseExpense('kal 500 lunch', categories);
      final date = result['date'] as DateTime;
      final expected = DateTime.now().subtract(const Duration(days: 1));

      expect(DateTime(date.year, date.month, date.day),
          DateTime(expected.year, expected.month, expected.day));
    });

    test('returns confidence and review metadata', () {
      final result =
          LocalNlpService().parseExpense('500 for biryani', categories);

      expect(result['confidence'], isA<double>());
      expect(result['needsReview'], isA<bool>());
    });

    test('allows instant save for a valid entry with a resolved account', () {
      final parsed =
          LocalNlpService().parseExpense('500 for biryani', categories);

      expect(
        shouldAutoSaveSmartEntry(parsed, hasResolvedWallet: true),
        isTrue,
      );
      expect(
        shouldAutoSaveSmartEntry(parsed, hasResolvedWallet: false),
        isFalse,
      );
    });

    test('unknown categories still save instantly when an account is resolved', () {
      final parsed =
          LocalNlpService().parseExpense('500 something', categories);

      expect(parsed['category'], 'General');
      expect(
        shouldAutoSaveSmartEntry(parsed, hasResolvedWallet: true),
        isTrue,
      );
    });

    test('uses funded Cash first and JazzCash as fallback', () {
      const accounts = [
        SmartEntryAccount(
          id: 'cash',
          name: 'Cash in Hand',
          type: 'cash',
          availableBalance: 100,
        ),
        SmartEntryAccount(
          id: 'jazz',
          name: 'JazzCash',
          type: 'jazzcash',
          availableBalance: 1000,
        ),
      ];

      expect(
        resolveSmartEntryAccount(
          input: '50 biryani',
          accounts: accounts,
          transactionType: 'expense',
          amount: 50,
        ),
        'cash',
      );
      expect(
        resolveSmartEntryAccount(
          input: '500 petrol',
          accounts: accounts,
          transactionType: 'expense',
          amount: 500,
        ),
        'jazz',
      );
    });

    test('explicit JazzCash mention overrides the Cash default', () {
      const accounts = [
        SmartEntryAccount(
          id: 'cash',
          name: 'Cash in Hand',
          type: 'cash',
          availableBalance: 1000,
        ),
        SmartEntryAccount(
          id: 'jazz',
          name: 'JazzCash',
          type: 'jazzcash',
          availableBalance: 1000,
        ),
      ];

      expect(
        resolveSmartEntryAccount(
          input: '500 petrol from jazz cash',
          accounts: accounts,
          transactionType: 'expense',
          amount: 500,
        ),
        'jazz',
      );
    });

    test('empty Cash and JazzCash require account review', () {
      const accounts = [
        SmartEntryAccount(
          id: 'cash',
          name: 'Cash in Hand',
          type: 'cash',
          availableBalance: 0,
        ),
        SmartEntryAccount(
          id: 'jazz',
          name: 'JazzCash',
          type: 'jazzcash',
          availableBalance: 0,
        ),
      ];

      expect(
        resolveSmartEntryAccount(
          input: 'salary 5000 aayi',
          accounts: accounts,
          transactionType: 'income',
          amount: 5000,
        ),
        isNull,
      );
      expect(
        resolveSmartEntryAccount(
          input: '500 biryani',
          accounts: accounts,
          transactionType: 'expense',
          amount: 500,
        ),
        isNull,
      );
    });

    test('an explicitly named empty account can receive income', () {
      const accounts = [
        SmartEntryAccount(
          id: 'cash',
          name: 'Cash in Hand',
          type: 'cash',
          availableBalance: 0,
        ),
        SmartEntryAccount(
          id: 'jazz',
          name: 'JazzCash',
          type: 'jazzcash',
          availableBalance: 0,
        ),
      ];

      expect(
        resolveSmartEntryAccount(
          input: 'salary 5000 cash mein aayi',
          accounts: accounts,
          transactionType: 'income',
          amount: 5000,
        ),
        'cash',
      );
    });
    test('selected custom account overrides automatic Cash selection', () {
      const accounts = [
        SmartEntryAccount(
          id: 'cash',
          name: 'Cash in Hand',
          type: 'cash',
          availableBalance: 1000,
        ),
        SmartEntryAccount(
          id: 'hbl',
          name: 'HBL Account',
          type: 'custom',
          availableBalance: 2000,
        ),
      ];

      expect(
        resolveSmartEntryAccount(
          input: '500 groceries',
          accounts: accounts,
          transactionType: 'expense',
          amount: 500,
          preferredAccountId: 'hbl',
        ),
        'hbl',
      );
    });

    test('selected reserve account can be used for instant entry', () {
      const accounts = [
        SmartEntryAccount(
          id: 'reserve',
          name: 'Emergency Stash',
          type: 'reserve',
          availableBalance: 1000,
          isBackup: true,
        ),
      ];

      expect(
        resolveSmartEntryAccount(
          input: '300 medicine',
          accounts: accounts,
          transactionType: 'expense',
          amount: 300,
          preferredAccountId: 'reserve',
        ),
        'reserve',
      );
    });

    test('underfunded selected account requires review', () {
      const accounts = [
        SmartEntryAccount(
          id: 'cash',
          name: 'Cash in Hand',
          type: 'cash',
          availableBalance: 100,
        ),
        SmartEntryAccount(
          id: 'jazz',
          name: 'JazzCash',
          type: 'jazzcash',
          availableBalance: 1000,
        ),
      ];

      expect(
        resolveSmartEntryAccount(
          input: '500 groceries',
          accounts: accounts,
          transactionType: 'expense',
          amount: 500,
          preferredAccountId: 'cash',
        ),
        isNull,
      );
    });


  });
}
