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

  const ReceiptReviewScreen({
    super.key,
    required this.receipt,
  });

  @override
  ConsumerState<ReceiptReviewScreen> createState() =>
      _ReceiptReviewScreenState();
}

class _ReceiptReviewScreenState extends ConsumerState<ReceiptReviewScreen> {
  late final List<_ReceiptRow> _rows;
  late final TextEditingController _totalTitleController;
  late final TextEditingController _totalController;

  _ReceiptSaveMode _mode = _ReceiptSaveMode.items;

  String? _globalWalletId;
  String? _globalCategory;

  bool _confirmDiscrepancy = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _rows = widget.receipt.items
        .map(
          (item) => _ReceiptRow(
        title: TextEditingController(text: item.name),
        amount: TextEditingController(text: _formatAmount(item.price)),
      ),
    )
        .toList();

    if (_rows.isEmpty && widget.receipt.total > 0) {
      _rows.add(
        _ReceiptRow(
          title: TextEditingController(
            text: widget.receipt.vendor.trim().isEmpty
                ? 'Receipt purchase'
                : widget.receipt.vendor.trim(),
          ),
          amount: TextEditingController(
            text: _formatAmount(widget.receipt.total),
          ),
        ),
      );
    }

    _mode = widget.receipt.items.isEmpty
        ? _ReceiptSaveMode.total
        : _ReceiptSaveMode.items;

    _totalTitleController = TextEditingController(
      text: widget.receipt.vendor.trim().isEmpty
          ? 'Receipt purchase'
          : widget.receipt.vendor.trim(),
    );
    _totalController = TextEditingController(
      text: _formatAmount(widget.receipt.total),
    );
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

  static String _formatAmount(double value) =>
      value == value.truncateToDouble()
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

  double get _difference => _selectedTotal - widget.receipt.total;

  bool get _hasSuspiciousDifference {
    if (widget.receipt.total <= 0) return false;
    final limit = widget.receipt.total * 0.05 > 5
        ? widget.receipt.total * 0.05
        : 5.0;
    return _difference.abs() > limit;
  }

