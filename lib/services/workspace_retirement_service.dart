import 'package:hive_flutter/hive_flutter.dart';

import '../models/expense_model.dart';

/// One-time compatibility migration for versions that supported custom
/// workspaces. Every record is retained and merged into the single Main ledger.
class WorkspaceRetirementService {
  static const String legacySelectedWorkspaceKey =
      'selected_workspace_id_v1';

  const WorkspaceRetirementService._();

  static Future<void> mergeIntoMain() async {
    if (!Hive.isBoxOpen('expenses') || !Hive.isBoxOpen('preferences')) return;
    final expenses = Hive.box<Expense>('expenses');
    final updates = <dynamic, Expense>{};
    for (final key in expenses.keys) {
      final entry = expenses.get(key);
      if (entry != null && entry.workspaceId != 'personal') {
        updates[key] = entry.copyWith(workspaceId: 'personal');
      }
    }
    if (updates.isNotEmpty) await expenses.putAll(updates);
    await Hive.box('preferences').delete(legacySelectedWorkspaceKey);
  }
}
