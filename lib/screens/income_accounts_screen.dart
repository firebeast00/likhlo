import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/income_accounts_provider.dart';

class IncomeAccountsScreen extends ConsumerWidget {
  const IncomeAccountsScreen({super.key});

  void _notice(BuildContext context, Object value, {bool success = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(value.toString().replaceFirst('Invalid argument(s): ', '')),
      backgroundColor: success ? Colors.green : Colors.red,
    ));
  }

  Future<String?> _nameDialog(BuildContext context, String title,
      [String initial = '']) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Account name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _addAccount(BuildContext context, WidgetRef ref) async {
    final name = await _nameDialog(context, 'New income source');
    if (name == null) return;
    try {
      await ref.read(incomeAccountsProvider.notifier).addAccount(name);
    } catch (error) {
      if (context.mounted) _notice(context, error);
    }
  }

  Future<void> _rename(
      BuildContext context, WidgetRef ref, IncomeAccount account) async {
    final name =
        await _nameDialog(context, 'Update income source', account.name);
    if (name == null) return;
    try {
      await ref
          .read(incomeAccountsProvider.notifier)
          .updateAccount(account.id, name);
    } catch (error) {
      if (context.mounted) _notice(context, error);
    }
  }

  Future<void> _income(BuildContext context, WidgetRef ref,
      List<IncomeAccount> accounts) async {
    if (accounts.isEmpty) return _addAccount(context, ref);
    final amount = TextEditingController();
    final note = TextEditingController();
    var accountId = accounts.first.id;
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Add income'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              initialValue: accountId,
              decoration: const InputDecoration(labelText: 'Income source'),
              items: accounts
                  .map((item) =>
                      DropdownMenuItem(value: item.id, child: Text(item.name)))
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => accountId = value);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amount,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration:
                  const InputDecoration(labelText: 'Amount', prefixText: 'Rs. '),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: note,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
          ]),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
    if (save != true) return;
    try {
      await ref.read(incomeAccountsProvider.notifier).addIncome(
            accountId: accountId,
            amount: double.tryParse(amount.text.trim()) ?? 0,
            date: DateTime.now(),
            note: note.text,
          );
      if (context.mounted) {
        _notice(context, 'Income added to account and main budget.',
            success: true);
      }
    } catch (error) {
      if (context.mounted) _notice(context, error);
    }
  }

  Future<void> _transfer(BuildContext context, WidgetRef ref,
      List<IncomeAccount> accounts) async {
    if (accounts.length < 2) {
      _notice(context, 'Create at least two accounts before transferring.');
      return;
    }
    final amount = TextEditingController();
    var fromId = accounts.first.id;
    var toId = accounts[1].id;
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Transfer'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              initialValue: fromId,
              decoration: const InputDecoration(labelText: 'From'),
              items: accounts
                  .map((item) =>
                      DropdownMenuItem(value: item.id, child: Text(item.name)))
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => fromId = value);
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: toId,
              decoration: const InputDecoration(labelText: 'To'),
              items: accounts
                  .map((item) =>
                      DropdownMenuItem(value: item.id, child: Text(item.name)))
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => toId = value);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amount,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration:
                  const InputDecoration(labelText: 'Amount', prefixText: 'Rs. '),
            ),
          ]),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Transfer'),
            ),
          ],
        ),
      ),
    );
    if (save != true) return;
    try {
      await ref.read(incomeAccountsProvider.notifier).transfer(
            fromAccountId: fromId,
            toAccountId: toId,
            amount: double.tryParse(amount.text.trim()) ?? 0,
          );
      if (context.mounted) _notice(context, 'Transfer completed.', success: true);
    } catch (error) {
      if (context.mounted) _notice(context, error);
    }
  }

  Future<bool> _confirm(
      BuildContext context, String title, String body) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(title),
            content: Text(body),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Confirm'),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(incomeAccountsProvider);
    final total =
        state.accounts.fold<double>(0, (sum, item) => sum + item.balance);
    final color = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(title: const Text('Income accounts')),
      body: state.accounts.isEmpty
          ? Center(
              child: FilledButton.icon(
                onPressed: () => _addAccount(context, ref),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Create income source'),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 110),
              children: [
                Card(
                  color: color,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Total income balance',
                              style: TextStyle(color: Colors.white70)),
                          const SizedBox(height: 6),
                          Text('Rs. ' + total.toStringAsFixed(0),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 28,
                                  fontWeight: FontWeight.w800)),
                        ]),
                  ),
                ),
                const SizedBox(height: 12),
                ...state.accounts.map((account) => Card(
                      child: ListTile(
                        leading: const Icon(Icons.payments_outlined),
                        title: Text(account.name),
                        subtitle:
                            Text('Rs. ' + account.balance.toStringAsFixed(0)),
                        trailing: PopupMenuButton<String>(
                          onSelected: (action) async {
                            if (action == 'rename') {
                              await _rename(context, ref, account);
                            } else if (action == 'clear') {
                              if (await _confirm(context, 'Clear account?',
                                  'This balance will also be reconciled with the current main budget.')) {
                                await ref
                                    .read(incomeAccountsProvider.notifier)
                                    .clearAccount(account.id, DateTime.now());
                              }
                            } else if (action == 'delete') {
                              if (await _confirm(context, 'Delete account?',
                                  'The balance will be reconciled with the current main budget.')) {
                                await ref
                                    .read(incomeAccountsProvider.notifier)
                                    .deleteAccount(account.id, DateTime.now());
                              }
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                                value: 'rename', child: Text('Update name')),
                            PopupMenuItem(
                                value: 'clear', child: Text('Clear balance')),
                            PopupMenuItem(
                                value: 'delete', child: Text('Delete account')),
                          ],
                        ),
                      ),
                    )),
              ],
            ),
      floatingActionButton: state.accounts.isEmpty
          ? null
          : Wrap(spacing: 10, children: [
              FloatingActionButton.small(
                heroTag: 'account',
                onPressed: () => _addAccount(context, ref),
                child: const Icon(Icons.add_business_rounded),
              ),
              FloatingActionButton.extended(
                heroTag: 'transfer',
                onPressed: () => _transfer(context, ref, state.accounts),
                icon: const Icon(Icons.swap_horiz_rounded),
                label: const Text('Transfer'),
              ),
              FloatingActionButton.extended(
                heroTag: 'income',
                onPressed: () => _income(context, ref, state.accounts),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Income'),
              ),
            ]),
    );
  }
}
