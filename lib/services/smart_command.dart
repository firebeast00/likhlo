import 'local_nlp_service.dart';

enum SmartInputSource { typed, voice, notification, receipt }

class TransactionSelector {
  final String? title;
  final double? amount;
  final DateTime? date;
  final String? walletHint;
  final String? transactionType;

  const TransactionSelector({
    this.title,
    this.amount,
    this.date,
    this.walletHint,
    this.transactionType,
  });

  bool get hasConstraint =>
      (title != null && title!.trim().isNotEmpty) ||
      (amount != null && amount! > 0) ||
      date != null ||
      (walletHint != null && walletHint!.trim().isNotEmpty) ||
      transactionType != null;
}

class TransactionPatch {
  final String? title;
  final double? amount;
  final String? category;
  final DateTime? date;
  final String? walletId;

  const TransactionPatch({
    this.title,
    this.amount,
    this.category,
    this.date,
    this.walletId,
  });

  bool get isEmpty =>
      title == null &&
      amount == null &&
      category == null &&
      date == null &&
      walletId == null;
}

sealed class SmartCommand {
  final ParsedSmartEntryCommand parsed;
  final SmartInputSource source;

  const SmartCommand({required this.parsed, required this.source});
}

class AddSmartTransactionCommand extends SmartCommand {
  const AddSmartTransactionCommand({
    required super.parsed,
    required super.source,
  });
}

class TransferCommand extends SmartCommand {
  const TransferCommand({
    required super.parsed,
    required super.source,
  });
}

class MutationCommand extends SmartCommand {
  final TransactionSelector selector;
  final TransactionPatch patch;
  final bool deleting;

  const MutationCommand({
    required super.parsed,
    required super.source,
    required this.selector,
    required this.patch,
    required this.deleting,
  });
}

class RepeatCommand extends SmartCommand {
  final TransactionSelector selector;

  const RepeatCommand({
    required super.parsed,
    required super.source,
    required this.selector,
  });
}

class ReadOnlySmartCommand extends SmartCommand {
  const ReadOnlySmartCommand({
    required super.parsed,
    required super.source,
  });
}

class UnknownSmartCommand extends SmartCommand {
  const UnknownSmartCommand({
    required super.parsed,
    required super.source,
  });
}
