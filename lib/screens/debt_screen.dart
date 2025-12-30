import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../models/debt_model.dart';
import '../services/notification_service.dart'; // Import Notification Service

class DebtScreen extends StatefulWidget {
  const DebtScreen({super.key});

  @override
  State<DebtScreen> createState() => _DebtScreenState();
}

class _DebtScreenState extends State<DebtScreen> {
  final Box<DebtEntry> debtBox = Hive.box<DebtEntry>('debts');

  // Add Debt Logic with Date Picker & Notification
  void _showAddDialog() {
    final nameCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    String type = 'lent'; // 'lent' (I gave) or 'borrowed' (I took)
    DateTime? selectedDate;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: const Text("New Udhaar Entry"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Type Selector (Tabs)
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setModalState(() => type = 'lent'),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(color: type == 'lent' ? Colors.green : Colors.grey.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                            child: Center(child: Text("I Gave", style: TextStyle(color: type == 'lent' ? Colors.white : Colors.black, fontWeight: FontWeight.bold))),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setModalState(() => type = 'borrowed'),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(color: type == 'borrowed' ? Colors.red : Colors.grey.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                            child: Center(child: Text("I Took", style: TextStyle(color: type == 'borrowed' ? Colors.white : Colors.black, fontWeight: FontWeight.bold))),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 15),
                  TextField(controller: nameCtrl, decoration: InputDecoration(labelText: "Person Name", prefixIcon: const Icon(Icons.person_rounded), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))), textCapitalization: TextCapitalization.sentences),
                  const SizedBox(height: 10),
                  TextField(controller: amountCtrl, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: "Amount", prefixIcon: const Icon(Icons.attach_money_rounded), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)))),
                  const SizedBox(height: 10),

                  // DATE PICKER
                  ListTile(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: Colors.grey.withOpacity(0.3))),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    title: Text(selectedDate == null ? "Set Due Date" : "Due: ${DateFormat.yMMMd().format(selectedDate!)}", style: TextStyle(color: selectedDate == null ? Colors.grey : Theme.of(context).textTheme.bodyLarge?.color)),
                    leading: const Icon(Icons.calendar_today_rounded, size: 20, color: Colors.blue),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () async {
                      final date = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime.now(), lastDate: DateTime(2030));
                      if (date != null) setModalState(() => selectedDate = date);
                    },
                  )
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
                ElevatedButton(
                  onPressed: () async {
                    if (nameCtrl.text.isNotEmpty && amountCtrl.text.isNotEmpty) {
                      final double amt = double.parse(amountCtrl.text);

                      final newDebt = DebtEntry(
                        id: const Uuid().v4(),
                        borrowerName: nameCtrl.text, // Ensure your model uses 'borrowerName' or 'name'
                        amount: amt,
                        type: type,
                        dueDate: selectedDate,
                      );

                      // 1. Save to Hive
                      int key = await debtBox.add(newDebt);

                      // 2. Schedule Notification (If date is set)
                      if (selectedDate != null && selectedDate!.isAfter(DateTime.now())) {
                        NotificationService().scheduleNotification(
                            key, // Use Hive key as ID
                            "Udhaar Due Today! 💰",
                            "${type == 'lent' ? 'Collect' : 'Pay'} Rs. ${amt.toStringAsFixed(0)} ${type == 'lent' ? 'from' : 'to'} ${nameCtrl.text}",
                            selectedDate!
                        );
                      }

                      setState(() {});
                      Navigator.pop(ctx);
                    }
                  },
                  child: const Text("Save"),
                )
              ],
            );
          }
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final debts = debtBox.values.toList();
    double iGave = debts.where((e) => e.type == 'lent').fold(0, (sum, e) => sum + e.amount);
    double iTook = debts.where((e) => e.type == 'borrowed').fold(0, (sum, e) => sum + e.amount);
    double balance = iGave - iTook;

    return Scaffold(
      backgroundColor: Colors.transparent, // Use parent background
      body: Column(
        children: [
          // 1. SUMMARY CARDS
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 5))]
            ),
            child: Column(
              children: [
                const Text("Net Balance", style: TextStyle(color: Colors.grey)),
                Text("Rs. ${balance.abs().toStringAsFixed(0)}", style: TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: balance >= 0 ? Colors.green : Colors.red)),
                Text(balance >= 0 ? "You will get" : "You have to pay", style: TextStyle(fontSize: 12, color: balance >= 0 ? Colors.green : Colors.red, fontWeight: FontWeight.bold)),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(child: _summaryBox("I Gave", iGave, Colors.green)),
                    const SizedBox(width: 15),
                    Expanded(child: _summaryBox("I Took", iTook, Colors.red)),
                  ],
                )
              ],
            ),
          ),

          // 2. LIST
          Expanded(
            child: debts.isEmpty
                ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.handshake_rounded, size: 60, color: Colors.grey.withOpacity(0.3)), const SizedBox(height: 10), const Text("No records found", style: TextStyle(color: Colors.grey))]))
                : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: debts.length,
              itemBuilder: (ctx, i) {
                final item = debts[i];
                final isLent = item.type == 'lent';
                return Dismissible(
                  key: Key(item.id),
                  background: Container(alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), color: Colors.red, child: const Icon(Icons.delete, color: Colors.white)),
                  onDismissed: (_) { item.delete(); setState((){}); },
                  child: Card(
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.grey.withOpacity(0.1))),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      leading: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: isLent ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1), shape: BoxShape.circle),
                        child: Icon(isLent ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, color: isLent ? Colors.green : Colors.red, size: 20),
                      ),
                      title: Text(item.borrowerName, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: item.dueDate != null
                          ? Row(children: [const Icon(Icons.calendar_month_rounded, size: 12, color: Colors.grey), const SizedBox(width: 4), Text("Due: ${DateFormat.MMMd().format(item.dueDate!)}", style: const TextStyle(fontSize: 12, color: Colors.grey))])
                          : const Text("No Due Date", style: TextStyle(fontSize: 12, color: Colors.grey)),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text("Rs. ${item.amount.toStringAsFixed(0)}", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: isLent ? Colors.green : Colors.red)),
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
        onPressed: _showAddDialog,
      ),
    );
  }

  Widget _summaryBox(String title, double amount, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(amount.toStringAsFixed(0), style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}