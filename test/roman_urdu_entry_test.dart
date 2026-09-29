import 'package:flutter_test/flutter_test.dart';
import 'package:student_expense_manager/services/local_nlp_service.dart';
import 'package:student_expense_manager/services/pakistani_language_normalizer.dart';
import 'package:student_expense_manager/services/smart_command.dart';
import 'package:student_expense_manager/services/smart_input_engine.dart';

void main() {
  final engine = SmartInputEngine();
  const categories = ['General', 'Food', 'Transport'];
  const accounts = [
    SmartEntryAccount(
      id: 'daily',
      name: 'Daily Expenses',
      type: 'custom',
      availableBalance: 9000000,
    ),
    SmartEntryAccount(
      id: 'jazz',
      name: 'JazzCash',
      type: 'jazzcash',
      availableBalance: 0,
    ),
  ];

  for (final source in SmartInputSource.values) {
    for (final verb in ['transfer', 'jama', 'add', 'daal']) {
      test('$source: wallet relations resolve $verb as transfer', () {
        final plan = engine.parse(
          'assi hazar daily sy jazzcash me $verb karo',
          categories,
          accounts: accounts,
          source: source,
        );
        expect(plan.command, isA<TransferCommand>());
        expect(plan.parsed.amount, 80000);
        final wallets = resolveSmartEntryTransferAccounts(
          plan.normalizedText,
          accounts,
        );
        expect(wallets?.sourceAccountId, 'daily');
        expect(wallets?.destinationAccountId, 'jazz');
      });
    }
  }

  for (final entry in {
    'aik lak': 100000,
    '40 lak': 4000000,
    'derh lakh': 150000,
    'dedh lak': 150000,
    'dhai lakh': 250000,
    'sawa lakh': 125000,
    'paune do lakh': 175000,
    '2 krore': 20000000,
    '2 cr': 20000000,
    'do sau': 200,
    'pachees hazar': 25000,
    'pachpan sau': 5500,
    'پچیس ہزار': 25000,
    'پندرہ سو': 1500,
  }.entries) {
    test('amount ${entry.key}', () {
      final plan = engine.parse('${entry.key} cash me jama karo', categories);
      expect(plan.parsed.amount, entry.value);
      expect(plan.parsed.intent, SmartEntryIntent.addIncome);
    });
  }

  test('Urdu transcript and digit input reach the same transfer', () {
    final plan = engine.parse(
      'ڈیڑھ لاکھ ڈیلی سے جاز کیش میں جمع کرو',
      categories,
      accounts: accounts,
    );
    expect(plan.parsed.intent, SmartEntryIntent.transfer);
    expect(plan.parsed.amount, 150000);
    final expense = engine.parse('۵۰۰ بریانی پر خرچ کیا', categories);
    expect(expense.parsed.intent, SmartEntryIntent.addExpense);
    expect(expense.parsed.amount, 500);
  });

  test('reverse wallet order preserves direction', () {
    final plan = engine.parse(
      'jazzcash me daily se 500 jama karo',
      categories,
      accounts: accounts,
    );
    expect(plan.parsed.intent, SmartEntryIntent.transfer);
    expect(
      resolveSmartEntryTransferAccounts(
        plan.normalizedText,
        accounts,
      )?.sourceAccountId,
      'daily',
    );
  });

  test('ambiguous aliases cannot silently become income', () {
    final plan = engine.parse(
      'daily sy jazzcash me 500 jama karo',
      categories,
      accounts: [
        ...accounts,
        const SmartEntryAccount(
          id: 'savings',
          name: 'Daily Savings',
          type: 'custom',
          availableBalance: 1000,
        ),
      ],
    );
    expect(plan.command, isA<UnknownSmartCommand>());
  });

  test('negation and alternatives do not execute', () {
    for (final input in [
      '500 cash me jama nahi karo',
      'daily se jazzcash me 500 ya 1000 transfer karo',
    ]) {
      expect(
        engine.parse(input, categories, accounts: accounts).command,
        isA<UnknownSmartCommand>(),
      );
    }
  });

  test('Urdu alias replacement respects word boundaries', () {
    expect(
      PakistaniLanguageNormalizer().normalize('نومبر').normalized,
      'نومبر',
    );
  });

  test('helper do does not inflate word amounts', () {
    expect(
      engine.parse('aik lakh cash me jama kar do', categories).parsed.amount,
      100000,
    );
  });

  test('time-like ASR amount requires confirmation before saving', () {
    final plan = engine.parse(
      '3:30 lakh ka tel',
      categories,
      source: SmartInputSource.voice,
    );
    expect(plan.parsed.amount, 350000);
    expect(plan.requiresAsrReview, true);
  });
}
