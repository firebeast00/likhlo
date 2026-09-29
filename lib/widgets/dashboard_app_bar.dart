import 'package:flutter/material.dart';

import 'primary_ledger_tabs.dart';

class DashboardAppBar extends StatelessWidget implements PreferredSizeWidget {
  final PrimaryLedgerTab activeTab;
  final bool isSearching;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onBeforeOpenDrawer;
  final VoidCallback onOpenWallets;
  final VoidCallback onToggleSearch;

  const DashboardAppBar({
    super.key,
    required this.activeTab,
    required this.isSearching,
    required this.onSearchChanged,
    required this.onBeforeOpenDrawer,
    required this.onOpenWallets,
    required this.onToggleSearch,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      elevation: 0,
      scrolledUnderElevation: 0,
      title: isSearching
          ? TextField(
              style: const TextStyle(fontSize: 15),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: 'Search transactions...',
                hintStyle: TextStyle(
                  color: Colors.grey.shade400,
                  fontSize: 14,
                ),
              ),
              onChanged: onSearchChanged,
            )
          : Text(
              activeTab == PrimaryLedgerTab.main ? 'Main' : 'Udhar',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 17,
              ),
            ),
      centerTitle: true,
      leading: Builder(
        builder: (context) => IconButton(
          tooltip: 'Open sidebar',
          icon: const Icon(Icons.view_sidebar_outlined, size: 24),
          onPressed: () {
            onBeforeOpenDrawer();
            Scaffold.of(context).openDrawer();
          },
        ),
      ),
      actions: [
        if (activeTab == PrimaryLedgerTab.main && !isSearching)
          IconButton(
            tooltip: 'Wallets',
            icon: const Icon(
              Icons.account_balance_wallet_outlined,
              size: 22,
            ),
            onPressed: onOpenWallets,
          ),
        if (activeTab == PrimaryLedgerTab.main)
          IconButton(
            tooltip: isSearching ? 'Close search' : 'Search',
            icon: Icon(
              isSearching ? Icons.close_rounded : Icons.search_rounded,
              size: 22,
            ),
            onPressed: onToggleSearch,
          ),
      ],
    );
  }
}
