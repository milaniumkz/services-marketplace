import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:services_marketplace/core/api.dart';
import 'package:services_marketplace/core/theme.dart';
import 'package:services_marketplace/screens/promotions_history.dart';

class _Vault implements SessionVault {
  Future<String?> read() async => null;
  Future<void> write(String value) async {}
  Future<void> clear() async {}
}

void main() {
  testWidgets(
      'promotion status does not claim payment for a reservation and rereads confirmed resolution and active state',
      (tester) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var state = 'reserved', paid = false, support = 0;
    final api = JobaApi('https://isolated.example',
        vault: _Vault(),
        transport: MockClient((r) async => http.Response(
            jsonEncode({
              'data': {
                'id': 'owned',
                'status': state,
                'payment_confirmed': paid
              }
            }),
            200)));
    api.session = {
      'access_token': 'test',
      'user': {'id': 'owner', 'country': 'KZ'}
    };
    await tester.pumpWidget(MaterialApp(
        theme: jobaTheme(),
        home: Scaffold(
            body: PromotionStatus(
                api: api,
                id: 'owned',
                onHistory: () {},
                onSupport: () => support++))));
    await tester.pumpAndSettle();
    expect(find.text('Место зарезервировано'), findsOneWidget);
    expect(find.textContaining('Оплата подтверждена'), findsNothing);
    state = 'resolution_required';
    await tester.tap(find.text('Обновить статус'));
    await tester.pumpAndSettle();
    expect(find.text('Нужно решение\nпо размещению'), findsOneWidget);
    expect(find.textContaining('Оплата подтверждена'), findsNothing);
    paid = true;
    await tester.tap(find.text('Обновить статус'));
    await tester.pumpAndSettle();
    expect(find.text('Оплата подтверждена,\nместо недоступно'), findsOneWidget);
    await tester.tap(find.text('Связаться с поддержкой'));
    expect(support, 1);
    state = 'active';
    await tester.tap(find.text('Обновить статус'));
    await tester.pumpAndSettle();
    expect(find.text('Размещение действует'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'promotion history tabs send distinct buckets and open the actual selected record',
      (tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final buckets = <String>[];
    Json? selected;
    final api = JobaApi('https://isolated.example', vault: _Vault(),
        transport: MockClient((r) async {
      final bucket = r.url.queryParameters['bucket']!;
      buckets.add(bucket);
      return http.Response(
          jsonEncode({
            'data': {
              'items': [
                {
                  'id': bucket,
                  'status': bucket == 'active' ? 'active' : 'expired',
                  'title': 'Собственное размещение',
                  'placement_id': 'home.promoted.services',
                  'provenance': 'admin_grant',
                  'price': {'amount_minor': 0}
                }
              ]
            }
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    }));
    api.session = {
      'access_token': 'test',
      'user': {'id': 'owner', 'country': 'KZ'}
    };
    await tester.pumpWidget(MaterialApp(
        theme: jobaTheme(),
        home: Scaffold(
            body: PromotionsHistory(
                api: api,
                onNew: () {},
                onOpen: (r) => selected = r,
                dateLabel: (_) => 'UTC'))));
    await tester.pumpAndSettle();
    expect(buckets.last, 'active');
    expect(find.text('Бесплатно'), findsOneWidget);
    await tester.tap(find.text('История'));
    await tester.pumpAndSettle();
    expect(buckets.last, 'history');
    await tester.tap(find.text('Условия и помощь'));
    expect(selected?['id'], 'history');
    expect(tester.takeException(), isNull);
  });
}
