import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:services_marketplace/core/api.dart';
import 'package:services_marketplace/main.dart';
import 'package:services_marketplace/screens/marketplace.dart';
import 'widget_test.dart' show MemoryVault, ok;

void main() {
  for (final entry in const {'KZ': '+7', 'RU': '+7', 'BY': '+375', 'KG': '+996'}.entries) {
    testWidgets('phone fields prefill country prefix ${entry.key}', (t) async {
      final api = JobaApi('https://isolated.example', vault: MemoryVault(),
          transport: MockClient((r) async => ok({'items': []})));
      addTearDown(api.dispose);
      await t.pumpWidget(JobaApp(api: api));
      await t.pumpAndSettle();
      final dynamic state = t.state(find.byType(Marketplace));
      state.country = entry.key;
      for (final route in ['login', 'register', 'phone']) {
        state.go(route);
        await t.pumpAndSettle();
        final field = t.widget<TextFormField>(find.byType(TextFormField).first);
        expect(field.controller!.text, entry.value, reason: route);
      }
    });
  }
  testWidgets(
      'login keyboard sends one exact request, blocks navigation while pending and retains rejected credentials',
      (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final requests = <http.Request>[];
    final gate = Completer<http.Response>();
    final api = JobaApi('https://isolated.example', vault: MemoryVault(),
        transport: MockClient((r) async {
      if (r.url.path.endsWith('/auth/login')) {
        requests.add(r);
        return gate.future;
      }
      return ok({'items': []});
    }));
    await t.pumpWidget(JobaApp(api: api));
    await t.pumpAndSettle();
    final dynamic state = t.state(find.byType(Marketplace));
    state.go('login');
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Войти'));
    await t.pumpAndSettle();
    expect(requests, isEmpty);
    expect(find.text('Заполните поле'), findsOneWidget);
    expect(find.text('Введите номер в международном формате с кодом страны'),
        findsOneWidget);
    final fields = find.byType(TextFormField);
    await t.enterText(fields.at(0), '77000000001');
    await t.enterText(fields.at(1), 'Isolated invalid-format password');
    await t.ensureVisible(find.widgetWithText(FilledButton, 'Войти'));
    await t.tap(find.widgetWithText(FilledButton, 'Войти'));
    await t.pumpAndSettle();
    expect(requests, isEmpty);
    expect(find.text('Введите номер в международном формате с кодом страны'),
        findsOneWidget);
    await t.enterText(fields.at(0), ' +77000000001 ');
    await t.testTextInput.receiveAction(TextInputAction.next);
    await t.pump();
    t.testTextInput.enterText('  Isolated exact password!  ');
    await t.pump();
    expect(t.widget<TextFormField>(fields.at(1)).controller!.text,
        '  Isolated exact password!  ');
    await t.ensureVisible(find.byTooltip('Показать пароль'));
    await t.tap(find.byTooltip('Показать пароль'));
    await t.pumpAndSettle();
    expect(
        t
            .widget<TextField>(find.descendant(
                of: fields.at(1), matching: find.byType(TextField)))
            .obscureText,
        false);
    await t.tap(find.byTooltip('Скрыть пароль'));
    await t.pumpAndSettle();
    expect(
        t
            .widget<TextField>(find.descendant(
                of: fields.at(1), matching: find.byType(TextField)))
            .obscureText,
        true);
    await t.showKeyboard(fields.at(1));
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(requests.length, 1);
    expect(jsonDecode(requests.single.body), {
      'country': 'KZ',
      'phone': '+77000000001',
      'password': '  Isolated exact password!  '
    });
    expect(
        t
            .widget<TextButton>(
                find.widgetWithText(TextButton, 'Нужна помощь со входом?'))
            .onPressed,
        isNull);
    expect(
        t
            .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Зарегистрироваться'))
            .onPressed,
        isNull);
    state.back();
    state.go('recovery');
    await t.pump();
    expect(state.route, 'login');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pump();
    expect(requests.length, 1);
    gate.complete(http.Response(
        jsonEncode({
          'error': {
            'code': 'INVALID_CREDENTIALS',
            'message': 'Неверный номер или пароль'
          }
        }),
        401,
        headers: {'content-type': 'application/json; charset=utf-8'}));
    await t.pumpAndSettle();
    expect(state.route, 'login');
    expect(api.authenticated, false);
    expect(t.widget<TextFormField>(fields.at(0)).controller!.text,
        ' +77000000001 ');
    expect(t.widget<TextFormField>(fields.at(1)).controller!.text,
        '  Isolated exact password!  ');
    await t.ensureVisible(find
        .text('Не удалось войти. Проверьте данные или обратитесь за помощью.'));
    expect(
        find.text(
            'Не удалось войти. Проверьте данные или обратитесь за помощью.'),
        findsOneWidget);
    await t.ensureVisible(find.text('Помощь со входом'));
    await t.tap(find.text('Помощь со входом'));
    await t.pumpAndSettle();
    expect(state.route, 'recovery');
    state.go('login');
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Зарегистрироваться'));
    await t.tap(find.text('Зарегистрироваться'));
    await t.pumpAndSettle();
    expect(state.route, 'register');
    await t.ensureVisible(find.text('Уже есть аккаунт? Войти'));
    await t.tap(find.text('Уже есть аккаунт? Войти'));
    await t.pumpAndSettle();
    expect(state.route, 'login');
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    api.dispose();
  });

  testWidgets(
      'rate-limit countdown uses server duration, prevents early retries and back returns to the preserved login form',
      (t) async {
    t.view.physicalSize = const Size(390, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    var attempts = 0;
    final api = JobaApi('https://isolated.example', vault: MemoryVault(),
        transport: MockClient((r) async {
      if (!r.url.path.endsWith('/auth/login')) return ok({'items': []});
      attempts++;
      return http.Response(
          jsonEncode({
            'error': {
              'code': 'RATE_LIMITED',
              'message': 'Слишком много попыток. Повторите позже.',
              'details': {'retry_after_seconds': 30}
            }
          }),
          429,
          headers: {'content-type': 'application/json; charset=utf-8'});
    }));
    await t.pumpWidget(JobaApp(api: api));
    await t.pumpAndSettle();
    final dynamic state = t.state(find.byType(Marketplace));
    state.go('login');
    await t.pumpAndSettle();
    final fields = find.byType(TextFormField);
    await t.enterText(fields.at(0), '+77000000001');
    await t.enterText(fields.at(1), 'Isolated rejected password');
    await t.ensureVisible(find.text('Войти'));
    await t.tap(find.text('Войти'));
    await t.pumpAndSettle();
    expect(attempts, 1);
    expect(find.text('Попробуйте ещё раз'), findsOneWidget);
    expect(find.text('Повторить через 00:30'), findsOneWidget);
    expect(
        t
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Повторить через 00:30'))
            .onPressed,
        isNull);
    expect(
        t
            .widget<TextButton>(
                find.widgetWithText(TextButton, 'Помощь со входом'))
            .onPressed,
        isNotNull);
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pump();
    expect(attempts, 1);
    await t.pump(const Duration(seconds: 29));
    expect(find.text('Повторить через 00:01'), findsOneWidget);
    await t.pump(const Duration(seconds: 1));
    await t.ensureVisible(find.widgetWithText(FilledButton, 'Повторить'));
    expect(
        t
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Повторить'))
            .onPressed,
        isNotNull);
    await t.tap(find.widgetWithText(FilledButton, 'Повторить'));
    await t.pumpAndSettle();
    expect(attempts, 2);
    await t.ensureVisible(find.byTooltip('Показать пароль'));
    await t.tap(find.byTooltip('Показать пароль'));
    await t.pumpAndSettle();
    expect(
        t
            .widget<TextField>(find.descendant(
                of: fields.at(1), matching: find.byType(TextField)))
            .obscureText,
        false);
    await t.tap(find.byTooltip('Назад'));
    await t.pumpAndSettle();
    expect(state.route, 'login');
    expect(find.text('С возвращением'), findsOneWidget);
    expect(find.textContaining('Повторить через'), findsNothing);
    expect(
        t
            .widget<TextField>(find.descendant(
                of: fields.at(1), matching: find.byType(TextField)))
            .obscureText,
        true);
    expect(
        t.widget<TextFormField>(fields.at(0)).controller!.text, '+77000000001');
    expect(t.widget<TextFormField>(fields.at(1)).controller!.text,
        'Isolated rejected password');
    await t.tap(find.byTooltip('Назад'));
    await t.pumpAndSettle();
    expect(state.route, 'welcome');
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    api.dispose();
  });

  testWidgets(
      'successful login reaches local protection without persisting an unprotected session',
      (t) async {
    final vault = MemoryVault();
    final user = {
      'id': 'login-owner',
      'country': 'KZ',
      'locale': 'kk',
      'active_role': 'customer',
      'roles': ['customer'],
      'version': 1
    };
    var localeSaved = false;
    final api = JobaApi('https://isolated.example', vault: vault,
        transport: MockClient((r) async {
      if (r.url.path.endsWith('/auth/login'))
        return ok({
          'access_token': 'isolated-access',
          'refresh_token': 'isolated-refresh',
          'user': user
        });
      if (r.method == 'PATCH') {
        expect(jsonDecode(r.body), {'expected_version': 1, 'locale': 'ru'});
        localeSaved = true;
        return ok({...user, 'locale': 'ru', 'version': 2});
      }
      return ok(user);
    }));
    await t.pumpWidget(JobaApp(api: api));
    await t.pumpAndSettle();
    final dynamic state = t.state(find.byType(Marketplace));
    state.go('login');
    await t.pumpAndSettle();
    final fields = find.byType(TextFormField);
    await t.enterText(fields.at(0), '+77000000001');
    await t.enterText(fields.at(1), 'Isolated correct password!');
    await t.ensureVisible(find.text('Войти'));
    await t.tap(find.widgetWithText(FilledButton, 'Войти'));
    await t.pumpAndSettle();
    expect(state.route, 'lock-setup');
    expect(localeSaved, true);
    expect(state.me['locale'], 'ru');
    expect(api.authenticated, true);
    expect(vault.value, isNull);
    expect(state.authSubmitting, false);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    api.dispose();
  });

  testWidgets(
      'profile bootstrap failure clears unprotected credentials and preserves a created account path',
      (t) async {
    t.view.physicalSize = const Size(390, 1200);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    for (final register in [false, true]) {
      final vault = MemoryVault();
      final api = JobaApi('https://isolated.example', vault: vault,
          transport: MockClient((r) async {
        if (r.url.path.endsWith('/auth/login') ||
            r.url.path.endsWith('/auth/register'))
          return ok({
            'access_token': 'isolated-access',
            'refresh_token': 'isolated-refresh',
            'user': {'id': 'bootstrap-owner', 'country': 'KZ', 'locale': 'ru'}
          });
        if (r.url.path.endsWith('/me'))
          return http.Response(
              '{"error":{"code":"TEMPORARY_FAILURE","message":"Profile unavailable"}}',
              503);
        return ok({'items': []});
      }));
      await t.pumpWidget(JobaApp(key: ValueKey(register), api: api));
      await t.pumpAndSettle();
      final dynamic state = t.state(find.byType(Marketplace));
      state.go(register ? 'register' : 'login');
      await t.pumpAndSettle();
      final fields = find.byType(TextFormField);
      await t.enterText(fields.at(0), '+77000000001');
      await t.enterText(fields.at(1), 'Isolated bootstrap password!');
      if (register)
        await t.enterText(fields.at(2), 'Isolated bootstrap password!');
      final button =
          find.widgetWithText(FilledButton, register ? 'Продолжить' : 'Войти');
      await t.ensureVisible(button);
      await t.tap(button);
      await t.pumpAndSettle();
      expect(api.authenticated, false);
      expect(vault.value, isNull);
      expect(state.route, 'login');
      expect(state.authSubmitting, false);
      expect(
          t
              .widget<TextFormField>(find.byType(TextFormField).first)
              .controller!
              .text,
          '+77000000001');
      if (register)
        expect(find.text('Аккаунт создан. Войдите, чтобы продолжить.'),
            findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      api.dispose();
    }
  });

  testWidgets(
      'login visual capture uses the native viewport and retains keyboard access on small screens',
      (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    t.view.padding = const FakeViewPadding(top: 43, bottom: 22);
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.view.resetPadding);
    addTearDown(t.view.resetViewInsets);
    await (FontLoader('Noto')
          ..addFont(rootBundle.load('assets/NotoSans-Regular.ttf'))
          ..addFont(rootBundle.load('assets/NotoSans-Bold.ttf')))
        .load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
    final api = JobaApi('https://isolated.example',
        vault: MemoryVault(),
        transport: MockClient((_) async => ok({'items': []})));
    final boundary = GlobalKey();
    await t
        .pumpWidget(RepaintBoundary(key: boundary, child: JobaApp(api: api)));
    await t.pumpAndSettle();
    final dynamic state = t.state(find.byType(Marketplace));
    state.go('login');
    await t.pumpAndSettle();
    if (Platform.environment['JOBA_LOGIN_DIAGNOSTICS'] != null) {
      for (final f in find.byType(TextField).evaluate()) {
        final field = f.widget as TextField;
        print(
            '${field.decoration?.hintText}: ${t.getRect(find.byWidget(field))}');
      }
    }
    final output = Platform.environment['JOBA_SCREENSHOT_DIR'];
    if (output != null)
      await t.runAsync(() async {
        final image = await (boundary.currentContext!.findRenderObject()
                as RenderRepaintBoundary)
            .toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(output).create(recursive: true);
        await File('$output/S02-login.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    t.view.viewInsets = const FakeViewPadding(bottom: 320);
    await t.pumpAndSettle();
    await t.ensureVisible(find.byType(TextFormField).at(1));
    await t.enterText(find.byType(TextFormField).at(1), 'keyboard text');
    await t.ensureVisible(find.widgetWithText(FilledButton, 'Войти'));
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    api.dispose();
  });
}
