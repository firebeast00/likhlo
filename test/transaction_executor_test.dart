import 'package:flutter_test/flutter_test.dart';
import 'package:student_expense_manager/models/expense_model.dart';
import 'package:student_expense_manager/services/transaction_executor.dart';

class _FakeStore implements TransactionStore {
  final Map<String, Expense> entries = {};
  final Map<String, Expense> deletedEntries = {};

  @override
  Future<bool> add(Expense entry) async {
    if (entries.containsKey(entry.id) || entry.amount <= 0) return false;
    entries[entry.id] = entry;
    return true;
  }

  @override
  Future<bool> addAll(Iterable<Expense> additions) async {
    final values = additions.toList();
    if (values.any((entry) => entries.containsKey(entry.id))) return false;
    for (final entry in values) {
      entries[entry.id] = entry;
    }
    return true;
  }

  @override
  Future<bool> delete(String id) async {
    final entry = entries.remove(id);
    if (entry == null) return false;
    deletedEntries[id] = entry.copyWith(deletedAt: DateTime(2026, 9, 22));
    return true;
  }

  @override
  Future<bool> deleteTransfer(String transactionId) async {
    final base = transactionId.replaceFirst(RegExp(r'_(out|in)$'), '');
    final out = entries.remove('${base}_out');
    final incoming = entries.remove('${base}_in');
    if (out != null) {
      deletedEntries[out.id] = out.copyWith(deletedAt: DateTime(2026, 9, 22));
    }
    if (incoming != null) {
      deletedEntries[incoming.id] =
          incoming.copyWith(deletedAt: DateTime(2026, 9, 22));
    }
    return out != null || incoming != null;
  }

  @override
  Future<bool> update(String id, Expense entry) async {
    if (!entries.containsKey(id)) return false;
    entries[id] = entry;
    return true;
  }

  @override
  Expense? findById(String id) => entries[id];

  @override
  Expense? findDeletedById(String id) => deletedEntries[id];

  @override
  Future<bool> restore(String id) async {
    final entry = deletedEntries.remove(id);
    if (entry == null) return false;
    entries[id] = entry.copyWith(clearDeletedAt: true);
    return true;
  }

  @override
  Future<bool> restoreTransfer(String transactionId) async {
    final base = transactionId.replaceFirst(RegExp(r'_(out|in)$'), '');
    final out = deletedEntries.remove('${base}_out');
    final incoming = deletedEntries.remove('${base}_in');
    if (out == null || incoming == null) return false;
    entries[out.id] = out.copyWith(clearDeletedAt: true);
    entries[incoming.id] = incoming.copyWith(clearDeletedAt: true);
    return true;
  }

  @override
  Future<bool> permanentlyDelete(String id) async {
    final entry = deletedEntries[id];
    if (entry == null) return false;
    if (entry.category == 'Transfer') {
      final base = id.replaceFirst(RegExp(r'_(out|in)$'), '');
      deletedEntries.remove('${base}_out');
      deletedEntries.remove('${base}_in');
    } else {
      deletedEntries.remove(id);
    }
    return true;
  }

  @override
  Future<void> emptyTrash() async => deletedEntries.clear();
}

Expense _entry({
  required String id,
  required String type,
  required String walletId,
  String category = 'Food',
  double amount = 500,
  String title = 'Test',
}) {
  return Expense(
    id: id,
    title: title,
    amount: amount,
    date: DateTime(2026, 9, 21),
    category: category,
    colorValue: 0,
    type: type,
    walletId: walletId,
  );
}

