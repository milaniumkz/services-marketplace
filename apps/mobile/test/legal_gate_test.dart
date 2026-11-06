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
  Future<void> write(String value) async {}
  Future<void> clear() async {}
}

void main() {
  for (final types in <List<String>>[
    [],
    ['terms'],
    ['privacy'],
    ['terms', 'privacy']
  ]) {
    testWidgets('legal continuation requires both published types: $types',
        (tester) async {
      final documents = [
        for (final type in types)
          {
            'id': type,
            'type': type,
            'hash': 'hash-$type',
            'version': 1,
            'title': type,
            'content': 'Isolated document'
          }
      ];
      final api = JobaApi('https://isolated.example', vault: _Vault(),
          transport: MockClient((r) async {
        return http.Response(
            jsonEncode({
              'data': {
                'items': r.url.path.endsWith('/legal/documents')
                    ? documents
                    : r.url.path.endsWith('/me/consents')
                        ? [
                            for (final type in types)
                              {
                                'document_id': type,
                                'document_hash': 'hash-$type',
                                'sequence': 1,
                                'accepted': true
                              }
                          ]
                        : []
              }
            }),
            200);
      }));
      await tester.pumpWidget(JobaApp(api: api));
      await tester.pumpAndSettle();
      final dynamic state = tester.state(find.byType(Marketplace));
      api.session = {
        'access_token': 'isolated-token',
        'user': {'id': 'owner'}
      };
      state.me = {'id': 'owner', 'country': 'KZ', 'locale': 'ru', 'version': 1};
      state.go('terms');
      await tester.pumpAndSettle();
      final button = find.widgetWithText(FilledButton, 'Продолжить');
      await tester.scrollUntilVisible(button, 150,
          scrollable: find.byType(Scrollable).first);
      expect(tester.widget<FilledButton>(button).onPressed != null,
          types.length == 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      api.dispose();
    });
  }
}
