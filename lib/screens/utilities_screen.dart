import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../providers/settings_provider.dart';

class UtilitiesScreen extends ConsumerStatefulWidget {
  const UtilitiesScreen({super.key});

  @override
  ConsumerState<UtilitiesScreen> createState() => _UtilitiesScreenState();
}

class _UtilitiesScreenState extends ConsumerState<UtilitiesScreen> {
  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final primaryColor = Color(settings.profileColorValue);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: [
          const Text("Student Tools Hub", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text("Academic & financial utilities for campus life", style: TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 20),

          _toolCard(Icons.fact_check_rounded, "Attendance & Bunk Planner", "Calculate safe lecture skips or classes needed for 75%", Colors.indigo, _openAttendancePlanner, isDark),
          _toolCard(Icons.school_rounded, "Semester GPA Calculator", "Calculate exact GPA across multiple courses & credits", Colors.teal, _openGpaCalculator, isDark),
          _toolCard(Icons.timer_rounded, "Pomodoro Study Clock", "25-minute focus cycles with short break intervals", Colors.deepOrange, _openPomodoroTimer, isDark),
          _toolCard(Icons.discount_rounded, "Discount & Savings Tool", "Calculate student vouchers, taxes, and final prices", Colors.pink, _openDiscountCalculator, isDark),
          _toolCard(Icons.calculate_rounded, "Academic Calculator", "Solve quick numerical formulas and expressions", Colors.blue, _openCalculator, isDark),
          _toolCard(Icons.currency_exchange_rounded, "Currency & Fee Converter", "Quick PKR exchange estimates for international fees", Colors.amber.shade800, _openCurrencyConverter, isDark),
          _toolCard(Icons.note_alt_rounded, "Academic Scratchpad", "Auto-saved notes for formulas, codes, and reminders", Colors.purple, _openScratchpad, isDark),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _toolCard(IconData icon, String title, String subtitle, Color color, VoidCallback onTap, bool isDark) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isDark ? Colors.white.withOpacity(0.08) : Colors.grey.withOpacity(0.12)),
          boxShadow: [BoxShadow(color: isDark ? Colors.black26 : Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: color.withOpacity(0.12), shape: BoxShape.circle),
              child: Icon(icon, size: 24, color: color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade500), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.arrow_forward_ios_rounded, color: Colors.grey.shade400, size: 14),
          ],
        ),
      ),
    );
  }

  // 🌟 Reusable Modern Input Helper for all forms
  Widget _buildModernInput({required TextEditingController controller, required String label, required IconData icon, required Color color, bool isNumber = true}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextField(
      controller: controller,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey.shade500, fontSize: 13),
        prefixIcon: Icon(icon, color: color.withOpacity(0.7), size: 20),
        filled: true,
        fillColor: isDark ? Colors.black26 : Colors.grey.shade50,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: color, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      ),
    );
  }

  // ================= 1. ATTENDANCE & BUNK PLANNER =================
  void _openAttendancePlanner() {
    final attendedCtrl = TextEditingController();
    final totalCtrl = TextEditingController();
    double targetPercentage = 75.0;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          insetPadding: const EdgeInsets.all(20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Row(
            children: [
              Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.indigo.withOpacity(0.15), shape: BoxShape.circle), child: const Icon(Icons.fact_check_rounded, color: Colors.indigo, size: 20)),
              const SizedBox(width: 12),
              const Text("Attendance Planner", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 4),
                _buildModernInput(controller: attendedCtrl, label: "Classes Attended", icon: Icons.check_circle_outline_rounded, color: Colors.indigo),
                const SizedBox(height: 12),
                _buildModernInput(controller: totalCtrl, label: "Total Classes Held", icon: Icons.format_list_numbered_rounded, color: Colors.indigo),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text("Target:", style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(width: 12),
                    ChoiceChip(
                      label: const Text("75%"),
                      selected: targetPercentage == 75.0,
                      selectedColor: Colors.indigo.withOpacity(0.2),
                      onSelected: (v) => setModalState(() => targetPercentage = 75.0),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text("80%"),
                      selected: targetPercentage == 80.0,
                      selectedColor: Colors.indigo.withOpacity(0.2),
                      onSelected: (v) => setModalState(() => targetPercentage = 80.0),
                    ),
                  ],
                )
              ],
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          actions: [
            Row(
              children: [
                Expanded(child: TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel", style: TextStyle(color: Colors.grey)))),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(vertical: 12)),
                    onPressed: () {
                      final attended = int.tryParse(attendedCtrl.text) ?? 0;
                      final total = int.tryParse(totalCtrl.text) ?? 0;
                      if (total <= 0 || attended > total) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please enter valid class numbers."))); return; }
                      Navigator.pop(ctx);
                      final currentPct = (attended / total) * 100;
                      String resultMessage = "Current Attendance: ${currentPct.toStringAsFixed(1)}%\n\n";
                      if (currentPct >= targetPercentage) {
                        int canBunk = 0;
                        while (((attended) / (total + canBunk + 1)) * 100 >= targetPercentage) { canBunk++; }
                        resultMessage += canBunk > 0 ? "🎉 You can safely skip $canBunk upcoming lecture(s) while staying above ${targetPercentage.toInt()}%!" : "⚠️ You are on the border! You cannot miss the next class.";
                      } else {
                        int needed = 0;
                        while (((attended + needed) / (total + needed)) * 100 < targetPercentage) { needed++; }
                        resultMessage += "🚨 You need to attend $needed consecutive class(es) to reach your ${targetPercentage.toInt()}% target.";
                      }
                      _alert("Attendance Status", resultMessage);
                    },
                    child: const Text("Calculate"),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ================= 2. MULTI-COURSE GPA CALCULATOR =================
  void _openGpaCalculator() {
    showDialog(context: context, builder: (ctx) => const _GpaCalculatorDialog());
  }

  // ================= 3. POMODORO FOCUS TIMER =================
  void _openPomodoroTimer() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const _PomodoroScreen()));
  }

  // ================= 4. STUDENT DISCOUNT & SAVINGS =================
  void _openDiscountCalculator() {
    final priceCtrl = TextEditingController();
    final discountCtrl = TextEditingController();
    final extraVoucherCtrl = TextEditingController(text: "0");

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        insetPadding: const EdgeInsets.all(20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.pink.withOpacity(0.15), shape: BoxShape.circle), child: const Icon(Icons.discount_rounded, color: Colors.pink, size: 20)),
            const SizedBox(width: 12),
            const Text("Discount Tool", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 4),
              _buildModernInput(controller: priceCtrl, label: "Original Price (Rs.)", icon: Icons.sell_rounded, color: Colors.pink),
              const SizedBox(height: 12),
              _buildModernInput(controller: discountCtrl, label: "Sale Discount (%)", icon: Icons.percent_rounded, color: Colors.pink),
              const SizedBox(height: 12),
              _buildModernInput(controller: extraVoucherCtrl, label: "Extra Voucher (Rs.)", icon: Icons.card_giftcard_rounded, color: Colors.pink),
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        actions: [
          Row(
            children: [
              Expanded(child: TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel", style: TextStyle(color: Colors.grey)))),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.pink, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(vertical: 12)),
                  onPressed: () {
                    final original = double.tryParse(priceCtrl.text) ?? 0;
                    final pct = double.tryParse(discountCtrl.text) ?? 0;
                    final coupon = double.tryParse(extraVoucherCtrl.text) ?? 0;
                    if (original <= 0) return;
                    final discounted = original - (original * (pct / 100));
                    final finalPrice = (discounted - coupon).clamp(0, double.infinity);
                    final totalSaved = original - finalPrice;
                    Navigator.pop(ctx);
                    _alert("Savings Summary", "Final Payable: Rs. ${finalPrice.toStringAsFixed(0)}\nTotal Saved: Rs. ${totalSaved.toStringAsFixed(0)} (${((totalSaved / original) * 100).toStringAsFixed(1)}% off)");
                  },
                  child: const Text("Calculate"),
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  // ================= 5. SCIENTIFIC MATH CALCULATOR =================
  void _openCalculator() {
    showDialog(context: context, builder: (ctx) => const _CalculatorDialog());
  }

  // ================= 6. CURRENCY CONVERTER =================
  void _openCurrencyConverter() {
    final amountCtrl = TextEditingController();
    String currency = 'USD';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          insetPadding: const EdgeInsets.all(20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Row(
            children: [
              Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.amber.shade800.withOpacity(0.15), shape: BoxShape.circle), child: Icon(Icons.currency_exchange_rounded, color: Colors.amber.shade800, size: 20)),
              const SizedBox(width: 12),
              const Expanded(child: Text("PKR Converter", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 4),
              _buildModernInput(controller: amountCtrl, label: "Foreign Amount", icon: Icons.public_rounded, color: Colors.amber.shade800),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(color: isDark ? Colors.black26 : Colors.grey.shade50, borderRadius: BorderRadius.circular(16)),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: currency,
                    isExpanded: true,
                    icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.grey),
                    items: ['USD', 'EUR', 'GBP', 'SAR', 'AED'].map((c) => DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontWeight: FontWeight.bold)))).toList(),
                    onChanged: (v) => setModalState(() => currency = v!),
                  ),
                ),
              ),
            ],
          ),
          actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          actions: [
            Row(
              children: [
                Expanded(child: TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel", style: TextStyle(color: Colors.grey)))),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.amber.shade800, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(vertical: 12)),
                    onPressed: () {
                      double amt = double.tryParse(amountCtrl.text) ?? 0;
                      double rate = 278.5;
                      if (currency == 'EUR') rate = 302.0;
                      if (currency == 'GBP') rate = 356.0;
                      if (currency == 'SAR') rate = 74.2;
                      if (currency == 'AED') rate = 75.8;
                      double converted = amt * rate;
                      Navigator.pop(ctx);
                      _alert("Exchange Estimate", "$amt $currency = Rs. ${converted.toStringAsFixed(2)}\n(Estimated base rate)");
                    },
                    child: const Text("Convert"),
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  // ================= 7. ACADEMIC SCRATCHPAD =================
  void _openScratchpad() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const _ScratchpadScreen()));
  }

  void _alert(String title, String msg) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Text(msg, style: const TextStyle(fontSize: 15, height: 1.4)),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Got it"))],
      ),
    );
  }
}

