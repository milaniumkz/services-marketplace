// SDK channel is mocked: these tests never request live ads or record impressions.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
// ignore: implementation_imports
import 'package:google_mobile_ads/src/ad_instance_manager.dart';
import 'package:services_marketplace/advertising/google_banner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final channel = MethodChannel('plugins.flutter.io/google_mobile_ads',
      StandardMethodCodec(AdMessageCodec()));
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'MobileAds#initialize') {
        return InitializationStatus(<String, AdapterStatus>{});
      }
      return null;
    });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  testWidgets('no fill falls back once and disposes the native ad', (t) async {
    var failures = 0;
    await t.pumpWidget(MaterialApp(
        home: GoogleBanner(
            unitId: 'ca-app-pub-3940256099942544/6300978111',
            personalized: false,
            onFailed: () => failures++)));
    await t.pumpAndSettle();
    final load = calls.singleWhere((c) => c.method == 'loadBannerAd');
    expect((load.arguments['request'] as AdRequest).nonPersonalizedAds, true);
    final event = channel.codec.encodeMethodCall(MethodCall('onAdEvent', {
      'adId': load.arguments['adId'],
      'eventName': 'onAdFailedToLoad',
      'loadAdError': LoadAdError(3, 'test', 'no fill', null),
    }));
    await t.binding.defaultBinaryMessenger
        .handlePlatformMessage(channel.name, event, (_) {});
    await t.pumpAndSettle();
    expect(failures, 1);
    expect(calls.where((c) => c.method == 'disposeAd').length, 1);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 21));
    expect(failures, 1);
    expect(t.takeException(), isNull);
  });
  testWidgets(
      'stalled load falls back; late callbacks cannot revive disposed banner',
      (t) async {
    var failures = 0;
    await t.pumpWidget(MaterialApp(
        home: GoogleBanner(
            unitId: 'ca-app-pub-3940256099942544/6300978111',
            personalized: false,
            onFailed: () => failures++)));
    await t.pumpAndSettle();
    await t.pump(const Duration(seconds: 21));
    expect(failures, 1);
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
    expect(calls.where((c) => c.method == 'disposeAd').length, 1);
    expect(t.takeException(), isNull);
  });
}
