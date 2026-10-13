import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:services_marketplace/main.dart';
import 'package:services_marketplace/core/api.dart';

class MemoryVault implements SessionVault {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String v) async {
    value = v;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

http.Response ok(dynamic data) =>
    http.Response(jsonEncode({'data': data, 'meta': {}}), 200,
        headers: {'content-type': 'application/json; charset=utf-8'});
void main() {
  test('Old command never replays under a newly signed-in account', () async {
    final pending = Completer<http.Response>(), started = Completer<void>();
    var rotations = 0, mutations = 0;
    final api = JobaApi('https://example.com', vault: MemoryVault(),
        transport: MockClient((request) async {
      if (request.url.path.endsWith('/auth/login'))
        return ok({
          'access_token': 'new-user-token',
          'refresh_token': 'new-refresh',
          'user': {'id': 'new-user'}
        });
      if (request.url.path.endsWith('/auth/refresh')) {
        rotations++;
        return ok({});
      }
      mutations++;
      started.complete();
      return pending.future;
    }))
      ..session = {
        'access_token': 'old-user-token',
        'refresh_token': 'old-refresh',
        'user': {'id': 'old-user'}
      };
    final command = api.request('/me',
        method: 'PATCH',
        body: {'expected_version': 1, 'display_name': 'Old account data'});
    await started.future;
    await api
        .signIn({'phone': '+77000000002', 'password': 'New account password!'});
    pending.complete(http.Response(
        '{"error":{"code":"TOKEN_EXPIRED","message":"expired"}}', 401));
    await expectLater(
        command,
        throwsA(isA<ApiException>()
            .having((error) => error.code, 'code', 'SESSION_SUPERSEDED')));
    expect(rotations, 0);
    expect(mutations, 1);
    expect(api.session!['user']['id'], 'new-user');
    api.dispose();
  });

  test(
      'Ambiguous binary upload resumes its server record without creating another file',
      () async {
    var initiations = 0, puts = 0, finalizations = 0;
    var uploaded = false;
    final image = Uint8List.fromList([1, 2, 3, 4]);
    final api = JobaApi('https://example.com', vault: MemoryVault(),
        transport: MockClient((request) async {
      if (request.url.path.endsWith('/uploads/initiate')) {
        initiations++;
        return ok({'id': 'upload-one', 'status': 'initiated'});
      }
      if (request.url.path.endsWith('/content')) {
        puts++;
        uploaded = true;
        throw http.ClientException(
            'Connection lost after the server accepted bytes');
      }
      if (request.url.path.endsWith('/metadata'))
        return ok({
          'id': 'upload-one',
          'status': uploaded ? 'uploaded' : 'initiated',
          'mime': 'image/png'
        });
      if (request.url.path.endsWith('/finalize')) {
        finalizations++;
        return ok(
            {'id': 'upload-one', 'status': 'clean', 'mime': 'image/jpeg'});
      }
      return ok({});
    }))
      ..session = {
        'access_token': 'token',
        'refresh_token': 'refresh',
        'user': {'id': 'owner'}
      };
    await expectLater(
        api.upload(image, 'image/png', 'avatar'),
        throwsA(isA<ApiException>()
            .having((error) => error.code, 'code', 'OFFLINE')));
    final saved = await api.upload(image, 'image/png', 'avatar');
    expect(saved['id'], 'upload-one');
    expect(saved['status'], 'clean');
    expect(initiations, 1);
    expect(puts, 1);
    expect(finalizations, 1);
    api.dispose();
  });

  test(
      'Concurrent expired requests rotate once and retain mutation idempotency',
      () async {
    var rotations = 0;
    final keys = <String>[];
    final client = MockClient((r) async {
      if (r.url.path.endsWith('/auth/refresh')) {
        rotations++;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return ok({'access_token': 'new', 'refresh_token': 'next'});
      }
      keys.add(r.headers['Idempotency-Key'] ?? '');
      if (r.headers['Authorization'] == 'Bearer old')
        return http.Response(
            '{"error":{"code":"TOKEN_EXPIRED","message":"expired"}}', 401,
            headers: {'content-type': 'application/json; charset=utf-8'});
      return ok({'id': 'saved'});
    });
    final api =
        JobaApi('https://example.com', transport: client, vault: MemoryVault())
          ..session = {'access_token': 'old', 'refresh_token': 'refresh'};
    await Future.wait([
      api.request('/orders',
          method: 'POST', key: 'original-key', body: {'title': 'Task'}),
      api.request('/me')
    ]);
    expect(rotations, 1);
    expect(keys.where((k) => k == 'original-key').length, 2);
    expect(api.accessToken, 'new');
    api.dispose();
  });
  test('An ambiguous network failure keeps the command key for user retry',
      () async {
    final keys = <String>[];
    var count = 0;
    final api = JobaApi('https://example.com', vault: MemoryVault(),
        transport: MockClient((r) async {
      keys.add(r.headers['Idempotency-Key']!);
      if (count++ == 0) throw http.ClientException('connection interrupted');
      return ok({'id': 'same-order'});
    }))
      ..session = {
        'access_token': 'valid',
        'refresh_token': 'refresh',
        'user': {'id': 'owner'}
      };
    await expectLater(
        api.request('/orders', method: 'POST', body: {'title': 'One order'}),
        throwsA(isA<ApiException>()));
    await api.request('/orders', method: 'POST', body: {'title': 'One order'});
    expect(keys.toSet().length, 1);
    api.dispose();
  });
  test('A refresh finishing after logout cannot restore saved credentials',
      () async {
    final reply = Completer<http.Response>(), vault = MemoryVault();
    final api = JobaApi('https://example.com',
        vault: vault, transport: MockClient((r) => reply.future))
      ..session = {'access_token': 'old', 'refresh_token': 'old-refresh'};
    final pending = api.refresh();
    final failed = expectLater(pending, throwsA(isA<ApiException>()));
    await api.forget();
    reply.complete(
        ok({'access_token': 'late', 'refresh_token': 'late-refresh'}));
    await failed;
    expect(api.authenticated, false);
    expect(vault.value, isNull);
    api.dispose();
  });
  test('Revoked refresh clears saved credentials', () async {
    final vault = MemoryVault()..value = 'saved';
    final api = JobaApi('https://example.com',
        vault: vault,
        transport: MockClient((r) async => http.Response(
            '{"error":{"code":"TOKEN_EXPIRED","message":"expired"}}', 401,
            headers: {'content-type': 'application/json; charset=utf-8'})))
      ..session = {'access_token': 'old', 'refresh_token': 'revoked'};
    await expectLater(api.refresh(), throwsA(isA<ApiException>()));
    expect(vault.value, isNull);
    expect(api.authenticated, false);
    api.dispose();
  });
  testWidgets('Saved credentials stay behind local unlock without refreshing',
      (tester) async {
    var requests = 0;
    final vault = MemoryVault()
      ..value = jsonEncode({
        'access_token': 'saved',
        'refresh_token': 'saved-refresh',
        'user': {'id': 'saved-user'}
      });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            (call) async => call.method == 'read' ? '{}' : null);
    final api = JobaApi('https://example.com', vault: vault,
        transport: MockClient((r) async {
      requests++;
      return ok({});
    }));
    await tester.pumpWidget(JobaApp(api: api));
    await tester.pumpAndSettle();
    expect(find.text('Разблокировка JOBA'), findsOneWidget);
    expect(requests, 0);
    await tester.pumpWidget(const SizedBox());
    api.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            null);
  });
  testWidgets(
      'Login fields work, passwords can be revealed, API error is visible',
      (tester) async {
    final api = JobaApi('https://example.com',
        vault: MemoryVault(),
        transport: MockClient((r) async => http.Response(
            '{"error":{"code":"INVALID_CREDENTIALS","message":"Неверный номер или пароль"}}',
            401,
            headers: {'content-type': 'application/json; charset=utf-8'})));
    await tester.pumpWidget(JobaApp(api: api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Продолжить'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), '+77011234567');
    await tester.enterText(
        find.byType(TextFormField).at(1), 'invalid password');
    await tester.tap(find.byTooltip('Показать пароль'));
    await tester.pump();
    expect(find.byTooltip('Скрыть пароль'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Войти'));
    await tester.pumpAndSettle();
    expect(find.text('Неверный номер или пароль'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    api.dispose();
  });
  testWidgets(
      'Current legal consent can be accepted and withdrawn without continuing on an unaccepted version',
      (tester) async {
    var accepted = false;
    final document = {
      'id': 'legal-current',
      'type': 'privacy',
      'hash': 'current-hash',
      'content': 'Утверждённая политика обработки данных'
    };
    final user = {
      'id': 'consent-user',
      'country': 'KZ',
      'locale': 'ru',
      'roles': ['customer'],
      'version': 1
    };
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            (call) async => call.method == 'read' ? '{}' : null);
    final api = JobaApi('https://example.com', vault: MemoryVault(),
        transport: MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/auth/login'))
        return ok({
          'access_token': 'consent-token',
          'refresh_token': 'consent-refresh',
          'user': user
        });
      if (path.endsWith('/legal/documents'))
        return ok({
          'items': [document]
        });
      if (path.endsWith('/me/consents')) {
        if (request.method == 'POST')
          accepted = jsonDecode(request.body)['accepted'] == true;
        return ok({
          'items': [
            {
              'document_id': 'legal-current',
              'document_hash': 'current-hash',
              'accepted': accepted,
              'sequence': 1
            }
          ]
        });
      }
      if (path.endsWith('/me')) return ok(user);
      return ok({});
    }));
    await tester.pumpWidget(JobaApp(api: api));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Продолжить'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), '+77011234567');
    await tester.enterText(
        find.byType(TextFormField).at(1), 'Consenting account password');
    await tester.tap(find.widgetWithText(FilledButton, 'Войти'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Входить с паролем'));
    await tester.tap(find.text('Входить с паролем'));
    await tester.pumpAndSettle();
    FilledButton next() => tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'Продолжить'));
    expect(next().onPressed, isNull);
    await tester.tap(find.text('Принять эту версию'));
    await tester.pumpAndSettle();
    expect(accepted, true);
    expect(next().onPressed, isNotNull);
    await tester.tap(find.text('Отозвать согласие'));
    await tester.pumpAndSettle();
    expect(accepted, false);
    expect(next().onPressed, isNull);
    await tester.pumpWidget(const SizedBox());
    api.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            null);
  });
}
