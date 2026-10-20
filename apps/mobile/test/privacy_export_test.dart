import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:services_marketplace/core/api.dart';
import 'package:services_marketplace/core/theme.dart';
import 'package:services_marketplace/main.dart';
import 'package:services_marketplace/screens/marketplace.dart';
import 'package:services_marketplace/screens/privacy_export.dart';

class _Vault implements SessionVault {
  Future<String?> read() async => null;
  Future<void> write(String v) async {}
  Future<void> clear() async {}
}

void main() {
  testWidgets(
      'export requests require the current password, retain a failed form, and expose saving only for an available archive',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Json job = {
      'id': 'export-owned',
      'type': 'export',
      'status': 'processing',
      'download_available': false
    };
    final user = {
      'id': 'privacy-owner',
      'country': 'KZ',
      'status': 'active',
      'locale': 'ru',
      'roles': ['customer']
    };
    final requests = <http.Request>[];
    http.Response ok(dynamic value) =>
        http.Response(jsonEncode({'data': value, 'meta': {}}), 200,
            headers: {'content-type': 'application/json; charset=utf-8'});
    final api = JobaApi('https://isolated.example', vault: _Vault(),
        transport: MockClient((r) async {
      requests.add(r);
      if (r.method == 'POST' && r.url.path.endsWith('/me/privacy-requests')) {
        if (jsonDecode(r.body)['current_password'] !=
            'isolated-correct-password')
          return http.Response(
              '{"error":{"code":"REAUTH_REQUIRED","message":"Подтвердите текущий пароль"}}',
              401,
              headers: {'content-type': 'application/json; charset=utf-8'});
        return ok(job);
      }
      if (r.url.path.endsWith('/me/privacy-requests/export-owned'))
        return ok(job);
      if (r.url.path.endsWith('/me')) return ok(user);
      return ok({'items': []});
    }));
    await tester.pumpWidget(JobaApp(api: api));
    await tester.pumpAndSettle();
    final dynamic state = tester.state(find.byType(Marketplace));
    api.session = {
      'access_token': 'isolated-access',
      'refresh_token': 'isolated-refresh',
      'user': user
    };
    state.me = user;
    state.go('privacy');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Экспортировать данные'));
    await tester.pumpAndSettle();
    expect(state.route, 'export');
    await tester.tap(find.text('Запросить экспорт'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byType(TextFormField), 'isolated-wrong-password');
    await tester.tap(find.text('Создать запрос'));
    await tester.pumpAndSettle();
    expect(api.authenticated, true);
    expect(find.text('Подтвердите текущий пароль'), findsOneWidget);
    expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        'isolated-wrong-password');
    expect(
        requests.where((r) => r.url.path.endsWith('/auth/refresh')), isEmpty);
    await tester.enterText(
        find.byType(TextFormField), 'isolated-correct-password');
    await tester.tap(find.text('Создать запрос'));
    await tester.pumpAndSettle();
    expect(state.route, 'export-pending');
    expect(state.objectId, 'export-owned');
    expect(find.text('Готовим вашу копию'), findsOneWidget);
    await tester.tap(find.text('Вернуться к приватности'));
    await tester.pumpAndSettle();
    expect(state.route, 'privacy');
    String? saved;
    var renew = 0;
    Future<void> show() async {
      await tester.pumpWidget(MaterialApp(
          theme: jobaTheme(),
          home: Scaffold(
              body: ExportStatus(
                  key: UniqueKey(),
                  api: api,
                  id: 'export-owned',
                  onPrivacy: () {},
                  onNewRequest: () => renew++,
                  onDownload: (id) => saved = id))));
      await tester.pumpAndSettle();
    }

    job = {
      ...job,
      'status': 'completed',
      'upload_id': 'actual-owned-archive',
      'download_available': false
    };
    await show();
    expect(find.text('Сохранить архив'), findsNothing);
    await tester.tap(find.text('Запросить экспорт'));
    expect(renew, 1);
    job = {...job, 'download_available': true};
    await show();
    await tester.tap(find.text('Сохранить архив'));
    expect(saved, 'actual-owned-archive');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    api.dispose();
  });
}
