import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/expense_provider.dart';
import '../providers/workspace_provider.dart';

class WorkspacesScreen extends ConsumerWidget {
  const WorkspacesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspaceState = ref.watch(workspaceProvider);
    final records = ref.watch(expenseProvider).allRecords;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          Text(
            'Keep projects and personal spending separate while every wallet remains one real balance.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          for (final workspace in workspaceState.workspaces)
            Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor:
                      Color(workspace.colorValue).withValues(alpha: 0.14),
                  foregroundColor: Color(workspace.colorValue),
                  child: Icon(
                    IconData(
                      workspace.iconCodePoint,
                      fontFamily: 'MaterialIcons',
                    ),
                  ),
                ),
                title: Text(workspace.name),
                subtitle: Text(
                  '${records.where((entry) => entry.workspaceId == workspace.id).length} transactions${workspace.isDefault ? ' · default' : ''}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (workspaceState.selectedId == workspace.id)
                      const Icon(Icons.check_circle_rounded),
                    if (!workspace.isDefault)
                      IconButton(
                        tooltip: 'Delete workspace',
                        icon: const Icon(Icons.delete_outline_rounded),
                        onPressed: () => _deleteWorkspace(
                          context,
                          ref,
                          workspace.id,
                          workspace.name,
                          records.any(
                            (entry) => entry.workspaceId == workspace.id,
                          ),
                        ),
                      ),
                  ],
                ),
                onTap: () =>
                    ref.read(workspaceProvider.notifier).select(workspace.id),
              ),
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => _createWorkspace(context, ref),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Create workspace'),
          ),
        ],
      ),
    );
  }

  Future<void> _createWorkspace(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('New workspace'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Name',
            hintText: 'Freelance, Trip, Side business…',
          ),
          onSubmitted: (value) => Navigator.pop(dialogContext, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || !context.mounted) return;
    final created = await ref.read(workspaceProvider.notifier).create(name: name);
    if (!created && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Use a unique workspace name.')),
      );
    }
  }

  Future<void> _deleteWorkspace(
    BuildContext context,
    WidgetRef ref,
    String id,
    String name,
    bool hasTransactions,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete $name?'),
        content: Text(
          hasTransactions
              ? 'Its transactions will move to Personal. Wallet balances and transaction history will be preserved.'
              : 'This workspace is empty and can be removed safely.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(hasTransactions ? 'Move and delete' : 'Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(workspaceProvider.notifier).delete(
          id,
          moveTransactionsToPersonal: hasTransactions,
        );
  }
}
