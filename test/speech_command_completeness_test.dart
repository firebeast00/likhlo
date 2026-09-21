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
  ];

  SpeechCommandCompleteness check(String input) {
    final plan = engine.parse(
      input,
      categories,
      source: SmartInputSource.voice,
    );
    return evaluator.evaluate(plan, accounts: accounts);
  }

  test('navigation waits for its destination', () {
    expect(check('open').isComplete, isFalse);
    expect(check('open wallets').isComplete, isTrue);
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
  });

  test('edit waits for selector and replacement value', () {
    expect(check('change milk name').isComplete, isFalse);
    expect(check('change milk name to doodh').isComplete, isTrue);
  });

  test('unknown speech is never complete', () {
    expect(check('hello there').isComplete, isFalse);
  });
}
