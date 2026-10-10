import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';

/// One language control shared by the app and Smart NLP preferences.
class LanguageSettingsTile extends StatelessWidget {
  final String language;
  final ValueChanged<String>? onChanged;

  const LanguageSettingsTile({
    super.key,
    required this.language,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.language_rounded),
      title: Text(AppStrings.current.text('settings_language')),
      subtitle: Text(AppStrings.current.text('settings_language_hint')),
      trailing: DropdownButton<String>(
        key: const ValueKey('settings-language'),
        value: language,
        underline: const SizedBox.shrink(),
        items: const [
          DropdownMenuItem(value: 'english', child: Text('English')),
          DropdownMenuItem(value: 'romanUrdu', child: Text('Roman Urdu')),
        ],
        onChanged: onChanged == null
            ? null
            : (value) {
                if (value != null) onChanged!(value);
              },
      ),
    );
  }
}
