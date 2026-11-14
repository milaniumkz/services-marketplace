import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:services_marketplace/core/api.dart';
import 'package:services_marketplace/main.dart';
import 'package:services_marketplace/screens/marketplace.dart';

class _Vault implements SessionVault {
  String? value;
  Future<String?> read() async => value;
  Future<void> write(String v) async {
    value = v;
  }

  Future<void> clear() async {
    value = null;
  }
}

void main() {
  testWidgets(
      'logout screen preserves session on cancel or server failure and clears it only after revocation',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final vault = _Vault();
    var reject = true, logoutCalls = 0;
    final api = JobaApi('https://isolated.example', vault: vault,
        transport: MockClient((r) async {
      if (r.url.path.endsWith('/auth/logout')) {
        logoutCalls++;
        if (reject)
          return http.Response('{"error":{"code":"SERVER_ERROR"}}', 500);
      }
      return http.Response(
          jsonEncode({
            'data': {'items': []},
            'meta': {}
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    }));
    await tester.pumpWidget(JobaApp(api: api));
    await tester.pumpAndSettle();
    final dynamic state = tester.state(find.byType(Marketplace));
    api.session = {
      'access_token': 'isolated-token',
      'user': {'id': 'isolated-owner', 'country': 'KZ'}
    };
    vault.value = 'isolated-session';
    state.go('settings');
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Выйти из аккаунта'), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Выйти из аккаунта'));
    await tester.pumpAndSettle();
    expect(state.route, 'logout-confirm');
    await tester.tap(find.text('Остаться'));
    await tester.pumpAndSettle();
    expect(state.route, 'settings');
    expect(logoutCalls, 0);
    expect(api.authenticated, true);
    state.confirmLogout();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Выйти'));
    await tester.pumpAndSettle();
    expect(state.route, 'logout-confirm');
    expect(api.authenticated, true);
    expect(vault.value, 'isolated-session');
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('Понятно'));
    await tester.pumpAndSettle();
    reject = false;
    await tester.tap(find.text('Выйти'));
    await tester.pumpAndSettle();
    expect(logoutCalls, 2);
    expect(api.authenticated, false);
    expect(vault.value, isNull);
    expect(api.sessionExpired, false);
    expect(state.route, 'login');
    expect(state.history, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    api.dispose();
  });
}
