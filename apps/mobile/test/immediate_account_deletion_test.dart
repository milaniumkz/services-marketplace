import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:services_marketplace/core/api.dart';
import 'package:services_marketplace/screens/privacy_states.dart';
import 'widget_test.dart' show MemoryVault;

void main() {
  testWidgets(
      'immediate deletion confirms locally before clearing the revoked session without a follow-up authenticated read',
      (t) async {
    var posts = 0;
    String? route;
    final api = JobaApi('https://isolated.example', vault: MemoryVault(),
        transport: MockClient((r) async {
      expect(r.method, 'POST');
      expect(r.url.path.endsWith('/me/privacy-requests'), true);
      expect(jsonDecode(r.body),
          {'type': 'delete', 'current_password': 'recording-password'});
      posts++;
      return http.Response(
          jsonEncode({
            'data': {
              'id': 'removed',
              'account_deleted': true,
              'status': 'limited_retention'
            },
            'meta': {}
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    }));
    addTearDown(api.dispose);
    api.session = {
      'access_token': 'isolated',
      'user': {'id': 'owner', 'country': 'KZ'}
    };
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: PrivacyStates(
                api: api, mode: 'delete-confirm', onGo: (r, _) => route = r))));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextFormField), 'recording-password');
    await t.ensureVisible(find.text('Подтвердить запрос'));
    await t.tap(find.text('Подтвердить запрос'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('Аккаунт удалён'), findsOneWidget);
    expect(api.authenticated, true);
    expect(posts, 1);
    await t.tap(find.text('Понятно'));
    await t.pumpAndSettle();
    expect(api.authenticated, false);
    expect(route, 'welcome');
    expect(posts, 1);
  });
}
