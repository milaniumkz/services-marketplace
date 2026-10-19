import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:services_marketplace/core/api.dart';
import 'package:services_marketplace/core/server_clock.dart';
import 'package:services_marketplace/screens/commerce_states.dart';
import 'package:services_marketplace/screens/executor_access.dart';

void main() {
  setUpAll(() => initializeDateFormatting());
  test('server time ignores device clock changes and stale or invalid samples',
      () {
    var ticks = Duration.zero;
    var device = DateTime.utc(2040);
    final clock = ServerClock(elapsed: () => ticks, deviceNow: () => device);
    expect(clock.now, device);
    expect(clock.synchronize('2026-10-19T10:00:00Z'), true);
    ticks = const Duration(seconds: 5);
    device = DateTime.utc(2000);
    expect(clock.now, DateTime.utc(2026, 10, 19, 10, 0, 5));
    for (final sample in [
      null,
      'invalid',
      '2026-10-19T10:00:00',
      '2026-10-19T10:00:01Z'
    ]) {
      expect(clock.synchronize(sample), false);
      expect(clock.now, DateTime.utc(2026, 10, 19, 10, 0, 5));
    }
    expect(clock.synchronize('2026-10-19T10:00:10Z'), true);
    ticks = const Duration(seconds: 6);
    expect(clock.now, DateTime.utc(2026, 10, 19, 10, 0, 11));
  });
  test('API metadata synchronizes time and missing metadata retains the anchor',
      () async {
    var ticks = Duration.zero;
    dynamic timestamp = '2026-10-19T10:00:00Z';
    final clock =
        ServerClock(elapsed: () => ticks, deviceNow: () => DateTime.utc(2040));
    final api = JobaApi('https://isolated.example',
        clock: clock,
        transport: MockClient((_) async => http.Response(
            jsonEncode({
              'data': {},
              'meta': {'server_time': timestamp}
            }),
            200)));
    addTearDown(api.dispose);
    await api.request('/health', authenticated: false);
    expect(api.serverTime, timestamp);
    ticks = const Duration(seconds: 3);
    for (final value in [null, 7, 'bad', '2026-10-19T09:00:00Z']) {
      timestamp = value;
      await api.request('/health', authenticated: false);
      expect(clock.now, DateTime.utc(2026, 10, 19, 10, 0, 3));
      expect(api.serverTime, '2026-10-19T10:00:00Z');
    }
    // A newer response can lag behind estimated now due to transport latency.
    // Its raw timestamp must still advance notification read-all's cursor.
    timestamp = '2026-10-19T10:00:02Z';
    await api.request('/health', authenticated: false);
    expect(api.serverTime, timestamp);
    expect(clock.now, DateTime.utc(2026, 10, 19, 10, 0, 3));
  });
  testWidgets(
      'executor access expires on the server boundary without reopening',
      (t) async {
    var ticks = Duration.zero;
    final clock =
        ServerClock(elapsed: () => ticks, deviceNow: () => DateTime.utc(2040));
    clock.synchronize('2026-10-19T10:00:00Z');
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ExecutorAccess(
                choosing: false,
                grants: [],
                config: {},
                subscriptions: [
                  {
                    'id': 'subscription',
                    'status': 'active',
                    'valid_until': '2026-10-19T10:00:02Z'
                  }
                ],
                now: () => clock.now,
                onGo: (_, __) {}))));
    await t.pumpAndSettle();
    expect(find.text('Активна'), findsOneWidget);
    ticks = const Duration(seconds: 2);
    await t.pump(const Duration(seconds: 1));
    expect(find.text('Не активна'), findsOneWidget);
    expect(find.text('Активна'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('subscription management expires using server time', (t) async {
    var ticks = Duration.zero;
    final clock =
        ServerClock(elapsed: () => ticks, deviceNow: () => DateTime.utc(2000));
    clock.synchronize('2026-10-19T10:00:00Z');
    final api = JobaApi('https://isolated.example',
        clock: clock,
        transport: MockClient((_) async => http.Response(
            jsonEncode({
              'data': {
                'id': 'sub',
                'status': 'active',
                'valid_until': '2026-10-19T10:00:02Z'
              }
            }),
            200)))
      ..session = {'access_token': 'isolated'};
    addTearDown(api.dispose);
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CommerceStateScreen(
                api: api,
                mode: 'manage-subscription',
                id: 'sub',
                onGo: (_, __) {}))));
    await t.pumpAndSettle();
    expect(find.text('Активна'), findsOneWidget);
    ticks = const Duration(seconds: 2);
    await t.pump(const Duration(seconds: 1));
    expect(find.text('Не активна'), findsOneWidget);
    expect(find.text('Активна'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets(
      'reward cooldown uses API time and becomes available without extra requests',
      (t) async {
    var ticks = Duration.zero;
    var requests = 0;
    final clock =
        ServerClock(elapsed: () => ticks, deviceNow: () => DateTime.utc(2040));
    clock.synchronize('2026-10-19T10:00:00Z');
    final api = JobaApi('https://isolated.example', clock: clock,
        transport: MockClient((_) async {
      requests++;
      return http.Response(
          jsonEncode({
            'data': {
              'rewarded_access_enabled': true,
              'reward_provider_ready': true,
              'reward_policy': {'kind': 'duration', 'duration_seconds': 86400},
              'reward_usage': {
                'remaining_today': 1,
                'cooldown_until': '2026-10-19T10:00:05Z'
              }
            }
          }),
          200);
    }))
      ..session = {'access_token': 'isolated'};
    addTearDown(api.dispose);
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CommerceStateScreen(
                api: api, mode: 'reward', onGo: (_, __) {}))));
    await t.pumpAndSettle();
    final button = find.widgetWithText(FilledButton, 'Посмотреть ролик');
    expect(t.widget<FilledButton>(button).onPressed, isNull);
    ticks = const Duration(seconds: 5);
    await t.pump(const Duration(seconds: 1));
    expect(t.widget<FilledButton>(button).onPressed, isNotNull);
    expect(requests, 1);
    await t.pumpWidget(const SizedBox());
  });
}
