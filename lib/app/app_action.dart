import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AppActionType {
  openMonthlyPdf,
}

class AppActionRequest {
  final int id;
  final AppActionType action;

  const AppActionRequest({
    required this.id,
    required this.action,
  });
}

class AppActionController extends Notifier<AppActionRequest?> {
  int _nextId = 0;

  @override
  AppActionRequest? build() => null;

  void request(AppActionType action) {
    _nextId++;
    state = AppActionRequest(id: _nextId, action: action);
  }

  void consume(int id) {
    if (state?.id == id) state = null;
  }
}

final appActionProvider =
    NotifierProvider<AppActionController, AppActionRequest?>(
  AppActionController.new,
);
