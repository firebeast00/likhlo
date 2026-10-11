import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';

/// Optional category controls within the existing transaction review sheet.
/// No suggestion or remembered alias is accepted without user selection.
class SpeechCategoryReview extends StatelessWidget {
  final String heardName;
  final List<String> suggestions;
  final String? selectedCategory;
  final bool remember;
  final ValueChanged<String> onCategoryChanged;
  final ValueChanged<bool> onRememberChanged;

  const SpeechCategoryReview({super.key, required this.heardName,
    this.suggestions = const [], this.selectedCategory, this.remember = false,
    required this.onCategoryChanged, required this.onRememberChanged});

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.current;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(heardName.isEmpty ? strings.text('expense_category_incomplete')
          : strings.text('speech_category_heard', {'p0': heardName})),
      if (suggestions.isNotEmpty) Wrap(spacing: 8, runSpacing: 4, children: [
        for (final name in suggestions) ChoiceChip(
          label: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 180),
              child: Text(strings.display(name), maxLines: 1, overflow: TextOverflow.ellipsis)),
          selected: selectedCategory == name,
          onSelected: (_) => onCategoryChanged(name)),
      ]),
      if (heardName.isNotEmpty) CheckboxListTile(contentPadding: EdgeInsets.zero,
        title: Text(strings.text('speech_category_remember')),
        value: remember, onChanged: (value) => onRememberChanged(value ?? false)),
    ]);
  }
}

class SpeechCategoryChoice {
  final String category;
  final bool remember;
  const SpeechCategoryChoice(this.category, {this.remember = false});
}

/// Confirmation changes only the isolated category, never the transaction text.
class SpeechCategoryDialog extends StatefulWidget {
  final String heardName;
  final List<String> categories;
  final List<String> suggestions;
  const SpeechCategoryDialog({super.key, required this.heardName,
    required this.categories, this.suggestions = const []});

  @override
  State<SpeechCategoryDialog> createState() => _SpeechCategoryDialogState();
}

class _SpeechCategoryDialogState extends State<SpeechCategoryDialog> {
  String? _selected;
  bool _remember = false;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.current;
    return AlertDialog(
      title: Text(strings.text('expense_category_choose')),
      content: SingleChildScrollView(child: Column(
        mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.heardName.isEmpty
              ? strings.text('expense_category_incomplete')
              : strings.text('speech_category_heard', {'p0': widget.heardName})),
          if (widget.suggestions.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 4, children: [
              for (final name in widget.suggestions)
                ChoiceChip(label: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 180),
                    child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis)), selected: _selected == name,
                    onSelected: (_) => setState(() => _selected = name)),
            ]),
          ],
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _selected,
            key: ValueKey(_selected),
            isExpanded: true, menuMaxHeight: 240,
            hint: Text(strings.text('expense_category_choose')),
            items: widget.categories.map((name) => DropdownMenuItem(
                value: name, child: Text(name, overflow: TextOverflow.ellipsis)))
                .toList(growable: false),
            onChanged: (name) => setState(() => _selected = name),
          ),
          if (widget.heardName.isNotEmpty) CheckboxListTile(contentPadding: EdgeInsets.zero,
            title: Text(strings.text('speech_category_remember')),
            value: _remember, onChanged: (value) => setState(() => _remember = value ?? false)),
        ],
      )),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(),
            child: Text(strings.text('cancel_77dfd2'))),
        FilledButton(onPressed: _selected == null ? null : () =>
            Navigator.of(context).pop(SpeechCategoryChoice(_selected!, remember: _remember)),
            child: Text(strings.text('speech_category_use'))),
      ],
    );
  }
}
