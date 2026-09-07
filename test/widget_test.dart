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

    test('uses a custom category mentioned by the user', () {
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
  });
}
