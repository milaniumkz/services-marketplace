import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import '../lib/core/api.dart';
import '../lib/core/theme.dart';
import '../lib/main.dart';
import '../lib/screens/marketplace.dart';
import '../lib/screens/revoke_session.dart';
import '../lib/screens/session_list.dart';

class Vault implements SessionVault {
  Future<String?> read() async => null;
  Future<void> write(String value) async {}
  Future<void> clear() async {}
}

http.Response ok(dynamic data) => http.Response(jsonEncode({'data': data}), 200,
    headers: {'content-type': 'application/json; charset=utf-8'});
const owner = {
  'id': 'owner',
  'country': 'KZ',
  'locale': 'ru',
  'roles': ['customer'],
  'active_role': 'customer'
};
void main() {
  testWidgets(
      'session cards identify current device, route remote revoke and preserve current on bulk logout',
      (t) async {
    var writes = 0;
    Json? body;
    final api = JobaApi('https://isolated.example', vault: Vault(),
        transport: MockClient((r) async {
      if (r.url.path.endsWith('/auth/logout-others')) {
        writes++;
        body = jsonDecode(r.body);
        return ok({'revoked': true, 'current_session_preserved': true});
      }
      if (r.url.path.endsWith('/me/sessions'))
        return ok({
          'items': [
            {'family': 'remote', 'current': false},
            {'family': 'local', 'current': true}
          ]
        });
      if (r.url.path.endsWith('/me')) return ok(owner);
      return ok({'items': []});
    }));
    addTearDown(api.dispose);
    await t.pumpWidget(JobaApp(api: api));
    await t.pumpAndSettle();
    api.session = {'access_token': 'first', 'user': owner};
    final dynamic state = t.state(find.byType(Marketplace));
    state.me = owner;
    state.go('sessions');
    await t.pumpAndSettle();
    expect(find.text('Это устройство'), findsOneWidget);
    expect(find.text('Сведения об устройстве недоступны'), findsNWidgets(2));
    await t.tap(find.text('Завершить сеанс'));
    await t.pumpAndSettle();
    expect(state.route, 'revoke-session');
    expect(state.objectId, 'remote');
    await t.tap(find.text('Отмена'));
    await t.pumpAndSettle();
    expect(state.route, 'sessions');
    await t.ensureVisible(find.text('Выйти на других устройствах'));
    await t.pumpAndSettle();
    await t.tap(find.text('Выйти на других устройствах'));
    await t.pumpAndSettle();
    expect(state.route, 'logout-others');
    expect(writes, 0);
    await t.enterText(find.byType(TextFormField), 'Current password!');
    await t
        .tap(find.widgetWithText(FilledButton, 'Выйти на других устройствах'));
    await t.pumpAndSettle();
    expect(writes, 1);
    expect(body!['current_password'], 'Current password!');
    expect(api.authenticated, true);
    expect(state.route, 'sessions');
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('late revoke cannot log out a replacement account', (t) async {
    final pending = Completer<http.Response>();
    var revoked = 0;
    final api = JobaApi('https://isolated.example',
        vault: Vault(),
        transport: MockClient((r) async => r.method == 'DELETE'
            ? pending.future
            : ok({
                'items': [
                  {'family': 'local', 'current': true}
                ]
              })))
      ..session = {'access_token': 'first', 'user': owner};
    addTearDown(api.dispose);
    await t.pumpWidget(MaterialApp(
        theme: jobaTheme(),
        home: Scaffold(
            body: RevokeSession(
                api: api,
                family: 'local',
                onCancel: () {},
                onRevoked: (_) => revoked++))));
    await t.pumpAndSettle();
    await t.tap(find.text('Завершить сеанс'));
    await t.pump();
    api.session = {
      'access_token': 'second',
      'user': {'id': 'replacement'}
    };
    pending.complete(ok({'revoked': true}));
    await t.pump();
    await t.pump(const Duration(milliseconds: 200));
    expect(revoked, 0);
    expect(api.authenticated, true);
    await t.pumpWidget(const SizedBox());
    expect(t.takeException(), isNull);
  });
  testWidgets(
      'only current session offers no bulk action and large text can scroll',
      (t) async {
    t.view.physicalSize = const Size(320, 740);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(MaterialApp(
        theme: jobaTheme(),
        home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
                body: SessionListContent(sessions: const [
              {'family': 'current', 'current': true}
            ], onRevoke: (_) {}, onRevokeOthers: () {})))));
    await t.pumpAndSettle();
    expect(find.text('Выйти на других устройствах'), findsNothing);
    expect(find.text('Завершить сеанс'), findsNothing);
    expect(t.takeException(), isNull);
  });
}
