import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

class CategoryNotifier extends StateNotifier<List<String>> {
  CategoryNotifier() : super([]) {
    _loadCategories();
  }

  void _loadCategories() {
    // ✅ SAFETY CHECK: Prevent crash if box isn't open yet
    if (!Hive.isBoxOpen('preferences')) return;

    final box = Hive.box('preferences');

    final List<String> defaults = [
      'General',
      'Food',
      'Transport',
      'Shopping',
      'Entertainment',
      'Health',
      'Education'
    ];

    final saved = box.get('categories', defaultValue: defaults);
    final loaded =
        saved is Iterable ? saved.whereType<String>().toList() : defaults;
    state = loaded.isEmpty ? defaults : loaded;
  }

  bool addCategory(String name) {
    if (!Hive.isBoxOpen('preferences')) return false; // Safety

    final cleaned = name.trim();
    final isDuplicate = state
        .any((category) => category.toLowerCase() == cleaned.toLowerCase());
    if (cleaned.isNotEmpty && !isDuplicate) {
      final updated = [...state, cleaned];
      final box = Hive.box('preferences');
      box.put('categories', updated);
      state = updated;
      return true;
    }
    return false;
  }

  void deleteCategory(String name) {
    if (!Hive.isBoxOpen('preferences')) return; // Safety

    if (state.contains(name)) {
      final updated = state.where((c) => c != name).toList();
      final box = Hive.box('preferences');
      box.put('categories', updated);
      state = updated;
    }
  }

  bool editCategory(String oldName, String newName) {
    if (!Hive.isBoxOpen('preferences')) return false; // Safety

    final cleaned = newName.trim();
    final isDuplicate = state.any(
      (category) =>
          category != oldName &&
          category.toLowerCase() == cleaned.toLowerCase(),
    );
    if (cleaned.isNotEmpty && !isDuplicate && state.contains(oldName)) {
      final index = state.indexOf(oldName);
      final updated = List<String>.from(state);
      updated[index] = cleaned;

      final box = Hive.box('preferences');
      box.put('categories', updated);
      state = updated;
      return true;
    }
    return false;
  }
}

final categoryProvider =
    StateNotifierProvider<CategoryNotifier, List<String>>((ref) {
  return CategoryNotifier();
});
