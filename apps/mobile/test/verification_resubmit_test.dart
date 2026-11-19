import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:services_marketplace/core/api.dart';
import 'package:services_marketplace/core/theme.dart';
import 'package:services_marketplace/screens/verification_editor.dart';

void main() {
  testWidgets(
      'rejection shows the real reason and opens the protected upload form only after retry',
      (t) async {
    var writes = 0, appeals = 0, picks = 0;
    final api =
        JobaApi('https://isolated.example', transport: MockClient((r) async {
      if (r.method != 'GET') writes++;
      return http.Response(
          jsonEncode({
            'data': {
              'status': 'rejected',
              'policy': {
                'id': 'policy',
                'version': 1,
                'document_id': 'legal',
                'document_types': ['id_card'],
                'required_pages': {
                  'id_card': ['Лицевая сторона', 'Оборотная сторона']
                },
                'consent_accepted': true
              },
              'items': [
                {
                  'id': 'check',
                  'version': 4,
                  'policy_id': 'policy',
                  'policy_version': 1,
                  'status': 'rejected',
                  'reason': 'Блик закрывает текст документа',
                  'document_type': 'id_card',
                  'created_at': '2026-10-15',
                  'required_pages': ['Лицевая сторона', 'Оборотная сторона']
                }
              ]
            },
            'meta': {}
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    }))
          ..session = {'access_token': 'isolated'};
    await t.pumpWidget(MaterialApp(
        theme: jobaTheme(),
        home: Scaffold(
            body: VerificationEditor(
                api: api,
                country: 'KZ',
                uploads: {},
                pick: (id) async {
                  picks++;
                  return {'id': 'new-page'};
                },
                onTerms: () {},
                onProfile: () {},
                onSupport: () {},
                onAppeal: (s) {
                  expect(s['id'], 'check');
                  appeals++;
                }))));
    await t.pumpAndSettle();
    expect(find.text('Блик закрывает текст документа'), findsNWidgets(2));
    expect(find.text('Добавить фотографии'), findsNothing);
    expect(writes, 0);
    await t.tap(find.text('Обжаловать решение'));
    expect(appeals, 1);
    await t.tap(find.text('Загрузить заново'));
    await t.pumpAndSettle();
    expect(find.text('Добавить фотографии'), findsOneWidget);
    expect(writes, 0);
    await t.scrollUntilVisible(find.text('Добавить фотографии'), 150,
        scrollable: find.byType(Scrollable).first);
    await t.tap(find.text('Добавить фотографии'));
    await t.pumpAndSettle();
    expect(picks, 1);
    expect(
        t
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Отправить на проверку'))
            .onPressed,
        isNull);
    await t.pumpWidget(const SizedBox());
    api.dispose();
  });
}
