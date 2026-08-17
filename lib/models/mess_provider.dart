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
    final box = Hive.box<MessEntry>('mess_khata');
    await box.add(entry);
    loadEntries();
  }

  Future<void> deleteEntry(String id) async {
    final box = Hive.box<MessEntry>('mess_khata');
    final entry = box.values.firstWhere((e) => e.id == id);
    await entry.delete();
    loadEntries();
  }
}

final messProvider = StateNotifierProvider<MessNotifier, List<MessEntry>>((ref) {
  return MessNotifier();
});