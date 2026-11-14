import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:services_marketplace/core/local_lock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:services_marketplace/core/api.dart';
import 'package:services_marketplace/main.dart';
import 'package:services_marketplace/screens/marketplace.dart';

class _Vault implements SessionVault {
  String? value;
  int clears = 0;
  Future<String?> read() async => value;
  Future<void> write(String v) async {
    value = v;
  }

  Future<void> clear() async {
    value = null;
    clears++;
  }
}

void main() {
  testWidgets(
      'five real local PIN failures erase local protection and open the full-login state without API calls',
      (tester) async {
    // Keep Flutter's mock platform channel moving while the real KDF isolate runs.
    Future<void> drive(Future<void> operation) async {
      var complete = false;
      Object? failure;
      operation.then((_) {
        complete = true;
      }, onError: (Object e) {
        failure = e;
        complete = true;
      });
      for (var i = 0; i < 2000 && !complete; i++) {
        await tester.pump();
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)));
      }
      expect(complete, true, reason: 'KDF/platform operation did not finish');
      if (failure != null) throw failure!;
    }

    final storage = <String, String>{};
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const vaultChannel =
        MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    const deviceChannel = MethodChannel('joba.device_security');
    messenger.setMockMethodCallHandler(vaultChannel, (call) async {
      final args = Map<String, dynamic>.from(call.arguments as Map);
      switch (call.method) {
        case 'read':
          return storage[args['key']];
        case 'write':
          storage[args['key']] = args['value'];
          return null;
        case 'delete':
          storage.remove(args['key']);
          return null;
      }
      return null;
    });
    messenger.setMockMethodCallHandler(deviceChannel, (call) async => true);
    addTearDown(() => messenger.setMockMethodCallHandler(vaultChannel, null));
    addTearDown(() => messenger.setMockMethodCallHandler(deviceChannel, null));
    var requests = 0;
    final vault = _Vault();
    final api = JobaApi('https://isolated.example', vault: vault,
        transport: MockClient((r) async {
      requests++;
      return http.Response('{"data":{}}', 200);
    }));
    final protection = LocalLock('isolated-five-failures');
    await drive(protection.configure('123456'));
    expect(jsonDecode(storage[protection.key]!)['failures'], 0);
    await tester.pumpWidget(JobaApp(api: api));
    await tester.pumpAndSettle();
    final dynamic state = tester.state(find.byType(Marketplace));
    api.session = {
      'access_token': 'isolated-token',
      'refresh_token': 'isolated-refresh',
      'user': {'id': 'owner'}
    };
    vault.value = jsonEncode(api.session);
    state.lock = protection;
    state.locked = true;
    state.localProtected = true;
    state.go('unlock');
    await tester.pumpAndSettle();
    for (var i = 0; i < 4; i++) {
      Object? rejection;
      try {
        await drive(state.unlockSession(pin: '000000'));
      } catch (e) {
        rejection = e;
      }
      expect(rejection,
          isA<ApiException>().having((e) => e.code, 'code', 'PIN_INVALID'));
    }
    expect(jsonDecode(storage[protection.key]!)['failures'], 4);
    await drive(state.unlockSession(pin: '000000'));
    await tester.pumpAndSettle();
    expect(state.route, 'pin-limit');
    expect(state.locked, false);
    expect(state.localProtected, false);
    expect(api.authenticated, false);
    expect(vault.value, isNull);
    expect(vault.clears, 1);
    expect(storage.containsKey(protection.key), false);
    expect(requests, 0);
    expect(find.text('Войдите снова'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    api.dispose();
  });
  testWidgets(
      'PIN limit native viewport and enlarged narrow layout remain usable',
      (tester) async {
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    tester.view.padding = const FakeViewPadding(top: 86, bottom: 44);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    final capture = Platform.environment['JOBA_PIN_LIMIT_CAPTURE'];
    if (capture != null) {
      final font = FontLoader('Noto')
        ..addFont(rootBundle.load('assets/NotoSans-Regular.ttf'))
        ..addFont(rootBundle.load('assets/NotoSans-Bold.ttf'));
      await font.load();
    }
    final api = JobaApi('https://isolated.example', vault: _Vault());
    final boundary = GlobalKey();
    await tester
        .pumpWidget(RepaintBoundary(key: boundary, child: JobaApp(api: api)));
    await tester.pumpAndSettle();
    final dynamic state = tester.state(find.byType(Marketplace));
    state.go('pin-limit');
    state.history.clear();
    await tester.pumpAndSettle();
    if (capture != null)
      await tester.runAsync(() async {
        final render = boundary.currentContext!.findRenderObject()
            as RenderRepaintBoundary;
        final image = await render.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(capture).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    tester.view.physicalSize = const Size(640, 1280);
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Помощь со входом'), 150,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Помощь со входом'));
    await tester.pumpAndSettle();
    expect(state.route, 'recovery');
    await tester.pumpWidget(const SizedBox());
    api.dispose();
  });
  for (final action in ['back', 'system', 'login', 'help']) {
    testWidgets('PIN limit $action reaches full sign-in without a route loop',
        (tester) async {
      var requests = 0;
      final api = JobaApi('https://isolated.example', vault: _Vault(),
          transport: MockClient((r) async {
        requests++;
        return http.Response('{"data":{}}', 200);
      }));
      await tester.pumpWidget(JobaApp(api: api));
      await tester.pumpAndSettle();
      final dynamic state = tester.state(find.byType(Marketplace));
      state.go('pin-limit');
      state.history.clear();
      await tester.pumpAndSettle();
      if (action == 'back') await tester.tap(find.byTooltip('Назад'));
      if (action == 'system') await tester.binding.handlePopRoute();
      if (action == 'login')
        await tester
            .tap(find.widgetWithText(FilledButton, 'Войти номером и паролем'));
      if (action == 'help') {
        await tester.scrollUntilVisible(find.text('Помощь со входом'), 150,
            scrollable: find.byType(Scrollable).first);
        await tester.tap(find.text('Помощь со входом'));
        await tester.pumpAndSettle();
        expect(state.route, 'recovery');
        await tester.tap(find.byTooltip('Назад'));
      }
      await tester.pumpAndSettle();
      expect(state.route, 'login');
      expect(state.history, isEmpty);
      expect(requests, 0);
      expect(api.authenticated, false);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      api.dispose();
    });
  }
}
