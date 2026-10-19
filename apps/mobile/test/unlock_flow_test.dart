import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:services_marketplace/core/api.dart';
import 'package:services_marketplace/core/local_lock.dart';
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
  Future<int?> pinLength() async => 6;
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
  for (final choice in ['password', 'biometry']) {
    testWidgets('keypad $choice action uses the actual account route',
        (tester) async {
      final api = _Api(), protection = _Lock();
      protection.bioResult = false;
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
      final key = find.byKey(ValueKey(
          choice == 'password' ? 'unlock-password' : 'unlock-key-biometry'));
      await tester.scrollUntilVisible(key, 150,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      await tester.tap(key);
      await tester.pumpAndSettle();
      expect(state.route, choice == 'password' ? 'login' : 'unlock');
      expect(api.authenticated, choice != 'password');
      expect(api.refreshes, 0);
      expect(protection.bios, choice == 'biometry' ? 1 : 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      api.dispose();
    });
  }
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
      'unlock keypad waits for six digits, submits once and retains the lock on rejection',
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
    for (final digit in ['1', '2', '3']) {
      await tester.tap(find.byKey(ValueKey('unlock-key-$digit')));
      await tester.pump();
    }
    expect(protection.pins, 0);
    for (final digit in ['4', '5', '6']) {
      await tester.tap(find.byKey(ValueKey('unlock-key-$digit')));
      await tester.pump();
    }
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
      final Future<void> pending = state.unlockSession(pin: '123456');
      await tester.pump();
      if (expire) {
        await api.forget();
        await tester.pumpAndSettle();
      } else {
        expect(
            tester
                .widget<InkWell>(
                    find.byKey(const ValueKey('unlock-key-biometry')))
                .onTap,
            isNull);
        expect(
            tester
                .widget<InkWell>(find.byKey(const ValueKey('unlock-key-1')))
                .onTap,
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
