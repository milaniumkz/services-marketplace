import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:services_marketplace/core/api.dart';
import 'package:services_marketplace/screens/commerce_states.dart';
import 'widget_test.dart' show MemoryVault, ok;

void main() {
  testWidgets(
      'checkbox without opening documents triggers explicit test purchase and shows server-confirmed test success',
      (t) async {
    Json? purchase;
    final offer = {
      'id': 'test-customer-v0-s1',
      'plan': 'customer',
      'role': 'customer',
      'provider': 'test',
      'product_type': 'subscription',
      'period': 'days',
      'duration_days': 30,
      'amount_minor': 50000,
      'currency': 'KZT',
      'is_test': true
    };
    final api = JobaApi('https://isolated.example', vault: MemoryVault(),
        transport: MockClient((r) async {
      if (r.url.path.endsWith('/billing/offers'))
        return ok({
          'items': [offer]
        });
      if (r.url.path.endsWith('/billing/test-purchase')) {
        purchase = jsonDecode(r.body);
        return ok({
          'is_test': true,
          'subscription': {'id': 'test-subscription'}
        });
      }
      if (r.url.path.endsWith('/me/subscriptions/test-subscription'))
        return ok({
          'is_test': true,
          'status': 'active',
          'valid_until': DateTime.now()
              .toUtc()
              .add(const Duration(days: 30))
              .toIso8601String()
        });
      fail('Unexpected request: ${r.url.path}');
    }));
    addTearDown(api.dispose);
    api.session = {
      'access_token': 'test-token',
      'user': {'id': 'customer', 'active_role': 'customer'}
    };
    String? route, id;
    Widget screen(String mode) => MaterialApp(
        home: Scaffold(
            body: CommerceStateScreen(
                key: ValueKey(mode),
                api: api,
                mode: mode,
                id: id,
                onGo: (r, value) {
                  route = r;
                  id = value;
                })));
    await t.pumpWidget(screen('checkout'));
    await t.pumpAndSettle();
    expect(purchase, isNull);
    await t.scrollUntilVisible(find.byType(CheckboxListTile), 200);
    await t.tap(find.byType(CheckboxListTile));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Продолжить оплату'));
    await t.tap(find.text('Продолжить оплату'));
    await t.pumpAndSettle();
    expect(purchase?['accepted'], true);
    expect(purchase?['offer_id'], offer['id']);
    expect(route, 'test-payment-success');
    await t.pumpWidget(screen('test-payment-success'));
    await t.pumpAndSettle();
    expect(find.text('Тестовая оплата прошла'), findsOneWidget);
    expect(find.textContaining('деньги не списывались'), findsOneWidget);
  });
  testWidgets('renewal receipt confirms the scheduled period and upgrade receipt preserves its original end', (t) async {
    Json subscription={'is_test':true,'status':'scheduled','valid_from':DateTime.now().add(const Duration(days:15)).toUtc().toIso8601String(),'valid_until':DateTime.now().add(const Duration(days:45)).toUtc().toIso8601String()};
    final api=JobaApi('https://isolated.example',vault:MemoryVault(),transport:MockClient((r)async=>ok(subscription)));
    addTearDown(api.dispose);
    api.session={'access_token':'test-token','user':{'id':'customer','active_role':'customer'}};
    Widget receipt(String id)=>MaterialApp(home:Scaffold(body:CommerceStateScreen(key:ValueKey(id),api:api,mode:'test-payment-success',id:id,onGo:(_,__){})));
    await t.pumpWidget(receipt('renewal'));await t.pumpAndSettle();
    expect(find.text('Тестовая оплата прошла'),findsOneWidget);expect(find.textContaining('Продление сохранено'),findsOneWidget);expect(find.text('Тестовый доступ не активен.'),findsNothing);
    subscription={...subscription,'status':'active','is_upgrade':true};
    await t.pumpWidget(receipt('upgrade'));await t.pumpAndSettle();
    expect(find.textContaining('Дата окончания оплаченного доступа сохранена'),findsOneWidget);expect(find.textContaining('активирована на 30 дней'),findsNothing);
  });

}
