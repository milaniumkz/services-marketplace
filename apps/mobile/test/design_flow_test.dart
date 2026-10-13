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
import 'package:services_marketplace/main.dart';
import 'package:services_marketplace/screens/marketplace.dart';

class _Vault implements SessionVault {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String value) async {}
  @override
  Future<void> clear() async {}
}

http.Response _ok(dynamic data) =>
    http.Response(jsonEncode({'data': data, 'meta': {}}), 200,
        headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  testWidgets(
      'Design menus navigate, role changes persist, language failures retain selection, country changes require logout',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 43, bottom: 22);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final loader = FontLoader('Noto')
      ..addFont(rootBundle.load('assets/NotoSans-Regular.ttf'))
      ..addFont(rootBundle.load('assets/NotoSans-Bold.ttf'));
    await loader.load();
    final requests = <http.Request>[];
    var user = <String, dynamic>{
      'id': 'design-owner',
      'country': 'KZ',
      'city': 'Алматы',
      'display_name': 'Марина П.',
      'locale': 'ru',
      'languages': ['ru'],
      'roles': ['customer', 'executor'],
      'active_role': 'customer',
      'version': 1
    };
    var rejectLanguage = true;
    final api = JobaApi('https://example.com', vault: _Vault(),
        transport: MockClient((request) async {
      requests.add(request);
      final path = request.url.path;
      if (path.endsWith('/auth/logout')) return _ok({'logged_out': true});
      if (path.endsWith('/me')) {
        if (request.method == 'PATCH') {
          final change = jsonDecode(request.body) as Map<String, dynamic>;
          if (change['locale'] != null && rejectLanguage)
            return http.Response(
                jsonEncode({
                  'error': {
                    'code': 'STATE_CONFLICT',
                    'message': 'Профиль изменился. Повторите попытку.'
                  }
                }),
                409,
                headers: {'content-type': 'application/json; charset=utf-8'});
          user = {...user, ...change, 'version': user['version'] + 1};
        }
        return _ok(user);
      }
      if (path.endsWith('/me/overview'))
        return _ok({
          'orders': {'active': 3, 'open': 1},
          'assigned_orders': {'active': 2},
          'invitations': {'pending': 3},
          'rating': {'count': 7, 'average': 4.9},
          'contractor': {'status': 'published'}
        });
      if (path.endsWith('/catalog/categories'))
        return _ok({
          'items': [
            for (final entry in {
              'repair': 'Ремонт',
              'cleaning': 'Уборка',
              'transport': 'Перевозки',
              'beauty': 'Красота',
              'education': 'Обучение'
            }.entries)
              {
                'id': entry.key,
                'name': entry.value,
                'schema': {'properties': {}, 'required': []}
              }
          ]
        });
      if (path.endsWith('/me/contractor-profile'))
        return _ok({
          'profile': {
            'id': 'own-profile',
            'version': 1,
            'availability': 'available'
          }
        });
      if (path.endsWith('/me/sessions'))
        return _ok({
          'items': [
            {
              'family': 'active-session',
              'expires_at': '2026-12-01T12:00:00Z',
              'current': true
            }
          ]
        });
      if (path.endsWith('/contractors'))
        return _ok({
          'items': [
            {
              'id': 'contractor',
              'display_name': 'Алексей К.',
              'title': 'Ремонт и отделка',
              'description':
                  'Аккуратный ремонт без лишних хлопот. Берусь за небольшие и комплексные задачи.',
              'city': 'Алматы',
              'price': {'amount_min': 750000, 'currency': 'KZT'},
              'rating': {'average': 4.9, 'count': 32}
            }
          ]
        });
      if (path.endsWith('/orders'))
        return _ok({
          'items': [
            {
              'id': 'working-order',
              'title': 'Собрать кухню и подключить мойку',
              'description': 'Описание заказа из изолированной тестовой базы.',
              'status': 'open',
              'city': 'Алматы',
              'budget_amount': 4500000,
              'currency': 'KZT'
            }
          ]
        });
      return _ok({'items': []});
    }));
    final boundary = GlobalKey();
    await tester
        .pumpWidget(RepaintBoundary(key: boundary, child: JobaApp(api: api)));
    await tester.pumpAndSettle();
    final dynamic state = tester.state(find.byType(Marketplace));
    api.session = {
      'access_token': 'design-fixture',
      'refresh_token': 'design-refresh',
      'user': user
    };
    state.me = user;
    state.country = 'KZ';
    state.go('home');
    await tester.pumpAndSettle();
    Future<void> capture(String name) async {
      final dir = Platform.environment['JOBA_SCREENSHOT_DIR'];
      if (dir == null) return;
      await tester.runAsync(() async {
        final image = await (boundary.currentContext!.findRenderObject()
                as RenderRepaintBoundary)
            .toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(dir).create(recursive: true);
        await File('$dir/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    await capture('S06-home');
    expect(find.text('Какая услуга нужна?'), findsOneWidget);
    await tester.tap(find.text('Ремонт'));
    await tester.pumpAndSettle();
    expect(requests.last.url.queryParameters['category_id'], 'repair');
    expect(requests.last.url.queryParameters['city'], 'Алматы');
    state.go('home');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Заказчик'));
    await tester.pumpAndSettle();
    expect(user['active_role'], 'executor');
    expect(find.text('Найдём ваш\nследующий заказ'), findsOneWidget);
    await capture('S09-executor-home');
    await tester.tap(find.text('Профиль'));
    await tester.pumpAndSettle();
    await capture('S11-account');
    await tester.tap(find.text('Редактировать профиль'));
    await tester.pumpAndSettle();
    await capture('S04-profile-edit');
    await tester.enterText(find.byType(TextFormField).first, 'Марина Новая');
    await tester.tap(find.text('Сохранить профиль'));
    await tester.pumpAndSettle();
    expect(user['display_name'], 'Марина Новая');
    state.go('settings');
    await tester.pumpAndSettle();
    await capture('S35-settings');
    await tester.tap(find.text('Язык интерфейса'));
    await tester.pumpAndSettle();
    await capture('S35-languages');
    await tester.tap(find.text('Српски'));
    await tester.pump();
    await tester.tap(find.text('Сохранить выбор'));
    await tester.pumpAndSettle();
    expect(find.text('Профиль изменился. Повторите попытку.'), findsOneWidget);
    await tester.tap(find.text('Понятно'));
    await tester.pumpAndSettle();
    rejectLanguage = false;
    await tester.tap(find.text('Сохранить выбор'));
    await tester.pumpAndSettle();
    expect(user['locale'], 'sr');
    (state.widget as Marketplace).onLocaleChanged?.call('ru');
    state.locale = 'ru';
    state.go('country');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сербия'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(state.country, 'KZ');
    expect(requests.where((r) => r.url.path.endsWith('/auth/logout')), isEmpty);
    await tester.tap(find.text('Сербия'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Продолжить'));
    await tester.pumpAndSettle();
    expect(state.country, 'RS');
    expect(api.authenticated, false);
    expect(user['country'], 'KZ');
    api.session = {
      'access_token': 'second-isolated-session',
      'refresh_token': 'refresh',
      'user': user
    };
    state.me = user;
    state.country = 'KZ';
    state.go('security');
    await tester.pumpAndSettle();
    await capture('S15-security');
    state.go('sessions');
    await tester.pumpAndSettle();
    await capture('S15-sessions');
    await tester.tap(find.text('Завершить сессию'));
    await tester.pumpAndSettle();
    expect(api.authenticated, false);
    expect(
        requests.any((r) =>
            r.method == 'DELETE' &&
            r.url.path.endsWith('/me/sessions/active-session')),
        true);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    api.dispose();
  });
}