void main() {
  test('creates and updates through one executor boundary', () async {
    final store = _FakeStore();
    final executor = TransactionExecutor(store, enableAudio: false);
    final original = _entry(id: 'one', type: 'expense', walletId: 'cash');

    final created = await executor.execute(CreateTransactionCommand(original));
    final updated = await executor.execute(UpdateTransactionCommand(
      existingId: original.id,
      updated: original.copyWith(amount: 650),
    ));

    expect(created.succeeded, isTrue);
    expect(updated.succeeded, isTrue);
    expect(store.entries['one']?.amount, 650);
  });

  test('accepts only a complete balanced transfer pair', () async {
    final store = _FakeStore();
    final executor = TransactionExecutor(store, enableAudio: false);
    final date = DateTime(2026, 9, 21);
    final outgoing = _entry(
      id: 'pair_out',
      type: 'expense',
      walletId: 'cash',
      category: 'Transfer',
      title: 'Transfer to Very Long Wallet',
    ).copyWith(date: date);
    final incoming = _entry(
      id: 'pair_in',
      type: 'income',
      walletId: 'bank',
      category: 'Transfer',
      title: 'Transfer from Cash in Hand',
    ).copyWith(date: date);

    final result = await executor.execute(CreateTransferCommand(
      outgoing: outgoing,
      incoming: incoming,
    ));

    expect(result.succeeded, isTrue);
    expect(store.entries.keys, containsAll(['pair_out', 'pair_in']));
    expect(store.entries['pair_out']?.title, 'Transfer Very Long');
    expect(store.entries['pair_in']?.title, 'Transfer Cash Hand');
  });

  test('rejects a transfer with the same source and destination', () async {
    final store = _FakeStore();
    final executor = TransactionExecutor(store, enableAudio: false);
    final outgoing = _entry(
      id: 'pair_out',
      type: 'expense',
      walletId: 'cash',
      category: 'Transfer',
    );
    final incoming = _entry(
      id: 'pair_in',
      type: 'income',
      walletId: 'cash',
      category: 'Transfer',
    );

    final result = await executor.execute(CreateTransferCommand(
      outgoing: outgoing,
      incoming: incoming,
    ));

    expect(result.status, TransactionResultStatus.rejected);
    expect(store.entries, isEmpty);
  });

  test('stores only three core title words for creates and updates', () async {
    final store = _FakeStore();
    final executor = TransactionExecutor(store, enableAudio: false);
    final original = _entry(
      id: 'compact',
      type: 'expense',
      walletId: 'cash',
      title: 'please add blue gel ink pen',
    );

    await executor.execute(CreateTransactionCommand(original));
    expect(store.entries['compact']?.title, 'blue gel ink');

    await executor.execute(UpdateTransactionCommand(
      existingId: 'compact',
      updated: original.copyWith(title: 'university admission form fee'),
    ));
    expect(store.entries['compact']?.title, 'university admission form');
  });

  test('receipt batch is all-or-nothing and requires discrepancy consent',
      () async {
    final store = _FakeStore();
    final executor = TransactionExecutor(store, enableAudio: false);
    final items = [
      _entry(id: 'tea', type: 'expense', walletId: 'cash', amount: 100),
      _entry(id: 'meal', type: 'expense', walletId: 'cash', amount: 200),
    ];

    final rejected = await executor.execute(
      CreateBatchTransactionsCommand(
        entries: items,
        detectedTotal: 500,
      ),
    );
    expect(rejected.status, TransactionResultStatus.rejected);
    expect(store.entries, isEmpty);

    final saved = await executor.execute(
      CreateBatchTransactionsCommand(
        entries: items,
        detectedTotal: 500,
        discrepancyConfirmed: true,
      ),
    );
    expect(saved.succeeded, isTrue);
    expect(store.entries.keys, containsAll(['tea', 'meal']));
  });

  test('new entries always use Main without changing wallets', () async {
    final store = _FakeStore();
    final executor = TransactionExecutor(
      store,
      enableAudio: false,
    );
    final entry = _entry(id: 'job', type: 'income', walletId: 'bank')
        .copyWith(workspaceId: 'freelance');

    final saved = await executor.execute(CreateTransactionCommand(entry));

    expect(saved.succeeded, isTrue);
    expect(store.entries['job']?.workspaceId, 'personal');
    expect(store.entries['job']?.walletId, 'bank');
  });

  test('a transfer pair moves to Trash and restores together', () async {
    final store = _FakeStore();
    final executor = TransactionExecutor(store, enableAudio: false);
    final date = DateTime(2026, 9, 21);
    await executor.execute(
      CreateTransferCommand(
        outgoing: _entry(
          id: 'trash_pair_out',
          type: 'expense',
          walletId: 'cash',
          category: 'Transfer',
        ).copyWith(date: date),
        incoming: _entry(
          id: 'trash_pair_in',
          type: 'income',
          walletId: 'bank',
          category: 'Transfer',
        ).copyWith(date: date),
      ),
    );

    expect(
      (await executor.execute(const DeleteTransferCommand('trash_pair_out')))
          .succeeded,
      isTrue,
    );
    expect(store.entries, isEmpty);
    expect(store.deletedEntries.length, 2);

    expect(
      (await executor.execute(const RestoreTransferCommand('trash_pair_in')))
          .succeeded,
      isTrue,
    );
    expect(store.entries.length, 2);
    expect(store.deletedEntries, isEmpty);
  });
}
