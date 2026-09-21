import 'package:flutter_test/flutter_test.dart';
import 'package:student_expense_manager/services/confidence_evaluator.dart';
import 'package:student_expense_manager/services/smart_command.dart';
import 'package:student_expense_manager/services/smart_input_engine.dart';

void main() {
  const categories = ['General', 'Food', 'Transport'];
  final engine = SmartInputEngine();
  const evaluator = ConfidenceEvaluator();

  test('missing wallet always prevents automatic expense execution', () {
    final plan = engine.parse('500 biryani', categories);
    final result = evaluator.evaluate(
      plan.command,
      context: const ConfidenceContext(hasExactAmount: true),
    );

    expect(result.canAutoExecute, isFalse);
    expect(result.reasons, contains('A wallet must be resolved.'));
  });

  test('transfer requires exact source, destination, and direction', () {
    final plan = engine.parse(
      'transfer 500 cash JazzCash',
      categories,
    );
    final result = evaluator.evaluate(
      plan.command,
      context: const ConfidenceContext(
        hasExactAmount: true,
        hasResolvedTransferSource: true,
        hasResolvedTransferDestination: true,
        transferDirectionConfidence: 0.92,
      ),
    );

    expect(result.disposition, ConfidenceDisposition.clarify);
    expect(result.reasons, contains('Transfer direction is ambiguous.'));
  });

  test('unique high-confidence mutation may execute', () {
    final plan = engine.parse(
      'change burger amount to 600',
      categories,
    );
    final result = evaluator.evaluate(
      plan.command,
      context: const ConfidenceContext(
        hasUniqueTarget: true,
        targetConfidence: 0.98,
      ),
    );

    expect(plan.command, isA<MutationCommand>());
    expect(result.canAutoExecute, isTrue);
  });
}
