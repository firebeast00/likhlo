import '../l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

import '../models/debt_model.dart';
import '../models/expense_model.dart';
import '../providers/expense_provider.dart';
import '../services/transaction_executor.dart';
import '../services/udhar_ledger_link_service.dart';

class TrashScreen extends ConsumerStatefulWidget {
  const TrashScreen({super.key});

  @override
  ConsumerState<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends ConsumerState<TrashScreen> {
  @override
  Widget build(BuildContext context) {
    AppStrings.of(context);
    final deleted = ref.watch(expenseProvider).deletedExpenses;
    final deletedIds = deleted.map((entry) => entry.id).toSet();
    final visible = visibleTransactions(deleted).where((entry) {
      if (!entry.id.endsWith('_settlement')) return true;
      final debtId = entry.id.substring(0, entry.id.length - '_settlement'.length);
      return !deletedIds.contains(debtId) ||
          const UdharLedgerLinkService().find(debtId) == null;
    }).toList(growable: false);
    final orphanDebts = Hive.isBoxOpen('debts')
        ? Hive.box<DebtEntry>('debts')
            .values
            .where(
              (entry) =>
                  entry.deletedAt != null && !deletedIds.contains(entry.id),
            )
            .toList()
        : <DebtEntry>[];
    final totalCount = visible.length + orphanDebts.length;
    final primary = Theme.of(context).colorScheme.primary;

    if (totalCount == 0) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_sweep_outlined, size: 58, color: Colors.grey),
            SizedBox(height: 12),
            Text(
              AppStrings.current.text('trash_is_empty_49b796'),
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            SizedBox(height: 5),
            Text(
              AppStrings.current.text('deleted_entries_are_kept_for_30_days_aa3bcc'),
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
                  AppStrings.current.text('deleted_998369', {'p0': totalCount, 'p1': totalCount == 1 ? 'entry' : 'entries'}),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              TextButton.icon(
                onPressed: () => _emptyTrash(
                  context,
                  ref,
                  deleted,
                  orphanDebts,
                ),
                icon: const Icon(Icons.delete_forever_outlined, size: 19),
                label: Text(AppStrings.current.text('empty_trash_cb42d7')),
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
                  orphanDebts[index - visible.length],
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
                        tooltip: AppStrings.current.text('restore_3cbe6d'),
                        onPressed: () => _restore(context, ref, entry),
                        icon: Icon(Icons.restore_rounded, color: primary),
                      ),
                      IconButton(
                        tooltip: AppStrings.current.text('delete_permanently_e63b51'),
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
    await _restoreLinkedRecord(entry.id);
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
            title: Text(AppStrings.current.text('delete_permanently_afd1aa')),
            content: Text(
              AppStrings.current.text('this_entry_and_any_linked_udhaar_record_cannot_b_a5449d'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(AppStrings.current.text('cancel_77dfd2')),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(AppStrings.current.text('delete_permanently_e63b51')),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    final result = await ref.read(transactionExecutorProvider).execute(
          PermanentlyDeleteTransactionCommand(entry.id),
        );
    if (result.succeeded) await _deleteLinkedRecord(entry.id);
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
  ) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(AppStrings.current.text('empty_trash_ad55b6')),
            content: Text(
              AppStrings.current.text('permanently_delete_all_entries_this_cannot_be_un_3bf5c2', {'p0': deleted.length + orphanDebts.length}),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(AppStrings.current.text('cancel_77dfd2')),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(AppStrings.current.text('empty_trash_cb42d7')),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    for (final entry in deleted) {
      await _deleteLinkedRecord(entry.id);
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
    if (mounted) setState(() {});
    if (context.mounted) _message(context, 'Trash emptied.');
  }

  Widget _buildOrphanCard(
    BuildContext context,
    DebtEntry record,
    Color primary,
  ) {
    final id = record.id;
    final title =
        '${record.type == 'lent' ? 'Udhaar to' : 'Borrowed from'} ${record.borrowerName}';
    final amount = record.amount;
    final deletedAt = record.deletedAt;
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
              tooltip: AppStrings.current.text('restore_3cbe6d'),
              icon: Icon(Icons.restore_rounded, color: primary),
              onPressed: () async {
                await Hive.box<DebtEntry>('debts').put(
                  record.key ?? id,
                  record.copyWith(clearDeletedAt: true),
                );
                if (mounted) setState(() {});
              },
            ),
            IconButton(
              tooltip: AppStrings.current.text('delete_permanently_e63b51'),
              icon: const Icon(Icons.delete_forever_outlined, color: Colors.red),
              onPressed: () async {
                final confirmed = await _confirmPermanentDelete(context);
                if (!confirmed) return;
                await Hive.box<DebtEntry>('debts').delete(record.key ?? id);
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
            title: Text(AppStrings.current.text('delete_permanently_afd1aa')),
            content: Text(AppStrings.current.text('this_record_cannot_be_recovered_3c1744')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(AppStrings.current.text('cancel_77dfd2')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(AppStrings.current.text('delete_permanently_e63b51')),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _restoreLinkedRecord(String id) async {
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

  Future<void> _deleteLinkedRecord(String id) async {
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
          content: Text(AppStrings.current.display(message)),
          behavior: SnackBarBehavior.floating,
          backgroundColor: error ? Colors.red.shade700 : Colors.green.shade700,
        ),
      );
  }
}
