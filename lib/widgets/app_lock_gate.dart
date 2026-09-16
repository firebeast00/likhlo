import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../services/biometric_service.dart';

class AppLockGate extends StatefulWidget {
  final Widget child;
  final DeviceAuthenticator? authenticator;
  final bool Function()? isLockEnabled;

  const AppLockGate({
    super.key,
    required this.child,
    this.authenticator,
    this.isLockEnabled,
  });

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate>
    with WidgetsBindingObserver {
  late final DeviceAuthenticator _authenticator;
  late bool _locked;
  bool _authenticating = false;
  bool _backgrounded = false;
  String? _message;

  bool _isEnabled() {
    final override = widget.isLockEnabled;
    if (override != null) return override();
    if (!Hive.isBoxOpen('preferences')) return false;
    return Hive.box('preferences').get(
          BiometricService.preferenceKey,
          defaultValue: false,
        ) ==
        true;
  }

  @override
  void initState() {
    super.initState();
    _authenticator = widget.authenticator ?? BiometricService();
    _locked = _isEnabled();
    WidgetsBinding.instance.addObserver(this);
    if (_locked) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _authenticate());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if ((state == AppLifecycleState.paused ||
            state == AppLifecycleState.detached) &&
        _isEnabled() &&
        !_authenticating) {
      _backgrounded = true;
      if (mounted && !_locked) {
        setState(() {
          _locked = true;
          _message = null;
        });
      }
      return;
    }

    if (state == AppLifecycleState.resumed && _backgrounded) {
      _backgrounded = false;
      if (_locked && !_authenticating) {
        _authenticate();
      }
    }
  }

  Future<void> _authenticate() async {
    if (_authenticating) return;
    if (!_isEnabled()) {
      if (mounted) {
        setState(() {
          _locked = false;
          _message = null;
        });
      }
      return;
    }

    setState(() {
      _authenticating = true;
      _message = null;
    });

    DeviceAuthResult result;
    try {
      result = await _authenticator.authenticate(
        reason: 'Unlock Likhlo to access your financial records.',
        biometricOnly: false,
      );
    } catch (error) {
      debugPrint('App unlock failed: $error');
      result = const DeviceAuthResult.failure(
        'Authentication could not be completed. Please try again.',
      );
    }
    if (!mounted) return;

    setState(() {
      _authenticating = false;
      _locked = !result.authenticated;
      _message = result.authenticated ? null : result.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_locked) return widget.child;

    final colors = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: colors.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.lock_rounded,
                        size: 52,
                        color: colors.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Likhlo is locked',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _message ??
                          'Authenticate with your fingerprint, Face ID, or device passcode to continue.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 28),
                    FilledButton.icon(
                      onPressed: _authenticating ? null : _authenticate,
                      icon: _authenticating
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.fingerprint_rounded),
                      label: Text(
                        _authenticating ? 'Authenticating…' : 'Unlock Likhlo',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
