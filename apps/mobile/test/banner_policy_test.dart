import 'package:flutter_test/flutter_test.dart';
import 'package:services_marketplace/advertising/banner_policy.dart';

void main() {
  final config = <String, dynamic>{
    'enabled': true,
    'admob_enabled': true,
    'admob_android_banner_id': 'ca-app-pub-5590941579295248/9567708649',
    'android_banner_id': 'R-M-20254161-1',
    'ios_banner_id': '',
  };
  test('both networks can lead with exactly one fallback', () {
    expect(nativeBannerNetworks(config, android: true, googleFirst: true),
        ['google', 'yandex']);
    expect(nativeBannerNetworks(config, android: true, googleFirst: false),
        ['yandex', 'google']);
  });
  test('global switch, explicit refusal and per-network switch are respected',
      () {
    for (final patch in [
      {'enabled': false},
      {'consent_recorded': true, 'consent': false}
    ]) {
      expect(
          nativeBannerNetworks({...config, ...patch},
              android: true, googleFirst: true),
          isEmpty);
    }
    expect(
        nativeBannerNetworks({...config, 'admob_enabled': false},
            android: true, googleFirst: true),
        ['yandex']);
  });
  test('Android IDs are never used on iOS or accepted with the wrong format',
      () {
    expect(nativeBannerNetworks(config, android: false, googleFirst: true),
        isEmpty);
    expect(
        nativeBannerNetworks({...config, 'android_banner_id': 'R-A-20302217-1'},
            android: true, googleFirst: false),
        ['google']);
    expect(
        nativeBannerNetworks({...config, 'admob_android_banner_id': 'bad'},
            android: true, googleFirst: true),
        ['yandex']);
  });
}
