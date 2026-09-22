import 'package:flutter/material.dart';

typedef TransactionListBuilder = Widget Function(bool isSliver);

class DashboardContent extends StatelessWidget {
  final bool isLandscape;
  final bool isSearching;
  final Widget? moneySetupCard;
  final Widget monthSelector;
  final Widget heroCard;
  final Widget smartInputBar;
  final Widget categoryTabs;
  final TransactionListBuilder transactionListBuilder;

  const DashboardContent({
    super.key,
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
    if (isLandscape && !isSearching) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 80),
              child: Column(
                children: [
                  if (moneySetupCard != null) ...[
                    moneySetupCard!,
                    const SizedBox(height: 10),
                  ],
                  monthSelector,
                  const SizedBox(height: 8),
                  RepaintBoundary(child: heroCard),
                  const SizedBox(height: 14),
                  smartInputBar,
                  const SizedBox(height: 8),
                  categoryTabs,
                ],
              ),
            ),
          ),
          Expanded(child: transactionListBuilder(false)),
        ],
      );
    }

    if (isSearching) {
      return Column(
        children: [
          const SizedBox(height: 4),
          Expanded(child: transactionListBuilder(false)),
        ],
      );
    }

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        if (moneySetupCard != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
              child: moneySetupCard!,
            ),
          ),
        SliverToBoxAdapter(child: monthSelector),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: RepaintBoundary(child: heroCard),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 8),
            child: smartInputBar,
          ),
        ),
        SliverPersistentHeader(
          pinned: true,
          delegate: DashboardStickyHeaderDelegate(
            minHeight: 56,
            maxHeight: 56,
            child: ColoredBox(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: categoryTabs,
            ),
          ),
        ),
        transactionListBuilder(true),
      ],
    );
  }
}

class DashboardStickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double minHeight;
  final double maxHeight;
  final Widget child;

  DashboardStickyHeaderDelegate({
    required this.minHeight,
    required this.maxHeight,
    required this.child,
  });

  @override
  double get minExtent => minHeight;

  @override
  double get maxExtent => maxHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return SizedBox.expand(child: child);
  }

  @override
  bool shouldRebuild(DashboardStickyHeaderDelegate oldDelegate) {
    return maxHeight != oldDelegate.maxHeight ||
        minHeight != oldDelegate.minHeight ||
        child != oldDelegate.child;
  }
}