  @override
  Widget build(BuildContext context) {
    final wallets = ref.watch(walletProvider);
    final categories = ref.watch(categoryProvider);

    _globalWalletId ??= wallets.isEmpty ? null : wallets.first.id;
    _globalCategory ??= categories.contains(widget.receipt.category)
        ? widget.receipt.category
        : (categories.isEmpty ? 'General' : categories.first);

    return Scaffold(
      appBar: AppBar(title: const Text('Review receipt')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
          children: [
            _buildConfidenceCard(),
            const SizedBox(height: 16),
            _buildGlobalSettings(wallets, categories),
            SegmentedButton<_ReceiptSaveMode>(
              segments: const [
                ButtonSegment(
                  value: _ReceiptSaveMode.items,
                  icon: Icon(Icons.receipt_long_outlined),
                  label: Text('Individual items'),
                ),
                ButtonSegment(
                  value: _ReceiptSaveMode.total,
                  icon: Icon(Icons.payments_outlined),
                  label: Text('Single total'),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (value) {
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
              title: const Text('Raw scanned text'),
              subtitle: const Text('Use this to verify any uncertain fields.'),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: SelectableText(
                    widget.receipt.rawText.trim().isEmpty
                        ? 'No raw text was recognized.'
                        : widget.receipt.rawText,
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
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
              : const Icon(Icons.check_rounded),
          label: Text(
            _saving
                ? 'Saving...'
                : 'Save Rs. ${_currentCalculatedTotal.toStringAsFixed(0)}',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ),
      ),
    );
  }

  Widget _buildConfidenceCard() {
    final percent = (widget.receipt.confidence * 100).round();
    final low = widget.receipt.confidence < 0.7;
    return Card(
      elevation: 0,
      color: low
          ? Theme.of(context).colorScheme.errorContainer
          : Theme.of(context).colorScheme.secondaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(low ? Icons.warning_amber_rounded : Icons.fact_check_outlined),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Scan confidence: $percent%. Check names and amounts before saving. Nothing is added until you confirm below.',
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
        side: BorderSide(color: Theme.of(context).dividerColor.withOpacity(0.2)),
      ),
      margin: const EdgeInsets.only(bottom: 24),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Payment Details',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: wallets.any((wallet) => wallet.id == _globalWalletId)
                        ? _globalWalletId
                        : null,
                    decoration: InputDecoration(
                      labelText: 'Paid From',
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    items: wallets.map((wallet) => DropdownMenuItem(
                      value: wallet.id,
                      child: Text(wallet.name, overflow: TextOverflow.ellipsis),
                    )).toList(),
                    onChanged: (value) => setState(() => _globalWalletId = value),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: categories.contains(_globalCategory) ? _globalCategory : null,
                    decoration: InputDecoration(
                      labelText: 'Category',
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    items: categories.map((category) => DropdownMenuItem(
                      value: category,
                      child: Text(category, overflow: TextOverflow.ellipsis),
                    )).toList(),
                    onChanged: (value) => setState(() => _globalCategory = value),
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
      Text('Receipt items', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: 4),
      Text(
        'Selected items are saved atomically (either all are added or none are).',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 12),
      for (var index = 0; index < _rows.length; index++)
        _buildItemRow(index),
      OutlinedButton.icon(
        onPressed: () {
          setState(() {
            _rows.add(
              _ReceiptRow(
                title: TextEditingController(),
                amount: TextEditingController(),
              ),
            );
          });
        },
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add manual item'),
      ),
      const SizedBox(height: 16),
      Card(
        elevation: 0,
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _totalLine('Detected receipt total', widget.receipt.total),
              _totalLine('Sum of selected items', _selectedTotal),
              const Divider(height: 16),
              _totalLine('Difference', _difference, signed: true),
              if (_hasSuspiciousDifference) ...[
                const SizedBox(height: 12),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _confirmDiscrepancy,
                  title: const Text('Save despite this difference', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                  subtitle: const Text(
                    'The items you selected do not match the total detected on the receipt.',
                  ),
                  onChanged: (value) => setState(
                        () => _confirmDiscrepancy = value ?? false,
                  ),
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
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.15)),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: const Offset(0, 2)),
          ]
      ),
      child: Row(
        children: [
          Checkbox(
            value: row.included,
            onChanged: (value) => setState(() => row.included = value ?? false),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
          Expanded(
            child: Column(
              children: [
                TextField(
                  controller: row.title,
                  enabled: row.included,
                  decoration: const InputDecoration(
                    labelText: 'Item Name',
                    isDense: true,
                    border: InputBorder.none,
                    filled: true,
                    fillColor: Colors.transparent,
                  ),
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                ),
                Divider(height: 1, color: Theme.of(context).dividerColor.withOpacity(0.1)),
                TextField(
                  controller: row.amount,
                  enabled: row.included,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Amount (Rs)',
                    isDense: true,
                    border: InputBorder.none,
                    filled: true,
                    fillColor: Colors.transparent,
                  ),
                  style: TextStyle(fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary),
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Remove item',
            onPressed: () {
              setState(() {
                final removed = _rows.removeAt(index);
                removed.dispose();
              });
            },
            icon: const Icon(Icons.close_rounded, color: Colors.grey),
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
          labelText: 'Receipt Description',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _totalController,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: 'Receipt Total (Rs)',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 12),
      const Text(
        'Single-total mode creates one expense only; individual items are ignored.',
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
          Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w500))),
          Text('Rs $prefix${value.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (_globalWalletId == null || _globalCategory == null) {
      _showError('Choose a wallet and category at the top first.');
      return;
    }

    final wallets = ref.read(walletProvider);
    final selectedWallet = wallets.firstWhere((w) => w.id == _globalWalletId, orElse: () => wallets.first);
    final currentBalance = ref.read(walletProvider.notifier).getBalanceForWallet(selectedWallet.id);

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
          title: _totalTitleController.text.trim().isEmpty ? 'Receipt purchase' : _totalTitleController.text.trim(),
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
        if (row.title.text.trim().isEmpty || amount == null || !amount.isFinite || amount <= 0) {
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
            category: _globalCategory!,
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
      _showError('Insufficient balance in ${selectedWallet.name}. Need Rs. ${totalDeduction.toStringAsFixed(0)}, but you only have Rs. ${currentBalance.toStringAsFixed(0)}.');
      return;
    }

    setState(() => _saving = true);

    try {
      final executor = ref.read(transactionExecutorProvider);
      TransactionResult result;

      if (_mode == _ReceiptSaveMode.total) {
        result = await executor.execute(CreateTransactionCommand(entries.first));
      } else {
        result = await executor.execute(
          CreateBatchTransactionsCommand(
            entries: entries,
            detectedTotal: widget.receipt.total,
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
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
      ));
  }
}

class _ReceiptRow {
  final TextEditingController title;
  final TextEditingController amount;
  bool included = true;

  _ReceiptRow({
    required this.title,
    required this.amount,
  });

  void dispose() {
    title.dispose();
    amount.dispose();
  }
}