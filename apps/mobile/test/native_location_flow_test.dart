import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:services_marketplace/core/api.dart';
import 'package:services_marketplace/core/device_location.dart';
import 'package:services_marketplace/core/external_activity.dart';
import 'package:services_marketplace/core/widgets.dart';
import 'widget_test.dart' show MemoryVault, ok;

void main() {
  const location = MethodChannel('joba.location');
  testWidgets(
      'nearby orders survive a native permission dialog and retain precise coordinates',
      (t) async {
    final gate = Completer<Map<String, dynamic>>();
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(location, (call) {
      expect(call.method, 'current');
      expect(externalActivityActive, isTrue);
      return gate.future;
    });
    addTearDown(() => t.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(location, null));
    final queries = <Uri>[];
    final api = JobaApi('https://isolated.example', vault: MemoryVault(),
        transport: MockClient((r) async {
      queries.add(r.url);
      return ok({
        'items': [
          {'id': 'local', 'title': 'Работа рядом'}
        ],
        'meta': {'has_any': true}
      });
    }));
    api.session = {'access_token':'token','user':{'id':'executor','active_role':'executor'}};
    addTearDown(api.dispose);
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SearchListings(
                api: api,
                path: '/orders',
                initialFilters: const {'city': 'Караганда'},
                tile: (row) => Text(row['title'])))));
    await t.pumpAndSettle();
    await t.tap(find.text('Рядом со мной'));
    await t.pump();
    expect(externalActivityActive, isTrue);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    gate.complete(
        {'latitude': 49.812345, 'longitude': 73.123456, 'accuracy': 15.0});
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pumpAndSettle();
    final nearest = queries.last;
    expect(nearest.queryParameters['near_lat'], '49.812345');
    expect(nearest.queryParameters['near_lon'], '73.123456');
    expect(nearest.queryParameters['radius_km'], '50');
    expect(nearest.queryParameters.containsKey('city'), isFalse);
    expect(find.text('Работа рядом'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets(
      'denied or invalid native location does not request an unfiltered order list',
      (t) async {
    var invalid = false;
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(location,
        (_) async {
      if (!invalid) throw PlatformException(code: 'GPS_DENIED');
      return {'latitude': 300.0, 'longitude': 73.0};
    });
    addTearDown(() => t.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(location, null));
    await expectLater(
        currentDeviceLocation(), throwsA(isA<PlatformException>()));
    invalid = true;
    await expectLater(currentDeviceLocation(), throwsA(isA<ApiException>()));
  });
}
