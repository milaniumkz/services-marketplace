import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:services_marketplace/core/api.dart';
import 'package:services_marketplace/core/theme.dart';
import 'package:services_marketplace/screens/action_receipt.dart';

class _Vault implements SessionVault {
  Future<String?> read() async => null;
  Future<void> write(String v) async {}
  Future<void> clear() async {}
}

void main() {
  testWidgets(
      'action receipts read actual states and never claim publication agreement or a missing review',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Json row = {};
    var offers = 0, jobs = 0, orders = 0;
    String? opened;
    final paths = <String>[];
    final api = JobaApi('https://isolated.example', vault: _Vault(),
        transport: MockClient((r) async {
      paths.add(r.url.path);
      return http.Response(jsonEncode({'data': row, 'meta': {}}), 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    }))
      ..session = {
        'access_token': 'isolated',
        'user': {'country': 'KZ'}
      };
    Future<void> show(ReceiptKind kind, Json data) async {
      row = data;
      await tester.pumpWidget(MaterialApp(
          theme: jobaTheme(),
          home: Scaffold(
              body: ActionReceipt(
                  key: UniqueKey(),
                  api: api,
                  id: kind == ReceiptKind.offer ? 'offer-real' : 'order-real',
                  kind: kind,
                  onOrders: () => orders++,
                  onOffers: () => offers++,
                  onJobs: () => jobs++,
                  onOrder: (id) => opened = id))));
      await tester.pumpAndSettle();
    }

    await show(ReceiptKind.published, {'status': 'pending_moderation'});
    expect(find.text('Заказ на виду'), findsNothing);
    expect(find.text('Заказ на проверке'), findsOneWidget);
    await tester.tap(find.text('Открыть заказ'));
    expect(opened, 'order-real');
    await show(ReceiptKind.published, {'status': 'open'});
    await tester.tap(find.text('Посмотреть отклики'));
    expect(offers, 1);
    await tester.tap(find.text('Мои заказы'));
    expect(orders, 1);
    await show(ReceiptKind.offer, {
      'status': 'active',
      'order_id': 'order-linked',
      'order': {'status': 'open'}
    });
    await tester.tap(find.text('К подходящим заказам'));
    expect(jobs, 1);
    expect(paths.last.endsWith('/offers/offer-real'), true);
    await show(ReceiptKind.offer, {
      'status': 'active',
      'order_id': 'order-linked',
      'order': {'status': 'cancelled'}
    });
    expect(find.text('Предложение\nу заказчика'), findsNothing);
    await tester.tap(find.text('Открыть заказ'));
    expect(opened, 'order-linked');
    await show(ReceiptKind.review, {
      'my_review': {'status': 'sealed'}
    });
    expect(find.textContaining('Пока она скрыта'), findsOneWidget);
    await show(ReceiptKind.review, {
      'my_review': {'status': 'published'}
    });
    expect(find.text('Ваш отзыв опубликован.'), findsOneWidget);
    expect(find.textContaining('Пока она скрыта'), findsNothing);
    await show(ReceiptKind.review, {});
    expect(find.text('Спасибо за отзыв'), findsNothing);
    expect(find.text('Отзыв не найден'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    api.dispose();
  });
}
