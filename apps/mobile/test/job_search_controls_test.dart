import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
      'job search offers city/category/GPS, retains text and clears stale city when using GPS',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final requests = <http.Request>[];
    Json savedFilters = {};
    final api = JobaApi('https://isolated.example', vault: _Vault(),
        transport: MockClient((r) async {
      requests.add(r);
      return http.Response(
          jsonEncode({
            'data': {'items': []}
          }),
          200);
    }))
      ..session = {
        'access_token': 'isolated-token',
        'user': {'country': 'KZ'}
      };
    addTearDown(api.dispose);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('joba.location'),
            (call) async => {'latitude': 49.8, 'longitude': 73.1});
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('joba.location'), null));
    await tester.pumpWidget(MaterialApp(
        theme: jobaTheme(),
        home: Scaffold(
            body: SearchListings(
                api: api,
                path: '/orders',
                onFiltersChanged: (value) => savedFilters = value,
                    initialFilters: {'city': 'Караганда', 'category_id': 'plaster'},
                tile: (r) => Text(r['title'])))));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Фильтры'), findsNothing);
    expect(find.text('Рядом со мной'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'штукатурка');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Рядом со мной'));
    await tester.pumpAndSettle();
    final query = requests
        .lastWhere((r) => r.url.path.endsWith('/orders'))
        .url
        .queryParameters;
    expect(query['q'], 'штукатурка');
    expect(query['category_id'], 'plaster');
    expect(query['near_lat'], '49.8');
    expect(query['near_lon'], '73.1');
    expect(query.containsKey('city'), false);
    expect(savedFilters['q'], 'штукатурка');
    expect(savedFilters['near_lat'], 49.8);
    expect(savedFilters.containsKey('city'), false);
    expect(find.text('В радиусе 50 км. Расположение заказа — по городу.'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
