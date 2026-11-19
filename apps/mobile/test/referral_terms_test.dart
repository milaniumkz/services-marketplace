import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/screens/referral_terms.dart';

void main() {
  test('reward activation requires an unexpired available reward', () {
    final now = DateTime.utc(2026, 10, 16);
    expect(
        referralRewardAvailable(
            {'status': 'available', 'expires_at': '2026-10-17T00:00:00Z'}, now),
        isTrue);
    for (final reward in [
      {'status': 'available', 'expires_at': now.toIso8601String()},
      {'status': 'available', 'expires_at': 'invalid'},
      {'status': 'redeemed', 'expires_at': '2026-10-17T00:00:00Z'},
      {'status': 'available'},
    ]) {
      expect(referralRewardAvailable(reward, now), isFalse);
    }
  });
  testWidgets(
      'terms display the supplied snapshot and optional attribution window',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Text(referralTerms(context, {
                  'threshold': 3,
                  'qualifying_event': 'completed_order',
                  'reward_duration_seconds': 3600,
                  'capabilities': ['search_full'],
                  'attribution_window_days': 30,
                })))));
    expect(find.textContaining('30 суток'), findsOneWidget);
    expect(find.textContaining('Полный поиск'), findsOneWidget);
    expect(find.textContaining('Приглашений для награды: 3'), findsOneWidget);
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Text(referralTerms(context, {
                  'threshold': 1,
                  'qualifying_event': 'executor_verified',
                  'reward_duration_seconds': 120,
                  'capabilities': ['send_offer'],
                })))));
    expect(find.textContaining('Код можно ввести'), findsNothing);
    expect(find.textContaining('Проверка исполнителя'), findsOneWidget);
  });
}
