import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import '../lib/core/api.dart';
import '../lib/core/theme.dart';
import '../lib/screens/notification_settings.dart';

class Vault implements SessionVault {
  Future<String?> read() async => null;
  Future<void> write(String value) async {}
  Future<void> clear() async {}
}

http.Response ok(dynamic data) => http.Response(jsonEncode({'data': data}), 200,
    headers: {'content-type': 'application/json; charset=utf-8'});
Future<void> mount(WidgetTester t, JobaApi api, VoidCallback saved,
    {double scale = 1}) async {
  await t.pumpWidget(MaterialApp(
      theme: jobaTheme(),
      home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Scaffold(
              body: NotificationSettingsContent(api: api, onSaved: saved)))));
  await t.pumpAndSettle();
}

JobaApi client(Future<http.Response> Function(http.Request) send) =>
    JobaApi('https://isolated.example',
        vault: Vault(), transport: MockClient(send))
      ..session = {
        'access_token': 'first',
        'user': {'id': 'owner'}
      };
void main() {
  testWidgets('load retries and uses the preference snapshot version',
      (t) async {
    var loads = 0;
    Json? written;
    final api = client((r) async {
      if (r.method == 'PATCH') {
        written = jsonDecode(r.body);
        return ok({});
      }
      if (r.url.path.endsWith('/me'))
        return ok({'version': 1, 'country': 'KZ'});
      if (++loads == 1)
        return http.Response(
            jsonEncode({
              'error': {'code': 'UNAVAILABLE', 'message': 'Unavailable'}
            }),
            503,
            headers: {'content-type': 'application/json'});
      return ok(
          {'version': 9, 'chat': true, 'service': true, 'marketing': false});
    });
    addTearDown(api.dispose);
    await mount(t, api, () {});
    expect(find.text('Повторить'), findsOneWidget);
    await t.tap(find.text('Повторить'));
    await t.pumpAndSettle();
    await t.tap(find.text('Сохранить'));
    await t.pumpAndSettle();
    expect(loads, 2);
    expect(written!['expected_version'], 9);
    expect((written!['preferences'] as Map).containsKey('version'), false);
  });
  testWidgets('conflict reload can fail and retry without saving stale values',
      (t) async {
    var loads = 0, writes = 0, saved = 0;
    Json? written;
    final api = client((r) async {
      if (r.method == 'PATCH') {
        writes++;
        written = jsonDecode(r.body);
        return writes == 1
            ? http.Response(
                jsonEncode({
                  'error': {
                    'code': 'STATE_CONFLICT',
                    'message': 'Данные изменились. Обновите экран.'
                  }
                }),
                409,
                headers: {'content-type': 'application/json'})
            : ok({});
      }
      if (r.url.path.endsWith('/me')) return ok({'version': 1});
      loads++;
      if (loads == 2)
        return http.Response(
            jsonEncode({
              'error': {'code': 'UNAVAILABLE', 'message': 'Unavailable'}
            }),
            503,
            headers: {'content-type': 'application/json'});
      return ok({
        'version': loads == 1 ? 2 : 3,
        'chat': true,
        'service': true,
        'orders': loads == 1,
        'marketing': false
      });
    });
    addTearDown(api.dispose);
    await mount(t, api, () => saved++);
    await t.tap(find.text('Сохранить'));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.text('Обновить настройки'), 200,
        scrollable: find.byType(Scrollable).first);
    await t.tap(find.text('Обновить настройки'));
    await t.pumpAndSettle();
    expect(writes, 1);
    expect(t.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    await t.scrollUntilVisible(find.text('Обновить настройки'), 200,
        scrollable: find.byType(Scrollable).first);
    await t.tap(find.text('Обновить настройки'));
    await t.pumpAndSettle();
    expect(
        t
            .widgetList<NotificationPreferenceToggle>(
                find.byType(NotificationPreferenceToggle))
            .elementAt(1)
            .value,
        false);
    await t.tap(find.text('Сохранить'));
    await t.pumpAndSettle();
    expect(saved, 1);
    expect(writes, 2);
    expect(written!['expected_version'], 3);
    expect(written!['preferences']['orders'], false);
  });
  testWidgets('four independent switches save API state and retain quiet hours',
      (t) async {
    Json? body;
    var saved = 0;
    final api = client((r) async {
      if (r.method == 'PATCH') {
        body = jsonDecode(r.body);
        return ok(body!['preferences']);
      }
      return ok(r.url.path.endsWith('/me')
          ? {'version': 7, 'country': 'KG'}
          : {
              'chat': true,
              'service': false,
              'orders': true,
              'support': false,
              'marketing': false,
              'quiet_hours': {
                'start': '21:00',
                'end': '07:00',
                'time_zone': 'Asia/Bishkek'
              }
            });
    });
    addTearDown(api.dispose);
    await mount(t, api, () => saved++);
    expect(
        t
            .widgetList<NotificationPreferenceToggle>(
                find.byType(NotificationPreferenceToggle))
            .take(4)
            .map((x) => x.value),
        [true, true, false, false]);
    await t.tap(find.text('Сообщения'));
    await t.tap(find.text('Заказы'));
    await t.tap(find.text('Новости и предложения'));
    await t.tap(find.text('Поддержка'));
    await t.pumpAndSettle();
    await t.tap(find.text('Сохранить'));
    await t.pumpAndSettle();
    expect(saved, 1);
    expect(body!['expected_version'], 7);
    expect(body!['preferences']['support'], true);
    expect(body!['preferences']['orders'], false);
    expect(body!['preferences']['chat'], false);
    expect(body!['preferences']['marketing'], true);
    expect(body!['preferences']['service'], false);
    expect(body!['preferences']['quiet_hours'],
        {'start': '21:00', 'end': '07:00', 'time_zone': 'Asia/Bishkek'});
  });
  testWidgets(
      'rejection retains draft, disables duplicate submit, and permits retry',
      (t) async {
    var writes = 0, saved = 0;
    var pending = Completer<http.Response>();
    final api = client((r) async {
      if (r.method == 'PATCH') {
        writes++;
        return pending.future;
      }
      return ok(r.url.path.endsWith('/me')
          ? {'version': 1}
          : {'chat': true, 'service': true, 'marketing': false});
    });
    addTearDown(api.dispose);
    await mount(t, api, () => saved++);
    await t.tap(find.text('Заказы'));
    await t.pump();
    await t.tap(find.text('Сохранить'));
    await t.pump();
    expect(t.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    pending.complete(http.Response(
        jsonEncode({
          'error': {
            'code': 'VALIDATION_ERROR',
            'message': 'Проверьте настройки'
          }
        }),
        400,
        headers: {'content-type': 'application/json'}));
    await t.pumpAndSettle();
    expect(saved, 0);
    expect(writes, 1);
    expect(
        t
            .widgetList<NotificationPreferenceToggle>(
                find.byType(NotificationPreferenceToggle))
            .elementAt(1)
            .value,
        false);
    pending = Completer<http.Response>();
    await t.tap(find.text('Сохранить'));
    await t.pump();
    pending.complete(ok({}));
    await t.pumpAndSettle();
    expect(writes, 2);
    expect(saved, 1);
  });
  testWidgets('late success cannot navigate a replacement account', (t) async {
    final pending = Completer<http.Response>();
    var saved = 0;
    final api = client((r) async => r.method == 'PATCH'
        ? pending.future
        : ok(r.url.path.endsWith('/me')
            ? {'version': 1}
            : {'chat': true, 'service': true, 'marketing': false}));
    addTearDown(api.dispose);
    await mount(t, api, () => saved++);
    await t.tap(find.text('Сохранить'));
    await t.pump();
    api.session = {
      'access_token': 'second',
      'user': {'id': 'other'}
    };
    pending.complete(ok({}));
    await t.pumpAndSettle();
    expect(saved, 0);
    expect(t.takeException(), isNull);
  });
  testWidgets('quiet hours validate before saving and preserve the draft',
      (t) async {
    var writes = 0;
    final api = client((r) async {
      if (r.method == 'PATCH') {
        writes++;
        return ok({});
      }
      return ok(r.url.path.endsWith('/me')
          ? {'version': 1, 'country': 'KZ'}
          : {'chat': true, 'service': true, 'marketing': false});
    });
    addTearDown(api.dispose);
    await mount(t, api, () {});
    await t.ensureVisible(find.text('Часы тишины'));
    await t.tap(find.text('Часы тишины'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Включены'));
    await t.pumpAndSettle();
    await t.tap(find.text('Включены'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.byType(TextField).first);
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).first, '24:00');
    await t.tap(find.text('Сохранить'));
    await t.pumpAndSettle();
    expect(writes, 0);
    expect(t.widget<TextField>(find.byType(TextField).first).controller!.text,
        '24:00');
    await t.enterText(find.byType(TextField).first, '23:00');
    await t.tap(find.text('Сохранить'));
    await t.pumpAndSettle();
    expect(writes, 1);
  });
  testWidgets('narrow enlarged text scrolls without overflow', (t) async {
    t.view.physicalSize = const Size(320, 740);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final api = client((r) async => ok(r.url.path.endsWith('/me')
        ? {'version': 1}
        : {'chat': true, 'service': true, 'marketing': false}));
    addTearDown(api.dispose);
    await mount(t, api, () {}, scale: 2);
    expect(t.takeException(), isNull);
    await t.scrollUntilVisible(find.text('Часы тишины'), 250,
        scrollable: find.byType(Scrollable).first);
    expect(t.takeException(), isNull);
  });
}
