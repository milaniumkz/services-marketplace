import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/core/widgets.dart';

void main() {
  testWidgets(
      'communication languages select multiple server options and submit codes without free text',
      (tester) async {
    Map<String, String>? submitted;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ActionForm(
                fields: const [
          InputSpec('languages', 'Языки общения',
              multiSelect: true,
              initial: 'sr,ru',
              options: {
                'ru': 'Русский',
                'ky': 'Киргизский',
                'kk': 'Казахский',
                'be': 'Белорусский',
                'en': 'Английский'
              })
        ],
                button: 'Сохранить',
                submit: (values) async {
                  submitted = Map.from(values);
                }))));
    for (final name in [
      'Русский',
      'Киргизский',
      'Казахский',
      'Белорусский',
      'Английский'
    ]) expect(find.text(name), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    await tester.tap(find.text('Киргизский'));
    await tester.pump();
    await tester.tap(find.text('Английский'));
    await tester.pump();
    await tester.ensureVisible(find.text('Сохранить'));
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(submitted?['languages'], 'ru,ky,en');
  });
  testWidgets('at least one communication language is required',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ActionForm(
                fields: const [
          InputSpec('languages', 'Языки общения',
              multiSelect: true,
              initial: 'ru',
              options: {'ru': 'Русский', 'ky': 'Киргизский'})
        ],
                button: 'Сохранить',
                submit: (_) async {
                  calls++;
                }))));
    await tester.tap(find.text('Русский'));
    await tester.pump();
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.text('Выберите хотя бы один язык общения.'), findsOneWidget);
  });
}
