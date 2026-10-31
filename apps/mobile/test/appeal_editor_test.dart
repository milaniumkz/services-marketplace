import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:services_marketplace/core/api.dart';
import 'package:services_marketplace/core/theme.dart';
import 'package:services_marketplace/screens/appeal_editor.dart';

class _Vault implements SessionVault {
  Future<String?> read() async => null;
  Future<void> write(String v) async {}
  Future<void> clear() async {}
}

void main() {
  testWidgets(
      'appeal keeps text and evidence on conflict, refreshes decision before retry, and confirms only actual success',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final sent = <Json>[];
    var opened = 0;
    final api = JobaApi('https://isolated.example', vault: _Vault(),
        transport: MockClient((r) async {
      if (r.method == 'POST') {
        final body = jsonDecode(r.body) as Json;
        sent.add(body);
        if (body['expected_version'] == 1)
          return http.Response('{"error":{"code":"STATE_CONFLICT"}}', 409);
        return http.Response(
            '{"data":{"id":"case-owned","status":"appealed","version":3},"meta":{}}',
            200);
      }
      return http.Response(
          '{"data":{"id":"case-owned","status":"resolved","decision":"content_removed","version":2},"meta":{}}',
          200);
    }))
      ..session = {
        'access_token': 'isolated',
        'user': {'country': 'KZ'}
      };
    await tester.pumpWidget(MaterialApp(
        theme: jobaTheme(),
        home: AppealEditor(
            api: api,
            incident: {
              'id': 'case-owned',
              'status': 'resolved',
              'decision': 'content_removed',
              'version': 1
            },
            pickUpload: () async =>
                {'id': 'clean-owned-file', 'status': 'clean'},
            onCases: () => opened++)));
    await tester.tap(find.text('Отправить апелляцию'));
    await tester.pumpAndSettle();
    expect(sent, isEmpty);
    final reason = find.byType(TextFormField);
    await tester.ensureVisible(reason);
    await tester.enterText(
        reason, 'Прошу пересмотреть решение по приложенным материалам.');
    await tester.scrollUntilVisible(find.text('Добавить материалы'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Добавить материалы'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Отправить апелляцию'));
    await tester.pumpAndSettle();
    expect(sent.single['upload_ids'], ['clean-owned-file']);
    expect(find.text('Апелляция отправлена'), findsNothing);
    final submit = find.widgetWithText(FilledButton, 'Отправить апелляцию');
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);
    await tester.scrollUntilVisible(find.text('Обновить решение'), -200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Обновить решение'));
    await tester.pumpAndSettle();
    expect(find.text('Прошу пересмотреть решение по приложенным материалам.'),
        findsOneWidget);
    await tester.tap(find.text('Отправить апелляцию'));
    await tester.pumpAndSettle();
    expect(sent.last['expected_version'], 2);
    expect(sent.last['upload_ids'], ['clean-owned-file']);
    expect(find.text('Апелляция отправлена'), findsOneWidget);
    expect(opened, 0);
    await tester.tap(find.text('Мои обращения'));
    expect(opened, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    api.dispose();
  });
}
