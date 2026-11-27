import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:services_marketplace/core/api.dart';
import 'package:services_marketplace/core/theme.dart';
import 'package:services_marketplace/core/widgets.dart';

class _Vault implements SessionVault {
  Future<String?> read() async => null;
  Future<void> write(String value) async {}
  Future<void> clear() async {}
}

void main() {
  testWidgets(
      'search transitions through loading, retry, empty, filters and actual query results without hiding access errors',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final initial = Completer<http.Response>();
    final requests = <http.Request>[];
    var first = true, created = false;
    http.Response ok(dynamic data) =>
        http.Response(jsonEncode({'data': data, 'meta': {}}), 200,
            headers: {'content-type': 'application/json; charset=utf-8'});
    final api = JobaApi('https://isolated.example', vault: _Vault(),
        transport: MockClient((request) async {
      requests.add(request);
      if (request.url.path.endsWith('/contractors')) {
        if (first) {
          first = false;
          return initial.future;
        }
        if (request.url.queryParameters['q'] == 'restricted')
          return http.Response(
              '{"error":{"code":"ENTITLEMENT_REQUIRED"}}', 403);
        return ok({
          'items': request.url.queryParameters['q'] == 'ремонт'
              ? [
                  {
                    'id': 'isolated-result',
                    'title': 'Изолированная найденная услуга'
                  }
                ]
              : []
        });
      }
      return ok({'items': []});
    }))
      ..session = {
        'access_token': 'isolated-token',
        'user': {'country': 'KZ'}
      };
    addTearDown(api.dispose);
    await tester.pumpWidget(MaterialApp(
        theme: jobaTheme(),
        home: Scaffold(
            appBar: AppBar(title: const Text('Специалисты')),
            body: SearchListings(
                api: api,
                path: '/contractors',
                tile: (row) => Text(row['title']),
                onCreate: () => created = true))));
    await tester.pumpAndSettle();
    expect(find.text('Загружаем специалистов…'), findsOneWidget);
    initial.complete(http.Response('{"error":{"code":"SERVER_ERROR"}}', 500));
    await tester.pumpAndSettle();
    expect(find.text('Попробуем ещё раз?'), findsOneWidget);
    await tester.tap(find.text('Повторить'));
    await tester.pumpAndSettle();
    expect(find.text('Пока никого не нашли'), findsOneWidget);
    await tester.ensureVisible(find.text('Создать заказ'));
    await tester.tap(find.text('Создать заказ'));
    expect(created, true);
    await tester.ensureVisible(find.text('Изменить фильтры'));
    await tester.tap(find.text('Изменить фильтры'));
    await tester.pumpAndSettle();
    expect(find.text('Фильтры'), findsOneWidget);
    final query = find.byKey(const ValueKey('search-filter-query'));
    await tester.scrollUntilVisible(query, 300,
        scrollable: find.byType(Scrollable).first);
    await tester.enterText(query, 'ремонт');
    await tester.tap(find.text('Показать специалистов'));

    await tester.pumpAndSettle();
    expect(find.text('Изолированная найденная услуга'), findsOneWidget);
    expect(
        requests
            .lastWhere((r) => r.url.path.endsWith('/contractors'))
            .url
            .queryParameters['q'],
        'ремонт');
    await tester.enterText(find.byType(TextField), 'restricted');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.textContaining('Нужен действующий доступ'), findsOneWidget);
    expect(find.text('Попробуем ещё раз?'), findsNothing);
  });
}
