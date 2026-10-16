import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:services_marketplace/core/api.dart';
import 'package:services_marketplace/screens/portfolio_editor.dart';

http.Response ok(dynamic data) =>
    http.Response(jsonEncode({'data': data, 'meta': {}}), 200,
        headers: {'content-type': 'application/json; charset=utf-8'});
const pixel =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';
void main() {
  testWidgets(
      'moderation retries retain edited fields and use the latest saved version',
      (t) async {
    final writes = <Json>[];
    var version = 7, submissions = 0;
    String? route;
    final api =
        JobaApi('https://isolated.example', transport: MockClient((r) async {
      if (r.url.path.endsWith('/download'))
        return http.Response.bytes(base64Decode(pixel), 200);
      if (r.url.path.endsWith('/catalog/categories'))
        return ok({
          'items': [
            {'id': 'category', 'name': 'Ремонт'}
          ]
        });
      if (r.method == 'PATCH') {
        final body = Json.from(jsonDecode(r.body));
        writes.add(body);
        expect(body['expected_version'], version);
        version++;
        return ok({'id': 'project', 'version': version, 'status': 'draft'});
      }
      if (r.method == 'POST') {
        submissions++;
        expect(jsonDecode(r.body)['expected_version'], version);
        if (submissions == 1)
          return http.Response(
              jsonEncode({
                'error': {
                  'code': 'TEMPORARY_FAILURE',
                  'message': 'Повторите отправку'
                }
              }),
              503,
              headers: {'content-type': 'application/json; charset=utf-8'});
        return ok({'id': 'project', 'version': ++version, 'status': 'pending'});
      }
      return ok({
        'id': 'project',
        'version': version,
        'title': 'Исходный проект',
        'description': 'Описание',
        'category_id': 'category',
        'status': 'draft',
        'photos': ['photo'],
        'cover_id': 'photo',
        'rights_confirmed': true
      });
    }))
          ..session = {'access_token': 'isolated'};
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: PortfolioEditor(
                api: api,
                id: 'project',
                pickPhoto: () async => null,
                onGo: (r, id) => route = r))));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextFormField).first, 'Изменённый проект');
    await t.tap(find.text('Отправить на проверку'));
    await t.pumpAndSettle();
    expect(route, isNull);
    expect(find.text('Изменённый проект'), findsOneWidget);
    await t.tap(find.text('Отправить на проверку'));
    await t.pumpAndSettle();
    expect(route, 'portfolio-pending');
    expect(submissions, 2);
    expect(writes.map((b) => b['expected_version']), [7, 8]);
    expect(writes.last['title'], 'Изменённый проект');
    expect(writes.last['rights_confirmed'], true);
    expect(writes.last['upload_ids'], ['photo']);
    await t.pumpWidget(const SizedBox());
    api.dispose();
  });
  testWidgets(
      'photo management saves the edited draft first and never submits it',
      (t) async {
    final paths = <String>[];
    Json? body;
    String? route;
    final api =
        JobaApi('https://isolated.example', transport: MockClient((r) async {
      if (r.url.path.endsWith('/download'))
        return http.Response.bytes(base64Decode(pixel), 200);
      if (r.url.path.endsWith('/catalog/categories'))
        return ok({
          'items': [
            {'id': 'category', 'name': 'Ремонт'}
          ]
        });
      if (r.method != 'GET') {
        paths.add(r.url.path);
        body = Json.from(jsonDecode(r.body));
        return ok({'id': 'project', 'version': 8, 'status': 'draft'});
      }
      return ok({
        'id': 'project',
        'version': 7,
        'title': 'Исходный проект',
        'category_id': 'category',
        'photos': ['photo'],
        'cover_id': 'photo',
        'rights_confirmed': false
      });
    }))
          ..session = {'access_token': 'isolated'};
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: PortfolioEditor(
                api: api,
                id: 'project',
                pickPhoto: () async => null,
                onGo: (r, id) => route = r))));
    await t.pumpAndSettle();
    expect(
        t
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Отправить на проверку'))
            .onPressed,
        isNull);
    await t.enterText(
        find.byType(TextFormField).first, 'Сохранённый перед фото');
    await t.tap(find.byType(Image).first);
    await t.pumpAndSettle();
    expect(route, 'portfolio-photos');
    expect(paths, ['/api/v1/me/portfolio-projects/project']);
    expect(body?['title'], 'Сохранённый перед фото');
    expect(body?['rights_confirmed'], false);
    await t.pumpWidget(const SizedBox());
    api.dispose();
  });
  testWidgets('new draft is not created twice when attaching photos fails',
      (t) async {
    var created = 0, patched = 0;
    String? route;
    final api =
        JobaApi('https://isolated.example', transport: MockClient((r) async {
      if (r.url.path.endsWith('/download'))
        return http.Response.bytes(base64Decode(pixel), 200);
      if (r.method == 'GET')
        return ok({
          'items': [
            {'id': 'category', 'name': 'Ремонт'}
          ]
        });
      if (r.method == 'POST') {
        created++;
        return ok({'id': 'created', 'version': 1, 'status': 'draft'});
      }
      patched++;
      expect(jsonDecode(r.body)['expected_version'], 1);
      expect(jsonDecode(r.body)['upload_ids'], ['uploaded']);
      if (patched == 1)
        return http.Response(
            jsonEncode({
              'error': {
                'code': 'TEMPORARY_FAILURE',
                'message': 'Повторите сохранение'
              }
            }),
            503,
            headers: {'content-type': 'application/json; charset=utf-8'});
      return ok({'id': 'created', 'version': 2, 'status': 'draft'});
    }))
          ..session = {'access_token': 'isolated'};
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: PortfolioEditor(
                api: api,
                pickPhoto: () async => {'id': 'uploaded'},
                onGo: (r, id) => route = r))));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextFormField).first, 'Созданный проект');
    await t.tap(find.byType(DropdownButtonFormField<String>));
    await t.pumpAndSettle();
    await t.tap(find.text('Ремонт').last);
    await t.pumpAndSettle();
    await t.tap(find.text('Добавить'));
    await t.pumpAndSettle();
    await t.tap(find.text('Сохранить'));
    await t.pumpAndSettle();
    expect(route, isNull);
    await t.tap(find.text('Сохранить'));
    await t.pumpAndSettle();
    expect(created, 1);
    expect(patched, 2);
    expect(route, 'portfolio-project');
    await t.pumpWidget(const SizedBox());
    api.dispose();
  });
}
