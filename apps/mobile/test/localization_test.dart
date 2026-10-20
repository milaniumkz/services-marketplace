import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:services_marketplace/main.dart';
import 'package:services_marketplace/core/api.dart';
import 'package:services_marketplace/core/l10n.dart';
import 'package:services_marketplace/core/widgets.dart';
import 'widget_test.dart' show MemoryVault, ok;

void main() {
  testWidgets('Welcome switches all four interface languages immediately',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = JobaApi('https://example.com',
        vault: MemoryVault(), transport: MockClient((_) async => ok({})));
    await tester.pumpWidget(JobaApp(api: api));
    await tester.pumpAndSettle();
    expect(find.text('Дела становятся проще'), findsOneWidget);
    for (final entry in {
      'Қазақша': 'Істер оңайырақ болады',
      'Srpski': 'Послови постају једноставнији',
      'Беларуская': 'Справы становяцца прасцей',
      'Русский': 'Дела становятся проще',
    }.entries) {
      final picker = find.byType(DropdownButtonFormField<String>);
      await tester.ensureVisible(picker);
      await tester.tap(picker);
      await tester.pumpAndSettle();
      await tester.tap(find.text(entry.key).last);
      await tester.pumpAndSettle();
      expect(find.text(entry.value), findsOneWidget);
    }
    await tester.pumpWidget(const SizedBox());
    api.dispose();
  });

  testWidgets('Changing locale preserves entered data and user card text',
      (tester) async {
    var language = 'ru';
    await tester.pumpWidget(StatefulBuilder(
        builder: (context, change) => MaterialApp(
              locale: Locale(language),
              supportedLocales: const [Locale('ru'), Locale('sr')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              home: Scaffold(
                  body: Column(children: [
                TextButton(
                    onPressed: () => change(() => language = 'sr'),
                    child: const UiText('Настройки')),
                const DataCard('Профиль',
                    subtitle: 'Настройки', status: 'Активен'),
                Expanded(
                    child: ActionForm(
                        fields: const [InputSpec('name', 'Имя')],
                        submit: (_) async {})),
              ])),
            )));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Мой профиль');
    await tester.tap(find.widgetWithText(TextButton, 'Настройки'));
    await tester.pumpAndSettle();
    expect(find.text('Подешавања'), findsOneWidget);
    expect(find.text('Име'), findsOneWidget);
    expect(find.text('Активно'), findsOneWidget);
    expect(find.text('Профиль'), findsOneWidget);
    expect(find.text('Настройки'), findsOneWidget);
    expect(find.text('Мой профиль'), findsOneWidget);
  });
}
