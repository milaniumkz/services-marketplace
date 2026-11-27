import 'dart:async';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../core/external_activity.dart';
import 'google_banner.dart';

Future<bool> playGoogleRewarded(String unitId,
    {required bool Function() current}) async {
  await initializeGoogleAds();
  if (!current()) return false;
  final loaded = Completer<RewardedAd?>();
  bool abandoned = false;
  RewardedAd? ad;
  void release(RewardedAd value) {
    value.dispose().catchError((Object _) {});
  }

  try {
    await RewardedAd.load(
        adUnitId: unitId,
        request: const AdRequest(nonPersonalizedAds: true),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (value) {
            if (abandoned) {
              release(value);
            } else {
              loaded.complete(value);
            }
          },
          onAdFailedToLoad: (_) {
            if (!abandoned) loaded.complete(null);
          },
        ));
    ad = await loaded.future.timeout(const Duration(seconds: 45));
    if (ad == null) throw StateError('Google Rewarded has no fill');
    if (!current()) return false;
    final dismissed = Completer<bool>();
    bool earned = false, showFailed = false;
    ad.fullScreenContentCallback = FullScreenContentCallback<RewardedAd>(
      onAdDismissedFullScreenContent: (_) {
        if (!dismissed.isCompleted) dismissed.complete(earned);
      },
      onAdFailedToShowFullScreenContent: (_, error) {
        showFailed = true;
        if (!dismissed.isCompleted) dismissed.complete(false);
      },
    );
    final result = await withExternalActivity(() async {
      await ad!.show(onUserEarnedReward: (_, reward) {
        earned = true;
      });
      return dismissed.future
          .timeout(const Duration(minutes: 5), onTimeout: () => false);
    });
    if (showFailed) throw StateError('Google Rewarded could not open');
    return result;
  } finally {
    abandoned = true;
    if (ad != null) {
      try {
        await ad.dispose();
      } catch (_) {}
    }
  }
}