// ================= MULTI-COURSE GPA DIALOG (OVERFLOW FIXED) =================
class _GpaCalculatorDialog extends StatefulWidget {
  const _GpaCalculatorDialog();

  @override
  State<_GpaCalculatorDialog> createState() => _GpaCalculatorDialogState();
}

class _CourseEntry {
  final TextEditingController nameCtrl = TextEditingController();
  final TextEditingController creditCtrl = TextEditingController(text: "3");
  String grade = 'A+ / A';
}

class _GpaCalculatorDialogState extends State<_GpaCalculatorDialog> {
  final List<_CourseEntry> _courses = [_CourseEntry(), _CourseEntry(), _CourseEntry()];
  final Map<String, double> _gradePoints = {'A+ / A': 4.0, 'A-': 3.67, 'B+': 3.33, 'B': 3.0, 'B-': 2.67, 'C+': 2.33, 'C': 2.0, 'D': 1.0, 'F': 0.0};

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Row(
        children: [
          Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.teal.withOpacity(0.15), shape: BoxShape.circle), child: const Icon(Icons.school_rounded, color: Colors.teal, size: 20)),
          const SizedBox(width: 12),
          const Expanded(child: Text("GPA Calculator", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
        ],
      ),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.9,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ..._courses.asMap().entries.map((entry) {
                final i = entry.key;
                final c = entry.value;
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.black26 : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade200),
                  ),
                  child: Column(
                    children: [
                      // 🛡️ Card Layout prevents row squishing and layout overflows
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: c.nameCtrl,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                              decoration: InputDecoration(
                                hintText: "Course ${i + 1} Name",
                                hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                                border: InputBorder.none,
                                isDense: true,
                              ),
                            ),
                          ),
                          if (_courses.length > 1)
                            InkWell(
                              onTap: () => setState(() => _courses.removeAt(i)),
                              child: const Icon(Icons.close_rounded, color: Colors.red, size: 18),
                            )
                        ],
                      ),
                      const Divider(height: 12, thickness: 0.5),
                      Row(
                        children: [
                          const Icon(Icons.book_rounded, size: 16, color: Colors.teal),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: c.creditCtrl,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(fontSize: 14),
                              decoration: const InputDecoration(hintText: "Credits", border: InputBorder.none, isDense: true),
                            ),
                          ),
                          Container(width: 1, height: 20, color: Colors.grey.withOpacity(0.3), margin: const EdgeInsets.symmetric(horizontal: 8)),
                          Expanded(
                            flex: 3,
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _gradePoints.containsKey(c.grade) ? c.grade : 'A+ / A',
                                isExpanded: true, // 🛡️ CRITICAL FIX: Forces dropdown to respect parent boundaries without overflowing
                                isDense: true,
                                icon: const Icon(Icons.arrow_drop_down_rounded, color: Colors.grey),
                                items: _gradePoints.keys.map((g) => DropdownMenuItem(value: g, child: Text("Grade: $g", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)))).toList(),
                                onChanged: (val) => setState(() => c.grade = val!),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }),
              TextButton.icon(
                onPressed: () => setState(() => _courses.add(_CourseEntry())),
                icon: const Icon(Icons.add_rounded, size: 18, color: Colors.teal),
                label: const Text("Add Another Course", style: TextStyle(color: Colors.teal, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      actions: [
        Row(
          children: [
            Expanded(child: TextButton(onPressed: () => Navigator.pop(context), child: const Text("Close", style: TextStyle(color: Colors.grey)))),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(vertical: 12)),
                onPressed: () {
                  double totalPoints = 0;
                  double totalCredits = 0;
                  for (var c in _courses) {
                    final credits = double.tryParse(c.creditCtrl.text) ?? 0;
                    final point = _gradePoints[c.grade] ?? 0.0;
                    totalPoints += (credits * point);
                    totalCredits += credits;
                  }
                  if (totalCredits <= 0) return;
                  final gpa = totalPoints / totalCredits;
                  Navigator.pop(context);
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                      title: const Text("GPA Result", style: TextStyle(fontWeight: FontWeight.bold)),
                      content: Text("Semester GPA: ${gpa.toStringAsFixed(2)}\nTotal Credit Hours: ${totalCredits.toStringAsFixed(0)}\nTotal Quality Points: ${totalPoints.toStringAsFixed(1)}", style: const TextStyle(fontSize: 15, height: 1.4)),
                      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Got it"))],
                    ),
                  );
                },
                child: const Text("Calculate GPA"),
              ),
            ),
          ],
        )
      ],
    );
  }
}

