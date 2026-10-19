import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:services_marketplace/main.dart';
import 'package:services_marketplace/core/api.dart';
import 'package:services_marketplace/core/widgets.dart';

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

class RecordingSink implements StreamConsumer<List<int>> {
  final bytes = <int>[];
  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      bytes.addAll(chunk);
    }
  }

  @override
  Future<void> close() async {}
}

void main() {
  test(
      'reauthentication and credential errors preserve current credentials without spending a refresh token',
      () async {
    final vault = MemoryVault()..value = 'isolated saved session';
    var refreshes = 0;
    String code = 'REAUTH_REQUIRED';
    final api = JobaApi('https://isolated.example', vault: vault,
        transport: MockClient((r) async {
      if (r.url.path.endsWith('/auth/refresh')) refreshes++;
      return http.Response(
          jsonEncode({
            'error': {'code': code}
          }),
          401);
    }))
      ..session = {
        'access_token': 'isolated-access',
        'refresh_token': 'isolated-refresh',
        'user': {'id': 'isolated-owner'}
      };
    for (final failure in ['REAUTH_REQUIRED', 'INVALID_CREDENTIALS']) {
      code = failure;
      await expectLater(
          api.request('/me/privacy-requests', method: 'POST', body: {
            'type': 'export',
            'current_password': 'isolated wrong password'
          }),
          throwsA(isA<ApiException>().having((e) => e.code, 'code', failure)));
      expect(api.authenticated, true);
      expect(api.sessionExpired, false);
      expect(api.accessToken, 'isolated-access');
      expect(vault.value, 'isolated saved session');
    }
    expect(refreshes, 0);
    api.dispose();
  });

  test(
      'expired access without refresh clears credentials and distinguishes expiry from explicit logout',
      () async {
    final vault = MemoryVault()..value = 'isolated saved session';
    final api = JobaApi('https://isolated.example',
        vault: vault,
        transport: MockClient(
            (request) async => request.url.path.endsWith('/auth/login')
                ? ok({
                    'access_token': 'isolated-restored',
                    'refresh_token': 'isolated-refresh',
                    'user': {'id': 'isolated-owner'}
                  })
                : http.Response('{"error":{"code":"TOKEN_EXPIRED"}}', 401)))
      ..session = {'access_token': 'isolated-expired'};
    addTearDown(api.dispose);
    await expectLater(
        api.request('/me'),
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', 'TOKEN_EXPIRED')));
    expect(api.authenticated, false);
    expect(api.sessionExpired, true);
    expect(vault.value, isNull);
    await api.signIn(
        {'phone': 'isolated-account', 'password': 'isolated test password'});
    expect(api.authenticated, true);
    expect(api.sessionExpired, false);
    await api.forget();
    expect(api.sessionExpired, false);
  });

  testWidgets(
      'Completed order picker keeps executor scope across pages and can clear a saved link',
      (tester) async {
    final calls = <Uri>[];
    final api = JobaApi('https://example.com', vault: MemoryVault(),
        transport: MockClient((request) async {
      calls.add(request.url);
      final next = request.url.queryParameters['cursor'] == 'next';
      return ok({
        'items': [
          {
            'id': next ? 'completed-129' : 'completed-1',
            'title':
                next ? '129-й завершённый заказ' : 'Первый завершённый заказ',
            'city': 'Алматы'
          }
        ],
        'meta': {'next_cursor': next ? null : 'next'}
      });
    }))
      ..session = {'access_token': 'isolated-picker'};
    String? selected;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ActionForm(
                fields: [
          InputSpec('order_id', 'Связать с выполненным заказом',
              initial: 'old-link',
              required: false,
              pickerApi: api,
              pickerPath: '/me/completed-orders',
              pickerQuery: const {'role': 'executor'})
        ],
                submit: (values) async {
                  selected = values['order_id'];
                }))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Выбранный заказ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Показать ещё'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('129-й завершённый заказ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(selected, 'completed-129');
    expect(calls.length, 2);
    expect(
        calls.every((uri) => uri.queryParameters['role'] == 'executor'), true);
    await tester.tap(find.text('129-й завершённый заказ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Без связи с заказом'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(selected, '');
    await tester.pumpWidget(const SizedBox());
    api.dispose();
  });

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
    expect(find.text('Введите PIN приложения'), findsOneWidget);
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
    expect(find.text('Не удалось войти. Проверьте данные или обратитесь за помощью.'), findsOneWidget);
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
          'items': [{'id':'terms-current','type':'terms','hash':'terms-hash','content':'Isolated accepted agreement'},document]
        });
      if (path.endsWith('/me/consents')) {
        if (request.method == 'POST')
          accepted = jsonDecode(request.body)['accepted'] == true;
        return ok({
          'items': [
            {'document_id':'terms-current','document_hash':'terms-hash','accepted':true,'sequence':1},
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
    await tester.scrollUntilVisible(find.text('Вводить номер и пароль'), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Вводить номер и пароль'));
    await tester.pumpAndSettle();
    FilledButton next() => tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'Продолжить'));
    await tester.scrollUntilVisible(find.widgetWithText(FilledButton, 'Продолжить'), 150, scrollable: find.byType(Scrollable).first);
    expect(next().onPressed, isNull);
    await tester.scrollUntilVisible(find.text('Принять эту версию'),-150,scrollable:find.byType(Scrollable).first);
    await tester.tap(find.text('Принять эту версию'));
    await tester.pumpAndSettle();
    expect(accepted, true);
    await tester.scrollUntilVisible(find.widgetWithText(FilledButton, 'Продолжить'), 150, scrollable: find.byType(Scrollable).first);
    expect(next().onPressed, isNotNull);
    final policy = find.ancestor(of:find.text('Утверждённая политика обработки данных'),matching:find.byType(DataCard));
    final withdraw = find.descendant(of:policy,matching:find.text('Отозвать согласие'));
    await tester.scrollUntilVisible(withdraw,-150,scrollable:find.byType(Scrollable).first);
    await tester.tap(withdraw);
    await tester.pumpAndSettle();
    expect(accepted, false);
    await tester.scrollUntilVisible(find.widgetWithText(FilledButton, 'Продолжить'), 150, scrollable: find.byType(Scrollable).first);
    expect(next().onPressed, isNull);
    await tester.pumpWidget(const SizedBox());
    api.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            null);
  });
  test(
      'File download never refreshes or returns an old account response after sign-in changes',
      () async {
    final pending = Completer<http.Response>(), started = Completer<void>();
    final calls = <String>[];
    final api = JobaApi('https://example.com', vault: MemoryVault(),
        transport: MockClient((request) async {
      calls.add(request.url.path);
      if (request.url.path.endsWith('/download')) {
        started.complete();
        return pending.future;
      }
      return ok({
        'access_token': 'new-access',
        'refresh_token': 'new-refresh',
        'user': {'id': 'new-user'}
      });
    }))
      ..session = {
        'access_token': 'old-access',
        'refresh_token': 'old-refresh',
        'user': {'id': 'old-user'}
      };
    final download = api.download('private-file');
    await started.future;
    final failed = expectLater(
        download,
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', 'SESSION_SUPERSEDED')));
    await api.signIn({
      'country': 'KZ',
      'phone': '+77011234567',
      'password': 'Different account password'
    });
    pending.complete(http.Response('', 401));
    await failed;
    expect(calls.where((path) => path.endsWith('/auth/refresh')), isEmpty);
    expect(api.session!['user']['id'], 'new-user');
    api.dispose();
  });
  testWidgets(
      'Photo loads a preview, opens an original in a zoom viewer, and hides it after logout',
      (tester) async {
    final bytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=');
    final variants = <String?>[];
    final api = JobaApi('https://example.com', vault: MemoryVault(),
        transport: MockClient((request) async {
      variants.add(request.url.queryParameters['variant']);
      return http.Response.bytes(bytes, 200,
          headers: {'content-type': 'image/png'});
    }))
      ..session = {
        'access_token': 'photo-access',
        'user': {'id': 'photo-owner'}
      };
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: PrivatePhoto(
                api: api,
                id: 'private-photo',
                gallery: const ['private-photo', 'second-photo'],
                caption: 'Настоящее название проекта'))));
    await tester.pumpAndSettle();
    expect(variants, ['preview']);
    await tester.tap(find.byType(Image));
    await tester.pumpAndSettle();
    expect(variants, ['preview', 'original']);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.text('1 из 2'), findsOneWidget);
    expect(
        tester
            .widget<IconButton>(find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == 'Предыдущее фото'))
            .onPressed,
        isNull);
    await tester.scrollUntilVisible(find.text('Увеличить'), 200,
        scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('Увеличить'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<InteractiveViewer>(find.byType(InteractiveViewer))
            .transformationController!
            .value
            .getMaxScaleOnAxis(),
        2);
    await tester.tap(find.byWidgetPredicate(
        (w) => w is IconButton && w.tooltip == 'Следующее фото'));
    await tester.pumpAndSettle();
    expect(find.text('2 из 2'), findsOneWidget);
    expect(variants, ['preview', 'original', 'original']);
    expect(
        tester
            .widget<IconButton>(find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == 'Следующее фото'))
            .onPressed,
        isNull);
    expect(
        tester
            .widget<InteractiveViewer>(find.byType(InteractiveViewer))
            .transformationController!
            .value
            .getMaxScaleOnAxis(),
        1);
    await api.forget();
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsNothing);
    expect(find.text('Настоящее название проекта'), findsNothing);
    expect(find.text('2 из 2'), findsNothing);
    await tester.tap(find.byTooltip('Закрыть'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    api.dispose();
  });
  test(
      'Archive download streams chunks and reports received bytes without buffering a response',
      () async {
    final api = JobaApi('https://example.com', vault: MemoryVault(),
        transport: MockClient.streaming((request, body) async {
      await body.drain<void>();
      return http.StreamedResponse(
          Stream.fromIterable([
            [1, 2],
            [3, 4]
          ]),
          200,
          contentLength: 4);
    }))
      ..session = {
        'access_token': 'stream-access',
        'user': {'id': 'stream-owner'}
      };
    final sink = RecordingSink(), progress = <List<int?>>[];
    await api.downloadToSink('archive', sink,
        onProgress: (bytes, total) => progress.add([bytes, total]));
    expect(sink.bytes, [1, 2, 3, 4]);
    expect(progress, [
      [2, 4],
      [4, 4]
    ]);
    api.dispose();
  });
  test('Archive stream stops before accepting a chunk after logout', () async {
    final controller = StreamController<List<int>>(), first = Completer<void>();
    var cancelled = false;
    controller.onCancel = () => cancelled = true;
    final api = JobaApi('https://example.com', vault: MemoryVault(),
        transport: MockClient.streaming((request, body) async {
      await body.drain<void>();
      return http.StreamedResponse(controller.stream, 200);
    }))
      ..session = {
        'access_token': 'stream-access',
        'user': {'id': 'stream-owner'}
      };
    final sink = RecordingSink(),
        download =
            api.downloadToSink('archive', sink, onProgress: (bytes, total) {
          if (!first.isCompleted) first.complete();
        });
    final rejected = expectLater(
        download,
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', 'SESSION_SUPERSEDED')));
    controller.add([1, 2]);
    await first.future;
    await api.forget();
    controller.add([3, 4]);
    await rejected;
    expect(sink.bytes, [1, 2]);
    expect(cancelled, true);
    await controller.close();
    api.dispose();
  });
}
