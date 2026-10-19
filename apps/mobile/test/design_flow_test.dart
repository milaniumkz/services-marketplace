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
    final material = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await material.load();
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
    var rejectInvitation = true;
    final api = JobaApi('https://example.com', vault: _Vault(),
        transport: MockClient((request) async {
      requests.add(request);
      final path = request.url.path;
      if (path.endsWith('/referrals/attribute'))
        return _ok({'status': 'pending'});
      if (path.endsWith('/me/referrals'))
        return _ok({
          'code': 'isolated-code-37',
          'campaigns': [
            {
              'threshold': 2,
              'reward_duration_seconds': 3600,
              'qualifying_event': 'completed_order'
            }
          ],
          'attributions': [
            {'status': 'pending'},
            {'status': 'qualified'}
          ],
          'rewards': []
        });
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
      if (path.endsWith('/geo/cities'))
        return _ok({
          'items': [
            {'id': 'almaty', 'name': 'Алматы', 'country': 'KZ'},
            {'id': 'astana', 'name': 'Астана', 'country': 'KZ'}
          ]
        });
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
      if (path.endsWith('/me/cases/overview'))
        return _ok({'open': 1, 'resolved': 1});
      if (path.endsWith('/me/cases'))
        return _ok({
          'items': [
            {
              'id': request.url.queryParameters['bucket'] == 'resolved'
                  ? 'resolved-case'
                  : 'created-case',
              'status': request.url.queryParameters['bucket'] == 'resolved'
                  ? 'resolved'
                  : 'new',
              'reason_code': 'unsafe',
              'description': 'Описание конкретной проблемы в работе.'
            }
          ]
        });
      if (path.endsWith('/cases') && request.method == 'POST')
        return _ok({
          'id': 'created-case',
          'status': 'new',
          ...jsonDecode(request.body)
        });
      if (path.endsWith('/cases/created-case'))
        return _ok({
          'id': 'created-case',
          'status': 'new',
          'reason_code': 'unsafe',
          'description': 'Описание конкретной проблемы в работе.'
        });
      if (path.endsWith('/contractors/contractor'))
        return _ok({
          'id': 'contractor',
          'display_name': 'Алексей К.',
          'title': 'Ремонт и отделка'
        });
      if (path.endsWith('/orders/working-order/invites') && rejectInvitation) {
        rejectInvitation = false;
        return http.Response(
            jsonEncode({
              'error': {
                'code': 'TEMPORARILY_UNAVAILABLE',
                'message': 'Повторите попытку.'
              }
            }),
            503,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }
      if(path.endsWith('/orders/working-order/invites'))return _ok({'id':'sent-invite','order_id':'working-order','status':'pending'});
      if(path.endsWith('/order-invites/sent-invite'))return _ok({'id':'sent-invite','order_id':'working-order','status':'pending'});
      if (path.endsWith('/me/order-invites'))
        return _ok({
          'items': [
            {
              'id': 'incoming-invite',
              'order_id': 'invited-order',
              'version': 1,
              'status': 'pending',
              'created_at': '2026-10-13T09:10:00Z',
              'expires_at': '2026-10-16T09:10:00Z',
              'customer': {'display_name': 'Марина П.'},
              'order': {
                'title': 'Обновить стены в гостиной',
                'city': 'Алматы',
                'budget_amount': 8000000,
                'currency': 'KZT'
              }
            }
          ]
        });
      if (path.endsWith('/orders/invited-order'))
        return _ok({
          'id': 'invited-order',
          'title': 'Обновить стены в гостиной',
          'revision': 1,
          'status': 'open',
          'version': 1
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
    await tester.tap(find.text('Алматы, Казахстан'));
    await tester.pumpAndSettle();
    expect(find.text('Где искать?'), findsOneWidget);
    await tester.tap(find.text('Астана'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Выбрать Астана'));
    await tester.pumpAndSettle();
    expect(user['city'], 'Астана');
    state.me = {...user, 'city': 'Алматы'};
    user = {...user, 'city': 'Алматы'};
    state.go('home');
    await tester.pumpAndSettle();

    expect(find.text('Какая услуга нужна?'), findsOneWidget);
    await tester.tap(find.text('Ремонт'));
    await tester.pumpAndSettle();
    expect(requests.last.url.queryParameters['category_id'], 'repair');
    expect(requests.last.url.queryParameters['city'], 'Алматы');
    state.go('home');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Заказчик'));
    await tester.pumpAndSettle();
    expect(find.text('Моя роль'), findsOneWidget);
    await capture('S11-roles');
    await tester.tap(find.text('Исполнитель'));
    await tester.pumpAndSettle();
    expect(user['active_role'], 'executor');
    expect(find.text('Найдём ваш\nследующий заказ'), findsOneWidget);
    await capture('S09-executor-home');
    state.go('invite', 'contractor');
    await tester.pumpAndSettle();
    expect(requests.last.url.queryParameters['bucket'], 'open');
    await tester.tap(find.text('Собрать кухню и подключить мойку'));
    await tester.enterText(find.byType(TextField), 'Подойдут ли вам сроки?');
    await capture('S19-invite');
    await tester.tap(find.text('Отправить приглашение'));
    await tester.pumpAndSettle();
    expect(state.route, 'invite');
    expect(find.text('Подойдут ли вам сроки?'), findsOneWidget);
    await tester.tap(find.text('Отправить приглашение'));
    await tester.pumpAndSettle();
    final sentInvites = requests
        .where((r) => r.url.path.endsWith('/orders/working-order/invites'))
        .toList();
    expect(sentInvites.length, 2);
    expect(
        jsonDecode(sentInvites.last.body)['message'], 'Подойдут ли вам сроки?');
    expect(state.route, 'invited');
    expect(find.text('Приглашение\nотправлено'), findsOneWidget);

    state.reportObject('contractor', 'contractor');
    await tester.pumpAndSettle();
    await capture('S29-report');
    await tester.enterText(find.byType(TextFormField).first,
        'Описание конкретной проблемы в работе.');
    await tester.ensureVisible(find.text('Небезопасное поведение'));
    await tester.tap(find.text('Небезопасное поведение'));
    await tester.pumpAndSettle();
    expect(find.text('Описание конкретной проблемы в работе.'), findsOneWidget);
    await capture('S29-report-filled');
    await tester.tap(find.text('Отправить обращение'));
    await tester.pumpAndSettle();
    final complaint = requests
        .firstWhere((r) => r.url.path.endsWith('/cases') && r.method == 'POST');
    expect(jsonDecode(complaint.body)['target_type'], 'contractor');
    expect(jsonDecode(complaint.body)['reason_code'], 'unsafe');
    expect(state.route, 'case');
    expect(state.objectId, 'created-case');
    state.go('cases');
    await tester.pumpAndSettle();
    await capture('S30-cases');
    await tester.tap(find.text('Решённые · 1'));
    await tester.pumpAndSettle();
    expect(requests.last.url.queryParameters['bucket'], 'resolved');
    expect(find.text('Решено'), findsOneWidget);
    await tester.tap(find.text('Новое обращение'));
    await tester.pumpAndSettle();
    expect(state.route, 'support');

    state.go('invitations');
    await tester.pumpAndSettle();
    expect(find.text('Обновить стены в гостиной'), findsOneWidget);
    expect(find.text('Марина П.'), findsOneWidget);
    await capture('S20-invitations');
    await tester.tap(find.text('Ответить'));
    await tester.pumpAndSettle();
    final invitationResponse = requests.firstWhere(
        (r) => r.url.path.endsWith('/order-invites/incoming-invite/respond'));
    expect(jsonDecode(invitationResponse.body)['decision'], 'accept');
    expect(state.route, 'offer');
    expect(state.objectId, 'invited-order');
    state.go('executor-home');
    await tester.pumpAndSettle();

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
    await tester.tap(find.text('Кыргызстан'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(state.country, 'KZ');
    expect(requests.where((r) => r.url.path.endsWith('/auth/logout')), isEmpty);
    await tester.tap(find.text('Кыргызстан'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Продолжить'));
    await tester.pumpAndSettle();
    expect(state.country, 'KG');
    expect(api.authenticated, false);
    expect(user['country'], 'KZ');
    api.session = {
      'access_token': 'second-isolated-session',
      'refresh_token': 'refresh',
      'user': user
    };
    state.me = user;
    state.country = 'KZ';
    state.go('referrals');
    await tester.pumpAndSettle();
    expect(find.text('isolated-code-37'), findsOneWidget);
    await capture('S37-referrals');
    await tester.scrollUntilVisible(find.text('Как начисляются бонусы'), 150,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Как начисляются бонусы'));
    await tester.pumpAndSettle();
    expect(find.text('Как получить бонус'), findsOneWidget);
    expect(find.textContaining('60'), findsWidgets);
    await capture('S37-rules');
    state.go('referrals');
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('У меня есть код'), 150,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('У меня есть код'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'other-isolated-code');
    await tester.tap(find.text('Проверить код'));
    await tester.pumpAndSettle();
    final attributed = requests.lastWhere(
        (request) => request.url.path.endsWith('/referrals/attribute'));
    expect(jsonDecode(attributed.body)['code'], 'other-isolated-code');

    state.go('security');
    await tester.pumpAndSettle();
    await capture('S15-security');
    state.go('sessions');
    await tester.pumpAndSettle();
    await capture('S15-sessions');
    expect(find.text('Завершить сеанс'), findsNothing);
    state.go('revoke-session', 'active-session');
    await tester.pumpAndSettle();
    expect(api.authenticated, true);
    expect(requests.any((r) => r.method == 'DELETE' && r.url.path.endsWith('/me/sessions/active-session')), false);
    await tester.tap(find.text('Завершить сеанс'));
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
