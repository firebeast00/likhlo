part of '../../screens/home_screen.dart';

extension _DashboardHeroWidgetMethods on _HomeScreenState {
  Widget _buildHeroCard(
      double totalAvailable,
      double spent,
      List<Wallet> wallets,
      Color primary,
      ) {
    final visibleWallets = _resolvedHomeWallets(wallets);
    final darkerPrimary = Color.lerp(
      primary,
      Colors.black,
      Theme.of(context).brightness == Brightness.dark ? 0.12 : 0.18,
    )!;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [primary, darkerPrimary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  AppStrings.current.text('total_available_43f41a'),
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                tooltip: AppStrings.current.text('choose_daily_wallets_dee1a5'),
                onPressed: _showHomeWalletPicker,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 32,
                  height: 32,
                ),
                icon: const Icon(
                  Icons.tune_rounded,
                  color: Colors.white,
                  size: 19,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              'Rs. ${totalAvailable.toStringAsFixed(0)}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.8,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildBalanceMetric(
                  label: AppStrings.current.text('spent_this_month_2ecf74'),
                  value: 'Rs. ${spent.toStringAsFixed(0)}',
                  onTap: () => _changeSection(AppSection.stats),
                  semanticHint: 'Open monthly statistics',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildBalanceMetric(
                  label: AppStrings.current.text('all_wallets_0134de'),
                  value: '${wallets.length}',
                  onTap: _openIncomeAccounts,
                  semanticHint: 'Open wallet accounts',
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          Row(
            children: [
              Expanded(
                child: Text(
                  AppStrings.current.text('daily_wallets_5cc919'),
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                AppStrings.current.text('of_shown_54e7c9', {'p0': visibleWallets.length, 'p1': wallets.length}),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 9.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          if (visibleWallets.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Text(
                AppStrings.current.text('no_wallets_yet_f53201'),
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                ),
              ),
            )
          else
            SizedBox(
              height: 62,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: visibleWallets.length,
                separatorBuilder: (_, __) => const SizedBox(width: 9),
                itemBuilder: (context, index) =>
                    _buildAccountPill(visibleWallets[index]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBalanceMetric({
    required String label,
    required String value,
    VoidCallback? onTap,
    String? semanticHint,
  }) {
    return Semantics(
      button: onTap != null,
      label: label,
      value: value,
      hint: semanticHint,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.11),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        AppStrings.current.display(label),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.68),
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onTap != null)
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 12,
                    color: Colors.white.withValues(alpha: 0.62),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAccountPill(Wallet wallet) {
    final balance =
    ref.read(walletProvider.notifier).getBalanceForWallet(wallet.id);

    return Container(
      width: 158,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.10),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: Color(wallet.colorValue).withValues(alpha: 0.22),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _walletIcon(wallet),
              color: Colors.white,
              size: 15,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  wallet.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Rs. ${balance.toStringAsFixed(0)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          if (wallet.isBackup)
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Icon(
                Icons.shield_outlined,
                color: Colors.white54,
                size: 13,
              ),
            ),
        ],
      ),
    );
  }

  IconData _walletIcon(Wallet wallet) {
    if (wallet.isBackup) return Icons.shield_outlined;
    switch (wallet.walletType.toLowerCase()) {
      case 'jazzcash':
        return Icons.phone_android_rounded;
      case 'bank':
        return Icons.account_balance_outlined;
      case 'cash':
        return Icons.payments_outlined;
      default:
        return Icons.account_balance_wallet_outlined;
    }
  }


}
