import 'package:flutter_test/flutter_test.dart';
import 'package:student_expense_manager/features/budget_predictor/budget_intent_parser.dart';

void main() {
  group('BudgetIntentParser', () {
    final parser = BudgetIntentParser();

    test('understands monthly budget amount', () {
      final intent = parser.parse('budget 40k rakho');
      expect(intent.action, BudgetIntentAction.setBudget);
      expect(intent.amount, 40000);
    });

    test('understands savings goal in Roman Urdu', () {
      final intent = parser.parse('5 hazar save karni hai');
      expect(intent.action, BudgetIntentAction.setSavingsGoal);
      expect(intent.amount, 5000);
    });

    test('understands item limit', () {
      final intent = parser.parse('petrol max 4000');
      expect(intent.action, BudgetIntentAction.setItemAmount);
      expect(intent.amount, 4000);
      expect(intent.target, contains('petrol'));
    });

    test('understands recurring and one-time corrections', () {
      expect(
        parser.parse('hostel har month').action,
        BudgetIntentAction.rememberRecurring,
      );
      expect(
        parser.parse('bike repair one time').action,
        BudgetIntentAction.markOneTime,
      );
    });

    test('splits multiple budget commands safely', () {
      final intents = parser.parseMany('budget 40k aur save 5k');
      expect(intents, hasLength(2));
      expect(intents.first.action, BudgetIntentAction.setBudget);
      expect(intents.last.action, BudgetIntentAction.setSavingsGoal);
    });

    test('understands budget questions', () {
      expect(
        parser.parse('kitna safe budget hona chahiye').action,
        BudgetIntentAction.queryRecommended,
      );
      expect(
        parser.parse('daily kitna kharch kar sakta hun').action,
        BudgetIntentAction.queryDailySafe,
      );
    });
  });
}
