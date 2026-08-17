import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../models/recurring_bill_model.dart';
import '../providers/recurring_provider.dart';
import '../providers/settings_provider.dart';
import '../services/local_nlp_service.dart';
import '../services/ocr_scanner_service.dart';

class RecurringBillsScreen extends ConsumerStatefulWidget {
  const RecurringBillsScreen({super.key});

  @override
  ConsumerState<RecurringBillsScreen> createState() => _RecurringBillsScreenState();
}

class _RecurringBillsScreenState extends ConsumerState<RecurringBillsScreen> {
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
          if (val == 'done' || val == 'notListening') {
            setState(() => _isListening = false);
            if (_smartInputCtrl.text.isNotEmpty && _smartInputCtrl.text != "Listening...") {
              _processNLP(_smartInputCtrl.text);
            }
          }
        },
        onError: (val) => setState(() => _isListening = false),
      );

      if (available) {
        setState(() => _isListening = true);
        _smartInputCtrl.text = "Listening...";
        _speech.listen(
          onResult: (val) => setState(() {
            _smartInputCtrl.text = val.recognizedWords;
          }),
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
    final result = LocalNlpService().parseExpense(text, ["Subscription", "Bills"]);

    if (result['amount'] > 0) {
      _showAddDialog(context, ref, initialTitle: result['title'], initialAmount: result['amount'].toString());
      _smartInputCtrl.clear();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("❌ Could not detect amount. Try: '1500 for Internet'"), backgroundColor: Colors.red),
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
              const Text("Scanning Bill...", style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );

    final receiptData = await OcrScannerService().scanReceipt();
    if (mounted) Navigator.pop(context);

    if (receiptData != null && receiptData['amount'] > 0) {
      _showAddDialog(context, ref, initialTitle: receiptData['title'], initialAmount: receiptData['amount'].toString());
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("❌ Could not read bill clearly."), backgroundColor: Colors.red),
      );
    }
  }

  void _showAddDialog(BuildContext context, WidgetRef ref, {String initialTitle = "", String initialAmount = ""}) {
    final titleCtrl = TextEditingController(text: initialTitle);
    final amountCtrl = TextEditingController(text: initialAmount);
    String frequency = 'Monthly';
    DateTime dueDate = DateTime.now().add(const Duration(days: 30));

    final settings = ref.read(settingsProvider);
    final primaryColor = Color(settings.profileColorValue);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          backgroundColor: Theme.of(context).cardColor,
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: primaryColor.withOpacity(0.15), shape: BoxShape.circle),
                child: Icon(Icons.update_rounded, color: primaryColor),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  "New Subscription",
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
                children: [
                  const SizedBox(height: 4),
                  _buildDialogInput(titleCtrl, "Bill Name (e.g. Internet)", Icons.title_rounded, context, primaryColor),
                  const SizedBox(height: 12),
                  _buildDialogInput(amountCtrl, "Amount (Rs.)", Icons.attach_money_rounded, context, primaryColor, isNumber: true),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark ? Colors.black26 : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: frequency,
                        isExpanded: true,
                        icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.grey),
                        items: ['Monthly', 'Weekly'].map((f) => DropdownMenuItem(value: f, child: Text(f, style: const TextStyle(fontWeight: FontWeight.w600)))).toList(),
                        onChanged: (v) => setModalState(() => frequency = v!),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: dueDate,
                        firstDate: DateTime.now(),
                        lastDate: DateTime(2030),
                      );
                      if (picked != null) setModalState(() => dueDate = picked);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark ? Colors.black26 : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today_rounded, color: Colors.grey, size: 20),
                          const SizedBox(width: 12),
                          Text("Next Due: ${DateFormat.yMMMd().format(dueDate)}", style: const TextStyle(fontWeight: FontWeight.w600)),
                          const Spacer(),
                          const Icon(Icons.edit_calendar_rounded, size: 18, color: Colors.grey),
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
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      final amt = double.tryParse(amountCtrl.text) ?? 0;
                      if (titleCtrl.text.isNotEmpty && amt > 0) {
                        ref.read(recurringProvider.notifier).addBill(
                          RecurringBill(
                            id: const Uuid().v4(),
                            title: titleCtrl.text,
                            amount: amt,
                            frequency: frequency,
                            nextDueDate: dueDate,
                          ),
                        );
                        Navigator.pop(ctx);
                      }
                    },
                    child: const Text("Save Bill", style: TextStyle(fontWeight: FontWeight.bold)),
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
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      style: const TextStyle(fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey.shade500, fontSize: 14),
        prefixIcon: Icon(icon, color: Colors.grey, size: 20),
        filled: true,
        fillColor: Theme.of(context).brightness == Brightness.dark ? Colors.black26 : Colors.grey.shade50,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: primaryColor, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bills = ref.watch(recurringProvider);
    final settings = ref.watch(settingsProvider);
    final primaryColor = Color(settings.profileColorValue); // 🛡️ Guaranteed theme color in dark/light mode
    final isDark = Theme.of(context).brightness == Brightness.dark;

    double totalMonthlyOutflow = bills.fold(0, (sum, b) => sum + (b.frequency == 'Weekly' ? b.amount * 4 : b.amount));

    return Scaffold(
      appBar: AppBar(title: const Text("Recurring Subscriptions", style: TextStyle(fontWeight: FontWeight.bold)), centerTitle: true),
      body: Column(
        children: [
          // 1. 🌟 Hero Summary Card First
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [primaryColor, primaryColor.withOpacity(0.75)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(color: primaryColor.withOpacity(isDark ? 0.35 : 0.4), blurRadius: 18, offset: const Offset(0, 8))
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Estimated Monthly Outflow", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w500)),
                    Icon(Icons.update_rounded, color: Colors.white70),
                  ],
                ),
                const SizedBox(height: 8),
                Text("Rs. ${totalMonthlyOutflow.toStringAsFixed(0)}", style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.white)),
                const SizedBox(height: 8),
                Text("Active Subscriptions: ${bills.length}", style: const TextStyle(color: Colors.white60, fontSize: 11)),
              ],
            ),
          ),

          // 2. 🎙️ Smart Voice & OCR Input Bar Below Hero Card (With Overflow Fixes)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: isDark ? primaryColor.withOpacity(0.4) : Colors.grey.withOpacity(0.2), width: 1.2),
              ),
              child: Row(
                children: [
                  IconButton(
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(8),
                    icon: Icon(_isListening ? Icons.mic : Icons.mic_none_rounded, color: _isListening ? Colors.red : primaryColor, size: 22),
                    onPressed: _listenForInput,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _smartInputCtrl,
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: _isListening ? 'Listening...' : 'Speak/Type: "1500 for Internet"',
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
                    padding: const EdgeInsets.all(8),
                    icon: const Icon(Icons.document_scanner_rounded, color: Colors.blueAccent, size: 20),
                    onPressed: _startReceiptScan,
                    tooltip: "Scan Bill",
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(8),
                    icon: Icon(Icons.send_rounded, color: primaryColor, size: 20),
                    onPressed: () => _processNLP(_smartInputCtrl.text),
                  ),
                ],
              ),
            ),
          ),

          // 3. Bills List
          Expanded(
            child: bills.isEmpty
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.repeat_rounded, size: 60, color: Colors.grey.withOpacity(0.3)),
                  const SizedBox(height: 12),
                  const Text("No active recurring bills", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w500)),
                ],
              ),
            )
                : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              itemCount: bills.length,
              itemBuilder: (ctx, i) {
                final bill = bills[i];
                return Card(
                  elevation: 0,
                  color: Theme.of(context).cardColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: isDark ? primaryColor.withOpacity(0.25) : Colors.grey.withOpacity(0.12),
                      width: 1.2,
                    ),
                  ),
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: primaryColor.withOpacity(0.15), shape: BoxShape.circle),
                          child: Icon(Icons.update_rounded, color: primaryColor),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                bill.title,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "Due: ${DateFormat.MMMEd().format(bill.nextDueDate)} • ${bill.frequency}",
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              "Rs. ${bill.amount.toStringAsFixed(0)}",
                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                            ),
                            const SizedBox(height: 6),
                            InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () {
                                ref.read(recurringProvider.notifier).deleteBill(bill.id);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text("Removed recurring bill"), backgroundColor: Colors.red),
                                );
                              },
                              child: const Padding(
                                padding: EdgeInsets.all(4.0),
                                child: Icon(Icons.delete_outline_rounded, color: Colors.red, size: 20),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddDialog(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: const Text("Add Bill"),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 4,
      ),
    );
  }
}