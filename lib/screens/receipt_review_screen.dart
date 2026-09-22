import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/expense_model.dart';
import '../models/wallet_model.dart';
import '../providers/category_provider.dart';
import '../providers/wallet_provider.dart';
import '../providers/workspace_provider.dart';
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
  String? _walletId;
  String? _category;
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
    _walletId ??= wallets.isEmpty ? null : wallets.first.id;
    _category ??= categories.contains(widget.receipt.category)
        ? widget.receipt.category
        : (categories.isEmpty ? 'General' : categories.first);
    for (final row in _rows) {
      row.walletId ??= _walletId;
      row.category ??= _category;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Review receipt')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
          children: [
            _buildConfidenceCard(),
            const SizedBox(height: 16),
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
            const SizedBox(height: 16),
            if (_mode == _ReceiptSaveMode.total) ...[
              DropdownButtonFormField<String>(
                initialValue: wallets.any((wallet) => wallet.id == _walletId)
                    ? _walletId
                    : null,
                decoration: const InputDecoration(
                  labelText: 'Wallet',
                  border: OutlineInputBorder(),
                ),
                items: wallets
                    .map(
                      (wallet) => DropdownMenuItem(
                        value: wallet.id,
                        child: Text(wallet.name),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _walletId = value),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue:
                    categories.contains(_category) ? _category : null,
                decoration: const InputDecoration(
                  labelText: 'Category',
                  border: OutlineInputBorder(),
                ),
                items: categories
                    .map(
                      (category) => DropdownMenuItem(
                        value: category,
                        child: Text(category),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _category = value),
              ),
              const SizedBox(height: 20),
            ],
            if (_mode == _ReceiptSaveMode.items)
              ..._buildItemEditor(wallets, categories)
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
          label: Text(_saving ? 'Saving…' : 'Save reviewed receipt'),
        ),
      ),
    );
  }

  Widget _buildConfidenceCard() {
    final percent = (widget.receipt.confidence * 100).round();
    final low = widget.receipt.confidence < 0.7;
    return Card(
      color: low
          ? Theme.of(context).colorScheme.errorContainer
          : Theme.of(context).colorScheme.secondaryContainer,
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

  List<Widget> _buildItemEditor(
    List<Wallet> wallets,
    List<String> categories,
  ) {
    return [
      Text('Receipt items', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 4),
      Text(
        'Selected items are saved atomically—either every item is added or none are.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 12),
      for (var index = 0; index < _rows.length; index++)
        _buildItemRow(index, wallets, categories),
      OutlinedButton.icon(
        onPressed: () {
          setState(() {
            _rows.add(
              _ReceiptRow(
                title: TextEditingController(),
                amount: TextEditingController(),
                walletId: _walletId,
                category: _category,
              ),
            );
          });
        },
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add item'),
      ),
      const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              _totalLine('Detected total', widget.receipt.total),
              _totalLine('Selected items', _selectedTotal),
              _totalLine('Difference', _difference, signed: true),
              if (_hasSuspiciousDifference) ...[
                const Divider(),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _confirmDiscrepancy,
                  title: const Text('Save despite this difference'),
                  subtitle: const Text(
                    'The selected items differ materially from the detected receipt total.',
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

  Widget _buildItemRow(
    int index,
    List<Wallet> wallets,
    List<String> categories,
  ) {
    final row = _rows[index];
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: row.included,
              onChanged: (value) => setState(
                () => row.included = value ?? false,
              ),
            ),
            Expanded(
              child: Column(
                children: [
                  TextField(
                    controller: row.title,
                    enabled: row.included,
                    decoration: const InputDecoration(labelText: 'Item'),
                  ),
                  TextField(
                    controller: row.amount,
                    enabled: row.included,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Amount'),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: wallets.any(
                            (wallet) => wallet.id == row.walletId,
                          )
                              ? row.walletId
                              : null,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Wallet',
                            isDense: true,
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
                          onChanged: row.included
                              ? (value) =>
                                  setState(() => row.walletId = value)
                              : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: categories.contains(row.category)
                              ? row.category
                              : null,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Category',
                            isDense: true,
                          ),
                          items: categories
                              .map(
                                (category) => DropdownMenuItem(
                                  value: category,
                                  child: Text(
                                    category,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: row.included
                              ? (value) =>
                                  setState(() => row.category = value)
                              : null,
                        ),
                      ),
                    ],
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
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildTotalEditor() {
    return [
      TextField(
        controller: _totalTitleController,
        decoration: const InputDecoration(
          labelText: 'Description',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _totalController,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(
          labelText: 'Receipt total',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 8),
      const Text(
        'Single-total mode creates one expense only; individual items are not also saved.',
      ),
    ];
  }

  Widget _totalLine(String label, double value, {bool signed = false}) {
    final prefix = signed && value > 0 ? '+' : '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text('Rs $prefix${value.toStringAsFixed(2)}'),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final walletId = _walletId;
    final category = _category;
    if (walletId == null || category == null) {
      _showError('Choose a wallet and category first.');
      return;
    }

    setState(() => _saving = true);
    try {
      final executor = ref.read(transactionExecutorProvider);
      final workspaceId = ref.read(selectedWorkspaceIdProvider);
      TransactionResult result;
      if (_mode == _ReceiptSaveMode.total) {
        final amount = double.tryParse(_totalController.text.trim());
        if (amount == null || !amount.isFinite || amount <= 0) {
          _showError('Enter a valid receipt total.');
          return;
        }
        result = await executor.execute(
          CreateTransactionCommand(
            Expense(
              id: const Uuid().v4(),
              title: _totalTitleController.text.trim(),
              amount: amount,
              date: DateTime.now(),
              category: category,
              colorValue: 0xFFEF4444,
              walletId: walletId,
              workspaceId: workspaceId,
            ),
          ),
        );
      } else {
        final entries = <Expense>[];
        for (final row in _rows.where((row) => row.included)) {
          final amount = double.tryParse(row.amount.text.trim());
          if (row.title.text.trim().isEmpty ||
              amount == null ||
              !amount.isFinite ||
              amount <= 0 ||
              row.walletId == null ||
              row.category == null) {
            _showError(
              'Every selected item needs a name, amount, wallet, and category.',
            );
            return;
          }
          entries.add(
            Expense(
              id: const Uuid().v4(),
              title: row.title.text.trim(),
              amount: amount,
              date: DateTime.now(),
              category: row.category!,
              colorValue: 0xFFEF4444,
              walletId: row.walletId!,
              workspaceId: workspaceId,
            ),
          );
        }
        if (entries.isEmpty) {
          _showError('Select at least one receipt item.');
          return;
        }
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
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _ReceiptRow {
  final TextEditingController title;
  final TextEditingController amount;
  bool included = true;
  String? walletId;
  String? category;

  _ReceiptRow({
    required this.title,
    required this.amount,
    this.walletId,
    this.category,
  });

  void dispose() {
    title.dispose();
    amount.dispose();
  }
}
