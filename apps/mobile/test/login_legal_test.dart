import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:services_marketplace/core/api.dart';
import 'package:services_marketplace/main.dart';
import 'package:services_marketplace/screens/marketplace.dart';
import 'widget_test.dart' show MemoryVault, ok;

void main() {
  testWidgets(
      'login documents open in a modal without authentication or losing entered credentials',
      (t) async {
    t.view.physicalSize = const Size(320, 640);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final legalReads = <String>[];
    final api = JobaApi('https://isolated.example', vault: MemoryVault(),
        transport: MockClient((r) async {
      if (r.url.path.endsWith('/legal/documents')) {
        expect(r.method, 'GET');
        expect(r.headers['Authorization'], isNull);
        expect(r.url.queryParameters, containsPair('country', 'KZ'));
        expect(r.url.queryParameters, containsPair('locale', 'ru'));
        legalReads.add(r.url.path);
        return ok({
          'items': [
            for (final type in ['privacy', 'terms', 'payments'])
              {
                'id': type,
                'type': type,
                'version': 3,
                'published_at': '2026-11-01T00:00:00Z',
                'content': 'Опубликованный текст $type для Казахстана.'
              },
          ]
        });
      }
      return ok({'items': []});
    }));
    addTearDown(api.dispose);
    await t.pumpWidget(JobaApp(api: api));
    await t.pumpAndSettle();
    final dynamic state = t.state(find.byType(Marketplace));
    state.go('login');
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextFormField).at(0), '+77000000001');
    await t.enterText(find.byType(TextFormField).at(1), 'Preserved password');
    final phoneController =
        t.widget<TextFormField>(find.byType(TextFormField).at(0)).controller!;
    final passwordController =
        t.widget<TextFormField>(find.byType(TextFormField).at(1)).controller!;
    expect(legalReads, isEmpty);
    for (final link in [
      'Политика конфиденциальности',
      'Пользовательское соглашение',
      'Другие документы'
    ]) {
      await t.scrollUntilVisible(find.text(link), 180,
          scrollable: find.byType(Scrollable).first);
      await t.pumpAndSettle();
      await t.ensureVisible(find.widgetWithText(TextButton, link));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(TextButton, link));
      await t.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      expect(state.route, 'login');
      if (link == 'Другие документы') {
        await t.tap(find.text('Условия оплаты'));
        await t.pumpAndSettle();
        expect(find.text('Опубликованный текст payments для Казахстана.'),
            findsOneWidget);
        await t.tap(find.byTooltip('Список документов'));
        await t.pumpAndSettle();
        expect(find.text('Условия оплаты'), findsOneWidget);
      } else {
        expect(
            find.text(
                'Опубликованный текст ${link.startsWith('Политика') ? 'privacy' : 'terms'} для Казахстана.'),
            findsOneWidget);
      }
      expect(t.getRect(find.byTooltip('Закрыть документ')).bottom,
          lessThanOrEqualTo(640));
      await t.tap(find.byTooltip('Закрыть документ'));
      await t.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(phoneController.text, '+77000000001');
      expect(passwordController.text, 'Preserved password');
      expect(api.authenticated, false);
    }
    expect(legalReads.length, 3);
  });
}
