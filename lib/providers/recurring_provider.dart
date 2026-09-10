import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/recurring_bill_model.dart';

class RecurringNotifier extends StateNotifier<List<RecurringBill>> {
  RecurringNotifier() : super([]) {
    loadBills();
  }

  void loadBills() {
    if (!Hive.isBoxOpen('recurring_bills')) return;
    final box = Hive.box<RecurringBill>('recurring_bills');
    state = box.values.toList();
  }

  Future<void> addBill(RecurringBill bill) async {
    if (!bill.amount.isFinite || bill.amount <= 0 || bill.title.trim().isEmpty) {
      return;
    }
    final box = Hive.box<RecurringBill>('recurring_bills');
    await box.add(bill);
    loadBills();
  }

  Future<void> deleteBill(String id) async {
    final box = Hive.box<RecurringBill>('recurring_bills');
    final matches = box.values.where((bill) => bill.id == id);
    if (matches.isEmpty) return;
    await matches.first.delete();
    loadBills();
  }
}

final recurringProvider = StateNotifierProvider<RecurringNotifier, List<RecurringBill>>((ref) {
  return RecurringNotifier();
});
