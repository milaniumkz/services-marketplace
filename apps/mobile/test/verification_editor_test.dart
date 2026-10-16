import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:services_marketplace/core/api.dart';
import 'package:services_marketplace/core/theme.dart';
import 'package:services_marketplace/core/design_icons.dart';
import 'package:services_marketplace/screens/verification_editor.dart';

class Vault implements SessionVault {
  Future<String?> read() async => null;
  Future<void> write(String value) async {}
  Future<void> clear() async {}
}

http.Response ok(dynamic data) =>
    http.Response(jsonEncode({'data': data, 'meta': {}}), 200,
        headers: {'content-type': 'application/json; charset=utf-8'});
void main() {
  testWidgets(
      'verification keeps both page uploads after failure and sends only the selected session',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 43, bottom: 22);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final font = FontLoader('Noto')
      ..addFont(rootBundle.load('assets/NotoSans-Regular.ttf'))
      ..addFont(rootBundle.load('assets/NotoSans-Bold.ttf'));
    await font.load();
    final material = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await material.load();
    var pending = false, fail = true, picks = 0, terms = 0;
    final submissions = <Json>[];
    final api = JobaApi('https://isolated.example', vault: Vault(),
        transport: MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/me/verification'))
        return ok({
          'status': pending ? 'pending_review' : 'not_started',
          'policy': {
            'id': 'policy',
            'version': 1,
            'document_id': 'legal',
            'document_types': ['id_card', 'passport'],
            'required_pages': {
              'id_card': ['Лицевая сторона', 'Оборотная сторона'],
              'passport': ['Страница с данными']
            },
            'consent_accepted': false
          },
          'items': pending
              ? [
                  {
                    'id': 'check',
                    'status': 'pending_review',
                    'document_type': 'id_card',
                    'created_at': '2026-01-01'
                  }
                ]
              : []
        });
      if (path.endsWith('/legal/documents'))
        return ok({
          'items': [
            {'id': 'legal', 'hash': 'legal-hash'}
          ]
        });
      if (path.endsWith('/me/consents')) return ok({'accepted': true});
      if (path.endsWith('/me/verification-sessions'))
        return ok({
          'id': 'check',
          'version': 1,
          'policy_id': 'policy',
          'policy_version': 1,
          'status': 'draft',
          'document_type': 'id_card',
          'required_pages': ['Лицевая сторона', 'Оборотная сторона']
        });
      if (path.endsWith('/submit')) {
        submissions.add(jsonDecode(request.body) as Json);
        if (fail) {
          fail = false;
          return http.Response(
              jsonEncode({
                'error': {
                  'code': 'TEMPORARY_FAILURE',
                  'message': 'Повторите отправку',
                  'retryable': true
                }
              }),
              503);
        }
        pending = true;
        return ok({'status': 'pending_review'});
      }
      throw StateError('Unexpected $path');
    }));
    api.session = {
      'access_token': 'isolated-token',
      'refresh_token': 'isolated-refresh',
      'user': {'id': 'owner', 'country': 'KZ'}
    };
    addTearDown(api.dispose);
    final uploads = <String, List<String>>{};
    await tester.pumpWidget(MaterialApp(
        theme: jobaTheme(),
        home: RepaintBoundary(
            key: const ValueKey('capture'),
            child: Scaffold(
                backgroundColor: canvas,
                appBar: AppBar(
                    leading: IconButton(
                        onPressed: () {}, icon: const JobaIcon('back')),
                    title: const Text('Проверка исполнителя')),
                body: VerificationEditor(
                    api: api,
                    country: 'KZ',
                    uploads: uploads,
                    pick: (id) async {
                      expect(id, 'check');
                      return {'id': 'photo-${++picks}'};
                    },
                    onTerms: () => terms++,
                    onProfile: () {},
                    onSupport: () {})))));
    await tester.pumpAndSettle();
    expect(find.text('Подтвердите документ'), findsOneWidget);
    final destination = Platform.environment['JOBA_SCREENSHOT_DIR'];
    if (destination != null) {
      await tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('capture')));
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(destination).create(recursive: true);
        await File('$destination/S13-verification.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.scrollUntilVisible(find.byType(CheckboxListTile), 200);
    await tester.drag(find.byType(ListView), const Offset(0, -180));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Лицевая сторона'), -150);
    await tester.tap(find.text('Лицевая сторона'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Оборотная сторона'), 100);
    await tester.tap(find.text('Оборотная сторона'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Условия проверки'), 150);
    await tester.drag(find.byType(ListView), const Offset(0, -100));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Условия проверки'));
    expect(terms, 1);
    expect(picks, 2);
    await tester.tap(find.text('Отправить на проверку'));
    await tester.pumpAndSettle();
    expect(uploads['check'], ['photo-1', 'photo-2']);
    expect(submissions.length, 1);
    await tester.tap(find.text('Отправить на проверку'));
    await tester.pumpAndSettle();
    expect(submissions.length, 2);
    expect(submissions[0]['upload_ids'], submissions[1]['upload_ids']);
    expect(picks, 2);
    expect(uploads, isEmpty);
    expect(find.text('Проверяем документ'), findsOneWidget);
  });
  testWidgets(
      'verification refreshes an open pending screen after a result event',
      (tester) async {
    var passed = false;
    final revision = ValueNotifier(0);
    addTearDown(revision.dispose);
    final api = JobaApi('https://isolated.example',
        vault: Vault(),
        transport: MockClient((request) async => ok({
              'status': passed ? 'passed' : 'pending_review',
              'policy': null,
              'items': [
                {
                  'id': 'check',
                  'status': passed ? 'passed' : 'pending_review',
                  'document_type': 'passport',
                  'created_at': '2026-01-01',
                  'decided_at': passed ? '2026-10-14T10:00:00Z' : null,
                  'expires_at': passed ? '2027-10-14T10:00:00Z' : null
                }
              ]
            })));
    api.session = {
      'access_token': 'isolated-token',
      'user': {'id': 'owner', 'country': 'KZ'}
    };
    addTearDown(api.dispose);
    await tester.pumpWidget(MaterialApp(
        theme: jobaTheme(),
        home: Scaffold(
            body: ValueListenableBuilder<int>(
                valueListenable: revision,
                builder: (context, value, child) => VerificationEditor(
                    api: api,
                    country: 'KZ',
                    revision: value,
                    uploads: {},
                    pick: (id) async => null,
                    onTerms: () {},
                    onProfile: () {},
                    onSupport: () {})))));
    await tester.pumpAndSettle();
    expect(find.text('Проверяем документ'), findsOneWidget);
    passed = true;
    revision.value++;
    await tester.pumpAndSettle();
    expect(find.text('Документ проверен'), findsOneWidget);
    expect(find.text('Проверяем документ'), findsNothing);
    expect(find.text('Следующая проверка'), findsOneWidget);
  });

  testWidgets(
      'changing document type isolates uploads and withdrawing consent reaches the API',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final consents = <bool>[], submissions = <Json>[];
    final api = JobaApi('https://isolated.example', vault: Vault(),
        transport: MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/me/verification'))
        return ok({
          'status': 'not_started',
          'policy': {
            'id': 'policy',
            'version': 1,
            'document_id': 'legal',
            'document_types': ['id_card', 'passport'],
            'required_pages': {
              'id_card': ['Лицевая сторона', 'Оборотная сторона'],
              'passport': ['Страница с данными']
            },
            'consent_accepted': true
          },
          'items': [
            {
              'id': 'old-id-card',
              'version': 1,
              'policy_id': 'policy',
              'policy_version': 1,
              'status': 'draft',
              'document_type': 'id_card',
              'required_pages': ['Лицевая сторона', 'Оборотная сторона'],
              'created_at': '2026-01-01'
            }
          ]
        });
      if (path.endsWith('/legal/documents'))
        return ok({
          'items': [
            {'id': 'legal', 'hash': 'legal-hash'}
          ]
        });
      if (path.endsWith('/me/consents')) {
        consents.add(jsonDecode(request.body)['accepted']);
        return ok({'accepted': consents.last});
      }
      if (path.endsWith('/me/verification-sessions')) {
        expect(jsonDecode(request.body)['document_type'], 'passport');
        return ok({
          'id': 'new-passport',
          'version': 1,
          'policy_id': 'policy',
          'policy_version': 1,
          'status': 'draft',
          'document_type': 'passport',
          'required_pages': ['Страница с данными']
        });
      }
      if (path.endsWith('/new-passport/submit')) {
        submissions.add(jsonDecode(request.body) as Json);
        return ok({'status': 'pending_review'});
      }
      throw StateError('Unexpected $path');
    }));
    api.session = {
      'access_token': 'isolated-token',
      'user': {'id': 'owner', 'country': 'KZ'}
    };
    addTearDown(api.dispose);
    final uploads = <String, List<String>>{
      'old-id-card': ['old-front', 'old-back']
    };
    await tester.pumpWidget(MaterialApp(
        theme: jobaTheme(),
        home: Scaffold(
            body: VerificationEditor(
                api: api,
                country: 'KZ',
                uploads: uploads,
                pick: (id) async {
                  expect(id, 'new-passport');
                  return {'id': 'passport-photo'};
                },
                onTerms: () {},
                onProfile: () {},
                onSupport: () {}))));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byType(CheckboxListTile), 200);
    await tester.drag(find.byType(ListView), const Offset(0, -180));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    expect(consents, [false]);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Паспорт'), -150);
    await tester.tap(find.text('Паспорт'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Добавить фотографии'), 100);
    await tester.tap(find.text('Добавить фотографии'));
    await tester.pumpAndSettle();
    expect(consents, [false, true]);
    expect(uploads['old-id-card'], ['old-front', 'old-back']);
    await tester.tap(find.text('Отправить на проверку'));
    await tester.pumpAndSettle();
    expect(submissions.single['upload_ids'], ['passport-photo']);
  });
}
