import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:services_marketplace/advertising/banner_policy.dart';
import 'package:services_marketplace/advertising/placements.dart';

void main() {
  final config = <String, dynamic>{
    'enabled': true,
    'admob_enabled': true,
    'rewarded_enabled': true,
    'admob_android_banner_id': 'ca-app-pub-5590941579295248/9567708649',
    'admob_android_rewarded_id': 'ca-app-pub-5590941579295248/6068875357',
    'android_banner_id': 'R-M-20254161-1',
    'android_rewarded_id': 'R-M-20254161-3',
    'ios_banner_id': '',
  };
  test(
      'all routes are inventoried and 100 eligible screens split exactly 50/50',
      () {
    final inventory = jsonDecode(
        File('../../services/api/src/ad-placements.json')
            .readAsStringSync()) as List;
    final source = File('lib/screens/marketplace.dart').readAsStringSync();
    final routeSwitch = source.substring(source.indexOf('    switch (route) {'),
        source.indexOf('  Widget countryCard'));
    final routes = RegExp("case '([^']+)':")
        .allMatches(routeSwitch)
        .map((m) => m[1])
        .toSet();
    expect(inventory.map((i) => i['route']).toSet(), routes);
    expect(bannerPlacements.length, 100);
    expect(bannerPlacements.values.where((n) => n == 'google').length, 50);
    expect(bannerPlacements.values.where((n) => n == 'yandex').length, 50);
    for (final row in inventory) {
      expect(bannerPlacements[row['route']], row['network']);
      if (row['network'] == null) expect(row['excluded_reason'], isNotEmpty);
    }
  });
  test(
      'banner network is fixed for each route and never falls back to the other',
      () {
    expect(
        nativeBannerNetworks(config, android: true, route: 'home'), ['google']);
    expect(nativeBannerNetworks(config, android: true, route: 'orders'),
        ['yandex']);
    expect(
        nativeBannerNetworks({...config, 'admob_enabled': false},
            android: true, route: 'home'),
        isEmpty);
    for (final route in [
      'checkout',
      'bank-payment',
      'bank-payment-open',
      'payment-pending',
      'promotion-checkout',
      'unlock',
      'login',
      'face-enroll',
      'unknown'
    ]) {
      expect(
          nativeBannerNetworks(config, android: true, route: route), isEmpty);
    }
  });
  test('global switch, explicit refusal, wrong IDs and platform are respected',
      () {
    for (final patch in [
      {'enabled': false},
      {'consent_recorded': true, 'consent': false}
    ]) {
      expect(
          nativeBannerNetworks({...config, ...patch},
              android: true, route: 'orders'),
          isEmpty);
    }
    expect(
        nativeBannerNetworks(config, android: false, route: 'home'), isEmpty);
    expect(
        nativeBannerNetworks({...config, 'android_banner_id': 'R-A-20302217-1'},
            android: true, route: 'orders'),
        isEmpty);
  });
  test('only Rewarded uses a shuffled primary and a single fallback', () {
    expect(nativeRewardNetworks(config, android: true, googleFirst: true),
        ['google', 'yandex']);
    expect(nativeRewardNetworks(config, android: true, googleFirst: false),
        ['yandex', 'google']);
    expect(
        nativeRewardNetworks({...config, 'admob_enabled': false},
            android: true, googleFirst: true),
        ['yandex']);
    expect(
        nativeRewardNetworks({...config, 'rewarded_enabled': false},
            android: true, googleFirst: true),
        isEmpty);
  });
}
