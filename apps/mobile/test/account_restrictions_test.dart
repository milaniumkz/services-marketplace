import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:services_marketplace/core/api.dart';
import 'package:services_marketplace/core/theme.dart';
import 'package:services_marketplace/screens/account_restrictions.dart';

class _Vault implements SessionVault {
  Future<String?> read() async => null;
  Future<void> write(String v) async {}
  Future<void> clear() async {}
}

void main() {
  testWidgets(
      'restriction details use API state and keep support privacy work and a valid appeal reachable',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var restricted = true, support = 0, privacy = 0, orders = 0;
    String? incident, appeal;
    final api = JobaApi('https://isolated.example',
        vault: _Vault(),
        transport: MockClient((r) async => http.Response(
            jsonEncode({
              'data': {
                'items': restricted
                    ? [
                        {
                          'id': 'isolated-limit',
                          'reason': 'Опубликованное объяснение',
                          'ends_at': '2026-10-16T10:00:00Z',
                          'case_id': 'case-visible',
                          'can_appeal': true
                        }
                      ]
                    : [],
                'meta': {'restricted': restricted}
              },
              'meta': {}
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'})))
      ..session = {
        'access_token': 'isolated',
        'user': {'country': 'KZ'}
      };
    await tester.pumpWidget(MaterialApp(
        theme: jobaTheme(),
        home: Scaffold(
            body: AccountRestrictions(
                api: api,
                onSupport: () => support++,
                onPrivacy: () => privacy++,
                onOrders: () => orders++,
                onCase: (id) => incident = id,
                onAppeal: (id) => appeal = id,
                dateLabel: (v) => 'Дата из API: $v'))));
    await tester.pumpAndSettle();
    expect(find.text('Опубликованное объяснение'), findsOneWidget);
    expect(find.text('Дата из API: 2026-10-16T10:00:00Z'), findsOneWidget);
    await tester.tap(find.text('Подать апелляцию'));
    expect(appeal, 'case-visible');
    await tester.scrollUntilVisible(find.text('Дело'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Дело'));
    expect(incident, 'case-visible');
    await tester.scrollUntilVisible(find.text('Поддержка'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Поддержка'));
    await tester.tap(find.text('Приватность'));
    await tester.scrollUntilVisible(find.text('Действующие заказы'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Действующие заказы'));
    expect([support, privacy, orders], [1, 1, 1]);
    restricted = false;
    await tester.scrollUntilVisible(find.text('Обновить статус'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Обновить статус'));
    await tester.pumpAndSettle();
    expect(find.text('Ограничений нет'), findsOneWidget);
    expect(find.text('Подать апелляцию'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    api.dispose();
  });
}
