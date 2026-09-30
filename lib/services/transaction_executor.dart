import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/expense_model.dart';
import '../providers/expense_provider.dart';
import 'transaction_title_policy.dart';
import 'audio_feedback_service.dart';
import 'deterministic_feedback_service.dart';

enum TransactionAction {
  create,
  batch,
  transfer,
  update,
  delete,
  repeat,
  restore,
  permanentlyDelete,
  emptyTrash,
}

enum TransactionResultStatus { succeeded, rejected, notFound }

class TransactionResult {
  final TransactionResultStatus status;
  final TransactionAction action;
  final List<String> affectedIds;
  final String? reason;

  const TransactionResult({
    required this.status,
    required this.action,
    this.affectedIds = const [],
    this.reason,
  });

  bool get succeeded => status == TransactionResultStatus.succeeded;
}

sealed class LedgerCommand {
  final TransactionAction action;

  const LedgerCommand(this.action);
}

class CreateTransactionCommand extends LedgerCommand {
  final Expense entry;

  const CreateTransactionCommand(
    this.entry, {
    TransactionAction action = TransactionAction.create,
  }) : super(action);
}

class CreateBatchTransactionsCommand extends LedgerCommand {
  final List<Expense> entries;
  final double? detectedTotal;
  final bool discrepancyConfirmed;

  const CreateBatchTransactionsCommand({
    required this.entries,
    this.detectedTotal,
    this.discrepancyConfirmed = false,
  }) : super(TransactionAction.batch);
}

class CreateTransferCommand extends LedgerCommand {
  final Expense outgoing;
  final Expense incoming;

  const CreateTransferCommand({
    required this.outgoing,
    required this.incoming,
  }) : super(TransactionAction.transfer);
}

class UpdateTransactionCommand extends LedgerCommand {
  final String existingId;
  final Expense updated;

  const UpdateTransactionCommand({
    required this.existingId,
    required this.updated,
  }) : super(TransactionAction.update);
}

class DeleteTransactionCommand extends LedgerCommand {
  final String id;

  const DeleteTransactionCommand(this.id) : super(TransactionAction.delete);
}

class DeleteTransferCommand extends LedgerCommand {
  final String transactionId;

  const DeleteTransferCommand(this.transactionId)
      : super(TransactionAction.delete);
}

class RestoreTransactionCommand extends LedgerCommand {
  final String id;

  const RestoreTransactionCommand(this.id) : super(TransactionAction.restore);
}

class RestoreTransferCommand extends LedgerCommand {
  final String transactionId;

  const RestoreTransferCommand(this.transactionId)
      : super(TransactionAction.restore);
}

class PermanentlyDeleteTransactionCommand extends LedgerCommand {
  final String id;

  const PermanentlyDeleteTransactionCommand(this.id)
      : super(TransactionAction.permanentlyDelete);
}

class EmptyTrashCommand extends LedgerCommand {
  const EmptyTrashCommand() : super(TransactionAction.emptyTrash);
}

abstract interface class TransactionStore {
  Future<bool> add(Expense entry);
  Future<bool> addAll(Iterable<Expense> entries);
  Future<bool> update(String id, Expense entry);
  Future<bool> delete(String id);
  Future<bool> deleteTransfer(String transactionId);
  Expense? findById(String id);
  Expense? findDeletedById(String id);
  Future<bool> restore(String id);
  Future<bool> restoreTransfer(String transactionId);
  Future<bool> permanentlyDelete(String id);
  Future<void> emptyTrash();
}

class ExpenseTransactionStore implements TransactionStore {
  final ExpenseNotifier notifier;

  ExpenseTransactionStore(this.notifier);

  @override
  Future<bool> add(Expense entry) => notifier.addExpense(entry);

  @override
  Future<bool> addAll(Iterable<Expense> entries) =>
      notifier.addExpenses(entries);

  @override
  Future<bool> update(String id, Expense entry) =>
      notifier.editExpense(id, entry);

  @override
  Future<bool> delete(String id) => notifier.deleteExpense(id);

  @override
  Future<bool> deleteTransfer(String transactionId) async {
    return notifier.deleteTransferPair(transactionId);
  }

  @override
  Expense? findById(String id) => notifier.findById(id);

  @override
  Expense? findDeletedById(String id) => notifier.findDeletedById(id);

  @override
  Future<bool> restore(String id) => notifier.restoreExpense(id);

  @override
  Future<bool> restoreTransfer(String transactionId) =>
      notifier.restoreTransferPair(transactionId);

  @override
  Future<bool> permanentlyDelete(String id) => notifier.permanentlyDelete(id);

  @override
  Future<void> emptyTrash() => notifier.emptyTrash();
}

/// The only application service allowed to translate a resolved command into
/// ledger mutations. Parsing, speech, and UI feedback stay outside this class.
class TransactionExecutor {
  final TransactionStore store;
  final AudioFeedbackService audioFeedback;
  final bool enableAudio;

