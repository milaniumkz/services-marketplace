import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:services_marketplace/core/api.dart';
import 'package:services_marketplace/core/theme.dart';
import 'package:services_marketplace/screens/profile_editor.dart';

class _Vault implements SessionVault {
  Future<String?> read() async => null;
  Future<void> write(String v) async {}
  Future<void> clear() async {}
}

final initial = <String, dynamic>{
  'id': 'owner',
  'version': 1,
  'display_name': 'Марина',
  'country': 'KZ',
  'locale': 'ru',
  'roles': ['customer'],
  'active_role': 'customer'
};
http.Response ok(Object data) => http.Response(jsonEncode({'data': data}), 200,
    headers: {'content-type': 'application/json; charset=utf-8'});
Widget host(Widget child) => MaterialApp(
    locale: const Locale('ru'),
    supportedLocales: const [Locale('ru')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: jobaTheme(),
    home: Scaffold(backgroundColor: canvas, body: child));
JobaApi client(Future<http.Response> Function(http.Request) send) =>
    JobaApi('https://isolated.example',
        vault: _Vault(), transport: MockClient(send))
      ..session = {
        'access_token': 'isolated-token',
        'user': {'id': 'owner'}
      };
void main() {
  testWidgets(
      'a selected avatar survives a failed attachment and is included in the explicit profile retry',
      (tester) async {
    var picks = 0, writes = 0;
    Json? saved;
    final api = client((r) async {
      writes++;
      final body = jsonDecode(r.body) as Json;
      expect(body['avatar_id'], 'isolated-upload');
      if (writes == 1)
        return http.Response(
            '{"error":{"code":"SCANNER_UNAVAILABLE","message":"Scanner unavailable"}}',
            503);
      expect(body['display_name'], 'Марина');
      return ok({...initial, ...body, 'version': 2});
    });
    await tester.pumpWidget(host(ProfileEditor(
        api: api,
        initial: initial,
        onboarding: true,
        pickAvatar: () async {
          picks++;
          return {'id': 'isolated-upload'};
        },
        onSaved: (v) => saved = v)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Добавить фото'));
    await tester.pumpAndSettle();
    expect(writes, 1);
    expect(saved, isNull);
    expect(find.text('Повторить'), findsOneWidget);
    await tester.tap(find.text('Сохранить профиль'));
    await tester.pumpAndSettle();
    expect(writes, 2);
    expect(picks, 1);
    expect(saved?['avatar_id'], 'isolated-upload');
    await tester.pumpWidget(const SizedBox());
    api.dispose();
  });
  testWidgets(
      'profile editing selects city and language names before an explicit save',
      (tester) async {
    final bodies = <Json>[];
    Json? saved;
    final api = client((r) async {
      if (r.method == 'GET')
        return ok({
          'items': [
            {'id': 'almaty', 'name': 'Алматы'}
          ]
        });
      final body = jsonDecode(r.body) as Json;
      bodies.add(body);
      return ok({...initial, ...body, 'version': 2});
    });
    await tester.pumpWidget(host(ProfileEditor(
        api: api,
        initial: {...initial, 'phone': '+77000000001'},
        onboarding: false,
        pickAvatar: () async => null,
        onSaved: (v) => saved = v)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Изменить фото'));
    await tester.pumpAndSettle();
    expect(bodies, isEmpty);
    await tester.enterText(find.byType(TextFormField), 'x' * 61);
    await tester.tap(find.text('Сохранить профиль'));
    await tester.pumpAndSettle();
    expect(bodies, isEmpty);
    await tester.enterText(find.byType(TextFormField), 'Марина');
    await tester.tap(find.byKey(const ValueKey('profile-city-selector')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Алматы');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Алматы'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Выбрать Алматы'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('profile-languages-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Қазақша'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Выбрать'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сохранить профиль'));
    await tester.pumpAndSettle();
    expect(bodies.single['city'], 'Алматы');
    expect(bodies.single['languages'], ['ru', 'kk']);
    expect(bodies.single.containsKey('roles'), false);
    expect(bodies.single.containsKey('active_role'), false);
    expect(saved!['phone'], '+77000000001');
    await tester.pumpWidget(const SizedBox());
    api.dispose();
  });
  testWidgets(
      'profile conflict refreshes its version while preserving the name and selected role',
      (tester) async {
    var writes = 0, reads = 0;
    Json? saved;
    final api = client((r) async {
      if (r.method == 'GET') {
        reads++;
        return ok({...initial, 'version': 2});
      }
      writes++;
      if (writes == 1)
        return http.Response(
            '{"error":{"code":"STATE_CONFLICT","message":"Данные изменились"}}',
            409,
            headers: {'content-type': 'application/json; charset=utf-8'});
      final body = jsonDecode(r.body);
      expect(body['expected_version'], 2);
      expect(body['display_name'], 'Новое имя');
      expect(body['active_role'], 'executor');
      return ok({...initial, ...body, 'id': 'owner', 'version': 3});
    });
    await tester.pumpWidget(host(ProfileEditor(
        api: api,
        initial: initial,
        onboarding: true,
        pickAvatar: () async => null,
        onSaved: (v) => saved = v)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Новое имя');
    await tester.scrollUntilVisible(find.text('Найти заказы'), 150,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Найти заказы'));
    await tester.pump();
    await tester.tap(find.text('Сохранить профиль'));
    await tester.pumpAndSettle();
    expect(reads, 1,
        reason:
            'writes=$writes; notices=${tester.widgetList<Notice>(find.byType(Notice)).map((n) => n.text).join("|")}');
    expect(saved, isNull);
    expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        'Новое имя');
    await tester.tap(find.text('Сохранить профиль'));
    await tester.pumpAndSettle();
    expect(writes, 2);
    expect(saved?['active_role'], 'executor');
    await tester.pumpWidget(const SizedBox());
    api.dispose();
  });
  testWidgets('an old avatar picker never patches a replacement session',
      (tester) async {
    final picker = Completer<Json?>();
    var writes = 0;
    final api = client((r) async {
      writes++;
      return ok({...initial, 'version': 2, 'avatar_id': 'isolated-photo'});
    });
    await tester.pumpWidget(host(ProfileEditor(
        api: api,
        initial: initial,
        onboarding: true,
        pickAvatar: () => picker.future,
        onSaved: (v) => fail('Not a save'))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Добавить фото'));
    await tester.pump();
    await api.forget();
    api.session = {
      'access_token': 'replacement-token',
      'user': {'id': 'other-owner'}
    };
    picker.complete({'id': 'isolated-photo'});
    await tester.pumpAndSettle();
    expect(writes, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    api.dispose();
  });
  testWidgets('overlong profile names are rejected without an API command',
      (tester) async {
    var writes = 0;
    final api = client((r) async {
      writes++;
      return ok(initial);
    });
    await tester.pumpWidget(host(ProfileEditor(
        api: api,
        initial: initial,
        onboarding: true,
        pickAvatar: () async => null,
        onSaved: (v) {})));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byType(TextFormField).first, List.filled(61, 'x').join());
    await tester.tap(find.text('Сохранить профиль'));
    await tester.pumpAndSettle();
    expect(writes, 0);
    await tester.pumpWidget(const SizedBox());
    api.dispose();
  });
  testWidgets(
      'city load retries and cancelling selectors preserves the existing draft',
      (tester) async {
    var reads = 0, writes = 0;
    final api = client((r) async {
      if (r.method != 'GET') {
        writes++;
        return ok(initial);
      }
      if (++reads == 1)
        return http.Response(
            '{"error":{"code":"UNAVAILABLE","message":"Unavailable"}}', 503,
            headers: {'content-type': 'application/json'});
      return ok({
        'items': [
          {'id': 'almaty', 'name': 'Алматы'}
        ]
      });
    });
    await tester.pumpWidget(host(ProfileEditor(
        api: api,
        initial: {...initial, 'city': 'Астана'},
        onboarding: false,
        pickAvatar: () async => null,
        onSaved: (_) {})));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('profile-city-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Повторить'));
    await tester.pumpAndSettle();
    expect(reads, 2);
    await tester.tap(find.byTooltip('Назад'));
    await tester.pumpAndSettle();
    expect(find.text('Астана'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('profile-languages-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Русский').last);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Выбрать'))
            .onPressed,
        isNull);
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(find.text('Русский'), findsOneWidget);
    expect(writes, 0);
    await tester.pumpWidget(const SizedBox());
    api.dispose();
  });
  testWidgets(
      'avatar response retains private phone and does not overwrite the role on edit save',
      (tester) async {
    Json? saved;
    final bodies = <Json>[];
    final api = client((r) async {
      if (r.method == 'GET') return http.Response('{}', 404);
      final b = jsonDecode(r.body) as Json;
      bodies.add(b);
      return ok({
        ...initial,
        ...b,
        'version': b['expected_version'] + 1,
        'avatar_id': 'clean-upload'
      });
    });
    await tester.pumpWidget(host(ProfileEditor(
        api: api,
        initial: {...initial, 'phone': '+77000000001'},
        onboarding: false,
        pickAvatar: () async => {'id': 'clean-upload'},
        onSaved: (v) => saved = v)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Изменить фото'));
    await tester.pumpAndSettle();
    expect(find.text('+77000000001'), findsOneWidget);
    await tester.tap(find.text('Сохранить профиль'));
    await tester.pumpAndSettle();
    expect(bodies.last['expected_version'], 2);
    expect(bodies.last.containsKey('roles'), false);
    expect(saved!['phone'], '+77000000001');
    await tester.pumpWidget(const SizedBox());
    api.dispose();
  });
}
