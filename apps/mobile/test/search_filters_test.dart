import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:services_marketplace/core/api.dart';
import 'package:services_marketplace/core/theme.dart';
import 'package:services_marketplace/screens/search_filters.dart';

class _Vault implements SessionVault {
  Future<String?> read() async => null;
  Future<void> write(String value) async {}
  Future<void> clear() async {}
}

void main() {
  testWidgets(
      'filters validate prices without losing selections and emit exact minor units',
      (tester) async {
    final api = JobaApi('https://isolated.example',
        vault: _Vault(),
        transport: MockClient((request) async => http.Response(
            jsonEncode({
              'data': {
                'items': request.url.path.endsWith('/geo/cities')
                    ? [
                        {'id': 'almaty', 'name': 'Алматы'}
                      ]
                    : [
                        {'id': 'repair', 'name': 'Ремонт'}
                      ]
              },
              'meta': {}
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'})));
    api.session = {
      'access_token': 'isolated-token',
      'user': {'country': 'KZ'}
    };
    addTearDown(api.dispose);
    Json? applied;
    await tester.pumpWidget(MaterialApp(
        theme: jobaTheme(),
        home: SearchFilters(
            api: api,
            initial: {
              'city': 'Алматы',
              'work_mode': 'onsite',
              'category_id': 'repair'
            },
            onClose: () {},
            onApply: (value) => applied = value)));
    await tester.pumpAndSettle();
    final lower = find.byKey(const ValueKey('search-price-min'));
    final upper = find.byKey(const ValueKey('search-price-max'));
    await tester.scrollUntilVisible(lower, 250,
        scrollable: find.byType(Scrollable).first);
    await tester.enterText(lower, '8 000,50');
    await tester.enterText(upper, '7 500');
    await tester.tap(find.text('Показать специалистов'));
    await tester.pumpAndSettle();
    expect(applied, isNull);
    expect(find.text('Проверьте диапазон цены'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.enterText(lower, '7 000,50');
    await tester.ensureVisible(find.text('4,8 и выше'));
    await tester.tap(find.text('4,8 и выше'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Показать специалистов'));
    await tester.pumpAndSettle();
    expect(applied, {
      'city': 'Алматы',
      'category_id': 'repair',
      'work_mode': 'onsite',
      'price_min': 700050,
      'price_max': 750000,
      'rating_min': '4.8'
    });
    applied = null;
    await tester.ensureVisible(lower);
    await tester.enterText(lower, 'invalid price');
    await tester.tap(find.text('Показать специалистов'));
    await tester.pumpAndSettle();
    expect(applied, isNull);
    expect(find.text('Проверьте диапазон цены'), findsOneWidget);
    await tester.tap(find.text('Сбросить'));
    await tester.pumpAndSettle();
    expect(find.text('Проверьте диапазон цены'), findsNothing);
    await tester.tap(find.text('Показать специалистов'));
    await tester.pumpAndSettle();
    expect(applied, isEmpty);
  });
}
