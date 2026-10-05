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
    expect(
      normalizer
          .normalize('Spain pen 200', enableContextualAsrRepairs: true)
          .normalized,
      'spent pen 200',
    );
    expect(
      normalizer
          .normalize('200 pain khareeda', enableContextualAsrRepairs: true)
          .normalized,
      '200 pen khareeda',
    );
    expect(
      normalizer
          .normalize('pain medicine 200', enableContextualAsrRepairs: true)
          .normalized,
      'pain medicine 200',
    );
  });

  test('repairs live Stats month ASR variants only in voice context', () {
    final status = normalizer.normalize(
      'show October status',
      enableContextualAsrRepairs: true,
    );
    final starts = normalizer.normalize(
      'show September starts',
      enableContextualAsrRepairs: true,
    );
    final typo = normalizer.normalize('show octouber stats');

    expect(status.normalized, 'show october stats');
    expect(starts.normalized, 'show september stats');
    expect(typo.normalized, 'show october stats');
    expect(status.appliedRules, contains('stats_asr_context'));
    expect(starts.appliedRules, contains('stats_asr_context'));
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
