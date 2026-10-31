import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:services_marketplace/core/api.dart';
import 'package:services_marketplace/core/theme.dart';
import 'package:services_marketplace/screens/support_new.dart';

class _Vault implements SessionVault {
  Future<String?> read() async => null;
  Future<void> write(String value) async {}
  Future<void> clear() async {}
}

void main() {
  testWidgets(
      'support form validates text, preserves draft and attachment on rejection, and opens the actual created thread',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var reject = true;
    String? opened;
    final sent = <Json>[];
    final api = JobaApi('https://isolated.example', vault: _Vault(),
        transport: MockClient((r) async {
      if (r.method == 'POST') {
        sent.add(jsonDecode(r.body) as Json);
        if (reject)
          return http.Response(
              '{"error":{"code":"UNSAFE_UPLOAD","message":"Файл ещё проверяется"}}',
              422,
              headers: {'content-type': 'application/json; charset=utf-8'});
        return http.Response(
            '{"data":{"id":"created-support"},"meta":{}}', 200);
      }
      return http.Response(
          '{"data":{"items":[{"id":"owned-order","title":"Реальный выбранный заказ"}]},"meta":{}}',
          200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    }))
      ..session = {
        'access_token': 'isolated',
        'user': {'country': 'KZ'}
      };
    await tester.pumpWidget(MaterialApp(
        theme: jobaTheme(),
        home: Scaffold(
            body: SupportNew(
                api: api,
                executor: false,
                pickUpload: () async =>
                    {'id': 'isolated-upload', 'status': 'clean'},
                onCreated: (id) => opened = id))));
    await tester.tap(find.text('Начать чат'));
    await tester.pumpAndSettle();
    expect(sent, isEmpty);
    await tester.tap(find.text('Без связи с заказом'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Реальный выбранный заказ'));
    await tester.pumpAndSettle();
    final question = find.byType(TextFormField);
    await tester.ensureVisible(question);
    await tester.enterText(question, 'Как запросить доработку результата?');
    await tester.scrollUntilVisible(find.text('Фото или файл'), 150,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Фото или файл'));
    await tester.pumpAndSettle();
    expect(find.text('Файл проверен'), findsOneWidget);
    await tester.tap(find.text('Начать чат'));
    await tester.pumpAndSettle();
    expect(opened, isNull);
    expect(sent.single['upload_ids'], ['isolated-upload']);
    expect(sent.single['topic'], 'orders');
    expect(sent.single['order_id'], 'owned-order');
    expect(sent.single['text'], 'Как запросить доработку результата?');
    expect(find.text('Как запросить доработку результата?'), findsOneWidget);
    reject = false;
    await tester.tap(find.text('Начать чат'));
    await tester.pumpAndSettle();
    expect(opened, 'created-support');
    expect(sent.length, 2);
    expect(sent.last, sent.first);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    api.dispose();
  });
}
