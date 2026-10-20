import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:services_marketplace/screens/executor_access.dart';

void main() {
  testWidgets(
      'executor sees separate 30-day plans and selects the matching offer',
      (t) async {
    final selected = <String?>[];
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ExecutorAccess(
                choosing: true,
                grants: [],
                subscriptions: [],
                config: {
                  'offers': [
                    {
                      'id': 'standard-offer',
                      'plan': 'standard',
                      'amount_minor': 100000,
                      'currency': 'KZT',
                      'period': 'days',
                      'duration_days': 30
                    },
                    {
                      'id': 'premium-offer',
                      'plan': 'premium',
                      'amount_minor': 150000,
                      'currency': 'KZT',
                      'period': 'days',
                      'duration_days': 30
                    }
                  ]
                },
                onGo: (route, id) {
                  selected.add(id);
                }))));
    await t.pumpAndSettle();
    expect(find.text('Стандарт'), findsOneWidget);
    await t.ensureVisible(find.text('Премиум'));
    await t.pumpAndSettle();
    expect(find.text('Приоритет услуг в Топ-100 на 30 дней'), findsOneWidget);
    final buttons = find.widgetWithText(FilledButton, 'Посмотреть условия');
    await t.ensureVisible(buttons.last);
    await t.tap(buttons.last);
    expect(selected, ['premium-offer']);
  });
  testWidgets('configured prices remain visible before billing is connected',
      (t) async {
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ExecutorAccess(
                choosing: true,
                grants: [],
                subscriptions: [],
                config: {
                  'plans': [
                    {
                      'code': 'standard',
                      'amount_minor': 100000,
                      'currency': 'KZT'
                    },
                    {
                      'code': 'premium',
                      'amount_minor': 150000,
                      'currency': 'KZT'
                    }
                  ]
                },
                onGo: (_, __) {}))));
    await t.pumpAndSettle();
    expect(find.textContaining(RegExp(r'1[\s,]000')), findsWidgets);
    expect(find.text('Цена ещё не установлена'), findsNothing);
  });
}
