import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import '../lib/core/api.dart';
import '../lib/core/photo_file.dart';
import '../lib/screens/face_access.dart';

class Vault implements SessionVault {
  Future<String?> read() async => null;
  Future<void> write(String value) async {}
  Future<void> clear() async {}
}

http.Response ok(Map<String, dynamic> data) =>
    http.Response(jsonEncode({'data': data}), 200,
        headers: {'content-type': 'application/json; charset=utf-8'});
void main() {
  testWidgets(
      'enrollment requires consent and sends current password with camera capture',
      (t) async {
    var captures = 0, saved = false;
    Map<String, dynamic>? body;
    final api = JobaApi('https://example.test', vault: Vault(),
        transport: MockClient((r) async {
      if (r.method == 'GET')
        return ok({
          'enrolled': false,
          'can_enroll_without_password': false,
          'notice': 'Согласен сохранить шаблон лица'
        });
      body = jsonDecode(r.body) as Map<String, dynamic>;
      return ok({'enrolled': true});
    }))
      ..session = {
        'access_token': 'token',
        'user': {'id': 'u'}
      };
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: FaceAccess(
                api: api,
                onDone: () => saved = true,
                capturePhoto: (_) async {
                  captures++;
                  return PhotoFile(Uint8List.fromList([255, 216, 255, 1]));
                }))));
    await t.pumpAndSettle();
    final save = find.text('Сохранить лицо через камеру');
    await t.ensureVisible(save);
    await t.tap(save);
    await t.pump();
    expect(captures, 0);
    await t.enterText(find.byType(TextField), 'Current secret');
    await t.ensureVisible(find.byType(CheckboxListTile));
    await t.tap(find.byType(CheckboxListTile));
    await t.pump();
    await t.ensureVisible(save);
    await t.tap(save);
    await t.pumpAndSettle();
    expect(captures, 1);
    expect(saved, true);
    expect(body!['consent'], true);
    expect(body!['current_password'], 'Current secret');
    expect(body!['photos'], hasLength(5));
    expect((body!['photos'] as List).map((p) => p['step']),
        ['front', 'left', 'right', 'blink', 'smile']);
  });
  testWidgets(
      'recovery only reveals password form after face match and submits one-use proof',
      (t) async {
    var done = false;
    final requests = <http.Request>[];
    final api = JobaApi('https://example.test', vault: Vault(),
        transport: MockClient((r) async {
      requests.add(r);
      return ok(r.url.path.endsWith('/verify')
          ? {'verified': true, 'reset_token': 'one-use'}
          : {'changed': true});
    }));
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: FaceAccess(
                api: api,
                challenge: {'id': 'challenge', 'nonce': 'nonce'},
                onDone: () => done = true,
                capturePhoto: (_) async =>
                    PhotoFile(Uint8List.fromList([255, 216, 255, 1]))))));
    await t.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    await t.ensureVisible(find.text('Открыть фронтальную камеру'));
    await t.tap(find.text('Открыть фронтальную камеру'));
    await t.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(2));
    await t.enterText(find.byType(TextField).at(0), 'New secret 123');
    await t.enterText(find.byType(TextField).at(1), 'New secret 123');
    await t.ensureVisible(find.text('Сменить пароль'));
    await t.tap(find.text('Сменить пароль'));
    await t.pumpAndSettle();
    expect(done, true);
    expect(jsonDecode(requests.last.body)['reset_token'], 'one-use');
    expect(
        requests.every((r) => !r.headers.containsKey('authorization')), true);
  });
  testWidgets('mismatch keeps password change unavailable', (t) async {
    final api = JobaApi('https://example.test',
        vault: Vault(),
        transport: MockClient((_) async =>
            ok({'verified': false, 'message': 'Лицо не совпало'})));
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: FaceAccess(
                api: api,
                challenge: {'id': 'c', 'nonce': 'n'},
                onDone: () => fail('must not finish'),
                capturePhoto: (_) async =>
                    PhotoFile(Uint8List.fromList([255, 216, 255, 1]))))));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Открыть фронтальную камеру'));
    await t.tap(find.text('Открыть фронтальную камеру'));
    await t.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Лицо не совпало'), findsWidgets);
    expect(find.byType(SnackBar), findsOneWidget);
  });
}
