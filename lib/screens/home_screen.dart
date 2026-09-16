import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:quick_actions/quick_actions.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';

import "../services/notification_service.dart";
import '../providers/expense_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/category_provider.dart';
import '../providers/wallet_provider.dart';
import '../models/expense_model.dart';
import '../models/debt_model.dart';
import '../models/mess_entry_model.dart';
import '../models/wallet_model.dart';
import '../widgets/app_drawer.dart';
import 'debt_screen.dart';
import 'settings_screen.dart';
import 'stats_screen.dart';
import 'about_screen.dart';
import '../services/local_nlp_service.dart';
import '../services/ocr_scanner_service.dart';
import "./mess_khata_screen.dart";
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
  bool _isScanningReceipt = false;
  final TextEditingController _smartInputCtrl = TextEditingController();
  Timer? _notificationUpdateTimer;
  Timer? _messageTimer;
  OverlayEntry? _activeMessageEntry;

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

      _queuePersistentNotificationUpdate(
        delay: const Duration(seconds: 2),
      );
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
    }).catchError((Object error) {
      debugPrint("Quick Tile Error: $error");
      return null;
    });

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
    _notificationUpdateTimer?.cancel();
    _messageTimer?.cancel();
    _activeMessageEntry?.remove();
    _activeMessageEntry = null;
    _categoryScrollCtrl.dispose();
    _smartInputCtrl.dispose();
    super.dispose();
  }

  void _queuePersistentNotificationUpdate({
    Duration delay = const Duration(milliseconds: 350),
  }) {
    _notificationUpdateTimer?.cancel();
    _notificationUpdateTimer = Timer(delay, () {
      if (!mounted) return;
      final now = DateTime.now();
      final expenses = ref.read(expenseProvider).allExpenses;
      final wallets = ref.read(walletProvider);
      final walletNotifier = ref.read(walletProvider.notifier);

      final totalAvailable = wallets.fold<double>(
        0,
            (sum, wallet) => sum + walletNotifier.getBalanceForWallet(wallet.id),
      );

      double spentToday = 0;
      for (final entry in expenses) {
        if (entry.category == 'Transfer') continue;
        if (entry.type == 'expense' &&
            entry.date.year == now.year &&
            entry.date.month == now.month &&
            entry.date.day == now.day) {
          spentToday += entry.amount;
        }
      }

      NotificationService().updatePersistentStatusBarWidget(
        remainingToday: totalAvailable,
        spentToday: spentToday,
      );
    });
  }

  void _selectCategory(String category, int index) {
    setState(() => _selectedCategoryTab = category);
    double offset = (index * 70.0) - (MediaQuery.of(context).size.width / 2) + 35;
    if (offset < 0) offset = 0;
    if (_categoryScrollCtrl.hasClients) {
      _categoryScrollCtrl.animateTo(offset, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  Future<void> _changeView(String view) async {
    if (!mounted || view == _currentView) return;

    try {
      if (view == 'Mess Khata' && !Hive.isBoxOpen('mess_khata')) {
        await Hive.openBox<MessEntry>('mess_khata');
      } else if (view == 'Udhaar' && !Hive.isBoxOpen('debts')) {
        await Hive.openBox<DebtEntry>('debts');
      }
    } catch (error) {
      if (mounted) {
        _showTransactionError('Could not open $view. Please try again.');
      }
      return;
    }

    if (!mounted) return;
    setState(() {
      _currentView = view;
      _isSearching = false;
      _searchQuery = '';
    });

    if (view == 'Dashboard') _queuePersistentNotificationUpdate();
  }

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
            Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: primaryColor.withValues(alpha: 0.15), shape: BoxShape.circle), child: Icon(Icons.category_rounded, color: primaryColor, size: 20)),
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
                        _showTransactionError(
                          'Choose a different name for this category.',
                          title: 'Category already exists',
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

  Future<void> _confirmDeleteCategory(String category) async {
    if (category == 'All') return;
    final categories = ref.read(categoryProvider);

    if (categories.length <= 1) {
      _showTransactionError('Keep at least one expense category.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          'Delete Category?',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        content: Text(
          "Delete '$category'? Existing transactions will remain unchanged.",
          style: const TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    ref.read(categoryProvider.notifier).deleteCategory(category);

    if (_selectedCategoryTab == category) {
      setState(() => _selectedCategoryTab = 'All');
    }
    _showTransactionSuccess(
      "Category '$category' was deleted.",
      title: 'Category deleted',
    );
  }

  // ==================== TRANSACTION / TRANSFER MODAL ====================
  Future<bool?> _showAddOrEditModal({
    Expense? existing,
    String? prefilledAmount,
    String? prefilledTitle,
    String? prefilledCategory,
    DateTime? prefilledDate,
    String? preselectedWalletId,
    String initialType = 'expense',
    String? reviewMessage,
  }) async {
    if (existing?.category == 'Transfer') {
      _showTransactionInfo(
        'Delete this transfer and create it again if its details need to change.',
        title: 'Transfers cannot be edited',
      );
      return null;
    }

    final titleCtrl = TextEditingController(
      text: existing?.title ?? prefilledTitle ?? "",
    );
    final amountCtrl = TextEditingController(
      text: prefilledAmount ?? (existing?.amount.toString() ?? ""),
    );
    String selectedCategory =
        existing?.category ?? prefilledCategory ?? "General";
    DateTime selectedDate =
        existing?.date ?? prefilledDate ?? DateTime.now();

    String transactionType = existing?.type ?? initialType;

    final wallets = ref.read(walletProvider);
    String selectedWalletId =
        existing?.walletId ?? preselectedWalletId ?? '';
    String transferToWalletId = '';

    final categories = ref.read(categoryProvider);
    if (!categories.contains(selectedCategory) && categories.isNotEmpty) {
      selectedCategory = categories.first;
    }

    final primaryColor = Color(ref.read(settingsProvider).profileColorValue);

    if (!wallets.any((w) => w.id == selectedWalletId) && wallets.isNotEmpty) {
      final cashWallet = wallets.cast<Wallet?>().firstWhere(
            (w) => w != null && !w.isBackup && (w.walletType == 'cash' || w.name.toLowerCase().contains('cash')),
        orElse: () => null,
      );

      if (cashWallet != null) {
        selectedWalletId = cashWallet.id;
      } else {
        selectedWalletId = wallets.firstWhere((w) => !w.isBackup, orElse: () => wallets.first).id;
      }
    }

    if (wallets.length > 1) {
      transferToWalletId = wallets.firstWhere((w) => w.id != selectedWalletId, orElse: () => wallets.last).id;
    }

    return showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => StatefulBuilder(
          builder: (context, setModalState) => Container(
            decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 30, offset: const Offset(0, -10))]
            ),
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom + 24, left: 24, right: 24, top: 12),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 48, height: 4, decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2)), margin: const EdgeInsets.only(bottom: 24)),

                  if (reviewMessage != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: primaryColor.withValues(alpha: 0.09),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: primaryColor.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.fact_check_outlined,
                            color: primaryColor,
                            size: 21,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Review before saving',
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  reviewMessage,
                                  style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                    fontSize: 12.5,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

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

                        if (transactionType == 'expense') {
                          final currentBalance = ref
                              .read(walletProvider.notifier)
                              .getBalanceForWallet(selectedWalletId);
                          final reusableAmount = existing != null &&
                                  existing.type == 'expense' &&
                                  existing.walletId == selectedWalletId
                              ? existing.amount
                              : 0.0;
                          final available = currentBalance + reusableAmount;
                          if (amt > available) {
                            final accountName = wallets
                                .firstWhere((w) => w.id == selectedWalletId)
                                .name;
                            _showTransactionError(
                              'Available in $accountName: Rs. ${available.toStringAsFixed(0)}. Required: Rs. ${amt.toStringAsFixed(0)}. Add money to this account or enter a smaller amount.',
                              title: 'Insufficient balance',
                            );
                            return;
                          }
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
                              'Available in the source account: Rs. ${available.toStringAsFixed(0)}. Enter a smaller amount or add money first.',
                              title: 'Insufficient balance',
                            );
                            return;
                          }
                          final fromName = wallets.firstWhere((w) => w.id == selectedWalletId).name;
                          final toName = wallets.firstWhere((w) => w.id == transferToWalletId).name;
                          final transferId = const Uuid().v4();

                          final saved = await ref
                              .read(expenseProvider.notifier)
                              .addExpenses([
                            Expense(id: '${transferId}_out', title: "Transfer to $toName", amount: amt, date: selectedDate, category: "Transfer", colorValue: Colors.blue.toARGB32(), type: 'expense', walletId: selectedWalletId),
                            Expense(id: '${transferId}_in', title: "Transfer from $fromName", amount: amt, date: selectedDate, category: "Transfer", colorValue: Colors.blue.toARGB32(), type: 'income', walletId: transferToWalletId),
                          ]);
                          if (!saved) {
                            _showTransactionError(
                              'The source account no longer has enough money for this transfer.',
                              title: 'Transfer not saved',
                            );
                            return;
                          }
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
                            final saved = await ref.read(expenseProvider.notifier).addExpense(Expense(id: const Uuid().v4(), title: finalTitle, amount: amt, date: selectedDate, category: finalCategory, colorValue: primaryColor.toARGB32(), type: transactionType, walletId: selectedWalletId));
                            if (!saved) {
                              _showTransactionError(
                                'Check the selected account balance and try again.',
                                title: 'Transaction not saved',
                              );
                              return;
                            }
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
                        if (ctx.mounted) Navigator.pop(ctx, true);
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

  void _showTransactionError(
    String message, {
    String title = 'Unable to continue',
  }) {
    _showTopMessage(title: title, message: message, tone: _MessageTone.error);
  }

  void _showTransactionSuccess(
    String message, {
    String title = 'Completed',
    String? actionLabel,
    Future<void> Function()? onAction,
  }) {
    _showTopMessage(
      title: title,
      message: message,
      tone: _MessageTone.success,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  void _showTransactionInfo(
    String message, {
    String title = 'Information',
  }) {
    _showTopMessage(title: title, message: message, tone: _MessageTone.info);
  }

  void _showTopMessage({
    required String title,
    required String message,
    required _MessageTone tone,
    String? actionLabel,
    Future<void> Function()? onAction,
  }) {
    if (!mounted) return;

    _messageTimer?.cancel();
    _activeMessageEntry?.remove();

    late final OverlayEntry entry;
    void dismiss() {
      if (_activeMessageEntry != entry) return;
      entry.remove();
      _activeMessageEntry = null;
      _messageTimer?.cancel();
      _messageTimer = null;
    }

    entry = OverlayEntry(
      builder: (overlayContext) => Positioned(
        top: MediaQuery.paddingOf(overlayContext).top + 12,
        left: 16,
        right: 16,
        child: Align(
          alignment: Alignment.topCenter,
          child: _TopMessageCard(
            title: title,
            message: message,
            tone: tone,
            actionLabel: actionLabel,
            onAction: onAction,
            onDismiss: dismiss,
          ),
        ),
      ),
    );

    _activeMessageEntry = entry;
    Overlay.of(context, rootOverlay: true).insert(entry);
    _messageTimer = Timer(
      Duration(seconds: actionLabel == null ? 5 : 7),
      dismiss,
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
          decoration: BoxDecoration(color: isActive ? color.withValues(alpha: 0.15) : Colors.transparent, borderRadius: BorderRadius.circular(12)),
          child: Center(child: Text(label, style: TextStyle(color: isActive ? color : Colors.grey, fontWeight: FontWeight.bold, fontSize: 12))),
        ),
      ),
    );
  }

  Widget _buildWalletDropdown(List<Wallet> wallets, String value, String hint, Function(String?) onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.withValues(alpha: 0.1))),
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

  Widget _buildModernInput(TextEditingController ctrl, String label, IconData icon, Color primaryColor, {bool isNumber = false}) {
    return TextField(
      controller: ctrl,
      keyboardType: isNumber
          ? const TextInputType.numberWithOptions(decimal: true, signed: false)
          : TextInputType.text,
      inputFormatters: isNumber
          ? [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))]
          : null,
      textCapitalization: isNumber ? TextCapitalization.none : TextCapitalization.sentences,
      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      decoration: InputDecoration(labelText: label, labelStyle: TextStyle(color: Colors.grey.shade500, fontSize: 13), prefixIcon: Icon(icon, color: Colors.grey.shade500, size: 20), filled: true, fillColor: Theme.of(context).cardColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: primaryColor, width: 1.5)), contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16)),
    );
  }

  Future<void> _openIncomeAccounts() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const IncomeAccountsScreen()),
    );
    if (mounted) _queuePersistentNotificationUpdate();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<ExpenseState>(expenseProvider, (_, __) {
      _queuePersistentNotificationUpdate();
    });
    ref.listen<List<Wallet>>(walletProvider, (_, __) {
      _queuePersistentNotificationUpdate();
    });

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;

    if (_currentView != 'Dashboard') {
      return Scaffold(
        drawer: AppDrawer(
          currentView: _currentView,
          onViewChanged: _changeView,
        ),
        appBar: AppBar(
          elevation: 0,
          scrolledUnderElevation: 0,
          title: Text(
            _currentView,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
          ),
          centerTitle: true,
          leading: Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.menu_rounded, size: 24),
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
          ),
        ),
        body: _buildOtherViews(),
      );
    }

    final ledger = ref.watch(monthlyLedgerProvider(_focusedMonth));
    final categories = ref.watch(categoryProvider);
    final wallets = ref.watch(walletProvider);

    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    final monthlyTransactions = ledger.transactions;
    final globalSpent = ledger.spent;

    final walletNotifier = ref.read(walletProvider.notifier);
    final totalAvailable = wallets.fold<double>(
      0,
          (sum, wallet) => sum + walletNotifier.getBalanceForWallet(wallet.id),
    );

    var displayExpenses = List<Expense>.from(monthlyTransactions);

    if (_selectedCategoryTab != 'All' && !categories.contains(_selectedCategoryTab)) {
      _selectedCategoryTab = 'All';
    }

    if (_selectedCategoryTab != 'All') displayExpenses = displayExpenses.where((e) => e.category == _selectedCategoryTab).toList();
    if (_searchQuery.isNotEmpty) displayExpenses = displayExpenses.where((e) => e.title.toLowerCase().contains(_searchQuery.toLowerCase())).toList();

    displayExpenses.sort((a,b) => b.date.compareTo(a.date));

    return Scaffold(
      drawer: AppDrawer(
        currentView: _currentView,
        onViewChanged: _changeView,
      ),
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
              onPressed: _openIncomeAccounts,
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
      body: _buildResponsiveBody(
        isLandscape,
        isDark,
        primaryColor,
        totalAvailable,
        globalSpent,
        wallets,
        categories,
        displayExpenses,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: (_currentView == 'Dashboard') ? GestureDetector(
        onTapDown: (_) => _fabController.forward(),
        onTapUp: (_) { _fabController.reverse(); _showAddOrEditModal(); },
        onTapCancel: () => _fabController.reverse(),
        child: ScaleTransition(
          scale: _fabScale,
          child: Container(
            height: 52, padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(gradient: LinearGradient(colors: [primaryColor, primaryColor.withValues(alpha: 0.8)], begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(26), boxShadow: [BoxShadow(color: primaryColor.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 6))]),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.add_rounded, color: Colors.white, size: 22), SizedBox(width: 8), Text("Add Transaction", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14))]),
          ),
        ),
      ) : null,
    );
  }

  Widget _buildResponsiveBody(bool isLandscape, bool isDark, Color primaryColor, double totalAvailable, double spent, List<Wallet> wallets, List<String> categories, List<Expense> displayExpenses) {
    if (_currentView != 'Dashboard') return _buildOtherViews();

    if (isLandscape && !_isSearching) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 1, child: SingleChildScrollView(padding: const EdgeInsets.only(bottom: 80), child: Column(children: [_buildMonthSelector(isDark), const SizedBox(height: 8), _buildHeroCard(totalAvailable, spent, wallets, primaryColor), const SizedBox(height: 35), _buildSmartInputBar(primaryColor, isDark), _buildCategoryTabsWidget(categories, primaryColor, isDark)]))),
          Expanded(flex: 1, child: _buildExpenseList(displayExpenses, primaryColor, isDark, isSliver: false)),
        ],
      );
    }

    if (!_isSearching) {
      return CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.only(bottom: 12.0), child: _buildMonthSelector(isDark))),

          SliverAppBar(
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            expandedHeight: 300.0,
            collapsedHeight: 70.0,
            pinned: true,
            elevation: 0,
            automaticallyImplyLeading: false,
            flexibleSpace: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final top = constraints.biggest.height;
                final bool isCollapsed = top <= 100.0;

                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 150),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  child: isCollapsed
                      ? Align(
                    key: const ValueKey('mini'),
                    alignment: Alignment.bottomCenter,
                    child: SingleChildScrollView(
                      physics: const NeverScrollableScrollPhysics(),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: _buildMiniHero(totalAvailable, primaryColor),
                      ),
                    ),
                  )
                      : Align(
                    key: const ValueKey('full'),
                    alignment: Alignment.topCenter,
                    child: SingleChildScrollView(
                      physics: const NeverScrollableScrollPhysics(),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: _buildHeroCard(totalAvailable, spent, wallets, primaryColor),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 16.0, bottom: 8.0),
              child: _buildSmartInputBar(primaryColor, isDark),
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
          _buildExpenseList(displayExpenses, primaryColor, isDark, isSliver: true),
        ],
      );
    }
    return Column(children: [const SizedBox(height: 4), Expanded(child: _buildExpenseList(displayExpenses, primaryColor, isDark, isSliver: false))]);
  }

  Widget _buildOtherViews() {
    if (_currentView == 'Mess Khata') return const MessKhataScreen();
    if (_currentView == 'Udhaar') return const DebtScreen();
    if (_currentView == 'Stats') return const StatsScreen();
    if (_currentView == 'Settings') return const SettingsScreen();
    if (_currentView == 'About') return const AboutScreen();
    return const SizedBox.shrink();
  }

  Widget _buildExpenseList(List<Expense> expenses, Color primaryColor, bool isDark, {required bool isSliver}) {
    if (expenses.isEmpty) {
      final emptyState = Center(child: Padding(padding: const EdgeInsets.only(top: 40.0), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.receipt_long_rounded, size: 50, color: Colors.grey.withValues(alpha: 0.3)), const SizedBox(height: 12), Text("No transactions here yet.", style: TextStyle(color: Colors.grey.shade500, fontSize: 13))])));
      return isSliver ? SliverFillRemaining(hasScrollBody: false, child: emptyState) : emptyState;
    }

    final now = DateTime.now();
    final double todaySpend = expenses
        .where((e) =>
    e.type == 'expense' &&
        e.category != 'Transfer' &&
        e.date.day == now.day &&
        e.date.month == now.month &&
        e.date.year == now.year)
        .fold(0.0, (sum, e) => sum + e.amount);

    final hasTodaySummary = todaySpend > 0;
    final itemCount = expenses.length + (hasTodaySummary ? 1 : 0);

    Widget buildItem(BuildContext context, int index) {
      if (hasTodaySummary && index == 0) {
        return _buildTodaySpendPill(todaySpend, primaryColor);
      }
      final expenseIndex = index - (hasTodaySummary ? 1 : 0);
      return _buildExpenseTile(
        expenses[expenseIndex],
        primaryColor,
        isDark,
      );
    }

    if (isSliver) {
      return SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 80),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            buildItem,
            childCount: itemCount,
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 80),
      itemCount: itemCount,
      itemBuilder: buildItem,
    );
  }

  Widget _buildTodaySpendPill(double todaySpend, Color primaryColor) {
    return Padding(
      key: const ValueKey('daily_spend_pill'),
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Align(
        alignment: Alignment.center,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: primaryColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: primaryColor.withValues(alpha: 0.2)),
          ),
          child: Text(
            "Today's Spend: Rs. ${todaySpend.toStringAsFixed(0)}",
            style: TextStyle(
              color: primaryColor,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExpenseTile(Expense e, Color primaryColor, bool isDark) {
    final eColor = Color(e.colorValue);
    final isIncome = e.type == 'income';
    final isTransfer = e.category == 'Transfer';

    final amountSign = isTransfer ? "" : (isIncome ? "+" : "-");
    final amountColor = isTransfer ? Colors.blue : (isIncome ? Colors.green : (isDark ? Colors.white : Colors.black87));
    final displayIcon = isTransfer ? Icons.swap_horiz_rounded : (isIncome ? Icons.south_west_rounded : Icons.category_rounded);

    return Dismissible(
      key: Key(e.id),
      direction: DismissDirection.endToStart,
      background: Container(alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), margin: const EdgeInsets.only(bottom: 12), decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(18)), child: const Icon(Icons.delete_outline_rounded, color: Colors.white)),
      confirmDismiss: (direction) async {
        return await showDialog(context: context, builder: (dialogCtx) => Dialog(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)), backgroundColor: Theme.of(context).cardColor, child: Padding(padding: const EdgeInsets.all(24.0), child: Column(mainAxisSize: MainAxisSize.min, children: [Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.1), shape: BoxShape.circle), child: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 28)), const SizedBox(height: 16), Text(isTransfer ? "Delete Transfer?" : "Delete Transaction?", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), const SizedBox(height: 8), Text(isTransfer ? "Delete this complete transfer? Both linked account entries will be removed." : "Are you sure you want to delete '${e.title}'? This action cannot be undone.", textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Colors.grey.shade500, height: 1.4)), const SizedBox(height: 24), Row(children: [Expanded(child: TextButton(style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), onPressed: () => Navigator.of(dialogCtx).pop(false), child: const Text("Cancel", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)))), const SizedBox(width: 12), Expanded(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), onPressed: () => Navigator.of(dialogCtx).pop(true), child: const Text("Delete", style: TextStyle(fontWeight: FontWeight.bold))))])]))));
      },
      onDismissed: (direction) async {
        if (isTransfer) {
          await ref.read(expenseProvider.notifier).deleteTransferPair(e.id);
        } else {
          await ref.read(expenseProvider.notifier).deleteExpense(e.id);
        }
        if (!mounted) return;
        _showTransactionSuccess(
          "'${e.title}' was removed from your records.",
          title: isTransfer ? 'Transfer deleted' : 'Transaction deleted',
        );
      },
      child: GestureDetector(
        onTap: isTransfer ? null : () => _showAddOrEditModal(existing: e),
        child: Container(
            margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(18), border: Border.all(color: isDark ? primaryColor.withValues(alpha: 0.2) : Colors.grey.withValues(alpha: 0.12), width: 1.2)),
            child: Row(
              children: [
                Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: (isTransfer ? Colors.blue : (isIncome ? Colors.green : eColor)).withValues(alpha: 0.15), shape: BoxShape.circle), child: Icon(displayIcon, color: isTransfer ? Colors.blue : (isIncome ? Colors.green : eColor), size: 20)),
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
      child: Container(margin: const EdgeInsets.only(right: 8), padding: const EdgeInsets.symmetric(horizontal: 16), decoration: BoxDecoration(color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(20), border: Border.all(color: isDark ? Colors.white24 : Colors.grey.shade300, width: 1.2)), child: Row(children: [Icon(Icons.add_rounded, size: 16, color: isDark ? Colors.white70 : Colors.black87), const SizedBox(width: 4), Text("New", style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontWeight: FontWeight.bold, fontSize: 12))])),
    );
  }

  Widget _buildTab(String label, int index, bool isDark, Color primaryColor) {
    bool isSelected = _selectedCategoryTab == label;
    return GestureDetector(
        onTap: () => _selectCategory(label, index),
        onLongPress: label == 'All' ? null : () => _confirmDeleteCategory(label),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: isSelected ? primaryColor : Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(20),
            border: isSelected ? null : Border.all(color: isDark ? primaryColor.withValues(alpha: 0.25) : Colors.grey.withValues(alpha: 0.15), width: 1.2),
          ),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: TextStyle(color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87), fontWeight: isSelected ? FontWeight.bold : FontWeight.w600, fontSize: 12)),
                if (isSelected && label != 'All') ...[
                  const SizedBox(width: 6),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _confirmDeleteCategory(label),
                    child: const Padding(
                      padding: EdgeInsets.all(2),
                      child: Icon(Icons.close_rounded, size: 14, color: Colors.white),
                    ),
                  ),
                ],
              ],
            ),
          ),
        )
    );
  }

  Widget _buildSmartInputBar(Color primaryColor, bool isDark) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 160),
          child: _isListening
              ? Container(
                  key: const ValueKey('voice-listening'),
                  margin: const EdgeInsets.only(left: 24, right: 24, bottom: 7),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: isDark ? 0.16 : 0.08),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 8,
                        height: 8,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Voice NLP is listening — speak now',
                        style: TextStyle(
                          color: Colors.red,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                )
              : const SizedBox.shrink(key: ValueKey('voice-idle')),
        ),
        Container(
          height: 52,
          margin: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              width: _isListening ? 1.5 : 1,
              color: _isListening
                  ? Colors.red
                  : primaryColor.withValues(alpha: isDark ? 0.28 : 0.16),
            ),
          ),
          child: TextField(
            controller: _smartInputCtrl,
            textInputAction: TextInputAction.done,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            onSubmitted: _processNLP,
            decoration: InputDecoration(
              hintText: _isListening ? 'Listening…' : 'e.g. 500 for groceries',
              hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 12),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.only(left: 16, top: 16, bottom: 16),
              suffixIconConstraints: const BoxConstraints(minHeight: 40),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Scan receipt',
                    visualDensity: VisualDensity.compact,
                    onPressed: _isScanningReceipt ? null : _scanReceiptIntoInput,
                    icon: _isScanningReceipt
                        ? SizedBox(
                            width: 17,
                            height: 17,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: primaryColor,
                            ),
                          )
                        : Icon(Icons.document_scanner_outlined, size: 20, color: primaryColor),
                  ),
                  IconButton(
                    tooltip: _isListening ? 'Stop listening' : 'Voice input',
                    visualDensity: VisualDensity.compact,
                    onPressed: _listenForExpense,
                    icon: Icon(
                      _isListening ? Icons.stop_circle_rounded : Icons.mic_none_rounded,
                      size: 21,
                      color: _isListening ? Colors.red : primaryColor,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Review quick entry',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _processNLP(_smartInputCtrl.text),
                    icon: Icon(Icons.arrow_upward_rounded, size: 20, color: primaryColor),
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMiniHero(double totalAvailable, Color primary) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
          gradient: LinearGradient(colors: [primary, primary.withValues(alpha: 0.8)]),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: primary.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 4))]
      ),
      child: Center(
        child: Text("Total: Rs. ${totalAvailable.toStringAsFixed(0)}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
      ),
    );
  }

  Widget _buildHeroCard(double totalAvailable, double spent, List<Wallet> wallets, Color primary) {
    final activeWallets = wallets.where((w) => !w.isBackup).take(3).toList();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      decoration: BoxDecoration(
          gradient: LinearGradient(colors: [primary, primary.withValues(alpha: 0.8)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(28),
          boxShadow: [BoxShadow(color: primary.withValues(alpha: 0.35), blurRadius: 18, offset: const Offset(0, 8))]
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Total Available", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, fontSize: 13)),
              IconButton(
                tooltip: 'Manage money accounts',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                onPressed: _openIncomeAccounts,
                icon: const Icon(Icons.edit_outlined, color: Colors.white70, size: 19),
              ),
            ],
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text("Rs. ${totalAvailable.toStringAsFixed(0)}", style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: -1.0)),
          ),
          const SizedBox(height: 16),

          if (activeWallets.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: List.generate(activeWallets.length, (index) {
                  final w = activeWallets[index];
                  final balance = ref.read(walletProvider.notifier).getBalanceForWallet(w.id);
                  return Padding(
                    padding: EdgeInsets.only(bottom: index == activeWallets.length - 1 ? 0 : 6.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.account_balance_wallet_rounded, size: 12, color: Colors.white.withValues(alpha: 0.7)),
                            const SizedBox(width: 6),
                            Text(w.name, style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 12, fontWeight: FontWeight.w500)),
                          ],
                        ),
                        Text("Rs. ${balance.toStringAsFixed(0)}", style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  );
                }),
              ),
            ),

          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Spent This Month", style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12, fontWeight: FontWeight.w500)),
              Text("Rs. ${spent.toStringAsFixed(0)}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
            ],
          )
        ],
      ),
    );
  }

  Future<void> _pickBudgetMonth() async {
    var selectedYear = _focusedMonth.year;
    final selected = await showDialog<DateTime>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Select month and year'),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  value: selectedYear,
                  decoration: const InputDecoration(
                    labelText: 'Year',
                    prefixIcon: Icon(Icons.calendar_today_rounded),
                  ),
                  items: [
                    for (var year = 2000; year <= 2100; year++)
                      DropdownMenuItem(value: year, child: Text('$year')),
                  ],
                  onChanged: (year) {
                    if (year != null) {
                      setDialogState(() => selectedYear = year);
                    }
                  },
                ),
                const SizedBox(height: 16),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 2.2,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: 12,
                  itemBuilder: (context, index) {
                    final month = index + 1;
                    final isSelected = selectedYear == _focusedMonth.year &&
                        month == _focusedMonth.month;
                    return FilledButton.tonal(
                      style: FilledButton.styleFrom(
                        backgroundColor: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : null,
                        foregroundColor: isSelected ? Colors.white : null,
                        padding: EdgeInsets.zero,
                      ),
                      onPressed: () => Navigator.pop(
                        dialogContext,
                        DateTime(selectedYear, month, 1),
                      ),
                      child: Text(DateFormat.MMM().format(DateTime(2000, month))),
                    );
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
    if (selected != null && mounted) {
      setState(() => _focusedMonth = selected);
    }
  }

  Widget _buildMonthSelector(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 16),
            onPressed: () => setState(() => _focusedMonth =
                DateTime(_focusedMonth.year, _focusedMonth.month - 1, 1)),
          ),
          TextButton.icon(
            onPressed: _pickBudgetMonth,
            icon: const Icon(Icons.calendar_month_rounded, size: 18),
            label: Text(
              DateFormat.yMMMM().format(_focusedMonth),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
            onPressed: () => setState(() => _focusedMonth =
                DateTime(_focusedMonth.year, _focusedMonth.month + 1, 1)),
          ),
        ],
      ),
    );
  }

  Future<void> _listenForExpense() async {
    if (_isListening) {
      await _speech.stop();
      await HapticFeedback.selectionClick();
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
        final languageUnavailable =
            error.errorMsg.contains('error_language_unavailable');
        _showTransactionError(
          languageUnavailable
              ? 'English speech recognition is unavailable on this phone. Install or enable an English speech language in Google voice typing, then try again.'
              : 'Voice Log stopped before an entry could be saved. Please try again.',
          title: languageUnavailable
              ? 'Speech language unavailable'
              : 'Voice Log stopped',
        );
      },
    );
    if (!mounted) return;
    if (!available) {
      _showTransactionError(
        'Allow microphone and speech-recognition access in phone settings, then try again.',
        title: 'Permission required',
      );
      return;
    }

    final speechLocaleId = await _resolveSpeechLocale();
    if (!mounted) return;
    if (speechLocaleId == null) {
      _showTransactionError(
        'Install an English speech-recognition language in Google voice typing and reopen Likhlo.',
        title: 'English speech language required',
      );
      return;
    }

    setState(() => _isListening = true);
    await HapticFeedback.mediumImpact();
    await _speech.listen(
      localeId: speechLocaleId,
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

  Future<String?> _resolveSpeechLocale() async {
    try {
      final locales = await _speech.locales();
      if (locales.isEmpty) return null;

      String normalize(String value) =>
          value.toLowerCase().replaceAll('-', '_');
      const preferred = ['en_us', 'en_gb', 'en_in', 'en_pk'];

      for (final preferredId in preferred) {
        for (final locale in locales) {
          if (normalize(locale.localeId) == preferredId) {
            return locale.localeId;
          }
        }
      }

      for (final locale in locales) {
        if (normalize(locale.localeId).startsWith('en_')) {
          return locale.localeId;
        }
      }
      return null;
    } catch (error) {
      debugPrint('Speech locale lookup failed: $error');
      return null;
    }
  }

  Future<void> _scanReceiptIntoInput() async {
    if (_isScanningReceipt) return;
    FocusScope.of(context).unfocus();
    setState(() => _isScanningReceipt = true);
    try {
      final receiptData = await OcrScannerService().scanReceipt();
      if (!mounted || receiptData == null) return;

      final amount = receiptData['amount'];
      if (amount is! num || !amount.isFinite || amount <= 0) {
        _showTransactionError(
          'No reliable receipt total was detected. Retake the photo with the full receipt visible and good lighting.',
          title: 'Receipt total not found',
        );
        return;
      }

      final title = receiptData['title']?.toString().trim() ?? '';
      final confidence =
          (receiptData['confidence'] as num?)?.toDouble() ?? 0.0;
      final confidencePercent = (confidence * 100).round();
      final reviewMessage = confidence < 0.7
          ? 'Scan confidence is $confidencePercent%. Carefully verify the amount, account, category, and date.'
          : 'Receipt details were detected with $confidencePercent% confidence. Verify every field before saving.';

      final confirmed = await _showAddOrEditModal(
        prefilledAmount: amount.toDouble() ==
                amount.toDouble().truncateToDouble()
            ? amount.toStringAsFixed(0)
            : amount.toStringAsFixed(2),
        prefilledTitle: title.isEmpty ? 'Receipt purchase' : title,
        prefilledCategory: receiptData['category']?.toString(),
        initialType: 'expense',
        reviewMessage: reviewMessage,
      );
      if (confirmed == true && mounted) {
        _showTransactionSuccess(
          'The reviewed receipt was added to your records.',
          title: 'Receipt saved',
        );
      }
    } finally {
      if (mounted) setState(() => _isScanningReceipt = false);
    }
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
    if (amount is! num || !amount.isFinite || amount <= 0) {
      _showTransactionError(
        "Include an amount in your entry, for example: '500 for biryani' or '1.5k petrol'.",
        title: 'Amount not detected',
      );
      return;
    }

    final wallets = ref.read(walletProvider);
    if (wallets.isEmpty) {
      _showTransactionError(
        'Create a money account before using Smart Entry.',
        title: 'Money account required',
      );
      return;
    }

    final mentionedWalletId = _findMentionedWalletId(normalized, wallets);
    final activeWallets =
        wallets.where((wallet) => !wallet.isBackup).toList(growable: false);
    final resolvedWalletId = mentionedWalletId ??
        (activeWallets.length == 1 ? activeWallets.first.id : null);
    final canSaveInstantly = shouldAutoSaveSmartEntry(
      result,
      hasResolvedWallet: resolvedWalletId != null,
    );

    if (canSaveInstantly && resolvedWalletId != null) {
      final type = result['type'] == 'income' ? 'income' : 'expense';
      final wallet = wallets.firstWhere(
        (item) => item.id == resolvedWalletId,
      );
      final amountValue = amount.toDouble();

      if (type == 'expense') {
        final available = ref
            .read(walletProvider.notifier)
            .getBalanceForWallet(resolvedWalletId);
        if (amountValue > available) {
          _showTransactionError(
            'Available in ${wallet.name}: Rs. ${available.toStringAsFixed(0)}. Required: Rs. ${amountValue.toStringAsFixed(0)}. Add money or choose another account manually.',
            title: 'Insufficient balance',
          );
          return;
        }
      }

      final entry = Expense(
        id: const Uuid().v4(),
        title: result['title']?.toString() ??
            (type == 'income' ? 'Income / Allowance' : 'Quick Expense'),
        amount: amountValue,
        category: type == 'income'
            ? 'Income / Allowance'
            : result['category']?.toString() ?? 'General',
        date: result['date'] is DateTime
            ? result['date'] as DateTime
            : DateTime.now(),
        colorValue:
            Color(ref.read(settingsProvider).profileColorValue).toARGB32(),
        type: type,
        walletId: resolvedWalletId,
      );

      final saved =
          await ref.read(expenseProvider.notifier).addExpense(entry);
      if (!mounted) return;
      if (!saved) {
        _showTransactionError(
          'The entry could not be saved. Check the selected account balance and try again.',
          title: 'Smart Entry not saved',
        );
        return;
      }

      _smartInputCtrl.clear();
      FocusScope.of(context).unfocus();
      await HapticFeedback.lightImpact();
      if (!mounted) return;
      _showTransactionSuccess(
        '${entry.title} — Rs. ${entry.amount.toStringAsFixed(0)} from ${wallet.name}',
        title: type == 'income' ? 'Income added' : 'Expense saved',
        actionLabel: 'Undo',
        onAction: () async {
          final deleted = await ref
              .read(expenseProvider.notifier)
              .deleteExpense(entry.id);
          if (!mounted) return;
          if (deleted) {
            _showTransactionInfo(
              'The instant Smart Entry was removed.',
              title: 'Entry undone',
            );
          }
        },
      );
      return;
    }

    final confidence =
        (result['confidence'] as num?)?.toDouble() ?? 0.0;
    final confidencePercent = (confidence * 100).round();
    final needsAccount = resolvedWalletId == null;
    final reviewMessage = needsAccount
        ? 'Choose the correct money account. The other detected details are editable before saving.'
        : 'Some details are uncertain ($confidencePercent% confidence). Review the amount, type, category, and date.';

    final confirmed = await _showAddOrEditModal(
      prefilledAmount:
          amount.toDouble() == amount.toDouble().truncateToDouble()
              ? amount.toStringAsFixed(0)
              : amount.toStringAsFixed(2),
      prefilledTitle: result['title']?.toString(),
      prefilledCategory: result['category']?.toString(),
      prefilledDate: result['date'] is DateTime
          ? result['date'] as DateTime
          : DateTime.now(),
      preselectedWalletId: resolvedWalletId,
      initialType: result['type'] == 'income' ? 'income' : 'expense',
      reviewMessage: reviewMessage,
    );

    if (confirmed == true && mounted) {
      _smartInputCtrl.clear();
      _showTransactionSuccess(
        'Your reviewed Smart Entry was added to the selected account.',
        title: 'Transaction saved',
      );
    }
    if (mounted) FocusScope.of(context).unfocus();
  }

  String? _findMentionedWalletId(String text, List<Wallet> wallets) {
    final normalizedText = text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();
    final compactText = normalizedText.replaceAll(' ', '');
    final sortedWallets = List<Wallet>.from(wallets)
      ..sort((a, b) => b.name.length.compareTo(a.name.length));

    for (final wallet in sortedWallets) {
      final normalizedName = wallet.name
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
          .trim();
      if (normalizedName.isEmpty) continue;

      final exactName = RegExp(
        '(^|\\s)${RegExp.escape(normalizedName)}(\\s|\$)',
      );
      if (exactName.hasMatch(normalizedText)) return wallet.id;

      final compactName = normalizedName.replaceAll(' ', '');
      if (compactName.length >= 5 && compactText.contains(compactName)) {
        return wallet.id;
      }
    }
    return null;
  }
}


