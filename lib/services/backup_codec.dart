import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

class BackupException implements Exception {
  final String message;

  const BackupException(this.message);

  @override
  String toString() => message;
}

/// Encodes Likhlo data in an authenticated, password-protected envelope.
///
/// The JSON envelope is intentionally versioned so future releases can reject
/// unsupported formats without touching the user's local Hive boxes.
class BackupCodec {
  static const String format = 'likhlo-encrypted-backup';
  static const int formatVersion = 1;
  static const int kdfIterations = 120000;

  final Cipher _cipher;
  final KdfAlgorithm _kdf;

  BackupCodec({Cipher? cipher, KdfAlgorithm? kdf})
      : _cipher = cipher ?? AesGcm.with256bits(),
        _kdf = kdf ??
            Pbkdf2(
              macAlgorithm: Hmac.sha256(),
              iterations: kdfIterations,
              bits: 256,
            );

  Future<Uint8List> encrypt(
    Map<String, dynamic> payload,
    String password,
  ) async {
    _validatePassword(password);
    final secureRandom = Random.secure();
    final salt = List<int>.generate(
      16,
      (_) => secureRandom.nextInt(256),
      growable: false,
    );
    final secretKey = await _kdf.deriveKeyFromPassword(
      password: password,
      nonce: salt,
    );
    final secretBox = await _cipher.encrypt(
      utf8.encode(jsonEncode(payload)),
      secretKey: secretKey,
    );
    final envelope = <String, dynamic>{
      'format': format,
      'version': formatVersion,
      'kdf': <String, dynamic>{
        'name': 'pbkdf2-hmac-sha256',
        'iterations': kdfIterations,
        'salt': base64Encode(salt),
      },
      'cipher': <String, dynamic>{
        'name': 'aes-256-gcm',
        'nonce': base64Encode(secretBox.nonce),
        'cipherText': base64Encode(secretBox.cipherText),
        'mac': base64Encode(secretBox.mac.bytes),
      },
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(envelope)));
  }

  Future<Map<String, dynamic>> decrypt(
    Uint8List bytes,
    String password,
  ) async {
    _validatePassword(password);
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<String, dynamic> ||
          decoded['format'] != format ||
          decoded['version'] != formatVersion) {
        throw const BackupException(
          'This is not a supported Likhlo backup file.',
        );
      }

      final kdfData = _map(decoded['kdf']);
      final cipherData = _map(decoded['cipher']);
      if (kdfData['name'] != 'pbkdf2-hmac-sha256' ||
          kdfData['iterations'] != kdfIterations ||
          cipherData['name'] != 'aes-256-gcm') {
        throw const BackupException(
          'This backup uses an unsupported encryption format.',
        );
      }

      final salt = base64Decode(_string(kdfData['salt']));
      final nonce = base64Decode(_string(cipherData['nonce']));
      final cipherText = base64Decode(_string(cipherData['cipherText']));
      final mac = base64Decode(_string(cipherData['mac']));
      if (salt.length != 16 || nonce.length != 12 || mac.length != 16) {
        throw const BackupException('The backup file is damaged.');
      }

      final secretKey = await _kdf.deriveKeyFromPassword(
        password: password,
        nonce: salt,
      );
      final clearText = await _cipher.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
        secretKey: secretKey,
      );
      final payload = jsonDecode(utf8.decode(clearText));
      if (payload is! Map<String, dynamic>) {
        throw const BackupException('The backup payload is invalid.');
      }
      return payload;
    } on BackupException {
      rethrow;
    } on SecretBoxAuthenticationError {
      throw const BackupException(
        'Incorrect passphrase or the backup file was modified.',
      );
    } on FormatException {
      throw const BackupException('The backup file is damaged.');
    } catch (_) {
      throw const BackupException(
        'Could not decrypt this backup. Check the passphrase and file.',
      );
    }
  }

  static void _validatePassword(String password) {
    if (password.length < 8) {
      throw const BackupException(
        'Use a passphrase containing at least 8 characters.',
      );
    }
  }

  static Map<String, dynamic> _map(Object? value) {
    if (value is Map<String, dynamic>) return value;
    throw const BackupException('The backup file is damaged.');
  }

  static String _string(Object? value) {
    if (value is String && value.isNotEmpty) return value;
    throw const BackupException('The backup file is damaged.');
  }
}
