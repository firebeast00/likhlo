import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_strings.dart';

/// Roman Urdu is Latin-script and left-to-right. Keep English date parsing,
/// numeric formatting and calendar limits; customize the visible controls.
class AppMaterialDelegate extends LocalizationsDelegate<MaterialLocalizations> {
  const AppMaterialDelegate();
  @override
  bool isSupported(Locale locale) => AppStrings.delegate.isSupported(locale);
  @override
  Future<MaterialLocalizations> load(Locale locale) =>
      SynchronousFuture<MaterialLocalizations>(locale.languageCode == 'ur'
          ? const RomanUrduMaterialStrings()
          : const DefaultMaterialLocalizations());
  @override
  bool shouldReload(AppMaterialDelegate old) => false;
}

class AppWidgetsDelegate extends LocalizationsDelegate<WidgetsLocalizations> {
  const AppWidgetsDelegate();
  @override
  bool isSupported(Locale locale) => AppStrings.delegate.isSupported(locale);
  @override
  Future<WidgetsLocalizations> load(Locale locale) =>
      SynchronousFuture<WidgetsLocalizations>(const DefaultWidgetsLocalizations());
  @override
  bool shouldReload(AppWidgetsDelegate old) => false;
}

class RomanUrduMaterialStrings extends DefaultMaterialLocalizations {
  const RomanUrduMaterialStrings();
  @override
  String get cancelButtonLabel => 'Cancel';
  @override
  String get okButtonLabel => 'Theek hai';
  @override
  String get saveButtonLabel => 'Save';
  @override
  String get closeButtonLabel => 'Band karen';
  @override
  String get closeButtonTooltip => 'Band karen';
  @override
  String get backButtonTooltip => 'Wapas';
  @override
  String get nextMonthTooltip => 'Agla mahina';
  @override
  String get previousMonthTooltip => 'Pichla mahina';
  @override
  String get datePickerHelpText => 'Tareekh chunen';
  @override
  String get dateRangePickerHelpText => 'Tareekhon ka arsa chunen';
  @override
  String get dateInputLabel => 'Tareekh likhen';
  @override
  String get dateRangeStartLabel => 'Shuru ki tareekh';
  @override
  String get dateRangeEndLabel => 'Aakhri tareekh';
  @override
  String get invalidDateFormatLabel => 'Tareekh ka format sahi nahi';
  @override
  String get dateOutOfRangeLabel => 'Tareekh dastiyab arse se bahar hai';
  @override
  String get invalidDateRangeLabel => 'Tareekhon ka arsa sahi nahi';
  @override
  String get calendarModeButtonLabel => 'Calendar se chunen';
  @override
  String get inputDateModeButtonLabel => 'Tareekh likhen';
  @override
  String get timePickerDialHelpText => 'Waqt chunen';
  @override
  String get timePickerInputHelpText => 'Waqt likhen';
  @override
  String get timePickerHourLabel => 'Ghanta';
  @override
  String get timePickerMinuteLabel => 'Minute';
  @override
  String get invalidTimeLabel => 'Waqt sahi nahi';
  @override
  String get inputTimeModeButtonLabel => 'Waqt likhen';
  @override
  String get dialModeButtonLabel => 'Dial se waqt chunen';
  @override
  String get copyButtonLabel => 'Copy';
  @override
  String get cutButtonLabel => 'Cut';
  @override
  String get pasteButtonLabel => 'Paste';
  @override
  String get selectAllButtonLabel => 'Sab chunen';
  @override
  String get lookUpButtonLabel => 'Talash karen';
  @override
  String get searchWebButtonLabel => 'Web par talash';
  @override
  String get shareButtonLabel => 'Share';
  @override
  String get menuBarMenuLabel => 'Menu';
  @override
  String get popupMenuLabel => 'Menu';
  @override
  String get drawerLabel => 'Menu';
  @override
  String get dialogLabel => 'Dialog';
  @override
  String get alertDialogLabel => 'Alert';
  @override
  String get deleteButtonTooltip => 'Delete';
  @override
  String get moreButtonTooltip => 'Mazeed';
}
