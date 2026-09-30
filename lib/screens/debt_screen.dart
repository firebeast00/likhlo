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
        final walletName = _walletLabel(wallets, walletId);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Udhaar recorded: Rs. ${amount.toStringAsFixed(0)} · $person · $walletName',
            ),
            behavior: SnackBarBehavior.floating,
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

    unawaited(
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (sheetContext) => StatefulBuilder(
          builder: (context, setModalState) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final wallets = ref.read(walletProvider);
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Add Udhar',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Record money you gave or received as a loan.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<String>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(
                            value: 'lent',
                            label: Text('I Gave'),
                            icon: Icon(Icons.arrow_upward_rounded),
                          ),
                          ButtonSegment(
                            value: 'borrowed',
                            label: Text('I Took'),
                            icon: Icon(Icons.arrow_downward_rounded),
                          ),
                        ],
                        selected: {type},
                        onSelectionChanged: (selection) {
                          setModalState(() => type = selection.first);
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildModernInput(
                      nameCtrl,
                      'Person name',
                      Icons.person_outline_rounded,
                      primaryColor,
                      isDark,
                    ),
                    const SizedBox(height: 12),
                    _buildModernInput(
                      amountCtrl,
                      'Amount (Rs.)',
                      Icons.payments_outlined,
                      primaryColor,
                      isDark,
                      isNumber: true,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: wallets.any(
                        (wallet) => wallet.id == selectedWalletId,
                      )
                          ? selectedWalletId
                          : null,
                      decoration: InputDecoration(
                        labelText: type == 'lent'
                            ? 'Paid from'
                            : 'Received in',
                        prefixIcon: const Icon(
                          Icons.account_balance_wallet_outlined,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      items: wallets
                          .map(
                            (wallet) => DropdownMenuItem(
                              value: wallet.id,
                              child: Text(
                                wallet.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (id) {
                        setModalState(() => selectedWalletId = id);
                      },
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () async {
                        final now = DateTime.now();
                        final date = await showDatePicker(
                          context: context,
                          initialDate: selectedDate ?? now,
                          firstDate: now,
                          lastDate: DateTime(now.year + 5, 12, 31),
                        );
                        if (date != null) {
                          setModalState(() => selectedDate = date);
                        }
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 15,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.055)
                              : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Theme.of(context)
                                .colorScheme
                                .outlineVariant,
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.calendar_today_outlined,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                selectedDate == null
                                    ? 'Due date (optional)'
                                    : 'Due ${DateFormat.yMMMd().format(selectedDate!)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (selectedDate != null)
                              IconButton(
                                tooltip: 'Clear due date',
                                visualDensity: VisualDensity.compact,
                                onPressed: () {
                                  setModalState(() => selectedDate = null);
                                },
                                icon: const Icon(
                                  Icons.close_rounded,
                                  size: 18,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: primaryColor,
                        ),
                        onPressed: _savingDebt
                            ? null
                            : () async {
                                final walletId = selectedWalletId;
                                if (walletId == null) {
                                  ScaffoldMessenger.of(sheetContext)
                                      .showSnackBar(
                                    const SnackBar(
                                      content:
                                          Text('Choose a wallet first.'),
                                    ),
                                  );
                                  return;
                                }
                                final saved = await _saveDebtRecord(
                                  name: nameCtrl.text,
                                  amount: double.tryParse(
                                        amountCtrl.text.trim(),
                                      ) ??
                                      0,
                                  type: type,
                                  walletId: walletId,
                                  dueDate: selectedDate,
                                );
                                if (saved) {
                                  unawaited(
                                    NotificationService()
                                        .showManualLedgerResult(
                                      'Udhaar saved',
                                      '${nameCtrl.text.trim()} · Rs. ${amountCtrl.text.trim()}',
                                    ),
                                  );
                                }
                                if (saved && sheetContext.mounted) {
                                  Navigator.pop(sheetContext);
                                }
                              },
                        icon: const Icon(Icons.check_rounded),
                        label: const Text(
                          'Save record',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ).whenComplete(() {
        nameCtrl.dispose();
        amountCtrl.dispose();
      }),
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

  bool _isDueSoon(DebtEntry debt) {
    final due = debt.dueDate;
    if (due == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dueDay = DateTime(due.year, due.month, due.day);
    return !dueDay.isAfter(today.add(const Duration(days: 7)));
  }

  String _dueLabel(DebtEntry debt) {
    final due = debt.dueDate;
    if (due == null) return 'No due date';

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dueDay = DateTime(due.year, due.month, due.day);
    final difference = dueDay.difference(today).inDays;

    if (difference < 0) {
      final days = difference.abs();
      return '$days day${days == 1 ? '' : 's'} overdue';
    }
    if (difference == 0) return 'Due today';
    if (difference == 1) return 'Due tomorrow';
    if (difference <= 7) return 'Due in $difference days';
    return 'Due ${DateFormat.MMMd().format(due)}';
  }

  Color _dueColor(BuildContext context, DebtEntry debt) {
    final due = debt.dueDate;
    if (due == null) return Theme.of(context).colorScheme.onSurfaceVariant;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dueDay = DateTime(due.year, due.month, due.day);
    if (dueDay.isBefore(today)) return Colors.red;
    if (dueDay.difference(today).inDays <= 1) return Colors.orange;
    return Theme.of(context).colorScheme.primary;
  }

  List<DebtEntry> _visibleDebts(List<DebtEntry> debts) {
    Iterable<DebtEntry> visible = debts;
    switch (_udharFilter) {
      case 'receive':
        visible = visible.where((entry) => entry.type == 'lent');
        break;
      case 'owe':
        visible = visible.where((entry) => entry.type == 'borrowed');
        break;
      case 'due':
        visible = visible.where(_isDueSoon);
        break;
      case 'all':
      default:
        break;
    }

    final result = visible.toList(growable: false);
    result.sort((a, b) {
      final aDue = a.dueDate;
      final bDue = b.dueDate;
      if (aDue == null && bDue == null) return 0;
      if (aDue == null) return 1;
      if (bDue == null) return -1;
      return aDue.compareTo(bDue);
    });
    return result;
  }

  String _walletLabelForDebt(List<Wallet> wallets, DebtEntry debt) {
    final direct = _walletById(wallets, debt.walletId);
    if (direct != null) return direct.name;

    final original = ref.read(expenseProvider.notifier).findById(debt.id);
    final fallback = _walletById(wallets, original?.walletId);
    return fallback?.name ?? 'Legacy record';
  }

  Future<bool> _settleWithFeedback(DebtEntry debt) async {
    final settled = await _settleDebtRecord(debt);
    if (!settled || !mounted) return settled;

    unawaited(
      NotificationService().showManualLedgerResult(
        'Udhaar settled',
        '${debt.borrowerName} · Rs. ${debt.amount.toStringAsFixed(0)}',
      ),
    );
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            'Settled Udhaar with ${debt.borrowerName}',
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    return true;
  }

  void _showDebtDetails(DebtEntry debt, List<Wallet> wallets) {
    final isLent = debt.type == 'lent';
    final walletLabel = _walletLabelForDebt(wallets, debt);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  child: Icon(
                    isLent
                        ? Icons.arrow_upward_rounded
                        : Icons.arrow_downward_rounded,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    debt.borrowerName,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Text(
                  'Rs. ${debt.amount.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.swap_horiz_rounded),
              title: Text(isLent ? 'You will receive' : 'You owe'),
              subtitle: Text(
                isLent
                    ? 'You gave money to this person'
                    : 'You received money from this person',
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.account_balance_wallet_outlined),
              title: Text(isLent ? 'Paid from' : 'Received in'),
              subtitle: Text(walletLabel),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today_outlined),
              title: const Text('Due'),
              subtitle: Text(_dueLabel(debt)),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: _savingDebt
                    ? null
                    : () async {
                        final settled = await _settleWithFeedback(debt);
                        if (settled && sheetContext.mounted) {
                          Navigator.pop(sheetContext);
                        }
                      },
                icon: const Icon(Icons.check_circle_outline_rounded),
                label: const Text('Mark settled'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewCard({
    required Color primaryColor,
    required double receive,
    required double owe,
  }) {
    final net = receive - owe;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(20, 14, 20, 10),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            primaryColor,
            primaryColor.withValues(alpha: 0.78),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _overviewMetric(
                  'You will receive',
                  receive,
                  Icons.south_west_rounded,
                ),
              ),
              Container(
                width: 1,
                height: 42,
                color: Colors.white.withValues(alpha: 0.22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _overviewMetric(
                  'You owe',
                  owe,
                  Icons.north_east_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 9,
            ),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              net >= 0
                  ? 'Net receivable · Rs. ${net.toStringAsFixed(0)}'
                  : 'Net payable · Rs. ${net.abs().toStringAsFixed(0)}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _overviewMetric(String label, double amount, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: Colors.white70, size: 17),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Text(
          'Rs. ${amount.toStringAsFixed(0)}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }

  Widget _buildQuickUdharCard({
    required List<Wallet> wallets,
    required Color primaryColor,
    required bool isDark,
    required String language,
  }) {
    final resolvedWallet = _walletById(wallets, _activeWalletId);
    final quickLabel = _quickWalletLabel(wallets);
    final subtitle = _selectedWalletId == null
        ? resolvedWallet == null
            ? 'Automatic wallet'
            : 'Automatic · currently ${resolvedWallet.name}'
        : 'Default for commands without a named wallet';

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 2, 20, 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _isListening
              ? Colors.red.withValues(alpha: 0.65)
              : primaryColor.withValues(alpha: isDark ? 0.28 : 0.12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Quick Udhar',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _isListening
                          ? 'Listening now…'
                          : 'Type or speak naturally · saves instantly when clear',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _isListening ? null : _showUdharWalletPicker,
                icon: const Icon(
                  Icons.account_balance_wallet_outlined,
                  size: 17,
                ),
                label: Text(
                  quickLabel,
                  overflow: TextOverflow.ellipsis,
                ),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: primaryColor,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 12),
          Container(
            height: 52,
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.055)
                  : primaryColor.withValues(alpha: 0.045),
              borderRadius: BorderRadius.circular(15),
            ),
            child: TextField(
              controller: _smartInputCtrl,
              textInputAction: TextInputAction.done,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              onSubmitted: _processNLP,
              decoration: InputDecoration(
                hintText: _isListening
                    ? 'Listening…'
                    : language == 'romanUrdu'
                        ? 'Misal: Ali ko 500 udhaar diya'
                        : 'e.g. Borrowed 500 from Sara',
                hintStyle: TextStyle(
                  color: Colors.grey.shade500,
                  fontSize: 12,
                ),
                border: InputBorder.none,
                contentPadding:
                    const EdgeInsets.fromLTRB(14, 16, 4, 16),
                suffixIconConstraints:
                    const BoxConstraints(minHeight: 40),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Voice input',
                      visualDensity: VisualDensity.compact,
                      constraints:
                          const BoxConstraints.tightFor(width: 38, height: 40),
                      onPressed: _listenForInput,
                      icon: Icon(
                        _isListening
                            ? Icons.stop_circle_rounded
                            : Icons.mic_none_rounded,
                        color: _isListening ? Colors.red : primaryColor,
                        size: 21,
                      ),
                    ),
                    Container(
                      width: 34,
                      height: 34,
                      margin: const EdgeInsets.only(right: 5),
                      decoration: BoxDecoration(
                        color: primaryColor,
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        tooltip: 'Save Quick Udhar',
                        padding: EdgeInsets.zero,
                        onPressed: () =>
                            _processNLP(_smartInputCtrl.text),
                        icon: const Icon(
                          Icons.arrow_upward_rounded,
                          size: 18,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _scanningDebt ? null : _startReceiptScan,
              icon: _scanningDebt
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.document_scanner_outlined, size: 18),
              label: const Text('Scan receipt'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips(Color primaryColor) {
    const filters = <String, String>{
      'all': 'All',
      'receive': 'Receive',
      'owe': 'Owe',
      'due': 'Due soon',
    };
    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          for (final filter in filters.entries) ...[
            ChoiceChip(
              label: Text(filter.value),
              selected: _udharFilter == filter.key,
              onSelected: (_) {
                setState(() => _udharFilter = filter.key);
              },
              selectedColor: primaryColor.withValues(alpha: 0.14),
              side: BorderSide(
                color: _udharFilter == filter.key
                    ? primaryColor.withValues(alpha: 0.35)
                    : Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildDebtSection({
    required String title,
    required List<DebtEntry> items,
    required List<Wallet> wallets,
    required Color primaryColor,
    required bool isDark,
  }) {
    if (items.isEmpty) return const SizedBox.shrink();
    final total =
        items.fold<double>(0, (sum, entry) => sum + entry.amount);

    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Text(
                  '${items.length} · Rs. ${total.toStringAsFixed(0)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
          ),
        ),
        SliverList.builder(
          itemCount: items.length,
          itemBuilder: (context, index) => Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              0,
              20,
              index == items.length - 1 ? 4 : 10,
            ),
            child: _buildDebtCard(
              items[index],
              wallets,
              primaryColor,
              isDark,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDebtCard(
    DebtEntry item,
    List<Wallet> wallets,
    Color primaryColor,
    bool isDark,
  ) {
    final isLent = item.type == 'lent';
    final dueColor = _dueColor(context, item);
    final walletLabel = _walletLabelForDebt(wallets, item);

    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.green,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.white),
            SizedBox(width: 8),
            Text(
              'Mark settled',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
      confirmDismiss: (_) => _settleWithFeedback(item),
      child: Card(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isDark
                ? primaryColor.withValues(alpha: 0.2)
                : Colors.grey.withValues(alpha: 0.12),
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _showDebtDetails(item, wallets),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 10, 10),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: (isLent ? Colors.green : Colors.red)
                            .withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isLent
                            ? Icons.south_west_rounded
                            : Icons.north_east_rounded,
                        color: isLent ? Colors.green : Colors.red,
                        size: 19,
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.borrowerName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '$walletLabel · ${_dueLabel(item)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Rs. ${item.amount.toStringAsFixed(0)}',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: isLent ? Colors.green : Colors.red,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: dueColor.withValues(alpha: 0.09),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        _dueLabel(item),
                        style: TextStyle(
                          color: dueColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _savingDebt
                          ? null
                          : () => _settleWithFeedback(item),
                      icon: const Icon(
                        Icons.check_circle_outline_rounded,
                        size: 17,
                      ),
                      label: const Text('Settle'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(expenseProvider);
    final debts = debtBox.values
        .where(
          (entry) =>
              entry.deletedAt == null && entry.settledAt == null,
        )
        .toList(growable: false);
    final settings = ref.watch(settingsProvider);
    final wallets = ref.watch(walletProvider);
    final primaryColor = Color(settings.profileColorValue);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final iGave = debts
        .where((entry) => entry.type == 'lent')
        .fold<double>(0, (sum, entry) => sum + entry.amount);
    final iTook = debts
        .where((entry) => entry.type == 'borrowed')
        .fold<double>(0, (sum, entry) => sum + entry.amount);

    final visible = _visibleDebts(debts);
    final receive =
        visible.where((entry) => entry.type == 'lent').toList();
    final owe =
        visible.where((entry) => entry.type == 'borrowed').toList();

    final body = CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _buildOverviewCard(
            primaryColor: primaryColor,
            receive: iGave,
            owe: iTook,
          ),
        ),
        SliverToBoxAdapter(
          child: _buildQuickUdharCard(
            wallets: wallets,
            primaryColor: primaryColor,
            isDark: isDark,
            language: settings.smartEntryLanguage,
          ),
        ),
        SliverToBoxAdapter(
          child: _buildFilterChips(primaryColor),
        ),
        if (visible.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 90),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      debts.isEmpty
                          ? Icons.handshake_outlined
                          : Icons.filter_alt_off_outlined,
                      size: 48,
                      color: Colors.grey.withValues(alpha: 0.35),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      debts.isEmpty
                          ? 'No active Udhar. You are all settled.'
                          : 'No Udhar records match this filter.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
        else ...[
          _buildDebtSection(
            title: 'You will receive',
            items: receive,
            wallets: wallets,
            primaryColor: primaryColor,
            isDark: isDark,
          ),
          _buildDebtSection(
            title: 'You owe',
            items: owe,
            wallets: wallets,
            primaryColor: primaryColor,
            isDark: isDark,
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 90)),
        ],
      ],
    );

    final addButton = FloatingActionButton.extended(
      icon: const Icon(Icons.add_rounded),
      label: const Text('Add Udhar'),
      backgroundColor: primaryColor,
      foregroundColor: Colors.white,
      elevation: 3,
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

}