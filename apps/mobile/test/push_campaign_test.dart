import 'dart:convert';
import 'package:flutter/material.dart';
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

void main() {
  testWidgets(
      'campaign notification shows API text, marks read and resolves an offer with object authorization',
      (t) async {
    const offerId = '321e4567-e89b-42d3-a456-426614174000';
    const orderId = '421e4567-e89b-42d3-a456-426614174000';
    final requests = <http.Request>[];
    var denyOffer = false;
    final api = JobaApi('https://example.com', vault: _Vault(), transport: MockClient((r) async {
      requests.add(r);
      dynamic data = {'items': []};
      if (r.url.path.endsWith('/me/notifications'))
        data = {
          'items': [
            {
              'id': 'notice',
              'type': 'service.campaign',
              'title': 'Заголовок из API',
              'body': 'Настоящий текст уведомления',
              'deep_link': {'route': 'offer', 'id': offerId},
              'read': false
            }
          ]
        };
      if(r.url.path.endsWith('/orders/$orderId'))data={'id':orderId,'owner':'another-owner','status':'completed','title':'Доступный заказ','city':'Алматы','currency':'KZT','budget_amount':10000,'description':'Описание заказа','version':1};
      if (r.url.path.endsWith('/offers/$offerId')) {
        if (denyOffer)
          return http.Response(
              jsonEncode({
                'error': {'code': 'NOT_FOUND', 'message': 'Объект недоступен'}
              }),
              404, headers: {'content-type':'application/json; charset=utf-8'});
        data = {'order_id': orderId};
      }
      return http.Response(jsonEncode({'data': data}), 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    }));
    await t.pumpWidget(JobaApp(api: api));
    await t.pumpAndSettle();
    final dynamic state = t.state(find.byType(Marketplace));
    state.me = {
      'id': 'owner',
      'country': 'KZ',
      'roles': ['customer'],
      'active_role': 'customer',
      'locale': 'ru'
    };
    api.session = {'access_token':'isolated-test','refresh_token':'isolated-refresh','user':state.me};
    state.go('notifications');
    await t.pumpAndSettle();
    expect(find.text('Заголовок из API'), findsOneWidget);
    expect(find.text('Настоящий текст уведомления'), findsOneWidget);
    await t.tap(find.text('Заголовок из API'));
    await t.pumpAndSettle();
    expect(
        requests.any((r) =>
            r.method == 'POST' &&
            r.url.path.endsWith('/me/notifications/notice/read')),
        true);
    expect(state.route, 'order');
    expect(state.objectId, orderId);
    state.go('notifications');
    await t.pumpAndSettle();
    denyOffer = true;
    await expectLater(state.openCampaignLink({'route': 'offer', 'id': offerId}),
        throwsA(isA<ApiException>()));
    expect(state.route, 'notifications');
    final count = requests.length;
    await expectLater(
        state.openCampaignLink({'route': 'order', 'id': '../../admin'}),
        throwsA(isA<ApiException>()));
    await expectLater(
        state.openCampaignLink({'route': 'https://outside.example'}),
        throwsA(isA<ApiException>()));
    expect(requests.length, count);
    await t.tap(find.text('Заголовок из API'));await t.pumpAndSettle();
    expect(find.byType(AlertDialog),findsOneWidget);
    await t.tap(find.text('Понятно'));await t.pumpAndSettle();
    expect(state.route,'notifications');
    expect(find.text('Новое'),findsNothing);
    expect(find.text('Заголовок из API'),findsOneWidget);
    await t.pumpWidget(const SizedBox.shrink());
  });
}
