import '../l10n/app_strings.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../providers/category_provider.dart';
import '../providers/expense_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/wallet_provider.dart';
import '../services/backup_codec.dart';
import '../services/backup_service.dart';
import '../services/automatic_backup_service.dart';

class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  final BackupService _service = BackupService();
  final BackupCodec _codec = BackupCodec();
  bool _busy = false;
  bool _hasRecovery = false;

  @override
  void initState() {
    super.initState();
    _refreshRecoveryState();
  }

  Future<void> _refreshRecoveryState() async {
    final available = await _service.hasRecoverySnapshot();
    if (mounted) setState(() => _hasRecovery = available);
  }

  Future<void> _createBackup() async {
    final password = await showDialog<String>(
      context: context,
      builder: (_) => const _BackupPasswordDialog(confirmPassword: true),
    );
    if (password == null || !mounted) return;
    await _runBusy(() async {
      final payload = await _service.createPayload();
      final fingerprint = BackupService.contentFingerprint(payload);
      final bytes = await _codec.encrypt(payload, password);
      if (bytes.length > BackupService.maxBackupBytes) {
        throw const BackupException('This backup exceeds the 25 MB limit.');
      }
      final timestamp = DateFormat('yyyy-MM-dd_HHmm').format(DateTime.now());
      if (defaultTargetPlatform == TargetPlatform.android &&
          await AutomaticBackupService.instance.supported) {
        final saved = await AutomaticBackupService.instance.saveNew(
          bytes,
          password,
          'Likhlo_Backup_$timestamp.likhlo',
          fingerprint: fingerprint,
        );
        if (saved && mounted) {
          _showMessage(
            'Encrypted backup saved. Automatic refresh runs daily only when your data changed.',
          );
        }
        return;
      }
      final destination = await FilePicker.platform.saveFile(
        dialogTitle: 'Save encrypted Likhlo backup',
        fileName: 'Likhlo_Backup_$timestamp.likhlo',
        type: FileType.custom,
        allowedExtensions: const ['likhlo'],
        bytes: bytes,
      );
      if (destination != null && mounted) {
        _showMessage('Encrypted backup saved successfully.');
      }
    });
  }

  Future<void> _restoreBackup() async {
    FilePickerResult? result;
    try {
      // Android does not map the private .likhlo extension to a MIME type.
      // The authenticated codec verifies the selected document instead.
      result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Choose a Likhlo backup',
        type: FileType.any,
        allowMultiple: false,
        withData: true,
      );
    } on PlatformException catch (error) {
      debugPrint('Backup picker failed: $error');
      if (mounted) {
        _showMessage('Could not open the file picker. Please try again.');
      }
      return;
    } catch (error) {
      debugPrint('Backup picker failed: $error');
      if (mounted) _showMessage('Could not select the backup file.');
      return;
    }

    if (result == null || result.files.isEmpty || !mounted) return;
    final selected = result.files.single;
    if (selected.size > BackupService.maxBackupBytes) {
      _showMessage('This backup is larger than the 25 MB safety limit.');
      return;
    }
    final password = await showDialog<String>(
      context: context,
      builder: (_) => const _BackupPasswordDialog(confirmPassword: false),
    );
    if (password == null || !mounted) return;

    await _runBusy(() async {
      Uint8List bytes;
      try {
        bytes = selected.bytes ?? await selected.xFile.readAsBytes();
      } catch (error) {
        debugPrint('Could not read selected backup: $error');
        throw const BackupException(
          'Could not read this file. Select the original Likhlo backup again.',
        );
      }
      if (bytes.length > BackupService.maxBackupBytes) {
        throw const BackupException(
          'This backup is larger than the 25 MB safety limit.',
        );
      }
      final payload = await _codec.decrypt(bytes, password);
      final backup = _service.validate(payload);
      if (!mounted) return;
      final confirmed = await _confirmRestore(backup.preview);
      if (!confirmed) return;
      await _service.restore(backup);
      _refreshProviders();
      await _refreshRecoveryState();
      if (mounted) {
        _showMessage(
          'Backup restored successfully. Your previous data is available as a recovery snapshot.',
        );
      }
    });
  }

  Future<void> _restorePreviousData() async {
    await _runBusy(() async {
      final backup = await _service.readRecoverySnapshot();
      if (backup == null) {
        throw const BackupException('No valid recovery snapshot is available.');
      }
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(AppStrings.current.text('recover_previous_data_d16eb5')),
              content: Text(
                AppStrings.current.text('this_replaces_the_current_data_with_the_snapshot_342c91'),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(AppStrings.current.text('cancel_77dfd2')),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(AppStrings.current.text('recover_4addbf')),
                ),
              ],
            ),
          ) ??
          false;
      if (!confirmed) return;
      await _service.restoreRecoverySnapshot(backup);
      _refreshProviders();
      await _refreshRecoveryState();
      if (mounted) _showMessage('Previous data recovered.');
    });
  }

  Future<bool> _confirmRestore(BackupPreview preview) async {
    final created = DateFormat('dd MMM yyyy, h:mm a').format(preview.createdAt);
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(AppStrings.current.text('review_backup_d1e459')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(AppStrings.current.text('created_08513d', {'p0': created})),
                const SizedBox(height: 16),
                _CountRow('Transactions', preview.expenses),
                _CountRow('Wallets', preview.wallets),
                _CountRow('Categories', preview.categories),
                _CountRow('Udhar records', preview.debts),
                const SizedBox(height: 16),
                Text(
                  AppStrings.current.text('current_data_will_be_replaced_likhlo_will_first__e5d8b7'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(AppStrings.current.text('cancel_77dfd2')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(AppStrings.current.text('restore_3cbe6d')),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _refreshProviders() {
    ref.invalidate(expenseProvider);
    ref.invalidate(walletProvider);
    ref.invalidate(categoryProvider);
    ref.invalidate(settingsProvider);
  }

  Future<void> _runBusy(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on BackupException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (error) {
      debugPrint('Backup operation failed: $error');
      if (mounted) {
        _showMessage('Backup operation failed. No data was deleted.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(AppStrings.current.display(message))));
  }

  @override
  Widget build(BuildContext context) {
    AppStrings.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    return Scaffold(
      appBar: AppBar(title: Text(AppStrings.current.text('backup_restore_3bdd40'))),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.lock_rounded, size: 32),
                    SizedBox(height: 12),
                    Text(
                      AppStrings.current.text('your_financial_data_stays_private_eafd2a'),
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                    SizedBox(height: 6),
                    Text(
                      AppStrings.current.text('backups_are_encrypted_before_leaving_the_app_kee_415db3'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppStrings.current.text('smart_backup_5ed013'),
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    SizedBox(height: 6),
                    Text(
                      AppStrings.current.text('on_android_the_backup_file_you_select_becomes_th_373cc8'),
                      style: TextStyle(fontSize: 12, height: 1.4),
                    ),
                    SizedBox(height: 6),
                    Text(
                      AppStrings.current.text('device_biometrics_the_automatic_backup_timestamp_18c56f'),
                      style: TextStyle(fontSize: 12, height: 1.4),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.backup_rounded),
                      title: Text(AppStrings.current.text('create_encrypted_backup_56c337')),
                      subtitle: Text(
                        AppStrings.current.text('transactions_trash_wallets_categories_settings_p_cceb75'),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: _busy ? null : _createBackup,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.restore_rounded),
                      title: Text(AppStrings.current.text('restore_from_backup_eb2bb4')),
                      subtitle: Text(
                          AppStrings.current.text('validate_and_preview_before_replacing_data_183600')),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: _busy ? null : _restoreBackup,
                    ),
                    if (_hasRecovery) ...[
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.history_rounded),
                        title: Text(AppStrings.current.text('recover_data_before_last_restore_7eec15')),
                        subtitle: Text(
                            AppStrings.current.text('available_until_the_next_successful_recovery_a3d274')),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: _busy ? null : _restorePreviousData,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (_busy)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x55000000),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }
}

class _CountRow extends StatelessWidget {
  final String label;
  final int value;

  const _CountRow(this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(AppStrings.current.display(label)),
            Text('$value', style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      );
}

class _BackupPasswordDialog extends StatefulWidget {
  final bool confirmPassword;

  const _BackupPasswordDialog({required this.confirmPassword});

  @override
  State<_BackupPasswordDialog> createState() => _BackupPasswordDialogState();
}

class _BackupPasswordDialogState extends State<_BackupPasswordDialog> {
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscure = true;

  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title:
            Text(widget.confirmPassword ? AppStrings.current.text('protect_backup_b03065') : AppStrings.current.text('unlock_backup_f761d5')),
        content: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _password,
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: AppStrings.current.text('passphrase_89950c'),
                  helperText: widget.confirmPassword
                      ? AppStrings.current.text('at_least_8_characters_it_cannot_be_recovered_b299d6')
                      : null,
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(
                        _obscure ? Icons.visibility : Icons.visibility_off),
                  ),
                ),
                validator: (value) => (value ?? '').length < 8
                    ? 'Enter at least 8 characters'
                    : null,
              ),
              if (widget.confirmPassword) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _confirmation,
                  obscureText: _obscure,
                  decoration:
                      InputDecoration(labelText: AppStrings.current.text('confirm_passphrase_ebaac0')),
                  validator: (value) => value != _password.text
                      ? 'Passphrases do not match'
                      : null,
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppStrings.current.text('cancel_77dfd2')),
          ),
          FilledButton(
            onPressed: () {
              if (_formKey.currentState?.validate() != true) return;
              Navigator.pop(context, _password.text);
            },
            child: Text(widget.confirmPassword ? AppStrings.current.text('continue_2e0262') : AppStrings.current.text('unlock_1526a1')),
          ),
        ],
      );
}
