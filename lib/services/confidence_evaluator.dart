import 'smart_command.dart';

enum ConfidenceDisposition { autoExecute, review, clarify, block }

class ConfidenceContext {
  final bool hasResolvedWallet;
  final bool hasExactAmount;
  final bool hasResolvedTransferSource;
  final bool hasResolvedTransferDestination;
  final double transferDirectionConfidence;
  final bool hasUniqueTarget;
  final double targetConfidence;

  const ConfidenceContext({
    this.hasResolvedWallet = false,
    this.hasExactAmount = false,
    this.hasResolvedTransferSource = false,
    this.hasResolvedTransferDestination = false,
    this.transferDirectionConfidence = 0,
    this.hasUniqueTarget = false,
    this.targetConfidence = 0,
  });
}

class SemanticConfidence {
  final double score;
  final ConfidenceDisposition disposition;
  final List<String> reasons;

  const SemanticConfidence({
    required this.score,
    required this.disposition,
    this.reasons = const [],
  });

  bool get canAutoExecute => disposition == ConfidenceDisposition.autoExecute;
}

/// Evaluates financial meaning rather than trusting an ASR provider's acoustic
/// confidence. Required slots and ambiguity always override a numeric score.
class ConfidenceEvaluator {
  const ConfidenceEvaluator();

  SemanticConfidence evaluate(
    SmartCommand command, {
    ConfidenceContext context = const ConfidenceContext(),
  }) {
    final parsed = command.parsed;
    if (command is UnknownSmartCommand) {
      return const SemanticConfidence(
        score: 0,
        disposition: ConfidenceDisposition.block,
        reasons: ['Command intent was not recognized.'],
      );
    }

    if (command is ReadOnlySmartCommand) {
      return SemanticConfidence(
        score: parsed.confidence,
        disposition: parsed.needsClarification
            ? ConfidenceDisposition.clarify
            : ConfidenceDisposition.autoExecute,
        reasons: parsed.clarificationReasons,
      );
    }

    if (command is AddSmartTransactionCommand) {
      final reasons = <String>[];
      if (!context.hasExactAmount || parsed.amount <= 0) {
        reasons.add('A positive exact amount is required.');
      }
      if (!context.hasResolvedWallet) {
        reasons.add('A wallet must be resolved.');
      }
      if (reasons.isNotEmpty) {
        return SemanticConfidence(
          score: parsed.confidence,
          disposition: ConfidenceDisposition.review,
          reasons: reasons,
        );
      }
      return SemanticConfidence(
        score: parsed.confidence,
        disposition: parsed.confidence >= 0.94
            ? ConfidenceDisposition.autoExecute
            : ConfidenceDisposition.review,
        reasons: parsed.confidence >= 0.94
            ? const []
            : const ['Review fields before saving.'],
      );
    }

    if (command is TransferCommand) {
      final reasons = <String>[];
      if (!context.hasExactAmount || parsed.amount <= 0) {
        reasons.add('An exact transfer amount is required.');
      }
      if (!context.hasResolvedTransferSource) {
        reasons.add('The source wallet is missing.');
      }
      if (!context.hasResolvedTransferDestination) {
        reasons.add('The destination wallet is missing.');
      }
      if (context.transferDirectionConfidence < 0.97) {
        reasons.add('Transfer direction is ambiguous.');
      }
      final score = (
        (parsed.confidenceByField['intent'] ?? 0) * 0.25 +
        (parsed.confidenceByField['amount'] ?? 0) * 0.30 +
        (context.hasResolvedTransferSource ? 1 : 0) * 0.15 +
        (context.hasResolvedTransferDestination ? 1 : 0) * 0.15 +
        context.transferDirectionConfidence * 0.15
      ).clamp(0.0, 1.0).toDouble();
      return SemanticConfidence(
        score: score,
        disposition: reasons.isEmpty && score >= 0.97
            ? ConfidenceDisposition.autoExecute
            : ConfidenceDisposition.clarify,
        reasons: reasons,
      );
    }

    if (command is MutationCommand) {
      final reasons = <String>[];
      if (!command.selector.hasConstraint) {
        reasons.add('A transaction selector is required.');
      }
      if (!command.deleting && command.patch.isEmpty) {
        reasons.add('At least one changed field is required.');
      }
      if (!context.hasUniqueTarget) {
        reasons.add('The target transaction is not unique.');
      }
      final score = context.targetConfidence;
      return SemanticConfidence(
        score: score,
        disposition: reasons.isEmpty && score >= 0.95
            ? ConfidenceDisposition.autoExecute
            : ConfidenceDisposition.review,
        reasons: reasons,
      );
    }

    if (command is RepeatCommand) {
      return SemanticConfidence(
        score: context.targetConfidence,
        disposition: context.hasUniqueTarget && context.targetConfidence >= 0.95
            ? ConfidenceDisposition.autoExecute
            : ConfidenceDisposition.review,
        reasons: context.hasUniqueTarget
            ? const []
            : const ['Choose the entry to repeat.'],
      );
    }

    return const SemanticConfidence(
      score: 0,
      disposition: ConfidenceDisposition.block,
    );
  }
}
