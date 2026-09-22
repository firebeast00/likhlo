import 'package:flutter/material.dart';

import '../models/workspace_model.dart';

class WorkspaceSelector extends StatelessWidget {
  final List<Workspace> workspaces;
  final String selectedId;
  final ValueChanged<String> onSelected;

  const WorkspaceSelector({
    super.key,
    required this.workspaces,
    required this.selectedId,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    Workspace? selected;
    for (final workspace in workspaces) {
      if (workspace.id == selectedId) {
        selected = workspace;
        break;
      }
    }
    selected ??= workspaces.isEmpty ? null : workspaces.first;
    final label = selected?.name ?? 'Personal';
    final color = selected == null
        ? Theme.of(context).colorScheme.primary
        : Color(selected.colorValue);

    return PopupMenuButton<String>(
      tooltip: 'Switch workspace',
      initialValue: selected?.id,
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final workspace in workspaces)
          PopupMenuItem<String>(
            value: workspace.id,
            child: Row(
              children: [
                Icon(
                  workspace.id == selectedId
                      ? Icons.check_circle_rounded
                      : Icons.circle_outlined,
                  size: 19,
                  color: Color(workspace.colorValue),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    workspace.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
      ],
      child: Semantics(
        button: true,
        label: 'Current workspace: $label',
        child: Container(
          constraints: const BoxConstraints(maxWidth: 190),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.2)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 5),
              Icon(Icons.expand_more_rounded, size: 18, color: color),
            ],
          ),
        ),
      ),
    );
  }
}
