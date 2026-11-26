import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:services_marketplace/core/api.dart';
import 'package:services_marketplace/screens/reviews_screen.dart';
import 'widget_test.dart' show MemoryVault, ok;

void main() {
  testWidgets(
      'author can find sent sealed review and open it; other profiles only show published received reviews',
      (t) async {
    String? opened;
    final queries = <String?>[];
    final api = JobaApi('https://isolated.example', vault: MemoryVault(),
        transport: MockClient((r) async {
      queries.add(r.url.queryParameters['direction']);
      return ok({
        'items': r.url.queryParameters['direction'] == 'sent'
            ? [
                {
                  'id': 'review',
                  'rating': 5,
                  'text': 'Мой сохранённый отзыв',
                  'status': 'sealed',
                  'order_id': 'order',
                  'publish_after': '2026-12-10T10:00:00Z'
                }
              ]
            : []
      });
    }))
      ..session = {
        'access_token': 'test',
        'user': {'country': 'KZ'}
      };
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ReviewsScreen(
                api: api,
                userId: 'owner',
                own: true,
                onReview: (id) => opened = id))));
    await t.pumpAndSettle();
    await t.tap(find.text('Мои отзывы'));
    await t.pumpAndSettle();
    expect(find.text('Мой сохранённый отзыв'), findsOneWidget);
    expect(find.text('Ожидает публикации'), findsOneWidget);
    expect(find.textContaining('Отзыв сохранён и виден вам.'), findsOneWidget);
    await t.tap(find.text('Мой сохранённый отзыв'));
    expect(opened, 'order');
    expect(queries, contains('sent'));
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ReviewsScreen(
                api: api,
                userId: 'other',
                own: false,
                onReview: (_) => fail('Not own review')))));
    await t.pumpAndSettle();
    expect(find.text('Мои отзывы'), findsNothing);
    expect(queries.last, isNull);
    await t.pumpWidget(const SizedBox());
    api.dispose();
  });
}
