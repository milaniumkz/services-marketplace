import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:services_marketplace/core/api.dart';
import 'package:services_marketplace/core/commerce_gateway.dart';
import 'package:services_marketplace/core/theme.dart';
import 'package:services_marketplace/screens/promotion_purchase.dart';

http.Response ok(dynamic data) =>
    http.Response(jsonEncode({'data': data, 'meta': {}}), 200,
        headers: {'content-type': 'application/json; charset=utf-8'});

class Gateway extends CommerceGateway {
  int purchases = 0;
  Future<Json> purchase(Json offer) async {
    purchases++;
    return {'provider': 'test', 'transaction_reference': 'paid-once'};
  }

  Future<List<Json>> restore() async => [];
  Future<void> manage(Json subscription) async {}
  Future<bool> playReward(Json session) async => false;
}

Widget host(Widget child) =>
    MaterialApp(theme: jobaTheme(), home: Scaffold(body: child));
void main() {
  testWidgets(
      'only compatible placements can be reserved, and period selection uses the exact published price',
      (t) async {
    Json? body;
    String? route;
    final api =
        JobaApi('https://isolated.example', transport: MockClient((r) async {
      if (r.method == 'POST') {
        body = Json.from(jsonDecode(r.body));
        return ok({'id': 'reserved'});
      }
      if (r.url.path.endsWith('/boost-offers'))
        return ok({
          'items': [
            {
              'id': 'week',
              'period': 'week',
              'currency': 'KZT',
              'amount_minor': 199000
            },
            {
              'id': 'month',
              'period': 'month',
              'currency': 'KZT',
              'amount_minor': 599000
            }
          ],
          'placements': [
            {
              'title': 'Каталог услуг',
              'payload': {'placement_id': 'search.services.promoted'}
            },
            {
              'title': 'Лента заказов',
              'payload': {'placement_id': 'search.orders.promoted'}
            }
          ]
        });
      if (r.url.path.endsWith('/me/contractor-profile'))
        return ok({
          'profile': {
            'id': 'service',
            'status': 'published',
            'title': 'Ремонт и отделка'
          }
        });
      return ok({'items': []});
    }))
          ..session = {'access_token': 'isolated'};
    await t.pumpWidget(host(PromotionPurchase(
        api: api, mode: 'promotion', onGo: (r, id) => route = r)));
    await t.pumpAndSettle();
    expect(find.text('Каталог услуг'), findsOneWidget);
    expect(find.text('Лента заказов'), findsNothing);
    await t.tap(find.text('Месяц'));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.text('Условия размещения'), 150,
        scrollable: find.byType(Scrollable).first);
    await t.tap(find.text('Условия размещения'));
    await t.pumpAndSettle();
    await t.tap(find.text('Вернуться к размещению'));
    await t.pumpAndSettle();
    expect(
        t.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Месяц')).selected,
        true);
    await t.tap(find.text('Проверить размещение'));
    await t.pumpAndSettle();
    expect(body, {
      'target_id': 'service',
      'price_id': 'month',
      'placement_id': 'search.services.promoted'
    });
    expect(route, 'promotion-checkout');
    await t.pumpWidget(const SizedBox());
    api.dispose();
  });
  testWidgets(
      'retrying proof verification does not charge again even after the reservation expires',
      (t) async {
    final gateway = Gateway();
    var clock = DateTime.utc(2026, 10, 15, 10);
    var attempts = 0;
    String? route;
    final api =
        JobaApi('https://isolated.example', transport: MockClient((r) async {
      if (r.method == 'POST') {
        attempts++;
        expect(jsonDecode(r.body)['transaction_reference'], 'paid-once');
        if (attempts == 1)
          return http.Response(
              jsonEncode({
                'error': {
                  'code': 'TEMPORARY_FAILURE',
                  'message': 'Повторите проверку'
                }
              }),
              503,
              headers: {'content-type': 'application/json; charset=utf-8'});
        return ok({'status': 'resolution_required'});
      }
      return ok({
        'id': 'reservation',
        'title': 'Моя услуга',
        'city': 'Алматы',
        'status': 'reserved',
        'reservation_expires_at':
            clock.add(const Duration(seconds: 20)).toIso8601String(),
        'starts_at': '2026-10-15T10:00:00Z',
        'ends_at': '2026-10-22T10:00:00Z',
        'price': {
          'provider': 'test',
          'product_id': 'week',
          'currency': 'KZT',
          'amount_minor': 199000,
          'period': 'week',
          'time_zone': 'UTC'
        }
      });
    }))
          ..session = {'access_token': 'isolated'};
    await t.pumpWidget(host(PromotionPurchase(
        api: api,
        mode: 'promotion-checkout',
        id: 'reservation',
        gateway: gateway,
        now: () => clock,
        onGo: (r, id) => route = r)));
    await t.pumpAndSettle();
    expect(
        t
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Продолжить оплату'))
            .onPressed,
        isNull);
    await t.scrollUntilVisible(
        find.widgetWithText(TextButton, 'Условия размещения'), 200,
        scrollable: find.byType(Scrollable).first);
    await t.tap(find.byType(Checkbox));
    await t.pump();
    await t.tap(find.text('Продолжить оплату'));
    await t.pumpAndSettle();
    expect(route, isNull);
    expect(gateway.purchases, 1);
    await t.scrollUntilVisible(
        find.widgetWithText(TextButton, 'Условия размещения'), 150,
        scrollable: find.byType(Scrollable).first);
    await t.tap(find.widgetWithText(TextButton, 'Условия размещения'));
    await t.pumpAndSettle();
    await t.tap(find.text('Вернуться к размещению'));
    await t.pumpAndSettle();
    clock = clock.add(const Duration(seconds: 21));
    await t.pump(const Duration(seconds: 1));
    await t.drag(find.byType(ListView).first, const Offset(0, 1000));
    await t.pumpAndSettle();
    expect(find.text('Резерв больше не доступен'), findsOneWidget);
    await t.tap(find.text('Проверить оплату'));
    await t.pumpAndSettle();
    expect(gateway.purchases, 1);
    expect(attempts, 2);
    expect(route, 'promotion-pending');
    await t.pumpWidget(const SizedBox());
    api.dispose();
  });
  testWidgets('disconnected checkout cannot start a purchase or send a receipt',
      (t) async {
    var writes = 0;
    final api =
        JobaApi('https://isolated.example', transport: MockClient((r) async {
      if (r.method != 'GET') writes++;
      return ok({
        'id': 'reservation',
        'title': 'Моя услуга',
        'status': 'reserved',
        'reservation_expires_at':
            DateTime.now().add(const Duration(minutes: 10)).toIso8601String(),
        'price': {'currency': 'KZT', 'amount_minor': 199000, 'period': 'week'}
      });
    }))
          ..session = {'access_token': 'isolated'};
    await t.pumpWidget(host(PromotionPurchase(
        api: api,
        mode: 'promotion-checkout',
        id: 'reservation',
        onGo: (r, id) {})));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(
        find.widgetWithText(TextButton, 'Условия размещения'), 200,
        scrollable: find.byType(Scrollable).first);
    await t.tap(find.byType(Checkbox));
    await t.pump();
    expect(
        t
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Продолжить оплату'))
            .onPressed,
        isNull);
    expect(writes, 0);
    await t.pumpWidget(const SizedBox());
    api.dispose();
  });
}
