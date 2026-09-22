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
    state = box.values.where((entry) => entry.deletedAt == null).toList();
  }

  Future<bool> addEntry(MessEntry entry) async {
    if (entry.id.trim().isEmpty ||
        !entry.totalAmount.isFinite ||
        entry.totalAmount <= 0) {
      return false;
    }
    final box = Hive.box<MessEntry>('mess_khata');
    if (box.values.any((existing) => existing.id == entry.id)) return false;
    await box.put(entry.id, entry);
    loadEntries();
    return true;
  }

  Future<void> deleteEntry(String id) async {
    final box = Hive.box<MessEntry>('mess_khata');
    final matches = box.values.where((entry) => entry.id == id);
    if (matches.isEmpty) return;
    await box.put(id, matches.first.copyWith(deletedAt: DateTime.now()));
    loadEntries();
  }

  Future<void> restoreEntry(String id) async {
    final box = Hive.box<MessEntry>('mess_khata');
    final entry = box.get(id);
    if (entry == null || entry.deletedAt == null) return;
    await box.put(id, entry.copyWith(clearDeletedAt: true));
    loadEntries();
  }

  Future<void> permanentlyDelete(String id) async {
    final box = Hive.box<MessEntry>('mess_khata');
    final entry = box.get(id);
    if (entry?.deletedAt == null) return;
    await box.delete(id);
    loadEntries();
  }
}

final messProvider =
    StateNotifierProvider<MessNotifier, List<MessEntry>>((ref) {
  return MessNotifier();
});
