import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:services_marketplace/core/api.dart';
import 'package:services_marketplace/core/theme.dart';
import 'package:services_marketplace/screens/top_listings.dart';

class _Vault implements SessionVault {
  Future<String?> read() async => null;
  Future<void> write(String value) async {}
  Future<void> clear() async {}
}

void main() {
  testWidgets(
      'Top switches target and sort, filters real catalogs and toggles own vote',
      (tester) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final requests = <http.Request>[];
    int? mine;
    final api = JobaApi('https://isolated.example', vault: _Vault(),
        transport: MockClient((r) async {
      requests.add(r);
      dynamic data;
      if (r.url.path.contains('/listing-votes/')) {
        mine = r.method == 'DELETE' ? null : jsonDecode(r.body)['value'];
        data = {'value': mine};
      } else if (r.url.path.endsWith('/geo/cities')) {
        data = {
          'items': [
            {'id': 'city', 'name': 'Астана'}
          ]
        };
      } else {
        data = {
          'items': [
            {
              'id': 'listing',
              'title': 'Ремонт',
              'display_name': 'Алексей К.',
              'likes': mine == 1 ? 4 : 3,
              'dislikes': 0,
              'my_vote': mine
            }
          ]
        };
      }
      return http.Response(jsonEncode({'data': data}), 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    }));
    api.session = {
      'access_token': 'test-token',
      'refresh_token': 'test-refresh',
      'user': {'id': 'reader', 'country': 'KZ'}
    };
    await tester.pumpWidget(MaterialApp(
        theme: jobaTheme(),
        home: Scaffold(body: TopListings(api: api, onOpen: (_, __) {}))));
    await tester.pumpAndSettle();
    expect(find.text('Алексей К.'), findsOneWidget);
    await tester.tap(find.text('3'));
    await tester.pumpAndSettle();
    expect(requests.where((r) => r.method == 'PUT').single.url.path,
        endsWith('/listing-votes/services/listing'));
    await tester.tap(find.text('4'));
    await tester.pumpAndSettle();
    expect(requests.where((r) => r.method == 'DELETE').length, 1);
    await tester.tap(find.text('Заказы'));
    await tester.pumpAndSettle();
    expect(
        requests
            .lastWhere((r) => r.url.path.endsWith('/top-listings'))
            .url
            .queryParameters['target_type'],
        'orders');
    await tester.tap(find.text('Популярные'));
    await tester.pumpAndSettle();
    expect(
        requests
            .lastWhere((r) => r.url.path.endsWith('/top-listings'))
            .url
            .queryParameters['sort'],
        'new');
    await tester.tap(find.text('Все города'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Астана'));
    await tester.pumpAndSettle();
    expect(
        requests
            .lastWhere((r) => r.url.path.endsWith('/top-listings'))
            .url
            .queryParameters['city'],
        'Астана');
    expect(tester.takeException(), isNull);
  });
  testWidgets('an unavailable orders tab keeps services and filters reachable',
      (tester) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = JobaApi('https://isolated.example', vault: _Vault(),
        transport: MockClient((r) async {
      if (r.url.queryParameters['target_type'] == 'orders')
        return http.Response(
            jsonEncode({
              'error': {
                'code': 'VERIFICATION_REQUIRED',
                'message': 'Требуется проверка документа исполнителя'
              }
            }),
            403,
            headers: {'content-type': 'application/json; charset=utf-8'});
      return http.Response(
          jsonEncode({
            'data': {'items': []}
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    }));
    api.session = {
      'access_token': 'test-token',
      'user': {'id': 'reader', 'country': 'KZ'}
    };
    await tester.pumpWidget(MaterialApp(
        theme: jobaTheme(),
        home: Scaffold(body: TopListings(api: api, onOpen: (_, __) {}))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Заказы'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Требуется проверка документа исполнителя'),
        findsOneWidget);
    expect(find.text('Все города'), findsOneWidget);
    await tester.tap(find.text('Услуги'));
    await tester.pumpAndSettle();
    expect(find.text('По выбранным условиям пока нет объявлений.'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
