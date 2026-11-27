import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:services_marketplace/core/theme.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:services_marketplace/core/api.dart';
import 'package:services_marketplace/screens/refunds.dart';

http.Response ok(dynamic data) => http.Response(jsonEncode({'data': data}), 200,
    headers: {'content-type': 'application/json; charset=utf-8'});
Json payment() => {
      'id': 'payment-owned',
      'amount_minor': 123456,
      'currency': 'KZT',
      'benefit': 'subscription',
      'balance': {'available_minor': 100001, 'reserved_minor': 23455}
    };
void main() {
  test('refund amount keeps exact minor units and rejects invalid amounts', () {
    expect(parseRefundAmount('1000,01'), 100001);
    expect(parseRefundAmount('0.01'), 1);
    expect(parseRefundAmount('90071992547409.91'), 9007199254740991);
    for (final value in [
      '0',
      '-1',
      'NaN',
      '1.111',
      '1e3',
      '90071992547409.92'
    ]) {
      expect(parseRefundAmount(value), isNull, reason: value);
    }
  });
  testWidgets(
      'refund screens fit the mobile viewport and expose actual server status',
      (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await (FontLoader('Noto')
          ..addFont(rootBundle.load('assets/NotoSans-Regular.ttf'))
          ..addFont(rootBundle.load('assets/NotoSans-Bold.ttf')))
        .load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
    final api =
        JobaApi('https://isolated.example', transport: MockClient((r) async {
      if (r.url.path.endsWith('refundable-payments'))
        return ok({
          'items': [payment()],
          'meta': {}
        });
      return ok({
        'items': [
          {
            'id': 'request-owned',
            'payment_id': 'payment-owned',
            'amount_minor': 100001,
            'currency': 'KZT',
            'reason': 'Услуга не требуется',
            'status': 'unknown',
            'version': 3
          }
        ],
        'meta': {}
      });
    }))
          ..session = {'access_token': 'isolated'};
    final boundary = GlobalKey();
    await t.pumpWidget(RepaintBoundary(
        key: boundary,
        child: MaterialApp(
            debugShowCheckedModeBanner: false, theme: jobaTheme(),
            home: Scaffold(
                appBar: AppBar(title: const Text('Платежи и возвраты')),
                body: RefundsScreen(api: api, onSupport: () {})))));
    await t.pumpAndSettle();
    Future<void> capture(String name) async {
      final dir = Platform.environment['JOBA_SCREENSHOT_DIR'];
      if (dir == null) return;
      await t.runAsync(() async {
        final image = await (boundary.currentContext!.findRenderObject()
                as RenderRepaintBoundary)
            .toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(dir).create(recursive: true);
        await File('$dir/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    await capture('refund-payments');
    expect(t.takeException(), isNull);
    await t.tap(find.byType(ListTile));
    await t.pumpAndSettle();
    await capture('refund-editor');
    expect(t.takeException(), isNull);
    await t.tap(find.text('К платежам'));
    await t.pumpAndSettle();
    await t.tap(find.text('Заявки'));
    await t.pumpAndSettle();
    await capture('refund-history');
    await t.tap(find.text('Требуется сверка'));
    await t.pumpAndSettle();
    await capture('refund-unknown');
    expect(find.textContaining('Сумма остаётся зарезервированной'),
        findsOneWidget);
    expect(find.text('Возврат подтверждён'), findsNothing);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    api.dispose();
  });
  testWidgets(
      'lost submission locks the payload and retries one idempotent command',
      (t) async {
    t.view.physicalSize = const Size(390, 1400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final sent = <http.Request>[];
    Json? saved;
    final api =
        JobaApi('https://isolated.example', transport: MockClient((r) async {
      sent.add(r);
      if (sent.length == 1) throw http.ClientException('response lost');
      return ok({'id': 'actual-request', 'status': 'requested'});
    }))
          ..session = {
            'access_token': 'isolated',
            'user': {'id': 'owner'}
          };
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: RefundEditor(
                api: api,
                payment: payment(),
                onBack: () {},
                onSaved: (v) => saved = v))));
    await t.enterText(find.byKey(const ValueKey('refund-amount')), '1000,02');
    await t.enterText(
        find.byKey(const ValueKey('refund-reason')), 'Услуга не требуется');
    await t.tap(find.byType(CheckboxListTile));
    await t.pumpAndSettle();
    await t.tap(find.text('Отправить заявку'));
    await t.pumpAndSettle();
    expect(sent, isEmpty);
    expect(find.text('Сумма превышает доступный остаток'), findsOneWidget);
    await t.enterText(find.byKey(const ValueKey('refund-amount')), '1000,01');
    await t.tap(find.text('Отправить заявку'));
    await t.pumpAndSettle();
    expect(saved, isNull);
    expect(sent.length, 1);
    expect(
        t
            .widget<TextFormField>(find.byKey(const ValueKey('refund-amount')))
            .enabled,
        false);
    expect(find.text('Услуга не требуется'), findsOneWidget);
    await t.tap(find.text('Повторить отправку'));
    await t.pumpAndSettle();
    expect(saved?['id'], 'actual-request');
    expect(sent.length, 2);
    expect(sent[0].headers['Idempotency-Key'], isNotEmpty);
    expect(
        sent[1].headers['Idempotency-Key'], sent[0].headers['Idempotency-Key']);
    expect(sent[1].body, sent[0].body);
    expect(jsonDecode(sent[1].body)['amount_minor'], 100001);
    await t.pumpWidget(const SizedBox());
    api.dispose();
  });
  testWidgets(
      'history paginates, cancellation checks version, conflict refreshes actual state',
      (t) async {
    t.view.physicalSize = const Size(390, 1400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    var status = 'requested', pages = 0, support = 0;
    final commands = <Json>[];
    final api =
        JobaApi('https://isolated.example', transport: MockClient((r) async {
      if (r.method == 'POST') {
        commands.add(Json.from(jsonDecode(r.body)));
        status = 'approved';
        return http.Response(
            jsonEncode({
              'error': {
                'code': 'STATE_CONFLICT',
                'message': 'Данные изменились'
              }
            }),
            409,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }
      if (r.url.path.endsWith('refundable-payments'))
        return ok({
          'items': [payment()],
          'meta': {}
        });
      pages++;
      return ok({
        'items': [
          {
            'id': r.url.queryParameters['cursor'] == null ? 'first' : 'second',
            'payment_id': 'payment-owned',
            'amount_minor': 100001,
            'currency': 'KZT',
            'reason': 'Услуга не требуется',
            'status': status,
            'version': status == 'requested' ? 3 : 4,
          }
        ],
        'meta': {
          'next_cursor':
              r.url.queryParameters['cursor'] == null ? 'next-page' : null
        }
      });
    }))
          ..session = {'access_token': 'isolated'};
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: RefundsScreen(api: api, onSupport: () => support++))));
    await t.pumpAndSettle();
    await t.tap(find.text('Заявки'));
    await t.pumpAndSettle();
    expect(find.text('На рассмотрении'), findsOneWidget);
    await t.tap(find.text('Показать ещё'));
    await t.pumpAndSettle();
    expect(pages, 2);
    expect(find.text('На рассмотрении'), findsNWidgets(2));
    await t.tap(find.text('На рассмотрении').first);
    await t.pumpAndSettle();
    await t.tap(find.text('Отменить заявку'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Отменить заявку'));
    await t.pumpAndSettle();
    expect(commands.single['expected_version'], 3);
    expect(find.text('Данные изменились. Обновите экран и повторите действие.'),
        findsOneWidget);
    await t.tap(find.text('Обновить историю'));
    await t.pumpAndSettle();
    await t.tap(find.text('Возврат согласован').first);
    await t.pumpAndSettle();
    expect(find.text('Отменить заявку'), findsNothing);
    expect(find.textContaining('не означает зачисления'), findsOneWidget);
    await t.tap(find.text('Обратиться в поддержку'));
    expect(support, 1);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    api.dispose();
  });
  testWidgets(
      'full reservation disables a new refund and never submits a request',
      (t) async {
    var commands = 0;
    final p = payment();
    p['balance'] = {'available_minor': 0, 'reserved_minor': 123456};
    final api =
        JobaApi('https://isolated.example', transport: MockClient((r) async {
      commands++;
      return ok({});
    }))
          ..session = {'access_token': 'test'};
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: RefundEditor(
                api: api, payment: p, onBack: () {}, onSaved: (_) {}))));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Отправить заявку'));
    expect(
        t
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Отправить заявку'))
            .onPressed,
        isNull);
    expect(commands, 0);
    await t.pumpWidget(const SizedBox());
    api.dispose();
  });
}
