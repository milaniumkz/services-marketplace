import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:services_marketplace/core/reference_picker.dart';

void main() {
  final cities = [
    {'id': 'a', 'name': 'Город А', 'region': 'Область А'},
    {'id': 'b', 'name': 'Манас', 'region': 'Область Б', 'aliases': ['Джалал-Абад']},
    {'id': 'c', 'name': 'Город В', 'region': 'Область А'},
  ];
  final categories = [
    {'id': 'r', 'name': 'Ремонт'},
    {'id': 'other', 'name': 'Обучение'},
    {'id': 's', 'name': 'Сантехника', 'parent_id': 'r'},
    {'id': 'leaf', 'name': 'Установка крана', 'parent_id': 's'},
  ];
  testWidgets('region then its cities, back and global alias search', (t) async {
    String? saved;
    await t.pumpWidget(MaterialApp(home: Scaffold(body: ReferenceSelector(
        rows: cities, cities: true, onSave: (r) async => saved = r['id']))));
    expect(find.text('Область А'), findsOneWidget);
    expect(find.text('Город А'), findsNothing);
    await t.tap(find.text('Область А')); await t.pumpAndSettle();
    expect(find.text('Город А'), findsOneWidget);
    expect(find.text('Манас'), findsNothing);
    await t.tap(find.text('Все области и регионы')); await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'джалал'); await t.pumpAndSettle();
    expect(find.text('Манас'), findsOneWidget);
    expect(find.text('Область Б'), findsOneWidget);
    await t.tap(find.text('Манас')); await t.pump();
    await t.tap(find.text('Выбрать Манас')); await t.pumpAndSettle();
    expect(saved, 'b');
  });
  testWidgets('categories start at roots then descend and search globally', (t) async {
    String? saved;
    await t.pumpWidget(MaterialApp(home: Scaffold(body: ReferenceSelector(
        rows: categories, cities: false, onSave: (r) async => saved = r['id']))));
    expect(find.text('Ремонт'), findsOneWidget);
    expect(find.text('Сантехника'), findsNothing);
    await t.tap(find.text('Ремонт')); await t.pumpAndSettle();
    expect(find.text('Сантехника'), findsOneWidget);
    expect(find.text('Обучение'), findsNothing);
    await t.tap(find.text('Сантехника')); await t.pumpAndSettle();
    expect(find.text('Установка крана'), findsOneWidget);
    await t.tap(find.text('Назад к категориям')); await t.pumpAndSettle();
    expect(find.text('Сантехника'), findsOneWidget);
    await t.enterText(find.byType(TextField), 'крана'); await t.pumpAndSettle();
    expect(find.text('Ремонт → Сантехника'), findsOneWidget);
    await t.tap(find.text('Установка крана')); await t.pump();
    await t.tap(find.text('Выбрать Установка крана')); await t.pumpAndSettle();
    expect(saved, 'leaf');
  });
  testWidgets('empty search and failed save keep selection for retry', (t) async {
    var attempts = 0;
    await t.pumpWidget(MaterialApp(home: Scaffold(body: ReferenceSelector(
        rows: cities, cities: true, onSave: (_) async {
          attempts++; if (attempts == 1) throw Exception('offline');
        }))));
    await t.enterText(find.byType(TextField), 'несуществующий'); await t.pump();
    expect(find.text('Ничего не найдено. Попробуйте другое название.'), findsOneWidget);
    await t.enterText(find.byType(TextField), 'Город А'); await t.pump();
    await t.tap(find.widgetWithText(ListTile, 'Город А')); await t.pump();
    await t.tap(find.text('Выбрать Город А')); await t.pumpAndSettle();
    await t.tap(find.text('Выбрать Город А')); await t.pumpAndSettle();
    expect(attempts, 2);
  });
}
