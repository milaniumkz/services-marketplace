import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/core/api.dart';
import '../lib/screens/executor_access.dart';
import '../lib/screens/referral_terms.dart';

void main() {
  testWidgets(
      'active Standard exposes separate Top-100 and a discounted prorated upgrade, each with its own checkout',
      (tester) async {
    tester.view.physicalSize = const Size(430, 1300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime.utc(2026, 10, 28),
        until = now.add(const Duration(days: 15)).toIso8601String();
    final navigation = <String>[];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ExecutorAccess(
                choosing: true,
                grants: const [],
                subscriptions: [
                  {
                    'id': 'base',
                    'plan': 'standard',
                    'status': 'active',
                    'valid_until': until
                  }
                ],
                config: {
                  'offers': <Json>[
                    {
                      'id': 'upgrade',
                      'plan': 'premium',
                      'offer_kind': 'upgrade',
                      'amount_minor': 20000,
                      'currency': 'KZT',
                      'discount_percent': 20,
                      'valid_until': until
                    },
                    {
                      'id': 'addon',
                      'plan': 'top100',
                      'offer_kind': 'addon',
                      'amount_minor': 50000,
                      'currency': 'KZT',
                      'duration_days': 30
                    },
                    {
                      'id': 'renew',
                      'plan': 'standard',
                      'offer_kind': 'renewal',
                      'amount_minor': 100000,
                      'currency': 'KZT',
                      'duration_days': 30
                    },
                  ]
                },
                now: () => now,
                onGo: (route, id) => navigation.add('$route:$id')))));
    await tester.pumpAndSettle();
    expect(find.text('Повысить до Премиума'), findsOneWidget);
    expect(find.textContaining('скидка 20%'), findsOneWidget);
    await tester.tap(find.text('Перейти на Премиум'));
    expect(navigation.last, 'checkout:upgrade');
    await tester.ensureVisible(find.text('Подключить Топ-100'));
    await tester.tap(find.text('Подключить Топ-100'));
    expect(navigation.last, 'checkout:addon');
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'referral terms identify a percentage and covered services instead of generic access',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Text(referralTerms(context, {
                  'threshold': 3,
                  'qualifying_event': 'registered',
                  'reward_kind': 'discount',
                  'discount_percent': 25,
                  'discount_services': ['upgrade', 'top100'],
                  'reward_duration_seconds': 604800
                })))));
    expect(find.textContaining('Персональная скидка: 25%'), findsOneWidget);
    expect(find.textContaining('Переход на Премиум · Топ-100'), findsOneWidget);
    expect(find.textContaining('Регистрация и ввод кода'), findsOneWidget);
  });
}
