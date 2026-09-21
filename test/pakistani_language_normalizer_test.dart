import 'package:flutter_test/flutter_test.dart';
import 'package:student_expense_manager/services/pakistani_language_normalizer.dart';
import 'package:student_expense_manager/services/smart_command.dart';
import 'package:student_expense_manager/services/smart_input_engine.dart';

void main() {
  final normalizer = PakistaniLanguageNormalizer();

  test('normalizes Urdu script transfer language and digits', () {
    final result = normalizer.normalize(
      'جاز کیش سے ۵۰۰۰ بینک میں بھیجو',
    );

    expect(result.normalized, 'jazzcash se 5000 bank me bhejo');
    expect(result.appliedRules, contains('urdu_script'));
    expect(result.appliedRules, contains('urdu_digits'));
  });

  test('corrects finance ASR aliases only in amount context', () {
    expect(
      normalizer.normalize('do show petrol').normalized,
      'do sau petrol',
    );
    expect(
      normalizer.normalize('show petrol expenses').normalized,
      'show petrol expenses',
    );
    expect(
      normalizer.normalize('jazz cast se do gazaar').normalized,
      'jazzcash se do hazar',
    );
  });

  test('builds a selector and title patch for Roman Urdu edit', () {
    final plan = SmartInputEngine().parse(
      '400 ki headphones ka naam Kurch karo',
      const ['General', 'Shopping'],
    );
    final command = plan.command as MutationCommand;

    expect(command.selector.title, 'headphones');
    expect(command.selector.amount, 400);
    expect(command.patch.title, 'Kurch');
    expect(command.patch.amount, isNull);
  });

  test('builds a separate selector and amount patch', () {
    final plan = SmartInputEngine().parse(
      'change 500 burger amount to 600',
      const ['General', 'Food'],
    );
    final command = plan.command as MutationCommand;

    expect(command.selector.title, 'burger');
    expect(command.selector.amount, 500);
    expect(command.patch.amount, 600);
  });
}
