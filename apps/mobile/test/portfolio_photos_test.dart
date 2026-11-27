import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:services_marketplace/core/api.dart';
import 'package:services_marketplace/screens/portfolio_photos.dart';

http.Response ok(dynamic data) =>
    http.Response(jsonEncode({'data': data, 'meta': {}}), 200,
        headers: {'content-type': 'application/json; charset=utf-8'});
void main() {
  testWidgets(
      'photo order and cover survive failed save; crop uses the selected real upload',
      (t) async {
    final image = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=');
    var attempts = 0, done = false;
    Json? saved;
    String? cropped;
    final api =
        JobaApi('https://isolated.example', transport: MockClient((r) async {
      if (r.url.path.endsWith('/download'))
        return http.Response.bytes(image, 200,
            headers: {'content-type': 'image/png'});
      if (r.url.path.endsWith('/crop')) {
        cropped = r.url.path;
        return ok({'id': 'cropped-second'});
      }
      if (r.method == 'PATCH') {
        attempts++;
        saved = Json.from(jsonDecode(r.body));
        if (attempts == 1)
          return http.Response(
              jsonEncode({
                'error': {
                  'code': 'TEMPORARY_FAILURE',
                  'message': 'Повторите сохранение'
                }
              }),
              503,
              headers: {'content-type': 'application/json; charset=utf-8'});
        return ok({'id': 'project', 'version': 8});
      }
      return ok({
        'id': 'project',
        'version': 7,
        'photos': ['first', 'second'],
        'cover_id': 'first'
      });
    }))
          ..session = {
            'access_token': 'isolated',
            'user': {'id': 'owner'}
          };
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: PortfolioPhotos(
                api: api, id: 'project', onDone: () => done = true))));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.byTooltip('Действия с фото').first, 150,
        scrollable: find.byType(Scrollable).first);
    await t.tap(find.byTooltip('Действия с фото').first);
    await t.pumpAndSettle();
    await t.tap(find.text('Ниже'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Действия с фото').first);
    await t.pumpAndSettle();
    await t.tap(find.text('Сделать обложкой'));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.text('Обрезать'), -150,
        scrollable: find.byType(Scrollable).first);
    await t.tap(find.text('Обрезать'));
    await t.pumpAndSettle();
    expect(cropped?.endsWith('/uploads/second/crop'), true);
    await t.tap(find.text('Готово'));
    await t.pumpAndSettle();
    expect(done, false);
    await t.tap(find.text('Готово'));
    await t.pumpAndSettle();
    expect(done, true);
    expect(attempts, 2);
    expect(saved?['expected_version'], 7);
    expect(saved?['upload_ids'], ['cropped-second', 'first']);
    expect(saved?['cover_id'], 'cropped-second');
    await t.pumpWidget(const SizedBox());
    api.dispose();
  });
}
