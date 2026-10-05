import '../l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/expense_model.dart';
import '../models/wallet_model.dart';
import '../providers/expense_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/wallet_provider.dart';
import '../services/transaction_executor.dart';

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
            title: Text(existing == null ? AppStrings.current.text('new_wallet_325723') : AppStrings.current.text('update_wallet_fd811d')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: AppStrings.current.text('wallet_name_33ba81'),
                    errorText: nameError,
                    prefixIcon:
                        const Icon(Icons.account_balance_wallet_outlined),
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
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true, signed: false),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'^\d*\.?\d{0,2}'),
                    ),
                  ],
                  decoration: InputDecoration(
                    labelText: AppStrings.current.text('current_balance_a234f7'),
                    hintText: AppStrings.current.text('amount_currently_available_87bcc0'),
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
                Text(
                  AppStrings.current.text('this_amount_is_included_automatically_in_the_tot_1e4c27'),
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(AppStrings.current.text('reserve_wallet_686caf')),
                  subtitle:
                      Text(AppStrings.current.text('mark_money_that_you_prefer_to_keep_aside_1ac728')),
                  value: isBackup,
                  onChanged: (value) => setDialogState(() => isBackup = value),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(AppStrings.current.text('cancel_77dfd2')),
              ),
              FilledButton(
                onPressed: () async {
                  final name = controller.text.trim();
                  final balance =
                      double.tryParse(balanceController.text.trim());
                  if (name.isEmpty) {
                    setDialogState(() => nameError = 'Enter a wallet name.');
                    return;
                  }
                  if (balance == null || !balance.isFinite || balance < 0) {
                    setDialogState(() => balanceError =
                        'Enter a valid balance of zero or more.');
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
                      () =>
                          nameError = 'A wallet with this name already exists.',
                    );
                    return;
                  }
                  Navigator.pop(dialogContext);
                },
                child: Text(existing == null ? AppStrings.current.text('create_6e157c') : AppStrings.current.text('update_fb91e2')),
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
    String walletId = wallets
        .firstWhere((wallet) => !wallet.isBackup, orElse: () => wallets.first)
        .id;
    String? error;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _DialogControllerScope(
        controllers: [titleController, amountController],
        child: StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(AppStrings.current.text('add_income_4d6cdd')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: AppStrings.current.text('income_title_a0661e'),
                    hintText: AppStrings.current.text('salary_allowance_freelance_051ac3'),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true, signed: false),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'^\d*\.?\d{0,2}'),
                    ),
                  ],
                  decoration: InputDecoration(
                    labelText: AppStrings.current.text('amount_43dc85'),
                    prefixText: 'Rs. ',
                    errorText: error,
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: walletId,
                  decoration: InputDecoration(labelText: AppStrings.current.text('wallet_b60862')),
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
                Text(
                  AppStrings.current.text('this_income_increases_the_selected_wallet_and_th_3f8261'),
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(AppStrings.current.text('cancel_77dfd2')),
              ),
              FilledButton(
                onPressed: () async {
                  final amount = double.tryParse(amountController.text.trim());
                  if (amount == null || !amount.isFinite || amount <= 0) {
                    setDialogState(
                        () => error = 'Enter a valid amount above zero.');
                    return;
                  }

                  final result = await ref
                      .read(transactionExecutorProvider)
                      .execute(CreateTransactionCommand(
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
                      ));
                  if (!dialogContext.mounted) return;
                  if (!result.succeeded) {
                    setDialogState(() => error = 'Could not save this income.');
                    return;
                  }
                  Navigator.pop(dialogContext);
                },
                child: Text(AppStrings.current.text('add_income_4d6cdd')),
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
            title: Text(AppStrings.current.text('clear_wallet_balance_989625')),
            content: Text(
              AppStrings.current.text('set_to_rs_0_transaction_history_will_remain_avai_61a4b0', {'p0': wallet.name}),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(AppStrings.current.text('cancel_77dfd2')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(AppStrings.current.text('clear_balance_204c15')),
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
        SnackBar(content: Text(AppStrings.current.text('at_least_one_wallet_is_required_ad359c'))),
      );
      return;
    }

    final fallback = wallets.firstWhere(
      (candidate) => candidate.id != wallet.id && !candidate.isBackup,
      orElse: () =>
          wallets.firstWhere((candidate) => candidate.id != wallet.id),
    );
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(AppStrings.current.text('delete_wallet_d09dab')),
            content: Text(
              AppStrings.current.text('delete_its_transaction_history_and_opening_adjus_be1766', {'p0': wallet.name, 'p1': fallback.name}),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(AppStrings.current.text('cancel_77dfd2')),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(AppStrings.current.text('delete_f6fdbe')),
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
    AppStrings.of(context);
    final wallets = ref.watch(walletProvider);
    ref.watch(expenseProvider);
    final primaryColor = Color(ref.watch(settingsProvider).profileColorValue);

    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.current.text('wallets_98d5a1')),
        actions: [
          IconButton(
            tooltip: AppStrings.current.text('create_wallet_f4a4e0'),
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
              subtitle: Text(wallet.isBackup ? AppStrings.current.text('reserve_wallet_686caf') : AppStrings.current.text('wallet_b60862')),
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
                    itemBuilder: (_) => [
                      PopupMenuItem(
                          value: 'edit', child: Text(AppStrings.current.text('rename_update_9ef904'))),
                      PopupMenuItem(
                          value: 'clear', child: Text(AppStrings.current.text('clear_balance_204c15'))),
                      PopupMenuItem(value: 'delete', child: Text(AppStrings.current.text('delete_f6fdbe'))),
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
        label: Text(AppStrings.current.text('add_income_4d6cdd')),
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
  State<_DialogControllerScope> createState() => _DialogControllerScopeState();
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
