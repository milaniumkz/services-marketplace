import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:services_marketplace/core/api.dart';
import 'package:services_marketplace/core/widgets.dart';

void main() {
  testWidgets(
      'promoted cards use server targets, carry a label and open the actual target',
      (t) async {
    String? opened;
    final api = JobaApi('https://example.com', transport: MockClient((r) async {
      expect(r.url.queryParameters['placement_id'], 'search.services.promoted');
      return http.Response(
          jsonEncode({
            'data': {
              'items': [
                {
                  'boost_id': 'actual-boost',
                  'promoted': true,
                  'target_type': 'contractor',
                  'target': {
                    'id': 'actual-profile',
                    'title': 'Actual published service',
                    'city': 'Almaty'
                  }
                }
              ]
            }
          }),
          200);
    }))
      ..session = {'access_token': 'isolated'};
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: PromotedListings(
                api: api,
                placement: 'search.services.promoted',
                onOpen: (type, id) => opened = '$type:$id'))));
    await t.pumpAndSettle();
    expect(find.text('Продвигается'), findsNWidgets(2));
    await t.tap(find.text('Actual published service'));
    expect(opened, 'services:actual-profile');
  });
  testWidgets(
      'unavailable optional inventory leaves the organic content usable',
      (t) async {
    final api = JobaApi('https://example.com',
        transport: MockClient((r) async => http.Response(
            jsonEncode({
              'error': {
                'code': 'ENTITLEMENT_REQUIRED',
                'message': 'Access required'
              }
            }),
            403)))
      ..session = {'access_token': 'isolated'};
    var tapped = false;
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Column(children: [
      PromotedListings(api: api, placement: 'search.services.promoted'),
      TextButton(
          onPressed: () => tapped = true, child: const Text('Organic result'))
    ]))));
    await t.pumpAndSettle();
    expect(find.text('Продвигается'), findsNothing);
    await t.tap(find.text('Organic result'));
    expect(tapped, true);
  });
}
