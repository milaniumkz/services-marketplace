import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:services_marketplace/core/api.dart';
import 'package:services_marketplace/main.dart';
import 'package:services_marketplace/screens/notification_widgets.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:services_marketplace/screens/marketplace.dart';

class Vault implements SessionVault {
  Future<String?> read() async => null;
  Future<void> write(String value) async {}
  Future<void> clear() async {}
}

http.Response ok(dynamic data) => http.Response(jsonEncode({'data': data}), 200,
    headers: {'content-type': 'application/json; charset=utf-8'});
const owner = {
  'id': 'owner',
  'country': 'KZ',
  'locale': 'ru',
  'roles': ['customer'],
  'active_role': 'customer'
};
Future<dynamic> open(WidgetTester t, JobaApi api) async {
  await t.pumpWidget(JobaApp(api: api));
  await t.pumpAndSettle();
  final dynamic state = t.state(find.byType(Marketplace));
  api.session = {'access_token': 'first', 'user': owner};
  state.me = owner;
  state.go('notifications');
  await t.pumpAndSettle();
  return state;
}

void main() {
  setUpAll(() => initializeDateFormatting());

  testWidgets(
      'confirmed read updates the counter when its object is unavailable',
      (t) async {
    const id = '321e4567-e89b-42d3-a456-426614174000';
    final api = JobaApi('https://isolated.example', vault: Vault(),
        transport: MockClient((r) async {
      if (r.url.path.endsWith('/notice/read')) return ok({'read': true});
      if (r.url.path.endsWith('/offers/$id'))
        return http.Response(
            jsonEncode({
              'error': {'code': 'NOT_FOUND', 'message': 'Not found'}
            }),
            404);
      return ok({
        'items': [
          {
            'id': 'notice',
            'title': 'Event',
            'read': false,
            'deep_link': {'route': 'offer', 'id': id}
          }
        ],
        'meta': {'unread_count': 1, 'read_before': '2026-10-19T10:00:00.000Z'}
      });
    }));
    addTearDown(api.dispose);
    await open(t, api);
    await t.tap(find.text('Event'));
    await t.pumpAndSettle();
    await t.tap(find.text('Понятно'));
    await t.pumpAndSettle();
    expect(find.text('Новое'), findsNothing);
    expect(find.text(' (0)'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('refresh replaces the read-all watermark', (t) async {
    var revision = 0;
    String? before;
    final api = JobaApi('https://isolated.example', vault: Vault(),
        transport: MockClient((r) async {
      if (r.url.path.endsWith('/read-all')) {
        before = jsonDecode(r.body)['before'];
        return ok({'read': true});
      }
      if (r.url.path.endsWith('/me/notifications'))
        return ok({
          'items': [
            {'id': 'notice', 'title': 'Event', 'type': 'other', 'read': false}
          ],
          'meta': {
            'read_before': revision == 0
                ? '2026-10-19T10:00:00.000Z'
                : '2026-10-19T10:01:00.000Z'
          }
        });
      return ok({});
    }));
    addTearDown(api.dispose);
    await open(t, api);
    revision = 1;
    await t.fling(find.byType(ListView), const Offset(0, 400), 1000);
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Прочитать все'));
    await t.pumpAndSettle();
    expect(before, '2026-10-19T10:01:00.000Z');
    await t.pumpWidget(const SizedBox());
  });

  for (final entry in {
    'offer.created': 'offers',
    'order.completion_requested': 'complete',
    'support.message.created': 'support-chat',
    'verification.updated': 'verification',
    'subscription.updated': 'my-access',
    'portfolio.published': 'portfolio-project'
  }.entries) {
    testWidgets('notification ${entry.key} opens its actual route', (t) async {
      const id = '321e4567-e89b-42d3-a456-426614174000';
      var reads = 0;
      final pending = Completer<http.Response>();
      final api = JobaApi('https://isolated.example', vault: Vault(),
          transport: MockClient((r) async {
        if (r.url.path.endsWith('/me/notifications'))
          return ok({
            'items': [
              {
                'id': 'notice',
                'title': 'Event',
                'type': entry.key,
                'read': false,
                'target_id': id
              }
            ]
          });
        if (r.url.path.endsWith('/notice/read')) {
          reads++;
          return ok({'read': true});
        }
        if (r.url.path.endsWith('/me'))
          return ok({...owner, 'verification': 'passed', 'version': 1});
        return pending.future;
      }));
      addTearDown(api.dispose);
      final state = await open(t, api);
      await t.tap(find.text('Event'));
      for (var i = 0; i < 20 && state.route == 'notifications'; i++)
        await t.pump();
      expect(reads, 1);
      expect(state.route, entry.value);
      if (['offers', 'complete', 'support-chat', 'portfolio-project']
          .contains(entry.value)) expect(state.objectId, id);
      if (entry.value == 'my-access')
        expect(find.text('Для заказчика бесплатно'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      pending.complete(ok({}));
      await t.pumpAndSettle();
    });
  }
  testWidgets('notification groups remain usable with enlarged text at 320px',
      (t) async {
    t.view.physicalSize = const Size(320, 740);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final now = DateTime.utc(2026, 10, 19);
    String? settings;
    await t.pumpWidget(MaterialApp(
        builder: (c, child) => MediaQuery(
            data: MediaQuery.of(c)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!),
        home: Scaffold(
            body: Column(children: [
          NotificationHeader(
              category: 'all',
              onCategory: (_) {},
              onSettings: () => settings = 'open'),
          Expanded(
              child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: NotificationGroups(
                      now: now,
                      rows: [
                        {
                          'id': 'event',
                          'type': 'offer.created',
                          'title':
                              'Очень длинное уведомление о новом отклике исполнителя',
                          'body':
                              'Описание события с дополнительными подробностями',
                          'created_at': now.toIso8601String(),
                          'read': false
                        }
                      ],
                      title: (r) => r['title'],
                      onOpen: (_) {})))
        ]))));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await t.tap(find.byTooltip('Настройки уведомлений'));
    expect(settings, 'open');
    await t.pumpWidget(const SizedBox());
  });
  testWidgets(
      'notification tabs query the API and settings open from the header',
      (t) async {
    final categories = <String>[];
    final api = JobaApi('https://isolated.example', vault: Vault(),
        transport: MockClient((r) async {
      if (r.url.path.endsWith('/me/notifications')) {
        final category = r.url.queryParameters['category'] ?? 'all';
        categories.add(category);
        return ok({
          'items': [
            {'id': category, 'title': 'Event $category', 'read': true}
          ],
          'meta': {'read_before': '2026-10-19T10:00:00.000Z', 'unread_count': 3}
        });
      }
      if (r.url.path.endsWith('/me')) return ok({...owner, 'version': 1});
      return ok({});
    }));
    addTearDown(api.dispose);
    final state = await open(t, api);
    expect(find.text('Event all'), findsOneWidget);
    await t.tap(find.text('Заказы'));
    await t.pumpAndSettle();
    expect(find.text('Event orders'), findsOneWidget);
    expect(find.text('Event all'), findsNothing);
    await t.tap(find.text('Аккаунт'));
    await t.pumpAndSettle();
    expect(find.text('Event account'), findsOneWidget);
    await t.tap(find.text('Все'));
    await t.pumpAndSettle();
    expect(categories, ['all', 'orders', 'account', 'all']);
    await t.tap(find.byTooltip('Настройки уведомлений'));
    await t.pumpAndSettle();
    expect(state.route, 'notification-settings');
    await t.tap(find.byTooltip('Назад'));
    await t.pumpAndSettle();
    await t.tap(find.text('Аккаунт'));
    await t.pumpAndSettle();
    await api.forget();
    await t.pumpAndSettle();
    expect(state.notificationCategory, 'all');
    await t.pumpWidget(const SizedBox());
  });

  testWidgets(
      'read all retains the displayed watermark through failure and retries',
      (t) async {
    const watermark = '2026-10-19T10:00:00.000Z';
    final posts = <http.Request>[];
    var read = false;
    final api = JobaApi('https://isolated.example', vault: Vault(),
        transport: MockClient((r) async {
      if (r.url.path.endsWith('/read-all')) {
        posts.add(r);
        if (posts.length == 1)
          return http.Response(
              jsonEncode({
                'error': {'code': 'TEMPORARY_FAILURE', 'message': 'Retry'}
              }),
              503);
        read = true;
        return ok({'read': true});
      }
      return ok({
        'items': [
          {'id': 'notice', 'title': 'Notice', 'type': 'isolated', 'read': read}
        ],
        'meta': {'read_before': watermark, 'unread_count': read ? 0 : 1}
      });
    }));
    addTearDown(api.dispose);
    final state = await open(t, api);
    api.serverTime = '2040-01-01T00:00:00Z';
    await t.tap(find.byTooltip('Прочитать все'));
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await t.tap(find.text('Понятно'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Прочитать все'));
    await t.pumpAndSettle();
    expect(posts.length, 2);
    for (final post in posts)
      expect(jsonDecode(post.body), {'before': watermark});
    expect(posts[0].headers['idempotency-key'],
        posts[1].headers['idempotency-key']);
    expect(find.text('Новое'), findsNothing);
    expect(find.text('Notice'), findsOneWidget);
    expect(state.route, 'notifications');
    await t.pumpWidget(const SizedBox());
  });
  for (final stage in ['read', 'offer']) {
    testWidgets(
        'late notification $stage result cannot navigate another account',
        (t) async {
      const id = '321e4567-e89b-42d3-a456-426614174000';
      final pending = Completer<http.Response>();
      var offerReads = 0;
      final api = JobaApi('https://isolated.example', vault: Vault(),
          transport: MockClient((r) async {
        if (r.url.path.endsWith('/notice/read'))
          return stage == 'read' ? pending.future : ok({});
        if (r.url.path.endsWith('/offers/$id')) {
          offerReads++;
          return pending.future;
        }
        return ok({
          'items': [
            {
              'id': 'notice',
              'title': 'Notice',
              'read': false,
              'deep_link': {'route': 'offer', 'id': id}
            }
          ]
        });
      }));
      addTearDown(api.dispose);
      final state = await open(t, api);
      await t.tap(find.text('Notice'));
      await t.pump();
      await t.pump();
      api.session = {
        'access_token': 'second',
        'user': {'id': 'replacement'}
      };
      pending.complete(ok({'order_id': id}));
      await t.pumpAndSettle();
      expect(state.route, 'notifications');
      expect(offerReads, stage == 'read' ? 0 : 1);
      expect(find.byType(AlertDialog), findsNothing);
      await t.pumpWidget(const SizedBox());
    });
  }
}
