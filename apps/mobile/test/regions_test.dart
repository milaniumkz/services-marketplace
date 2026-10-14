import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:services_marketplace/core/api.dart';
import 'package:services_marketplace/core/regions.dart';
import 'package:services_marketplace/main.dart';
import 'package:services_marketplace/screens/marketplace.dart';
import 'widget_test.dart' show MemoryVault, ok;

void main() {
  test('Preferences retain only validated device fields and serialize writes',
      () async {
    final vault = MemoryVault(), preferences = DevicePreferences(MemoryVault());
    expect(await preferences.read(), {'country': 'KZ', 'locale': 'ru'});
    vault.value = jsonEncode({
      'country': 'XX',
      'locale': 'xx',
      'endpoint': 'https://attacker.example',
      'access_token': 'ignored'
    });
    final parsed = DevicePreferences(vault);
    expect(await parsed.read(), {'country': 'KZ', 'locale': 'ru'});
    await Future.wait([parsed.save('RS', 'sr'), parsed.save('BY', 'be')]);
    expect(await parsed.read(), {'country': 'BY', 'locale': 'be'});
    expect(jsonDecode(vault.value!).keys.toSet(), {'country', 'locale'});
  });
  test(
      'Unavailable and credential-bearing endpoints never reach the client factory',
      () {
    var calls = 0;
    final regions =
        RegionGateway({'KZ': 'https://user:secret@example.com', 'RS': ''},
            factory: (country, endpoint) {
      calls++;
      throw StateError('must not be called');
    });
    expect(() => regions.create('KZ'), throwsA(isA<ApiException>()));
    expect(() => regions.create('RS'), throwsA(isA<ApiException>()));
    expect(() => regions.create('RU'), throwsA(isA<ApiException>()));
    expect(calls, 0);
  });
  testWidgets(
      'Stored country selects its API before restore; switching logs out only the old region',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final prefs = MemoryVault();
    prefs.value = jsonEncode({'country': 'RS', 'locale': 'ru'});
    final requests = <http.Request>[], clients = <JobaApi>[];
    final regions =
        RegionGateway({'KZ': 'https://kz.example', 'RS': 'https://rs.example'},
            factory: (country, endpoint) {
      final api = JobaApi(endpoint, vault: MemoryVault(),
          transport: MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/auth/logout'))
          return ok({'logged_out': true});
        return ok({'items': []});
      }));
      clients.add(api);
      return api;
    });
    await tester.pumpWidget(
        JobaApp(regions: regions, preferences: DevicePreferences(prefs)));
    await tester.pumpAndSettle();
    final dynamic state = tester.state(find.byType(Marketplace));
    expect(state.country, 'RS');
    expect(state.api.base.host, 'rs.example');
    final original = state.api as JobaApi;
    original.session = {
      'access_token': 'isolated-rs-token',
      'refresh_token': 'isolated-rs-refresh',
      'user': {'id': 'account', 'country': 'RS'}
    };
    state.me = {'id': 'account', 'country': 'RS'};
    await expectLater(state.chooseCountry('BY'), throwsA(isA<ApiException>()));
    expect(state.api, original);
    expect(original.authenticated, true);
    expect(requests, isEmpty);

    await state.chooseCountry('KZ');
    await tester.pumpAndSettle();
    expect(state.api.base.host, 'kz.example');
    expect(state.api.authenticated, false);
    final logout =
        requests.singleWhere((r) => r.url.path.endsWith('/auth/logout'));
    expect(logout.url.host, 'rs.example');
    expect(logout.headers['Authorization'], 'Bearer isolated-rs-token');
    expect(original.disposed, true);
    expect(state.me, null);
    expect(jsonDecode(prefs.value!)['country'], 'KZ');
    await tester.pumpWidget(const SizedBox());
    expect(clients.every((c) => c.disposed), true);
  });
}
