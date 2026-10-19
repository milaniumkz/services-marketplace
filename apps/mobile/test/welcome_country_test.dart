import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:services_marketplace/core/api.dart';
import 'package:services_marketplace/core/regions.dart';
import 'package:services_marketplace/main.dart';
import 'package:services_marketplace/screens/marketplace.dart';
import 'widget_test.dart' show MemoryVault, ok;

void main() {
  testWidgets(
      'each active welcome country selects its own API, persists selection and opens the matching phone form',
      (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final vault = MemoryVault();
    final clients = <JobaApi>[];
    final regions = RegionGateway({
      for (final code in regionCodes)
        code: 'https://${code.toLowerCase()}.example'
    }, factory: (country, endpoint) {
      final api = JobaApi(endpoint,
          vault: MemoryVault(),
          transport: MockClient((_) async => ok({'items': []})));
      clients.add(api);
      return api;
    });
    await t.pumpWidget(
        JobaApp(regions: regions, preferences: DevicePreferences(vault)));
    await t.pumpAndSettle();
    final dynamic state = t.state(find.byType(Marketplace));
    for (final entry in {
      'Казахстан': 'KZ',
      'Кыргызстан': 'KG',
      'Россия': 'RU',
      'Беларусь': 'BY'
    }.entries) {
      state.go('welcome');
      await t.pumpAndSettle();
      await t.ensureVisible(find.text(entry.key));
      await t.tap(find.text(entry.key));
      await t.pumpAndSettle();
      expect(state.country, entry.value);
      expect(state.api.base.host, '${entry.value.toLowerCase()}.example');
      // Initial KZ may already be the stored default; all explicit changes persist.
      if (vault.value != null)
        expect(jsonDecode(vault.value!)['country'], entry.value);
      expect(
          find.byWidgetPredicate((w) =>
              w is Semantics &&
              w.properties.selected == true &&
              w.properties.button == true),
          findsOneWidget);
      await t.tap(find.text('Продолжить'));
      await t.pumpAndSettle();
      expect(state.route, 'login');
      final prefix =
          {'KZ': '+7', 'KG': '+996', 'RU': '+7', 'BY': '+375'}[entry.value]!;
      expect(find.text('$prefix · номер телефона'), findsOneWidget);
    }
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    expect(clients.every((c) => c.disposed), true);
  });
}
