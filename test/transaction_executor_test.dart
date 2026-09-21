import 'package:flutter_test/flutter_test.dart';
import 'package:student_expense_manager/models/expense_model.dart';
import 'package:student_expense_manager/services/transaction_executor.dart';

class _FakeStore implements TransactionStore {
  final Map<String, Expense> entries = {};

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
  Future<bool> delete(String id) async => entries.remove(id) != null;

  @override
  Future<bool> deleteTransfer(String transactionId) async {
    final base = transactionId.replaceFirst(RegExp(r'_(out|in)$'), '');
    final out = entries.remove('${base}_out');
    final incoming = entries.remove('${base}_in');
    return out != null || incoming != null;
  }

  @override
  Future<bool> update(String id, Expense entry) async {
    if (!entries.containsKey(id)) return false;
    entries[id] = entry;
    return true;
  }
}

Expense _entry({
  required String id,
  required String type,
  required String walletId,
  String category = 'Food',
  double amount = 500,
}) {
  return Expense(
    id: id,
    title: 'Test',
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
    final executor = TransactionExecutor(store);
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
    final executor = TransactionExecutor(store);
    final date = DateTime(2026, 9, 21);
    final outgoing = _entry(
      id: 'pair_out',
      type: 'expense',
      walletId: 'cash',
      category: 'Transfer',
    ).copyWith(date: date);
    final incoming = _entry(
      id: 'pair_in',
      type: 'income',
      walletId: 'bank',
      category: 'Transfer',
    ).copyWith(date: date);

    final result = await executor.execute(CreateTransferCommand(
      outgoing: outgoing,
      incoming: incoming,
    ));

    expect(result.succeeded, isTrue);
    expect(store.entries.keys, containsAll(['pair_out', 'pair_in']));
  });

  test('rejects a transfer with the same source and destination', () async {
    final store = _FakeStore();
    final executor = TransactionExecutor(store);
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
}
