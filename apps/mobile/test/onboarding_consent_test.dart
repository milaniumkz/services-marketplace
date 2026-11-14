import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:services_marketplace/core/api.dart';
import 'package:services_marketplace/core/theme.dart';
import 'package:services_marketplace/screens/onboarding_consent.dart';

class _Vault implements SessionVault {
  Future<String?> read() async => null;
  Future<void> write(String value) async {}
  Future<void> clear() async {}
}

void main() {
  for (final hold in ['consent', 'preferences']) {
    testWidgets('document revision during $hold stops the old acceptance chain',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final gate = Completer<http.Response>();
      final calls = <http.Request>[];
      var accepted = false;
      var revision = 1;
      final api = JobaApi('https://isolated.example', vault: _Vault(),
          transport: MockClient((r) async {
        calls.add(r);
        if ((hold == 'consent' && calls.length == 1) ||
            (hold == 'preferences' &&
                r.method == 'GET' &&
                r.url.path.endsWith('/notification-preferences')))
          return gate.future;
        return http.Response(
            jsonEncode({
              'data': r.url.path.endsWith('/me') ? {'version': 1} : {}
            }),
            200);
      }));
      api.session = {
        'access_token': 'isolated-token',
        'user': {'id': 'owner'}
      };
      addTearDown(api.dispose);
      Widget screen() => MaterialApp(
          theme: jobaTheme(),
          home: Scaffold(
              body: OnboardingConsent(
                  api: api,
                  documents: [
                    {
                      'id': 'terms',
                      'type': 'terms',
                      'version': revision,
                      'hash': 'terms-$revision',
                      'minimum_age': 18
                    },
                    {
                      'id': 'privacy',
                      'type': 'privacy',
                      'version': revision,
                      'hash': 'privacy-$revision'
                    }
                  ],
                  countryLabel: 'Казахстан',
                  localeLabel: 'Русский',
                  onAccepted: () => accepted = true)));
      await tester.pumpWidget(screen());
      for (final index in [0, 1]) {
        await tester.ensureVisible(find.byType(CheckboxListTile).at(index));
        await tester.tap(find.byType(CheckboxListTile).at(index));
        await tester.pump();
      }
      await tester.tap(find.text('Принять и продолжить'));
      await tester.pumpAndSettle();
      final beforeChange = calls.length;
      revision = 2;
      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();
      gate.complete(http.Response('{"data":{}}', 200));
      await tester.pumpAndSettle();
      expect(calls, hasLength(beforeChange));
      expect(accepted, false);
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull);
      expect(
          tester
              .widget<CheckboxListTile>(find.byType(CheckboxListTile).at(0))
              .value,
          false);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets(
      'server revision conflict clears declarations and requests current documents',
      (tester) async {
    var reloads = 0, calls = 0;
    final api = JobaApi('https://isolated.example', vault: _Vault(),
        transport: MockClient((r) async {
      calls++;
      return http.Response(
          '{"error":{"code":"LEGAL_VERSION_CHANGED","message":"Версия документа изменилась"}}',
          409,
          headers: {'content-type': 'application/json; charset=utf-8'});
    }));
    api.session = {
      'access_token': 'isolated-token',
      'user': {'id': 'owner'}
    };
    addTearDown(api.dispose);
    await tester.pumpWidget(MaterialApp(
        theme: jobaTheme(),
        home: Scaffold(
            body: OnboardingConsent(
                api: api,
                documents: const [
                  {
                    'id': 'terms',
                    'type': 'terms',
                    'hash': 'old-terms',
                    'version': 1,
                    'minimum_age': 18
                  },
                  {
                    'id': 'privacy',
                    'type': 'privacy',
                    'hash': 'old-privacy',
                    'version': 1
                  }
                ],
                countryLabel: 'Казахстан',
                localeLabel: 'Русский',
                onReload: () => reloads++,
                onAccepted: () => fail('Stale revision accepted')))));
    for (final index in [0, 1]) {
      await tester.ensureVisible(find.byType(CheckboxListTile).at(index));
      await tester.tap(find.byType(CheckboxListTile).at(index));
      await tester.pump();
    }
    await tester.tap(find.text('Принять и продолжить'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(reloads, 1);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    expect(
        tester
            .widget<CheckboxListTile>(find.byType(CheckboxListTile).at(0))
            .value,
        false);
    expect(
        tester
            .widget<CheckboxListTile>(find.byType(CheckboxListTile).at(1))
            .value,
        false);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'both document links open the selected published version without accepting it',
      (tester) async {
    final requests = <http.Request>[];
    final api = JobaApi('https://isolated.example', vault: _Vault(),
        transport: MockClient((r) async {
      requests.add(r);
      return http.Response('{"data":{}}', 200);
    }));
    addTearDown(api.dispose);
    await tester.pumpWidget(MaterialApp(
        theme: jobaTheme(),
        home: Scaffold(
            body: OnboardingConsent(
                api: api,
                documents: const [
                  {
                    'id': 'terms',
                    'type': 'terms',
                    'hash': 'terms-hash',
                    'version': 3,
                    'content': 'Isolated terms version three'
                  },
                  {
                    'id': 'privacy',
                    'type': 'privacy',
                    'hash': 'privacy-hash',
                    'version': 5,
                    'content': 'Isolated privacy version five'
                  }
                ],
                countryLabel: 'Казахстан',
                localeLabel: 'Русский',
                onAccepted: () => fail('Reading is not acceptance')))));
    for (final doc in {
      'Пользовательское соглашение': 'Isolated terms version three',
      'Политика конфиденциальности': 'Isolated privacy version five'
    }.entries) {
      await tester.tap(find.text(doc.key));
      await tester.pumpAndSettle();
      expect(find.text(doc.value), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
    expect(requests, isEmpty);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    expect(
        tester
            .widget<CheckboxListTile>(find.byType(CheckboxListTile).at(0))
            .value,
        false);
    expect(tester.takeException(), isNull);
  });
  testWidgets('missing legal documents explain the block and allow refreshing',
      (tester) async {
    var refreshed = false;
    final api = JobaApi('https://isolated.example', vault: _Vault());
    addTearDown(api.dispose);
    await tester.pumpWidget(MaterialApp(
        theme: jobaTheme(),
        home: Scaffold(
            body: OnboardingConsent(
                api: api,
                documents: const [],
                countryLabel: 'Казахстан',
                localeLabel: 'Русский',
                onAccepted: () => fail('Missing documents'),
                onReload: () => refreshed = true))));
    expect(find.textContaining('Регистрация временно недоступна:'),
        findsOneWidget);
    await tester.tap(find.text('Обновить'));
    expect(refreshed, true);
    for (var i = 0; i < 3; i++) {
      await tester.ensureVisible(find.byType(CheckboxListTile).at(i));
      await tester.tap(find.byType(CheckboxListTile).at(i));
      await tester.pump();
    }
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
  });
  for (final optionalMarketing in [false, true]) {
    testWidgets(
        'onboarding requires both explicit declarations and stores marketing $optionalMarketing separately',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final commands = <http.Request>[];
      var accepted = false;
      final api = JobaApi('https://isolated.example', vault: _Vault(),
          transport: MockClient((request) async {
        commands.add(request);
        dynamic data = {};
        if (request.url.path.endsWith('/me/notification-preferences'))
          data = request.method == 'GET'
              ? {
                  'marketing': false,
                  'chat': false,
                  'service': true,
                  'quiet_hours': {
                    'start': '22:00',
                    'end': '08:00',
                    'time_zone': 'Asia/Almaty'
                  }
                }
              : jsonDecode(request.body)['preferences'];
        if (request.url.path.endsWith('/me')) data = {'version': 4};
        return http.Response(jsonEncode({'data': data, 'meta': {}}), 200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }));
      api.session = {
        'access_token': 'isolated-token',
        'user': {'id': 'owner'}
      };
      addTearDown(api.dispose);
      var termsHash = 'terms-hash';
      Widget consent() => MaterialApp(
          theme: jobaTheme(),
          home: Scaffold(
              body: OnboardingConsent(
                  api: api,
                  documents: [
                    {
                      'id': 'terms',
                      'type': 'terms',
                      'version': 1,
                      'hash': termsHash,
                      'minimum_age': 18
                    },
                    {
                      'id': 'privacy',
                      'type': 'privacy',
                      'version': 1,
                      'hash': 'privacy-hash'
                    }
                  ],
                  countryLabel: 'Казахстан',
                  localeLabel: 'Русский',
                  onAccepted: () => accepted = true)));
      await tester.pumpWidget(consent());
      FilledButton submit() => tester
          .widget(find.widgetWithText(FilledButton, 'Принять и продолжить'));
      expect(submit().onPressed, isNull);
      await tester.tap(find.byType(CheckboxListTile).at(0));
      await tester.pumpAndSettle();
      expect(submit().onPressed, isNull);
      await tester.tap(find.byType(CheckboxListTile).at(1));
      await tester.pumpAndSettle();
      expect(submit().onPressed, isNotNull);
      // A newly published revision invalidates the previous declarations.
      termsHash = 'updated-terms-hash';
      await tester.pumpWidget(consent());
      await tester.pumpAndSettle();
      expect(submit().onPressed, isNull);
      expect(
          tester
              .widget<CheckboxListTile>(find.byType(CheckboxListTile).at(0))
              .value,
          false);
      expect(
          tester
              .widget<CheckboxListTile>(find.byType(CheckboxListTile).at(1))
              .value,
          false);
      await tester.tap(find.byType(CheckboxListTile).at(0));
      await tester.tap(find.byType(CheckboxListTile).at(1));
      await tester.pumpAndSettle();
      if (optionalMarketing) {
        await tester.tap(find.byType(CheckboxListTile).at(2));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Принять и продолжить'));
      await tester.pumpAndSettle();
      expect(accepted, true);
      final consents = commands
          .where((r) => r.url.path.endsWith('/me/consents'))
          .map((r) => jsonDecode(r.body) as Json)
          .toList();
      expect(consents.length, 2);
      expect(consents.first['age_confirmed'], true);
      expect(consents.first['document_hash'], 'updated-terms-hash');
      expect(consents.last.containsKey('age_confirmed'), false);
      final notification = jsonDecode(commands.last.body) as Json;
      expect(notification['expected_version'], 4);
      expect(notification['preferences']['marketing'], optionalMarketing);
      expect(notification['preferences']['chat'], false);
      expect(notification['preferences']['quiet_hours']['start'], '22:00');
    });
  }
}
