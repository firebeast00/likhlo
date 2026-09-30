import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'dart:async';

import '../models/debt_model.dart';
import '../models/wallet_model.dart';
import '../services/notification_service.dart';
import '../services/local_nlp_service.dart';
import '../services/udhar_input_service.dart';
import '../services/pakistani_language_normalizer.dart';
import '../providers/wallet_provider.dart';
import '../services/ocr_scanner_service.dart';
import '../providers/settings_provider.dart';
import '../models/expense_model.dart';
import '../services/transaction_executor.dart';
import '../services/speech_session_controller.dart';
import '../services/udhar_ledger_link_service.dart';
import '../providers/expense_provider.dart';

class DebtScreen extends ConsumerStatefulWidget {
  final bool embedded;

  const DebtScreen({super.key, this.embedded = false});

  @override
  ConsumerState<DebtScreen> createState() => _DebtScreenState();
}

class _DebtScreenState extends ConsumerState<DebtScreen> {
  static const _udharDefaultWalletKey = 'udhar_default_wallet_id';

  final Box<DebtEntry> debtBox = Hive.box<DebtEntry>('debts');

  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  bool _voiceFinalizing = false;
  bool _savingDebt = false;
  bool _scanningDebt = false;
  final SpeechSessionController _speechSession =
      SpeechSessionController(maxRetries: 0);
  String? _selectedWalletId;
  String _udharFilter = 'all';
  final TextEditingController _smartInputCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final stored = Hive.box('preferences').get(_udharDefaultWalletKey);
    _selectedWalletId =
        stored is String && stored.trim().isNotEmpty ? stored : null;
  }

  String? get _activeWalletId {
    final wallets = ref.read(walletProvider);
    if (wallets.isEmpty) return null;
    if (wallets.any((wallet) => wallet.id == _selectedWalletId)) {
      return _selectedWalletId;
    }
    for (final wallet in wallets) {
      if (!wallet.isBackup && wallet.walletType == 'cash') {
        return wallet.id;
      }
    }
    return wallets.first.id;
  }

  List<SmartEntryAccount> _udharAccounts() {
    final wallets = ref.read(walletProvider);
    return wallets.map((wallet) => SmartEntryAccount(
      id: wallet.id,
      name: wallet.name,
      type: wallet.walletType,
      isBackup: wallet.isBackup,
      availableBalance: ref.read(walletProvider.notifier).getBalanceForWallet(wallet.id),
    )).toList(growable: false);
  }

  String? _walletForCommand(String text) {
    final normalized =
        PakistaniLanguageNormalizer().normalize(text).normalized;
    final matches =
        findMentionedSmartEntryAccountIds(normalized, _udharAccounts());
    if (matches.length > 1) return null;
    return matches.isEmpty ? _activeWalletId : matches.single;
  }

  Wallet? _walletById(List<Wallet> wallets, String? id) {
    if (id == null) return null;
    for (final wallet in wallets) {
      if (wallet.id == id) return wallet;
    }
    return null;
  }

  String _walletLabel(List<Wallet> wallets, String? id) {
    return _walletById(wallets, id)?.name ?? 'Wallet unavailable';
  }

  String _quickWalletLabel(List<Wallet> wallets) {
    if (_selectedWalletId == null) return 'Automatic';
    return _walletLabel(wallets, _selectedWalletId);
  }

  IconData _walletIcon(Wallet wallet) {
    final type = wallet.walletType.toLowerCase();
    if (type == 'cash') return Icons.payments_outlined;
    if (type == 'jazzcash' || type == 'easypaisa') {
      return Icons.account_balance_wallet_outlined;
    }
    if (type == 'bank') return Icons.account_balance_outlined;
    return Icons.wallet_outlined;
  }

  Future<void> _showUdharWalletPicker() async {
    FocusScope.of(context).unfocus();
    final wallets = ref.read(walletProvider);
    if (wallets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Create a wallet first.')),
      );
      return;
    }
    final walletNotifier = ref.read(walletProvider.notifier);
    final selectedId =
        wallets.any((wallet) => wallet.id == _selectedWalletId)
            ? _selectedWalletId
            : null;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.72,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Default Quick Udhar wallet',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 12),
                children: [
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Theme.of(sheetContext)
                          .colorScheme
                          .primaryContainer,
                      child: Icon(
                        Icons.auto_awesome_rounded,
                        color: Theme.of(sheetContext).colorScheme.primary,
                      ),
                    ),
                    title: const Text(
                      'Automatic',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: const Text(
                      'Use Cash first; an explicitly named wallet still wins',
                    ),
                    trailing: selectedId == null
                        ? const Icon(Icons.check_circle_rounded)
                        : null,
                    onTap: () async {
                      await Hive.box('preferences')
                          .delete(_udharDefaultWalletKey);
                      if (!mounted) return;
                      setState(() => _selectedWalletId = null);
                      if (sheetContext.mounted) {
                        Navigator.pop(sheetContext);
                      }
                    },
                  ),
                  const Divider(height: 1),
                  for (final wallet in wallets)
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Color(wallet.colorValue)
                            .withValues(alpha: 0.14),
                        child: Icon(
                          _walletIcon(wallet),
                          color: Color(wallet.colorValue),
                          size: 20,
                        ),
                      ),
                      title: Text(
                        wallet.name,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        '${wallet.isBackup ? 'Reserve wallet' : 'Available'} · Rs. ${walletNotifier.getBalanceForWallet(wallet.id).toStringAsFixed(0)}',
                      ),
                      trailing: selectedId == wallet.id
                          ? const Icon(Icons.check_circle_rounded)
                          : null,
                      onTap: () async {
                        await Hive.box('preferences').put(
                          _udharDefaultWalletKey,
                          wallet.id,
                        );
                        if (!mounted) return;
                        setState(() => _selectedWalletId = wallet.id);
                        if (sheetContext.mounted) {
                          Navigator.pop(sheetContext);
                        }
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    unawaited(_speech.cancel());
    _smartInputCtrl.dispose();
    super.dispose();
  }

  void _listenForInput() async {
    if (_voiceFinalizing || _savingDebt) return;
    if (!_isListening) {
      _speechSession.start();
      bool available = await _speech.initialize(
        onStatus: (val) {
          if (!mounted) return;
          if (val == 'done' || val == 'notListening') {
            unawaited(_finishVoiceInput(finalResult: false));
          }
        },
        onError: (val) {
          _speechSession.onRecognizerError(retryable: false);
          if (mounted) {
            setState(() => _isListening = false);
            _smartInputCtrl.clear();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Voice recognition stopped. Please try again.'),
              ),
            );
          }
        },
      );

      if (!mounted) return;

      if (available) {
        final localeId = await _preferredSpeechLocale();
        if (!mounted) return;
        setState(() => _isListening = true);
        _smartInputCtrl.clear();
        await _speech.listen(
          listenOptions: stt.SpeechListenOptions(
            localeId: localeId,
            cancelOnError: true,
            listenMode: stt.ListenMode.dictation,
            pauseFor: const Duration(seconds: 7),
            listenFor: const Duration(seconds: 45),
            partialResults: true,
          ),
          onResult: (val) {
            if (!mounted || !_isListening) return;
            final words = val.recognizedWords.trim();
            if (words.isNotEmpty) {
              final decision = _speechSession.recordTranscript(
                words,
                isFinal: val.finalResult,
              );
              _smartInputCtrl.value = TextEditingValue(
                text: words,
                selection: TextSelection.collapsed(offset: words.length),
              );
              if (decision.action == SpeechSessionAction.processFinal) {
                unawaited(_finishVoiceInput(finalResult: true, decision: decision));
              }
            }
          },
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Speech recognition unavailable.",
              style: TextStyle(fontSize: 13),
            ),
          ),
        );
      }
    } else {
      await _finishVoiceInput(finalResult: false);
    }
  }

  Future<String?> _preferredSpeechLocale() async {
    try {
      final locales = await _speech.locales();
      final preferences = ref.read(settingsProvider).smartEntryLanguage == 'romanUrdu'
          ? const ['ur_pk', 'ur', 'ur_in', 'en_pk', 'en_in']
          : const ['en_pk', 'en_in', 'en_gb', 'en_us'];
      for (final preferred in preferences) {
        for (final locale in locales) {
          if (locale.localeId.toLowerCase().replaceAll('-', '_') == preferred) {
            return locale.localeId;
          }
        }
      }
    } catch (_) {
      // The recognizer will use its device locale when lookup is unavailable.
    }
    return null;
  }

  Future<void> _finishVoiceInput({
    required bool finalResult,
    SpeechSessionDecision? decision,
  }) async {
    if (!_isListening || _voiceFinalizing) return;
    _voiceFinalizing = true;
    setState(() => _isListening = false);
    try {
      final result = decision ?? _speechSession.onRecognizerStopped();
      await _speech.stop();
      if (!mounted) return;
      if (result.action == SpeechSessionAction.processFinal &&
          result.transcript.isNotEmpty) {
        await _processNLP(
          result.transcript,
          fromVoice: true,
          allowInstantSave: finalResult,
        );
      } else {
        _smartInputCtrl.clear();
      }
    } catch (_) {
      if (mounted) _smartInputCtrl.clear();
    } finally {
      _speechSession.reset();
      _voiceFinalizing = false;
    }
  }

  Future<void> _processNLP(String text, {
    bool fromVoice = false,
    bool allowInstantSave = true,
  }) async {
    if (text.trim().isEmpty || _savingDebt) return;
    final wallets = ref.read(walletProvider);
    final draft = const UdharInputService().parse(
      text,
      walletNames: wallets.map((wallet) => wallet.name),
      accounts: _udharAccounts(),
    );
    if (draft == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Say an amount and person, e.g. 'Ali ko 500 udhaar diya'.",
          ),
        ),
      );
      if (fromVoice) _smartInputCtrl.clear();
      return;
    }
    final walletId = _walletForCommand(text);
    if (allowInstantSave && draft.canSaveImmediately && walletId != null) {
      final saved = await _saveDebtRecord(
        name: draft.person,
        amount: draft.amount,
        type: draft.type,
        walletId: walletId,
      );
      if (saved && mounted) _smartInputCtrl.clear();
    } else {
      _showAddDialog(
        initialName: draft.person,
        initialAmount: draft.amount.toStringAsFixed(
          draft.amount == draft.amount.truncateToDouble() ? 0 : 2,
        ),
        initialType: draft.type,
        initialWalletId: walletId,
      );
      if (fromVoice) _smartInputCtrl.clear();
    }
    if (mounted) FocusScope.of(context).unfocus();
  }

  void _startReceiptScan() async {
    if (_scanningDebt) return;
    setState(() => _scanningDebt = true);
    try {
      final receipt = await OcrScannerService().scanReceiptDetailed();
      if (!mounted || receipt == null) return;
      final wallets = ref.read(walletProvider);
      final draft = const UdharInputService().parse(
        receipt.rawText,
        walletNames: wallets.map((wallet) => wallet.name),
        accounts: _udharAccounts(),
      );
      if (draft != null &&
          draft.canSaveImmediately &&
          receipt.total > 0 &&
          draft.amount == receipt.total &&
          receipt.confidence >= 0.85 &&
          _walletForCommand(receipt.rawText) != null) {
        await _saveDebtRecord(
          name: draft.person,
          amount: draft.amount,
          type: draft.type,
          walletId: _walletForCommand(receipt.rawText)!,
        );
      } else {
        _showAddDialog(
          initialName: draft?.person ?? '',
          initialAmount:
              (receipt.total > 0 ? receipt.total : draft?.amount ?? 0) > 0
              ? (receipt.total > 0 ? receipt.total : draft!.amount)
                    .toStringAsFixed(0)
              : '',
          initialType: draft?.type ?? 'lent',
          initialWalletId: _walletForCommand(receipt.rawText),
        );
      }
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Receipt scan failed. Try another photo.'),
          ),
        );
    } finally {
      if (mounted) setState(() => _scanningDebt = false);
    }
  }

  Future<bool> _saveDebtRecord({
    required String name,
    required double amount,
    required String type,
    required String walletId,
    DateTime? dueDate,
  }) async {
    if (_savingDebt) return false;
    final person = name.trim();
    final wallets = ref.read(walletProvider);
    if ((type != 'lent' && type != 'borrowed') ||
        person.isEmpty ||
        amount <= 0 ||
        !amount.isFinite ||
        !wallets.any((wallet) => wallet.id == walletId)) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Enter a person, valid amount and wallet.'),
          ),
        );
      return false;
    }
    if (type == 'lent') {
      final available = ref
          .read(walletProvider.notifier)
          .getBalanceForWallet(walletId);
      if (available + 0.000001 < amount) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Insufficient balance. Available: Rs. ${available.toStringAsFixed(0)}.',
              ),
            ),
          );
        return false;
      }
    }
    _savingDebt = true;
    final debtId = const Uuid().v4();
    dynamic key;
    try {
      key = await debtBox.add(
        DebtEntry(
          id: debtId,
          borrowerName: person,
          amount: amount,
          type: type,
          dueDate: dueDate,
          walletId: walletId,
        ),
      );
      final result = await ref.read(transactionExecutorProvider).execute(
        CreateTransactionCommand(
          Expense(
            id: debtId,
            title: type == 'lent' ? 'Udhaar: $person' : 'Borrowed from $person',
            amount: amount,
            category: 'Udhaar',
            date: DateTime.now(),
            colorValue: type == 'lent'
                ? Colors.red.toARGB32()
                : Colors.green.toARGB32(),
            type: type == 'lent' ? 'expense' : 'income',
            walletId: walletId,
          ),
        ),
      );
      if (!result.succeeded) {
        await debtBox.delete(key);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.reason ?? 'Udhaar could not be saved.'),
            ),
          );
        }
        return false;
      }
      if (dueDate != null && dueDate.isAfter(DateTime.now())) {
        unawaited(
          NotificationService().scheduleNotification(
            key,
            'Udhaar Due Today! 💰',
            '${type == 'lent' ? 'Collect' : 'Pay'} Rs. ${amount.toStringAsFixed(0)} ${type == 'lent' ? 'from' : 'to'} $person',
            dueDate,
          ),
        );
      }
      if (mounted) {
        _smartInputCtrl.clear();
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Udhaar recorded: Rs. ${amount.toStringAsFixed(0)} · $person',
            ),
          ),
        );
      }
      return true;
    } catch (_) {
      if (key != null) await debtBox.delete(key);
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Udhaar could not be saved. Try again.'),
          ),
        );
      return false;
    } finally {
      _savingDebt = false;
    }
  }

  Future<bool> _settleDebtRecord(DebtEntry debt) async {
    if (_savingDebt) return false;
    _savingDebt = true;
    var createdSettlement = false;
    try {
      final original = ref.read(expenseProvider.notifier).findById(debt.id);
      if (original == null) {
        // Older borrowed records never created a ledger movement. Preserve
        // their historical behavior instead of inventing past income.
        await debtBox.put(
          debt.key ?? debt.id,
          debt.copyWith(deletedAt: DateTime.now()),
        );
      } else {
        final walletId = debt.walletId ?? original.walletId;
        final wallet = ref.read(walletProvider)
            .where((item) => item.id == walletId);
        if (wallet.isEmpty) return false;
        final settlement = Expense(
          id: UdharLedgerLinkService.settlementId(debt.id),
          title: debt.type == 'lent'
              ? 'Udhaar returned: ${debt.borrowerName}'
              : 'Udhaar repaid: ${debt.borrowerName}',
          amount: debt.amount,
          category: 'Udhaar',
          date: DateTime.now(),
          colorValue: debt.type == 'lent'
              ? Colors.green.toARGB32()
              : Colors.red.toARGB32(),
          type: debt.type == 'lent' ? 'income' : 'expense',
          walletId: walletId,
        );
        final result = await ref.read(transactionExecutorProvider).execute(
          CreateTransactionCommand(settlement),
        );
        if (!result.succeeded) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(result.reason ?? 'Udhaar could not be settled.'),
            ));
          }
          return false;
        }
        createdSettlement = true;
        await debtBox.put(
          debt.key ?? debt.id,
          debt.copyWith(settledAt: DateTime.now()),
        );
      }
      if (mounted) setState(() {});
      return true;
    } catch (_) {
      if (createdSettlement) {
        final settlementId = UdharLedgerLinkService.settlementId(debt.id);
        if (await ref.read(expenseProvider.notifier).deleteExpense(settlementId)) {
          await ref.read(expenseProvider.notifier).permanentlyDelete(settlementId);
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Udhaar could not be settled.')),
        );
      }
      return false;
    } finally {
      _savingDebt = false;
    }
  }

  void _showAddDialog({
    String initialName = "",
    String initialAmount = "",
    String initialType = 'lent',
    String? initialWalletId,
  }) {
    final nameCtrl = TextEditingController(text: initialName);
    final amountCtrl = TextEditingController(text: initialAmount);
    String type = initialType;
    String? selectedWalletId = initialWalletId ?? _activeWalletId;
    DateTime? selectedDate;

    final settings = ref.read(settingsProvider);
    final primaryColor = Color(settings.profileColorValue);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return AlertDialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 24,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            backgroundColor: Theme.of(context).cardColor,
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.handshake_rounded,
                    color: primaryColor,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    "Udhaar Record",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
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
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: type == 'lent'
                                      ? Colors.green
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Center(
                                  child: Text(
                                    "I Gave (Lent)",
                                    style: TextStyle(
                                      color: type == 'lent'
                                          ? Colors.white
                                          : Colors.grey.shade500,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () =>
                                  setModalState(() => type = 'borrowed'),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: type == 'borrowed'
                                      ? Colors.red
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Center(
                                  child: Text(
                                    "I Took (Borrowed)",
                                    style: TextStyle(
                                      color: type == 'borrowed'
                                          ? Colors.white
                                          : Colors.grey.shade500,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildModernInput(
                      nameCtrl,
                      "Person Name",
                      Icons.person_rounded,
                      primaryColor,
                      isDark,
                    ),
                    const SizedBox(height: 12),
                    _buildModernInput(
                      amountCtrl,
                      "Amount (Rs.)",
                      Icons.attach_money_rounded,
                      primaryColor,
                      isDark,
                      isNumber: true,
                    ),
                    const SizedBox(height: 12),

                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue:
                          ref
                              .read(walletProvider)
                              .any((wallet) => wallet.id == selectedWalletId)
                          ? selectedWalletId
                          : null,
                      decoration: InputDecoration(
                        labelText: type == 'lent'
                            ? 'Paid from wallet'
                            : 'Receiving wallet',
                        prefixIcon: const Icon(
                          Icons.account_balance_wallet_outlined,
                        ),
                        border: const OutlineInputBorder(),
                      ),
                      items: ref
                          .read(walletProvider)
                          .map(
                            (wallet) => DropdownMenuItem(
                              value: wallet.id,
                              child: Text(
                                wallet.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (id) =>
                          setModalState(() => selectedWalletId = id),
                    ),
                    const SizedBox(height: 12),

                    // DATE PICKER
                    GestureDetector(
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: DateTime.now(),
                          firstDate: DateTime.now(),
                          lastDate: DateTime(2030),
                        );
                        if (date != null) {
                          setModalState(() => selectedDate = date);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.black26 : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.calendar_today_rounded,
                              color: Colors.grey.shade500,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              selectedDate == null
                                  ? "Set Due Date (Optional)"
                                  : "Due: ${DateFormat.yMMMd().format(selectedDate!)}",
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                color: selectedDate == null
                                    ? Colors.grey.shade500
                                    : (isDark ? Colors.white : Colors.black87),
                              ),
                            ),
                            const Spacer(),
                            Icon(
                              Icons.edit_calendar_rounded,
                              size: 18,
                              color: Colors.grey.shade400,
                            ),
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
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text(
                        "Cancel",
                        style: TextStyle(
                          color: Colors.grey,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
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
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () async {
                        final walletId = selectedWalletId;
                        if (walletId == null) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(
                              content: Text('Choose a wallet first.'),
                            ),
                          );
                          return;
                        }
                      final saved = await _saveDebtRecord(
                        name: nameCtrl.text,
                          amount: double.tryParse(amountCtrl.text.trim()) ?? 0,
                          type: type,
                          walletId: walletId,
                        dueDate: selectedDate,
                      );
                      if (saved) {
                        unawaited(NotificationService().showManualLedgerResult(
                          'Udhaar saved',
                          '${nameCtrl.text.trim()} · Rs. ${amountCtrl.text.trim()}',
                        ));
                      }
                      if (saved && ctx.mounted) Navigator.pop(ctx);
                      },
                      child: const Text(
                        "Save Record",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildModernInput(
    TextEditingController ctrl,
    String label,
    IconData icon,
    Color primaryColor,
    bool isDark, {
    bool isNumber = false,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      textCapitalization: isNumber
          ? TextCapitalization.none
          : TextCapitalization.words,
      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey.shade500, fontSize: 13),
        prefixIcon: Icon(icon, color: Colors.grey.shade500, size: 20),
        filled: true,
        fillColor: isDark ? Colors.black26 : Colors.grey.shade50,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: primaryColor, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          vertical: 14,
          horizontal: 16,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(expenseProvider);
    final debts = debtBox.values
        .where((entry) => entry.deletedAt == null && entry.settledAt == null)
        .toList();
    final settings = ref.watch(settingsProvider);
    final wallets = ref.watch(walletProvider);
    final primaryColor = Color(settings.profileColorValue);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    double iGave = debts
        .where((e) => e.type == 'lent')
        .fold(0.0, (sum, e) => sum + e.amount);
    double iTook = debts
        .where((e) => e.type == 'borrowed')
        .fold(0.0, (sum, e) => sum + e.amount);
    double balance = iGave - iTook;

    final body = Column(
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
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Net Balance",
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                  Icon(
                    balance >= 0
                        ? Icons.trending_up_rounded
                        : Icons.trending_down_rounded,
                    color: Colors.white.withValues(alpha: 0.8),
                    size: 20,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    balance < 0 ? "-" : "",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                  ),
                  Text(
                    "Rs. ${balance.abs().toStringAsFixed(0)}",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
              Text(
                balance >= 0 ? "Overall you will receive" : "Overall you owe",
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: _summaryBox("I Gave", iGave, Colors.greenAccent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _summaryBox(
                      "I Took",
                      iTook,
                      Colors.redAccent.shade100,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
          child: DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: wallets.any((wallet) => wallet.id == _activeWalletId)
                ? _activeWalletId
                : null,
            decoration: const InputDecoration(
              labelText: 'Udhaar wallet',
              prefixIcon: Icon(Icons.account_balance_wallet_outlined),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: wallets
                .map(
                  (wallet) => DropdownMenuItem(
                    value: wallet.id,
                    child: Text(wallet.name, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: (id) => setState(() => _selectedWalletId = id),
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
              border: Border.all(
                color: isDark
                    ? primaryColor.withValues(alpha: 0.4)
                    : Colors.grey.withValues(alpha: 0.2),
                width: 1.2,
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  padding: EdgeInsets.zero,
                  icon: Icon(
                    _isListening ? Icons.mic : Icons.mic_none_rounded,
                    color: _isListening ? Colors.red : primaryColor,
                    size: 20,
                  ),
                  onPressed: _listenForInput,
                ),
                Expanded(
                  child: TextField(
                    controller: _smartInputCtrl,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: _isListening
                          ? 'Listening...'
                          : 'Speak: "Borrowed 500 from Sara"',
                      border: InputBorder.none,
                      hintStyle: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 12,
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 8,
                      ),
                    ),
                    onSubmitted: (val) => _processNLP(val),
                  ),
                ),
                IconButton(
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  padding: EdgeInsets.zero,
                  icon: const Icon(
                    Icons.document_scanner_rounded,
                    color: Colors.blueAccent,
                    size: 18,
                  ),
                  onPressed: _scanningDebt ? null : _startReceiptScan,
                  tooltip: "Scan Receipt",
                ),
                IconButton(
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
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
                      Icon(
                        Icons.handshake_rounded,
                        size: 60,
                        color: Colors.grey.withValues(alpha: 0.3),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        "No active records. You're all settled!",
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 4,
                  ),
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
                        decoration: BoxDecoration(
                          color: Colors.green,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Icon(
                              Icons.check_circle_rounded,
                              color: Colors.white,
                            ),
                            SizedBox(width: 8),
                            Text(
                              "Mark Settled",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      confirmDismiss: (_) async {
                        return _settleDebtRecord(item);
                      },
                      onDismissed: (_) {
                        if (!mounted) return;
                        unawaited(NotificationService().showManualLedgerResult(
                          'Udhaar settled',
                          '${item.borrowerName} · Rs. ${item.amount.toStringAsFixed(2)}',
                        ));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              "Settled Udhaar with ${item.borrowerName} 🤝",
                              style: const TextStyle(fontSize: 13),
                            ),
                            backgroundColor: Colors.green,
                          ),
                        );
                      },
                      child: Card(
                        elevation: 0,
                        color: Theme.of(context).cardColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color: isDark
                                ? primaryColor.withValues(alpha: 0.2)
                                : Colors.grey.withValues(alpha: 0.12),
                            width: 1.2,
                          ),
                        ),
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: isLent
                                      ? Colors.green.withValues(alpha: 0.15)
                                      : Colors.red.withValues(alpha: 0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  isLent
                                      ? Icons.arrow_upward_rounded
                                      : Icons.arrow_downward_rounded,
                                  color: isLent ? Colors.green : Colors.red,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      item.borrowerName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        Icon(
                                          item.dueDate != null
                                              ? Icons.calendar_month_rounded
                                              : Icons.info_outline_rounded,
                                          size: 11,
                                          color: Colors.grey.shade500,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          item.dueDate != null
                                              ? "Due: ${DateFormat.MMMEd().format(item.dueDate!)}"
                                              : (isLent
                                                    ? "You gave them"
                                                    : "They gave you"),
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey.shade500,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                "Rs. ${item.amount.toStringAsFixed(0)}",
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15,
                                  color: isLent ? Colors.green : Colors.red,
                                ),
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
    );
    final addButton = FloatingActionButton.extended(
      icon: const Icon(Icons.add_rounded),
      label: const Text("Add Record"),
      backgroundColor: primaryColor,
      foregroundColor: Colors.white,
      elevation: 4,
      onPressed: _showAddDialog,
    );
    if (widget.embedded) {
      return Stack(
        children: [
          Positioned.fill(child: body),
          Positioned(right: 18, bottom: 18, child: addButton),
        ],
      );
    }
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: body,
      floatingActionButton: addButton,
    );
  }

  Widget _summaryBox(String title, double amount, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            amount.toStringAsFixed(0),
            style: TextStyle(
              color: textColor,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
