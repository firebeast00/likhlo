import '../l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/expense_model.dart';
import '../models/wallet_model.dart';
import '../providers/category_provider.dart';
import '../providers/wallet_provider.dart';
import '../services/ocr_scanner_service.dart';
import '../services/transaction_executor.dart';

enum _ReceiptSaveMode { items, total }

class ReceiptReviewScreen extends ConsumerStatefulWidget {
  final ScannedReceipt receipt;
  final Future<ScannedReceipt?> Function()? onAdjustSelection;

  const ReceiptReviewScreen({
    super.key,
    required this.receipt,
    this.onAdjustSelection,
  });

  @override
  ConsumerState<ReceiptReviewScreen> createState() =>
      _ReceiptReviewScreenState();
}

class _ReceiptReviewScreenState extends ConsumerState<ReceiptReviewScreen> {
  final List<_ReceiptRow> _rows = [];
  final _totalTitleController = TextEditingController();
  final _totalController = TextEditingController();
  late ScannedReceipt _receipt;
  _ReceiptSaveMode _mode = _ReceiptSaveMode.items;
  String? _globalWalletId;
  String? _globalCategory;
  bool _confirmDiscrepancy = false;
  bool _totalConfirmed = false;
  bool _saving = false;
  bool _adjusting = false;

  @override
  void initState() {
    super.initState();
    _applyReceipt(widget.receipt);
  }

  void _applyReceipt(ScannedReceipt receipt) {
    for (final row in _rows) {
      row.dispose();
    }
    _rows.clear();
    _receipt = receipt;
    _rows.addAll(
      receipt.items.map(
        (item) => _ReceiptRow(
          title: TextEditingController(text: item.name),
          amount: TextEditingController(text: _formatAmount(item.price)),
          category: item.category,
          issue: item.issue,
        ),
      ),
    );
    // Adjustments must not silently disappear from the recorded purchase.
    _mode = receipt.items.isEmpty || receipt.adjustmentTotal.abs() > 0.01
        ? _ReceiptSaveMode.total
        : _ReceiptSaveMode.items;
    _totalTitleController.text = receipt.purchaseTitle;
    _totalController.text = _formatAmount(receipt.total);
    _globalCategory = null;
    _confirmDiscrepancy = false;
    _totalConfirmed = false;
  }

  bool get _totalNeedsReview =>
      !_totalConfirmed &&
      ((!_receipt.hasPrintedTotal &&
              _receipt.items.any((item) => item.needsReview)) ||
          _receipt.issues.any(
            (issue) =>
                issue == 'receipt_amount_uncertain' ||
                issue == 'receipt_conflicting_totals',
          ));

  Future<void> _adjustSelection() async {
    if (widget.onAdjustSelection == null || _adjusting || _saving) return;
    setState(() => _adjusting = true);
    try {
      final receipt = await widget.onAdjustSelection!();
      if (mounted && receipt != null) setState(() => _applyReceipt(receipt));
    } finally {
      if (mounted) setState(() => _adjusting = false);
    }
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    _totalTitleController.dispose();
    _totalController.dispose();
    super.dispose();
  }

