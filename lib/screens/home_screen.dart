import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:quick_actions/quick_actions.dart';
import 'package:flutter/services.dart';

import "../services/notification_service.dart";
import '../providers/expense_provider.dart';
import '../providers/budget_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/category_provider.dart';
import '../providers/wallet_provider.dart';
import '../models/expense_model.dart';
import '../models/wallet_model.dart';
import '../widgets/app_drawer.dart';
import '../widgets/ai_chat_overlay.dart';

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
import './income_accounts_screen.dart';

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
  bool _voiceResultProcessed = false;
  final TextEditingController _smartInputCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fabController = AnimationController(vsync: this, duration: const Duration(milliseconds: 200), lowerBound: 0.0, upperBound: 0.1);
    _fabScale = Tween<double>(begin: 1.0, end: 0.95).animate(_fabController);

    const QuickActions quickActions = QuickActions();
    quickActions.initialize((String shortcutType) {
      Future.delayed(const Duration(milliseconds: 400), () {
        if (shortcutType == 'action_voice_log') {
          _listenForExpense();
        } else if (shortcutType == 'action_add_expense') {
          _showAddOrEditModal();
        }
      });
    });

    quickActions.setShortcutItems(<ShortcutItem>[
      const ShortcutItem(type: 'action_voice_log', localizedTitle: 'Voice Log', icon: 'ic_mic'),
      const ShortcutItem(type: 'action_add_expense', localizedTitle: 'Add Transaction', icon: 'ic_add'),
    ]);
    _setupNativeQuickTile();
    NotificationService().onActionTriggered = _handleNotificationAction;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pendingAction = NotificationService().takePendingAction();
      if (pendingAction != null) _handleNotificationAction(pendingAction);
    });
  }

  void _handleNotificationAction(String action) {
    if (!mounted) return;
    if (action == 'action_voice_log') {
      _listenForExpense();
    } else if (action == 'action_add_expense') {
      _showAddOrEditModal();
    }
  }

  void _setupNativeQuickTile() {
    platform.invokeMethod<String>('getQuickAction').then((action) {
      if (action == 'add_expense') {
        Future.delayed(const Duration(milliseconds: 500), () => _showAddOrEditModal());
      }
    }).catchError((e) => debugPrint("Quick Tile Error: $e"));

    platform.setMethodCallHandler((call) async {
      if (call.method == 'triggerAction' && call.arguments == 'add_expense') {
        _showAddOrEditModal();
      }
    });
  }

  @override
  void dispose() {
    NotificationService().onActionTriggered = null;
    _speech.cancel();
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

  // ==================== 🧮 INSTANT CALCULATOR BOTTOM SHEET ====================
  void _showCalculator() {
    String calcDisplay = '0';
    double? firstOperand;
    String? operator;
    bool shouldClear = false;

    final primaryColor = Color(ref.read(settingsProvider).profileColorValue);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    void onButtonTap(String value, StateSetter setModalState) {
      setModalState(() {
        if (value == 'C') {
          calcDisplay = '0';
          firstOperand = null;
          operator = null;
        } else if (value == '+' || value == '-' || value == '×' || value == '÷') {
          firstOperand = double.tryParse(calcDisplay);
          operator = value;
          shouldClear = true;
        } else if (value == '=') {
          if (firstOperand != null && operator != null) {
            double secondOperand = double.tryParse(calcDisplay) ?? 0;
            double result = 0;
            if (operator == '+') result = firstOperand! + secondOperand;
            if (operator == '-') result = firstOperand! - secondOperand;
            if (operator == '×') result = firstOperand! * secondOperand;
            if (operator == '÷') result = secondOperand != 0 ? firstOperand! / secondOperand : 0;

            calcDisplay = result.toStringAsFixed(result.truncateToDouble() == result ? 0 : 2);
            firstOperand = null;
            operator = null;
            shouldClear = true;
          }
        } else {
          if (calcDisplay == '0' || shouldClear) {
            calcDisplay = value;
            shouldClear = false;
          } else {
            calcDisplay += value;
          }
        }
      });
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 48, height: 4, decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3), borderRadius: BorderRadius.circular(2)), margin: const EdgeInsets.only(bottom: 24)),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(20), border: Border.all(color: primaryColor.withOpacity(0.2))),
                child: Text(calcDisplay, textAlign: TextAlign.right, style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
              ),
              const SizedBox(height: 20),

              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.2),
                itemCount: 16,
                itemBuilder: (context, index) {
                  final buttons = ['7','8','9','÷', '4','5','6','×', '1','2','3','-', 'C','0','=','+'];
                  final btn = buttons[index];
                  final isOp = ['÷', '×', '-', '+', '='].contains(btn);
                  final isClear = btn == 'C';

                  return GestureDetector(
                    onTap: () => onButtonTap(btn, setModalState),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isOp ? primaryColor : (isClear ? Colors.red.withOpacity(0.1) : Theme.of(context).cardColor),
                        borderRadius: BorderRadius.circular(16),
                        border: isOp || isClear ? null : Border.all(color: Colors.grey.withOpacity(0.1)),
                      ),
                      child: Center(
                        child: Text(btn, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: isOp ? Colors.white : (isClear ? Colors.red : (isDark ? Colors.white : Colors.black87)))),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity, height: 52,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.check_rounded, color: Colors.white),
                  style: ElevatedButton.styleFrom(backgroundColor: primaryColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _showAddOrEditModal(prefilledAmount: calcDisplay);
                  },
                  label: const Text("Use Result", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  // ==================== MISSING DIALOG METHODS ====================
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
            Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: primaryColor.withOpacity(0.15), shape: BoxShape.circle), child: Icon(Icons.category_rounded, color: primaryColor, size: 20)),
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
                      final added = ref
                          .read(categoryProvider.notifier)
                          .addCategory(catCtrl.text.trim());
                      if (!added) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('That category already exists.'),
                          ),
                        );
                        return;
                      }
                      Navigator.pop(ctx);
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

  void _showWalletDialog({Wallet? existing}) {
    final nameCtrl = TextEditingController(text: existing?.name ?? "");
    final primaryColor = Color(ref.read(settingsProvider).profileColorValue);
    bool isBackup = existing?.isBackup ?? false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          insetPadding: const EdgeInsets.all(20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Row(
            children: [
              Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: primaryColor.withOpacity(0.15), shape: BoxShape.circle), child: Icon(Icons.account_balance_wallet_rounded, color: primaryColor, size: 20)),
              const SizedBox(width: 12),
              Expanded(child: Text(existing == null ? "New Fund Source" : "Edit Fund Source", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildModernInput(nameCtrl, "Source Name (e.g. JazzCash)", Icons.payment_rounded, primaryColor),
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text("Backup / Reserve Stash", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                subtitle: const Text("Isolate from daily safe spend calculations", style: TextStyle(fontSize: 11, color: Colors.grey)),
                value: isBackup,
                activeColor: primaryColor,
                onChanged: (val) => setDialogState(() => isBackup = val),
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
                    style: ElevatedButton.styleFrom(backgroundColor: primaryColor, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(vertical: 12)),
                    onPressed: () {
                      if (nameCtrl.text.trim().isNotEmpty) {
                        if (existing == null) {
                          final newWallet = Wallet(
                            id: const Uuid().v4(),
                            name: nameCtrl.text.trim(),
                            balance: 0.0,
                            isBackup: isBackup,
                            colorValue: primaryColor.value,
                            walletType: 'custom',
                          );
                          ref.read(walletProvider.notifier).addWallet(newWallet);
                        } else {
                          final updated = existing.copyWith(name: nameCtrl.text.trim(), isBackup: isBackup);
                          ref.read(walletProvider.notifier).updateWallet(updated);
                        }
                        Navigator.pop(ctx);
                      }
                    },
                    child: const Text("Save"),
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  // ==================== TRANSACTION / TRANSFER MODAL ====================
  void _showAddOrEditModal({Expense? existing, String? prefilledAmount}) {
    if (existing?.category == 'Transfer') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Transfers cannot be edited. Delete the transfer and create it again.'),
        ),
      );
      return;
    }
    final titleCtrl = TextEditingController(text: existing?.title ?? "");
    final amountCtrl = TextEditingController(text: prefilledAmount ?? (existing?.amount.toString() ?? ""));
    String selectedCategory = existing?.category ?? "General";
    DateTime selectedDate = existing?.date ?? DateTime.now();

    String transactionType = existing?.type ?? 'expense';

    final wallets = ref.read(walletProvider);
    String selectedWalletId = existing?.walletId ?? '';
    String transferToWalletId = '';

    final categories = ref.read(categoryProvider);
    if (!categories.contains(selectedCategory) && categories.isNotEmpty) {
      selectedCategory = categories.first;
    }

    final primaryColor = Color(ref.read(settingsProvider).profileColorValue);

    if (!wallets.any((w) => w.id == selectedWalletId) && wallets.isNotEmpty) {
      selectedWalletId = wallets.firstWhere((w) => !w.isBackup, orElse: () => wallets.first).id;
    }
    if (wallets.length > 1) {
      transferToWalletId = wallets.firstWhere((w) => w.id != selectedWalletId, orElse: () => wallets.last).id;
    }

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

                  Container(
                    decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(16)),
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      children: [
                        _buildSegment(transactionType, 'expense', "Expense", Colors.red, () => setModalState(() => transactionType = 'expense')),
                        _buildSegment(transactionType, 'income', "Income", Colors.green, () => setModalState(() => transactionType = 'income')),
                        _buildSegment(transactionType, 'transfer', "Transfer", Colors.blue, () => setModalState(() => transactionType = 'transfer')),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  if (transactionType != 'transfer')
                    _buildModernInput(titleCtrl, "Title", Icons.title_rounded, primaryColor)
                  else
                    const Align(alignment: Alignment.centerLeft, child: Padding(padding: EdgeInsets.only(left: 8, bottom: 8), child: Text("Moving money between wallets", style: TextStyle(color: Colors.grey, fontSize: 13)))),

                  const SizedBox(height: 12),
                  _buildModernInput(amountCtrl, "Amount", Icons.attach_money_rounded, primaryColor, isNumber: true),
                  const SizedBox(height: 12),

                  if (transactionType == 'transfer') ...[
                    _buildWalletDropdown(wallets, selectedWalletId, "From Wallet", (v) => setModalState(() => selectedWalletId = v!)),
                    const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Icon(Icons.arrow_downward_rounded, color: Colors.grey)),
                    _buildWalletDropdown(wallets, transferToWalletId, "To Wallet", (v) => setModalState(() => transferToWalletId = v!)),
                  ] else ...[
                    _buildWalletDropdown(wallets, selectedWalletId, "Fund Source", (v) => setModalState(() => selectedWalletId = v!)),
                  ],
                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        flex: 1,
                        child: GestureDetector(
                          onTap: () async {
                            final picked = await showDatePicker(context: context, initialDate: selectedDate, firstDate: DateTime(2020), lastDate: DateTime(2030));
                            if (picked != null) setModalState(() => selectedDate = picked);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(16)),
                            child: Row(
                              children: [
                                Icon(Icons.calendar_today_rounded, color: Colors.grey.shade500, size: 20),
                                const SizedBox(width: 8),
                                Expanded(child: Text(DateFormat.yMMMd().format(selectedDate), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13), overflow: TextOverflow.ellipsis)),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (transactionType == 'expense') ...[
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 1,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(16)),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: categories.contains(selectedCategory) ? selectedCategory : (categories.isNotEmpty ? categories.first : "General"),
                                isExpanded: true,
                                icon: Icon(Icons.keyboard_arrow_down_rounded, color: Colors.grey.shade500),
                                items: categories.map((c) => DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis))).toList(),
                                onChanged: (v) => setModalState(() => selectedCategory = v!),
                              ),
                            ),
                          ),
                        ),
                      ]
                    ],
                  ),

                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity, height: 52,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: transactionType == 'transfer' ? Colors.blue : primaryColor, foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                      onPressed: () async {
                        final amt = double.tryParse(amountCtrl.text.trim());
                        if (amt == null || !amt.isFinite || amt <= 0) {
                          _showTransactionError('Enter a valid amount above zero.');
                          return;
                        }
                        if (wallets.isEmpty) {
                          _showTransactionError('Create an income account first.');
                          return;
                        }

                        if (transactionType == 'transfer') {
                            if (wallets.length < 2) {
                              _showTransactionError('Create at least two accounts to transfer money.');
                              return;
                            }
                            if (selectedWalletId == transferToWalletId) {
                              _showTransactionError('Choose two different accounts.');
                              return;
                            }
                            final available = ref
                                .read(walletProvider.notifier)
                                .getBalanceForWallet(selectedWalletId);
                            if (amt > available) {
                              _showTransactionError(
                                'Insufficient balance. Available: Rs. ${available.toStringAsFixed(0)}',
                              );
                              return;
                            }
                            final fromName = wallets.firstWhere((w) => w.id == selectedWalletId).name;
                            final toName = wallets.firstWhere((w) => w.id == transferToWalletId).name;
                            final transferId = const Uuid().v4();

                            await ref.read(expenseProvider.notifier).addExpense(Expense(id: '${transferId}_out', title: "Transfer to $toName", amount: amt, date: selectedDate, category: "Transfer", colorValue: Colors.blue.value, type: 'expense', walletId: selectedWalletId));
                            await ref.read(expenseProvider.notifier).addExpense(Expense(id: '${transferId}_in', title: "Transfer from $fromName", amount: amt, date: selectedDate, category: "Transfer", colorValue: Colors.blue.value, type: 'income', walletId: transferToWalletId));
                          } else {
                            String finalTitle = titleCtrl.text.trim();
                            if (finalTitle.isEmpty) {
                              if (transactionType == 'income') {
                                finalTitle = 'Income / Allowance';
                              } else {
                                _showTransactionError('Enter a transaction title.');
                                return;
                              }
                            }

                            final finalCategory = transactionType == 'income' ? 'Income / Allowance' : selectedCategory;
                            if (existing == null) {
                              await ref.read(expenseProvider.notifier).addExpense(Expense(id: const Uuid().v4(), title: finalTitle, amount: amt, date: selectedDate, category: finalCategory, colorValue: primaryColor.value, type: transactionType, walletId: selectedWalletId));
                            } else {
                              final updated = await ref.read(expenseProvider.notifier).editExpense(existing.id, Expense(id: existing.id, title: finalTitle, amount: amt, date: selectedDate, category: finalCategory, colorValue: existing.colorValue, type: transactionType, walletId: selectedWalletId));
                              if (!updated) {
                                _showTransactionError('This transaction no longer exists.');
                                return;
                              }
                            }
                          }
                          try {
                            await NotificationService().scheduleSmartEntryReminders();
                          } catch (e) {
                            debugPrint("Notification reset failed: $e");
                          }
                          if (ctx.mounted) Navigator.pop(ctx);
                      },
                      child: Text(transactionType == 'transfer' ? "Complete Transfer" : "Save Transaction", style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    ),
                  )
                ],
              ),
            ),
          ),
        )
    );
  }

  void _showTransactionError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  Widget _buildSegment(String current, String type, String label, Color color, VoidCallback onTap) {
    bool isActive = current == type;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(color: isActive ? color.withOpacity(0.15) : Colors.transparent, borderRadius: BorderRadius.circular(12)),
          child: Center(child: Text(label, style: TextStyle(color: isActive ? color : Colors.grey, fontWeight: FontWeight.bold, fontSize: 12))),
        ),
      ),
    );
  }

  Widget _buildWalletDropdown(List<Wallet> wallets, String value, String hint, Function(String?) onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.withOpacity(0.1))),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: wallets.any((w) => w.id == value) ? value : wallets.first.id,
          isExpanded: true,
          icon: Icon(Icons.keyboard_arrow_down_rounded, color: Colors.grey.shade500),
          items: wallets.map((w) => DropdownMenuItem(value: w.id, child: Row(children: [
            Icon(w.isBackup ? Icons.shield_rounded : Icons.account_balance_wallet_rounded, size: 18, color: Color(w.colorValue)),
            const SizedBox(width: 12),
            Text(w.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500))
          ]))).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  // ==================== REST OF THE UI ====================
  Widget _buildModernInput(TextEditingController ctrl, String label, IconData icon, Color primaryColor, {bool isNumber = false}) {
    return TextField(
      controller: ctrl,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      textCapitalization: isNumber ? TextCapitalization.none : TextCapitalization.sentences,
      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      decoration: InputDecoration(labelText: label, labelStyle: TextStyle(color: Colors.grey.shade500, fontSize: 13), prefixIcon: Icon(icon, color: Colors.grey.shade500, size: 20), filled: true, fillColor: Theme.of(context).cardColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: primaryColor, width: 1.5)), contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16)),
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
          title: Row(children: [Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.green.withOpacity(0.15), shape: BoxShape.circle), child: const Icon(Icons.savings_rounded, color: Colors.green, size: 20)), const SizedBox(width: 12), const Expanded(child: Text("Monthly Limit", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)))]),
          content: _buildModernInput(c, "Enter Budget Limit", Icons.currency_rupee_rounded, primaryColor, isNumber: true),
          actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          actions: [Row(children: [Expanded(child: TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel", style: TextStyle(color: Colors.grey)))), const SizedBox(width: 12), Expanded(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: primaryColor, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(vertical: 12)), onPressed: () async { final val = double.tryParse(c.text.trim()); if (val == null || !val.isFinite || val < 0) { _showTransactionError('Enter a valid budget amount.'); return; } await ref.read(budgetProvider.notifier).setBudget(val, _focusedMonth); if (ctx.mounted) Navigator.pop(ctx); }, child: const Text("Save")))])],
        )
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final expenseState = ref.watch(expenseProvider);
    final budgetState = ref.watch(budgetProvider);
    final categories = ref.watch(categoryProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Color(settings.profileColorValue);

    final bool isAiChatOpen = ref.watch(isAiChatOpenProvider);
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    final monthKey = DateFormat('yyyy-MM').format(_focusedMonth);
    final double monthlyBudget = budgetState[monthKey] ?? 0.0;

    final monthlyTransactions = expenseState.allExpenses.where((e) => e.date.month == _focusedMonth.month && e.date.year == _focusedMonth.year).toList();

    final double globalIncome = monthlyTransactions.where((e) => e.type == 'income' && e.category != 'Transfer').fold(0.0, (sum, e) => sum + e.amount);
    final double globalSpent = monthlyTransactions.where((e) => e.type == 'expense' && e.category != 'Transfer').fold(0.0, (sum, e) => sum + e.amount);

    final double effectiveBudget = monthlyBudget + globalIncome;
    final double globalRemaining = effectiveBudget - globalSpent;

    final now = DateTime.now();
    final double actualTodaySpent = expenseState.allExpenses
        .where((e) => e.type == 'expense' &&
        e.category != 'Transfer' &&
        e.date.day == now.day &&
        e.date.month == now.month &&
        e.date.year == now.year)
        .fold(0.0, (sum, e) => sum + e.amount);

    var displayExpenses = List<Expense>.from(monthlyTransactions);

    if (_selectedCategoryTab != 'All' && !categories.contains(_selectedCategoryTab)) {
      _selectedCategoryTab = 'All';
    }

    if (_selectedCategoryTab != 'All') displayExpenses = displayExpenses.where((e) => e.category == _selectedCategoryTab).toList();
    if (_searchQuery.isNotEmpty) displayExpenses = displayExpenses.where((e) => e.title.toLowerCase().contains(_searchQuery.toLowerCase())).toList();

    displayExpenses.sort((a,b) => b.date.compareTo(a.date));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationService().updatePersistentStatusBarWidget(
        remainingToday: globalRemaining,
        spentToday: actualTodaySpent,
      );
    });

    return Scaffold(
      drawer: AppDrawer(currentView: _currentView, onViewChanged: (v)=>setState(()=>_currentView=v)),
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        title: _isSearching ? TextField(autofocus: true, style: const TextStyle(fontSize: 15), decoration: InputDecoration(border: InputBorder.none, hintText: "Search transactions...", hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14)), onChanged: (v)=>setState(()=>_searchQuery=v)) : Text(_currentView, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        centerTitle: true,
        leading: Builder(builder: (context) => IconButton(icon: const Icon(Icons.menu_rounded, size: 24), onPressed: () => Scaffold.of(context).openDrawer())),
        actions: [
          if (_currentView == 'Dashboard' && !_isSearching)
            IconButton(
              tooltip: 'Income Accounts',
              icon: const Icon(Icons.account_balance_wallet_outlined, size: 22),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const IncomeAccountsScreen(),
                ),
              ),
            ),
          if (_currentView == 'Dashboard' && !_isSearching)
            IconButton(
              tooltip: 'Voice Log',
              icon: Icon(
                _isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                color: _isListening ? Colors.red : null,
                size: 22,
              ),
              onPressed: _listenForExpense,
            ),
          if (_currentView == 'Dashboard')
            IconButton(
              tooltip: _isSearching ? 'Close search' : 'Search',
              icon: Icon(
                _isSearching ? Icons.close_rounded : Icons.search_rounded,
                size: 22,
              ),
              onPressed: () => setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) _searchQuery = '';
              }),
            ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: _buildResponsiveBody(isLandscape, isDark, primaryColor, monthlyBudget, effectiveBudget, globalRemaining, globalSpent, categories, displayExpenses),
          ),
          const AiChatOverlay(),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: (_currentView == 'Dashboard' && !isAiChatOpen) ? GestureDetector(
        onTapDown: (_) => _fabController.forward(),
        onTapUp: (_) { _fabController.reverse(); _showAddOrEditModal(); },
        onTapCancel: () => _fabController.reverse(),
        child: ScaleTransition(
          scale: _fabScale,
          child: Container(
            height: 52, padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(gradient: LinearGradient(colors: [primaryColor, primaryColor.withOpacity(0.8)], begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(26), boxShadow: [BoxShadow(color: primaryColor.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 6))]),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.add_rounded, color: Colors.white, size: 22), SizedBox(width: 8), Text("Add Transaction", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14))]),
          ),
        ),
      ) : null,
    );
  }

  Widget _buildResponsiveBody(bool isLandscape, bool isDark, Color primaryColor, double baseBudget, double effectiveBudget, double remaining, double spent, List<String> categories, List<Expense> displayExpenses) {
    if (_currentView != 'Dashboard') return _buildOtherViews();

    if (isLandscape && !_isSearching) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 1, child: SingleChildScrollView(padding: const EdgeInsets.only(bottom: 80), child: Column(children: [_buildMonthSelector(isDark), const SizedBox(height: 8), _buildHeroCard(baseBudget, effectiveBudget, remaining, spent, primaryColor), _buildCategoryTabsWidget(categories, primaryColor, isDark)]))),
          Expanded(flex: 1, child: _buildExpenseList(displayExpenses, primaryColor, isDark, isSliver: false)),
        ],
      );
    }

    if (!_isSearching) {
      return CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.only(bottom: 12.0), child: _buildMonthSelector(isDark))),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _buildHeroCard(
                baseBudget,
                effectiveBudget,
                remaining,
                spent,
                primaryColor,
              ),
            ),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _StickyHeaderDelegate(
              minHeight: 56,
              maxHeight: 56,
              child: ColoredBox(
                color: Theme.of(context).scaffoldBackgroundColor,
                child: _buildCategoryTabsWidget(
                  categories,
                  primaryColor,
                  isDark,
                ),
              ),
            ),
          ),

          // 🚀 FIX: The call to build the list now correctly assigns the sliver wrapper.
          _buildExpenseList(displayExpenses, primaryColor, isDark, isSliver: true),
        ],
      );
    }
    return Column(children: [const SizedBox(height: 4), Expanded(child: _buildExpenseList(displayExpenses, primaryColor, isDark, isSliver: false))]);
  }

  Widget _buildWalletCarousel(List<Wallet> wallets, bool isDark) {
    return SizedBox(
      height: 90,
      child: ListView.builder(
        scrollDirection: Axis.horizontal, physics: const BouncingScrollPhysics(), padding: const EdgeInsets.symmetric(horizontal: 20), itemCount: wallets.length + 1,
        itemBuilder: (context, index) {
          if (index == wallets.length) {
            return GestureDetector(
              onTap: () => _showWalletDialog(),
              child: Container(width: 120, decoration: BoxDecoration(color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.withOpacity(0.08), borderRadius: BorderRadius.circular(20), border: Border.all(color: isDark ? Colors.white24 : Colors.grey.shade300, width: 1.2)), child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.add_rounded, size: 24, color: Colors.grey), SizedBox(height: 4), Text("Add Source", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.grey))])),
            );
          }
          final wallet = wallets[index];
          final color = Color(wallet.colorValue);
          final double dynamicBalance = ref.watch(walletProvider.notifier).getBalanceForWallet(wallet.id);

          return GestureDetector(
            onTap: () => _showWalletDialog(existing: wallet),
            onLongPress: () {
              showDialog(context: context, builder: (ctx) => AlertDialog(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), title: const Text("Delete Fund Source?"), content: Text("Are you sure you want to delete '${wallet.name}'?"), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white), onPressed: () { ref.read(walletProvider.notifier).deleteWallet(wallet.id); Navigator.pop(ctx); }, child: const Text("Delete"))]));
            },
            child: Container(
              width: 140, margin: const EdgeInsets.only(right: 12), padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withOpacity(0.2), width: 1.5)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(children: [Icon(wallet.isBackup ? Icons.shield_rounded : Icons.account_balance_wallet_rounded, size: 16, color: color), const SizedBox(width: 6), Expanded(child: Text(wallet.name, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis))]),
                  const Spacer(),
                  Text("Rs. ${dynamicBalance.toStringAsFixed(0)}", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: isDark ? Colors.white : Colors.black87), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildOtherViews() {
    if (_currentView == 'Insights') return const InsightsScreen();
    if (_currentView == 'Tasks') return const ToDoScreen();
    if (_currentView == 'Mess Khata') return const MessKhataScreen();
    if (_currentView == 'Recurring Bills') return const RecurringBillsScreen();
    if (_currentView == 'Tools') return const UtilitiesScreen();
    if (_currentView == 'Udhaar') return const DebtScreen();
    if (_currentView == 'Stats') return const StatsScreen();
    if (_currentView == 'Settings') return const SettingsScreen();
    if (_currentView == 'About') return const AboutScreen();
    return const SizedBox.shrink();
  }

  // 🚀 FIXED: List Reconciliation Bug - Replaced ListView.builder with explicit Keys
  Widget _buildExpenseList(List<Expense> expenses, Color primaryColor, bool isDark, {required bool isSliver}) {
    if (expenses.isEmpty) {
      final emptyState = Center(child: Padding(padding: const EdgeInsets.only(top: 40.0), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.receipt_long_rounded, size: 50, color: Colors.grey.withOpacity(0.3)), const SizedBox(height: 12), Text("No transactions here yet.", style: TextStyle(color: Colors.grey.shade500, fontSize: 13))])));
      return isSliver ? SliverFillRemaining(hasScrollBody: false, child: emptyState) : emptyState;
    }

    final double todaySpend = expenses.where((e) => e.type == 'expense' && e.category != 'Transfer' && e.date.day == DateTime.now().day && e.date.month == DateTime.now().month && e.date.year == DateTime.now().year).fold(0.0, (sum, e) => sum + e.amount);

    final listContents = <Widget>[
      if (todaySpend > 0)
        Padding(
          key: const ValueKey('daily_spend_pill'),
          padding: const EdgeInsets.only(bottom: 12.0),
          child: Align(
            alignment: Alignment.center,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(color: primaryColor.withOpacity(0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: primaryColor.withOpacity(0.2))),
              child: Text("Today's Spend: Rs. ${todaySpend.toStringAsFixed(0)}", style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold, fontSize: 12)),
            ),
          ),
        ),
      ...expenses.map((e) => _buildExpenseTile(e, primaryColor, isDark)),
    ];

    if (isSliver) {
      return SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 80),
        sliver: SliverList(delegate: SliverChildListDelegate(listContents)),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 80),
      children: listContents,
    );
  }

  Widget _buildExpenseTile(Expense e, Color primaryColor, bool isDark) {
    final eColor = Color(e.colorValue);
    final isIncome = e.type == 'income';
    final isTransfer = e.category == 'Transfer';

    final amountSign = isTransfer ? (isIncome ? "+" : "-") : (isIncome ? "+" : "-");
    final amountColor = isTransfer ? Colors.blue : (isIncome ? Colors.green : (isDark ? Colors.white : Colors.black87));
    final displayIcon = isTransfer ? Icons.swap_horiz_rounded : (isIncome ? Icons.south_west_rounded : Icons.category_rounded);

    return Dismissible(
      key: Key(e.id),
      direction: DismissDirection.endToStart,
      background: Container(alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), margin: const EdgeInsets.only(bottom: 12), decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(18)), child: const Icon(Icons.delete_outline_rounded, color: Colors.white)),
      confirmDismiss: (direction) async {
        return await showDialog(context: context, builder: (dialogCtx) => Dialog(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)), backgroundColor: Theme.of(context).cardColor, child: Padding(padding: const EdgeInsets.all(24.0), child: Column(mainAxisSize: MainAxisSize.min, children: [Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), shape: BoxShape.circle), child: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 28)), const SizedBox(height: 16), Text(isTransfer ? "Delete Transfer?" : "Delete Transaction?", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), const SizedBox(height: 8), Text(isTransfer ? "Delete this complete transfer? Both linked account entries will be removed." : "Are you sure you want to delete '${e.title}'? This action cannot be undone.", textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Colors.grey.shade500, height: 1.4)), const SizedBox(height: 24), Row(children: [Expanded(child: TextButton(style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), onPressed: () => Navigator.of(dialogCtx).pop(false), child: const Text("Cancel", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)))), const SizedBox(width: 12), Expanded(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), onPressed: () => Navigator.of(dialogCtx).pop(true), child: const Text("Delete", style: TextStyle(fontWeight: FontWeight.bold))))])]))));
      },
      onDismissed: (direction) async {
        if (isTransfer) {
          await ref.read(expenseProvider.notifier).deleteTransferPair(e.id);
        } else {
          await ref.read(expenseProvider.notifier).deleteExpense(e.id);
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Deleted '${e.title}'", style: const TextStyle(fontSize: 13)), backgroundColor: Colors.red, duration: const Duration(seconds: 2)));
      },
      child: GestureDetector(
        onTap: isTransfer ? null : () => _showAddOrEditModal(existing: e),
        child: Container(
            margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(18), border: Border.all(color: isDark ? primaryColor.withOpacity(0.2) : Colors.grey.withOpacity(0.12), width: 1.2)),
            child: Row(
              children: [
                Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: (isTransfer ? Colors.blue : (isIncome ? Colors.green : eColor)).withOpacity(0.15), shape: BoxShape.circle), child: Icon(displayIcon, color: isTransfer ? Colors.blue : (isIncome ? Colors.green : eColor), size: 20)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Row(children: [Icon(Icons.schedule_rounded, size: 11, color: Colors.grey.shade500), const SizedBox(width: 4), Text(DateFormat.MMMEd().format(e.date), style: TextStyle(fontSize: 11, color: Colors.grey.shade500))]),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text("$amountSign Rs. ${e.amount.toStringAsFixed(0)}", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: amountColor)),
              ],
            )
        ),
      ),
    );
  }

  Widget _buildSmartEntryWidget(Color primaryColor, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(18), border: Border.all(color: isDark ? primaryColor.withOpacity(0.3) : Colors.grey.withOpacity(0.15), width: 1.2)),
        child: Row(
          children: [
            IconButton(constraints: const BoxConstraints(minWidth: 36, minHeight: 36), padding: EdgeInsets.zero, icon: Icon(_isListening ? Icons.mic : Icons.mic_none_rounded, size: 20, color: _isListening ? Colors.red : (isDark ? Colors.white70 : primaryColor)), onPressed: _listenForExpense),
            Expanded(child: TextField(controller: _smartInputCtrl, style: const TextStyle(fontSize: 13), decoration: InputDecoration(hintText: _isListening ? 'Listening...' : 'Speak: "1500 for Pizza"', border: InputBorder.none, isDense: true, hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 12)), onSubmitted: (val) => _processNLP(val))),
            IconButton(constraints: const BoxConstraints(minWidth: 32, minHeight: 32), padding: EdgeInsets.zero, icon: const Icon(Icons.calculate_rounded, color: Colors.orange, size: 18), onPressed: _showCalculator),
            IconButton(constraints: const BoxConstraints(minWidth: 32, minHeight: 32), padding: EdgeInsets.zero, icon: const Icon(Icons.document_scanner_rounded, color: Colors.blueAccent, size: 18), onPressed: _startReceiptScan),
            IconButton(constraints: const BoxConstraints(minWidth: 36, minHeight: 36), padding: EdgeInsets.zero, icon: Icon(Icons.send_rounded, color: primaryColor, size: 18), onPressed: () => _processNLP(_smartInputCtrl.text)),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryTabsWidget(List<String> categories, Color primaryColor, bool isDark) {
    return Container(
      height: 40, margin: const EdgeInsets.only(top: 4, bottom: 8),
      child: ListView(
          controller: _categoryScrollCtrl, scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 20),
          children: [_buildTab('All', 0, isDark, primaryColor), ...List.generate(categories.length, (i) => _buildTab(categories[i], i + 1, isDark, primaryColor)), _buildAddCategoryBtn(primaryColor, isDark)]
      ),
    );
  }

  Widget _buildAddCategoryBtn(Color primaryColor, bool isDark) {
    return GestureDetector(
      onTap: _showAddCategoryDialog,
      child: Container(margin: const EdgeInsets.only(right: 8), padding: const EdgeInsets.symmetric(horizontal: 16), decoration: BoxDecoration(color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.withOpacity(0.08), borderRadius: BorderRadius.circular(20), border: Border.all(color: isDark ? Colors.white24 : Colors.grey.shade300, width: 1.2)), child: Row(children: [Icon(Icons.add_rounded, size: 16, color: isDark ? Colors.white70 : Colors.black87), const SizedBox(width: 4), Text("New", style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontWeight: FontWeight.bold, fontSize: 12))])),
    );
  }

  Widget _buildTab(String label, int index, bool isDark, Color primaryColor) {
    bool isSelected = _selectedCategoryTab == label;
    return GestureDetector(
        onTap: () => _selectCategory(label, index),
        child: AnimatedContainer(duration: const Duration(milliseconds: 200), margin: const EdgeInsets.only(right: 8), padding: const EdgeInsets.symmetric(horizontal: 16), decoration: BoxDecoration(color: isSelected ? primaryColor : Theme.of(context).cardColor, borderRadius: BorderRadius.circular(20), border: isSelected ? null : Border.all(color: isDark ? primaryColor.withOpacity(0.25) : Colors.grey.withOpacity(0.15), width: 1.2)), child: Center(child: Text(label, style: TextStyle(color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87), fontWeight: isSelected ? FontWeight.bold : FontWeight.w600, fontSize: 12))))
    );
  }

  Widget _buildMiniHero(double r, double s, Color primary) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14), decoration: BoxDecoration(gradient: LinearGradient(colors: [primary, primary.withOpacity(0.8)]), borderRadius: BorderRadius.circular(18), boxShadow: [BoxShadow(color: primary.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))]),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Row(children: [const Icon(Icons.account_balance_wallet_rounded, color: Colors.white70, size: 18), const SizedBox(width: 8), Text("Rs. ${r.abs().toStringAsFixed(0)}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))]), Text("Spent: ${s.toStringAsFixed(0)}", style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, fontSize: 12))]),
    );
  }

  Widget _buildHeroCard(double baseBudget, double effectiveBudget, double r, double s, Color primary) {
    bool isAlert = effectiveBudget > 0 && s > effectiveBudget;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 500), width: double.infinity, margin: const EdgeInsets.symmetric(horizontal: 20), padding: const EdgeInsets.all(16), decoration: BoxDecoration(gradient: LinearGradient(colors: isAlert ? [Colors.red.shade900, Colors.red] : [primary, primary.withOpacity(0.75)], begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(28), boxShadow: [BoxShadow(color: (isAlert ? Colors.red : primary).withOpacity(0.35), blurRadius: 18, offset: const Offset(0, 8))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min,
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(isAlert ? "Limit Exceeded!" : "Remaining Balance", style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w500, fontSize: 13)), Icon(isAlert ? Icons.warning_amber_rounded : Icons.account_balance_wallet_rounded, color: Colors.white70, size: 20)]),
          const SizedBox(height: 6),
          effectiveBudget == 0 ? GestureDetector(onTap: () => _editBudget(baseBudget), child: const Row(children: [Text("Set Limit", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)), SizedBox(width: 6), Icon(Icons.edit_rounded, color: Colors.white, size: 18)])) : FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text("Rs. ${r.abs().toStringAsFixed(0)}", style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -0.5))),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(onTap: () => _editBudget(baseBudget), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Text("Budget + Income", style: TextStyle(color: Colors.white.withOpacity(0.65), fontSize: 11)), const SizedBox(width: 4), Icon(Icons.edit_outlined, color: Colors.white.withOpacity(0.65), size: 10)]), const SizedBox(height: 2), FittedBox(fit: BoxFit.scaleDown, child: Text(effectiveBudget.toStringAsFixed(0), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)))])),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [Text("Total Spent", style: TextStyle(color: Colors.white.withOpacity(0.65), fontSize: 11)), const SizedBox(height: 2), FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight, child: Text(s.toStringAsFixed(0), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)))])),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildMonthSelector(bool isDark) {
    return Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 16), onPressed: ()=>setState(()=>_focusedMonth=DateTime(_focusedMonth.year, _focusedMonth.month-1, 1))), Text(DateFormat.yMMMM().format(_focusedMonth), style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: isDark?Colors.white:Colors.black87)), IconButton(icon: const Icon(Icons.arrow_forward_ios_rounded, size: 16), onPressed: ()=>setState(()=>_focusedMonth=DateTime(_focusedMonth.year, _focusedMonth.month+1, 1)))]));
  }

  Future<void> _listenForExpense() async {
    if (_isListening) {
      await _speech.stop();
      if (mounted) setState(() => _isListening = false);
      return;
    }

    _voiceResultProcessed = false;
    _smartInputCtrl.clear();
    final available = await _speech.initialize(
      onStatus: _handleSpeechStatus,
      onError: (error) {
        debugPrint('STT Error: $error');
        if (!mounted) return;
        setState(() => _isListening = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Voice Log stopped. Please try again.')),
        );
      },
    );
    if (!mounted) return;

    if (!available) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Microphone or speech-recognition permission was denied.'),
        ),
      );
      return;
    }

    setState(() => _isListening = true);
    await _speech.listen(
      onResult: (result) async {
        if (!mounted) return;
        final words = result.recognizedWords.trim();
        setState(() => _smartInputCtrl.text = words);
        if (result.finalResult && words.isNotEmpty && !_voiceResultProcessed) {
          _voiceResultProcessed = true;
          setState(() => _isListening = false);
          await _processNLP(words);
        }
      },
    );
  }

  void _handleSpeechStatus(String status) {
    if (!mounted || (status != 'done' && status != 'notListening')) return;
    final words = _smartInputCtrl.text.trim();
    setState(() => _isListening = false);
    if (!_voiceResultProcessed && words.isNotEmpty) {
      _voiceResultProcessed = true;
      _processNLP(words);
    }
  }

  Future<void> _processNLP(String text) async {
    final normalized = text.trim();
    if (normalized.isEmpty) return;
    final categories = ref.read(categoryProvider);
    final result = LocalNlpService().parseExpense(normalized, categories);

    final amount = result['amount'];
    if (amount is num && amount.isFinite && amount > 0) {
      final wallets = ref.read(walletProvider);
      if (wallets.isEmpty) {
        _showTransactionError('Create an income account before using Voice Log.');
        return;
      }

      final activeWallets = wallets.where((w) => !w.isBackup).toList();
      final defaultWalletId = activeWallets.isNotEmpty ? activeWallets.first.id : (wallets.isNotEmpty ? wallets.first.id : '');

      final newExpense = Expense(id: const Uuid().v4(), title: result['title'], amount: amount.toDouble(), category: result['category'], date: DateTime.now(), colorValue: Colors.purple.value, walletId: defaultWalletId);
      await ref.read(expenseProvider.notifier).addExpense(newExpense);
      try {
        await NotificationService().scheduleSmartEntryReminders();
      } catch (e) {
        debugPrint("Notification reset failed: $e");
      }
      if (!mounted) return;
      _smartInputCtrl.clear();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("✅ Saved: ${result['title']} (Rs. ${amount.toStringAsFixed(0)})", style: const TextStyle(fontSize: 13)), backgroundColor: Colors.green));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("❌ Could not detect amount. Try: '500 for biryani'.", style: TextStyle(fontSize: 13)), backgroundColor: Colors.red));
    }
    if (mounted) FocusScope.of(context).unfocus();
  }

  void _startReceiptScan() async {
    showDialog(context: context, barrierDismissible: false, builder: (ctx) => Center(child: Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(20)), child: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(color: Theme.of(context).primaryColor), const SizedBox(height: 16), const Text("Processing Receipt...", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14))]))));
    final receiptData = await OcrScannerService().scanReceipt();
    if (mounted) Navigator.pop(context);
    if (receiptData != null && receiptData['amount'] > 0) {
      final wallets = ref.read(walletProvider);
      final activeWallets = wallets.where((w) => !w.isBackup).toList();
      final defaultWalletId = activeWallets.isNotEmpty ? activeWallets.first.id : (wallets.isNotEmpty ? wallets.first.id : '');

      ref.read(expenseProvider.notifier).addExpense(Expense(id: const Uuid().v4(), title: receiptData['title'], amount: receiptData['amount'], category: receiptData['category'], date: DateTime.now(), colorValue: Colors.blueAccent.value, walletId: defaultWalletId));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("✅ Saved: ${receiptData['title']} (Rs. ${receiptData['amount'].toStringAsFixed(0)})", style: const TextStyle(fontSize: 13)), backgroundColor: Colors.green));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("❌ Could not read receipt clearly. Try manual entry.", style: TextStyle(fontSize: 13)), backgroundColor: Colors.red));
    }
  }
}

class _StickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double minHeight;
  final double maxHeight;
  final Widget child;
  _StickyHeaderDelegate({required this.minHeight, required this.maxHeight, required this.child});
  @override double get minExtent => minHeight;
  @override double get maxExtent => maxHeight;
  @override Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => SizedBox.expand(child: child);
  @override bool shouldRebuild(_StickyHeaderDelegate oldDelegate) => maxHeight != oldDelegate.maxHeight || minHeight != oldDelegate.minHeight || child != oldDelegate.child;
}
