import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:services_marketplace/core/api.dart';
import 'package:services_marketplace/core/local_lock.dart';
import 'package:services_marketplace/core/widgets.dart';
import 'package:services_marketplace/main.dart';
import 'package:services_marketplace/screens/marketplace.dart';

class _Vault implements SessionVault {
  Future<String?> read() async => null;
  Future<void> write(String v) async {}
  Future<void> clear() async {}
}

class _Api extends JobaApi {
  int refreshes = 0;
  bool offline = false;
  _Api({String profileId = "owner"})
      : super('https://isolated.example',
            vault: _Vault(),
            transport: MockClient((r) async => http.Response(
                '{"data":{"id":"$profileId","country":"KZ","locale":"ru","roles":["customer"],"active_role":"customer","items":[]}}',
                200)));
  Future<void> refresh() async {
    refreshes++;
    if (offline) throw ApiException("OFFLINE", "Нет соединения");
  }
}

class _Lock extends LocalLock {
  final gate = Completer<bool>();
  int pins = 0, bios = 0;
  Object? failure;
  bool bioResult = true;
  _Lock() : super('isolated-owner');
  Future<bool> unlock(String pin) async {
    pins++;
    if (failure != null) throw failure!;
    return gate.future;
  }

  Future<bool> unlockBiometry(
      {String title = 'JOBA', String cancel = 'Cancel'}) async {
    bios++;
    return bioResult;
  }

  Future<void> clear() async {}
}

class _SetupLock extends LocalLock {
  final gate = Completer<void>();
  _SetupLock() : super('isolated-biometry-owner');
  Future<void> enableBiometry() => gate.future;
  Future<void> clear() async {}
}

void main() {
  for (final outcome in ['success', 'failure', 'logout']) {
    testWidgets(
        'standalone biometric setup handles $outcome with a real route fallback',
        (tester) async {
      final api = _Api(), protection = _SetupLock();
      await tester.pumpWidget(JobaApp(api: api));
      await tester.pumpAndSettle();
      final dynamic state = tester.state(find.byType(Marketplace));
      api.session = {
        'access_token': 'isolated-token',
        'user': {'id': 'owner'}
      };
      await api.setPersistence(false);
      state.me = {'id': 'owner', 'country': 'KZ', 'locale': 'ru'};
      state.lock = protection;
      state.go('biometric');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Включить биометрию'));
      await tester.pump();
      state.back();
      expect(state.route, 'biometric');
      if (outcome == 'logout') {
        await api.forget();
        await tester.pumpAndSettle();
      }
      if (outcome == 'failure')
        protection.gate
            .completeError(ApiException('BIOMETRY_UNAVAILABLE', 'Недоступно'));
      else
        protection.gate.complete();
      await tester.pumpAndSettle();
      if (outcome == 'failure') {
        expect(find.text('Используйте PIN'), findsOneWidget);
        await tester.tap(find.text('Ввести PIN'));
        await tester.pumpAndSettle();
        expect(state.route, 'pin-setup');
      } else
        expect(state.route, outcome == 'logout' ? 'login' : 'terms');
      expect(state.localProtected, outcome == 'success');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      api.dispose();
    });
  }
  for (final mode in [
    'wrong-pin',
    'cancel',
    'exhausted',
    'network',
    'foreign-profile'
  ]) {
    testWidgets('unlock handles $mode without opening an unverified session',
        (tester) async {
      final api =
          _Api(profileId: mode == 'foreign-profile' ? 'other-owner' : 'owner');
      api.offline = mode == 'network';
      final protection = _Lock();
      protection.bioResult = false;
      if (mode == 'exhausted')
        protection.failure =
            ApiException('PIN_EXHAUSTED', 'Войдите снова', 401);
      await tester.pumpWidget(JobaApp(api: api));
      await tester.pumpAndSettle();
      final dynamic state = tester.state(find.byType(Marketplace));
      api.session = {
        'access_token': 'isolated-token',
        'user': {'id': 'owner'}
      };
      state.lock = protection;
      state.locked = true;
      state.go('unlock');
      await tester.pumpAndSettle();
      final Future<void> pending =
          state.unlockSession(pin: mode == 'cancel' ? null : '123456');
      if (['wrong-pin', 'network', 'foreign-profile'].contains(mode)) {
        final code = {
          'wrong-pin': 'PIN_INVALID',
          'network': 'OFFLINE',
          'foreign-profile': 'SESSION_SUPERSEDED'
        }[mode];
        final rejected = expectLater(pending,
            throwsA(isA<ApiException>().having((e) => e.code, 'code', code)));
        protection.gate.complete(mode != 'wrong-pin');
        await rejected;
      } else {
        await pending;
      }
      await tester.pumpAndSettle();
      expect(state.locked, mode != 'exhausted');
      expect(state.route, mode == 'exhausted' ? 'pin-limit' : 'unlock');
      expect(api.authenticated, mode != 'exhausted');
      expect(
          api.refreshes, ['network', 'foreign-profile'].contains(mode) ? 1 : 0);
      expect(state.unlockSubmitting, false);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      api.dispose();
    });
  }
  testWidgets(
      'unlock validates PIN before consuming an attempt and supports keyboard Done',
      (tester) async {
    final api = _Api(), protection = _Lock();
    await tester.pumpWidget(JobaApp(api: api));
    await tester.pumpAndSettle();
    final dynamic state = tester.state(find.byType(Marketplace));
    api.session = {
      'access_token': 'isolated-token',
      'user': {'id': 'owner'}
    };
    state.lock = protection;
    state.locked = true;
    state.go('unlock');
    await tester.pumpAndSettle();
    final field = find.byType(TextFormField);
    await tester.enterText(field, '123');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(protection.pins, 0);
    await tester.enterText(field, '123456');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(protection.pins, 1);
    protection.gate.complete(false);
    await tester.pumpAndSettle();
    expect(find.text('Неверный PIN'), findsOneWidget);
    expect(state.locked, true);
    expect(api.refreshes, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    api.dispose();
  });
  for (final expire in [false, true]) {
    testWidgets(
        'unlock shares one pending operation and stops after logout: $expire',
        (tester) async {
      final api = _Api();
      final lock = _Lock();
      await tester.pumpWidget(JobaApp(api: api));
      await tester.pumpAndSettle();
      final dynamic state = tester.state(find.byType(Marketplace));
      api.session = {
        'access_token': 'isolated-token',
        'refresh_token': 'isolated-refresh',
        'user': {'id': 'owner'}
      };
      state.lock = lock;
      state.locked = true;
      state.localProtected = true;
      state.go('unlock');
      await tester.pumpAndSettle();
      final pending = tester
          .widget<ActionForm>(find.byType(ActionForm))
          .submit({'pin': '123456'});
      await tester.pump();
      if (expire) {
        await api.forget();
        await tester.pumpAndSettle();
      } else {
        expect(
            tester
                .widget<OutlinedButton>(find.widgetWithText(
                    OutlinedButton, 'Разблокировать биометрией'))
                .onPressed,
            isNull);
        expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
            isNull);
      }
      lock.gate.complete(true);
      await pending;
      await tester.pumpAndSettle();
      expect(api.refreshes, expire ? 0 : 1);
      expect(lock.pins, 1);
      expect(lock.bios, 0);
      expect(state.route, expire ? 'login' : 'home');
      expect(state.locked, false);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      api.dispose();
    });
  }
}
