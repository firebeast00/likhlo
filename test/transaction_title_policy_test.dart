import 'package:flutter_test/flutter_test.dart';
import 'package:student_expense_manager/services/transaction_title_policy.dart';

void main() {
  group('coreTransactionTitle', () {
    test('keeps only three useful words', () {
      expect(
        coreTransactionTitle('please add university admission form fee'),
        'university admission form',
      );
    });

    test('removes transaction and currency filler', () {
      expect(
        coreTransactionTitle('spent Rs 500 on blue gel pen'),
        '500 blue gel',
      );
    });

    test('keeps short existing titles unchanged', () {
      expect(coreTransactionTitle('Chicken Biryani'), 'Chicken Biryani');
      expect(coreTransactionTitle('Income / Allowance'), 'Income Allowance');
    });

    test('rejects a title made only from command filler', () {
      expect(coreTransactionTitle('please add expense'), isEmpty);
    });
  });
}
