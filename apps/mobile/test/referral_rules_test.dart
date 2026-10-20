import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/core/theme.dart';
import '../lib/screens/referral_rules.dart';

void main() {
  testWidgets('inactive referral program does not show steps promising access',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: jobaTheme(),
        home: const Scaffold(body: ReferralRulesContent(campaigns: []))));
    expect(
        find.text('Активных программ приглашений пока нет.'), findsOneWidget);
    expect(find.text('Получите доступ'), findsNothing);
  });
  testWidgets(
      'real campaign conditions remain readable on narrow screens with enlarged text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        theme: jobaTheme(),
        home: const MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(1.5)),
            child: Scaffold(
                body: ReferralRulesContent(campaigns: [
              {
                'threshold': 100,
                'qualifying_event': 'executor_verified',
                'reward_duration_seconds': 31622400,
                'attribution_window_days': 365,
                'capabilities': [
                  'search_full',
                  'send_offer',
                  'publish_profile'
                ],
              }
            ])))));
    await tester.scrollUntilVisible(find.textContaining('365 суток'), 100);
    expect(find.textContaining('Приглашений для награды: 100'), findsOneWidget);
    expect(find.textContaining('Публикация профиля'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
