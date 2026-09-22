import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

import '../models/debt_model.dart';
import '../models/expense_model.dart';
import '../models/mess_entry_model.dart';
import '../providers/expense_provider.dart';
import '../providers/mess_provider.dart';
import '../services/transaction_executor.dart';

class TrashScreen extends ConsumerStatefulWidget {
  const TrashScreen({super.key});

  @override
  ConsumerState<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends ConsumerState<TrashScreen> {
  @override
  Widget build(BuildContext context) {
    final deleted = ref.watch(expenseProvider).deletedExpenses;
    final visible = visibleTransactions(deleted);
    final deletedIds = deleted.map((entry) => entry.id).toSet();
    final orphanDebts = Hive.isBoxOpen('debts')
        ? Hive.box<DebtEntry>('debts')
            .values
            .where(
              (entry) =>
                  entry.deletedAt != null && !deletedIds.contains(entry.id),
            )
            .toList()
        : <DebtEntry>[];
    final orphanMess = Hive.isBoxOpen('mess_khata')
        ? Hive.box<MessEntry>('mess_khata')
            .values
            .where(
              (entry) =>
                  entry.deletedAt != null && !deletedIds.contains(entry.id),
            )
            .toList()
        : <MessEntry>[];
    final orphanRecords = <Object>[...orphanDebts, ...orphanMess];
    final totalCount = visible.length + orphanRecords.length;
    final primary = Theme.of(context).colorScheme.primary;

    if (totalCount == 0) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_sweep_outlined, size: 58, color: Colors.grey),
            SizedBox(height: 12),
            Text(
              'Trash is empty',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            SizedBox(height: 5),
            Text(
              'Deleted entries are kept for 30 days.',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '$totalCount deleted ${totalCount == 1 ? 'entry' : 'entries'}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              TextButton.icon(
                onPressed: () => _emptyTrash(
                  context,
                  ref,
                  deleted,
                  orphanDebts,
                  orphanMess,
                ),
                icon: const Icon(Icons.delete_forever_outlined, size: 19),
                label: const Text('Empty Trash'),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: totalCount,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              if (index >= visible.length) {
                return _buildOrphanCard(
                  context,
                  ref,
                  orphanRecords[index - visible.length],
                  primary,
                );
              }
              final entry = visible[index];
              final isTransfer = entry.category == 'Transfer';
              return Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: BorderSide(
                    color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isTransfer
                              ? Icons.swap_horiz_rounded
                              : Icons.delete_outline_rounded,
                          color: Colors.red.shade600,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Rs. ${entry.amount.toStringAsFixed(0)} • ${entry.deletedAt == null ? '' : DateFormat.MMMd().add_jm().format(entry.deletedAt!)}',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Restore',
                        onPressed: () => _restore(context, ref, entry),
                        icon: Icon(Icons.restore_rounded, color: primary),
                      ),
                      IconButton(
                        tooltip: 'Delete permanently',
                        onPressed: () => _permanentlyDelete(context, ref, entry),
                        icon: const Icon(
                          Icons.delete_forever_outlined,
                          color: Colors.red,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _restore(
    BuildContext context,
    WidgetRef ref,
    Expense entry,
  ) async {
    final isTransfer = entry.category == 'Transfer';
    final result = await ref.read(transactionExecutorProvider).execute(
          isTransfer
              ? RestoreTransferCommand(entry.id)
              : RestoreTransactionCommand(entry.id),
        );
    if (!result.succeeded || !context.mounted) {
      if (context.mounted) {
        _message(
          context,
          result.reason ?? 'This entry could not be restored.',
          error: true,
        );
      }
      return;
    }
    await _restoreLinkedRecord(ref, entry.id);
    if (context.mounted) _message(context, 'Entry restored to its original wallet.');
  }

  Future<void> _permanentlyDelete(
    BuildContext context,
    WidgetRef ref,
    Expense entry,
  ) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Delete permanently?'),
            content: const Text(
              'This entry and any linked Udhaar or Mess record cannot be recovered.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Delete permanently'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    final result = await ref.read(transactionExecutorProvider).execute(
          PermanentlyDeleteTransactionCommand(entry.id),
        );
    if (result.succeeded) await _deleteLinkedRecord(ref, entry.id);
    if (context.mounted) {
      _message(
        context,
        result.succeeded ? 'Entry permanently deleted.' : 'Entry not found.',
        error: !result.succeeded,
      );
    }
  }

  Future<void> _emptyTrash(
    BuildContext context,
    WidgetRef ref,
    List<Expense> deleted,
    List<DebtEntry> orphanDebts,
    List<MessEntry> orphanMess,
  ) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Empty Trash?'),
            content: Text(
              'Permanently delete all ${deleted.length + orphanDebts.length + orphanMess.length} entries? This cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Empty Trash'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    for (final entry in deleted) {
      await _deleteLinkedRecord(ref, entry.id);
    }
    await ref
        .read(transactionExecutorProvider)
        .execute(const EmptyTrashCommand());
    if (Hive.isBoxOpen('debts')) {
      final box = Hive.box<DebtEntry>('debts');
      for (final entry in orphanDebts) {
        await box.delete(entry.key ?? entry.id);
      }
    }
    for (final entry in orphanMess) {
      await ref.read(messProvider.notifier).permanentlyDelete(entry.id);
    }
    if (mounted) setState(() {});
    if (context.mounted) _message(context, 'Trash emptied.');
  }

  Widget _buildOrphanCard(
    BuildContext context,
    WidgetRef ref,
    Object record,
    Color primary,
  ) {
    late final String id;
    late final String title;
    late final double amount;
    late final DateTime? deletedAt;
    if (record is DebtEntry) {
      id = record.id;
      title =
          '${record.type == 'lent' ? 'Udhaar to' : 'Borrowed from'} ${record.borrowerName}';
      amount = record.amount;
      deletedAt = record.deletedAt;
    } else {
      final mess = record as MessEntry;
      id = mess.id;
      title = mess.title;
      amount = mess.totalAmount;
      deletedAt = mess.deletedAt;
    }
    return Card(
      elevation: 0,
      child: ListTile(
        leading: const Icon(Icons.delete_outline_rounded, color: Colors.red),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          'Rs. ${amount.toStringAsFixed(0)} • ${deletedAt == null ? '' : DateFormat.MMMd().add_jm().format(deletedAt)}',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Restore',
              icon: Icon(Icons.restore_rounded, color: primary),
              onPressed: () async {
                if (record is DebtEntry) {
                  await Hive.box<DebtEntry>('debts').put(
                    record.key ?? id,
                    record.copyWith(clearDeletedAt: true),
                  );
                } else {
                  await ref.read(messProvider.notifier).restoreEntry(id);
                }
                if (mounted) setState(() {});
              },
            ),
            IconButton(
              tooltip: 'Delete permanently',
              icon: const Icon(Icons.delete_forever_outlined, color: Colors.red),
              onPressed: () async {
                final confirmed = await _confirmPermanentDelete(context);
                if (!confirmed) return;
                if (record is DebtEntry) {
                  await Hive.box<DebtEntry>('debts').delete(record.key ?? id);
                } else {
                  await ref.read(messProvider.notifier).permanentlyDelete(id);
                }
                if (mounted) setState(() {});
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _confirmPermanentDelete(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Delete permanently?'),
            content: const Text('This record cannot be recovered.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Delete permanently'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _restoreLinkedRecord(WidgetRef ref, String id) async {
    if (Hive.isBoxOpen('mess_khata')) {
      await ref.read(messProvider.notifier).restoreEntry(id);
    }
    if (Hive.isBoxOpen('debts')) {
      final box = Hive.box<DebtEntry>('debts');
      for (final entry in box.values.where((entry) => entry.id == id)) {
        if (entry.deletedAt != null) {
          await box.put(
            entry.key ?? id,
            entry.copyWith(clearDeletedAt: true),
          );
        }
      }
    }
  }

  Future<void> _deleteLinkedRecord(WidgetRef ref, String id) async {
    if (Hive.isBoxOpen('mess_khata')) {
      await ref.read(messProvider.notifier).permanentlyDelete(id);
    }
    if (Hive.isBoxOpen('debts')) {
      final box = Hive.box<DebtEntry>('debts');
      for (final entry in box.values.where((entry) => entry.id == id)) {
        if (entry.deletedAt != null) {
          await box.delete(entry.key ?? id);
        }
      }
    }
  }

  void _message(BuildContext context, String message, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: error ? Colors.red.shade700 : Colors.green.shade700,
        ),
      );
  }
}
