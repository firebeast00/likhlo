import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AppActionType {
  openMonthlyPdf,
  openStatsMonth,
  openMonthlyPlan,
  runMonthlyPlanCommand,
  openBackup,
  persistentQuickEntryOn,
  persistentQuickEntryOff,
  smartRemindersOn,
  smartRemindersOff,
  spokenConfirmationsOn,
  spokenConfirmationsOff,
  smartEntryLanguageRomanUrdu,
  smartEntryLanguageEnglish,
  appLockOn,
  appLockOff,
}

class AppActionRequest {
  final int id;
  final AppActionType action;
  final DateTime? month;
  final String? text;

  const AppActionRequest({
    required this.id,
    required this.action,
    this.month,
    this.text,
  });
}

class AppActionController extends Notifier<AppActionRequest?> {
  int _nextId = 0;

  @override
  AppActionRequest? build() => null;

  void request(
    AppActionType action, {
    DateTime? month,
    String? text,
  }) {
    _nextId++;
    state = AppActionRequest(
      id: _nextId,
      action: action,
      month: month,
      text: text,
    );
  }

  void consume(int id) {
    if (state?.id == id) state = null;
  }
}

final appActionProvider =
    NotifierProvider<AppActionController, AppActionRequest?>(
  AppActionController.new,
);
