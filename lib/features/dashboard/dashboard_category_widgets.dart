part of '../../screens/home_screen.dart';

extension _DashboardCategoryWidgetMethods on _HomeScreenState {
  Widget _buildCategoryTabsWidget(List<String> categories, Color primaryColor, bool isDark) {
    return Container(
      height: 40, margin: const EdgeInsets.only(top: 4, bottom: 8),
      child: ListView(
          controller: _categoryScrollCtrl, scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 20),
          children: [_buildTab('All', 0, isDark, primaryColor), ...List.generate(categories.length, (i) => _buildTab(categories[i], i + 1, isDark, primaryColor)), _buildAddCategoryBtn(primaryColor, isDark)]
      ),
    );
  }

  Widget _buildAddCategoryBtn(Color primaryColor, bool isDark) {
    return GestureDetector(
      onTap: _showAddCategoryDialog,
      child: Container(margin: const EdgeInsets.only(right: 8), padding: const EdgeInsets.symmetric(horizontal: 16), decoration: BoxDecoration(color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(20), border: Border.all(color: isDark ? Colors.white24 : Colors.grey.shade300, width: 1.2)), child: Row(children: [Icon(Icons.add_rounded, size: 16, color: isDark ? Colors.white70 : Colors.black87), const SizedBox(width: 4), Text("New", style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontWeight: FontWeight.bold, fontSize: 12))])),
    );
  }

  Widget _buildTab(String label, int index, bool isDark, Color primaryColor) {
    bool isSelected = _selectedCategoryTab == label;
    return GestureDetector(
        onTap: () => _selectCategory(label, index),
        onLongPress: label == 'All' ? null : () => _confirmDeleteCategory(label),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: isSelected ? primaryColor : Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(20),
            border: isSelected ? null : Border.all(color: isDark ? primaryColor.withValues(alpha: 0.25) : Colors.grey.withValues(alpha: 0.15), width: 1.2),
          ),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: TextStyle(color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87), fontWeight: isSelected ? FontWeight.bold : FontWeight.w600, fontSize: 12)),
                if (isSelected && label != 'All') ...[
                  const SizedBox(width: 6),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _confirmDeleteCategory(label),
                    child: const Padding(
                      padding: EdgeInsets.all(2),
                      child: Icon(Icons.close_rounded, size: 14, color: Colors.white),
                    ),
                  ),
                ],
              ],
            ),
          ),
        )
    );
  }


}