// ================= POMODORO STUDY TIMER SCREEN =================
class _PomodoroScreen extends StatefulWidget {
  const _PomodoroScreen();
  @override
  State<_PomodoroScreen> createState() => _PomodoroScreenState();
}

class _PomodoroScreenState extends State<_PomodoroScreen> {
  int _secondsLeft = 25 * 60;
  bool _isRunning = false;
  Timer? _timer;
  bool _isBreak = false;

  void _startOrPauseTimer() {
    if (_isRunning) {
      _timer?.cancel();
      setState(() => _isRunning = false);
    } else {
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (_secondsLeft > 0) {
          setState(() => _secondsLeft--);
        } else {
          _timer?.cancel();
          setState(() { _isRunning = false; _isBreak = !_isBreak; _secondsLeft = _isBreak ? 5 * 60 : 25 * 60; });
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_isBreak ? "⏰ Focus session finished! Take a 5-minute break." : "🚀 Break over! Back to focus.")));
        }
      });
      setState(() => _isRunning = true);
    }
  }
  void _resetTimer(bool isBreakMode) { _timer?.cancel(); setState(() { _isRunning = false; _isBreak = isBreakMode; _secondsLeft = isBreakMode ? 5 * 60 : 25 * 60; }); }
  @override
  void dispose() { _timer?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final minutes = (_secondsLeft ~/ 60).toString().padLeft(2, '0');
    final seconds = (_secondsLeft % 60).toString().padLeft(2, '0');
    final progress = (_secondsLeft / (_isBreak ? 5 * 60 : 25 * 60));

    return Scaffold(
      appBar: AppBar(title: const Text("Pomodoro Focus Clock"), centerTitle: true),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_isBreak ? "☕ Short Break" : "🎯 Deep Focus Session", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _isBreak ? Colors.teal : Colors.deepOrange)),
            const SizedBox(height: 30),
            Stack(alignment: Alignment.center, children: [
              SizedBox(width: 220, height: 220, child: CircularProgressIndicator(value: progress, strokeWidth: 10, backgroundColor: Colors.grey.withOpacity(0.15), color: _isBreak ? Colors.teal : Colors.deepOrange)),
              Text("$minutes:$seconds", style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w900)),
            ]),
            const SizedBox(height: 40),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: _isBreak ? Colors.teal : Colors.deepOrange, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))), onPressed: _startOrPauseTimer, icon: Icon(_isRunning ? Icons.pause_rounded : Icons.play_arrow_rounded), label: Text(_isRunning ? "Pause" : "Start")),
                const SizedBox(width: 12),
                OutlinedButton(style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))), onPressed: () => _resetTimer(_isBreak), child: const Text("Reset")),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ChoiceChip(label: const Text("25m Focus"), selected: !_isBreak, onSelected: (_) => _resetTimer(false)),
                const SizedBox(width: 8),
                ChoiceChip(label: const Text("5m Break"), selected: _isBreak, onSelected: (_) => _resetTimer(true)),
              ],
            )
          ],
        ),
      ),
    );
  }
}

