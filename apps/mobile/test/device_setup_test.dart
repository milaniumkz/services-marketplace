import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:services_marketplace/core/api.dart';
import 'package:services_marketplace/core/theme.dart';
import 'package:services_marketplace/screens/device_setup.dart';

void main() {
  testWidgets(
      'PIN keyboard filters digits, checks confirmation, blocks duplicates and permits retry after failure',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var saves = 0;
    final first = Completer<void>();
    await tester.pumpWidget(MaterialApp(
        theme: jobaTheme(),
        home: Scaffold(
            body: PinSetup(
                onSave: (pin, bio) async {
                  saves++;
                  expect(pin, '123456');
                  expect(bio, true);
                  if (saves == 1) await first.future;
                },
                onPassword: () async => fail('Unexpected fallback')))));
    final input = find.byKey(const ValueKey('secure-pin-input'));
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    await tester.enterText(input, '12a345678');
    expect(tester.widget<TextField>(input).controller!.text, '123456');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('Повторите PIN'), findsWidgets);
    expect(tester.widget<TextField>(input).controller!.text, isEmpty);
    await tester.enterText(input, '654321');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(saves, 0);
    expect(find.text('PIN не совпадает'), findsOneWidget);
    await tester.enterText(input, '123456');
    await tester.ensureVisible(find.byType(Switch));
    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.tap(find.text('Сохранить PIN'));
    await tester.pump();
    expect(saves, 1);
    expect(tester.widget<TextField>(input).enabled, false);
    expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(saves, 1);
    first.completeError(ApiException('LOCAL_PROTECTION_UNAVAILABLE',
        'Используйте вход с номером и паролем'));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull);
    await tester.tap(find.text('Сохранить PIN'));
    await tester.pumpAndSettle();
    expect(saves, 2);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'password fallback stays on failure and can be retried without creating a PIN',
      (tester) async {
    var attempts = 0;
    await tester.pumpWidget(MaterialApp(
        theme: jobaTheme(),
        home: Scaffold(
            body: PinSetup(
                onSave: (pin, bio) async => fail('PIN must not be saved'),
                onPassword: () async {
                  attempts++;
                  if (attempts == 1)
                    throw ApiException('NETWORK_ERROR', 'Нет соединения');
                }))));
    final fallback = find.text('Вводить номер и пароль');
    await tester.scrollUntilVisible(fallback, 150,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(fallback);
    await tester.pumpAndSettle();
    expect(attempts, 1);
    await tester.scrollUntilVisible(fallback, 150,
        scrollable: find.byType(Scrollable).first);
    expect(
        tester
            .widget<TextButton>(
                find.widgetWithText(TextButton, 'Вводить номер и пароль'))
            .onPressed,
        isNotNull);
    await tester.tap(fallback);
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(tester.takeException(), isNull);
  });
}
