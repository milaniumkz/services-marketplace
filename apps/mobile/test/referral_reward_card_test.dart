import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import '../lib/core/theme.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/screens/referral_reward_card.dart';

Map<String, dynamic> reward(DateTime end, {String status = 'available'}) => {
      'id': 'isolated-reward',
      'status': status,
      'expires_at': end.toIso8601String(),
      'policy_snapshot': {
        'threshold': 100,
        'qualifying_event': 'executor_verified',
        'reward_duration_seconds': 31622400,
        'attribution_window_days': 365,
        'capabilities': ['search_full', 'send_offer', 'publish_profile']
      },
    };
Widget screen(Widget child) => RepaintBoundary(
      key: const ValueKey('reward-capture'),
      child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: jobaTheme(),
          home: Scaffold(body: SingleChildScrollView(child: child))),
    );
Future<void> capture(WidgetTester tester, String name) async {
  final directory = Platform.environment['JOBA_REWARD_SCREENS_DIR'];
  if (directory == null) return;
  await tester.pump();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('reward-capture')));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    await Directory(directory).create(recursive: true);
    await File('$directory/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
  });
}

void main() {
  setUpAll(() async {
    await (FontLoader('Noto')
          ..addFont(rootBundle.load('assets/NotoSans-Regular.ttf'))
          ..addFont(rootBundle.load('assets/NotoSans-Bold.ttf')))
        .load();
  });
  testWidgets('available reward expires while open and rechecks when resuming',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var now = DateTime.utc(2026, 10, 16);
    var calls = 0;
    await tester.pumpWidget(screen(ReferralRewardCard(
        reward: reward(now.add(const Duration(seconds: 2))),
        now: () => now,
        onActivate: () async {
          calls++;
        })));
    expect(find.text('Активировать'), findsOneWidget);
    await capture(tester, 'available');
    now = now.add(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Активировать'), findsNothing);
    expect(find.text('Срок истёк'), findsOneWidget);
    await capture(tester, 'expired');
    expect(calls, 0);
    final end = now.add(const Duration(hours: 12));
    await tester.pumpWidget(screen(ReferralRewardCard(
        reward: reward(end),
        now: () => now,
        onActivate: () async {
          calls++;
        })));
    expect(find.text('Активировать'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    now = end;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('Активировать'), findsNothing);
    expect(calls, 0);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'activation suppresses duplicates, retains reward on failure and allows retry',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime.utc(2026, 10, 16);
    var calls = 0;
    var pending = Completer<void>();
    await tester.pumpWidget(screen(ReferralRewardCard(
        reward: reward(now.add(const Duration(days: 1))),
        now: () => now,
        onActivate: () {
          calls++;
          return pending.future;
        })));
    await tester.tap(find.text('Активировать'));
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    expect(calls, 1);
    pending.completeError(StateError('isolated rejection'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('Понятно'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Публикация профиля'), findsOneWidget);
    pending = Completer<void>();
    await tester.tap(find.text('Активировать'));
    await tester.pump();
    expect(calls, 2);
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.text('Использована'), findsOneWidget);
    await capture(tester, 'redeemed');
    expect(find.text('Активировать'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'redeemed long conditions fit narrow screens with enlarged text without an activation button',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime.utc(2026, 10, 16);
    await tester.pumpWidget(RepaintBoundary(
        key: const ValueKey('reward-capture'),
        child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: jobaTheme(),
            home: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
                child: Scaffold(
                    body: SingleChildScrollView(
                        child: ReferralRewardCard(
                            reward: reward(now.add(const Duration(days: 1)),
                                status: 'redeemed'),
                            now: () => now,
                            onActivate: () async {
                              fail('Redeemed rewards cannot activate');
                            })))))));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await capture(tester, 'narrow-long');
    expect(find.text('Использована'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
