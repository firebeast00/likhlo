import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/error_codes.dart' as auth_error;
import 'package:local_auth/local_auth.dart';

class DeviceAuthResult {
  final bool authenticated;
  final String message;

  const DeviceAuthResult({
    required this.authenticated,
    required this.message,
  });

  const DeviceAuthResult.success()
      : authenticated = true,
        message = '';

  const DeviceAuthResult.failure(this.message) : authenticated = false;
}

abstract class DeviceAuthenticator {
  Future<bool> canUseBiometrics();

  Future<DeviceAuthResult> authenticate({
    required String reason,
    required bool biometricOnly,
  });
}

class BiometricService implements DeviceAuthenticator {
  static const String preferenceKey = 'app_lock_enabled';

  final LocalAuthentication _localAuthentication;

  BiometricService({LocalAuthentication? localAuthentication})
      : _localAuthentication = localAuthentication ?? LocalAuthentication();

  @override
  Future<bool> canUseBiometrics() async {
    try {
      final canCheck = await _localAuthentication.canCheckBiometrics;
      if (!canCheck) return false;
      final enrolled = await _localAuthentication.getAvailableBiometrics();
      return enrolled.isNotEmpty;
    } on PlatformException catch (error) {
      debugPrint('Biometric availability check failed: $error');
      return false;
    }
  }

  @override
  Future<DeviceAuthResult> authenticate({
    required String reason,
    required bool biometricOnly,
  }) async {
    try {
      final authenticated = await _localAuthentication.authenticate(
        localizedReason: reason,
        options: AuthenticationOptions(
          biometricOnly: biometricOnly,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
      return authenticated
          ? const DeviceAuthResult.success()
          : const DeviceAuthResult.failure(
              'Authentication was cancelled. Your financial records remain locked.',
            );
    } on PlatformException catch (error) {
      return DeviceAuthResult.failure(_messageFor(error.code));
    } catch (error) {
      debugPrint('Device authentication failed: $error');
      return const DeviceAuthResult.failure(
        'Device authentication is unavailable. Check your phone security settings and try again.',
      );
    }
  }

  String _messageFor(String code) {
    if (code == auth_error.notEnrolled) {
      return 'No fingerprint or Face ID is enrolled. Add one in your phone settings first.';
    }
    if (code == auth_error.passcodeNotSet) {
      return 'Set a secure screen lock on your phone before using Likhlo App Lock.';
    }
    if (code == auth_error.lockedOut) {
      return 'Authentication is temporarily locked after too many attempts. Wait briefly, then try again.';
    }
    if (code == auth_error.permanentlyLockedOut) {
      return 'Authentication is locked. Unlock your phone with its PIN or passcode, then try again.';
    }
    if (code == auth_error.notAvailable) {
      return 'Fingerprint, Face ID, or device authentication is not available on this phone.';
    }
    return 'Authentication could not be completed. Please try again.';
  }
}
