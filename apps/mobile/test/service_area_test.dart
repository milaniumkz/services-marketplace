import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:services_marketplace/core/api.dart';
import 'package:services_marketplace/screens/service_area.dart';

void main() {
  testWidgets(
      'service area requires an explicit opt-in and rounds the device position before saving',
      (t) async {
    Json? sent;
    var saved = false;
    final api = JobaApi('https://example.com', transport: MockClient((r) async {
      if (r.method == 'PATCH') {
        sent = jsonDecode(r.body);
        return http.Response(jsonEncode({'data': {}}), 200);
      }
      return http.Response(
          jsonEncode({
            'data': {
              'profile': {
                'version': 7,
                'city': 'Алматы',
                'public_location': null
              }
            }
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    }))
      ..session = {'access_token': 'isolated'};
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ServiceArea(
                api: api,
                locate: () async =>
                    {'latitude': 43.238945, 'longitude': 76.88941},
                onSaved: () => saved = true))));
    await t.pumpAndSettle();
    await t.tap(find.byType(SwitchListTile));
    await t.pump();
    expect(t.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    await t.tap(find.text('Указать зону по местоположению'));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.text('Сохранить выбор'), 150);
    await t.tap(find.text('Сохранить выбор'));
    await t.pumpAndSettle();
    expect(sent, containsPair('expected_version', 7));
    expect(sent!['enabled'], true);
    expect(sent!['location'], {'latitude': 43.24, 'longitude': 76.89});
    expect(saved, true);
  });
  testWidgets(
      'disabling an existing area sends explicit removal without requesting location',
      (t) async {
    Json? sent;
    var located = false;
    final api = JobaApi('https://example.com', transport: MockClient((r) async {
      if (r.method == 'PATCH') {
        sent = jsonDecode(r.body);
        return http.Response(jsonEncode({'data': {}}), 200);
      }
      return http.Response(
          jsonEncode({
            'data': {
              'profile': {
                'version': 8,
                'public_location': {'latitude': 43.24, 'longitude': 76.89}
              }
            }
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    }))
      ..session = {'access_token': 'isolated'};
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ServiceArea(
                api: api,
                locate: () async {
                  located = true;
                  return null;
                },
                onSaved: () {}))));
    await t.pumpAndSettle();
    await t.tap(find.byType(SwitchListTile));
    await t.pump();
    await t.tap(find.text('Сохранить выбор'));
    await t.pumpAndSettle();
    expect(sent, {'expected_version': 8, 'enabled': false});
    expect(located, false);
  });
}
