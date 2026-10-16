import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import '../lib/core/api.dart';
import '../lib/core/theme.dart';
import '../lib/screens/referral_code.dart';

class _Vault implements SessionVault {
  Future<String?> read() async => null;
  Future<void> write(String value) async {}
  Future<void> clear() async {}
}

void main() {
  testWidgets(
      'invitation validates locally, retains code after rejection and retries once without duplicate requests',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final requests = <http.Request>[];
    var pending = Completer<http.Response>();
    var accepted = 0;
    final api = JobaApi('https://isolated.example', vault: _Vault(),
        transport: MockClient((request) {
      requests.add(request);
      return pending.future;
    }));
    api.session = {
      'access_token': 'isolated-referral-session',
      'user': {'id': 'isolated-user'}
    };
    await tester.pumpWidget(MaterialApp(
        theme: jobaTheme(),
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                            builder: (_) => ReferralCodeScreen(
                                api: api, onAccepted: () => accepted++))),
                    child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Сначала проверим код'), findsOneWidget);
    await tester.tap(find.text('Проверить код'));
    await tester.pumpAndSettle();
    expect(requests, isEmpty);
    await tester.enterText(
        find.byType(TextFormField), List.filled(51, 'a').join());
    await tester.tap(find.text('Проверить код'));
    await tester.pumpAndSettle();
    expect(requests, isEmpty);
    expect(find.text('Код должен содержать не больше 50 символов'),
        findsOneWidget);
    await tester.enterText(find.byType(TextFormField), '  invited-code  ');
    await tester.tap(find.text('Проверить код'));
    await tester.pump();
    expect(requests.length, 1);
    expect(requests.single.url.path, '/api/v1/referrals/attribute');
    expect(jsonDecode(requests.single.body)['code'], 'invited-code');
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    pending.complete(http.Response(
        jsonEncode({
          'error': {
            'code': 'ATTRIBUTION_WINDOW_EXPIRED',
            'message': 'Срок ввода кода после регистрации истёк',
            'details': {}
          }
        }),
        422,
        headers: {'content-type': 'application/json; charset=utf-8'}));
    await tester.pumpAndSettle();
    expect(accepted, 0);
    expect(
        find.text('Срок ввода кода после регистрации истёк'), findsOneWidget);
    expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        '  invited-code  ');
    pending = Completer<http.Response>();
    await tester.tap(find.text('Проверить код'));
    await tester.pump();
    expect(requests.length, 2);
    pending.complete(http.Response(
        jsonEncode({
          'data': {'status': 'pending'}
        }),
        200));
    await tester.pumpAndSettle();
    expect(accepted, 1);
    expect(find.byType(ReferralCodeScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