  static String _formatAmount(double value) => value == value.truncateToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);

  double get _selectedTotal => _rows
      .where((row) => row.included)
      .fold<double>(
        0,
        (sum, row) => sum + (double.tryParse(row.amount.text) ?? 0),
      );

  double get _currentCalculatedTotal {
    if (_mode == _ReceiptSaveMode.total) {
      return double.tryParse(_totalController.text.trim()) ?? 0.0;
    } else {
      return _selectedTotal;
    }
  }

  double get _difference => _selectedTotal - _receipt.total;

  bool get _hasSuspiciousDifference {
    if (_receipt.total <= 0) return false;
    final limit = _receipt.total * 0.001 > 1 ? _receipt.total * 0.001 : 1.0;
    return _difference.abs() > limit;
  }

  @override
  Widget build(BuildContext context) {
    AppStrings.of(context);
    final wallets = ref.watch(walletProvider);
    final categories = ref.watch(categoryProvider);

    _globalWalletId ??= wallets.isEmpty ? null : wallets.first.id;
    _globalCategory ??= categories.contains(_receipt.category)
        ? _receipt.category
        : (categories.isEmpty ? 'General' : categories.first);

    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.current.text('review_receipt_c65cbb')),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
          children: [
            _buildConfidenceCard(),
            if (widget.onAdjustSelection != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _saving || _adjusting ? null : _adjustSelection,
                  icon: const Icon(Icons.crop_free),
                  label: Text(
                    AppStrings.current.text('receipt_adjust_selection'),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            _buildGlobalSettings(wallets, categories),
            SegmentedButton<_ReceiptSaveMode>(
              segments: [
                ButtonSegment(
                  value: _ReceiptSaveMode.items,
                  icon: Icon(Icons.receipt_long_outlined),
                  label: Text(
                    AppStrings.current.text('individual_items_75b5eb'),
                  ),
                ),
                ButtonSegment(
                  value: _ReceiptSaveMode.total,
                  icon: Icon(Icons.payments_outlined),
                  label: Text(AppStrings.current.text('single_total_4d8a59')),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: _saving
                  ? null
                  : (value) {
                      setState(() {
                        _mode = value.first;
                        _confirmDiscrepancy = false;
                      });
                    },
            ),
            const SizedBox(height: 20),
            if (_mode == _ReceiptSaveMode.items)
              ..._buildItemEditor()
            else
              ..._buildTotalEditor(),
            const SizedBox(height: 16),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(AppStrings.current.text('raw_scanned_text_f7d374')),
              subtitle: Text(
                AppStrings.current.text(
                  'use_this_to_verify_any_uncertain_fields_6ecd91',
                ),
              ),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: SelectableText(
                    _receipt.rawText.trim().isEmpty
                        ? AppStrings.current.display(
                            'No raw text was recognized.',
                          )
                        : _receipt.rawText,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: FilledButton.icon(
          onPressed:
              _saving ||
                  _adjusting ||
                  !(_currentCalculatedTotal > 0) ||
                  !_currentCalculatedTotal.isFinite
              ? null
              : _save,
          icon: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check_rounded),
          label: Text(
            _saving
                ? AppStrings.current.text('saving_ae7e88')
                : AppStrings.current.text('save_rs_c7ccc7', {
                    'p0': _currentCalculatedTotal.toStringAsFixed(2),
                  }),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ),
      ),
    );
  }

  Widget _buildConfidenceCard() {
    final uncertain = _rows.where((row) => row.needsReview).length;
    final empty = _receipt.total <= 0 && _receipt.items.isEmpty;
    final attention = empty || uncertain > 0 || _receipt.issues.isNotEmpty;
    return Card(
      elevation: 0,
      color: attention
          ? Theme.of(context).colorScheme.errorContainer
          : Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppStrings.current.text(
                empty
                    ? 'receipt_not_detected'
                    : uncertain > 0
                    ? 'receipt_check_highlighted'
                    : 'receipt_ready',
              ),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            for (final issue in _receipt.issues)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(AppStrings.current.text(issue)),
              ),
            if (_receipt.adjustmentTotal.abs() > 0.01)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  AppStrings.current.text('receipt_adjustments_total'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildGlobalSettings(List<Wallet> wallets, List<String> categories) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(context).dividerColor.withOpacity(0.2),
        ),
      ),
      margin: const EdgeInsets.only(bottom: 24),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppStrings.current.text('payment_details_b8579d'),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue:
                        wallets.any((wallet) => wallet.id == _globalWalletId)
                        ? _globalWalletId
                        : null,
                    decoration: InputDecoration(
                      labelText: AppStrings.current.text('paid_from_a2cf4d'),
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
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
                        .toList(),
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _globalWalletId = value),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: categories.contains(_globalCategory)
                        ? _globalCategory
                        : null,
                    decoration: InputDecoration(
                      labelText: AppStrings.current.text('category_a3c686'),
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
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
                        .toList(),
                    onChanged: _saving
                        ? null
                        : (value) => setState(() {
                            _globalCategory = value;
                            for (final row in _rows) {
                              row.category = value;
                            }
                          }),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildItemEditor() {
    return [
      Text(
        AppStrings.current.text('receipt_items_7103c3'),
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 4),
      Text(
        AppStrings.current.text(
          'selected_items_are_saved_atomically_either_all_a_690c15',
        ),
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 12),
      for (var index = 0; index < _rows.length; index++) _buildItemRow(index),
      OutlinedButton.icon(
        onPressed: () {
          setState(() {
            _confirmDiscrepancy = false;
            _rows.add(
              _ReceiptRow(
                title: TextEditingController(),
                amount: TextEditingController(),
                category: _globalCategory,
              ),
            );
          });
        },
        icon: const Icon(Icons.add_rounded),
        label: Text(AppStrings.current.text('add_manual_item_5cbf10')),
      ),
      const SizedBox(height: 16),
      Card(
        elevation: 0,
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withOpacity(0.3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _totalLine('Detected receipt total', _receipt.total),
              _totalLine('Sum of selected items', _selectedTotal),
              const Divider(height: 16),
              _totalLine('Difference', _difference, signed: true),
              if (_hasSuspiciousDifference) ...[
                const SizedBox(height: 12),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _confirmDiscrepancy,
                  title: Text(
                    AppStrings.current.text(
                      'save_despite_this_difference_e206c1',
                    ),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                  subtitle: Text(
                    AppStrings.current.text(
                      'the_items_you_selected_do_not_match_the_total_de_d4d711',
                    ),
                  ),
                  onChanged: (value) =>
                      setState(() => _confirmDiscrepancy = value ?? false),
                ),
              ],
            ],
          ),
        ),
      ),
    ];
  }

  Widget _buildItemRow(int index) {
    final row = _rows[index];
    final categories = ref.watch(categoryProvider);
    final category = categories.contains(row.category)
        ? row.category
        : _globalCategory;
    return Card(
      key: ObjectKey(row),
      color: row.needsReview
          ? Theme.of(context).colorScheme.errorContainer
          : null,
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        initiallyExpanded: row.needsReview,
        leading: Checkbox(
          value: row.included,
          onChanged: _saving
              ? null
              : (value) => setState(() {
                  row.included = value ?? false;
                  _confirmDiscrepancy = false;
                }),
        ),
        title: Text(
          row.title.text.isEmpty
              ? AppStrings.current.text('item_name_497c97')
              : row.title.text,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          'Rs ${row.amount.text} · ${AppStrings.current.display(category ?? 'General')}',
        ),
        childrenPadding: const EdgeInsets.all(12),
        children: [
          if (row.issue != null) Text(AppStrings.current.text(row.issue!)),
          TextField(
            controller: row.title,
            enabled: row.included && !_saving,
            decoration: InputDecoration(
              labelText: AppStrings.current.text('item_name_497c97'),
            ),
            onChanged: (_) => setState(() {}),
          ),
          TextField(
            controller: row.amount,
            enabled: row.included && !_saving,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: AppStrings.current.text('amount_rs_34c21f'),
            ),
            onChanged: (_) => setState(() {
              row.verified = true;
              _confirmDiscrepancy = false;
            }),
          ),
          DropdownButtonFormField<String>(
            key: ValueKey(category),
            initialValue: categories.contains(category) ? category : null,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: AppStrings.current.text('category_a3c686'),
            ),
            items: categories
                .map(
                  (name) => DropdownMenuItem(
                    value: name,
                    child: Text(AppStrings.current.display(name)),
                  ),
                )
                .toList(),
            onChanged: row.included && !_saving
                ? (value) => setState(() => row.category = value)
                : null,
          ),
          if (row.issue != null)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: row.verified,
              title: Text(AppStrings.current.text('receipt_checked_amount')),
              onChanged: _saving
                  ? null
                  : (value) => setState(() => row.verified = value ?? false),
            ),
          TextButton.icon(
            onPressed: _saving
                ? null
                : () => setState(() {
                    _rows.removeAt(index).dispose();
                    _confirmDiscrepancy = false;
                  }),
            icon: const Icon(Icons.close),
            label: Text(AppStrings.current.text('remove_item_76ecba')),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildTotalEditor() {
    return [
      TextField(
        controller: _totalTitleController,
        decoration: InputDecoration(
          labelText: AppStrings.current.text('receipt_description_9ffce2'),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _totalController,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: AppStrings.current.text('receipt_total_rs_5b78f7'),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onChanged: (_) => setState(() => _totalConfirmed = true),
      ),
      if (_totalNeedsReview)
        CheckboxListTile(
          value: _totalConfirmed,
          title: Text(AppStrings.current.text('receipt_checked_total')),
          onChanged: (value) =>
              setState(() => _totalConfirmed = value ?? false),
        ),
      const SizedBox(height: 12),
      Text(
        AppStrings.current.text(
          'single_total_mode_creates_one_expense_only_indiv_71fae6',
        ),
        style: TextStyle(color: Colors.grey),
      ),
    ];
  }

  Widget _totalLine(String label, double value, {bool signed = false}) {
    final prefix = signed && value > 0 ? '+' : '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              AppStrings.current.display(label),
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Text(
            'Rs $prefix${value.toStringAsFixed(2)}',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (_saving || _adjusting) return;
    if ((_mode == _ReceiptSaveMode.items &&
            _rows.any((row) => row.included && row.needsReview)) ||
        (_mode == _ReceiptSaveMode.total && _totalNeedsReview)) {
      _showError(AppStrings.current.text('receipt_check_highlighted'));
      return;
    }
    if (_mode == _ReceiptSaveMode.items &&
        _hasSuspiciousDifference &&
        !_confirmDiscrepancy) {
      _showError('Confirm the receipt total difference before saving.');
      return;
    }
    if (_globalWalletId == null || _globalCategory == null) {
      _showError('Choose a wallet and category at the top first.');
      return;
    }

    final wallets = ref.read(walletProvider);
    if (!wallets.any((wallet) => wallet.id == _globalWalletId)) {
      _showError('Choose a wallet and category at the top first.');
      return;
    }
    final selectedWallet = wallets.firstWhere((w) => w.id == _globalWalletId);
    final currentBalance = ref
        .read(walletProvider.notifier)
        .getBalanceForWallet(selectedWallet.id);

    double totalDeduction = 0.0;
    final entries = <Expense>[];

    if (_mode == _ReceiptSaveMode.total) {
      final amount = double.tryParse(_totalController.text.trim());
      if (amount == null || !amount.isFinite || amount <= 0) {
        _showError('Enter a valid receipt total.');
        return;
      }
      totalDeduction = amount;

      entries.add(
        Expense(
          id: const Uuid().v4(),
          title: _totalTitleController.text.trim().isEmpty
              ? 'Receipt purchase'
              : _totalTitleController.text.trim(),
          amount: amount,
          date: DateTime.now(),
          category: _globalCategory!,
          colorValue: 0xFFEF4444,
          type: 'expense',
          walletId: _globalWalletId!,
        ),
      );
    } else {
      for (final row in _rows.where((row) => row.included)) {
        final amount = double.tryParse(row.amount.text.trim());
        if (row.title.text.trim().isEmpty ||
            amount == null ||
            !amount.isFinite ||
            amount <= 0) {
          _showError('Every selected item needs a valid name and amount.');
          return;
        }
        totalDeduction += amount;
        entries.add(
          Expense(
            id: const Uuid().v4(),
            title: row.title.text.trim(),
            amount: amount,
            date: DateTime.now(),
            category: ref.read(categoryProvider).contains(row.category)
                ? row.category!
                : _globalCategory!,
            colorValue: 0xFFEF4444,
            type: 'expense',
            walletId: _globalWalletId!,
          ),
        );
      }

      if (entries.isEmpty) {
        _showError('Select at least one receipt item.');
        return;
      }
    }

    if (totalDeduction > currentBalance) {
      _showError(
        'Insufficient balance in ${selectedWallet.name}. Need Rs. ${totalDeduction.toStringAsFixed(0)}, but you only have Rs. ${currentBalance.toStringAsFixed(0)}.',
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final executor = ref.read(transactionExecutorProvider);
      TransactionResult result;

      if (_mode == _ReceiptSaveMode.total) {
        result = await executor.execute(
          CreateTransactionCommand(entries.first),
        );
      } else {
        result = await executor.execute(
          CreateBatchTransactionsCommand(
            entries: entries,
            detectedTotal: _receipt.total,
            discrepancyConfirmed: _confirmDiscrepancy,
          ),
        );
      }

      if (!mounted) return;
      if (!result.succeeded) {
        _showError(result.reason ?? 'The receipt could not be saved.');
        return;
      }

      Navigator.of(context).pop(true);
    } catch (_) {
      _showError('The receipt could not be saved.');
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
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }
}

class _ReceiptRow {
  final TextEditingController title;
  final TextEditingController amount;
  bool included = true;
  String? category;
  final String? issue;
  bool verified = false;
  bool get needsReview => issue != null && !verified;

  _ReceiptRow({
    required this.title,
    required this.amount,
    this.category,
    this.issue,
  });

  void dispose() {
    title.dispose();
    amount.dispose();
  }
}
