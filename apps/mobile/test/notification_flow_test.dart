import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:services_marketplace/core/api.dart';
import 'package:services_marketplace/main.dart';
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
    expect(find.text('Прочитано'), findsOneWidget);
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
