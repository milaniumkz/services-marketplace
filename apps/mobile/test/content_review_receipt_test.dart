import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:services_marketplace/core/api.dart';
import 'package:services_marketplace/core/theme.dart';
import 'package:services_marketplace/screens/content_review_receipt.dart';

class _Vault implements SessionVault {
  Future<String?> read() async => null;
  Future<void> write(String v) async {}
  Future<void> clear() async {}
}

void main() {
  testWidgets(
      'review receipts distinguish drafts from approved visibility and reflect subsequent decisions',
      (tester) async {
    Json current = {};
    var continued = 0;
    bool profile = true;
    final paths = <String>[];
    final api = JobaApi('https://isolated.example', vault: _Vault(),
        transport: MockClient((r) async {
      paths.add(r.url.path);
      return http.Response(
          jsonEncode({
            'data': profile ? {'profile': current} : current,
            'meta': {}
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    }))
      ..session = {
        'access_token': 'isolated',
        'user': {'country': 'KZ'}
      };
    Future<void> show(bool p, Json record) async {
      profile = p;
      current = record;
      await tester.pumpWidget(MaterialApp(
          theme: jobaTheme(),
          home: Scaffold(
              body: ContentReviewReceipt(
                  key: UniqueKey(),
                  api: api,
                  profile: p,
                  id: p ? null : 'project-owned',
                  onContinue: () => continued++))));
      await tester.pumpAndSettle();
    }

    await show(true, {
      'status': 'pending_review',
      'public_status': 'published',
      'public_visible': false
    });
    expect(find.text('Получили изменения'), findsOneWidget);
    expect(find.textContaining('остаётся видимой'), findsNothing);
    await tester.tap(find.text('Мои услуги'));
    expect(continued, 1);
    await show(true, {'status': 'pending_review', 'public_visible': true});
    expect(find.textContaining('остаётся видимой'), findsOneWidget);
    await show(false, {'status': 'pending_review', 'public_visible': true});
    expect(find.textContaining('Предыдущая безопасная версия'), findsOneWidget);
    expect(paths.last.endsWith('/me/portfolio-projects/project-owned'), true);
    await show(false, {'status': 'published', 'public_visible': false});
    expect(find.text('Публикация подтверждена'), findsNothing);
    await show(false, {'status': 'published', 'public_visible': true});
    expect(find.text('Публикация подтверждена'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    api.dispose();
  });
}
