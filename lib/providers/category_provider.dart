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
      'General', 'Food', 'Transport', 'Shopping', 'Entertainment', 'Health', 'Education'
    ];

    // Safely cast the list
    List<String> loaded = box.get('categories', defaultValue: defaults).cast<String>();
    state = loaded;
  }

  void addCategory(String name) {
    if (!Hive.isBoxOpen('preferences')) return; // Safety

    if (name.isNotEmpty && !state.contains(name)) {
      final updated = [...state, name];
      final box = Hive.box('preferences');
      box.put('categories', updated);
      state = updated;
    }
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

  void editCategory(String oldName, String newName) {
    if (!Hive.isBoxOpen('preferences')) return; // Safety

    final cleanName = newName.trim();
    final duplicate = state.any(
      (category) =>
          category != oldName &&
          category.toLowerCase() == cleanName.toLowerCase(),
    );
    if (cleanName.isNotEmpty && state.contains(oldName) && !duplicate) {
      final index = state.indexOf(oldName);
      final updated = List<String>.from(state);
      updated[index] = cleanName;

      final box = Hive.box('preferences');
      box.put('categories', updated);
      state = updated;
    }
  }
}

final categoryProvider = StateNotifierProvider<CategoryNotifier, List<String>>((ref) {
  return CategoryNotifier();
});