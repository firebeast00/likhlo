import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:student_expense_manager/services/backup_codec.dart';

void main() {
  late BackupCodec codec;

  setUp(() {
    codec = BackupCodec(
      kdf: Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: 10,
        bits: 256,
      ),
    );
  });

  test('encrypted backup round-trips without exposing financial text',
      () async {
    final payload = <String, dynamic>{
      'schemaVersion': 1,
      'app': 'Likhlo',
      'data': <String, dynamic>{'balance': 5500, 'account': 'JazzCash'},
    };

    final encrypted = await codec.encrypt(payload, 'correct horse');
    expect(utf8.decode(encrypted), isNot(contains('JazzCash')));
    expect(await codec.decrypt(encrypted, 'correct horse'), payload);
  });

  test('wrong passphrase cannot decrypt backup', () async {
    final encrypted = await codec.encrypt(
      <String, dynamic>{'schemaVersion': 1},
      'correct horse',
    );

    expect(
      () => codec.decrypt(encrypted, 'wrong horse'),
      throwsA(isA<BackupException>()),
    );
  });

  test('unsupported and malformed files are rejected', () async {
    final invalid = Uint8List.fromList(utf8.encode(jsonEncode({
      'format': BackupCodec.format,
      'version': 99,
    })));

    expect(
      () => codec.decrypt(invalid, 'correct horse'),
      throwsA(isA<BackupException>()),
    );
  });

  test('short passphrases are rejected before encryption', () {
    expect(
      () => codec.encrypt(<String, dynamic>{}, 'short'),
      throwsA(isA<BackupException>()),
    );
  });
}
