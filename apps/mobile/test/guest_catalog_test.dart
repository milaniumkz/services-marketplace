import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:services_marketplace/core/api.dart';
import 'package:services_marketplace/main.dart';

import 'widget_test.dart' show MemoryVault, ok;

void main() {
  testWidgets('iOS welcome opens published listings before authentication',
      (tester) async {
    var guestRequests = 0;
    final api = JobaApi('https://isolated.example', vault: MemoryVault(),
        transport: MockClient((request) async {
      if (request.url.path.endsWith('/public/contractors')) {
        guestRequests++;
        expect(request.headers['authorization'], isNull);
        expect(request.url.queryParameters['country'], 'KZ');
        return ok({
          'items': [
            {
              'id': 'service',
              'title': 'Ремонт кухни',
              'city': 'Алматы',
              'description': 'Покраска стен'
            },
          ],
          'next_cursor': null,
        });
      }
      return ok({'items': []});
    }));
    addTearDown(api.dispose);
    await tester.pumpWidget(JobaApp(api: api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Смотреть специалистов без входа'));
    await tester.pumpAndSettle();
    expect(guestRequests, 1);
    expect(find.text('Ремонт кухни'), findsOneWidget);
    await tester.tap(find.text('Ремонт кухни'));
    await tester.pumpAndSettle();
    expect(find.text('Покраска стен'), findsOneWidget);
    await tester.tap(find.text('Войти или создать аккаунт'));
    await tester.pumpAndSettle();
    expect(find.text('Вход в JOBA'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: const TargetPlatformVariant({TargetPlatform.iOS}));
}
