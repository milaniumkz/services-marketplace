import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:services_marketplace/core/api.dart';
import 'package:services_marketplace/core/local_lock.dart';
import 'package:services_marketplace/main.dart';
import 'package:services_marketplace/screens/marketplace.dart';
import 'package:services_marketplace/screens/device_setup.dart';

class _Vault implements SessionVault {
  String? value;
  bool failWrites = false;
  Future<String?> read() async => value;
  Future<void> write(String v) async {
    if (failWrites) throw StateError("Isolated vault failure");
    value = v;
  }

  Future<void> clear() async {
    value = null;
  }
}

class _Lock extends LocalLock {
  final gate = Completer<void>();
  int clears = 0;
  _Lock() : super('isolated-pin-owner');
  Future<void> configure(String pin) => gate.future;
  Future<void> clear() async {
    clears++;
  }

  Future<void> enableBiometry() async =>
      throw ApiException("BIOMETRY_UNAVAILABLE", "Биометрия недоступна");
}

void main() {
  testWidgets('accepted current documents skip consent and background keeps the session', (tester) async {
    final api=JobaApi('https://isolated.example',vault:_Vault(),transport:MockClient((r) async {
      final Object data=r.url.path.endsWith('/legal/documents') ? {'items':[
        {'id':'terms','type':'terms','hash':'terms-hash'},
        {'id':'privacy','type':'privacy','hash':'privacy-hash'}
      ]} : r.url.path.endsWith('/me/consents') ? {'items':[
        {'document_id':'terms','document_hash':'terms-hash','accepted':true,'sequence':1},
        {'document_id':'privacy','document_hash':'privacy-hash','accepted':true,'sequence':2}
      ]} : r.url.path.endsWith('/me') ? {'id':'owner','display_name':'Тест','country':'KZ','locale':'ru','roles':['customer']} : {'items':[]};
      return http.Response(jsonEncode({'data':data}),200,headers:{'content-type':'application/json; charset=utf-8'});
    }));
    await tester.pumpWidget(JobaApp(api:api));await tester.pumpAndSettle();
    api.session={'access_token':'isolated-token','user':{'id':'owner'}};
    final dynamic state=tester.state(find.byType(Marketplace));
    state.me={'id':'owner','display_name':'Тест','country':'KZ','locale':'ru'};
    state.go('lock-setup');await tester.pumpAndSettle();
    await state.completeLocalSetup(passwordOnly:true);await tester.pumpAndSettle();
    expect(state.route,'home');expect(api.authenticated,true);
    state.pausedAt=DateTime.now().subtract(const Duration(minutes:2));
    state.didChangeAppLifecycleState(AppLifecycleState.resumed);await tester.pumpAndSettle();
    expect(api.authenticated,true);expect(state.route,'home');
    await tester.pumpWidget(const SizedBox());api.dispose();
  });
  for (final mode in ['password', 'biometry-failure', 'vault-failure']) {
    testWidgets(
        'local setup handles $mode without false persistence or navigation',
        (tester) async {
      final vault = _Vault();
      final api = JobaApi('https://isolated.example',
          vault: vault,
          transport: MockClient(
              (r) async => http.Response('{"data":{"items":[]}}', 200)));
      await tester.pumpWidget(JobaApp(api: api));
      await tester.pumpAndSettle();
      api.session = {
        'access_token': 'isolated-token',
        'user': {'id': 'owner'}
      };
      await api.setPersistence(false);
      vault.failWrites = mode == 'vault-failure';
      final dynamic state = tester.state(find.byType(Marketplace));
      final protection = _Lock();
      state.me = {'id': 'owner', 'country': 'KZ', 'locale': 'ru'};
      state.lock = protection;
      state.go('pin-setup');
      await tester.pumpAndSettle();
      state.back();
      await tester.pumpAndSettle();
      expect(state.route, 'pin-setup');
      final form = tester.widget<PinSetup>(find.byType(PinSetup));
      if (mode == 'password') {
        await form.onPassword();
      } else {
        final pending = form.onSave('123456', mode == 'biometry-failure');
        if (mode == 'vault-failure') {
          final failed = expectLater(pending, throwsStateError);
          protection.gate.complete();
          await failed;
        } else {
          protection.gate.complete();
          await pending;
        }
      }
      await tester.pumpAndSettle();
      expect(state.route, mode == 'vault-failure' ? 'pin-setup' : 'terms');
      expect(state.localProtected, mode == 'biometry-failure');
      expect(api.persistSession, mode == 'biometry-failure');
      expect(vault.value != null, mode == 'biometry-failure');
      expect(state.localSetupSubmitting, false);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      api.dispose();
    });
  }
  for (final expire in [false, true]) {
    testWidgets(
        'PIN save blocks navigation and ignores expired session: $expire',
        (tester) async {
      final vault = _Vault();
      final api = JobaApi('https://isolated.example',
          vault: vault,
          transport: MockClient(
              (r) async => http.Response('{"data":{"items":[]}}', 200)));
      await tester.pumpWidget(JobaApp(api: api));
      await tester.pumpAndSettle();
      api.session = {
        'access_token': 'isolated-token',
        'user': {'id': 'owner'}
      };
      await api.setPersistence(false);
      final dynamic state = tester.state(find.byType(Marketplace));
      final protection = _Lock();
      state.me = {'id': 'owner', 'country': 'KZ', 'locale': 'ru'};
      state.lock = protection;
      state.go('lock-setup');
      await tester.pumpAndSettle();
      final pending = tester
          .widget<PinSetup>(find.byType(PinSetup))
          .onSave('123456', false);
      await tester.pump();
      if (!expire) {
        state.back();
        expect(state.route, 'lock-setup');
        state.go('home');
        expect(state.route, 'lock-setup');
      } else {
        await api.forget();
        await tester.pumpAndSettle();
        expect(state.route, 'login');
      }
      protection.gate.complete();
      await pending;
      await tester.pumpAndSettle();
      expect(state.route, expire ? 'login' : 'terms');
      expect(state.localProtected, !expire);
      if (expire)
        expect(vault.value, isNull);
      else
        expect(vault.value, isNotNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      api.dispose();
    });
  }
}
