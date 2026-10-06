import '../services/voice_diagnostics_service.dart';
import '../l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../features/smart_entry/transaction_batch_draft.dart';
import '../models/expense_model.dart';
import '../models/wallet_model.dart';
import '../providers/category_provider.dart';
import '../providers/expense_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/wallet_provider.dart';
import '../services/transaction_executor.dart';

class BatchTransactionReviewScreen extends ConsumerStatefulWidget {
  final TransactionBatchDraft draft;
  final String? diagnosticId;

  const BatchTransactionReviewScreen({
    super.key,
    required this.draft,
    this.diagnosticId,
  });

  @override
  ConsumerState<BatchTransactionReviewScreen> createState() =>
      _BatchTransactionReviewScreenState();
}

class _BatchTransactionReviewScreenState
    extends ConsumerState<BatchTransactionReviewScreen> {
  late final List<_BatchReviewRow> _rows;
  String? _globalWalletId;
  String? _globalCategory;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _rows = widget.draft.entries
        .map((entry) => _BatchReviewRow.fromDraft(entry))
        .toList(growable: true);
    _globalWalletId = _commonValue(
      widget.draft.entries.map((entry) => entry.walletId),
    );
    _globalCategory = _commonValue(
      widget.draft.entries
          .where((entry) => entry.type == 'expense')
          .map((entry) => entry.category),
    );
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  T? _commonValue<T>(Iterable<T?> values) {
    final nonNull = values.whereType<T>().toSet();
    return nonNull.length == 1 ? nonNull.single : null;
  }

  List<_BatchReviewRow> get _selectedRows =>
      _rows.where((row) => row.included).toList(growable: false);

  double get _expenseTotal => _selectedRows
      .where((row) => row.type == 'expense')
      .fold<double>(0, (sum, row) => sum + row.amount);

  double get _incomeTotal => _selectedRows
      .where((row) => row.type == 'income')
      .fold<double>(0, (sum, row) => sum + row.amount);

  bool _canSave(List<Wallet> wallets, List<String> categories) {
    final selected = _selectedRows;
    if (selected.isEmpty) return false;

    final validWalletIds = wallets.map((wallet) => wallet.id).toSet();
    for (final row in selected) {
      if (row.title.text.trim().isEmpty ||
          !row.amount.isFinite ||
          row.amount <= 0 ||
          row.walletId == null ||
          !validWalletIds.contains(row.walletId)) {
        return false;
      }
      if (row.type == 'expense' &&
          (row.category.trim().isEmpty ||
              !categories.contains(row.category))) {
        return false;
      }
    }

    final proposed = selected.asMap().entries.map((item) {
      final row = item.value;
      return Expense(
        id: 'preview-${item.key}',
        title: row.title.text.trim(),
        amount: row.amount,
        date: row.date,
        category: row.type == 'income'
            ? 'Income / Allowance'
            : row.category,
        colorValue: 0,
        type: row.type,
        walletId: row.walletId!,
      );
    }).toList(growable: false);

    return keepsWalletBalancesNonNegative(
      openingBalances: {
        for (final wallet in wallets) wallet.id: wallet.balance,
      },
      existingEntries: ref.read(expenseProvider).allExpenses,
      proposedEntries: proposed,
    );
  }

  void _applyGlobalWallet(String? walletId) {
    setState(() {
      _globalWalletId = walletId;
      if (walletId == null) return;
      for (final row in _rows.where((item) => item.included)) {
        row.walletId = walletId;
      }
    });
  }

  void _applyGlobalCategory(String? category) {
    setState(() {
      _globalCategory = category;
      if (category == null) return;
      for (final row in _rows.where(
        (item) => item.included && item.type == 'expense',
      )) {
        row.category = category;
      }
    });
  }

  Future<void> _save(
    List<Wallet> wallets,
    List<String> categories,
  ) async {
    if (_saving || !_canSave(wallets, categories)) return;

    final selected = _selectedRows;
    final colorValue =
        Color(ref.read(settingsProvider).profileColorValue).toARGB32();

    final entries = selected
        .map(
          (row) => Expense(
            id: const Uuid().v4(),
            title: row.title.text.trim(),
            amount: row.amount,
            date: row.date,
            category: row.type == 'income'
                ? 'Income / Allowance'
                : row.category,
            colorValue: colorValue,
            type: row.type,
            walletId: row.walletId!,
          ),
        )
        .toList(growable: false);

    setState(() => _saving = true);
    try {
      final result = await VoiceDiagnosticsService.instance.run(widget.diagnosticId, () => ref.read(transactionExecutorProvider).execute(
            CreateBatchTransactionsCommand(entries: entries),
          ));
      if (!mounted) return;
      if (!result.succeeded) {
        _showError(
          result.reason ??
              'The batch could not be saved. No transactions were added.',
        );
        return;
      }
      Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(AppStrings.current.display(message)),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red.shade700,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    AppStrings.of(context);
    final wallets = ref.watch(walletProvider);
    final categories = ref.watch(categoryProvider);
    final canSave = _canSave(wallets, categories);

    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.current.text('review_entries_042cd1')),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
          children: [
            _buildReviewNotice(),
            const SizedBox(height: 16),
            _buildGlobalSettings(wallets, categories),
            const SizedBox(height: 16),
            Text(
              AppStrings.current.text('detected_entries_b986ed'),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              AppStrings.current.text('selected_entries_are_saved_atomically_either_all_6c6754'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            for (var index = 0; index < _rows.length; index++)
              _buildRow(index, wallets, categories),
            OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  _rows.add(
                    _BatchReviewRow.manual(
                      walletId: _globalWalletId ??
                          (wallets.isEmpty ? null : wallets.first.id),
                      category: _globalCategory ??
                          (categories.isEmpty ? 'General' : categories.first),
                    ),
                  );
                });
              },
              icon: const Icon(Icons.add_rounded),
              label: Text(AppStrings.current.text('add_manual_item_5cbf10')),
            ),
            const SizedBox(height: 16),
            _buildSummary(),
            const SizedBox(height: 12),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(AppStrings.current.text('original_input_04f90b')),
              subtitle: Text(
                AppStrings.current.text('use_this_to_verify_what_likhlo_interpreted_7703b9'),
              ),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: SelectableText(widget.draft.rawInput),
                ),
              ],
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: FilledButton.icon(
          onPressed: !_saving && canSave
              ? () => _save(wallets, categories)
              : null,
          icon: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check_rounded),
          label: Text(
            _saving
                ? AppStrings.current.text('saving_ae7e88')
                : AppStrings.current.text('save_entries_f920ee', {'p0': _selectedRows.length}),
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReviewNotice() {
    final source = widget.draft.source == TransactionBatchSource.voice
        ? 'voice'
        : 'text';
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.fact_check_outlined),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                AppStrings.current.text('multiple_entries_were_detected_review_each_item__aaeaf9', {'p0': source}),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGlobalSettings(
    List<Wallet> wallets,
    List<String> categories,
  ) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppStrings.current.text('apply_to_selected_entries_8d2c19'),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              isExpanded: true,
              key: ValueKey('global-wallet-$_globalWalletId'),
              initialValue:
                  wallets.any((wallet) => wallet.id == _globalWalletId)
                      ? _globalWalletId
                      : null,
              decoration: InputDecoration(
                labelText: AppStrings.current.text('wallet_b60862'),
                border: OutlineInputBorder(),
              ),
              hint: Text(AppStrings.current.text('keep_detected_wallets_6de769')),
              items: wallets
                  .map(
                    (wallet) => DropdownMenuItem(
                      value: wallet.id,
                      child: Text(
                        wallet.name,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(growable: false),
              onChanged: _applyGlobalWallet,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              isExpanded: true,
              key: ValueKey('global-category-$_globalCategory'),
              initialValue: categories.contains(_globalCategory)
                  ? _globalCategory
                  : null,
              decoration: InputDecoration(
                labelText: AppStrings.current.text('expense_category_a78210'),
                border: OutlineInputBorder(),
              ),
              hint: Text(AppStrings.current.text('keep_detected_categories_bae015')),
              items: categories
                  .map(
                    (category) => DropdownMenuItem(
                      value: category,
                      child: Text(
                        AppStrings.current.display(category),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(growable: false),
              onChanged: _applyGlobalCategory,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(
    int index,
    List<Wallet> wallets,
    List<String> categories,
  ) {
    final row = _rows[index];
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
        child: Column(
          children: [
            Row(
              children: [
                Checkbox(
                  value: row.included,
                  onChanged: (value) {
                    setState(() => row.included = value ?? false);
                  },
                ),
                Expanded(
                  child: Text(
                    row.type == 'income' ? AppStrings.current.text('income_1c89b1') : AppStrings.current.text('expense_a0db8e'),
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: row.type == 'income'
                          ? Colors.green.shade700
                          : Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                if (row.hasInheritedContext)
                  Tooltip(
                    message: AppStrings.current.text('wallet_or_date_inherited_from_batch_context_e9f30d'),
                    child: Icon(Icons.link_rounded, size: 18),
                  ),
                IconButton(
                  tooltip: AppStrings.current.text('remove_item_76ecba'),
                  onPressed: () {
                    setState(() {
                      final removed = _rows.removeAt(index);
                      removed.dispose();
                    });
                  },
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            TextField(
              controller: row.title,
              enabled: row.included,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: AppStrings.current.text('title_768e0c'),
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: row.amountController,
              enabled: row.included,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: AppStrings.current.text('amount_rs_34c21f'),
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              isExpanded: true,
              key: ValueKey('row-wallet-$index-${row.walletId}'),
              initialValue: wallets.any((wallet) => wallet.id == row.walletId)
                  ? row.walletId
                  : null,
              decoration: InputDecoration(
                labelText: AppStrings.current.text('wallet_b60862'),
                border: OutlineInputBorder(),
              ),
              items: wallets
                  .map(
                    (wallet) => DropdownMenuItem(
                      value: wallet.id,
                      child: Text(
                        wallet.name,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(growable: false),
              onChanged: row.included
                  ? (value) => setState(() => row.walletId = value)
                  : null,
            ),
            if (row.type == 'expense') ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                isExpanded: true,
                key: ValueKey('row-category-$index-${row.category}'),
                initialValue: categories.contains(row.category)
                    ? row.category
                    : null,
                decoration: InputDecoration(
                  labelText: AppStrings.current.text('category_a3c686'),
                  border: OutlineInputBorder(),
                ),
                items: categories
                    .map(
                      (category) => DropdownMenuItem(
                        value: category,
                        child: Text(
                          AppStrings.current.display(category),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(growable: false),
                onChanged: row.included
                    ? (value) {
                        if (value != null) {
                          setState(() => row.category = value);
                        }
                      }
                    : null,
              ),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${DateFormat('dd MMM yyyy').format(row.date)} · ${row.sourceText}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummary() {
    final net = _incomeTotal - _expenseTotal;
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _summaryLine('Expenses', _expenseTotal),
            const SizedBox(height: 6),
            _summaryLine('Income', _incomeTotal),
            const Divider(height: 20),
            _summaryLine('Net change', net, signed: true),
          ],
        ),
      ),
    );
  }

  Widget _summaryLine(
    String label,
    double amount, {
    bool signed = false,
  }) {
    final prefix = signed && amount > 0 ? '+' : '';
    return Row(
      children: [
        Expanded(child: Text(AppStrings.current.display(label))),
        Text(
          'Rs. $prefix${amount.toStringAsFixed(0)}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}

class _BatchReviewRow {
  final TextEditingController title;
  final TextEditingController amountController;
  String category;
  String? walletId;
  final String type;
  DateTime date;
  bool included;
  final bool hasInheritedContext;
  final String sourceText;

  _BatchReviewRow({
    required this.title,
    required this.amountController,
    required this.category,
    required this.walletId,
    required this.type,
    required this.date,
    required this.included,
    required this.hasInheritedContext,
    required this.sourceText,
  });

  factory _BatchReviewRow.fromDraft(TransactionDraft draft) {
    return _BatchReviewRow(
      title: TextEditingController(text: draft.title),
      amountController: TextEditingController(
        text: draft.amount == draft.amount.truncateToDouble()
            ? draft.amount.toStringAsFixed(0)
            : draft.amount.toStringAsFixed(2),
      ),
      category: draft.category,
      walletId: draft.walletId,
      type: draft.type,
      date: draft.date,
      included: true,
      hasInheritedContext:
          !draft.hasExplicitWallet || !draft.hasExplicitDate,
      sourceText: draft.sourceText,
    );
  }

  factory _BatchReviewRow.manual({
    required String? walletId,
    required String category,
  }) {
    return _BatchReviewRow(
      title: TextEditingController(),
      amountController: TextEditingController(),
      category: category,
      walletId: walletId,
      type: 'expense',
      date: DateTime.now(),
      included: true,
      hasInheritedContext: false,
      sourceText: 'Manual item',
    );
  }

  double get amount =>
      double.tryParse(amountController.text.trim()) ?? 0.0;

  void dispose() {
    title.dispose();
    amountController.dispose();
  }
}
