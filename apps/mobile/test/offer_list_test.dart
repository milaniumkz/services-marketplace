import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:services_marketplace/core/api.dart';
import 'package:services_marketplace/screens/offer_list.dart';

void main() {
  testWidgets(
      'offer sorting changes actual cards and selection uses the exact offer id',
      (t) async {
    String? route, id;
    final api = JobaApi('https://isolated.example');
    final offers = <Json>[
      {
        'id': 'expensive',
        'amount': 5000000,
        'currency': 'KZT',
        'status': 'active',
        'text': 'Дороже',
        'conversation_id': 'chat-expensive',
        'executor': {
          'display_name': 'Первый мастер',
          'available': true,
          'rating': {'average': 4.9, 'count': 10}
        }
      },
      {
        'id': 'cheap',
        'amount': 4000000,
        'currency': 'KZT',
        'status': 'active',
        'text': 'Дешевле',
        'conversation_id': 'chat-cheap',
        'executor': {
          'display_name': 'Второй мастер',
          'available': true,
          'rating': {'average': 4.5, 'count': 12}
        }
      },
    ];
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: OfferList(
                api: api,
                order: {
                  'id': 'order',
                  'title': 'Заказ',
                  'currency': 'KZT',
                  'status': 'open'
                },
                offers: offers,
                onGo: (r, i) {
                  route = r;
                  id = i;
                }))));
    await t.pumpAndSettle();
    await t.tap(find.text('По цене'));
    await t.pumpAndSettle();
    expect(t.getTopLeft(find.text('Второй мастер')).dy,
        lessThan(t.getTopLeft(find.text('Первый мастер')).dy));
    await t.tap(find.widgetWithText(FilledButton, 'Выбрать').first);
    expect(route, 'select-contractor');
    expect(id, 'cheap');
    await t.tap(find.widgetWithText(OutlinedButton, 'Уточнить').first);
    expect(route, 'chat');
    expect(id, 'chat-cheap');
    await t.tap(find.text('По рейтингу'));
    await t.pumpAndSettle();
    expect(t.getTopLeft(find.text('Первый мастер')).dy,
        lessThan(t.getTopLeft(find.text('Второй мастер')).dy));
    await t.pumpWidget(const SizedBox());
    api.dispose();
  });
}
