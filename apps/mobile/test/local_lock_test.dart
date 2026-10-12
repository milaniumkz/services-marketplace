import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:services_marketplace/core/local_lock.dart';
import 'package:services_marketplace/core/api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final values = <String, String>{};
  bool hardware = true, changed = false;
  setUp(() {
    values.clear();
    hardware = true;
    changed = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            (call) async {
      final a = Map<String, dynamic>.from(call.arguments as Map);
      switch (call.method) {
        case 'read':
          return values[a['key']];
        case 'write':
          values[a['key']] = a['value'];
          return null;
        case 'delete':
          values.remove(a['key']);
          return null;
        default:
          return null;
      }
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('joba.device_security'),
            (call) async {
      if (call.method == 'hardwareBacked') return hardware;
      if (changed && ['checkBiometry', 'unlockBiometry'].contains(call.method))
        throw PlatformException(code: 'BIOMETRY_CHANGED');
      return true;
    });
  });
  test('PBKDF2 agrees with an independent reference vector', () {
    expect(derivePin(['123456', 'am9iYS10ZXN0LXNhbHQ=']),
        'NL2ODT5cqt+zC52t+prc55Pnn8Exzgzv7Ul5SHSM6Xw=');
  });
  test('PIN is derived with PBKDF2 and exhausted attempts require full sign-in',
      () async {
    final lock = LocalLock('isolated-test');
    await lock.configure('123456');
    final raw = values[lock.key]!;
    expect(raw.contains('123456'), false);
    final record = jsonDecode(raw);
    expect(record['salt'], isNotEmpty);
    expect(record['hash'], isNotEmpty);
    expect(await lock.unlock('123456'), true);
    for (var i = 0; i < 4; i++) {
      expect(await lock.unlock('000000'), false);
    }
    await expectLater(
        lock.unlock('000000'),
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', 'PIN_EXHAUSTED')));
    expect(await lock.configured(), false);
  });
  test('Hardware protection missing prevents saving a PIN', () async {
    hardware = false;
    final lock = LocalLock('unsupported');
    await expectLater(lock.configure('123456'), throwsA(isA<ApiException>()));
    expect(values, isEmpty);
  });
  test('Changed biometric enrollment invalidates local unlock', () async {
    final lock = LocalLock('biometry-test');
    await lock.enableBiometry();
    expect(await lock.configured(), true);
    changed = true;
    await expectLater(
        lock.unlockBiometry(),
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', 'PIN_EXHAUSTED')));
    expect(await lock.configured(), false);
  });
}
