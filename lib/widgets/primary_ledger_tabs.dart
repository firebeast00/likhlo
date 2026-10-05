import '../l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/debt_model.dart';
import '../screens/debt_screen.dart';

enum PrimaryLedgerTab { main, udhar }

class PrimaryLedgerTabsController extends ChangeNotifier {
  PrimaryLedgerTab _selected = PrimaryLedgerTab.main;

  PrimaryLedgerTab get selected => _selected;

  void select(PrimaryLedgerTab tab) {
    if (_selected == tab) return;
    _selected = tab;
    notifyListeners();
  }
}

class PrimaryLedgerTabs extends StatefulWidget {
  final PrimaryLedgerTabsController controller;
  final Widget mainTab;
  final ValueChanged<PrimaryLedgerTab>? onChanged;

  const PrimaryLedgerTabs({
    super.key,
    required this.controller,
    required this.mainTab,
    this.onChanged,
  });

  @override
  State<PrimaryLedgerTabs> createState() => _PrimaryLedgerTabsState();
}

class _PrimaryLedgerTabsState extends State<PrimaryLedgerTabs> {
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(
      initialPage: _pageFor(widget.controller.selected),
    );
    widget.controller.addListener(_followController);
  }

  @override
  void didUpdateWidget(PrimaryLedgerTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_followController);
    widget.controller.addListener(_followController);
    _followController();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_followController);
    _pageController.dispose();
    super.dispose();
  }

  void _followController() {
    if (!_pageController.hasClients) return;
    final page = _pageController.page?.round();
    final targetPage = _pageFor(widget.controller.selected);
    if (page != targetPage) {
      _pageController.jumpToPage(targetPage);
    }
    if (mounted) setState(() {});
  }

  void _select(PrimaryLedgerTab tab) {
    widget.controller.select(tab);
  }

  void _onPageChanged(int index) {
    final tab = index == 0 ? PrimaryLedgerTab.main : PrimaryLedgerTab.udhar;
    widget.controller.select(tab);
    widget.onChanged?.call(tab);
  }

  int _pageFor(PrimaryLedgerTab tab) =>
      tab == PrimaryLedgerTab.main ? 0 : 1;

  @override
  Widget build(BuildContext context) {
    AppStrings.of(context);
    final selected = widget.controller.selected;
    final colors = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
          child: SegmentedButton<PrimaryLedgerTab>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: PrimaryLedgerTab.main,
                label: Text(AppStrings.current.text('main_62bce9')),
                icon: Icon(Icons.home_outlined, size: 18),
              ),
              ButtonSegment(
                value: PrimaryLedgerTab.udhar,
                label: Text(AppStrings.current.text('udhar_3b8cbd')),
                icon: Icon(Icons.handshake_outlined, size: 18),
              ),
            ],
            selected: {selected},
            onSelectionChanged: (selection) => _select(selection.first),
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              foregroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? colors.onPrimaryContainer
                    : colors.onSurfaceVariant,
              ),
              backgroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? colors.primaryContainer
                    : colors.surfaceContainerHighest,
              ),
              side: WidgetStateProperty.resolveWith(
                (states) => BorderSide(
                  color: states.contains(WidgetState.selected)
                      ? colors.primary.withValues(alpha: 0.45)
                      : colors.outlineVariant.withValues(alpha: 0.55),
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            itemCount: 2,
            onPageChanged: _onPageChanged,
            itemBuilder: (context, index) => index == 0
                ? widget.mainTab
                : const _LazyUdharTab(),
          ),
        ),
      ],
    );
  }
}

class _LazyUdharTab extends StatefulWidget {
  const _LazyUdharTab();

  @override
  State<_LazyUdharTab> createState() => _LazyUdharTabState();
}

class _LazyUdharTabState extends State<_LazyUdharTab> {
  late Future<void> _ready;

  @override
  void initState() {
    super.initState();
    _ready = _openBox();
  }

  Future<void> _openBox() async {
    if (!Hive.isBoxOpen('debts')) {
      await Hive.openBox<DebtEntry>('debts');
    }
  }

  @override
  Widget build(BuildContext context) {
    AppStrings.of(context);
    return FutureBuilder<void>(
      future: _ready,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline_rounded, size: 42),
                  const SizedBox(height: 12),
                  Text(AppStrings.current.text('udhar_records_could_not_be_opened_2a95a2')),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => setState(() => _ready = _openBox()),
                    child: Text(AppStrings.current.text('try_again_042c86')),
                  ),
                ],
              ),
            ),
          );
        }
        return const DebtScreen(embedded: true);
      },
    );
  }
}
