part of '../../screens/home_screen.dart';

extension _DashboardCategoryMethods on _HomeScreenState {
  void _selectCategory(String category, int index) {
    _dismissKeyboard();
    _selectedCategoryTab = category;
    _categorySelectionNotifier.value = category;
    double offset = (index * 70.0) - (MediaQuery.of(context).size.width / 2) + 35;
    if (offset < 0) offset = 0;
    if (_categoryScrollCtrl.hasClients) {
      _categoryScrollCtrl.animateTo(offset, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  void _showAddCategoryDialog() {
    _dismissKeyboard();
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
            Expanded(child: Text(AppStrings.current.text('new_category_309531'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
          ],
        ),
        content: _buildModernInput(catCtrl, "Category Name", Icons.new_label_rounded, primaryColor),
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        actions: [
          Row(
            children: [
              Expanded(child: TextButton(onPressed: () => Navigator.pop(ctx), child: Text(AppStrings.current.text('cancel_77dfd2'), style: TextStyle(color: Colors.grey)))),
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
                          AppMessage('choose_a_different_name_for_this_category_46fbd6'),
                          title: AppMessage('category_already_exists_8ab7fa'),
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
                  child: Text(AppStrings.current.text('save_efc007')),
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  Future<void> _confirmDeleteCategory(String category) async {
    _dismissKeyboard();
    if (category == 'All') return;
    final categories = ref.read(categoryProvider);

    if (categories.length <= 1) {
      _showTransactionError(AppMessage('keep_at_least_one_expense_category_a44f7a'));
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          AppStrings.current.text('delete_category_61aa7c'),
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        content: Text(
          AppStrings.current.text('delete_existing_transactions_will_remain_unchang_da852e', {'p0': category}),
          style: const TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(AppStrings.current.text('cancel_77dfd2')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(AppStrings.current.text('delete_f6fdbe')),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    ref.read(categoryProvider.notifier).deleteCategory(category);

    if (_selectedCategoryTab == category) {
      _selectedCategoryTab = 'All';
      _categorySelectionNotifier.value = 'All';
    }
    _showDeletionMessage(
      AppMessage('category_was_deleted_39d1c3', {'p0': category}),
      title: AppMessage('category_deleted_5e23de'),
    );
  }

  // ==================== TRANSACTION / TRANSFER MODAL ====================

}
