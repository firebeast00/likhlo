import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/mess_entry_model.dart';

class MessNotifier extends StateNotifier<List<MessEntry>> {
  MessNotifier() : super([]) {
    loadEntries();
  }

  void loadEntries() {
    if (!Hive.isBoxOpen('mess_khata')) return;
    final box = Hive.box<MessEntry>('mess_khata');
    state = box.values.toList();
  }

  Future<void> addEntry(MessEntry entry) async {
    if (!entry.totalAmount.isFinite || entry.totalAmount <= 0) return;
    final box = Hive.box<MessEntry>('mess_khata');
    await box.add(entry);
    loadEntries();
  }

  Future<void> deleteEntry(String id) async {
    final box = Hive.box<MessEntry>('mess_khata');
    final matches = box.values.where((entry) => entry.id == id);
    if (matches.isEmpty) return;
    await matches.first.delete();
    loadEntries();
  }
}

final messProvider = StateNotifierProvider<MessNotifier, List<MessEntry>>((ref) {
  return MessNotifier();
});
