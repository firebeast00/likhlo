import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:hive/hive.dart';

import 'app_catalog.g.dart';

enum AppLanguage {
  english,
  romanUrdu;

  static AppLanguage parse(Object? value) => value == 'romanUrdu'
      ? AppLanguage.romanUrdu
      : AppLanguage.english;

  static AppLanguage read() => Hive.isBoxOpen('settings')
      ? parse(Hive.box('settings').get('appLanguage'))
      : AppLanguage.english;

  Locale get locale => this == AppLanguage.romanUrdu
      ? const Locale.fromSubtags(languageCode: 'ur', scriptCode: 'Latn')
      : const Locale('en');
}

/// A key and authoritative parameters shared by written and spoken feedback.
/// User values are inserted exactly once, never recursively translated.
class AppMessage {
  final String key;
  final Map<String, Object?> parameters;
  final String? _literal;

  const AppMessage(this.key, [this.parameters = const {}]) : _literal = null;
  const AppMessage.literal(String value)
      : key = '', parameters = const {}, _literal = value;

  /// Compatibility for existing service responses. Only call at app-authored
  /// response boundaries, never on a transaction title or custom wallet name.
  static AppMessage resolve(Object value) {
    if (value is AppMessage) return value;
    final text = value.toString();
    final exact = _keysByEnglish[text];
    if (exact != null) return AppMessage(exact);
    for (final item in _legacyTemplates) {
      final match = item.pattern.firstMatch(text);
      if (match == null) continue;
      return AppMessage(item.key, {
        for (var i = 0; i < item.parameters.length; i++)
          item.parameters[i]: match.group(i + 1),
      });
    }
    return AppMessage.literal(text);
  }

  bool get hasUrduSpeech => _literal == null && urduSpeechMessages.containsKey(key);

  String render(AppLanguage language, {bool spoken = false}) {
    if (_literal != null) return _literal!;
    final template = spoken && language == AppLanguage.romanUrdu
        ? urduSpeechMessages[key] ?? englishMessages[key]
        : language == AppLanguage.romanUrdu
            ? romanUrduMessages[key] ?? englishMessages[key]
            : englishMessages[key];
    if (template == null) return key;
    return template.replaceAllMapped(RegExp(r'\{(p\d+)\}'), (match) {
      final value = parameters[match.group(1)];
      return value is AppLabel
          ? value.render(language, spoken: spoken)
          : value is AppEnglishSuffix
              ? (language == AppLanguage.english ? value.value : '')
          : value is AppMessage
              ? value.render(language, spoken: spoken)
              : value?.toString() ?? '';
    });
  }
}

/// Marks a built-in section/category/period as translatable. Ordinary strings
/// passed as parameters remain untouched, including names such as "Food".
class AppLabel {
  final String value;
  const AppLabel(this.value);
  String render(AppLanguage language, {bool spoken = false}) {
    final message = AppMessage.resolve(value);
    return _dateWords(message.render(language, spoken: spoken), language, spoken);
  }
}

class AppEnglishSuffix {
  final String value;
  const AppEnglishSuffix(this.value);
}

String _dateWords(String text, AppLanguage language, bool spoken) {
  if (language == AppLanguage.english) return text;
  const names = {
    'January': ['Janwari', 'جنوری'], 'February': ['Farwari', 'فروری'],
    'March': ['March', 'مارچ'], 'April': ['April', 'اپریل'],
    'May': ['May', 'مئی'], 'June': ['June', 'جون'],
    'July': ['July', 'جولائی'], 'August': ['August', 'اگست'],
    'September': ['September', 'ستمبر'], 'October': ['October', 'اکتوبر'],
    'November': ['November', 'نومبر'], 'December': ['December', 'دسمبر'],
    'Monday': ['Peer', 'پیر'], 'Tuesday': ['Mangal', 'منگل'],
    'Wednesday': ['Budh', 'بدھ'], 'Thursday': ['Jumerat', 'جمعرات'],
    'Friday': ['Juma', 'جمعہ'], 'Saturday': ['Hafta', 'ہفتہ'],
    'Sunday': ['Itwar', 'اتوار'],
  };
  return text.replaceAllMapped(RegExp(r'\b[A-Za-z]+\b'), (match) {
    final word = match.group(0)!;
    final direct = names[word];
    if (direct != null) return direct[spoken ? 1 : 0];
    for (final item in names.entries) {
      if (item.key.substring(0, 3) == word) {
        return item.value[spoken ? 1 : 0];
      }
    }
    return word;
  });
}

final _keysByEnglish = <String, String>{
  for (final entry in englishMessages.entries) entry.value: entry.key,
};

class _LegacyTemplate {
  final String key;
  final RegExp pattern;
  final List<String> parameters;
  _LegacyTemplate(this.key, this.pattern, this.parameters);
}

final _legacyTemplates = englishMessages.entries
    .where((entry) => entry.value.contains(RegExp(r'\{p\d+\}')) &&
        entry.value.replaceAll(RegExp(r'\{p\d+\}'), '').contains(RegExp('[A-Za-z]')))
    .map((entry) {
      final names = <String>[];
      final pieces = <String>[];
      var position = 0;
      for (final token in RegExp(r'\{(p\d+)\}').allMatches(entry.value)) {
        pieces.add(RegExp.escape(entry.value.substring(position, token.start)));
        pieces.add('(.*?)');
        names.add(token.group(1)!);
        position = token.end;
      }
      pieces.add(RegExp.escape(entry.value.substring(position)));
      return _LegacyTemplate(entry.key, RegExp('^${pieces.join()}\$', dotAll: true), names);
    }).toList(growable: false);

class AppStrings {
  final AppLanguage language;
  const AppStrings(this.language);
  static AppStrings get current => AppStrings(AppLanguage.read());
  static AppStrings of(BuildContext context) =>
      Localizations.of<AppStrings>(context, AppStrings) ?? current;

  String text(String key, [Map<String, Object?> parameters = const {}]) =>
      AppMessage(key, parameters).render(language);

  String display(Object value) => AppMessage.resolve(value).render(language);
  String dateLabel(String value) => _dateWords(value, language, false);

  static const delegate = _AppStringsDelegate();
  static const supportedLocales = [
    Locale('en'),
    Locale.fromSubtags(languageCode: 'ur', scriptCode: 'Latn'),
  ];
}

class _AppStringsDelegate extends LocalizationsDelegate<AppStrings> {
  const _AppStringsDelegate();
  @override
  bool isSupported(Locale locale) => locale.languageCode == 'en' ||
      (locale.languageCode == 'ur' && locale.scriptCode == 'Latn');
  @override
  Future<AppStrings> load(Locale locale) => SynchronousFuture(AppStrings(
      locale.languageCode == 'ur' ? AppLanguage.romanUrdu : AppLanguage.english));
  @override
  bool shouldReload(_AppStringsDelegate old) => false;
}
