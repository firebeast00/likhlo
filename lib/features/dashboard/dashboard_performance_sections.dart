part of '../../screens/home_screen.dart';

class _DashboardHeroSection extends ConsumerWidget {
  final _HomeScreenState owner;
  final DateTime focusedMonth;

  const _DashboardHeroSection({
    required this.owner,
    required this.focusedMonth,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totalAvailable = ref.watch(totalAvailableProvider);
    final spent = ref.watch(monthlySpentProvider(focusedMonth));
    final wallets = ref.watch(walletProvider);
    // Total balance is unchanged by transfers, but individual wallet pills are
    // not. Keep this section subscribed to movement-map identity.
    ref.watch(walletMovementsProvider);
    final primaryColor = Theme.of(context).colorScheme.primary;
    return owner._buildHeroCard(
      totalAvailable,
      spent,
      wallets,
      primaryColor,
    );
  }
}

class _DashboardSmartInputSection extends ConsumerWidget {
  final _HomeScreenState owner;

  const _DashboardSmartInputSection({required this.owner});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallets = ref.watch(walletProvider);
    final language = ref.watch(
      settingsProvider.select((settings) => settings.smartEntryLanguage),
    );
    return ValueListenableBuilder<int>(
      valueListenable: owner._smartInputUiRevision,
      builder: (context, _, __) {
        return owner._buildSmartInputBar(
          Theme.of(context).colorScheme.primary,
          Theme.of(context).brightness == Brightness.dark,
          wallets,
          language,
        );
      },
    );
  }
}

class _DashboardCategorySection extends ConsumerWidget {
  final _HomeScreenState owner;

  const _DashboardCategorySection({required this.owner});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoryProvider);
    return owner._buildCategoryTabsWidget(
      categories,
      Theme.of(context).colorScheme.primary,
      Theme.of(context).brightness == Brightness.dark,
    );
  }
}

class _DashboardTransactionSection extends StatelessWidget {
  final _HomeScreenState owner;
  final DateTime focusedMonth;
  final String selectedCategory;
  final String? typeFilter;
  final SmartEntryTimeRange? searchRange;
  final bool searchAllHistory;
  final bool isSliver;

  const _DashboardTransactionSection({
    required this.owner,
    required this.focusedMonth,
    required this.selectedCategory,
    required this.typeFilter,
    required this.searchRange,
    required this.searchAllHistory,
    required this.isSliver,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: owner._searchQueryNotifier,
      builder: (context, query, _) {
        return Consumer(
          builder: (context, ref, _) {
            final List<Expense> source;
            if (searchAllHistory) {
              final allExpenses = ref.watch(
                expenseProvider.select((state) => state.allExpenses),
              );
              source = visibleTransactions(allExpenses);
            } else {
              source = ref.watch(monthlyTransactionsProvider(focusedMonth));
            }

            var displayExpenses = List<Expense>.from(source);
            if (selectedCategory != 'All') {
              displayExpenses = displayExpenses
                  .where((entry) => entry.category == selectedCategory)
                  .toList(growable: false);
            }
            if (query.isNotEmpty) {
              final normalizedQuery = query.toLowerCase();
              displayExpenses = displayExpenses
                  .where(
                    (entry) =>
                        entry.title.toLowerCase().contains(normalizedQuery),
                  )
                  .toList(growable: false);
            }
            if (typeFilter != null) {
              displayExpenses = displayExpenses
                  .where((entry) => entry.type == typeFilter)
                  .toList(growable: false);
            }
            if (searchRange != null) {
              displayExpenses = displayExpenses
                  .where(
                    (entry) => matchesSmartEntryTimeRange(
                      entry.date,
                      searchRange!,
                    ),
                  )
                  .toList(growable: false);
            }

            return owner._buildExpenseList(
              displayExpenses,
              Theme.of(context).colorScheme.primary,
              Theme.of(context).brightness == Brightness.dark,
              isSliver: isSliver,
            );
          },
        );
      },
    );
  }
}
