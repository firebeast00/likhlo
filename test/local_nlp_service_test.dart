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

    test('allows instant save only for a confident complete entry', () {
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

    test('requires review for an unknown expense category', () {
      final parsed =
          LocalNlpService().parseExpense('500 something', categories);

      expect(
        shouldAutoSaveSmartEntry(parsed, hasResolvedWallet: true),
        isFalse,
      );
    });
  });
}
