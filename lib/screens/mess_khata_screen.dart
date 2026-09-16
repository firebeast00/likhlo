import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../models/mess_entry_model.dart';
import '../models/expense_model.dart';
import '../providers/mess_provider.dart';
import '../providers/expense_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/wallet_provider.dart';
import '../services/local_nlp_service.dart';
import '../services/ocr_scanner_service.dart';

class MessKhataScreen extends ConsumerStatefulWidget {
  const MessKhataScreen({super.key});

  @override
  ConsumerState<MessKhataScreen> createState() => _MessKhataScreenState();
}

class _MessKhataScreenState extends ConsumerState<MessKhataScreen> {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  final TextEditingController _smartInputCtrl = TextEditingController();

  @override
  void dispose() {
    _smartInputCtrl.dispose();
    super.dispose();
  }

  void _listenForInput() async {
    if (!_isListening) {
      bool available = await _speech.initialize(
        onStatus: (val) {
          if (!mounted) return;
          if (val == 'done' || val == 'notListening') {
            setState(() => _isListening = false);
            if (_smartInputCtrl.text.isNotEmpty && _smartInputCtrl.text != "Listening...") {
              _processNLP(_smartInputCtrl.text);
            }
          }
        },
        onError: (val) {
          if (mounted) setState(() => _isListening = false);
        },
      );

      if (!mounted) return;

      if (available) {
        setState(() => _isListening = true);
        _smartInputCtrl.text = "Listening...";
        _speech.listen(
          onResult: (val) {
            if (!mounted) return;
            setState(() => _smartInputCtrl.text = val.recognizedWords);
          },
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Speech recognition unavailable.")));
      }
    } else {
      setState(() => _isListening = false);
      _speech.stop();
    }
  }

  void _processNLP(String text) {
    if (text.isEmpty || text == "Listening...") return;
    final result = LocalNlpService().parseExpense(text, ["Hostel/Mess", "Groceries", "Food"]);

    if (result['amount'] > 0) {
      _showAddDialog(context, ref, initialTitle: result['title'], initialAmount: result['amount'].toString());
      _smartInputCtrl.clear();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("❌ Could not detect amount. Try: '800 for Mess Lunch'"), backgroundColor: Colors.red),
      );
    }
    FocusScope.of(context).unfocus();
  }

  void _startReceiptScan() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(16)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Theme.of(context).primaryColor),
              const SizedBox(height: 16),
              const Text("Scanning Receipt...", style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );

    final receiptData = await OcrScannerService().scanReceipt();
    if (!mounted) return;
    Navigator.pop(context);

    if (receiptData != null && receiptData['amount'] > 0) {
      _showAddDialog(context, ref, initialTitle: receiptData['title'], initialAmount: receiptData['amount'].toString());
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("❌ Could not read receipt clearly."), backgroundColor: Colors.red),
      );
    }
  }

  // --- SETTLEMENT BREAKDOWN SHEET ---
  // --- SETTLEMENT BREAKDOWN SHEET ---
  void _showSettlementSheet(BuildContext context, List<MessEntry> entries) {
    // Calculate who paid what
    final Map<String, double> paidMap = {};
    double grandTotal = 0;

    for (var e in entries) {
      grandTotal += e.totalAmount;
      paidMap[e.paidBy] = (paidMap[e.paidBy] ?? 0) + e.totalAmount;
    }

    final activePayers = paidMap.keys.toList();
    final fairShare = activePayers.isNotEmpty ? grandTotal / (activePayers.length + 1) : 0.0;

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 20),
            const Text("Settlement Matrix", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            const Text("AI breakdown of shared hostel liability", style: TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.teal.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(16)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // 🚀 FIX: Wrapped in Expanded to prevent text overflow
                  const Expanded(
                    child: Text("Estimated Fair Share / Person", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  ),
                  const SizedBox(width: 8),
                  Text("Rs. ${fairShare.toStringAsFixed(0)}", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.teal)),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text("Individual Contributions", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 10),
            if (paidMap.isEmpty)
              const Text("No entries recorded yet to compute settlement.", style: TextStyle(color: Colors.grey, fontSize: 12))
            else
              ...paidMap.entries.map((entry) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // 🚀 FIX: Wrapped in Expanded with ellipsis
                    Expanded(
                      child: Text(entry.key, style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 8),
                    Text("Paid Rs. ${entry.value.toStringAsFixed(0)}", style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
              )),
          ],
        ),
      ),
    );
  }

  void _showAddDialog(BuildContext context, WidgetRef ref, {String initialTitle = "", String initialAmount = ""}) {
    final titleCtrl = TextEditingController(text: initialTitle);
    final amountCtrl = TextEditingController(text: initialAmount);
    final payerCtrl = TextEditingController(text: "Me");
    final countCtrl = TextEditingController(text: "2");

    final settings = ref.read(settingsProvider);
    final primaryColor = Color(settings.profileColorValue);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          backgroundColor: Theme.of(context).cardColor,
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: primaryColor.withValues(alpha: 0.15), shape: BoxShape.circle),
                child: Icon(Icons.group_rounded, color: primaryColor),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  "Add Split Expense",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: MediaQuery.of(context).size.width * 0.85,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  _buildDialogInput(titleCtrl, "Expense Title (e.g. Mess Lunch)", Icons.title_rounded, context, primaryColor),
                  const SizedBox(height: 14),
                  _buildDialogInput(amountCtrl, "Total Amount (Rs.)", Icons.attach_money_rounded, context, primaryColor, isNumber: true),
                  const SizedBox(height: 14),

                  // Quick Payer Selection Chips
                  const Text("Paid By:", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: ["Me", "Roommate", "Hostel Mess"].map((payer) {
                      final isSelected = payerCtrl.text == payer;
                      return ChoiceChip(
                        label: Text(payer, style: TextStyle(fontSize: 12, color: isSelected ? Colors.white : null)),
                        selected: isSelected,
                        selectedColor: primaryColor,
                        onSelected: (_) => setDialogState(() => payerCtrl.text = payer),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                  _buildDialogInput(countCtrl, "Split Among (People)", Icons.people_outline_rounded, context, primaryColor, isNumber: true),
                ],
              ),
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          actions: [
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text("Cancel", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () async {
                      final amt = double.tryParse(amountCtrl.text);
                      final count = int.tryParse(countCtrl.text);
                      if (titleCtrl.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Enter an expense title.')),
                        );
                        return;
                      }
                      if (amt == null || !amt.isFinite || amt <= 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Enter a valid amount above zero. Negative amounts are not allowed.'),
                          ),
                        );
                        return;
                      }
                      if (count == null || count <= 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Split count must be at least 1.')),
                        );
                        return;
                      }

                      final wallets = ref.read(walletProvider);
                      if (wallets.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Create a wallet before adding an expense.')),
                        );
                        return;
                      }
                      final sourceWallet = wallets.firstWhere(
                        (wallet) =>
                            !wallet.isBackup &&
                            (wallet.walletType == 'cash' ||
                                wallet.name.toLowerCase().contains('cash')),
                        orElse: () => wallets.firstWhere(
                          (wallet) => !wallet.isBackup,
                          orElse: () => wallets.first,
                        ),
                      );
                      final available = ref
                          .read(walletProvider.notifier)
                          .getBalanceForWallet(sourceWallet.id);
                      if (amt > available) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Not enough money in ${sourceWallet.name}. Available: Rs. ${available.toStringAsFixed(0)}; required: Rs. ${amt.toStringAsFixed(0)}. Add money or enter a smaller amount.',
                            ),
                          ),
                        );
                        return;
                      }

                      if (titleCtrl.text.isNotEmpty && amt > 0 && count > 0) {
                        final expenseId = const Uuid().v4();

                        final messEntry = MessEntry(
                          id: expenseId,
                          title: titleCtrl.text.trim(),
                          totalAmount: amt,
                          paidBy: payerCtrl.text.trim(),
                          splitCount: count,
                          date: DateTime.now(),
                        );
                        final messSaved =
                            await ref.read(messProvider.notifier).addEntry(messEntry);
                        if (!messSaved) {
                          if (!ctx.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Could not save the Mess Khata record.')),
                          );
                          return;
                        }
                        final linkedSaved = await ref
                            .read(expenseProvider.notifier)
                            .addExpense(
                              Expense(
                                id: expenseId,
                                title: "Mess: ${titleCtrl.text.trim()} (${payerCtrl.text.trim()})",
                                amount: amt,
                                category: "Hostel/Mess",
                                date: DateTime.now(),
                                colorValue: primaryColor.toARGB32(),
                                walletId: sourceWallet.id,
                              ),
                            );
                        if (!linkedSaved) {
                          await ref
                              .read(messProvider.notifier)
                              .deleteEntry(expenseId);
                          if (!ctx.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Could not save the linked expense.')),
                          );
                          return;
                        }

                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                      }
                    },
                    child: const Text("Save & Sync", style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildDialogInput(TextEditingController ctrl, String label, IconData icon, BuildContext context, Color primaryColor, {bool isNumber = false}) {
    return TextField(
      controller: ctrl,
      keyboardType: isNumber
          ? const TextInputType.numberWithOptions(decimal: true, signed: false)
          : TextInputType.text,
      inputFormatters: isNumber
          ? [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))]
          : null,
      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey.shade500, fontSize: 13),
        prefixIcon: Icon(icon, color: Colors.grey, size: 20),
        filled: true,
        fillColor: Theme.of(context).brightness == Brightness.dark ? Colors.black26 : Colors.grey.shade50,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: primaryColor, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = ref.watch(messProvider);
    final settings = ref.watch(settingsProvider);
    final primaryColor = Color(settings.profileColorValue);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    double totalMessSpend =
        entries.fold(0.0, (sum, e) => sum + e.totalAmount);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Hostel & Mess Khata", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
              IconButton(
                icon: const Icon(Icons.analytics_outlined),
                tooltip: "Settlement Breakdown",
                onPressed: () => _showSettlementSheet(context, entries),
              )
            ],
          ),
          const SizedBox(height: 16),

          // 1. Hero Summary Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [primaryColor, primaryColor.withValues(alpha: 0.75)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(32),
              boxShadow: [
                BoxShadow(color: primaryColor.withValues(alpha: isDark ? 0.3 : 0.4), blurRadius: 20, offset: const Offset(0, 10))
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Total Shared Pool", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, fontSize: 14)),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle),
                      child: const Icon(Icons.account_balance_wallet_rounded, color: Colors.white, size: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text("Rs. ${totalMessSpend.toStringAsFixed(0)}", style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -1.0)),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                  child: const Text("🔗 Automatically synced with monthly budget", style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 2. Smart Voice & OCR Input Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: isDark ? primaryColor.withValues(alpha: 0.3) : Colors.grey.withValues(alpha: 0.12), width: 1.2),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4))]
            ),
            child: Row(
              children: [
                IconButton(
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(10),
                  icon: Icon(_isListening ? Icons.mic : Icons.mic_none_rounded, color: _isListening ? Colors.red : primaryColor, size: 22),
                  onPressed: _listenForInput,
                ),
                Expanded(
                  child: TextField(
                    controller: _smartInputCtrl,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: _isListening ? 'Listening...' : 'Speak/Type: "1200 for Dinner"',
                      border: InputBorder.none,
                      hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    ),
                    onSubmitted: (val) => _processNLP(val),
                  ),
                ),
                IconButton(
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(10),
                  icon: const Icon(Icons.document_scanner_rounded, color: Colors.blueAccent, size: 20),
                  onPressed: _startReceiptScan,
                  tooltip: "Scan Receipt",
                ),
                IconButton(
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(10),
                  icon: Icon(Icons.send_rounded, color: primaryColor, size: 20),
                  onPressed: () => _processNLP(_smartInputCtrl.text),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // 3. Entries List Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Split History", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: -0.5)),
              Text("${entries.length} records", style: TextStyle(color: Colors.grey.shade500, fontSize: 13, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 12),

          // 4. Entries List Items
          if (entries.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 50),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.receipt_long_rounded, size: 60, color: Colors.grey.withValues(alpha: 0.3)),
                    const SizedBox(height: 12),
                    const Text("No shared expenses logged yet.", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            )
          else
            ...entries.map((item) {
              final perPerson = item.totalAmount / item.splitCount;
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: isDark ? primaryColor.withValues(alpha: 0.2) : Colors.grey.withValues(alpha: 0.1), width: 1.2),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4))]
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: primaryColor.withValues(alpha: 0.15), shape: BoxShape.circle),
                      child: Icon(Icons.group_rounded, color: primaryColor, size: 20),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "Paid by ${item.paidBy} • ${item.splitCount} people (Rs. ${perPerson.toStringAsFixed(0)}/ea)",
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontWeight: FontWeight.w500),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          "Rs. ${item.totalAmount.toStringAsFixed(0)}",
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                        ),
                        const SizedBox(height: 4),
                        InkWell(
                          borderRadius: BorderRadius.circular(6),
                          onTap: () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (dialogContext) => AlertDialog(
                                title: const Text('Delete Mess Khata record?'),
                                content: Text(
                                  "Delete '${item.title}'? This will also remove the linked expense from your records.",
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
                            );
                            if (confirmed != true || !mounted) return;
                            await ref.read(messProvider.notifier).deleteEntry(item.id);
                            await ref.read(expenseProvider.notifier).deleteExpense(item.id);
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Deleted split expense and updated records'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(2.0),
                            child: Icon(Icons.delete_outline_rounded, color: Colors.red.shade400, size: 18),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }).toList(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddDialog(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: const Text("Add Split Bill"),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 6,
      ),
    );
  }
}
