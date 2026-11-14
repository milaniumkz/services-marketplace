import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import '../lib/core/api.dart';
import '../lib/main.dart';
import '../lib/screens/marketplace.dart';

class Vault implements SessionVault {
  Future<String?> read() async => null;
  Future<void> write(String value) async {}
  Future<void> clear() async {}
}

const owner = {
  'id': 'owner',
  'country': 'KZ',
  'locale': 'ru',
  'roles': ['customer'],
  'active_role': 'customer',
  'phone': '+77000000638',
  'version': 1
};
http.Response ok(dynamic data) => http.Response(jsonEncode({'data': data}), 200,
    headers: {'content-type': 'application/json; charset=utf-8'});
Future<dynamic> open(WidgetTester t, JobaApi api, String route) async {
  await t.pumpWidget(JobaApp(api: api));
  await t.pumpAndSettle();
  api.session = {'access_token': 'first', 'user': owner};
  final dynamic state = t.state(find.byType(Marketplace));
  state.me = owner;
  state.go('security');
  state.go(route);
  await t.pumpAndSettle();
  return state;
}

Future<void> fillPhone(WidgetTester t) async {
  await t.enterText(find.byType(TextFormField).at(0), ' +77000000639 ');
  await t.enterText(find.byType(TextFormField).at(1), 'Current password!');
}

void main() {
  testWidgets(
      'phone response immediately updates confirmed profile and returns to security',
      (t) async {
    Json? sent;
    final api = JobaApi('https://isolated.example', vault: Vault(),
        transport: MockClient((r) async {
      if (r.url.path.endsWith('/me/security-policy'))
        return ok({'password_min': 6, 'password_max': 128});
      if (r.url.path.endsWith('/me/phone-change-requests')) {
        sent = jsonDecode(r.body);
        return ok({
          'phone': '+77000000639',
          'phone_status': 'unverified',
          'version': 2
        });
      }
      if (r.url.path.endsWith('/me')) return ok(owner);
      return ok({'items': []});
    }));
    addTearDown(api.dispose);
    final state = await open(t, api, 'phone');
    await fillPhone(t);
    await t.tap(find.widgetWithText(FilledButton, 'Сохранить'));
    await t.pumpAndSettle();
    expect(sent!['new_phone'], '+77000000639');
    expect(state.me['phone'], '+77000000639');
    expect(state.me['phone_status'], 'unverified');
    expect(state.me['version'], 2);
    expect(state.route, 'security');
    expect(api.authenticated, true);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets(
      'late phone response updates profile without leaving the new page',
      (t) async {
    final pending = Completer<http.Response>();
    final api = JobaApi('https://isolated.example',
        vault: Vault(),
        transport: MockClient(
            (r) async => r.url.path.endsWith('/me/phone-change-requests')
                ? pending.future
                : r.url.path.endsWith('/me')
                    ? ok(owner)
                    : ok({'items': []})));
    addTearDown(api.dispose);
    final state = await open(t, api, 'phone');
    await fillPhone(t);
    await t.tap(find.widgetWithText(FilledButton, 'Сохранить'));
    await t.pump();
    state.go('settings');
    pending.complete(ok(
        {'phone': '+77000000639', 'phone_status': 'unverified', 'version': 2}));
    await t.pumpAndSettle();
    expect(state.route, 'settings');
    expect(state.me['phone'], '+77000000639');
    expect(find.text('Номер изменён'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });
  for (final error in [false, true]) {
    testWidgets(
        'late phone ${error ? 'failure' : 'success'} cannot change another account or route',
        (t) async {
      final pending = Completer<http.Response>();
      final api = JobaApi('https://isolated.example',
          vault: Vault(),
          transport: MockClient(
              (r) async => r.url.path.endsWith('/me/phone-change-requests')
                  ? pending.future
                  : r.url.path.endsWith('/me')
                      ? ok(owner)
                      : ok({'items': []})));
      addTearDown(api.dispose);
      final state = await open(t, api, 'phone');
      await fillPhone(t);
      await t.tap(find.widgetWithText(FilledButton, 'Сохранить'));
      await t.pump();
      api.session = {
        'access_token': 'second',
        'user': {...owner, 'id': 'replacement'}
      };
      state.me = {...owner, 'id': 'replacement', 'phone': '+77000000640'};
      state.go('settings');
      pending.complete(error
          ? http.Response(
              jsonEncode({
                'error': {
                  'code': 'REAUTH_REQUIRED',
                  'message': 'Invalid password'
                }
              }),
              401,
              headers: {'content-type': 'application/json'})
          : ok({
              'phone': '+77000000639',
              'phone_status': 'unverified',
              'version': 2
            }));
      await t.pumpAndSettle();
      expect(state.route, 'settings');
      expect(state.me['phone'], '+77000000640');
      expect(find.text('Номер изменён'), findsNothing);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });
  }
  testWidgets(
      'password form is wired to root success and returns after confirmation',
      (t) async {
    var writes = 0;
    final api = JobaApi('https://isolated.example', vault: Vault(),
        transport: MockClient((r) async {
      if (r.url.path.endsWith('/me/security-policy'))
        return ok({'password_min': 6, 'password_max': 128});
      if (r.url.path.endsWith('/me/password/change')) {
        writes++;
        return ok({'changed': true});
      }
      if (r.url.path.endsWith('/me')) return ok(owner);
      return ok({'items': []});
    }));
    addTearDown(api.dispose);
    final state = await open(t, api, 'password');
    await t.tap(find.byTooltip('Назад'));
    await t.pumpAndSettle();
    expect(state.route, 'security');
    expect(writes, 0);
    state.go('password');
    await t.pumpAndSettle();
    for (var i = 0; i < 3; i++) {
      await t.enterText(find.byType(TextFormField).at(i),
          i == 0 ? 'Current password!' : 'Updated valid password!');
    }
    await t.tap(find.widgetWithText(FilledButton, 'Сохранить'));
    await t.pumpAndSettle();
    expect(writes, 1);
    expect(state.route, 'security');
    expect(api.authenticated, true);
    await t.pumpWidget(const SizedBox());
  });
}
