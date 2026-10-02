class AppLockActivityGuard {
  AppLockActivityGuard._();

  static int _externalActivityDepth = 0;

  static bool get isExternalActivityActive => _externalActivityDepth > 0;

  static void beginExternalActivity() {
    _externalActivityDepth++;
  }

  static void endExternalActivity() {
    if (_externalActivityDepth > 0) {
      _externalActivityDepth--;
    }
  }

  static Future<T> protectExternalActivity<T>(
    Future<T> Function() action,
  ) async {
    beginExternalActivity();
    try {
      return await action();
    } finally {
      endExternalActivity();
    }
  }
}
