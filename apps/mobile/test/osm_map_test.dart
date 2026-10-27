import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:services_marketplace/core/api.dart';
import 'package:services_marketplace/core/osm_map.dart';
import 'package:services_marketplace/screens/osm_location_picker.dart';

class TestTiles extends TileProvider {
  final image = MemoryImage(base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAQAAAAEAAQMAAABmvDolAAAAAXNSR0IB2cksfwAAAAlwSFlzAAALEwAACxMBAJqcGAAAAANQTFRF////p8QbyAAAAB9JREFUeJztwQENAAAAwqD3T20ON6AAAAAAAAAAAL4NIQAAAfFnIe4AAAAASUVORK5CYII='));
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      image;
}

void main() {
  testWidgets(
      'OSM centers on device without moving saved pin and retains attribution',
      (t) async {
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: OsmMap(
                initialCenter: const LatLng(43.2, 76.9),
                selected: const LatLng(43.2, 76.9),
                tileProvider: TestTiles(),
                locate: () async =>
                    {'latitude': 49.812345, 'longitude': 73.123456}))));
    await t.pumpAndSettle();
    final map = t.widget<FlutterMap>(find.byType(FlutterMap));
    expect(map.mapController!.camera.center.latitude, closeTo(49.812345, 1e-6));
    expect(
        map.mapController!.camera.center.longitude, closeTo(73.123456, 1e-6));
    expect(t.widget<TileLayer>(find.byType(TileLayer)).urlTemplate,
        'https://tile.openstreetmap.org/{z}/{x}/{y}.png');
    expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
    expect(t.widget<OsmMap>(find.byType(OsmMap)).selected,
        const LatLng(43.2, 76.9));
    await t.pumpWidget(const SizedBox());
  });
  testWidgets(
      'late GPS does not move a manually panned map or select a new address',
      (t) async {
    final pending = Completer<Json?>();
    var selected = false;
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: OsmMap(
                initialCenter: const LatLng(49.8, 73.1),
                tileProvider: TestTiles(),
                locate: () => pending.future,
                onLocated: (_) => selected = true))));
    await t.pump(const Duration(milliseconds:300));
    await t.drag(find.byType(FlutterMap), const Offset(120, 0));
    await t.pump(const Duration(seconds:1));
    final controller =
        t.widget<FlutterMap>(find.byType(FlutterMap)).mapController!;
    final manualCenter = controller.camera.center;
    pending.complete({'latitude': 43.2, 'longitude': 76.9});
    await t.pumpAndSettle();
    expect(controller.camera.center.latitude,closeTo(manualCenter.latitude,1e-6));
    expect(controller.camera.center.longitude,isNot(closeTo(76.9,0.001)));
    expect(selected, false);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('denied geolocation still allows manual map selection',
      (t) async {
    LatLng? chosen;
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: OsmMap(
                initialCenter: const LatLng(49.8, 73.1),
                tileProvider: TestTiles(),
                locate: () async =>
                    throw ApiException('GPS_DENIED', 'Выберите точку вручную.'),
                onSelected: (point) => chosen = point))));
    await t.pumpAndSettle();
    expect(find.text('Выберите точку вручную.'), findsOneWidget);
    await t.tapAt(t.getCenter(find.byType(FlutterMap)));
    await t.pump(const Duration(milliseconds: 400));
    await t.pumpAndSettle();
    expect(chosen, isNotNull);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets(
      'GPS reverse address and database city return with exact selected point',
      (t) async {
    Json? picked;
    final api = JobaApi('https://isolated.example',
        transport: MockClient((r) async => http.Response(
            jsonEncode({
              'data': r.url.path.contains('reverse')
                  ? {
                      'items': [
                        {
                          'latitude': 49.812345,
                          'longitude': 73.123456,
                          'address': 'Караганда, Тестовая улица, 10',
                          'city': {'id': 'city', 'name': 'Караганда'}
                        }
                      ]
                    }
                  : {'items': []}
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'})))
      ..session = {'access_token': 'fixture'};
    await t.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () async {
                      picked = await Navigator.push(
                          context,
                          MaterialPageRoute<Json>(
                              builder: (_) => OsmLocationPicker(
                                  api: api,
                                  tileProvider: TestTiles(),
                                  locate: () async => {
                                        'latitude': 49.812345,
                                        'longitude': 73.123456
                                      })));
                    },
                    child: const Text('Карта'))))));
    await t.tap(find.text('Карта'));
    await t.pumpAndSettle();
    await t.pump(const Duration(seconds: 1));
    await t.pumpAndSettle();
    expect(find.text('Караганда, Тестовая улица, 10'), findsOneWidget);
    await t.tap(find.text('Использовать этот адрес'));
    await t.pumpAndSettle();
    expect(picked!['latitude'], 49.812345);
    expect(picked!['longitude'], 73.123456);
    expect(picked!['city']['id'], 'city');
  });
  testWidgets(
      'address search runs only on submit and returns a selected result',
      (t) async {
    var searches = 0;
    final api =
        JobaApi('https://isolated.example', transport: MockClient((r) async {
      if (r.url.path.contains('/geo/search')) {
        searches++;
        return http.Response(
            jsonEncode({
              'data': {
                'items': [
                  {
                    'latitude': 49.8,
                    'longitude': 73.1,
                    'address': 'Тестовый адрес из поиска',
                    'city': {'id': 'city', 'name': 'Караганда'}
                  }
                ]
              }
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }
      return http.Response(
          jsonEncode({
            'data': {'items': []}
          }),
          200);
    }))
          ..session = {'access_token': 'fixture'};
    await t.pumpWidget(MaterialApp(
        home: OsmLocationPicker(
            api: api,
            tileProvider: TestTiles(),
            locate: () async =>
                throw ApiException('GPS_DENIED', 'Выберите точку вручную.'))));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).first, 'Тестовая улица');
    await t.pump(const Duration(seconds: 2));
    expect(searches, 0);
    await t.tap(find.byTooltip('Найти адрес'));
    await t.pumpAndSettle();
    expect(searches, 1);
    await t.tap(find.text('Тестовый адрес из поиска'));
    await t.pumpAndSettle();
    expect(t.widget<TextField>(find.byType(TextField).last).controller!.text,
        'Тестовый адрес из поиска');
    await t.pumpWidget(const SizedBox());
  });
}