  TransactionExecutor(
    this.store, {
    AudioFeedbackService? audioFeedback,
    this.enableAudio = true,
  }) : audioFeedback = audioFeedback ?? AudioFeedbackService();

  Future<TransactionResult> execute(LedgerCommand command) async {
    switch (command) {
      case CreateTransactionCommand():
        final entry = _prepareForMainLedger(command.entry);
        final saved = await store.add(entry);
        if (saved && enableAudio) {
          unawaited(
            audioFeedback.announce(
              action: _feedbackAction(command.action, entry),
              entry: entry,
            ),
          );
        }
        return TransactionResult(
          status: saved
              ? TransactionResultStatus.succeeded
              : TransactionResultStatus.rejected,
          action: command.action,
          affectedIds: saved ? [entry.id] : const [],
          reason: saved ? null : 'Ledger validation rejected the transaction.',
        );
      case CreateBatchTransactionsCommand():
        if (command.entries.isEmpty ||
            (command.detectedTotal != null &&
                (!command.detectedTotal!.isFinite ||
                    command.detectedTotal! < 0)) ||
            command.entries.any(
              (entry) => !entry.amount.isFinite || entry.amount <= 0,
            ) ||
            command.entries.map((entry) => entry.id).toSet().length !=
                command.entries.length) {
          return const TransactionResult(
            status: TransactionResultStatus.rejected,
            action: TransactionAction.batch,
            reason: 'Every selected receipt item needs a valid amount.',
          );
        }
        final selectedTotal = command.entries.fold<double>(
          0,
          (sum, entry) => sum + entry.amount,
        );
        final detectedTotal = command.detectedTotal;
        final discrepancy = detectedTotal == null
            ? 0.0
            : (selectedTotal - detectedTotal).abs();
        final discrepancyLimit = detectedTotal != null &&
                detectedTotal * 0.05 > 5
            ? detectedTotal * 0.05
            : 5.0;
        if (detectedTotal != null &&
            detectedTotal > 0 &&
            discrepancy > discrepancyLimit &&
            !command.discrepancyConfirmed) {
          return const TransactionResult(
            status: TransactionResultStatus.rejected,
            action: TransactionAction.batch,
            reason: 'Confirm the receipt total difference before saving.',
          );
        }
        final entries = command.entries.map(_prepareForMainLedger).toList();
        final saved = await store.addAll(entries);
        if (saved && enableAudio) {
          unawaited(
            audioFeedback.announce(
              action: FinancialFeedbackAction.expense,
              entry: entries.first,
            ),
          );
        }
        return TransactionResult(
          status: saved
              ? TransactionResultStatus.succeeded
              : TransactionResultStatus.rejected,
          action: TransactionAction.batch,
          affectedIds:
              saved ? entries.map((entry) => entry.id).toList() : const [],
          reason: saved
              ? null
              : 'The receipt could not be saved. No items were added.',
        );
      case CreateTransferCommand():
        if (!_isValidTransfer(command)) {
          return const TransactionResult(
            status: TransactionResultStatus.rejected,
            action: TransactionAction.transfer,
            reason: 'A transfer requires a valid outgoing and incoming pair.',
          );
        }
        final outgoing = _prepareForMainLedger(command.outgoing);
        final incoming = _prepareForMainLedger(command.incoming);
        final saved = await store.addAll([outgoing, incoming]);
        if (saved && enableAudio) {
          unawaited(
            audioFeedback.announce(
              action: FinancialFeedbackAction.transfer,
              entry: outgoing,
              pairedEntry: incoming,
            ),
          );
        }
        return TransactionResult(
          status: saved
              ? TransactionResultStatus.succeeded
              : TransactionResultStatus.rejected,
          action: TransactionAction.transfer,
          affectedIds:
              saved ? [command.outgoing.id, command.incoming.id] : const [],
          reason: saved ? null : 'Ledger validation rejected the transfer.',
        );
      case UpdateTransactionCommand():
        final updatedEntry = _prepareForMainLedger(command.updated);
        final updated = await store.update(
          command.existingId,
          updatedEntry,
        );
        if (updated && enableAudio) {
          unawaited(
            audioFeedback.announce(
              action: FinancialFeedbackAction.edit,
              entry: updatedEntry,
            ),
          );
        }
        return TransactionResult(
          status: updated
              ? TransactionResultStatus.succeeded
              : TransactionResultStatus.rejected,
          action: TransactionAction.update,
          affectedIds: updated ? [command.existingId] : const [],
          reason: updated ? null : 'The transaction could not be updated.',
        );
      case DeleteTransactionCommand():
        final existing = store.findById(command.id);
        final deleted = await store.delete(command.id);
        if (deleted && existing != null && enableAudio) {
          unawaited(
            audioFeedback.announce(
              action: FinancialFeedbackAction.delete,
              entry: existing,
            ),
          );
        }
        return TransactionResult(
          status: deleted
              ? TransactionResultStatus.succeeded
              : existing == null
                  ? TransactionResultStatus.notFound
                  : TransactionResultStatus.rejected,
          action: TransactionAction.delete,
          affectedIds: deleted ? [command.id] : const [],
          reason: deleted
              ? null
              : existing == null
                  ? 'The transaction no longer exists.'
                  : 'Deleting this entry would make a wallet balance negative.',
        );
      case DeleteTransferCommand():
        final existing = store.findById(command.transactionId);
        final deleted = await store.deleteTransfer(command.transactionId);
        if (deleted && existing != null && enableAudio) {
          unawaited(
            audioFeedback.announce(
              action: FinancialFeedbackAction.delete,
              entry: existing,
            ),
          );
        }
        return TransactionResult(
          status: deleted
              ? TransactionResultStatus.succeeded
              : TransactionResultStatus.notFound,
          action: TransactionAction.delete,
          affectedIds: deleted ? [command.transactionId] : const [],
          reason: deleted ? null : 'The transfer no longer exists.',
        );
      case RestoreTransactionCommand():
        final deleted = store.findDeletedById(command.id);
        final restored = await store.restore(command.id);
        if (restored && deleted != null && enableAudio) {
          unawaited(
            audioFeedback.announce(
              action: deleted.type == 'income'
                  ? FinancialFeedbackAction.income
                  : FinancialFeedbackAction.expense,
              entry: deleted.copyWith(clearDeletedAt: true),
            ),
          );
        }
        return TransactionResult(
          status: restored
              ? TransactionResultStatus.succeeded
              : TransactionResultStatus.rejected,
          action: TransactionAction.restore,
          affectedIds: restored ? [command.id] : const [],
          reason: restored
              ? null
              : 'The transaction cannot be restored to its original wallet.',
        );
      case RestoreTransferCommand():
        final restored = await store.restoreTransfer(command.transactionId);
        return TransactionResult(
          status: restored
              ? TransactionResultStatus.succeeded
              : TransactionResultStatus.rejected,
          action: TransactionAction.restore,
          affectedIds: restored ? [command.transactionId] : const [],
          reason: restored
              ? null
              : 'Both transfer wallets are required before restoring.',
        );
      case PermanentlyDeleteTransactionCommand():
        final removed = await store.permanentlyDelete(command.id);
        return TransactionResult(
          status: removed
              ? TransactionResultStatus.succeeded
              : TransactionResultStatus.notFound,
          action: TransactionAction.permanentlyDelete,
          affectedIds: removed ? [command.id] : const [],
          reason: removed ? null : 'The Trash entry no longer exists.',
        );
      case EmptyTrashCommand():
        await store.emptyTrash();
        return const TransactionResult(
          status: TransactionResultStatus.succeeded,
          action: TransactionAction.emptyTrash,
        );
    }
  }

