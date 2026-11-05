import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

Future<InitializationStatus>? _initialization;

class GoogleBanner extends StatefulWidget {
  final String unitId;
  final bool personalized;
  final VoidCallback onFailed;
  const GoogleBanner(
      {super.key,
      required this.unitId,
      required this.personalized,
      required this.onFailed});
  @override
  State<GoogleBanner> createState() => _GoogleBannerState();
}

class _GoogleBannerState extends State<GoogleBanner> {
  BannerAd? _ad;
  bool _ready = false, _failed = false;
  Timer? _timeout;
  void _release(BannerAd ad) {
    ad.dispose().catchError((Object _) {});
  }

  void _fail() {
    if (!mounted || _failed) return;
    _failed = true;
    _timeout?.cancel();
    final ad = _ad;
    _ad = null;
    if (ad != null) _release(ad);
    widget.onFailed();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      try {
        await (_initialization ??= MobileAds.instance.initialize())
            .timeout(const Duration(seconds: 20));
      } catch (_) {
        _initialization = null;
        rethrow;
      }
      if (!mounted) return;
      final ad = BannerAd(
        adUnitId: widget.unitId,
        size: AdSize.banner,
        request: AdRequest(nonPersonalizedAds: !widget.personalized),
        listener: BannerAdListener(
          onAdLoaded: (ad) {
            if (mounted && identical(ad, _ad)) {
              _timeout?.cancel();
              setState(() => _ready = true);
            }
          },
          onAdFailedToLoad: (ad, error) {
            if (mounted && identical(ad, _ad)) {
              _fail();
            }
          },
        ),
      );
      _ad = ad;
      _timeout = Timer(const Duration(seconds: 20), _fail);
      await ad.load();
    } catch (_) {
      _fail();
    }
  }

  @override
  void dispose() {
    _timeout?.cancel();
    if (_ad != null) _release(_ad!);
    _ad = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => !_ready || _ad == null
      ? const SizedBox.shrink()
      : SizedBox(
          height: 50,
          child: Center(
              child:
                  SizedBox(width: 320, height: 50, child: AdWidget(ad: _ad!))));
}
