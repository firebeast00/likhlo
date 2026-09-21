import 'package:flutter_test/flutter_test.dart';
import 'package:student_expense_manager/services/asr_hint_builder.dart';

void main() {
  test('builds compact deduplicated domain hints', () {
    final hints = const AsrHintBuilder(maxHints: 30).build(
      const DomainLexicon(
        walletNames: ['JazzCash', 'Business Wallet'],
        categories: ['Food'],
        frequentTitles: ['Foodpanda', 'Foodpanda'],
      ),
    );

    expect(hints.length, lessThanOrEqualTo(30));
    expect(hints, containsAll(['JazzCash', 'Business Wallet', 'Foodpanda']));
    expect(
      hints.where((hint) => hint.toLowerCase() == 'foodpanda').length,
      1,
    );
  });
}
