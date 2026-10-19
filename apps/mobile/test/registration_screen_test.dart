import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:services_marketplace/core/api.dart';
import 'package:services_marketplace/main.dart';
import 'package:services_marketplace/screens/marketplace.dart';

class _Vault implements SessionVault {
  Future<String?> read() async => null;
  Future<void> write(String v) async {}
  Future<void> clear() async {}
}

void main() {
  for (final entry in {
    'KZ': '+77000000001',
    'KG': '+996700000001',
    'RU': '+79160000001',
    'BY': '+375291000001'
  }.entries) {
    testWidgets(
        'registration ${entry.key} enforces password bounds and blocks duplicate pending requests',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final requests = <Json>[];
      final response = Completer<http.Response>();
      final api = JobaApi('https://isolated.example', vault: _Vault(),
          transport: MockClient((r) async {
        if (r.url.path.endsWith('/auth/register')) {
          requests.add(jsonDecode(r.body) as Json);
          return response.future;
        }
        return http.Response('{"data":{"items":[]},"meta":{}}', 200);
      }));
      await tester.pumpWidget(JobaApp(api: api));
      await tester.pumpAndSettle();
      final dynamic state = tester.state(find.byType(Marketplace));
      state.country = entry.key;
      state.go('login');
      state.go('register');
      await tester.pumpAndSettle();
      final fields = find.byType(TextFormField);
      for (final index in [1, 2]) {
        final field = fields.at(index);
        final eye = find.descendant(
            of: field, matching: find.byTooltip('Показать пароль'));
        await tester.ensureVisible(eye);
        await tester.tap(eye);
        await tester.pumpAndSettle();
        expect(
            tester
                .widget<TextField>(find.descendant(
                    of: field, matching: find.byType(TextField)))
                .obscureText,
            false);
        await tester.tap(find.descendant(
            of: field, matching: find.byTooltip('Скрыть пароль')));
        await tester.pumpAndSettle();
        expect(
            tester
                .widget<TextField>(find.descendant(
                    of: field, matching: find.byType(TextField)))
                .obscureText,
            true);
      }
      await tester.enterText(fields.at(0), ' ${entry.value} ');
      for (final length in [14, 129]) {
        final password = List.filled(length, 'x').join();
        await tester.enterText(fields.at(1), password);
        await tester.enterText(fields.at(2), password);
        await tester.ensureVisible(find.text('Продолжить'));
        await tester.tap(find.text('Продолжить'));
        await tester.pumpAndSettle();
        expect(requests, isEmpty);
        expect(
            find.text(length == 14
                ? 'Не менее 15 символов'
                : 'Не более 128 символов'),
            findsWidgets);
      }
      final password = ' ' + List.filled(126, 'x').join() + ' ';
      await tester.enterText(fields.at(1), password);
      await tester.enterText(fields.at(2), password);
      await tester.ensureVisible(find.text('Продолжить'));
      await tester.tap(find.text('Продолжить'));
      await tester.pump();
      expect(requests.single, {
        'country': entry.key,
        'phone': entry.value,
        'password': password,
        'locale': 'ru'
      });
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull);
      state.go('login');
      expect(state.route, 'register');
      await tester.tap(find.byTooltip('Назад'));
      await tester.pump();
      expect(state.route, 'register');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(requests, hasLength(1));
      response.complete(http.Response(
          '{"error":{"code":"REGISTRATION_UNAVAILABLE","message":"Не удалось зарегистрироваться. Обратитесь в поддержку."}}',
          409,
          headers: {'content-type': 'application/json; charset=utf-8'}));
      await tester.pumpAndSettle();
      expect(state.route, 'register');
      expect(tester.widget<TextFormField>(fields.at(1)).controller!.text,
          password);
      expect(api.authenticated, false);
      await tester.scrollUntilVisible(find.text('Уже есть аккаунт? Войти'), 180,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Уже есть аккаунт? Войти'));
      await tester.pumpAndSettle();
      expect(state.route, 'login');
      state.go('register');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Назад'));
      await tester.pumpAndSettle();
      expect(state.route, 'login');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      api.dispose();
    });
  }
  testWidgets(
      'successful registration preserves customer role and proceeds to local protection before documents',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final user = {
      'id': 'isolated-new-user',
      'country': 'KZ',
      'locale': 'ru',
      'roles': ['customer'],
      'active_role': 'customer',
      'version': 1
    };
    final paths = <String>[];
    final api = JobaApi('https://isolated.example', vault: _Vault(),
        transport: MockClient((r) async {
      paths.add(r.url.path);
      return http.Response(
          jsonEncode({
            'data': r.url.path.endsWith('/auth/register')
                ? {
                    'access_token': 'isolated-access',
                    'refresh_token': 'isolated-refresh',
                    'user': user
                  }
                : user
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    }));
    await tester.pumpWidget(JobaApp(api: api));
    await tester.pumpAndSettle();
    final dynamic state = tester.state(find.byType(Marketplace));
    state.go('register');
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), '+77000000001');
    await tester.enterText(fields.at(1), 'Isolated correct password');
    await tester.enterText(fields.at(2), 'Isolated correct password');
    await tester.ensureVisible(find.text('Продолжить'));
    await tester.tap(find.text('Продолжить'));
    await tester.pumpAndSettle();
    expect(state.route, 'lock-setup');
    expect(state.registrationInProgress, true);
    expect(state.me['roles'], ['customer']);
    expect(paths.where((p) => p.endsWith('/auth/register')), hasLength(1));
    expect(paths.any((p) => p.endsWith('/me')), true);
    expect(state.history, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    api.dispose();
  });
  testWidgets(
      'registration follows the profile step contract, prevents password mismatch, and preserves fields after rejection',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final registrations = <Json>[];
    final api = JobaApi('https://isolated.example', vault: _Vault(),
        transport: MockClient((r) async {
      if (r.url.path.endsWith('/auth/register')) {
        registrations.add(jsonDecode(r.body) as Json);
        return http.Response(
            '{"error":{"code":"VALIDATION_ERROR","message":"Регистрация отклонена"}}',
            422,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }
      return http.Response('{"data":{"items":[]},"meta":{}}', 200);
    }));
    await tester.pumpWidget(JobaApp(api: api));
    await tester.pumpAndSettle();
    final dynamic state = tester.state(find.byType(Marketplace));
    state.go('register');
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    expect(fields, findsNWidgets(3));
    expect(find.text('Как к вам обращаться'), findsNothing);
    await tester.enterText(fields.at(0), '+77000000001');
    await tester.enterText(fields.at(1), 'Isolated long password');
    await tester.enterText(fields.at(2), 'Different long password');
    await tester.scrollUntilVisible(find.text('Продолжить'), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Продолжить'));
    await tester.pumpAndSettle();
    expect(registrations, isEmpty);
    await tester.ensureVisible(fields.at(2));
    await tester.enterText(fields.at(2), 'Isolated long password');
    await tester.scrollUntilVisible(find.text('Продолжить'), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Продолжить'));
    await tester.pumpAndSettle();
    expect(registrations.single, {
      'country': 'KZ',
      'phone': '+77000000001',
      'password': 'Isolated long password',
      'locale': 'ru'
    });
    expect(tester.widget<TextFormField>(fields.at(0)).controller!.text,
        '+77000000001');
    expect(tester.widget<TextFormField>(fields.at(1)).controller!.text,
        'Isolated long password');
    expect(api.authenticated, false);
    expect(state.route, 'register');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    api.dispose();
  });
}
