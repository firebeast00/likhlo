import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'dart:ui';

import '../providers/expense_provider.dart';
import '../providers/budget_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/category_provider.dart';
import '../models/expense_model.dart';
import '../widgets/app_drawer.dart';

import 'todo_screen.dart';
import 'debt_screen.dart';
import 'utilities_screen.dart';
import 'settings_screen.dart';
import 'stats_screen.dart';
import 'about_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with SingleTickerProviderStateMixin {
  String _currentView = 'Dashboard';
  DateTime _focusedMonth = DateTime.now();
  String _selectedCategoryTab = 'All';
  bool _isSearching = false;
  String _searchQuery = "";
  final ScrollController _categoryScrollCtrl = ScrollController();

  late AnimationController _fabController;
  late Animation<double> _fabScale;

  @override
  void initState() {
    super.initState();
    _fabController = AnimationController(vsync: this, duration: const Duration(milliseconds: 200), lowerBound: 0.0, upperBound: 0.1);
    _fabScale = Tween<double>(begin: 1.0, end: 0.9).animate(_fabController);
  }

  void _selectCategory(String category, int index) {
    setState(() => _selectedCategoryTab = category);
    double offset = (index * 80.0) - (MediaQuery.of(context).size.width / 2) + 40;
    if (offset < 0) offset = 0;
    if (_categoryScrollCtrl.hasClients) {
      _categoryScrollCtrl.animateTo(offset, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  void _showAddOrEditModal({Expense? existing}) {
    final titleCtrl = TextEditingController(text: existing?.title ?? "");
    final amountCtrl = TextEditingController(text: existing?.amount.toString() ?? "");
    String selectedCategory = existing?.category ?? "General";
    DateTime selectedDate = existing?.date ?? DateTime.now();

    final categories = ref.read(categoryProvider);
    if (!categories.contains(selectedCategory) && categories.isNotEmpty) {
      selectedCategory = categories.first;
    } else if (categories.isEmpty) {
      selectedCategory = "General";
    }

    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => StatefulBuilder(
          builder: (context, setModalState) => Container(
            decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 20, offset: const Offset(0, -5))]
            ),
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom + 20, left: 24, right: 24, top: 10),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3), borderRadius: BorderRadius.circular(2)), margin: const EdgeInsets.only(bottom: 20)),
                  Row(
                    children: [
                      Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Theme.of(context).primaryColor.withOpacity(0.1), shape: BoxShape.circle), child: Icon(existing == null ? Icons.add_rounded : Icons.edit_rounded, color: Theme.of(context).primaryColor)),
                      const SizedBox(width: 15),
                      Expanded(child: Text(existing == null ? "New Expense" : "Edit Transaction", style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 22))), // ✅ FIXED OVERFLOW
                    ],
                  ),
                  const SizedBox(height: 25),
                  _buildModernInput(titleCtrl, "Title", Icons.title_rounded),
                  const SizedBox(height: 15),
                  _buildModernInput(amountCtrl, "Amount", Icons.attach_money_rounded, isNumber: true),
                  const SizedBox(height: 15),

                  GestureDetector(
                    onTap: () async {
                      final picked = await showDatePicker(
                          context: context,
                          initialDate: selectedDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2030)
                      );
                      if (picked != null) setModalState(() => selectedDate = picked);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(16)),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today_rounded, color: Colors.grey),
                          const SizedBox(width: 15),
                          Text(DateFormat.yMMMd().format(selectedDate), style: const TextStyle(fontWeight: FontWeight.w600)),
                          const Spacer(),
                          const Icon(Icons.arrow_drop_down_rounded)
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 15),

                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.withOpacity(0.1))),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: categories.contains(selectedCategory) ? selectedCategory : (categories.isNotEmpty ? categories.first : "General"),
                        isExpanded: true,
                        icon: const Icon(Icons.keyboard_arrow_down_rounded),
                        items: categories.map((c) => DropdownMenuItem(value: c, child: Row(children: [Icon(Icons.category_rounded, size: 18, color: Theme.of(context).primaryColor), const SizedBox(width: 10), Text(c)]))).toList(),
                        onChanged: (v) => setModalState(() => selectedCategory = v!),
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                  SizedBox(
                    width: double.infinity, height: 55,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).primaryColor, foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                      onPressed: (){
                        final amt = double.tryParse(amountCtrl.text) ?? 0;
                        if(titleCtrl.text.isNotEmpty && amt > 0) {
                          if (existing == null) {
                            ref.read(expenseProvider.notifier).addExpense(Expense(id: const Uuid().v4(), title: titleCtrl.text, amount: amt, date: selectedDate, category: selectedCategory, colorValue: Colors.teal.value));
                          } else {
                            existing.title = titleCtrl.text; existing.amount = amt; existing.category = selectedCategory; existing.date = selectedDate; existing.save(); ref.invalidate(expenseProvider);
                          }
                          Navigator.pop(ctx);
                        }
                      },
                      child: const Text("Save Transaction", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  )
                ],
              ),
            ),
          ),
        )
    );
  }

  Widget _buildModernInput(TextEditingController ctrl, String label, IconData icon, {bool isNumber = false}) {
    return TextField(
      controller: ctrl, keyboardType: isNumber ? TextInputType.number : TextInputType.text, textCapitalization: isNumber ? TextCapitalization.none : TextCapitalization.sentences,
      style: const TextStyle(fontWeight: FontWeight.w600),
      decoration: InputDecoration(labelText: label, labelStyle: const TextStyle(color: Colors.grey), prefixIcon: Icon(icon, color: Colors.grey), filled: true, fillColor: Theme.of(context).cardColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Theme.of(context).primaryColor, width: 2)), contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20)),
    );
  }

  void _editBudget(double currentBudget) {
    final c = TextEditingController(text: currentBudget > 0 ? currentBudget.toStringAsFixed(0) : "");
    showDialog(context: context, builder: (ctx) => AlertDialog(
        scrollable: true,
        title: const Row(
            children: [
              Icon(Icons.savings_rounded, color: Colors.green),
              SizedBox(width: 10),
              Expanded(child: Text("Set Monthly Budget")) // ✅ FIXED OVERFLOW HERE
            ]
        ),
        content: TextField(controller: c, keyboardType: TextInputType.number, decoration: InputDecoration(hintText: "Enter Limit", prefixIcon: const Icon(Icons.currency_rupee_rounded), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
        actions: [ElevatedButton(onPressed: (){ final val = double.tryParse(c.text) ?? 0; ref.read(budgetProvider.notifier).setBudget(val, _focusedMonth); Navigator.pop(ctx); }, child: const Text("Save Budget"))]
    ));
  }

  @override
  Widget build(BuildContext context) {
    final expenseState = ref.watch(expenseProvider);
    final budgetState = ref.watch(budgetProvider);
    final categories = ref.watch(categoryProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final monthKey = DateFormat('yyyy-MM').format(_focusedMonth);
    final double monthlyBudget = budgetState[monthKey] ?? 0.0;
    var expenses = expenseState.allExpenses.where((e) => e.date.month == _focusedMonth.month && e.date.year == _focusedMonth.year).toList();

    if (_selectedCategoryTab != 'All' && !categories.contains(_selectedCategoryTab)) {
      _selectedCategoryTab = 'All';
    }

    if (_selectedCategoryTab != 'All') expenses = expenses.where((e) => e.category == _selectedCategoryTab).toList();
    if (_searchQuery.isNotEmpty) expenses = expenses.where((e) => e.title.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
    expenses.sort((a,b) => b.date.compareTo(a.date));

    double spent = expenseState.allExpenses.where((e) => e.date.month == _focusedMonth.month && e.date.year == _focusedMonth.year).fold(0, (sum, e) => sum + e.amount);
    double remaining = monthlyBudget - spent;
    final primaryColor = Theme.of(context).primaryColor;

    return Scaffold(
      drawer: AppDrawer(currentView: _currentView, onViewChanged: (v)=>setState(()=>_currentView=v)),
      appBar: AppBar(
        title: _isSearching ? TextField(autofocus: true, decoration: const InputDecoration(border: InputBorder.none, hintText: "Search transactions..."), onChanged: (v)=>setState(()=>_searchQuery=v)) : Text(_currentView, style: const TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        leading: Builder(builder: (context) => IconButton(icon: const Icon(Icons.menu_rounded), onPressed: () => Scaffold.of(context).openDrawer())),
        actions: [if(_currentView=='Dashboard') IconButton(icon: Icon(_isSearching?Icons.close_rounded:Icons.search_rounded), onPressed: ()=>setState(()=>_isSearching=!_isSearching))],
      ),
      body: Column(
        children: [
          if (_currentView == 'Dashboard' && !_isSearching) ...[
            _buildMonthSelector(isDark),
            _buildHeroCard(monthlyBudget, remaining, spent),
            Container(
              height: 50, margin: const EdgeInsets.symmetric(vertical: 10),
              child: ListView(controller: _categoryScrollCtrl, scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [_buildTab('All', 0, isDark), ...List.generate(categories.length, (i) => _buildTab(categories[i], i + 1, isDark))]),
            ),
          ],
          // ... inside HomeScreen build method ...

          Expanded(
            child: AnimatedSwitcher(
              // ✅ SMOOTH STATE TRANSITION
              duration: const Duration(milliseconds: 400),
              switchInCurve: Curves.easeOutQuart,
              switchOutCurve: Curves.easeInQuart,
              transitionBuilder: (Widget child, Animation<double> animation) {
                // Subtle Fade + Slide + Scale for modern feel
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(begin: const Offset(0.05, 0), end: Offset.zero).animate(animation),
                    child: child,
                  ),
                );
              },
              child: KeyedSubtree(
                key: ValueKey<String>(_currentView), // 🔑 Key ensures animation triggers
                child: _buildBody(expenses),
              ),
            ),
          ),

// ... rest of code
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: _currentView == 'Dashboard' ? GestureDetector(
        onTapDown: (_) => _fabController.forward(),
        onTapUp: (_) { _fabController.reverse(); _showAddOrEditModal(); },
        onTapCancel: () => _fabController.reverse(),
        child: ScaleTransition(
          scale: _fabScale,
          child: Container(
            height: 60, padding: const EdgeInsets.symmetric(horizontal: 25),
            decoration: BoxDecoration(gradient: LinearGradient(colors: [primaryColor, primaryColor.withOpacity(0.8)], begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(30), boxShadow: [BoxShadow(color: primaryColor.withOpacity(0.4), blurRadius: 15, offset: const Offset(0, 8))]),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.add_rounded, color: Colors.white, size: 28), SizedBox(width: 10), Text("Add Expense", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))]),
          ),
        ),
      ) : null,
    );
  }

  Widget _buildTab(String label, int index, bool isDark) {
    bool isSelected = _selectedCategoryTab == label;
    return GestureDetector(
        onTap: () => _selectCategory(label, index),
        onLongPress: () {
          if (label == 'All') return;
          showDialog(context: context, builder: (ctx) => AlertDialog(
            title: const Text("Delete Category?"), content: Text("Are you sure you want to delete '$label'?"),
            actions: [
              TextButton(onPressed: ()=>Navigator.pop(ctx), child: const Text("Cancel")),
              TextButton(onPressed: (){
                ref.read(categoryProvider.notifier).deleteCategory(label);
                Navigator.pop(ctx);
              }, child: const Text("Delete", style: TextStyle(color: Colors.red)))
            ],
          ));
        },
        child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.only(right: 10), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(color: isSelected ? Theme.of(context).primaryColor : Theme.of(context).cardColor, borderRadius: BorderRadius.circular(30), border: isSelected ? null : Border.all(color: Colors.grey.withOpacity(0.2))),
            child: Center(child: Text(label, style: TextStyle(color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87), fontWeight: FontWeight.w600)))
        )
    );
  }

  Widget _buildBody(List<Expense> expenses) {
    if (_currentView == 'Tasks') return const ToDoScreen();
    if (_currentView == 'Tools') return const UtilitiesScreen();
    if (_currentView == 'Udhaar') return const DebtScreen();
    if (_currentView == 'Stats') return const StatsScreen();
    if (_currentView == 'Settings') return const SettingsScreen();
    if (_currentView == 'About') return const AboutScreen();

    if (expenses.isEmpty) return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.receipt_long_rounded, size: 64, color: Colors.grey.withOpacity(0.3)), const SizedBox(height: 16), const Text("No expenses here yet!", style: TextStyle(color: Colors.grey))]));

    return ListView.builder(
        itemCount: expenses.length, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        itemBuilder: (ctx, i) {
          final e = expenses[i];
          return Dismissible(
            key: Key(e.id),
            background: Container(alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), color: Colors.red, child: const Icon(Icons.delete, color: Colors.white)),
            onDismissed: (direction) { e.delete(); ref.invalidate(expenseProvider); },
            child: Card(
                elevation: 0, color: Theme.of(context).cardColor, margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.grey.withOpacity(0.1))),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Color(e.colorValue).withOpacity(0.15), shape: BoxShape.circle), child: Icon(Icons.category_rounded, color: Color(e.colorValue))),
                  title: Text(e.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Row(children: [const Icon(Icons.calendar_today_rounded, size: 12, color: Colors.grey), const SizedBox(width: 4), Text(DateFormat.MMMd().format(e.date), style: const TextStyle(fontSize: 12, color: Colors.grey))]),
                  trailing: Text("Rs. ${e.amount.toStringAsFixed(0)}", style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  onTap: () => _showAddOrEditModal(existing: e),
                )
            ),
          );
        }
    );
  }

  Widget _buildHeroCard(double b, double r, double s) {
    final primary = Theme.of(context).primaryColor;
    bool isAlert = b > 0 && s > b;
    return AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        width: double.infinity, margin: const EdgeInsets.symmetric(horizontal: 20), padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(gradient: LinearGradient(colors: isAlert ? [Colors.red.shade900, Colors.red] : [primary, primary.withOpacity(0.8)], begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(28), boxShadow: [BoxShadow(color: (isAlert ? Colors.red : primary).withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 10))]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            // ✅ FIXED OVERFLOW IN CARD HEADER
            Expanded(child: Text(isAlert ? "Limit Exceeded!" : "Remaining Balance", style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w500))),
            Icon(isAlert ? Icons.warning_amber_rounded : Icons.account_balance_wallet_rounded, color: Colors.white70)
          ]),
          b == 0
              ? GestureDetector(onTap: () => _editBudget(b), child: const Row(children: [Text("Set Budget", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)), SizedBox(width: 8), Icon(Icons.edit_rounded, color: Colors.white, size: 20)]))
              : Text("Rs. ${r.abs().toStringAsFixed(0)}", style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900)),
          const SizedBox(height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            GestureDetector(onTap: () => _editBudget(b), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [Text("Budget Limit", style: TextStyle(color: Colors.white70, fontSize: 12)), SizedBox(width: 4), Icon(Icons.edit_outlined, color: Colors.white70, size: 12)]),
              Text(b.toStringAsFixed(0), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
            ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              const Text("Total Spent", style: TextStyle(color: Colors.white70, fontSize: 12)),
              Text(s.toStringAsFixed(0), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
            ]),
          ])
        ])
    );
  }

  Widget _buildMonthSelector(bool isDark) { return Row(mainAxisAlignment: MainAxisAlignment.center, children: [IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18), onPressed: ()=>setState(()=>_focusedMonth=DateTime(_focusedMonth.year, _focusedMonth.month-1, 1))), Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.grey.withOpacity(0.1))), child: Text(DateFormat.yMMMM().format(_focusedMonth), style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isDark?Colors.white:Colors.black))), IconButton(icon: const Icon(Icons.arrow_forward_ios_rounded, size: 18), onPressed: ()=>setState(()=>_focusedMonth=DateTime(_focusedMonth.year, _focusedMonth.month+1, 1)))]); }
}