  FinancialFeedbackAction _feedbackAction(
    TransactionAction action,
    Expense entry,
  ) {
    if (action == TransactionAction.repeat) {
      return FinancialFeedbackAction.repeat;
    }
    if (action == TransactionAction.restore) {
      return entry.type == 'income'
          ? FinancialFeedbackAction.income
          : FinancialFeedbackAction.expense;
    }
    return entry.type == 'income'
        ? FinancialFeedbackAction.income
        : FinancialFeedbackAction.expense;
  }

  bool _isValidTransfer(CreateTransferCommand command) {
    final outgoing = command.outgoing;
    final incoming = command.incoming;
    final outgoingBase = outgoing.id.endsWith('_out')
        ? outgoing.id.substring(0, outgoing.id.length - 4)
        : '';
    final incomingBase = incoming.id.endsWith('_in')
        ? incoming.id.substring(0, incoming.id.length - 3)
        : '';
    return outgoingBase.isNotEmpty &&
        outgoingBase == incomingBase &&
        outgoing.type == 'expense' &&
        incoming.type == 'income' &&
        outgoing.category == 'Transfer' &&
        incoming.category == 'Transfer' &&
        outgoing.walletId != incoming.walletId &&
        outgoing.amount.isFinite &&
        outgoing.amount > 0 &&
        outgoing.amount == incoming.amount &&
        outgoing.date == incoming.date;
  }

  Expense _withCoreTitle(Expense entry) {
    var title = coreTransactionTitle(entry.title);
    if (title.isEmpty) {
      title = entry.type == 'income'
          ? 'Income Allowance'
          : coreTransactionTitle(entry.category);
    }
    if (title.isEmpty) title = 'Transaction';
    if (title == entry.title) return entry;
    return entry.copyWith(title: title);
  }

  Expense _prepareForMainLedger(Expense entry) {
    final titled = _withCoreTitle(entry);
    return titled.workspaceId == 'personal'
        ? titled
        : titled.copyWith(workspaceId: 'personal');
  }
}

final transactionExecutorProvider = Provider<TransactionExecutor>((ref) {
  return TransactionExecutor(
    ExpenseTransactionStore(ref.read(expenseProvider.notifier)),
  );
});
