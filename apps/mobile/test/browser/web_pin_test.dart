@TestOn('browser')
library;

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage_web/flutter_secure_storage_web.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:services_marketplace/core/local_lock.dart';
import 'package:services_marketplace/core/pin_kdf_web.dart';
import 'package:services_marketplace/screens/device_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorageWeb.registerWith(webPluginRegistrar);
  test('browser PBKDF2 matches the existing native reference vector', () async {
    expect(await deriveLocalPin('123456', 'am9iYS10ZXN0LXNhbHQ='),
        'NL2ODT5cqt+zC52t+prc55Pnn8Exzgzv7Ul5SHSM6Xw=');
  });
  test('browser persists PIN without a native device-security channel',
      () async {
    final scope = 'browser-pin-${DateTime.now().microsecondsSinceEpoch}';
    final lock = LocalLock(scope);
    addTearDown(lock.clear);
    await lock.configure('123456');
    final restored = LocalLock(scope);
    expect(await restored.pinLength(), 6);
    expect(await restored.unlock('654321'), false);
    expect(await restored.unlock('123456'), true);
    await restored.clear();
    expect(await restored.configured(), false);
  });

  testWidgets('web continues with saved PIN without offering native biometry',
      (t) async {
    var continued = false;
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: BiometrySetup(
      onEnable: () async => fail('Native biometry is unavailable in browser'),
      onPin: () => fail('Must continue with the saved PIN'),
      onContinue: () async {
        continued = true;
      },
    ))));
    expect(find.text('PIN сохранён'), findsOneWidget);
    expect(find.text('Включить биометрию'), findsNothing);
    await t.tap(find.text('Продолжить с PIN'));
    await t.pumpAndSettle();
    expect(continued, true);
  });
}
