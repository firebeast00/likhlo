import 'local_nlp_service.dart';
import 'smart_command.dart';
import 'smart_input_engine.dart';

class SpeechCommandCompleteness {
  final bool isComplete;
  final String reason;

  const SpeechCommandCompleteness._(this.isComplete, this.reason);

  const SpeechCommandCompleteness.complete(String reason)
      : this._(true, reason);

  const SpeechCommandCompleteness.incomplete(String reason)
      : this._(false, reason);
}

/// Decides whether a speech transcript contains enough information to act.
///
/// Recognition status alone is deliberately insufficient: Android can report
/// `done` after a short pause. The command must also satisfy its intent's
/// required fields before it may leave the voice-capture lifecycle.
class SpeechCommandCompletenessEvaluator {
  const SpeechCommandCompletenessEvaluator();

  SpeechCommandCompleteness evaluate(
    SmartInputPlan plan, {
    Iterable<SmartEntryAccount> accounts = const [],
  }) {
    final parsed = plan.parsed;
    final command = plan.command;

    // lib/services/speech_command_completeness.dart

    if (command is AddSmartTransactionCommand) {
      if (parsed.amount <= 0) {
        return const SpeechCommandCompleteness.incomplete('amount_missing');
      }

      // 🚀 FIX: "test se 400" is likely the beginning of a transfer, not a finished expense.
      final text = plan.normalizedText;
      final hasSourceMarker = RegExp(r'\b(se|sy|say|from)\b').hasMatch(text);
      final hasExplicitExpenseVerb = RegExp(r'\b(kharch|spent|paid|diye|kharida|loss)\b').hasMatch(text);

      if (hasSourceMarker && !hasExplicitExpenseVerb) {
        return const SpeechCommandCompleteness.incomplete('waiting_for_transfer_destination');
      }

      if (parsed.intent == SmartEntryIntent.addIncome) {
        return const SpeechCommandCompleteness.complete('income_with_amount');
      }
      if (!hasSpecificSmartEntryTitle(parsed.title)) {
        return const SpeechCommandCompleteness.incomplete('item_missing');
      }
      return const SpeechCommandCompleteness.complete('expense_with_amount_and_item');
    }

    if (command is TransferCommand) {
      if (parsed.amount <= 0) {
        return const SpeechCommandCompleteness.incomplete('amount_missing');
      }
      final availableAccounts = accounts.toList(growable: false);
      if (availableAccounts.isNotEmpty) {
        final resolution = resolveSmartEntryTransferAccounts(
          plan.normalizedText,
          availableAccounts,
        );
        if (resolution == null) {
          return const SpeechCommandCompleteness.incomplete(
            'transfer_accounts_missing',
          );
        }
        return const SpeechCommandCompleteness.complete(
          'transfer_with_accounts',
        );
      }
      if (!_hasStructuralTransferEndpoints(plan.normalizedText)) {
        return const SpeechCommandCompleteness.incomplete(
          'transfer_accounts_missing',
        );
      }
      return const SpeechCommandCompleteness.complete(
        'transfer_with_structural_endpoints',
      );
    }

    if (command is MutationCommand) {
      if (!command.selector.hasConstraint) {
        return const SpeechCommandCompleteness.incomplete(
          'entry_selector_missing',
        );
      }
      if (!command.deleting && command.patch.isEmpty) {
        return const SpeechCommandCompleteness.incomplete('new_value_missing');
      }
      return SpeechCommandCompleteness.complete(
        command.deleting ? 'delete_with_selector' : 'edit_with_patch',
      );
    }

    if (command is RepeatCommand) {
      if (command.selector.hasConstraint ||
          RegExp(
            r'\b(last|latest|previous|recent|pichli|pichla|akhri)\b',
          ).hasMatch(plan.normalizedText)) {
        return const SpeechCommandCompleteness.complete('repeat_target');
      }
      return const SpeechCommandCompleteness.incomplete(
        'repeat_target_missing',
      );
    }

    if (command is ReadOnlySmartCommand) {
      switch (parsed.intent) {
        case SmartEntryIntent.navigate:
          return parsed.navigationTarget == null
              ? const SpeechCommandCompleteness.incomplete(
                  'navigation_target_missing',
                )
              : const SpeechCommandCompleteness.complete(
                  'navigation_target',
                );
        case SmartEntryIntent.query:
          return parsed.queryMetric == null
              ? const SpeechCommandCompleteness.incomplete(
                  'query_metric_missing',
                )
              : const SpeechCommandCompleteness.complete('query_metric');
        case SmartEntryIntent.searchEntries:
          return _hasSearchSubject(plan.normalizedText)
              ? const SpeechCommandCompleteness.complete('search_subject')
              : const SpeechCommandCompleteness.incomplete(
                  'search_subject_missing',
                );
        case SmartEntryIntent.appControl:
          return parsed.appAction == null
              ? const SpeechCommandCompleteness.incomplete(
                  'app_control_missing',
                )
              : const SpeechCommandCompleteness.complete('app_control');
        case SmartEntryIntent.addExpense:
        case SmartEntryIntent.addIncome:
        case SmartEntryIntent.deleteEntry:
        case SmartEntryIntent.editEntry:
        case SmartEntryIntent.transfer:
        case SmartEntryIntent.repeatEntry:
        case SmartEntryIntent.unknown:
          break;
      }
    }

    return const SpeechCommandCompleteness.incomplete(
      'intent_incomplete_or_unknown',
    );
  }

  bool _hasStructuralTransferEndpoints(String input) {
    return RegExp(
      r'\b(?:from|se)\s+\S+(?:\s+\S+){0,2}\s+(?:to|mein|me|ko)\s+\S+',
    ).hasMatch(input);
  }

  bool _hasSearchSubject(String input) {
    final remainder = input
        .replaceAll(
          RegExp(r'\b(show|list|find|search|dhoondo|dikhao|me|mujhe)\b'),
          ' ',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return remainder.isNotEmpty;
  }
}
