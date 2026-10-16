import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:services_marketplace/core/api.dart';
import 'package:services_marketplace/main.dart';
import 'package:services_marketplace/screens/marketplace.dart';

class _Vault implements SessionVault {
  Future<String?> read() async => null;
  Future<void> write(String v) async {}
  Future<void> clear() async {}
}

void main() {
  testWidgets(
      'registration follows the profile step contract, prevents password mismatch, and preserves fields after rejection',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final registrations = <Json>[];
    final api = JobaApi('https://isolated.example', vault: _Vault(),
        transport: MockClient((r) async {
      if (r.url.path.endsWith('/auth/register')) {
        registrations.add(jsonDecode(r.body) as Json);
        return http.Response(
            '{"error":{"code":"VALIDATION_ERROR","message":"Регистрация отклонена"}}',
            422,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }
      return http.Response('{"data":{"items":[]},"meta":{}}', 200);
    }));
    await tester.pumpWidget(JobaApp(api: api));
    await tester.pumpAndSettle();
    final dynamic state = tester.state(find.byType(Marketplace));
    state.go('register');
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    expect(fields, findsNWidgets(3));
    expect(find.text('Как к вам обращаться'), findsNothing);
    await tester.enterText(fields.at(0), '+77000000001');
    await tester.enterText(fields.at(1), 'Isolated long password');
    await tester.enterText(fields.at(2), 'Different long password');
    await tester.scrollUntilVisible(find.text('Продолжить'), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Продолжить'));
    await tester.pumpAndSettle();
    expect(registrations, isEmpty);
    await tester.ensureVisible(fields.at(2));
    await tester.enterText(fields.at(2), 'Isolated long password');
    await tester.scrollUntilVisible(find.text('Продолжить'), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Продолжить'));
    await tester.pumpAndSettle();
    expect(registrations.single, {
      'country': 'KZ',
      'phone': '+77000000001',
      'password': 'Isolated long password',
      'locale': 'ru'
    });
    expect(tester.widget<TextFormField>(fields.at(0)).controller!.text,
        '+77000000001');
    expect(tester.widget<TextFormField>(fields.at(1)).controller!.text,
        'Isolated long password');
    expect(api.authenticated, false);
    expect(state.route, 'register');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    api.dispose();
  });
}
