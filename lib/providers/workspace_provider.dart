import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/workspace_model.dart';
import 'expense_provider.dart';

class WorkspaceState {
  final List<Workspace> workspaces;
  final String selectedId;

  const WorkspaceState({
    required this.workspaces,
    required this.selectedId,
  });
}

class WorkspaceNotifier extends StateNotifier<WorkspaceState> {
  static const selectedWorkspaceKey = 'selected_workspace_id_v1';
  final Box<Workspace> _box = Hive.box<Workspace>('workspaces');
  final Box _preferences = Hive.box('preferences');
  final Ref _ref;

  WorkspaceNotifier(this._ref)
      : super(const WorkspaceState(workspaces: [], selectedId: 'personal')) {
    _load();
  }

  void _load() {
    if (!_box.containsKey('personal')) {
      _box.put(
        'personal',
        Workspace(
          id: 'personal',
          name: 'Personal',
          colorValue: 0xFF2563EB,
          iconCodePoint: 0xe491,
          position: 0,
          isDefault: true,
        ),
      );
    }
    final workspaces = _box.values.toList()
      ..sort((a, b) => a.position.compareTo(b.position));
    final stored = _preferences.get(selectedWorkspaceKey);
    final selected = stored is String &&
            workspaces.any((workspace) => workspace.id == stored)
        ? stored
        : 'personal';
    state = WorkspaceState(workspaces: workspaces, selectedId: selected);
  }

  Future<void> select(String id) async {
    if (!state.workspaces.any((workspace) => workspace.id == id)) return;
    await _preferences.put(selectedWorkspaceKey, id);
    state = WorkspaceState(workspaces: state.workspaces, selectedId: id);
  }

  Future<bool> create({
    required String name,
    int? colorValue,
    int? iconCodePoint,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty ||
        state.workspaces.any(
          (workspace) =>
              workspace.name.toLowerCase() == trimmed.toLowerCase(),
        )) {
      return false;
    }
    final workspace = Workspace(
      id: const Uuid().v4(),
      name: trimmed,
      colorValue: colorValue ?? 0xFF7C3AED,
      iconCodePoint: iconCodePoint ?? Icons.work_outline_rounded.codePoint,
      position: state.workspaces.length,
    );
    await _box.put(workspace.id, workspace);
    _load();
    await select(workspace.id);
    return true;
  }

  Future<bool> delete(
    String id, {
    bool moveTransactionsToPersonal = false,
  }) async {
    if (id == 'personal' || !_box.containsKey(id)) return false;
    final hasTransactions = _ref
        .read(expenseProvider)
        .allRecords
        .any((entry) => entry.workspaceId == id);
    if (hasTransactions && !moveTransactionsToPersonal) return false;
    if (hasTransactions) {
      await _ref
          .read(expenseProvider.notifier)
          .reassignWorkspace(id, 'personal');
    }
    await _box.delete(id);
    if (state.selectedId == id) {
      await _preferences.put(selectedWorkspaceKey, 'personal');
    }
    _load();
    return true;
  }
}

final workspaceProvider =
    StateNotifierProvider<WorkspaceNotifier, WorkspaceState>((ref) {
  return WorkspaceNotifier(ref);
});

final selectedWorkspaceIdProvider =
    Provider<String>((ref) => ref.watch(workspaceProvider).selectedId);
