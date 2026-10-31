import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:services_marketplace/core/api.dart';
import 'package:services_marketplace/core/theme.dart';
import 'package:services_marketplace/screens/unlock_keypad.dart';

Widget host(Widget child) => MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: const Locale('ru'),
    supportedLocales: const [Locale('ru')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: jobaTheme(),
    home: Scaffold(backgroundColor: canvas, body: child));
Finder digit(String value) => find.byKey(ValueKey('unlock-key-$value'));
void main() {
  testWidgets(
      'all digits, deletion, legacy confirmation and optional methods use actual callbacks',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final pins = <String>[];
    var bios = 0, passwords = 0;
    await tester.pumpWidget(host(UnlockKeypad(
        name: 'Марина П.',
        busy: false,
        loadLength: () async => null,
        onPin: (pin) async => pins.add(pin),
        onBiometry: () async => bios++,
        onPassword: () async => passwords++)));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    for (final value in ['0', '1', '2', '3', '4', '5', '6', '7']) {
      await tester.ensureVisible(digit(value));
      await tester.pumpAndSettle();
      await tester.tap(digit(value));
      await tester.pump();
    }
    expect(pins, isEmpty);
    await tester.tap(digit('delete'));
    await tester.pump();
    await tester.ensureVisible(find.text('Разблокировать'));
    await tester.tap(find.text('Разблокировать'));
    await tester.pumpAndSettle();
    expect(pins, ['0123456']);
    await tester.ensureVisible(digit('biometry'));
    await tester.tap(digit('biometry'));
    await tester.pumpAndSettle();
    expect(bios, 1);
    await tester.ensureVisible(find.text('Войти номером и паролем'));
    await tester.tap(find.text('Войти номером и паролем'));
    await tester.pumpAndSettle();
    expect(passwords, 1);
    for (final value in ['8', '9', '8', '9', '8', '9']) {
      await tester.ensureVisible(digit(value));
      await tester.pumpAndSettle();
      await tester.tap(digit(value));
      await tester.pump();
    }
    await tester.ensureVisible(find.text('Разблокировать'));
    await tester.tap(find.text('Разблокировать'));
    await tester.pumpAndSettle();
    expect(pins.last, '898989');
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'hardware keys and touch share one auto submission and clear digits after a rejected attempt',
      (tester) async {
    final first = Completer<void>();
    final pins = <String>[];
    await tester.pumpWidget(host(UnlockKeypad(
        name: '',
        busy: false,
        loadLength: () async => 6,
        onPin: (pin) async {
          pins.add(pin);
          if (pins.length == 1) await first.future;
        },
        onBiometry: () async => fail('Duplicate'),
        onPassword: () async {})));
    await tester.pumpAndSettle();
    final semantics = tester.ensureSemantics();
    final button =
        tester.getSemantics(find.byKey(const ValueKey('unlock-semantics-1')));
    expect(button.getSemanticsData().hasAction(ui.SemanticsAction.tap), true);
    semantics.dispose();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(
        (tester
                .widget<Container>(find.byKey(const ValueKey('unlock-dot-0')))
                .decoration as BoxDecoration)
            .color,
        primary);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    for (final key in [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.backspace,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit6,
      LogicalKeyboardKey.digit7
    ]) await tester.sendKeyEvent(key);
    await tester.pump();
    expect(pins, ['124567']);
    expect(tester.widget<InkWell>(digit('biometry')).onTap, isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit8);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(pins, hasLength(1));
    first.completeError(ApiException('PIN_INVALID', 'Неверный PIN'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Неверный PIN'), -150,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Неверный PIN'), findsOneWidget);
    for (final value in ['9', '8', '7', '6', '5', '4']) {
      await tester.ensureVisible(digit(value));
      await tester.pumpAndSettle();
      await tester.tap(digit(value));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(pins.last, '987654');
    expect(tester.takeException(), isNull);
  });
  testWidgets('keypad native viewport and enlarged text remain scrollable',
      (tester) async {
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    tester.view.padding = const FakeViewPadding(top: 86, bottom: 44);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    final capture = Platform.environment['JOBA_KEYPAD_CAPTURE'];
    if (capture != null) {
      final font = FontLoader('Noto')
        ..addFont(rootBundle.load('assets/NotoSans-Regular.ttf'))
        ..addFont(rootBundle.load('assets/NotoSans-Bold.ttf'));
      await font.load();
    }
    final boundary = GlobalKey();
    Widget screen(double scale) => RepaintBoundary(
        key: boundary,
        child: host(MediaQuery(
            data: MediaQueryData.fromView(tester.view)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: Column(children: [
              Container(height: 43, color: Colors.white),
              Expanded(
                  child: UnlockKeypad(
                      name: 'Марина П.',
                      busy: false,
                      loadLength: () async => 6,
                      onPin: (pin) async {},
                      onBiometry: () async {},
                      onPassword: () async {})),
              Container(height: 22, color: Colors.white)
            ]))));
    await tester.pumpWidget(screen(1));
    await tester.pumpAndSettle();
    await tester.tap(digit('1'));
    await tester.tap(digit('2'));
    await tester.pumpAndSettle();
    if (capture != null) {
      await tester.runAsync(() async {
        final render = boundary.currentContext!.findRenderObject()
            as RenderRepaintBoundary;
        final image = await render.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(capture).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(screen(1.6));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Войти номером и паролем'), 180,
        scrollable: find.byType(Scrollable).first);
    expect(tester.takeException(), isNull);
  });
}
