import 'package:flutter_test/flutter_test.dart';
import 'package:student_expense_manager/features/budget_predictor/budget_prediction_models.dart';
import 'package:student_expense_manager/features/budget_predictor/budget_suggestion_engine.dart';
import 'package:student_expense_manager/features/budget_predictor/monthly_smart_plan_service.dart';
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

    test('learns a recurring item across recent months', () {
      final engine = BudgetSuggestionEngine();
      final draft = engine.buildDraft(
        targetMonth: DateTime(2026, 10),
        allTransactions: [
          tx(
            id: 'laundry-jul',
            title: 'Laundry',
            amount: 700,
            date: DateTime(2026, 7, 5),
            category: 'General',
          ),
          tx(
            id: 'laundry-aug',
            title: 'Laundry',
            amount: 800,
            date: DateTime(2026, 8, 5),
            category: 'General',
          ),
          tx(
            id: 'laundry-sep',
            title: 'Laundry',
            amount: 750,
            date: DateTime(2026, 9, 5),
            category: 'General',
          ),
        ],
      );

      final laundry = draft.routineHabits.singleWhere(
        (item) => item.title == 'Laundry',
      );
      expect(laundry.amount, 750);
      expect(laundry.reason, contains('recent months'));
      expect(laundry.expectedDay, 5);
    });

    test('remembered one-off becomes a next-month expected item', () {
      final engine = BudgetSuggestionEngine();
      final key = engine.suggestionKey('Bike Repair', 'General');
      final draft = engine.buildDraft(
        targetMonth: DateTime(2026, 10),
        rememberedPatternKeys: {key},
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

      final repair = draft.routineHabits.singleWhere(
        (item) => item.title == 'Bike Repair',
      );
      expect(repair.amount, 1800);
      expect(repair.reason, contains('Remembered'));
    });

    test('uses six-month recurrence and median amount to resist spikes', () {
      final engine = BudgetSuggestionEngine();
      final draft = engine.buildDraft(
        targetMonth: DateTime(2026, 10),
        allTransactions: [
          tx(
            id: 'jul',
            title: 'Bike Fuel',
            amount: 4000,
            date: DateTime(2026, 7, 8),
            category: 'Transport',
          ),
          tx(
            id: 'aug',
            title: 'Petrol Refill',
            amount: 9000,
            date: DateTime(2026, 8, 9),
            category: 'Transport',
          ),
          tx(
            id: 'sep',
            title: 'Petrol',
            amount: 4200,
            date: DateTime(2026, 9, 7),
            category: 'Transport',
          ),
        ],
      );

      final petrol = draft.routineHabits.singleWhere(
        (item) => item.title == 'Petrol',
      );
      expect(petrol.amount, 4200);
      expect(petrol.expectedDay, 8);
      expect(petrol.confidenceTier, isNot(BudgetConfidenceTier.low));
    });

    test('ignored one-time pattern is not suggested for a future draft', () {
      final engine = BudgetSuggestionEngine();
      final key = engine.suggestionKey('Bike Repair', 'General');
      final draft = engine.buildDraft(
        targetMonth: DateTime(2026, 10),
        ignoredPatternKeys: {key},
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

      expect(draft.suggestions, isEmpty);
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

  group('MonthlySmartPlanService', () {
    test('matches expected items and separates new expenses', () {
      final engine = BudgetSuggestionEngine();
      final entries = <Expense>[
        tx(
          id: 'sep-hostel',
          title: 'Hostel Fee',
          amount: 8000,
          date: DateTime(2026, 9, 2),
          category: 'Hostel',
        ),
        tx(
          id: 'sep-petrol-1',
          title: 'Petrol',
          amount: 1000,
          date: DateTime(2026, 9, 3),
          category: 'Transport',
        ),
        tx(
          id: 'sep-petrol-2',
          title: 'Petrol',
          amount: 1000,
          date: DateTime(2026, 9, 10),
          category: 'Transport',
        ),
        tx(
          id: 'sep-petrol-3',
          title: 'Petrol',
          amount: 1000,
          date: DateTime(2026, 9, 20),
          category: 'Transport',
        ),
        tx(
          id: 'oct-hostel',
          title: 'Hostel Fee',
          amount: 8000,
          date: DateTime(2026, 10, 2),
          category: 'Hostel',
        ),
        tx(
          id: 'oct-petrol',
          title: 'Petrol',
          amount: 500,
          date: DateTime(2026, 10, 5),
          category: 'Transport',
        ),
        tx(
          id: 'oct-repair',
          title: 'Bike Repair',
          amount: 2500,
          date: DateTime(2026, 10, 6),
          category: 'General',
        ),
        tx(
          id: 'oct-income',
          title: 'Home Allowance',
          amount: 30000,
          date: DateTime(2026, 10, 1),
          category: 'Income / Allowance',
          type: 'income',
        ),
      ];

      final draft = engine.buildDraft(
        targetMonth: DateTime(2026, 10),
        allTransactions: entries,
      );
      final repairKey = engine.suggestionKey('Bike Repair', 'General');
      final plan = MonthlySmartPlanService(engine: engine).build(
        draft: draft,
        allTransactions: entries,
        rememberedPatternKeys: {repairKey},
      );

      final hostel = plan.expectedItems.singleWhere(
        (item) => item.suggestion.title == 'Hostel Fee',
      );
      final petrol = plan.expectedItems.singleWhere(
        (item) => item.suggestion.title == 'Petrol',
      );
      final repair = plan.newExpenses.singleWhere(
        (item) => item.title == 'Bike Repair',
      );

      expect(hostel.status, MonthlyPlanItemStatus.handled);
      expect(hostel.actualAmount, 8000);
      expect(petrol.status, MonthlyPlanItemStatus.inProgress);
      expect(petrol.actualAmount, 500);
      expect(repair.rememberedForFuture, isTrue);
      expect(plan.currentMonthIncome, 30000);
      expect(plan.currentMonthSpent, 11000);
    });
  });
}
