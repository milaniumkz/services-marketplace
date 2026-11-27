import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:services_marketplace/core/widgets.dart';

void main() {
  testWidgets(
      'city selected by map updates form without resetting typed order title',
      (t) async {
    var overrides = <String, String>{};
    late StateSetter update;
    Map<String, String>? sent;
    await t.pumpWidget(MaterialApp(home: Scaffold(body: StatefulBuilder(
      builder: (context, set) {
        update = set;
        return ActionForm(
          fieldOverrides: overrides,
          fields: const [
            InputSpec('title', 'Название'),
            InputSpec('city', 'Город')
          ],
          submit: (values) async {
            sent = values;
          },
        );
      },
    ))));
    await t.enterText(
        find.byType(TextFormField).first, 'Название моего заказа');
    update(() => overrides = {'city': 'Караганда'});
    await t.pumpAndSettle();
    expect(find.text('Название моего заказа'), findsOneWidget);
    expect(find.text('Караганда'), findsOneWidget);
    await t.enterText(find.byType(TextFormField).last, 'Алматы');
    update(() {});
    await t.pumpAndSettle();
    expect(find.text('Алматы'), findsOneWidget);
    await t.tap(find.text('Сохранить'));
    await t.pumpAndSettle();
    expect(sent!['title'], 'Название моего заказа');
    expect(sent!['city'], 'Алматы');
  });
}
