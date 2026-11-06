import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
// ignore: implementation_imports
import 'package:google_mobile_ads/src/ad_instance_manager.dart';
import 'package:services_marketplace/advertising/google_rewarded.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final channel = MethodChannel('plugins.flutter.io/google_mobile_ads',
      StandardMethodCodec(AdMessageCodec()));
  final calls = <MethodCall>[];
  Future<void> event(int id, String name,
      [Map<String, Object?> extra = const {}]) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
            channel.name,
            channel.codec.encodeMethodCall(MethodCall('onAdEvent', {
              'adId': id,
              'eventName': name,
              ...extra,
            })),
            (_) {});
  }

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'MobileAds#initialize')
        return InitializationStatus(<String, AdapterStatus>{});
      return null;
    });
  });
  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));
  for (final earned in [false, true]) {
    testWidgets(
        'Google reward requires earned callback before dismissal: $earned',
        (t) async {
      final future = playGoogleRewarded(
          'ca-app-pub-3940256099942544/5224354917',
          current: () => true);
      await t.pumpAndSettle();
      final id = calls
          .singleWhere((c) => c.method == 'loadRewardedAd')
          .arguments['adId'] as int;
      await event(id, 'onAdLoaded');
      await t.pumpAndSettle();
      expect(calls.any((c) => c.method == 'showAdWithoutView'), true);
      if (earned)
        await event(id, 'onRewardedAdUserEarnedReward',
            {'rewardItem': RewardItem(1, 'test')});
      await event(id, 'onAdDismissedFullScreenContent');
      await t.pumpAndSettle();
      expect(await future, earned);
      expect(calls.where((c) => c.method == 'disposeAd').length, 1);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets('no fill raises a load failure without showing a fullscreen ad',
      (t) async {
    final future = playGoogleRewarded('ca-app-pub-3940256099942544/5224354917',
        current: () => true);
    final assertion = expectLater(future, throwsStateError);
    await t.pumpAndSettle();
    final id = calls
        .singleWhere((c) => c.method == 'loadRewardedAd')
        .arguments['adId'] as int;
    await event(id, 'onAdFailedToLoad',
        {'loadAdError': LoadAdError(3, 'test', 'no fill', null)});
    await t.pumpAndSettle();
    await assertion;
    expect(calls.any((c) => c.method == 'showAdWithoutView'), false);
    expect(t.takeException(), isNull);
  });
}
