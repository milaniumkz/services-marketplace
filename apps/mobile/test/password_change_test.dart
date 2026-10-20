import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import '../lib/core/api.dart';
import '../lib/core/theme.dart';
import '../lib/screens/password_change.dart';

class Vault implements SessionVault {
  Future<String?> read() async => null;
  Future<void> write(String value) async {}
  Future<void> clear() async {}
}

http.Response ok() => http.Response(
    jsonEncode({
      'data': {'changed': true}
    }),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'});
JobaApi client(Future<http.Response> Function(http.Request) send) =>
    JobaApi('https://isolated.example',
        vault: Vault(),
        transport:
            MockClient((r) async => r.url.path.endsWith('/me/security-policy')
                ? http.Response(
                    jsonEncode({
                      'data': {'password_min': 6, 'password_max': 128}
                    }),
                    200,
                    headers: {'content-type': 'application/json'})
                : send(r)))
      ..session = {
        'access_token': 'first',
        'user': {'id': 'owner'}
      };
Future<void> mount(WidgetTester t, JobaApi api, VoidCallback saved,
    {double scale = 1}) async {
  await t.pumpWidget(MaterialApp(
      theme: jobaTheme(),
      home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Scaffold(
              body: PasswordChangeContent(api: api, onChanged: saved)))));
  await t.pumpAndSettle();
}

Future<void> fill(WidgetTester t,
    {String password = 'Updated valid password!', String? repeat}) async {
  final fields = find.byType(TextFormField);
  await t.enterText(fields.at(0), 'Current password!');
  await t.enterText(fields.at(1), password);
  await t.enterText(fields.at(2), repeat ?? password);
}

void main() {
  testWidgets('policy failure retries and enforces the configured minimum',
      (t) async {
    var loads = 0, writes = 0;
    final api = JobaApi('https://isolated.example', vault: Vault(),
        transport: MockClient((r) async {
      if (r.url.path.endsWith('/me/security-policy')) {
        if (++loads == 1)
          return http.Response(
              jsonEncode({
                'error': {'code': 'UNAVAILABLE', 'message': 'Unavailable'}
              }),
              503,
              headers: {'content-type': 'application/json'});
        return http.Response(
            jsonEncode({
              'data': {'password_min': 20, 'password_max': 128}
            }),
            200,
            headers: {'content-type': 'application/json'});
      }
      writes++;
      return ok();
    }))
      ..session = {
        'access_token': 'first',
        'user': {'id': 'owner'}
      };
    addTearDown(api.dispose);
    await mount(t, api, () {});
    expect(find.byType(TextFormField), findsNothing);
    await t.tap(find.text('Повторить'));
    await t.pumpAndSettle();
    expect(loads, 2);
    expect(find.text('Не менее 20 символов'), findsOneWidget);
    await fill(t, password: 'x' * 19);
    await t.tap(find.text('Сохранить'));
    await t.pumpAndSettle();
    expect(writes, 0);
    expect(find.text('Пароль должен содержать от 20 до 128 символов'),
        findsOneWidget);
    await fill(t, password: 'x' * 20);
    await t.tap(find.text('Сохранить'));
    await t.pumpAndSettle();
    expect(writes, 1);
  });
  testWidgets('invalid policy cannot enable a credential form', (t) async {
    final api = JobaApi('https://isolated.example',
        vault: Vault(),
        transport: MockClient((r) async => http.Response(
            jsonEncode({
              'data': {'password_min': 2, 'password_max': 128}
            }),
            200,
            headers: {'content-type': 'application/json'})))
      ..session = {
        'access_token': 'first',
        'user': {'id': 'owner'}
      };
    addTearDown(api.dispose);
    await mount(t, api, () {});
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('Повторить'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets(
      'length and repeat validation prevent requests and each eye toggles independently',
      (t) async {
    var writes = 0;
    final api = client((r) async {
      writes++;
      return ok();
    });
    addTearDown(api.dispose);
    await mount(t, api, () {});
    await fill(t, password: 'short');
    await t.tap(find.text('Сохранить'));
    await t.pumpAndSettle();
    expect(writes, 0);
    expect(find.text('Пароль должен содержать от 6 до 128 символов'),
        findsOneWidget);
    await fill(t, repeat: 'Different valid password!');
    await t.tap(find.text('Сохранить'));
    await t.pumpAndSettle();
    expect(writes, 0);
    expect(find.text('Пароли не совпадают'), findsOneWidget);
    await fill(t);
    for (var i = 0; i < 3; i++) {
      await t.ensureVisible(find.byTooltip('Показать пароль').first);
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Показать пароль').first);
      await t.pump();
      expect(t.widgetList<TextFormField>(find.byType(TextFormField)).length, 3);
    }
    expect(find.byTooltip('Скрыть пароль'), findsNWidgets(3));
    await t.tap(find.text('Сохранить'));
    await t.pumpAndSettle();
    expect(writes, 1);
  });
  testWidgets(
      'failure retains inputs and retry sends only credentials with duplicate submit disabled',
      (t) async {
    var pending = Completer<http.Response>();
    var writes = 0, saved = 0;
    Json? body;
    final api = client((r) async {
      writes++;
      body = jsonDecode(r.body);
      return pending.future;
    });
    addTearDown(api.dispose);
    await mount(t, api, () => saved++);
    await fill(t);
    await t.tap(find.text('Сохранить'));
    await t.pump();
    expect(t.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    pending.complete(http.Response(
        jsonEncode({
          'error': {
            'code': 'REAUTH_REQUIRED',
            'message': 'Подтвердите текущий пароль'
          }
        }),
        401,
        headers: {'content-type': 'application/json'}));
    await t.pumpAndSettle();
    expect(saved, 0);
    expect(
        t
            .widget<TextFormField>(find.byType(TextFormField).at(1))
            .controller!
            .text,
        'Updated valid password!');
    pending = Completer<http.Response>();
    await t.tap(find.text('Сохранить'));
    await t.pump();
    pending.complete(ok());
    await t.pumpAndSettle();
    expect(saved, 1);
    expect(writes, 2);
    expect(body, {
      'current_password': 'Current password!',
      'new_password': 'Updated valid password!'
    });
  });
  testWidgets('late password success cannot navigate a replacement account',
      (t) async {
    final pending = Completer<http.Response>();
    var saved = 0;
    final api = client((r) => pending.future);
    addTearDown(api.dispose);
    await mount(t, api, () => saved++);
    await fill(t);
    await t.tap(find.text('Сохранить'));
    await t.pump();
    api.session = {
      'access_token': 'second',
      'user': {'id': 'replacement'}
    };
    pending.complete(ok());
    await t.pumpAndSettle();
    expect(saved, 0);
    expect(t.takeException(), isNull);
  });
  testWidgets('small screen and large text keep inputs scrollable', (t) async {
    t.view.physicalSize = const Size(320, 740);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final api = client((r) async => ok());
    addTearDown(api.dispose);
    await mount(t, api, () {}, scale: 2);
    await t.scrollUntilVisible(find.text('Повторите новый пароль'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(t.takeException(), isNull);
  });
}
