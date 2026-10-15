import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:services_marketplace/core/api.dart';
import 'package:services_marketplace/core/commerce_gateway.dart';
import 'package:services_marketplace/screens/device_setup.dart';
import 'package:services_marketplace/screens/commerce_states.dart';
import 'package:services_marketplace/screens/privacy_states.dart';
import 'package:services_marketplace/screens/work_states.dart';

http.Response ok(dynamic data) =>
    http.Response(jsonEncode({'data': data, 'meta': {}}), 200,
        headers: {'content-type': 'application/json; charset=utf-8'});
JobaApi api(Future<http.Response> Function(http.Request) handler) =>
    JobaApi('https://example.com', transport: MockClient(handler))
      ..session = {'access_token': 'isolated-token'};
Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

class Gateway extends CommerceGateway {
  int purchases = 0;
  @override
  Future<Json> purchase(Json offer) async {
    purchases++;
    return {'provider': 'isolated', 'transaction_reference': 'signed-proof'};
  }

  @override
  Future<List<Json>> restore() async => [];
  @override
  Future<void> manage(Json subscription) async {}
  @override
  Future<bool> playReward(Json session) async => true;
}

void main() {
  testWidgets(
      'PIN requires six digits and matching confirmation, keeps mismatch editable',
      (t) async {
    String? saved;
    await t.pumpWidget(host(PinSetup(
        onSave: (pin, bio) async {
          saved = pin;
        },
        onPassword: () async {})));
    final field = find.byKey(const ValueKey('secure-pin-input'));
    await t.enterText(field, '12345');
    await t.pump();
    expect(t.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    await t.enterText(field, '123456');
    await t.pump();
    await t.tap(find.text('Подтвердить PIN'));
    await t.pump();
    expect(saved, isNull);
    await t.enterText(field, '654321');
    await t.pump();
    await t.tap(find.text('Сохранить PIN'));
    await t.pump();
    expect(find.text('PIN не совпадает'), findsOneWidget);
    expect(saved, isNull);
    await t.enterText(field, '123456');
    await t.pump();
    await t.tap(find.text('Сохранить PIN'));
    await t.pump();
    expect(saved, '123456');
  });
  testWidgets('biometric failure offers an actual PIN fallback', (t) async {
    var fallback = false;
    await t.pumpWidget(host(BiometrySetup(
        onEnable: () async {
          throw Exception('Unavailable');
        },
        onPin: () => fallback = true)));
    await t.tap(find.text('Включить биометрию'));
    await t.pumpAndSettle();
    expect(find.text('Используйте PIN'), findsOneWidget);
    await t.tap(find.text('Ввести PIN'));
    expect(fallback, true);
  });
  testWidgets(
      'offer revision sends edits and acknowledgement in one versioned request',
      (t) async {
    Json? body;
    String? route;
    final a = api((r) async {
      if (r.method == 'PATCH') {
        body = jsonDecode(r.body);
        return ok({'id': 'offer', 'version': 4});
      }
      return ok({
        'id': 'offer',
        'status': 'active',
        'currency': 'KZT',
        'version': 3,
        'amount': 12000,
        'text': 'Мой комментарий',
        'acknowledged_revision': 1,
        'order': {
          'id': 'order',
          'status': 'open',
          'country': 'KZ',
          'currency': 'KZT',
          'revision': 2,
          'title': 'Задача',
          'description': 'Новые условия'
        }
      });
    });
    await t.pumpWidget(host(WorkStateScreen(
        api: a,
        mode: 'offer-revision',
        id: 'offer',
        onGo: (r, id) => route = r,
        pickPhoto: () async => null)));
    await t.pumpAndSettle();
    expect(t.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    await t.scrollUntilVisible(find.byType(CheckboxListTile), 200,
        scrollable: find.byType(Scrollable).first);
    await t.tap(find.byType(CheckboxListTile));
    await t.pump();
    await t.tap(find.text('Изменить мой отклик'));
    await t.pumpAndSettle();
    expect(body, isNull);
    await t.scrollUntilVisible(find.byType(CheckboxListTile), 200,
        scrollable: find.byType(Scrollable).first);
    await t.tap(find.byType(CheckboxListTile));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Сохранить'));
    await t.pumpAndSettle();
    expect(body, containsPair('acknowledged_revision', 2));
    expect(body, containsPair('expected_version', 3));
    expect(body, containsPair('amount', 12000));
    expect(route, 'offer-sent');
  });
  testWidgets(
      'checkout cannot purchase without consent and routes pending proof without granting',
      (t) async {
    final gateway = Gateway();
    String? route, id;
    final a = api((r) async => r.method == 'POST'
        ? ok({
            'pending': true,
            'check': {'id': 'check'}
          })
        : ok({
            'items': [
              {
                'id': 'offer',
                'title': 'Доступ',
                'product_type': 'subscription',
                'amount_minor': 100,
                'currency': 'KZT'
              }
            ]
          }));
    await t.pumpWidget(host(CommerceStateScreen(
        api: a,
        mode: 'checkout',
        gateway: gateway,
        onGo: (r, i) {
          route = r;
          id = i;
        })));
    await t.pumpAndSettle();
    expect(t.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    expect(gateway.purchases, 0);
    await t.scrollUntilVisible(find.byType(CheckboxListTile), 150);
    await t.tap(find.byType(CheckboxListTile));
    await t.pump();
    await t.tap(find.text('Продолжить оплату'));
    await t.pumpAndSettle();
    expect(gateway.purchases, 1);
    expect(route, 'payment-pending');
    expect(id, 'check');
  });
  testWidgets(
      'disconnected gateway reports failure instead of inventing a purchase',
      (t) async {
    String? route;
    final a = api((r) async => ok({
          'items': [
            {
              'id': 'offer',
              'title': 'Доступ',
              'amount_minor': 100,
              'currency': 'KZT'
            }
          ]
        }));
    await t.pumpWidget(host(CommerceStateScreen(
        api: a, mode: 'checkout', onGo: (r, id) => route = r)));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.byType(CheckboxListTile), 150);
    await t.tap(find.byType(CheckboxListTile));
    await t.pump();
    await t.tap(find.text('Продолжить оплату'));
    await t.pumpAndSettle();
    expect(route, isNull);
    await t.scrollUntilVisible(find.text('Сервис ещё не подключён.'), 150);
    expect(find.text('Сервис ещё не подключён.'), findsOneWidget);
  });
  testWidgets('optional consent keeps user selection after rejected save',
      (t) async {
    var reject = true;
    final bodies = <Json>[];
    String? route;
    final a = api((r) async {
      if (r.method == 'POST') {
        bodies.add(jsonDecode(r.body));
        if (reject)
          return http.Response(
              jsonEncode({
                'error': {
                  'code': 'STATE_CONFLICT',
                  'message': 'Повторите попытку'
                }
              }),
              409);
        return ok({});
      }
      return ok({
        'version': 7,
        'marketing': false,
        'ad_personalization': false,
        'optional_analytics': false
      });
    });
    await t.pumpWidget(host(
        PrivacyStates(api: a, mode: 'consents', onGo: (r, id) => route = r)));
    await t.pumpAndSettle();
    await t.tap(find.byType(SwitchListTile).first);
    await t.pump();
    await t.tap(find.text('Сохранить выбор'));
    await t.pumpAndSettle();
    expect(route, isNull);
    expect(t.widget<SwitchListTile>(find.byType(SwitchListTile).first).value,
        true);
    reject = false;
    await t.tap(find.text('Сохранить выбор'));
    await t.pumpAndSettle();
    expect(bodies.last, containsPair('marketing', true));
    expect(bodies.last, containsPair('expected_version', 7));
    expect(route, 'privacy');
  });
}
