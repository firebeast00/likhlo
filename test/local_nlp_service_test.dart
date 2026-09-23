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
      final result = LocalNlpService()
          .parseExpense('1200 for education books', categories);

      expect(result['amount'], 1200);
      expect(result['category'], 'Education');
    });

    test('returns zero when no amount is present', () {
      final result = LocalNlpService().parseExpense('bought lunch', categories);

      expect(result['amount'], 0);
    });

    test('parses comma-formatted and shorthand amounts', () {
      final comma =
          LocalNlpService().parseExpense('Rs 1,250 for groceries', categories);
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
      final result =
          LocalNlpService().parseExpense('salary 50 hazar aayi', categories);

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

    test('unknown categories still save instantly when an account is resolved',
        () {
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

    test('returns a typed command with per-field confidence', () {
      final command =
          LocalNlpService().parseCommand('500 burger cash', categories);

      expect(command.intent, SmartEntryIntent.addExpense);
      expect(command.amount, 500);
      expect(command.category, 'Food');
      expect(
          command.confidenceByField.keys,
          containsAll(
            ['intent', 'amount', 'title', 'category', 'date'],
          ));
      expect(command.clarificationReasons, isEmpty);
    });

    test('recognizes critical commands without auto-saving them', () {
      final service = LocalNlpService();
      final delete = service.parseCommand('delete burger', categories);
      final edit =
          service.parseCommand('change burger amount to 600', categories);
      final transfer =
          service.parseCommand('transfer 500 cash to JazzCash', categories);
      final query =
          service.parseCommand('show food spending this month', categories);

      expect(delete.intent, SmartEntryIntent.deleteEntry);
      expect(edit.intent, SmartEntryIntent.editEntry);
      expect(transfer.intent, SmartEntryIntent.transfer);
      expect(query.intent, SmartEntryIntent.query);
      expect(
        shouldAutoSaveSmartEntry(
          delete.toLegacyMap(),
          hasResolvedWallet: true,
        ),
        isFalse,
      );
    });

    test('parses English and Roman Urdu number phrases', () {
      final english = LocalNlpService()
          .parseCommand('fifty thousand salary received', categories);
      final romanUrdu = LocalNlpService()
          .parseCommand('pachaas hazar salary aayi', categories);

      expect(english.amount, 50000);
      expect(english.intent, SmartEntryIntent.addIncome);
      expect(romanUrdu.amount, 50000);
      expect(romanUrdu.intent, SmartEntryIntent.addIncome);
    });

    test('removes command filler words from transaction titles', () {
      final command =
          LocalNlpService().parseCommand('please add 500 burger', categories);

      expect(command.title, 'Burger');
      expect(command.category, 'Food');
    });

    test('rejects negative NLP amounts', () {
      final command = LocalNlpService().parseCommand('-500 burger', categories);

      expect(command.amount, 0);
      expect(command.needsClarification, isTrue);
      expect(
          command.clarificationReasons,
          contains(
            'Amount must be greater than zero.',
          ));
    });

    test('does not resolve when multiple wallets are mentioned', () {
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
          input: '500 burger cash JazzCash',
          accounts: accounts,
          transactionType: 'expense',
          amount: 500,
        ),
        isNull,
      );
    });

    test('finds one exact entry for a delete command', () {
      final command =
          LocalNlpService().parseCommand('delete burger', categories);
      final match = matchSmartEntryTransaction(
        command: command,
        entries: [
          SmartEntryTransaction(
            id: 'burger',
            title: 'Burger',
            amount: 500,
            category: 'Food',
            type: 'expense',
            date: DateTime(2026, 9, 16),
            walletId: 'cash',
          ),
          SmartEntryTransaction(
            id: 'petrol',
            title: 'Petrol',
            amount: 1000,
            category: 'Transport',
            type: 'expense',
            date: DateTime(2026, 9, 16),
            walletId: 'cash',
          ),
        ],
      );

      expect(match.status, SmartEntryMatchStatus.unique);
      expect(match.matches.single.id, 'burger');
    });

    test('returns a chooser list when exact titles are ambiguous', () {
      final command =
          LocalNlpService().parseCommand('delete burger', categories);
      final match = matchSmartEntryTransaction(
        command: command,
        entries: [
          SmartEntryTransaction(
            id: 'new',
            title: 'Burger',
            amount: 500,
            category: 'Food',
            type: 'expense',
            date: DateTime(2026, 9, 16),
            walletId: 'cash',
          ),
          SmartEntryTransaction(
            id: 'old',
            title: 'Burger',
            amount: 400,
            category: 'Food',
            type: 'expense',
            date: DateTime(2026, 9, 15),
            walletId: 'cash',
          ),
        ],
      );

      expect(match.status, SmartEntryMatchStatus.ambiguous);
      expect(match.matches, hasLength(2));
    });

    test('last selector chooses the newest matching entry', () {
      final command =
          LocalNlpService().parseCommand('delete last burger', categories);
      final match = matchSmartEntryTransaction(
        command: command,
        entries: [
          SmartEntryTransaction(
            id: 'old',
            title: 'Burger',
            amount: 400,
            category: 'Food',
            type: 'expense',
            date: DateTime(2026, 9, 15),
            walletId: 'cash',
          ),
          SmartEntryTransaction(
            id: 'new',
            title: 'Burger',
            amount: 500,
            category: 'Food',
            type: 'expense',
            date: DateTime(2026, 9, 16),
            walletId: 'cash',
          ),
        ],
      );

      expect(match.status, SmartEntryMatchStatus.unique);
      expect(match.matches.single.id, 'new');
    });

    test('delete matching can narrow by amount and wallet', () {
      final command =
          LocalNlpService().parseCommand('delete 500 burger cash', categories);
      final match = matchSmartEntryTransaction(
        command: command,
        walletId: 'cash',
        ignoredTitlePhrases: const ['cash'],
        entries: [
          SmartEntryTransaction(
            id: 'cash-entry',
            title: 'Burger',
            amount: 500,
            category: 'Food',
            type: 'expense',
            date: DateTime(2026, 9, 16),
            walletId: 'cash',
          ),
          SmartEntryTransaction(
            id: 'jazz-entry',
            title: 'Burger',
            amount: 500,
            category: 'Food',
            type: 'expense',
            date: DateTime(2026, 9, 16),
            walletId: 'jazz',
          ),
        ],
      );

      expect(match.status, SmartEntryMatchStatus.unique);
      expect(match.matches.single.id, 'cash-entry');
    });

    test('critical matcher never returns transfer records', () {
      final command =
          LocalNlpService().parseCommand('delete transfer', categories);
      final match = matchSmartEntryTransaction(
        command: command,
        entries: [
          SmartEntryTransaction(
            id: 'pair_out',
            title: 'Transfer to JazzCash',
            amount: 1000,
            category: 'Transfer',
            type: 'expense',
            date: DateTime(2026, 9, 16),
            walletId: 'cash',
          ),
        ],
      );

      expect(match.status, SmartEntryMatchStatus.notFound);
    });

    test('edit command uses the final numeric amount', () {
      final command = LocalNlpService()
          .parseCommand('change 500 burger amount to 600', categories);

      expect(command.intent, SmartEntryIntent.editEntry);
      expect(command.amount, 600);
      expect(command.title, 'Burger');
    });

    test('day before yesterday is parsed as two days ago', () {
      final command = LocalNlpService()
          .parseCommand('delete day before yesterday burger', categories);
      final expected = DateTime.now().subtract(const Duration(days: 2));

      expect(command.hasExplicitDate, isTrue);
      expect(
        DateTime(command.date.year, command.date.month, command.date.day),
        DateTime(expected.year, expected.month, expected.day),
      );
    });

    test('treats adding money to a wallet as income', () {
      final command =
          LocalNlpService().parseCommand('paso cash me add karo', categories);

      expect(command.intent, SmartEntryIntent.addIncome);
      expect(command.amount, 500);
    });

    test('cleans natural filler words from long delete commands', () {
      final command = LocalNlpService().parseCommand(
        'milk prepayment 840 ye milk prepayment ko delete karo',
        categories,
      );
      final match = matchSmartEntryTransaction(
        command: command,
        entries: [
          SmartEntryTransaction(
            id: 'milk',
            title: 'Milk Prepayment',
            amount: 840,
            category: 'General',
            type: 'expense',
            date: DateTime(2026, 9, 16),
            walletId: 'cash',
          ),
        ],
      );

      expect(command.intent, SmartEntryIntent.deleteEntry);
      expect(match.status, SmartEntryMatchStatus.unique);
      expect(match.matches.single.id, 'milk');
    });

    test('resolves English transfer direction', () {
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

      final resolution = resolveSmartEntryTransferAccounts(
        'transfer 500 from Cash to JazzCash',
        accounts,
      );

      expect(resolution, isNotNull);
      expect(resolution!.sourceAccountId, 'cash');
      expect(resolution.destinationAccountId, 'jazz');
    });

    test('resolves JazzCash to Cash without duplicating direction', () {
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
          availableBalance: 10000,
        ),
      ];

      final resolution = resolveSmartEntryTransferAccounts(
        'transfer 5000 from jazzcash to cash',
        accounts,
      );

      expect(resolution, isNotNull);
      expect(resolution!.sourceAccountId, 'jazz');
      expect(resolution.destinationAccountId, 'cash');
    });

    test('resolves Roman Urdu transfer direction', () {
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

      final resolution = resolveSmartEntryTransferAccounts(
        '500 cash se jazzcash me bhejo',
        accounts,
      );

      expect(resolution, isNotNull);
      expect(resolution!.sourceAccountId, 'cash');
      expect(resolution.destinationAccountId, 'jazz');
    });

    test('transfer requires exactly two named wallets', () {
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
        resolveSmartEntryTransferAccounts(
          'transfer 500 from cash',
          accounts,
        ),
        isNull,
      );
    });

    test('parses financial questions with metric and time range', () {
      final spending = LocalNlpService().parseCommand(
        'how much did I spend on food this month',
        categories,
      );
      final balance = LocalNlpService().parseCommand(
        'what is my cash balance',
        categories,
      );

      expect(spending.intent, SmartEntryIntent.query);
      expect(spending.queryMetric, SmartEntryQueryMetric.spending);
      expect(spending.timeRange, SmartEntryTimeRange.thisMonth);
      expect(spending.category, 'Food');
      expect(balance.intent, SmartEntryIntent.query);
      expect(balance.queryMetric, SmartEntryQueryMetric.balance);
    });

    test('does not turn normal income statements into questions', () {
      final command = LocalNlpService().parseCommand(
        'salary 50 hazar received in cash',
        categories,
      );

      expect(command.intent, SmartEntryIntent.addIncome);
      expect(command.amount, 50000);
    });

    test('recognizes repeat search and navigation commands', () {
      final repeat = LocalNlpService().parseCommand(
        'repeat last petrol expense',
        categories,
      );
      final search = LocalNlpService().parseCommand(
        'find burger entries',
        categories,
      );
      final navigate = LocalNlpService().parseCommand(
        'open wallets',
        categories,
      );

      expect(repeat.intent, SmartEntryIntent.repeatEntry);
      expect(search.intent, SmartEntryIntent.searchEntries);
      expect(navigate.intent, SmartEntryIntent.navigate);
      expect(navigate.navigationTarget, 'Wallets');
    });

    test('repeat last expense selects newest non-transfer expense', () {
      final command = LocalNlpService().parseCommand(
        'repeat last expense',
        categories,
      );
      final match = matchSmartEntryTransaction(
        command: command,
        entries: [
          SmartEntryTransaction(
            id: 'old',
            title: 'Books',
            amount: 500,
            category: 'Education',
            type: 'expense',
            date: DateTime(2026, 9, 19),
            walletId: 'cash',
          ),
          SmartEntryTransaction(
            id: 'new',
            title: 'Petrol',
            amount: 1000,
            category: 'Transport',
            type: 'expense',
            date: DateTime(2026, 9, 20),
            walletId: 'cash',
          ),
          SmartEntryTransaction(
            id: 'pair_out',
            title: 'Transfer to JazzCash',
            amount: 2000,
            category: 'Transfer',
            type: 'expense',
            date: DateTime(2026, 9, 21),
            walletId: 'cash',
          ),
        ],
      );

      expect(match.status, SmartEntryMatchStatus.unique);
      expect(match.matches.single.id, 'new');
    });

    test('time range helper handles current and previous months', () {
      final now = DateTime(2026, 9, 21);

      expect(
        matchesSmartEntryTimeRange(
          DateTime(2026, 9, 1),
          SmartEntryTimeRange.thisMonth,
          now: now,
        ),
        isTrue,
      );
      expect(
        matchesSmartEntryTimeRange(
          DateTime(2026, 8, 31),
          SmartEntryTimeRange.lastMonth,
          now: now,
        ),
        isTrue,
      );
      expect(
        matchesSmartEntryTimeRange(
          DateTime(2026, 7, 31),
          SmartEntryTimeRange.lastMonth,
          now: now,
        ),
        isFalse,
      );
    });
  });
}
