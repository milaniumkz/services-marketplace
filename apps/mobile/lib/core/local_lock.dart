import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';
import 'api.dart';

// PBKDF2-HMAC-SHA256. Work executes off the UI isolate; PIN never leaves the device.
String derivePin(List<String> input) {
  final prf = Hmac(sha256, utf8.encode(input[0]));
  var block = prf.convert([...base64Decode(input[1]), 0, 0, 0, 1]).bytes;
  final result = List<int>.from(block);
  for (var iteration = 1; iteration < 100000; iteration++) {
    block = prf.convert(block).bytes;
    for (var i = 0; i < result.length; i++) {
      result[i] ^= block[i];
    }
  }
  return base64Encode(result);
}

class LocalLock {
  final String key;
  final FlutterSecureStorage storage;
  String get alias => 'joba.biometry.${sha256.convert(utf8.encode(key))}';
  LocalLock(String scope,
      {this.storage = const FlutterSecureStorage(
          aOptions: AndroidOptions(encryptedSharedPreferences: true),
          iOptions: IOSOptions(accessibility: KeychainAccessibility.passcode))})
      : key = 'joba.lock.$scope';
  Future<bool> hasPin() async => await storage.read(key: key) != null;
  Future<bool> configured() async =>
      await storage.read(key: key) != null || await hasBiometry();
  Future<bool> hasBiometry() async =>
      await storage.read(key: '$key.biometry') == 'enabled';
  Future<void> enableBiometry() async {
    final protected = await const MethodChannel('joba.device_security')
        .invokeMethod<bool>('hardwareBacked');
    if (protected != true)
      throw ApiException('LOCAL_PROTECTION_UNAVAILABLE',
          'Используйте вход с номером и паролем');
    final ok = await const MethodChannel('joba.device_security')
        .invokeMethod<bool>('enableBiometry', {'alias': alias});
    if (ok != true)
      throw ApiException(
          'BIOMETRY_UNAVAILABLE', 'Не удалось включить биометрию');
    await storage.write(key: '$key.biometry', value: 'enabled');
  }

  Future<bool> unlockBiometry(
      {String title = 'JOBA', String cancel = 'Cancel'}) async {
    if (!await hasBiometry())
      throw ApiException('BIOMETRY_UNAVAILABLE', 'Биометрия не настроена');
    try {
      return await const MethodChannel('joba.device_security')
              .invokeMethod<bool>('unlockBiometry',
                  {'alias': alias, 'title': title, 'cancel': cancel}) ??
          false;
    } on PlatformException catch (e) {
      if (e.code == 'BIOMETRY_CHANGED') {
        await clear();
        throw ApiException(
            'PIN_EXHAUSTED', 'Биометрия изменилась. Войдите с паролем', 401);
      }
      throw ApiException(e.code, 'Биометрия не настроена');
    }
  }

  Future<void> configure(String pin) async {
    if (!RegExp(r'^\d{6,8}$').hasMatch(pin))
      throw ApiException('PIN_INVALID', 'PIN должен содержать 6–8 цифр');
    bool hardware = false;
    try {
      hardware = await const MethodChannel('joba.device_security')
              .invokeMethod<bool>('hardwareBacked') ??
          false;
    } on PlatformException {
      hardware = false;
    } on MissingPluginException {
      hardware = false;
    }
    if (!hardware)
      throw ApiException('LOCAL_PROTECTION_UNAVAILABLE',
          'На этом устройстве используйте вход с номером и паролем.');
    final random = Random.secure(),
        salt = base64Encode(List.generate(32, (_) => random.nextInt(256)));
    final hash = await compute(derivePin, [pin, salt]);
    await storage.write(
        key: key,
        value: jsonEncode({'salt': salt, 'hash': hash, 'failures': 0}));
  }

  Future<bool> unlock(String pin) async {
    if (await hasBiometry()) {
      try {
        final valid = await const MethodChannel('joba.device_security')
            .invokeMethod<bool>('checkBiometry', {'alias': alias});
        if (valid != true) {
          await clear();
          throw ApiException('PIN_EXHAUSTED', 'Войдите снова с паролем', 401);
        }
      } on PlatformException catch (e) {
        if (e.code == 'BIOMETRY_CHANGED') {
          await clear();
          throw ApiException('PIN_EXHAUSTED', 'Войдите снова с паролем', 401);
        }
        rethrow;
      }
    }
    final raw = await storage.read(key: key);
    if (raw == null) return false;
    final record = jsonDecode(raw) as Json;
    final failures = (record['failures'] as int) + 1;
    if (failures > 5) {
      await clear();
      throw ApiException(
          'PIN_EXHAUSTED', 'Войдите снова с номером и паролем', 401);
    }
    // Persist attempt before KDF, including interrupted attempts.
    await storage.write(
        key: key, value: jsonEncode({...record, 'failures': failures}));
    final actual = base64Decode(
        await compute(derivePin, <String>[pin, record['salt'] as String]));
    final expected = base64Decode(record['hash']);
    var difference = actual.length ^ expected.length;
    for (var i = 0; i < actual.length && i < expected.length; i++) {
      difference |= actual[i] ^ expected[i];
    }
    if (difference != 0) {
      if (failures >= 5) {
        await clear();
        throw ApiException(
            'PIN_EXHAUSTED', 'Войдите снова с номером и паролем', 401);
      }
      return false;
    }
    await storage.write(
        key: key, value: jsonEncode({...record, 'failures': 0}));
    return true;
  }

  Future<void> clear() async {
    await storage.delete(key: key);
    await storage.delete(key: '$key.biometry');
    try {
      await const MethodChannel('joba.device_security')
          .invokeMethod('clearBiometry', {'alias': alias});
    } on PlatformException {
      /* Server authentication is still required. */
    } on MissingPluginException {
      /* Unsupported platforms use full password sign-in. */
    }
  }
}
