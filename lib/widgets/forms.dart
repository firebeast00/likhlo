import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// ================= ADD EXPENSE FORM =================
class AddExpenseForm extends StatefulWidget {
  final Function(String, String, double, DateTime) onSubmit;
  final List<String> categories;
  final String? preSelectedCategory;

  const AddExpenseForm({
    super.key,
    required this.onSubmit,
    required this.categories,
    this.preSelectedCategory
  });

  @override
  State<AddExpenseForm> createState() => _AddExpenseFormState();
}

class _AddExpenseFormState extends State<AddExpenseForm> {
  final _descCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  late String _category;

  @override
  void initState() {
    super.initState();
    _category = widget.preSelectedCategory ?? (widget.categories.isNotEmpty ? widget.categories.first : "Other");
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).primaryColor;

    return _BaseFormLayout(
      title: "New Expense",
      child: Column(
        children: [
          _buildModernInput(_amountCtrl, "Amount (Rs)", Icons.attach_money_rounded, primaryColor, isDark, isNumber: true),
          const SizedBox(height: 12),
          _buildModernInput(_descCtrl, "Description (e.g. Burger)", Icons.description_rounded, primaryColor, isDark),
          const SizedBox(height: 12),

          // Category Dropdown
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: isDark ? Colors.black26 : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(16),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: widget.categories.contains(_category) ? _category : (widget.categories.isNotEmpty ? widget.categories.first : "Other"),
                isExpanded: true,
                icon: Icon(Icons.keyboard_arrow_down_rounded, color: Colors.grey.shade500),
                dropdownColor: Theme.of(context).cardColor,
                items: widget.categories.map((c) => DropdownMenuItem(
                    value: c,
                    child: Row(
                      children: [
                        Icon(Icons.category_rounded, size: 18, color: primaryColor),
                        const SizedBox(width: 12),
                        Text(c, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                      ],
                    )
                )).toList(),
                onChanged: (v) => setState(() => _category = v!),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Date Picker
          _buildDatePickerRow(context, _selectedDate, (d) => setState(() => _selectedDate = d), isDark),
          const SizedBox(height: 28),

          // Save Button
          _buildSaveButton(context, "Save Expense", primaryColor, () {
            final amt = double.tryParse(_amountCtrl.text) ?? 0;
            if (_descCtrl.text.isNotEmpty && amt > 0) {
              widget.onSubmit(_descCtrl.text, _category, amt, _selectedDate);
              Navigator.pop(context);
            }
          }),
        ],
      ),
    );
  }
}

// ================= ADD DEBT FORM =================
class AddDebtForm extends StatefulWidget {
  final Function(String, double, bool, DateTime) onSubmit;
  const AddDebtForm({super.key, required this.onSubmit});

  @override
  State<AddDebtForm> createState() => _AddDebtFormState();
}

class _AddDebtFormState extends State<AddDebtForm> {
  final _nameCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  bool _isIOwe = false;
  DateTime _selectedDate = DateTime.now();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).primaryColor;

    return _BaseFormLayout(
      title: "Udhaar Record",
      child: Column(
        children: [
          // Sleek Segmented Control
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: isDark ? Colors.black26 : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Expanded(child: _buildToggleBtn("I Gave (Lent)", !_isIOwe, Colors.green, () => setState(() => _isIOwe = false))),
                Expanded(child: _buildToggleBtn("I Took (Borrowed)", _isIOwe, Colors.red, () => setState(() => _isIOwe = true))),
              ],
            ),
          ),
          const SizedBox(height: 16),

          _buildModernInput(_nameCtrl, "Person Name", Icons.person_rounded, primaryColor, isDark),
          const SizedBox(height: 12),
          _buildModernInput(_amountCtrl, "Amount (Rs)", Icons.attach_money_rounded, primaryColor, isDark, isNumber: true),
          const SizedBox(height: 12),

          _buildDatePickerRow(context, _selectedDate, (d) => setState(() => _selectedDate = d), isDark),
          const SizedBox(height: 28),

          _buildSaveButton(context, "Save Record", primaryColor, () {
            final amt = double.tryParse(_amountCtrl.text) ?? 0;
            if (_nameCtrl.text.isNotEmpty && amt > 0) {
              widget.onSubmit(_nameCtrl.text.trim(), amt, _isIOwe, _selectedDate);
              Navigator.pop(context);
            }
          }),
        ],
      ),
    );
  }

  Widget _buildToggleBtn(String text, bool isActive, Color activeColor, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isActive ? activeColor : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isActive ? [BoxShadow(color: activeColor.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 2))] : [],
        ),
        child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: isActive ? Colors.white : Colors.grey.shade500
            )
        ),
      ),
    );
  }
}

// ================= SHARED UI COMPONENTS =================

class _BaseFormLayout extends StatelessWidget {
  final String title;
  final Widget child;

  const _BaseFormLayout({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 30, offset: const Offset(0, -5))]
      ),
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          left: 24, right: 24, top: 12
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
                child: Container(
                    width: 48, height: 4,
                    decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3), borderRadius: BorderRadius.circular(2)),
                    margin: const EdgeInsets.only(bottom: 24)
                )
            ),
            Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: -0.5)),
            const SizedBox(height: 20),
            child,
          ],
        ),
      ),
    );
  }
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

Widget _buildDatePickerRow(BuildContext context, DateTime dt, Function(DateTime) onPicked, bool isDark) {
  return GestureDetector(
    onTap: () async {
      final picked = await showDatePicker(
          context: context,
          initialDate: dt,
          firstDate: DateTime(2020),
          lastDate: DateTime(2030)
      );
      if (picked != null) onPicked(picked);
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
              DateFormat.yMMMd().format(dt),
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)
          ),
          const Spacer(),
          Icon(Icons.edit_calendar_rounded, size: 18, color: Colors.grey.shade400),
        ],
      ),
    ),
  );
}

Widget _buildSaveButton(BuildContext context, String text, Color color, VoidCallback onPressed) {
  return SizedBox(
    width: double.infinity,
    height: 52,
    child: ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
    ),
  );
}