import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/expense_model.dart';
import '../models/wallet_model.dart';
import '../providers/expense_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/wallet_provider.dart';

class IncomeAccountsScreen extends ConsumerWidget {
  const IncomeAccountsScreen({super.key});

  Future<void> _showAccountDialog(
    BuildContext context,
    WidgetRef ref, {
    Wallet? existing,
  }) async {
    final controller = TextEditingController(text: existing?.name ?? '');
    final currentBalance = existing == null
        ? 0.0
        : ref.read(walletProvider.notifier).getBalanceForWallet(existing.id);
    final balanceController = TextEditingController(
      text: existing == null
          ? '0'
          : currentBalance.toStringAsFixed(
              currentBalance == currentBalance.truncateToDouble() ? 0 : 2,
            ),
    );
    bool isBackup = existing?.isBackup ?? false;
    String? nameError;
    String? balanceError;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _DialogControllerScope(
        controllers: [controller, balanceController],
        child: StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
          scrollable: true,
          title: Text(existing == null ? 'New money account' : 'Update account'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: 'Account name',
                  errorText: nameError,
                  prefixIcon: const Icon(Icons.account_balance_wallet_outlined),
                ),
                onChanged: (_) {
                  if (nameError != null) {
                    setDialogState(() => nameError = null);
                  }
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: balanceController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Current balance',
                  hintText: 'Amount currently available',
                  prefixText: 'Rs. ',
                  errorText: balanceError,
                ),
                onChanged: (_) {
                  if (balanceError != null) {
                    setDialogState(() => balanceError = null);
                  }
                },
              ),
              const SizedBox(height: 8),
              const Text(
                'This amount is included automatically in the total shown on the Home screen.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Reserve account'),
                subtitle: const Text('Mark money that you prefer to keep aside.'),
                value: isBackup,
                onChanged: (value) => setDialogState(() => isBackup = value),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final name = controller.text.trim();
                final balance = double.tryParse(balanceController.text.trim());
                if (name.isEmpty) {
                  setDialogState(() => nameError = 'Enter an account name.');
                  return;
                }
                if (balance == null || !balance.isFinite || balance < 0) {
                  setDialogState(() => balanceError = 'Enter a valid balance of zero or more.');
                  return;
                }

                final notifier = ref.read(walletProvider.notifier);
                final saved = existing == null
                    ? await notifier.addWallet(
                        Wallet(
                          id: const Uuid().v4(),
                          name: name,
                          balance: balance,
                          isBackup: isBackup,
                          colorValue:
                              ref.read(settingsProvider).profileColorValue,
                          walletType: 'custom',
                        ),
                      )
                    : await notifier.updateWallet(
                        existing.copyWith(name: name, isBackup: isBackup),
                        currentBalance: balance,
                      );

                if (!dialogContext.mounted) return;
                if (!saved) {
                  setDialogState(
                    () => nameError = 'An account with this name already exists.',
                  );
                  return;
                }
                Navigator.pop(dialogContext);
              },
              child: Text(existing == null ? 'Create' : 'Update'),
            ),
          ],
          ),
        ),
      ),
    );
  }

  Future<void> _addIncome(BuildContext context, WidgetRef ref) async {
    final wallets = ref.read(walletProvider);
    if (wallets.isEmpty) return;

    final titleController = TextEditingController();
    final amountController = TextEditingController();
    String walletId =
        wallets.firstWhere((wallet) => !wallet.isBackup, orElse: () => wallets.first).id;
    String? error;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _DialogControllerScope(
        controllers: [titleController, amountController],
        child: StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add income'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Income title',
                  hintText: 'Salary, allowance, freelance…',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Amount',
                  prefixText: 'Rs. ',
                  errorText: error,
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: walletId,
                decoration: const InputDecoration(labelText: 'Income account'),
                items: wallets
                    .map(
                      (wallet) => DropdownMenuItem(
                        value: wallet.id,
                        child: Text(wallet.name),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setDialogState(() => walletId = value);
                  }
                },
              ),
              const SizedBox(height: 8),
              const Text(
                'This income increases the selected account and the total available balance.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final amount = double.tryParse(amountController.text.trim());
                if (amount == null || !amount.isFinite || amount <= 0) {
                  setDialogState(() => error = 'Enter a valid amount above zero.');
                  return;
                }

                final saved = await ref.read(expenseProvider.notifier).addExpense(
                      Expense(
                        id: const Uuid().v4(),
                        title: titleController.text.trim().isEmpty
                            ? 'Income / Allowance'
                            : titleController.text.trim(),
                        amount: amount,
                        date: DateTime.now(),
                        category: 'Income / Allowance',
                        colorValue: Colors.green.toARGB32(),
                        type: 'income',
                        walletId: walletId,
                      ),
                    );
                if (!dialogContext.mounted) return;
                if (!saved) {
                  setDialogState(() => error = 'Could not save this income.');
                  return;
                }
                Navigator.pop(dialogContext);
              },
              child: const Text('Add income'),
            ),
          ],
          ),
        ),
      ),
    );
  }

  Future<void> _clearAccount(
    BuildContext context,
    WidgetRef ref,
    Wallet wallet,
  ) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Clear account balance?'),
            content: Text(
              'Set ${wallet.name} to Rs. 0? Transaction history will remain available.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Clear balance'),
              ),
            ],
          ),
        ) ??
        false;

    if (confirmed) {
      await ref.read(walletProvider.notifier).clearBalance(wallet.id);
    }
  }

  Future<void> _deleteAccount(
    BuildContext context,
    WidgetRef ref,
    Wallet wallet,
  ) async {
    final wallets = ref.read(walletProvider);
    if (wallets.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('At least one income account is required.')),
      );
      return;
    }

    final fallback = wallets.firstWhere(
      (candidate) => candidate.id != wallet.id && !candidate.isBackup,
      orElse: () => wallets.firstWhere((candidate) => candidate.id != wallet.id),
    );
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Delete income account?'),
            content: Text(
              'Delete ${wallet.name}? Its transaction history and opening adjustment will move to ${fallback.name}.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    await ref
        .read(expenseProvider.notifier)
        .reassignWallet(wallet.id, fallback.id);
    if (wallet.balance != 0) {
      await ref.read(walletProvider.notifier).updateWallet(
            fallback.copyWith(balance: fallback.balance + wallet.balance),
          );
    }
    await ref.read(walletProvider.notifier).deleteWallet(wallet.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallets = ref.watch(walletProvider);
    ref.watch(expenseProvider);
    final primaryColor = Color(ref.watch(settingsProvider).profileColorValue);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Money Accounts'),
        actions: [
          IconButton(
            tooltip: 'Create account',
            onPressed: () => _showAccountDialog(context, ref),
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        itemCount: wallets.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final wallet = wallets[index];
          final balance =
              ref.read(walletProvider.notifier).getBalanceForWallet(wallet.id);
          final color = Color(wallet.colorValue);
          return Card(
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: CircleAvatar(
                backgroundColor: color.withValues(alpha: 0.12),
                child: Icon(
                  wallet.isBackup
                      ? Icons.shield_outlined
                      : Icons.account_balance_wallet_outlined,
                  color: color,
                ),
              ),
              title: Text(
                wallet.name,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(wallet.isBackup ? 'Reserve account' : 'Income source'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Rs. ${balance.toStringAsFixed(0)}',
                    style: TextStyle(
                      color: balance < 0 ? Colors.red : primaryColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (action) {
                      if (action == 'edit') {
                        _showAccountDialog(context, ref, existing: wallet);
                      } else if (action == 'clear') {
                        _clearAccount(context, ref, wallet);
                      } else if (action == 'delete') {
                        _deleteAccount(context, ref, wallet);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Rename / update')),
                      PopupMenuItem(value: 'clear', child: Text('Clear balance')),
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addIncome(context, ref),
        icon: const Icon(Icons.south_west_rounded),
        label: const Text('Add income'),
      ),
    );
  }
}

class _DialogControllerScope extends StatefulWidget {
  final List<TextEditingController> controllers;
  final Widget child;

  const _DialogControllerScope({
    required this.controllers,
    required this.child,
  });

  @override
  State<_DialogControllerScope> createState() =>
      _DialogControllerScopeState();
}

class _DialogControllerScopeState extends State<_DialogControllerScope> {
  @override
  void dispose() {
    for (final controller in widget.controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
