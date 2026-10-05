import 'package:flutter_test/flutter_test.dart';
import 'package:student_expense_manager/services/local_nlp_service.dart';
import 'package:student_expense_manager/services/smart_command.dart';
import 'package:student_expense_manager/services/smart_input_engine.dart';
import 'package:student_expense_manager/services/speech_command_completeness.dart';

void main() {
  final engine = SmartInputEngine();
  const evaluator = SpeechCommandCompletenessEvaluator();
  const categories = ['Food', 'Transport', 'Education', 'General'];
  const accounts = [
    SmartEntryAccount(
      id: 'cash',
      name: 'Cash',
      type: 'cash',
      availableBalance: 10000,
    ),
    SmartEntryAccount(
      id: 'jazzcash',
      name: 'JazzCash',
      type: 'jazzcash',
      availableBalance: 10000,
    ),
    SmartEntryAccount(
      id: 'bank',
      name: 'Bank Account',
      type: 'custom',
      availableBalance: 10000,
    ),
  ];

  SpeechCommandCompleteness check(String input) {
    final plan = engine.parse(
      input,
      categories,
      source: SmartInputSource.voice,
      accounts: accounts,
    );
    return evaluator.evaluate(plan, accounts: accounts);
  }

  test('navigation waits for its destination', () {
    expect(check('open').isComplete, isFalse);
    expect(check('open wallets').isComplete, isTrue);
  });

  test('app controls complete once the action is recognized', () {
    final inputs = [
      'turn on dark mode',
      'dark mode band karo',
      'show monthly PDF',
      'scan receipt',
      'open backup',
      'persistent quick entry on',
      'daily reminders band karo',
      'spoken confirmations on',
      'English language mode',
      'app lock on',
    ];

    for (final input in inputs) {
      final result = check(input);
      expect(result.isComplete, isTrue, reason: input);
      expect(result.reason, 'app_control', reason: input);
    }
  });

  test('generic balance voice question is complete', () {
    final balance = check('kitne paise hain');
    final account = check('account mein kitne paise hain');

    expect(balance.isComplete, isTrue);
    expect(balance.reason, 'query_metric');
    expect(account.isComplete, isTrue);
    expect(account.reason, 'query_metric');
  });

  test('expense waits for both amount and item', () {
    expect(check('add 500').isComplete, isFalse);
    expect(check('add shoes for 500').isComplete, isTrue);
  });

  test('transfer waits for source and destination accounts', () {
    expect(check('transfer 500 from cash').isComplete, isFalse);
    expect(
      check('transfer 500 from cash to jazzcash').isComplete,
      isTrue,
    );
    expect(
      check('transfer 5000 from jazzcash to cash').isComplete,
      isTrue,
    );
    expect(
      check('5000 JSK se bank account mein transfer karo').isComplete,
      isTrue,
    );
  });

  test('edit waits for selector and replacement value', () {
    expect(check('change milk name').isComplete, isFalse);
    expect(check('change milk name to doodh').isComplete, isTrue);
  });

  test('unknown speech is never complete', () {
    expect(check('hello there').isComplete, isFalse);
  });
}
