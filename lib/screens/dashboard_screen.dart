import 'package:flutter/material.dart';

import '../widgets/dashboard_content.dart';
import '../widgets/primary_ledger_tabs.dart';

/// Dashboard composition boundary.
///
/// This widget intentionally contains no finance, Smart Entry, voice, OCR or
/// persistence logic. It only composes the existing Main/Udhar ledger tabs.
class DashboardScreen extends StatelessWidget {
  final PrimaryLedgerTabsController controller;
  final ValueChanged<PrimaryLedgerTab> onTabChanged;
  final bool isLandscape;
  final bool isSearching;
  final Widget? moneySetupCard;
  final Widget monthSelector;
  final Widget heroCard;
  final Widget smartInputBar;
  final Widget categoryTabs;
  final Widget Function(bool isSliver) transactionListBuilder;

  const DashboardScreen({
    super.key,
    required this.controller,
    required this.onTabChanged,
    required this.isLandscape,
    required this.isSearching,
    required this.moneySetupCard,
    required this.monthSelector,
    required this.heroCard,
    required this.smartInputBar,
    required this.categoryTabs,
    required this.transactionListBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return PrimaryLedgerTabs(
      controller: controller,
      onChanged: onTabChanged,
      mainTab: DashboardContent(
        isLandscape: isLandscape,
        isSearching: isSearching,
        moneySetupCard: moneySetupCard,
        monthSelector: monthSelector,
        heroCard: heroCard,
        smartInputBar: smartInputBar,
        categoryTabs: categoryTabs,
        transactionListBuilder: transactionListBuilder,
      ),
    );
  }
}
