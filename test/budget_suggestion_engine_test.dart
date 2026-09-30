import 'package:flutter_test/flutter_test.dart';
import 'package:student_expense_manager/features/budget_predictor/budget_prediction_models.dart';
import 'package:student_expense_manager/features/budget_predictor/budget_suggestion_engine.dart';
import 'package:student_expense_manager/models/expense_model.dart';

Expense tx({
  required String id,
  required String title,
  required double amount,
  required DateTime date,
  required String category,
  String type = 'expense',
}) {
  return Expense(
    id: id,
    title: title,
    amount: amount,
    date: date,
    category: category,
    colorValue: 0,
    type: type,
    walletId: 'cash',
  );
}

void main() {
  group('BudgetSuggestionEngine', () {
    test('builds hostel budget from obligations, habits and surprise buffer', () {
      final engine = BudgetSuggestionEngine();
      final entries = <Expense>[
        tx(
          id: 'hostel',
          title: 'Hostel Fee',
          amount: 8000,
          date: DateTime(2026, 9, 2),
          category: 'Hostel',
        ),
        tx(
          id: 'package',
          title: 'Zong Package',
          amount: 1200,
          date: DateTime(2026, 9, 5),
          category: 'Bills',
        ),
        tx(
          id: 'petrol-1',
          title: 'Petrol',
          amount: 500,
          date: DateTime(2026, 9, 6),
          category: 'Transport',
        ),
        tx(
          id: 'petrol-2',
          title: 'Fuel',
          amount: 600,
          date: DateTime(2026, 9, 14),
          category: 'Transport',
        ),
        tx(
          id: 'petrol-3',
          title: 'Bike Petrol',
          amount: 700,
          date: DateTime(2026, 9, 24),
          category: 'Transport',
        ),
        tx(
          id: 'shoes',
          title: 'Shoes',
          amount: 4000,
          date: DateTime(2026, 9, 18),
          category: 'Shopping',
        ),
        tx(
          id: 'sep-med',
          title: 'Medicine',
          amount: 1000,
          date: DateTime(2026, 9, 20),
          category: 'Health',
        ),
        tx(
          id: 'aug-repair',
          title: 'Bike Repair',
          amount: 2000,
          date: DateTime(2026, 8, 10),
          category: 'General',
        ),
        tx(
          id: 'jul-books',
          title: 'Urgent Books',
          amount: 3000,
          date: DateTime(2026, 7, 11),
          category: 'Other',
        ),
        tx(
          id: 'allowance',
          title: 'Home Allowance',
          amount: 30000,
          date: DateTime(2026, 9, 1),
          category: 'Income / Allowance',
          type: 'income',
        ),
      ];

      final draft = engine.buildDraft(
        targetMonth: DateTime(2026, 10),
        allTransactions: entries,
      );

      expect(draft.fixedObligations.map((e) => e.title), contains('Hostel Fee'));
      expect(draft.fixedObligations.map((e) => e.title), contains('Zong Package'));

      final petrol = draft.routineHabits.singleWhere(
        (item) => item.title == 'Petrol',
      );
      expect(petrol.frequency, 3);
      expect(petrol.amount, 1800);

      expect(
        draft.suggestions.map((e) => e.title),
        isNot(contains('Shoes')),
      );
      expect(draft.surpriseBuffer, 2400);
      expect(draft.previousMonthIncome, 30000);
    });

    test('single uncertain purchase is not suggested as a repeating item', () {
      final engine = BudgetSuggestionEngine();
      final draft = engine.buildDraft(
        targetMonth: DateTime(2026, 10),
        allTransactions: [
          tx(
            id: 'repair',
            title: 'Bike Repair',
            amount: 1800,
            date: DateTime(2026, 9, 15),
            category: 'General',
          ),
        ],
      );

      expect(draft.fixedObligations, isEmpty);
      expect(draft.routineHabits, isEmpty);
      expect(draft.surpriseBuffer, greaterThan(0));
    });

    test('transfer and excluded Udhar records do not influence prediction', () {
      final engine = BudgetSuggestionEngine();
      final draft = engine.buildDraft(
        targetMonth: DateTime(2026, 10),
        excludedTransactionIds: {'udhar-1'},
        allTransactions: [
          tx(
            id: 'transfer',
            title: 'Wallet Transfer',
            amount: 5000,
            date: DateTime(2026, 9, 1),
            category: 'Transfer',
          ),
          tx(
            id: 'udhar-1',
            title: 'Udhaar: Ali',
            amount: 2000,
            date: DateTime(2026, 9, 2),
            category: 'General',
          ),
        ],
      );

      expect(draft.suggestions, isEmpty);
      expect(draft.surpriseBuffer, 0);
    });

    test('intent evaluator detects a one-time bill by title', () {
      final evaluator = BudgetIntentEvaluator();
      final expense = tx(
        id: 'wifi',
        title: 'Wifi Bill',
        amount: 1800,
        date: DateTime(2026, 9, 1),
        category: 'General',
      );
      final group = BudgetExpenseGroup(
        canonicalTitle: 'Wifi Bill',
        category: 'General',
        transactions: [expense],
        totalAmount: 1800,
      );

      expect(evaluator.evaluateIntent(group), ExpenseIntent.fixedBill);
    });
  });
}
