import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:quick_actions/quick_actions.dart';

import "../services/notification_service.dart";
import 'package:flutter/services.dart';

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
import '../services/local_nlp_service.dart';
import "../services/ocr_scanner_service.dart";
import "./insights_screen.dart";
import "./mess_khata_screen.dart";
import "./recurring_bills_screen.dart";

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with SingleTickerProviderStateMixin {

  static const platform = MethodChannel('com.likhlo/quick_tile');
  String _currentView = 'Dashboard';
  DateTime _focusedMonth = DateTime.now();
  String _selectedCategoryTab = 'All';
  bool _isSearching = false;
  String _searchQuery = "";
  final ScrollController _categoryScrollCtrl = ScrollController();

  late AnimationController _fabController;
  late Animation<double> _fabScale;

  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  final TextEditingController _smartInputCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fabController = AnimationController(vsync: this, duration: const Duration(milliseconds: 200), lowerBound: 0.0, upperBound: 0.1);
    _fabScale = Tween<double>(begin: 1.0, end: 0.95).animate(_fabController);

    // ✅ NEW: Setup Homescreen Quick Actions
    const QuickActions quickActions = QuickActions();
    quickActions.initialize((String shortcutType) {
      // Add a slight delay to ensure the UI is fully mounted before triggering dialogs/mic
      Future.delayed(const Duration(milliseconds: 400), () {
        if (shortcutType == 'action_voice_log') {
          _listenForExpense();
        } else if (shortcutType == 'action_add_expense') {
          _showAddOrEditModal();
        }
      });
    });

    // Define the items that appear when you long-press the app icon
    quickActions.setShortcutItems(<ShortcutItem>[
      const ShortcutItem(
          type: 'action_voice_log',
          localizedTitle: 'Voice Log',
          icon: 'ic_mic' // Note: For Android, this needs to match a drawable icon name if you want a specific icon, otherwise it falls back nicely.
      ),
      const ShortcutItem(
          type: 'action_add_expense',
          localizedTitle: 'Add Expense',
          icon: 'ic_add'
      ),
    ]);
    _setupNativeQuickTile();
  }
  void _setupNativeQuickTile() {
    // Scenario A: App launched from a dead state
    platform.invokeMethod<String>('getQuickAction').then((action) {
      if (action == 'add_expense') {
        Future.delayed(const Duration(milliseconds: 500), () => _showAddOrEditModal());
      }
    }).catchError((e) => print("Quick Tile Error: $e"));

    // Scenario B: App was in the background and brought forward
    platform.setMethodCallHandler((call) async {
      if (call.method == 'triggerAction' && call.arguments == 'add_expense') {
        _showAddOrEditModal();
      }
    });
  }

  @override
  void dispose() {
    _fabController.dispose();
    _categoryScrollCtrl.dispose();
    _smartInputCtrl.dispose();
    super.dispose();
  }

  void _selectCategory(String category, int index) {
    setState(() => _selectedCategoryTab = category);
    double offset = (index * 70.0) - (MediaQuery.of(context).size.width / 2) + 35;
    if (offset < 0) offset = 0;
    if (_categoryScrollCtrl.hasClients) {
      _categoryScrollCtrl.animateTo(offset, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  // ==================== NEW: ADD CATEGORY DIALOG ====================
  void _showAddCategoryDialog() {
    final catCtrl = TextEditingController();
    final primaryColor = Color(ref.read(settingsProvider).profileColorValue);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        insetPadding: const EdgeInsets.all(20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: primaryColor.withOpacity(0.15), shape: BoxShape.circle),
                child: Icon(Icons.category_rounded, color: primaryColor, size: 20)
            ),
            const SizedBox(width: 12),
            const Expanded(child: Text("New Category", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
          ],
        ),
        content: _buildModernInput(catCtrl, "Category Name", Icons.new_label_rounded, primaryColor),
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        actions: [
          Row(
            children: [
              Expanded(child: TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel", style: TextStyle(color: Colors.grey)))),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: primaryColor, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(vertical: 12)),
                  onPressed: () {
                    if (catCtrl.text.trim().isNotEmpty) {
                      ref.read(categoryProvider.notifier).addCategory(catCtrl.text.trim());
                      Navigator.pop(ctx);
                      // Scroll to end so user sees new category
                      Future.delayed(const Duration(milliseconds: 300), () {
                        if (_categoryScrollCtrl.hasClients) {
                          _categoryScrollCtrl.animateTo(_categoryScrollCtrl.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
                        }
                      });
                    }
                  },
                  child: const Text("Save"),
                ),
              ),
            ],
          )
        ],
      ),
    );
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

    final settings = ref.read(settingsProvider);
    final primaryColor = Color(settings.profileColorValue);

    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => StatefulBuilder(
          builder: (context, setModalState) => Container(
            decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 30, offset: const Offset(0, -10))]
            ),
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom + 24, left: 24, right: 24, top: 12),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 48, height: 4, decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3), borderRadius: BorderRadius.circular(2)), margin: const EdgeInsets.only(bottom: 24)),
                  Row(
                    children: [
                      Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: primaryColor.withOpacity(0.15), shape: BoxShape.circle), child: Icon(existing == null ? Icons.add_rounded : Icons.edit_rounded, color: primaryColor, size: 22)),
                      const SizedBox(width: 16),
                      Expanded(child: Text(existing == null ? "New Expense" : "Edit Transaction", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _buildModernInput(titleCtrl, "Title", Icons.title_rounded, primaryColor),
                  const SizedBox(height: 12),
                  _buildModernInput(amountCtrl, "Amount", Icons.attach_money_rounded, primaryColor, isNumber: true),
                  const SizedBox(height: 12),

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
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(16)),
                      child: Row(
                        children: [
                          Icon(Icons.calendar_today_rounded, color: Colors.grey.shade500, size: 20),
                          const SizedBox(width: 12),
                          Text(DateFormat.yMMMd().format(selectedDate), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                          const Spacer(),
                          Icon(Icons.arrow_drop_down_rounded, color: Colors.grey.shade500)
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(16)),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: categories.contains(selectedCategory) ? selectedCategory : (categories.isNotEmpty ? categories.first : "General"),
                        isExpanded: true,
                        icon: Icon(Icons.keyboard_arrow_down_rounded, color: Colors.grey.shade500),
                        items: categories.map((c) => DropdownMenuItem(value: c, child: Row(children: [Icon(Icons.category_rounded, size: 18, color: primaryColor), const SizedBox(width: 12), Text(c, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500))]))).toList(),
                        onChanged: (v) => setModalState(() => selectedCategory = v!),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity, height: 52,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: primaryColor, foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                      onPressed: () {
                        final amt = double.tryParse(amountCtrl.text) ?? 0;
                        if(titleCtrl.text.isNotEmpty && amt > 0) {
                          if (existing == null) {
                            ref.read(expenseProvider.notifier).addExpense(Expense(id: const Uuid().v4(), title: titleCtrl.text, amount: amt, date: selectedDate, category: selectedCategory, colorValue: primaryColor.value));
                          } else {
                            final updatedExpense = Expense(id: existing.id, title: titleCtrl.text, amount: amt, date: selectedDate, category: selectedCategory, colorValue: existing.colorValue);
                            ref.read(expenseProvider.notifier).editExpense(existing.id, updatedExpense);
                          }

                          // 🚀 NEW: Resets the daily 8 PM reminder since you logged an entry!
                          try {
                            NotificationService().cancelAll();
                            NotificationService().scheduleDailyReminder();
                          } catch (e) {
                            print("Notification reset failed: $e");
                          }

                          Navigator.pop(ctx);
                        }
                      },
                      child: const Text("Save Transaction", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    ),
                  )
                ],
              ),
            ),
          ),
        )
    );
  }

  Widget _buildModernInput(TextEditingController ctrl, String label, IconData icon, Color primaryColor, {bool isNumber = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextField(
      controller: ctrl,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      textCapitalization: isNumber ? TextCapitalization.none : TextCapitalization.sentences,
      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: Colors.grey.shade500, fontSize: 13),
          prefixIcon: Icon(icon, color: Colors.grey.shade500, size: 20),
          filled: true,
          fillColor: Theme.of(context).cardColor,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: primaryColor, width: 1.5)),
          contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16)
      ),
    );
  }

  void _editBudget(double currentBudget) {
    final c = TextEditingController(text: currentBudget > 0 ? currentBudget.toStringAsFixed(0) : "");
    final primaryColor = Color(ref.read(settingsProvider).profileColorValue);

    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
            insetPadding: const EdgeInsets.all(20),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: Row(
                children: [
                  Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.green.withOpacity(0.15), shape: BoxShape.circle), child: const Icon(Icons.savings_rounded, color: Colors.green, size: 20)),
                  const SizedBox(width: 12),
                  const Expanded(child: Text("Monthly Limit", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)))
                ]
            ),
            content: _buildModernInput(c, "Enter Budget Limit", Icons.currency_rupee_rounded, primaryColor, isNumber: true),
            actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            actions: [
              Row(
                children: [
                  Expanded(child: TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel", style: TextStyle(color: Colors.grey)))),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: primaryColor, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(vertical: 12)),
                      onPressed: (){ final val = double.tryParse(c.text) ?? 0; ref.read(budgetProvider.notifier).setBudget(val, _focusedMonth); Navigator.pop(ctx); },
                      child: const Text("Save"),
                    ),
                  ),
                ],
              )
            ]
        ));
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final expenseState = ref.watch(expenseProvider);
    final budgetState = ref.watch(budgetProvider);
    final categories = ref.watch(categoryProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Color(settings.profileColorValue);

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

    return Scaffold(
      drawer: AppDrawer(currentView: _currentView, onViewChanged: (v)=>setState(()=>_currentView=v)),
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        title: _isSearching ? TextField(
            autofocus: true,
            style: const TextStyle(fontSize: 15),
            decoration: InputDecoration(border: InputBorder.none, hintText: "Search transactions...", hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14)),
            onChanged: (v)=>setState(()=>_searchQuery=v)
        ) : Text(_currentView, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        centerTitle: true,
        leading: Builder(builder: (context) => IconButton(icon: const Icon(Icons.menu_rounded, size: 24), onPressed: () => Scaffold.of(context).openDrawer())),
        actions: [
          if(_currentView=='Dashboard')
            IconButton(icon: Icon(_isSearching ? Icons.close_rounded : Icons.search_rounded, size: 22), onPressed: ()=>setState(()=>_isSearching=!_isSearching))
        ],
      ),
      body: Column(
        children: [
          if (_currentView == 'Dashboard' && !_isSearching) ...[
            _buildMonthSelector(isDark),
            const SizedBox(height: 12),
            _buildHeroCard(monthlyBudget, remaining, spent, primaryColor),

            // 🎙️ SLEEK SMART ENTRY WIDGET
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: isDark ? primaryColor.withOpacity(0.3) : Colors.grey.withOpacity(0.15),
                    width: 1.2,
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      padding: EdgeInsets.zero,
                      icon: Icon(
                        _isListening ? Icons.mic : Icons.mic_none_rounded,
                        size: 20,
                        color: _isListening ? Colors.red : (isDark ? Colors.white70 : primaryColor),
                      ),
                      onPressed: _listenForExpense,
                    ),
                    Expanded(
                      child: TextField(
                        controller: _smartInputCtrl,
                        style: const TextStyle(fontSize: 13),
                        decoration: InputDecoration(
                            hintText: _isListening ? 'Listening...' : 'Speak/Type: "1500 for Pizza"',
                            border: InputBorder.none,
                            isDense: true,
                            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 12)
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
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      padding: EdgeInsets.zero,
                      icon: Icon(Icons.send_rounded, color: primaryColor, size: 18),
                      onPressed: () => _processNLP(_smartInputCtrl.text),
                    ),
                  ],
                ),
              ),
            ),

            // CATEGORY TABS WITH "ADD" BUTTON
            Container(
              height: 40, margin: const EdgeInsets.only(top: 8, bottom: 4),
              child: ListView(
                  controller: _categoryScrollCtrl,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    _buildTab('All', 0, isDark, primaryColor),
                    ...List.generate(categories.length, (i) => _buildTab(categories[i], i + 1, isDark, primaryColor)),
                    _buildAddCategoryBtn(primaryColor, isDark) // ➕ Add Button appended at the end
                  ]
              ),
            ),
          ],

          const SizedBox(height: 4),

          // LIST VIEW
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (Widget child, Animation<double> animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(begin: const Offset(0.02, 0), end: Offset.zero).animate(animation),
                    child: child,
                  ),
                );
              },
              child: KeyedSubtree(
                key: ValueKey<String>(_currentView),
                child: _buildBody(expenses, primaryColor, isDark),
              ),
            ),
          ),
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
            height: 52, padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(gradient: LinearGradient(colors: [primaryColor, primaryColor.withOpacity(0.8)], begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(26), boxShadow: [BoxShadow(color: primaryColor.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 6))]),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.add_rounded, color: Colors.white, size: 22), SizedBox(width: 8), Text("Add Expense", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14))]),
          ),
        ),
      ) : null,
    );
  }

  // ==================== NEW: ADD CATEGORY BUTTON ====================
  Widget _buildAddCategoryBtn(Color primaryColor, bool isDark) {
    return GestureDetector(
      onTap: _showAddCategoryDialog,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.withOpacity(0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isDark ? Colors.white24 : Colors.grey.shade300, width: 1.2),
        ),
        child: Row(
          children: [
            Icon(Icons.add_rounded, size: 16, color: isDark ? Colors.white70 : Colors.black87),
            const SizedBox(width: 4),
            Text("New", style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontWeight: FontWeight.bold, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildTab(String label, int index, bool isDark, Color primaryColor) {
    bool isSelected = _selectedCategoryTab == label;
    return GestureDetector(
        onTap: () => _selectCategory(label, index),
        onLongPress: () {
          if (label == 'All') return;
          // Polished Delete Category Dialog
          showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                insetPadding: const EdgeInsets.all(20),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                title: Row(
                  children: [
                    Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.red.withOpacity(0.15), shape: BoxShape.circle), child: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 20)),
                    const SizedBox(width: 12),
                    const Expanded(child: Text("Delete Category?", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                  ],
                ),
                content: Text("Are you sure you want to permanently delete '$label'?\nTransactions under this category will remain, but the filter will be removed.", style: TextStyle(fontSize: 14, color: Colors.grey.shade500, height: 1.4)),
                actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                actions: [
                  Row(
                    children: [
                      Expanded(child: TextButton(onPressed: ()=>Navigator.pop(ctx), child: const Text("Cancel", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)))),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                            onPressed: (){
                              ref.read(categoryProvider.notifier).deleteCategory(label);
                              if(_selectedCategoryTab == label) setState(() => _selectedCategoryTab = 'All');
                              Navigator.pop(ctx);
                            },
                            child: const Text("Delete", style: TextStyle(fontWeight: FontWeight.bold))
                        ),
                      ),
                    ],
                  )
                ],
              ));
        },
        child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
                color: isSelected ? primaryColor : Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(20),
                border: isSelected ? null : Border.all(color: isDark ? primaryColor.withOpacity(0.25) : Colors.grey.withOpacity(0.15), width: 1.2)
            ),
            child: Center(
              child: Text(
                label,
                style: TextStyle(color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87), fontWeight: isSelected ? FontWeight.bold : FontWeight.w600, fontSize: 12),
              ),
            )
        )
    );
  }

  Widget _buildBody(List<Expense> expenses, Color primaryColor, bool isDark) {
    if (_currentView == 'Insights') return const InsightsScreen();
    if (_currentView == 'Tasks') return const ToDoScreen();
    if (_currentView == 'Mess Khata') return const MessKhataScreen();
    if (_currentView == 'Recurring Bills') return const RecurringBillsScreen();
    if (_currentView == 'Tools') return const UtilitiesScreen();
    if (_currentView == 'Udhaar') return const DebtScreen();
    if (_currentView == 'Stats') return const StatsScreen();
    if (_currentView == 'Settings') return const SettingsScreen();
    if (_currentView == 'About') return const AboutScreen();

    if (expenses.isEmpty) {
      return Center(
          child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.receipt_long_rounded, size: 50, color: Colors.grey.withOpacity(0.3)),
                const SizedBox(height: 12),
                Text("No expenses here yet.", style: TextStyle(color: Colors.grey.shade500, fontSize: 13))
              ]
          )
      );
    }

    return ListView.builder(
        itemCount: expenses.length, padding: const EdgeInsets.fromLTRB(20, 8, 20, 80),
        itemBuilder: (ctx, i) {
          final e = expenses[i];
          final eColor = Color(e.colorValue);

          return Dismissible(
            key: Key(e.id),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(18)),
              child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
            ),
            confirmDismiss: (direction) async {
              return await showDialog(
                context: context,
                builder: (dialogCtx) => Dialog(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  elevation: 0,
                  backgroundColor: Theme.of(context).cardColor,
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), shape: BoxShape.circle), child: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 28)),
                        const SizedBox(height: 16),
                        const Text("Delete Transaction?", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Text("Are you sure you want to delete '${e.title}'? This action cannot be undone.", textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Colors.grey.shade500, height: 1.4)),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Expanded(child: TextButton(style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), onPressed: () => Navigator.of(dialogCtx).pop(false), child: const Text("Cancel", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)))),
                            const SizedBox(width: 12),
                            Expanded(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), onPressed: () => Navigator.of(dialogCtx).pop(true), child: const Text("Delete", style: TextStyle(fontWeight: FontWeight.bold)))),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
            onDismissed: (direction) {
              // 🚀 FIX: Use Riverpod notifier to delete, avoiding broken data states
              ref.read(expenseProvider.notifier).deleteExpense(e.id);

              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text("Deleted '${e.title}'", style: const TextStyle(fontSize: 13)),
                  backgroundColor: Colors.red,
                  duration: const Duration(seconds: 2)
              ));
            },
            child: GestureDetector(
              onTap: () => _showAddOrEditModal(existing: e),
              child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: isDark ? primaryColor.withOpacity(0.2) : Colors.grey.withOpacity(0.12), width: 1.2),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: eColor.withOpacity(0.15), shape: BoxShape.circle),
                        child: Icon(Icons.category_rounded, color: eColor, size: 20),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(e.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 4),
                            Row(children: [
                              Icon(Icons.schedule_rounded, size: 11, color: Colors.grey.shade500),
                              const SizedBox(width: 4),
                              Text(DateFormat.MMMEd().format(e.date), style: TextStyle(fontSize: 11, color: Colors.grey.shade500))
                            ]),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text("Rs. ${e.amount.toStringAsFixed(0)}", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                    ],
                  )
              ),
            ),
          );
        }
    );
  }

  Widget _buildHeroCard(double b, double r, double s, Color primary) {
    bool isAlert = b > 0 && s > b;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isAlert ? [Colors.red.shade900, Colors.red] : [primary, primary.withOpacity(0.75)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(color: (isAlert ? Colors.red : primary).withOpacity(0.35), blurRadius: 18, offset: const Offset(0, 8))
          ]
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                isAlert ? "Limit Exceeded!" : "Remaining Balance",
                style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w500, fontSize: 13),
              ),
              Icon(
                isAlert ? Icons.warning_amber_rounded : Icons.account_balance_wallet_rounded,
                color: Colors.white70, size: 20,
              ),
            ],
          ),
          const SizedBox(height: 6),
          b == 0
              ? GestureDetector(
            onTap: () => _editBudget(b),
            child: const Row(
              children: [
                Text("Set Limit", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                SizedBox(width: 6),
                Icon(Icons.edit_rounded, color: Colors.white, size: 18),
              ],
            ),
          )
              : Text("Rs. ${r.abs().toStringAsFixed(0)}", style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: -0.5)),

          const SizedBox(height: 24),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: () => _editBudget(b),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text("Budget Limit", style: TextStyle(color: Colors.white.withOpacity(0.65), fontSize: 11)),
                        const SizedBox(width: 4),
                        Icon(Icons.edit_outlined, color: Colors.white.withOpacity(0.65), size: 10),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(b.toStringAsFixed(0), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14))
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text("Total Spent", style: TextStyle(color: Colors.white.withOpacity(0.65), fontSize: 11)),
                  const SizedBox(height: 2),
                  Text(s.toStringAsFixed(0), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                ],
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildMonthSelector(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 16), onPressed: ()=>setState(()=>_focusedMonth=DateTime(_focusedMonth.year, _focusedMonth.month-1, 1))),
            Text(DateFormat.yMMMM().format(_focusedMonth), style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: isDark?Colors.white:Colors.black87)),
            IconButton(icon: const Icon(Icons.arrow_forward_ios_rounded, size: 16), onPressed: ()=>setState(()=>_focusedMonth=DateTime(_focusedMonth.year, _focusedMonth.month+1, 1)))
          ]
      ),
    );
  }

  void _listenForExpense() async {
    if (!_isListening) {
      bool available = await _speech.initialize(
        onStatus: (val) {
          if (val == 'done' || val == 'notListening') {
            setState(() => _isListening = false);
            if (_smartInputCtrl.text.isNotEmpty) {
              _processNLP(_smartInputCtrl.text);
            }
          }
        },
        onError: (val) => print('STT Error: $val'),
      );
      if (available) {
        setState(() => _isListening = true);
        _smartInputCtrl.text = "Listening...";
        _speech.listen(onResult: (val) => setState(() { _smartInputCtrl.text = val.recognizedWords; }));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Speech recognition denied/unavailable.", style: TextStyle(fontSize: 13))));
      }
    } else {
      setState(() => _isListening = false);
      _speech.stop();
    }
  }

  void _processNLP(String text) {
    if (text.isEmpty || text == "Listening...") return;
    final categories = ref.read(categoryProvider);
    final result = LocalNlpService().parseExpense(text, categories);

    if (result['amount'] > 0) {
      final newExpense = Expense(
        id: const Uuid().v4(),
        title: result['title'],
        amount: result['amount'],
        category: result['category'],
        date: DateTime.now(),
        colorValue: Colors.purple.value,
      );

      ref.read(expenseProvider.notifier).addExpense(newExpense);

      // 🚀 NEW: Resets the daily 8 PM reminder since you logged an entry via Voice/Text!
      try {
        NotificationService().cancelAll();
        NotificationService().scheduleDailyReminder();
      } catch (e) {
        print("Notification reset failed: $e");
      }

      _smartInputCtrl.clear();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("✅ Saved: ${result['title']} (Rs. ${result['amount'].toStringAsFixed(0)})", style: const TextStyle(fontSize: 13)),
          backgroundColor: Colors.green
      ));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("❌ Could not detect amount. Try: '500 for biryani'.", style: TextStyle(fontSize: 13)),
          backgroundColor: Colors.red
      ));
    }
    FocusScope.of(context).unfocus();
  }

  void _startReceiptScan() async {
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => Center(child: Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(20)), child: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(color: Theme.of(context).primaryColor), const SizedBox(height: 16), const Text("Processing Receipt...", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14))]))));

    final receiptData = await OcrScannerService().scanReceipt();
    if (mounted) Navigator.pop(context);

    if (receiptData != null && receiptData['amount'] > 0) {
      ref.read(expenseProvider.notifier).addExpense(Expense(id: const Uuid().v4(), title: receiptData['title'], amount: receiptData['amount'], category: receiptData['category'], date: DateTime.now(), colorValue: Colors.blueAccent.value));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("✅ Saved: ${receiptData['title']} (Rs. ${receiptData['amount'].toStringAsFixed(0)})", style: const TextStyle(fontSize: 13)), backgroundColor: Colors.green));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("❌ Could not read receipt clearly. Try manual entry.", style: TextStyle(fontSize: 13)), backgroundColor: Colors.red));
    }
  }
}