// ================= SCIENTIFIC CALCULATOR DIALOG =================
class _CalculatorDialog extends StatefulWidget { const _CalculatorDialog(); @override State<_CalculatorDialog> createState() => _CalculatorDialogState(); }
class _CalculatorDialogState extends State<_CalculatorDialog> {
  String _output = "0", _num1 = "", _operand = ""; bool _isCleared = true;
  void _onButtonPressed(String val) {
    setState(() {
      if (val == "C") { _output = "0"; _num1 = ""; _operand = ""; _isCleared = true; }
      else if (val == "+" || val == "-" || val == "×" || val == "÷") { _num1 = _output; _operand = val; _isCleared = true; }
      else if (val == "=") {
        if (_operand.isNotEmpty && _num1.isNotEmpty) {
          double n1 = double.tryParse(_num1) ?? 0; double n2 = double.tryParse(_output) ?? 0; double res = 0;
          if (_operand == "+") res = n1 + n2; if (_operand == "-") res = n1 - n2; if (_operand == "×") res = n1 * n2; if (_operand == "÷") res = n2 != 0 ? n1 / n2 : 0;
          _output = res.toString(); if (_output.endsWith(".0")) _output = _output.substring(0, _output.length - 2);
          _operand = ""; _num1 = ""; _isCleared = true;
        }
      } else { if (_isCleared) { _output = val; _isCleared = false; } else { _output = _output == "0" ? val : _output + val; } }
    });
  }
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: const Text("Academic Calculator", style: TextStyle(fontWeight: FontWeight.bold)),
      content: SizedBox(
        width: 270,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(alignment: Alignment.centerRight, padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.grey.withOpacity(0.1), borderRadius: BorderRadius.circular(16)), child: Text(_output, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold))),
            const SizedBox(height: 16),
            _buildBtnRow(["7", "8", "9", "÷"]), const SizedBox(height: 8), _buildBtnRow(["4", "5", "6", "×"]), const SizedBox(height: 8), _buildBtnRow(["1", "2", "3", "-"]), const SizedBox(height: 8), _buildBtnRow(["C", "0", "=", "+"]),
          ],
        ),
      ),
    );
  }
  Widget _buildBtnRow(List<String> values) {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: values.map((v) => ElevatedButton(style: ElevatedButton.styleFrom(minimumSize: const Size(52, 46), padding: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), onPressed: () => _onButtonPressed(v), child: Text(v, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)))).toList());
  }
}

