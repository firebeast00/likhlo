import '../l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

import '../models/expense_model.dart';
import '../models/wallet_model.dart';
import '../providers/budget_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/wallet_provider.dart';
import '../services/transaction_executor.dart';
import 'home_screen.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _profCtrl = TextEditingController();
  final TextEditingController _cashCtrl = TextEditingController();
  final TextEditingController _jazzCashCtrl = TextEditingController();
  final TextEditingController _incomeCtrl = TextEditingController();
  final TextEditingController _targetCtrl = TextEditingController();
  int _step = 0;
  String? _incomeWalletId;
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _profCtrl.dispose();
    _cashCtrl.dispose();
    _jazzCashCtrl.dispose();
    _incomeCtrl.dispose();
    _targetCtrl.dispose();
    super.dispose();
  }

  void _continueToMoneySetup() {
    if (_nameCtrl.text.trim().isEmpty || _profCtrl.text.trim().isEmpty) {
      _showMessage('Please fill in both profile fields to continue.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _step = 1);
  }

  double? _optionalAmount(TextEditingController controller) {
    final text = controller.text.trim();
    if (text.isEmpty) return 0;
    final value = double.tryParse(text);
    if (value == null || !value.isFinite || value < 0) return null;
    return value;
  }

  Future<void> _finishOnboarding({required bool skipMoneySetup}) async {
    if (_saving) return;
    final cash = skipMoneySetup ? 0.0 : _optionalAmount(_cashCtrl);
    final jazzCash = skipMoneySetup ? 0.0 : _optionalAmount(_jazzCashCtrl);
    final income = skipMoneySetup ? 0.0 : _optionalAmount(_incomeCtrl);
    final target = skipMoneySetup ? 0.0 : _optionalAmount(_targetCtrl);
    if (cash == null || jazzCash == null || income == null || target == null) {
      _showMessage('Use zero or a positive amount in each money field.');
      return;
    }

    setState(() => _saving = true);
    try {
      ref.read(settingsProvider.notifier).updateProfile(
            _nameCtrl.text.trim(),
            _profCtrl.text.trim(),
          );

      if (!skipMoneySetup) {
        final wallets = ref.read(walletProvider);
        final walletNotifier = ref.read(walletProvider.notifier);
        for (final wallet in wallets) {
          if (wallet.walletType == 'cash' && cash > 0) {
            await walletNotifier.updateWallet(wallet, currentBalance: cash);
          } else if (wallet.walletType == 'jazzcash' && jazzCash > 0) {
            await walletNotifier.updateWallet(
              wallet,
              currentBalance: jazzCash,
            );
          }
        }

        if (target > 0) {
          await ref.read(budgetProvider.notifier).setBudget(
                target,
                DateTime.now(),
              );
        }

        if (income > 0 && wallets.isNotEmpty) {
          final selectedWallet = wallets.firstWhere(
            (wallet) => wallet.id == _incomeWalletId,
            orElse: () => wallets.first,
          );
          final result = await ref.read(transactionExecutorProvider).execute(
                CreateTransactionCommand(
                  Expense(
                    id: const Uuid().v4(),
                    title: 'Opening income',
                    amount: income,
                    date: DateTime.now(),
                    category: 'Income / Allowance',
                    colorValue: selectedWallet.colorValue,
                    type: 'income',
                    walletId: selectedWallet.id,
                  ),
                ),
              );
          if (!result.succeeded) {
            throw StateError('Opening income could not be saved.');
          }
        }
      }

      await Hive.box('preferences').put('has_onboarded', true);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const HomeScreen(),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        _showMessage('Setup could not be completed. Your existing data is safe.');
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(AppStrings.current.display(message)),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red.shade700,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    AppStrings.of(context);
    final settings = ref.watch(settingsProvider);
    final wallets = ref.watch(walletProvider);
    final primaryColor = Color(settings.profileColorValue);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    _incomeWalletId ??= wallets.isEmpty ? null : wallets.first.id;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 240),
              child: _step == 0
                  ? _buildProfileStep(primaryColor, isDark)
                  : _buildMoneyStep(primaryColor, isDark, wallets),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileStep(Color primaryColor, bool isDark) {
    return Column(
      key: const ValueKey('profile-step'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _stepIcon(Icons.person_pin_circle_rounded, primaryColor),
        const SizedBox(height: 28),
        Text(
          AppStrings.current.text('welcome_to_likhlo_59777c'),
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          AppStrings.current.text('first_tell_us_a_little_about_yourself_a232ea'),
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey.shade500,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 38),
        _buildInput(
          _nameCtrl,
          'What should we call you?',
          Icons.person_rounded,
          primaryColor,
          isDark,
        ),
        const SizedBox(height: 16),
        _buildInput(
          _profCtrl,
          'What do you do? (e.g. Student)',
          Icons.school_rounded,
          primaryColor,
          isDark,
        ),
        const SizedBox(height: 34),
        _primaryButton(
          label: 'Continue',
          icon: Icons.arrow_forward_rounded,
          color: primaryColor,
          onPressed: _continueToMoneySetup,
        ),
      ],
    );
  }

  Widget _buildMoneyStep(
    Color primaryColor,
    bool isDark,
    List<Wallet> wallets,
  ) {
    return Column(
      key: const ValueKey('money-step'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: IconButton(
            tooltip: AppStrings.current.text('back_b52b36'),
            onPressed: _saving ? null : () => setState(() => _step = 0),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
        ),
        _stepIcon(Icons.account_balance_wallet_rounded, primaryColor),
        const SizedBox(height: 22),
        Text(
          AppStrings.current.text('set_up_your_money_15a172'),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 6),
        Text(
          AppStrings.current.text('optional_you_can_change_all_of_this_later_92e4a4'),
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
        ),
        const SizedBox(height: 28),
        _sectionLabel('Opening wallet balances'),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _moneyInput(
                _cashCtrl,
                'Cash',
                Icons.payments_outlined,
                primaryColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _moneyInput(
                _jazzCashCtrl,
                'JazzCash',
                Icons.phone_android_rounded,
                primaryColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        _sectionLabel('Add your first income'),
        const SizedBox(height: 10),
        _moneyInput(
          _incomeCtrl,
          'Income amount',
          Icons.south_west_rounded,
          primaryColor,
        ),
        if (wallets.isNotEmpty) ...[
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: wallets.any((w) => w.id == _incomeWalletId)
                ? _incomeWalletId
                : wallets.first.id,
            decoration: InputDecoration(
              labelText: AppStrings.current.text('income_wallet_61f7ff'),
              prefixIcon: const Icon(Icons.account_balance_wallet_outlined),
              filled: true,
              fillColor: Theme.of(context).cardColor,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
            items: wallets
                .map(
                  (wallet) => DropdownMenuItem(
                    value: wallet.id,
                    child: Text(wallet.name),
                  ),
                )
                .toList(growable: false),
            onChanged: (value) => setState(() => _incomeWalletId = value),
          ),
        ],
        const SizedBox(height: 22),
        _sectionLabel('Monthly spending target'),
        const SizedBox(height: 10),
        _moneyInput(
          _targetCtrl,
          'Optional target',
          Icons.flag_outlined,
          primaryColor,
        ),
        const SizedBox(height: 28),
        _primaryButton(
          label: _saving ? 'Saving…' : 'Finish setup',
          icon: Icons.check_rounded,
          color: primaryColor,
          onPressed: _saving
              ? null
              : () => _finishOnboarding(skipMoneySetup: false),
        ),
        TextButton(
          onPressed:
              _saving ? null : () => _finishOnboarding(skipMoneySetup: true),
          child: Text(AppStrings.current.text('skip_for_now_6fc096')),
        ),
      ],
    );
  }

  Widget _stepIcon(IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 54, color: color),
    );
  }

  Widget _sectionLabel(String text) => Text(
        AppStrings.current.display(text),
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
      );

  Widget _moneyInput(
    TextEditingController controller,
    String label,
    IconData icon,
    Color primaryColor,
  ) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
      ],
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: Theme.of(context).cardColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: primaryColor, width: 1.5),
        ),
      ),
    );
  }

  Widget _primaryButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      height: 54,
      child: FilledButton.icon(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: color,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        icon: Icon(icon),
        label: Text(AppStrings.current.display(label), style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildInput(
    TextEditingController controller,
    String label,
    IconData icon,
    Color primaryColor,
    bool isDark,
  ) {
    return TextField(
      controller: controller,
      textCapitalization: TextCapitalization.words,
      style: TextStyle(
        color: isDark ? Colors.white : Colors.black87,
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: Theme.of(context).cardColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: primaryColor, width: 1.8),
        ),
      ),
    );
  }
}
