import 'placements.dart';

// Ordinary banners use only the network assigned to the route.
// A shuffled primary and fallback are reserved for explicit rewarded playback.
List<String> nativeBannerNetworks(Map<String, dynamic> config,
    {required bool android, required String route}) {
  if (config['enabled'] != true ||
      config['consent_recorded'] == true && config['consent'] != true) {
    return [];
  }
  final yandexId = config[android ? 'android_banner_id' : 'ios_banner_id'];
  final googleId = config['admob_android_banner_id'];
  final networks = <String>[
    if (yandexId is String && RegExp(r'^R-M-\d+-\d+$').hasMatch(yandexId))
      'yandex',
    if (android &&
        config['admob_enabled'] == true &&
        googleId is String &&
        RegExp(r'^ca-app-pub-\d{16}/\d{10}$').hasMatch(googleId))
      'google',
  ];
  final assigned = bannerPlacements[route];
  return networks.where((network) => network == assigned).toList();
}

List<String> nativeRewardNetworks(Map<String, dynamic> config,
    {required bool android, required bool googleFirst}) {
  if (config['rewarded_enabled'] != true) return [];
  final networks = <String>[
    if (RegExp(r'^R-M-\d+-\d+$').hasMatch(
        '${config[android ? 'android_rewarded_id' : 'ios_rewarded_id'] ?? ''}'))
      'yandex',
    if (android &&
        config['admob_enabled'] == true &&
        RegExp(r'^ca-app-pub-\d{16}/\d{10}$')
            .hasMatch('${config['admob_android_rewarded_id'] ?? ''}'))
      'google',
  ];
  return googleFirst ? networks.reversed.toList() : networks;
}
