import 'dart:convert';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:services_marketplace/core/api.dart';
import 'package:services_marketplace/screens/offer_editor.dart';

http.Response ok(dynamic data) =>
    http.Response(jsonEncode({'data': data, 'meta': {}}), 200,
        headers: {'content-type': 'application/json; charset=utf-8'});
void main() {
  setUpAll(() => initializeDateFormatting());
  testWidgets(
      'offer retains rejected text and duration, requires consent and submits real terms',
      (t) async {
    var attempts = 0;
    Json? sent;
    Json? saved;
    final api =
        JobaApi('https://isolated.example', transport: MockClient((r) async {
      attempts++;
      sent = Json.from(jsonDecode(r.body));
      if (attempts == 1)
        return http.Response(
            jsonEncode({
              'error': {
                'code': 'TEMPORARY_FAILURE',
                'message': 'Повторите отправку'
              }
            }),
            503,
            headers: {'content-type': 'application/json; charset=utf-8'});
      return ok({'id': 'actual-offer', 'version': 1});
    }))
          ..session = {'access_token': 'isolated'};
    final order = <String, dynamic>{
      'id': 'actual-order',
      'version': 4,
      'revision': 7,
      'status': 'open',
      'country': 'KZ',
      'currency': 'KZT',
      'title': 'Сборка кухни',
      'budget_amount': 4500000,
      'offer_policy': {
        'time_zone': 'Asia/Almaty',
        'latest_expires_local': '2030-10-18T18:00'
      }
    };
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: OfferEditor(
                api: api, order: order, onSaved: (value) => saved = value))));
    await t.pumpAndSettle();
    final submit = find.widgetWithText(FilledButton, 'Отправить отклик');
    expect(t.widget<FilledButton>(submit).onPressed, isNull);
    await t.enterText(
        find.byKey(const ValueKey('offer-note')), 'Привезу инструменты');
    await t.enterText(find.byKey(const ValueKey('offer-price')), '45000');
    await t.ensureVisible(find.byKey(const ValueKey('offer-duration')));
    await t.enterText(find.byKey(const ValueKey('offer-duration')), '5');
    await t.scrollUntilVisible(find.byType(CheckboxListTile), 200,
        scrollable: find.byType(Scrollable).first);
    await t.tap(find.byType(CheckboxListTile));
    await t.pumpAndSettle();
    await t.tap(submit);
    await t.pumpAndSettle();
    expect(saved, isNull);
    expect(attempts, 1);
    await t.ensureVisible(find.byKey(const ValueKey('offer-note')));
    expect(find.text('Привезу инструменты'), findsOneWidget);
    await t.tap(submit);
    await t.pumpAndSettle();
    expect(saved?['id'], 'actual-offer');
    expect(sent?['amount'], 4500000);
    expect(sent?['duration_minutes'], 300);
    expect(sent?['acknowledged_revision'], 7);
    expect(sent?['expires_local'], '2030-10-18T18:00');
    await t.pumpWidget(const SizedBox());
    api.dispose();
  });
  testWidgets(
      'edit keeps the original expiry and version instead of extending to the policy maximum',
      (t) async {
    Json? sent;
    final api =
        JobaApi('https://isolated.example', transport: MockClient((r) async {
      sent = Json.from(jsonDecode(r.body));
      return ok({'id': 'actual-offer', 'version': 3});
    }))
          ..session = {'access_token': 'isolated'};
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: OfferEditor(
                api: api,
                order: {
                  'id': 'order',
                  'revision': 4,
                  'status': 'open',
                  'country': 'KZ',
                  'currency': 'KZT',
                  'title': 'Заказ',
                  'offer_policy': {
                    'time_zone': 'Asia/Almaty',
                    'latest_expires_local': '2030-10-18T18:00'
                  }
                },
                offer: {
                  'id': 'actual-offer',
                  'version': 2,
                  'status': 'active',
                  'text': 'Первоначальное предложение',
                  'amount': 4500000,
                  'duration_minutes': 300,
                  'proposed_start_local': '2030-10-17T10:00',
                  'expires_local': '2030-10-16T18:00'
                },
                onSaved: (_) {}))));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.byType(CheckboxListTile), 200,
        scrollable: find.byType(Scrollable).first);
    await t.tap(find.byType(CheckboxListTile));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Сохранить'));
    await t.pumpAndSettle();
    expect(sent?['expected_version'], 2);
    expect(sent?.containsKey('expires_local'), false);
    expect(sent?['proposed_start_local'], '2030-10-17T10:00');
    expect(sent?['duration_minutes'], 300);
    await t.pumpWidget(const SizedBox());
    api.dispose();
  });
  testWidgets(
      'start picker uses order dates while expiry can be before the start date',
      (t) async {
    final today = DateUtils.dateOnly(DateTime.now()),
        tomorrow =
            DateUtils.dateOnly(DateTime.now()).add(const Duration(days: 1));
    final until = tomorrow.add(const Duration(days: 2));
    String day(DateTime v) => v.toIso8601String().split('T').first;
    final api = JobaApi('https://isolated.example',
        transport: MockClient((r) async => ok({})));
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: OfferEditor(
                api: api,
                order: {
                  'id': 'order',
                  'revision': 1,
                  'status': 'open',
                  'country': 'KZ',
                  'currency': 'KZT',
                  'title': 'Заказ',
                  'time_window': {
                    'start_date': day(tomorrow),
                    'end_date': day(until),
                    'time_zone': 'Asia/Almaty'
                  },
                  'offer_policy': {
                    'time_zone': 'Asia/Almaty',
                    'latest_expires_local': '${day(today)}T18:00'
                  }
                },
                onSaved: (_) {}))));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Выберите дату'));
    await t.tap(find.text('Выберите дату'));
    await t.pumpAndSettle();
    var dialog = t.widget<DatePickerDialog>(find.byType(DatePickerDialog));
    expect(dialog.firstDate, tomorrow);
    expect(dialog.lastDate, until);
    Navigator.of(t.element(find.byType(DatePickerDialog))).pop();
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.textContaining('18:00'), 150,
        scrollable: find.byType(Scrollable).first);
    await t.tap(find.textContaining('18:00'));
    await t.pumpAndSettle();
    dialog = t.widget<DatePickerDialog>(find.byType(DatePickerDialog));
    expect(dialog.firstDate, today);
    expect(dialog.lastDate, today);
    Navigator.of(t.element(find.byType(DatePickerDialog))).pop();
    await t.pumpAndSettle();
    await t.pumpWidget(const SizedBox());
    api.dispose();
  });
}
