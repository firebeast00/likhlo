import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class AddExpenseForm extends StatefulWidget {
  final Function(String, String, double, DateTime) onSubmit;
  final List<String> categories;
  final String? preSelectedCategory;
  const AddExpenseForm({super.key, required this.onSubmit, required this.categories, this.preSelectedCategory});
  @override
  State<AddExpenseForm> createState() => _AddExpenseFormState();
}

class _AddExpenseFormState extends State<AddExpenseForm> {
  final tC = TextEditingController(); final aC = TextEditingController();
  DateTime dt = DateTime.now(); late String cat;
  @override
  void initState() { super.initState(); cat = widget.preSelectedCategory ?? (widget.categories.isNotEmpty ? widget.categories[0] : "Other"); }
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return _baseForm(context, "Add Expense", Column(children: [
      _inputField(aC, "Amount (Rs)", isDark, true), const SizedBox(height: 15),
      _inputField(tC, "Description (e.g. Burger)", isDark), const SizedBox(height: 15),
      DropdownButtonFormField(value: cat, dropdownColor: isDark ? const Color(0xFF2C2C2C) : Colors.white, items: widget.categories.map((c) => DropdownMenuItem(value: c, child: Text(c, style: TextStyle(color: isDark ? Colors.white : Colors.black)))).toList(), onChanged: (v) => setState(() => cat = v!), decoration: _inputDeco("Category", isDark)),
      const SizedBox(height: 15), _datePickerRow(context, dt, (d) => setState(() => dt = d), isDark),
      const SizedBox(height: 25), _saveButton(context, "Save Expense", () { if(tC.text.isNotEmpty && aC.text.isNotEmpty) { widget.onSubmit(tC.text, cat, double.parse(aC.text), dt); Navigator.pop(context); } }),
    ]));
  }
}

class AddDebtForm extends StatefulWidget {
  final Function(String, double, bool, DateTime) onSubmit;
  const AddDebtForm({super.key, required this.onSubmit});
  @override
  State<AddDebtForm> createState() => _AddDebtFormState();
}

class _AddDebtFormState extends State<AddDebtForm> {
  final nC = TextEditingController(); final aC = TextEditingController();
  bool isIOwe = false; DateTime dt = DateTime.now();
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return _baseForm(context, "Add Debt Record", Column(children: [
      Container(padding: const EdgeInsets.all(5), decoration: BoxDecoration(color: isDark ? Colors.grey[800] : Colors.grey[100], borderRadius: BorderRadius.circular(15)), child: Row(children: [Expanded(child: _toggleBtn("I Lent", !isIOwe, () => setState(() => isIOwe = false), isDark)), Expanded(child: _toggleBtn("I Borrowed", isIOwe, () => setState(() => isIOwe = true), isDark))])),
      const SizedBox(height: 20), _inputField(nC, "Person Name", isDark), const SizedBox(height: 15), _inputField(aC, "Amount (Rs)", isDark, true), const SizedBox(height: 15), _datePickerRow(context, dt, (d) => setState(() => dt = d), isDark),
      const SizedBox(height: 25), _saveButton(context, "Save Record", () { if(nC.text.isNotEmpty && aC.text.isNotEmpty) { widget.onSubmit(nC.text, double.parse(aC.text), isIOwe, dt); Navigator.pop(context); } }),
    ]));
  }
  Widget _toggleBtn(String t, bool a, VoidCallback p, bool d) => GestureDetector(onTap: p, child: AnimatedContainer(duration: const Duration(milliseconds: 200), padding: const EdgeInsets.symmetric(vertical: 12), decoration: BoxDecoration(color: a ? (d ? Colors.black : Colors.white) : Colors.transparent, borderRadius: BorderRadius.circular(12), boxShadow: a ? [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5)] : []), child: Text(t, textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, color: a ? (d ? Colors.white : Colors.black) : Colors.grey))));
}

Widget _baseForm(BuildContext ctx, String t, Widget c) {
  final isDark = Theme.of(ctx).brightness == Brightness.dark;
  return Container(padding: const EdgeInsets.all(25), decoration: BoxDecoration(color: isDark ? const Color(0xFF1E1E1E) : Colors.white, borderRadius: const BorderRadius.only(topLeft: Radius.circular(30), topRight: Radius.circular(30))), child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))), const SizedBox(height: 20), Text(t, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)), const SizedBox(height: 20), Padding(padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom), child: c)])));
}
Widget _inputField(TextEditingController c, String l, bool d, [bool n=false]) => TextField(controller: c, keyboardType: n ? TextInputType.number : TextInputType.text, style: TextStyle(color: d ? Colors.white : Colors.black), decoration: _inputDeco(l, d));
InputDecoration _inputDeco(String l, bool d) => InputDecoration(labelText: l, labelStyle: TextStyle(color: d ? Colors.grey : Colors.black54), filled: true, fillColor: d ? const Color(0xFF2C2C2C) : const Color(0xFFF5F7FA), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16));
Widget _datePickerRow(BuildContext ctx, DateTime dt, Function(DateTime) p, bool d) => Row(children: [Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: d ? const Color(0xFF2C2C2C) : const Color(0xFFF5F7FA), borderRadius: BorderRadius.circular(12)), child: Icon(Icons.calendar_today_rounded, size: 20, color: d ? Colors.white70 : Colors.grey)), const SizedBox(width: 15), Text(DateFormat.yMMMd().format(dt), style: TextStyle(fontWeight: FontWeight.bold, color: d ? Colors.white : Colors.black)), const Spacer(), TextButton(onPressed: () => showDatePicker(context: ctx, initialDate: dt, firstDate: DateTime(2022), lastDate: DateTime.now(), builder: (context, child) => Theme(data: d ? ThemeData.dark() : ThemeData.light(), child: child!)).then((v) { if(v!=null) p(v); }), child: const Text("Change", style: TextStyle(fontWeight: FontWeight.bold)))]);
Widget _saveButton(BuildContext ctx, String t, VoidCallback p) => SizedBox(width: double.infinity, child: ElevatedButton(onPressed: p, style: ElevatedButton.styleFrom(backgroundColor: Theme.of(ctx).primaryColor, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), elevation: 0), child: Text(t, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))));