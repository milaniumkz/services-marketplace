// One network per session, with a single fallback. Never stack or rapidly rotate
// native platform views when navigating between screens.
List<String> nativeBannerNetworks(Map<String, dynamic> config,
    {required bool android, required bool googleFirst}) {
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
  return googleFirst ? networks.reversed.toList() : networks;
}
