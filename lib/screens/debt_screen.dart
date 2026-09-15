import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../models/debt_model.dart';
import '../services/notification_service.dart';
import '../services/local_nlp_service.dart';
import '../services/ocr_scanner_service.dart';
import '../providers/settings_provider.dart';
import '../models/expense_model.dart';
import '../providers/expense_provider.dart';
import '../providers/wallet_provider.dart';

class DebtScreen extends ConsumerStatefulWidget {
  const DebtScreen({super.key});

  @override
  ConsumerState<DebtScreen> createState() => _DebtScreenState();
}

class _DebtScreenState extends ConsumerState<DebtScreen> {
  final Box<DebtEntry> debtBox = Hive.box<DebtEntry>('debts');


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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Speech recognition unavailable.", style: TextStyle(fontSize: 13))));
      }
    } else {
      setState(() => _isListening = false);
      _speech.stop();
    }
  }

  void _processNLP(String text) {
    if (text.isEmpty || text == "Listening...") return;

    // Smart Type Detection
    final lower = text.toLowerCase();
    String detectedType = 'lent'; // Default to "I Gave"
    if (lower.contains('borrow') || lower.contains('took') || lower.contains('from')) {
      detectedType = 'borrowed';
    }

    final result = LocalNlpService().parseExpense(text, ["Udhaar", "Debt"]);

    if (result['amount'] > 0) {
      // Clean up the name by removing transaction verbs
      String cleanName = result['title'].replaceAll(RegExp(r'(borrowed|lent|took|gave|from|to)', caseSensitive: false), '').trim();
      if (cleanName.isEmpty) cleanName = "Friend";

      _showAddDialog(initialName: cleanName, initialAmount: result['amount'].toString(), initialType: detectedType);
      _smartInputCtrl.clear();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("❌ Could not detect amount. Try: 'Lent 500 to Ali'", style: TextStyle(fontSize: 13)), backgroundColor: Colors.red),
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
          decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(20)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Theme.of(context).primaryColor),
              const SizedBox(height: 16),
              const Text("Scanning Receipt...", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            ],
          ),
        ),
      ),
    );

    final receiptData = await OcrScannerService().scanReceipt();
    if (!mounted) return;
    Navigator.pop(context);

    if (receiptData != null && receiptData['amount'] > 0) {
      _showAddDialog(initialName: receiptData['title'], initialAmount: receiptData['amount'].toString());
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("❌ Could not read amount clearly.", style: TextStyle(fontSize: 13)), backgroundColor: Colors.red),
      );
    }
  }

  void _showAddDialog({String initialName = "", String initialAmount = "", String initialType = 'lent'}) {
    final nameCtrl = TextEditingController(text: initialName);
    final amountCtrl = TextEditingController(text: initialAmount);
    String type = initialType;
    DateTime? selectedDate;
    final wallets = ref.read(walletProvider);
    String selectedWalletId = wallets.isEmpty
        ? ''
        : wallets.firstWhere(
            (wallet) => !wallet.isBackup,
            orElse: () => wallets.first,
          ).id;

    final settings = ref.read(settingsProvider);
    final primaryColor = Color(settings.profileColorValue);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              backgroundColor: Theme.of(context).cardColor,
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: primaryColor.withValues(alpha: 0.15), shape: BoxShape.circle),
                    child: Icon(Icons.handshake_rounded, color: primaryColor, size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text("Udhaar Record", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              content: SizedBox(
                width: MediaQuery.of(context).size.width * 0.9,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 🌟 Sleek Segmented Control for Type
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.black26 : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setModalState(() => type = 'lent'),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  decoration: BoxDecoration(
                                    color: type == 'lent' ? Colors.green : Colors.transparent,
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: type == 'lent' ? [BoxShadow(color: Colors.green.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 2))] : [],
                                  ),
                                  child: Center(
                                    child: Text("I Gave (Lent)", style: TextStyle(color: type == 'lent' ? Colors.white : Colors.grey.shade500, fontWeight: FontWeight.bold, fontSize: 13)),
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setModalState(() => type = 'borrowed'),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  decoration: BoxDecoration(
                                    color: type == 'borrowed' ? Colors.red : Colors.transparent,
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: type == 'borrowed' ? [BoxShadow(color: Colors.red.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 2))] : [],
                                  ),
                                  child: Center(
                                    child: Text("I Took (Borrowed)", style: TextStyle(color: type == 'borrowed' ? Colors.white : Colors.grey.shade500, fontWeight: FontWeight.bold, fontSize: 13)),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildModernInput(nameCtrl, "Person Name", Icons.person_rounded, primaryColor, isDark),
                      const SizedBox(height: 12),
                      _buildModernInput(amountCtrl, "Amount (Rs.)", Icons.attach_money_rounded, primaryColor, isDark, isNumber: true),
                      if (type == 'lent') ...[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: wallets.any((wallet) => wallet.id == selectedWalletId)
                              ? selectedWalletId
                              : null,
                          decoration: InputDecoration(
                            labelText: 'Money sent from',
                            prefixIcon: Icon(Icons.account_balance_wallet_rounded, color: primaryColor),
                            filled: true,
                            fillColor: isDark ? Colors.black26 : Colors.grey.shade50,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          items: wallets.map((wallet) {
                            final balance = ref
                                .read(walletProvider.notifier)
                                .getBalanceForWallet(wallet.id);
                            return DropdownMenuItem<String>(
                              value: wallet.id,
                              child: Text(
                                '${wallet.name} — Rs. ${balance.toStringAsFixed(0)}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }).toList(),
                          onChanged: wallets.isEmpty
                              ? null
                              : (value) => setModalState(
                                    () => selectedWalletId = value ?? '',
                                  ),
                        ),
                      ],
                      const SizedBox(height: 12),

                      // DATE PICKER
                      GestureDetector(
                        onTap: () async {
                          final date = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime.now(), lastDate: DateTime(2030));
                          if (date != null) setModalState(() => selectedDate = date);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.black26 : Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.calendar_today_rounded, color: Colors.grey.shade500, size: 20),
                              const SizedBox(width: 12),
                              Text(
                                  selectedDate == null ? "Set Due Date (Optional)" : "Due: ${DateFormat.yMMMd().format(selectedDate!)}",
                                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: selectedDate == null ? Colors.grey.shade500 : (isDark ? Colors.white : Colors.black87))
                              ),
                              const Spacer(),
                              Icon(Icons.edit_calendar_rounded, size: 18, color: Colors.grey.shade400),
                            ],
                          ),
                        ),
                      ),
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
                        style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
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
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () async {
                          final amt = double.tryParse(amountCtrl.text) ?? 0;
                          if (nameCtrl.text.isNotEmpty && amt > 0) {
                            if (type == 'lent') {
                              if (selectedWalletId.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Create a money account before lending money.')),
                                );
                                return;
                              }
                              final available = ref
                                  .read(walletProvider.notifier)
                                  .getBalanceForWallet(selectedWalletId);
                              if (amt > available) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Insufficient account balance. Available: Rs. ${available.toStringAsFixed(0)}',
                                    ),
                                  ),
                                );
                                return;
                              }
                            }
                            final debtId = const Uuid().v4(); // Generate shared ID

                            final newDebt = DebtEntry(
                              id: debtId,
                              borrowerName: nameCtrl.text.trim(),
                              amount: amt,
                              type: type,
                              dueDate: selectedDate,
                            );

                            int key = await debtBox.add(newDebt);

                            // 🔗 FIX: Cross-sync "I Gave" (Lent) to deduct from Main Budget
                            if (type == 'lent') {
                              ref.read(expenseProvider.notifier).addExpense(
                                  Expense(
                                    id: debtId, // Link IDs so deletion syncs later
                                    title: "Udhaar: ${nameCtrl.text.trim()}",
                                    amount: amt,
                                    category: "Udhaar",
                                    date: DateTime.now(),
                                    colorValue: Colors.red.toARGB32(),
                                    walletId: selectedWalletId,
                                  )
                              );
                            }

                            if (selectedDate != null && selectedDate!.isAfter(DateTime.now())) {
                              NotificationService().scheduleNotification(
                                  key,
                                  "Udhaar Due Today! 💰",
                                  "${type == 'lent' ? 'Collect' : 'Pay'} Rs. ${amt.toStringAsFixed(0)} ${type == 'lent' ? 'from' : 'to'} ${nameCtrl.text}",
                                  selectedDate!
                              );
                            }

                            if (!ctx.mounted) return;
                            setState(() {});
                            Navigator.pop(ctx);
                          }
                        },
                        child: const Text("Save Record", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      ),
                    )
                  ],
                )
              ],
            );
          }
      ),
    );
  }

  Widget _buildModernInput(TextEditingController ctrl, String label, IconData icon, Color primaryColor, bool isDark, {bool isNumber = false}) {
    return TextField(
      controller: ctrl,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      textCapitalization: isNumber ? TextCapitalization.none : TextCapitalization.words,
      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey.shade500, fontSize: 13),
        prefixIcon: Icon(icon, color: Colors.grey.shade500, size: 20),
        filled: true,
        fillColor: isDark ? Colors.black26 : Colors.grey.shade50,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: primaryColor, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final debts = debtBox.values.toList();
    final settings = ref.watch(settingsProvider);
    final primaryColor = Color(settings.profileColorValue);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    double iGave = debts
        .where((e) => e.type == 'lent')
        .fold(0.0, (sum, e) => sum + e.amount);
    double iTook = debts
        .where((e) => e.type == 'borrowed')
        .fold(0.0, (sum, e) => sum + e.amount);
    double balance = iGave - iTook;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          // 1. 🌟 SUMMARY HERO CARD
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(20, 16, 20, 10),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [primaryColor, primaryColor.withValues(alpha: 0.75)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(color: primaryColor.withValues(alpha: isDark ? 0.25 : 0.35), blurRadius: 18, offset: const Offset(0, 8))
                ]
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Net Balance", style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontWeight: FontWeight.w500, fontSize: 13)),
                    Icon(balance >= 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded, color: Colors.white.withValues(alpha: 0.8), size: 20),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(balance < 0 ? "-" : "", style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                    Text("Rs. ${balance.abs().toStringAsFixed(0)}", style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                  ],
                ),
                Text(balance >= 0 ? "Overall you will receive" : "Overall you owe", style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.7))),

                const SizedBox(height: 24),

                Row(
                  children: [
                    Expanded(child: _summaryBox("I Gave", iGave, Colors.greenAccent)),
                    const SizedBox(width: 12),
                    Expanded(child: _summaryBox("I Took", iTook, Colors.redAccent.shade100)),
                  ],
                )
              ],
            ),
          ),

          // 2. 🎙️ SMART VOICE & OCR INPUT BAR
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: isDark ? primaryColor.withValues(alpha: 0.4) : Colors.grey.withValues(alpha: 0.2), width: 1.2),
              ),
              child: Row(
                children: [
                  IconButton(
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    padding: EdgeInsets.zero,
                    icon: Icon(_isListening ? Icons.mic : Icons.mic_none_rounded, color: _isListening ? Colors.red : primaryColor, size: 20),
                    onPressed: _listenForInput,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _smartInputCtrl,
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: _isListening ? 'Listening...' : 'Speak: "Borrowed 500 from Sara"',
                        border: InputBorder.none,
                        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                      ),
                      onSubmitted: (val) => _processNLP(val),
                    ),
                  ),
                  IconButton(
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.document_scanner_rounded, color: Colors.blueAccent, size: 18),
                    onPressed: _startReceiptScan,
                    tooltip: "Scan Receipt",
                  ),
                  IconButton(
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    padding: EdgeInsets.zero,
                    icon: Icon(Icons.send_rounded, color: primaryColor, size: 18),
                    onPressed: () => _processNLP(_smartInputCtrl.text),
                  ),
                ],
              ),
            ),
          ),

          // 3. 📋 UDHAAR LIST
          Expanded(
            child: debts.isEmpty
                ? Center(
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.handshake_rounded, size: 60, color: Colors.grey.withValues(alpha: 0.3)),
                      const SizedBox(height: 12),
                      Text("No active records. You're all settled!", style: TextStyle(color: Colors.grey.shade500, fontSize: 13))
                    ]
                )
            )
                : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              itemCount: debts.length,
              itemBuilder: (ctx, i) {
                final item = debts[i];
                final isLent = item.type == 'lent';

                return Dismissible(
                  key: Key(item.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(color: Colors.green, borderRadius: BorderRadius.circular(16)),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Icon(Icons.check_circle_rounded, color: Colors.white),
                        SizedBox(width: 8),
                        Text("Mark Settled", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
                      ],
                    ),
                  ),
                  onDismissed: (_) {
                    // 1. Delete from Udhaar tab
                    item.delete();

                    // 2. Delete from Main Expenses to restore the budget
                    try {
                      ref.read(expenseProvider.notifier).deleteExpense(item.id);
                    } catch (_) {} // Catch in case it was a "borrowed" record that wasn't synced

                    setState((){});
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text("Settled Udhaar with ${item.borrowerName} 🤝", style: const TextStyle(fontSize: 13)), backgroundColor: Colors.green)
                    );
                  },
                  child: Card(
                    elevation: 0,
                    color: Theme.of(context).cardColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: isDark ? primaryColor.withValues(alpha: 0.2) : Colors.grey.withValues(alpha: 0.12), width: 1.2),
                    ),
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(color: isLent ? Colors.green.withValues(alpha: 0.15) : Colors.red.withValues(alpha: 0.15), shape: BoxShape.circle),
                            child: Icon(isLent ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, color: isLent ? Colors.green : Colors.red, size: 20),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  item.borrowerName,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Icon(item.dueDate != null ? Icons.calendar_month_rounded : Icons.info_outline_rounded, size: 11, color: Colors.grey.shade500),
                                    const SizedBox(width: 4),
                                    Text(
                                      item.dueDate != null ? "Due: ${DateFormat.MMMEd().format(item.dueDate!)}" : (isLent ? "You gave them" : "They gave you"),
                                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    )
                                  ],
                                )
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                              "Rs. ${item.amount.toStringAsFixed(0)}",
                              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: isLent ? Colors.green : Colors.red)
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add_rounded),
        label: const Text("Add Record"),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 4,
        onPressed: _showAddDialog,
      ),
    );
  }

  Widget _summaryBox(String title, double amount, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(16)
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 11, fontWeight: FontWeight.w500)),
          const SizedBox(height: 2),
          Text(amount.toStringAsFixed(0), style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
