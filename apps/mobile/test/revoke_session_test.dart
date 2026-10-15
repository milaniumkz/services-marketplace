import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:services_marketplace/core/api.dart';
import 'package:services_marketplace/core/theme.dart';
import 'package:services_marketplace/screens/revoke_session.dart';

class _Vault implements SessionVault {
  Future<String?> read() async => null;
  Future<void> write(String value) async {}
  Future<void> clear() async {}
}

void main() {
  testWidgets(
      'session confirmation cancels without revoking and preserves a failed request until actual success',
      (tester) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var attempts = 0, cancelled = 0, done = false;
    final api = JobaApi('https://isolated.example', vault: _Vault(),
        transport: MockClient((r) async {
      if (r.method == 'DELETE') {
        attempts++;
        if (attempts == 1)
          return http.Response(
              jsonEncode({
                'error': {
                  'code': 'STATE_CONFLICT',
                  'message': 'Повторите запрос'
                }
              }),
              409,
              headers: {'content-type': 'application/json; charset=utf-8'});
        return http.Response(
            jsonEncode({
              'data': {'revoked': true}
            }),
            200);
      }
      return http.Response(
          jsonEncode({
            'data': {
              'items': [
                {'family': 'remote', 'current': false}
              ]
            }
          }),
          200);
    }));
    api.session = {
      'access_token': 'isolated-token',
      'user': {'id': 'owner', 'country': 'KZ'}
    };
    await tester.pumpWidget(MaterialApp(
        theme: jobaTheme(),
        home: Scaffold(
            body: RevokeSession(
                api: api,
                family: 'remote',
                onCancel: () => cancelled++,
                onRevoked: (current) {
                  expect(current, false);
                  done = true;
                }))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Отмена'));
    expect(cancelled, 1);
    expect(attempts, 0);
    await tester.tap(find.text('Завершить сеанс'));
    await tester.pumpAndSettle();
    expect(done, false);
    expect(find.text('Отмена'), findsOneWidget);
    await tester.tap(find.text('Завершить сеанс'));
    await tester.pumpAndSettle();
    expect(done, true);
    expect(attempts, 2);
    expect(api.authenticated, true);
    expect(tester.takeException(), isNull);
  });
}