// ================= SCRATCHPAD SCREEN =================
class _ScratchpadScreen extends StatefulWidget { const _ScratchpadScreen(); @override State<_ScratchpadScreen> createState() => _ScratchpadScreenState(); }
class _ScratchpadScreenState extends State<_ScratchpadScreen> {
  final TextEditingController _noteCtrl = TextEditingController(); Box<String>? _scratchBox; bool _isLoading = true;
  @override
  void initState() { super.initState(); _initBox(); }
  Future<void> _initBox() async { if (!Hive.isBoxOpen('scratchpad_box')) { _scratchBox = await Hive.openBox<String>('scratchpad_box'); } else { _scratchBox = Hive.box<String>('scratchpad_box'); } _noteCtrl.text = _scratchBox?.get('notes', defaultValue: '') ?? ''; if (mounted) setState(() => _isLoading = false); }
  void _saveNotes() { _scratchBox?.put('notes', _noteCtrl.text); }
  @override
  void dispose() { _saveNotes(); _noteCtrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final wordCount = _noteCtrl.text.trim().isEmpty ? 0 : _noteCtrl.text.trim().split(RegExp(r'\s+')).length;
    final charCount = _noteCtrl.text.length;
    return Scaffold(
      appBar: AppBar(title: const Text("Academic Scratchpad", style: TextStyle(fontWeight: FontWeight.bold)), centerTitle: true, actions: [IconButton(icon: const Icon(Icons.check_rounded), onPressed: () { _saveNotes(); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Notes saved locally!"), duration: Duration(seconds: 1))); })]),
      body: _isLoading ? const Center(child: CircularProgressIndicator()) : Padding(padding: const EdgeInsets.all(20), child: Column(children: [Expanded(child: TextField(controller: _noteCtrl, maxLines: null, expands: true, onChanged: (_) => setState(() {}), decoration: const InputDecoration(hintText: "Jot down formulas, code snippets, or lecture reminders...", border: InputBorder.none))), Container(padding: const EdgeInsets.symmetric(vertical: 8), alignment: Alignment.centerRight, child: Text("$wordCount words • $charCount characters", style: TextStyle(color: Colors.grey.shade500, fontSize: 12)))])),
    );
  }
}