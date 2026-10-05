/// Retry a failed, empty device-recognition attempt offline at most once.
/// Offline recognition is a request to the device, not a guarantee that its
/// selected language pack is installed. Never switch languages or providers.
class SpeechNetworkRecovery {
  bool _onDevice = false;
  bool get onDevice => _onDevice;

  void reset() => _onDevice = false;

  bool tryOffline(String error, {
    required bool isCloud,
    required bool hasDraft,
    required int retryCount,
  }) {
    final normalized = error.toLowerCase();
    final networkFailure = normalized.contains('error_network') ||
        normalized.contains('error_server');
    if (!networkFailure || normalized.contains('error_too_many_requests') ||
        isCloud || hasDraft || retryCount != 0 || _onDevice) return false;
    _onDevice = true;
    return true;
  }
}
