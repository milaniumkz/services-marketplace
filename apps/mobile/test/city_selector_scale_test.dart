import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:services_marketplace/screens/city_selector.dart';

void main() {
  testWidgets('large city catalog is virtualized and aliases remain searchable',
      (t) async {
    final cities = List.generate(
        6000,
        (i) => <String, dynamic>{
              'id': '$i',
              'name': 'Населённый пункт $i',
              'aliases': ['Alias$i'],
              'region': 'Регион'
            });
    String? selected;
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CitySelector(
                cities: cities,
                initial: '',
                onSave: (city) async {
                  selected = city['id'];
                }))));
    await t.pumpAndSettle();
    expect(find.byType(InkWell).evaluate().length, lessThan(50));
    await t.enterText(find.byType(TextField), 'Alias5999');
    await t.pumpAndSettle();
    expect(find.text('Населённый пункт 5999'), findsOneWidget);
    await t.tap(find.text('Населённый пункт 5999'));
    await t.pump();
    await t.tap(find.byType(FilledButton));
    await t.pumpAndSettle();
    expect(selected, '5999');
  });
}
