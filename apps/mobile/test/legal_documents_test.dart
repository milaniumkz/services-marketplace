import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:services_marketplace/core/api.dart';
import 'package:services_marketplace/core/theme.dart';
import 'package:services_marketplace/screens/legal_documents.dart';

class _Vault implements SessionVault {
  Future<String?> read() async => null;
  Future<void> write(String v) async {}
  Future<void> clear() async {}
}

void main() {
  testWidgets(
      'public legal catalog requests selected country and language and opens published document with its immutable version',
      (tester) async {
    final requests = <http.Request>[];
    final api = JobaApi('https://isolated.example', vault: _Vault(),
        transport: MockClient((r) async {
      requests.add(r);
      return http.Response(
          jsonEncode({
            'data': {
              'items': [
                {
                  'id': 'published-document',
                  'type': 'terms',
                  'version': 4,
                  'published_at': '2026-10-15T01:00:00Z',
                  'content':
                      'Содержимое опубликованного документа выбранной страны и языка.'
                }
              ]
            },
            'meta': {}
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    }));
    await tester.pumpWidget(MaterialApp(
        theme: jobaTheme(),
        home: Scaffold(
            body: LegalDocuments(
                api: api,
                country: 'KG',
                locale: 'ru',
                countryLabel: 'Кыргызстан',
                localeLabel: 'Русский'))));
    await tester.pumpAndSettle();
    expect(
        requests.single.url.queryParameters, {'country': 'KG', 'locale': 'ru'});
    expect(requests.single.headers['Authorization'], isNull);
    expect(find.text('Версия 4 · 15.10.2026'), findsOneWidget);
    await tester.tap(find.text('Пользовательское соглашение'));
    await tester.pumpAndSettle();
    expect(
        find.text(
            'Содержимое опубликованного документа выбранной страны и языка.'),
        findsOneWidget);
    expect(find.text('Версия 4 · 15.10.2026'), findsOneWidget);
    expect(requests.length, 1);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Документы JOBA'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    api.dispose();
  });
}
