import 'dart:async';
import 'dart:convert';
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

http.Response ok(Object data) =>
    http.Response(jsonEncode({'data': data, 'meta': {}}), 200,
        headers: {'content-type': 'application/json; charset=utf-8'});
void main() {
  for (final name in ['', 'Complete']) {
    testWidgets('login resumes only an incomplete required profile: $name',
        (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      var user = <String, dynamic>{
        'id': 'owner',
        'version': 1,
        'display_name': name,
        'country': 'KZ',
        'locale': 'ru',
        'roles': ['customer'],
        'active_role': 'customer'
      };
      final a = JobaApi('https://isolated.example', vault: _Vault(),
          transport: MockClient((r) async {
        if (r.url.path.endsWith('/auth/login'))
          return ok({
            'access_token': 'isolated',
            'refresh_token': 'isolated-refresh',
            'user': user
          });
        if (r.url.path.endsWith('/me')) {
          if (r.method == 'PATCH')
            user = {...user, ...jsonDecode(r.body), 'version': 2};
          return ok(user);
        }
        if (r.url.path.endsWith('/legal/documents'))
          return ok({
            'items': [
              {'id': 'terms', 'type': 'terms', 'version': 1, 'hash': 'terms-1'},
              {
                'id': 'privacy',
                'type': 'privacy',
                'version': 1,
                'hash': 'privacy-1'
              }
            ]
          });
        return ok({'items': []});
      }));
      addTearDown(a.dispose);
      await t.pumpWidget(JobaApp(api: a));
      await t.pumpAndSettle();
      final dynamic state = t.state(find.byType(Marketplace));
      state.go('login');
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextFormField).at(0), '+77000000001');
      await t.enterText(
          find.byType(TextFormField).at(1), 'Isolated password 2026!');
      await t.ensureVisible(find.widgetWithText(FilledButton, 'Войти'));
      await t.tap(find.widgetWithText(FilledButton, 'Войти'));
      await t.pumpAndSettle();
      expect(state.route, 'lock-setup');
      expect(state.registrationInProgress, name.isEmpty);
      await state.completeLocalSetup(passwordOnly: true);
      await t.pumpAndSettle();
      expect(state.route, 'terms');
      if (name.isEmpty) {
        await t.tap(find.byType(CheckboxListTile).at(0));
        await t.pump();
        await t.tap(find.byType(CheckboxListTile).at(1));
        await t.pump();
        await t.tap(find.text('Принять и продолжить'));
        await t.pumpAndSettle();
        expect(state.route, 'onboarding');
        await t.enterText(find.byType(TextFormField).first, 'Complete');
        await t.tap(find.text('Сохранить профиль'));
        await t.pumpAndSettle();
        expect(state.route, 'home');
        expect(state.registrationInProgress, false);
        expect(user['display_name'], 'Complete');
      }
      await t.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
      'onboarding Back returns to terms and restores a scoped draft over the latest server version',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var version = 1;
    final writes = <Json>[];
    final user = <String, dynamic>{
      'id': 'owner',
      'version': 1,
      'display_name': 'Марина',
      'city': '',
      'country': 'KZ',
      'locale': 'ru',
      'roles': ['customer'],
      'active_role': 'customer'
    };
    final api = JobaApi('https://isolated.example', vault: _Vault(),
        transport: MockClient((r) async {
      if (r.url.path.endsWith('/me') && r.method == 'GET')
        return ok({...user, 'version': version});
      if (r.method == 'PATCH') {
        final b = jsonDecode(r.body) as Json;
        writes.add(b);
        return ok({...user, ...b, 'version': version + 1});
      }
      return ok({
        'items': [],
        'meta': {'has_any': false}
      });
    }));
    await tester.pumpWidget(JobaApp(api: api));
    await tester.pumpAndSettle();
    final dynamic state = tester.state(find.byType(Marketplace));
    api.session = {'access_token': 'isolated-token', 'user': user};
    state.me = user;
    state.go('terms');
    state.go('onboarding');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Черновик');
    await tester.scrollUntilVisible(find.text('Найти заказы'), 150,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Найти заказы'));
    await tester.pump();
    await tester.tap(find.byTooltip('Назад'));
    await tester.pumpAndSettle();
    expect(state.route, 'terms');
    expect(writes, isEmpty);
    version = 7;
    state.go('onboarding');
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        'Черновик');
    expect(state.profileDraft['role'], 'executor');
    await tester.scrollUntilVisible(find.text('Найти специалиста'), 150,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Найти специалиста'));
    await tester.pump();
    await tester.tap(find.text('Сохранить профиль'));
    await tester.pumpAndSettle();
    expect(writes.single['expected_version'], 7);
    expect(writes.single['display_name'], 'Черновик');
    expect(writes.single['active_role'], 'customer');
    expect(writes.single['roles'], ['customer']);
    expect(state.route, 'home');
    expect(state.profileDraft, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    api.dispose();
  });
  for (final choice in ['customer', 'executor', 'logout']) {
    testWidgets(
        'onboarding $choice preserves pending state and uses the correct continuation',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final gate = Completer<http.Response>();
      final calls = <http.Request>[];
      final user = <String, dynamic>{
        'id': 'owner',
        'version': 1,
        'display_name': 'Марина',
        'city': '',
        'country': 'KZ',
        'locale': 'ru',
        'roles': ['customer'],
        'active_role': 'customer'
      };
      final api = JobaApi('https://isolated.example', vault: _Vault(),
          transport: MockClient((r) async {
        calls.add(r);
        if (r.method == 'PATCH') {
          final b = jsonDecode(r.body);
          expect(b['display_name'], 'Новое имя');
          expect(
              b['active_role'], choice == 'executor' ? 'executor' : 'customer');
          return gate.future;
        }
        if (r.url.path.endsWith('/me')) return ok(user);
        if (r.url.path.endsWith('/me/contractor-profile'))
          return ok({'profile': null});
        return ok({
          'items': [],
          'meta': {'has_any': false}
        });
      }));
      await tester.pumpWidget(JobaApp(api: api));
      await tester.pumpAndSettle();
      final dynamic state = tester.state(find.byType(Marketplace));
      api.session = {'access_token': 'isolated-token', 'user': user};
      state.me = user;
      state.registrationInProgress = true;
      state.go('onboarding');
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'Новое имя');
      if (choice == 'executor') {
        await tester.scrollUntilVisible(find.text('Найти заказы'), 150,
            scrollable: find.byType(Scrollable).first);
        await tester.tap(find.text('Найти заказы'));
        await tester.pump();
      }
      await tester.tap(find.text('Сохранить профиль'));
      await tester.pump();
      expect(calls.where((r) => r.method == 'PATCH'), hasLength(1));
      expect(state.profilePending, 1);
      state.back();
      expect(state.route, 'onboarding');
      state.go('home');
      expect(state.route, 'onboarding');
      if (choice == 'logout') {
        await api.forget();
        await tester.pumpAndSettle();
      }
      gate.complete(ok({
        ...user,
        'display_name': 'Новое имя',
        'roles': choice == 'executor' ? ['customer', 'executor'] : ['customer'],
        'active_role': choice == 'executor' ? 'executor' : 'customer',
        'version': 2
      }));
      await tester.pumpAndSettle();
      expect(
          state.route,
          choice == 'logout'
              ? 'login'
              : choice == 'executor'
                  ? 'services'
                  : 'home');
      expect(state.profilePending, 0);
      expect(calls.any((r) => r.url.path.contains('/billing/')), false);
      if (choice == 'logout') {
        expect(state.me, isNull);
        expect(state.profileDraft, isNull);
      } else
        expect(state.me['display_name'], 'Новое имя');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      api.dispose();
    });
  }
}