enum _MessageTone { error, success, info }

class _TopMessageCard extends StatelessWidget {
  final String title;
  final String message;
  final _MessageTone tone;
  final String? actionLabel;
  final Future<void> Function()? onAction;
  final VoidCallback onDismiss;

  const _TopMessageCard({
    required this.title,
    required this.message,
    required this.tone,
    required this.actionLabel,
    required this.onAction,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final Color accent;
    final Color background;
    final Color foreground;
    final IconData icon;

    switch (tone) {
      case _MessageTone.error:
        accent = scheme.error;
        background = scheme.errorContainer;
        foreground = scheme.onErrorContainer;
        icon = Icons.error_outline_rounded;
      case _MessageTone.success:
        accent = const Color(0xFF16A34A);
        background = isDark ? const Color(0xFF123524) : const Color(0xFFF0FDF4);
        foreground = isDark ? const Color(0xFFDCFCE7) : const Color(0xFF14532D);
        icon = Icons.check_circle_outline_rounded;
      case _MessageTone.info:
        accent = scheme.primary;
        background = scheme.primaryContainer;
        foreground = scheme.onPrimaryContainer;
        icon = Icons.info_outline_rounded;
    }

    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      tween: Tween(begin: 0, end: 1),
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, -14 * (1 - value)),
          child: child,
        ),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Material(
          color: Colors.transparent,
          child: Semantics(
            container: true,
            liveRegion: true,
            label: '$title. $message',
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 13, 8, 13),
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: accent.withValues(alpha: 0.28)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.14),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: accent, size: 21),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: foreground,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          message,
                          style: TextStyle(
                            color: foreground.withValues(alpha: 0.82),
                            fontSize: 13,
                            height: 1.35,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (actionLabel != null && onAction != null) ...[
                          const SizedBox(height: 7),
                          TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: accent,
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(0, 30),
                              tapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () async {
                              onDismiss();
                              await onAction!();
                            },
                            child: Text(
                              actionLabel!,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Dismiss message',
                    onPressed: onDismiss,
                    icon: Icon(
                      Icons.close_rounded,
                      color: foreground.withValues(alpha: 0.65),
                      size: 19,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
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