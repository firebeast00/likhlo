import 'local_nlp_service.dart';
import 'smart_input_engine.dart';
import 'speech_command_completeness.dart';

/// Home-only endpoint policy. Unknown names need confirmation, not more silence.
class HomeCategorySpeechPolicy {
  const HomeCategorySpeechPolicy();

  /// Only a complete expense body can be completed by choosing a category.
  /// This must never bypass missing amount/title/wallet or other intent checks.
  bool canRecoverCategory(SmartInputPlan plan, {
      Iterable<SmartEntryAccount> accounts = const [],
      SpeechCommandCompletenessEvaluator evaluator =
          const SpeechCommandCompletenessEvaluator()}) =>
      plan.expenseCategory?.isInstructionIncomplete == true &&
      plan.parsed.intent == SmartEntryIntent.addExpense &&
      evaluator.evaluate(plan, accounts: accounts).isComplete;

  SpeechCommandCompleteness evaluate(SmartInputPlan plan, {
      Iterable<SmartEntryAccount> accounts = const [],
      SpeechCommandCompletenessEvaluator evaluator =
          const SpeechCommandCompletenessEvaluator()}) {
    if (plan.expenseCategory?.isInstructionIncomplete == true) {
      return const SpeechCommandCompleteness.incomplete('category_instruction_incomplete');
    }
    return evaluator.evaluate(plan, accounts: accounts);
  }
}
