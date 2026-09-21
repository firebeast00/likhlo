import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/expense_model.dart';
import '../providers/expense_provider.dart';

enum TransactionAction {
  create,
  transfer,
  update,
  delete,
  repeat,
  restore,
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

abstract interface class TransactionStore {
  Future<bool> add(Expense entry);
  Future<bool> addAll(Iterable<Expense> entries);
  Future<bool> update(String id, Expense entry);
  Future<bool> delete(String id);
  Future<bool> deleteTransfer(String transactionId);
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
    final baseId = transactionId.endsWith('_out')
        ? transactionId.substring(0, transactionId.length - 4)
        : transactionId.endsWith('_in')
            ? transactionId.substring(0, transactionId.length - 3)
            : transactionId;
    final exists = notifier.state.allExpenses.any(
      (entry) => entry.id == '${baseId}_out' || entry.id == '${baseId}_in',
    );
    if (!exists) return false;
    await notifier.deleteTransferPair(transactionId);
    return true;
  }
}

/// The only application service allowed to translate a resolved command into
/// ledger mutations. Parsing, speech, and UI feedback stay outside this class.
class TransactionExecutor {
  final TransactionStore store;

  const TransactionExecutor(this.store);

  Future<TransactionResult> execute(LedgerCommand command) async {
    switch (command) {
      case CreateTransactionCommand():
        final saved = await store.add(command.entry);
        return TransactionResult(
          status: saved
              ? TransactionResultStatus.succeeded
              : TransactionResultStatus.rejected,
          action: command.action,
          affectedIds: saved ? [command.entry.id] : const [],
          reason: saved ? null : 'Ledger validation rejected the transaction.',
        );
      case CreateTransferCommand():
        if (!_isValidTransfer(command)) {
          return const TransactionResult(
            status: TransactionResultStatus.rejected,
            action: TransactionAction.transfer,
            reason: 'A transfer requires a valid outgoing and incoming pair.',
          );
        }
        final saved = await store.addAll([
          command.outgoing,
          command.incoming,
        ]);
        return TransactionResult(
          status: saved
              ? TransactionResultStatus.succeeded
              : TransactionResultStatus.rejected,
          action: TransactionAction.transfer,
          affectedIds: saved
              ? [command.outgoing.id, command.incoming.id]
              : const [],
          reason: saved ? null : 'Ledger validation rejected the transfer.',
        );
      case UpdateTransactionCommand():
        final updated = await store.update(
          command.existingId,
          command.updated,
        );
        return TransactionResult(
          status: updated
              ? TransactionResultStatus.succeeded
              : TransactionResultStatus.rejected,
          action: TransactionAction.update,
          affectedIds: updated ? [command.existingId] : const [],
          reason: updated ? null : 'The transaction could not be updated.',
        );
      case DeleteTransactionCommand():
        final deleted = await store.delete(command.id);
        return TransactionResult(
          status: deleted
              ? TransactionResultStatus.succeeded
              : TransactionResultStatus.notFound,
          action: TransactionAction.delete,
          affectedIds: deleted ? [command.id] : const [],
          reason: deleted ? null : 'The transaction no longer exists.',
        );
      case DeleteTransferCommand():
        final deleted = await store.deleteTransfer(command.transactionId);
        return TransactionResult(
          status: deleted
              ? TransactionResultStatus.succeeded
              : TransactionResultStatus.notFound,
          action: TransactionAction.delete,
          affectedIds: deleted ? [command.transactionId] : const [],
          reason: deleted ? null : 'The transfer no longer exists.',
        );
    }
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
}

final transactionExecutorProvider = Provider<TransactionExecutor>((ref) {
  return TransactionExecutor(
    ExpenseTransactionStore(ref.read(expenseProvider.notifier)),
  );
});
