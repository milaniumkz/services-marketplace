import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'api.dart';

const regionCodes = ['KZ', 'KG', 'RU', 'BY'];
const interfaceLocales = ['ru', 'kk', 'sr', 'be'];

/// Endpoints are build configuration, never values supplied by an API response.
class RegionGateway {
  final Map<String, String> endpoints;
  final JobaApi Function(String country, String endpoint) factory;
  RegionGateway(Map<String, String> endpoints,
      {JobaApi Function(String, String)? factory})
      : endpoints = Map.unmodifiable(endpoints),
        factory = factory ??
            ((country, endpoint) => JobaApi(endpoint,
                vault: SecureSessionVault('joba.session.$country.$endpoint')));
  factory RegionGateway.environment() {
    const configured = String.fromEnvironment('JOBA_API_URL',
        defaultValue: kReleaseMode ? '' : 'http://localhost:3000');
    const sameOrigin = bool.fromEnvironment('JOBA_WEB_SAME_ORIGIN');
    final shared = kIsWeb && sameOrigin ? Uri.base.origin : configured;
    String endpoint(String value) => value.isEmpty ? shared : value;
    return RegionGateway({
      'KZ': endpoint(const String.fromEnvironment('JOBA_KZ_API_URL')),
      'KG': endpoint(const String.fromEnvironment('JOBA_KG_API_URL')),
      'RU': endpoint(const String.fromEnvironment('JOBA_RU_API_URL')),
      'BY': endpoint(const String.fromEnvironment('JOBA_BY_API_URL')),
    });
  }
  JobaApi create(String country) {
    final endpoint = endpoints[country];
    if (!regionCodes.contains(country) ||
        endpoint == null ||
        endpoint.isEmpty) {
      throw ApiException('REGION_UNAVAILABLE', 'Регион пока недоступен', 503);
    }
    // Validate before calling an injected factory or sending any credentials.
    final uri = Uri.tryParse(endpoint);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (kReleaseMode && uri.scheme != 'https')) {
      throw ApiException('REGION_UNAVAILABLE', 'Регион пока недоступен', 503);
    }
    return factory(country, endpoint);
  }
}

/// Device preferences contain no account records, tokens or endpoint overrides.
class DevicePreferences {
  final SessionVault vault;
  Future<void> _writes = Future.value();
  DevicePreferences(this.vault);
  Future<Json> read() async {
    final encoded = await vault.read();
    if (encoded == null) return {'country': 'KZ', 'locale': 'ru'};
    try {
      final value = jsonDecode(encoded) as Json;
      return {
        'country':
            regionCodes.contains(value['country']) ? value['country'] : 'KZ',
        'locale':
            interfaceLocales.contains(value['locale']) ? value['locale'] : 'ru',
      };
    } on FormatException {
      return {'country': 'KZ', 'locale': 'ru'};
    } on TypeError {
      return {'country': 'KZ', 'locale': 'ru'};
    }
  }

  Future<void> save(String country, String locale) {
    if (!regionCodes.contains(country) || !interfaceLocales.contains(locale)) {
      throw ArgumentError('Invalid device country or interface locale');
    }
    final operation = _writes.catchError((Object _) {}).then(
        (_) => vault.write(jsonEncode({'country': country, 'locale': locale})));
    _writes = operation;
    return operation;
  }
}
