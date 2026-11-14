import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:services_marketplace/core/api.dart';
import 'package:services_marketplace/core/commerce_gateway.dart';
import 'package:services_marketplace/screens/commerce_states.dart';
import 'package:services_marketplace/screens/privacy_states.dart';

http.Response ok(dynamic data) =>
    http.Response(jsonEncode({'data': data, 'meta': {}}), 200,
        headers: {'content-type': 'application/json; charset=utf-8'});

class Gateway extends CommerceGateway {
  int played = 0;
  Future<Json> purchase(Json offer) async => throw UnimplementedError();
  Future<List<Json>> restore() async => [];
  Future<void> manage(Json subscription) async {}
  Future<bool> playReward(Json session) async {
    played++;
    return true;
  }
}

void main() {
  testWidgets(
      'disabled reward never creates a session; refreshing reloads real availability',
      (t) async {
    var gets = 0, posts = 0;
    String? route;
    final api =
        JobaApi('https://isolated.example', transport: MockClient((r) async {
      r.method == 'GET' ? gets++ : posts++;
      return ok({
        'rewarded_access_enabled': false,
        'reward_provider_ready': false,
        'reward_usage': {'remaining_today': 3, 'daily_cap': 3}
      });
    }))
          ..session = {'access_token': 'isolated'};
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CommerceStateScreen(
                api: api, mode: 'reward', onGo: (r, id) => route = r))));
    await t.pumpAndSettle();
    expect(
        t
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Посмотреть ролик'))
            .onPressed,
        isNull);
    expect(posts, 0);
    await t.scrollUntilVisible(find.text('Обновить условия'), 200,
        scrollable: find.byType(Scrollable).first);
    await t.tap(find.text('Обновить условия'));
    await t.pumpAndSettle();
    expect(gets, 2);
    expect(posts, 0);
    await t.scrollUntilVisible(find.text('Выбрать подписку'), 150,
        scrollable: find.byType(Scrollable).first);
    await t.tap(find.text('Выбрать подписку'));
    expect(route, 'access');
    await t.pumpWidget(const SizedBox());
    api.dispose();
  });
  testWidgets(
      'completed provider view only submits the outcome and opens pending confirmation',
      (t) async {
    final gateway = Gateway();
    String? route, id;
    final paths = <String>[];
    final api =
        JobaApi('https://isolated.example', transport: MockClient((r) async {
      paths.add(r.url.path);
      if (r.method == 'GET')
        return ok({
          'rewarded_access_enabled': true,
          'reward_provider_ready': true,
          'reward_policy': {'kind': 'duration', 'duration_seconds': 86400},
          'reward_usage': {'remaining_today': 2, 'daily_cap': 3}
        });
      return ok({'id': 'actual-session', 'status': 'pending'});
    }))
          ..session = {'access_token': 'isolated'};
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CommerceStateScreen(
                api: api,
                mode: 'reward',
                gateway: gateway,
                onGo: (r, i) {
                  route = r;
                  id = i;
                }))));
    await t.pumpAndSettle();
    await t.tap(find.text('Посмотреть ролик'));
    await t.pumpAndSettle();
    expect(gateway.played, 1);
    expect(route, 'reward-pending');
    expect(id, 'actual-session');
    expect(paths.last.endsWith('/ads/reward-sessions/actual-session/outcome'),
        true);
    await t.pumpWidget(const SizedBox());
    api.dispose();
  });
  testWidgets(
      'customer deletion screen has no subscription and requires explicit acknowledgement',
      (t) async {
    String? route;
    var posts = 0;
    final api =
        JobaApi('https://isolated.example', transport: MockClient((r) async {
      if (r.method != 'GET') posts++;
      return ok({
        'active_orders': 0,
        'subscription_relevant': false,
        'policy_ready': true
      });
    }))
          ..session = {'access_token': 'isolated'};
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: PrivacyStates(
                api: api,
                mode: 'delete-account',
                onGo: (r, id) => route = r))));
    await t.pumpAndSettle();
    expect(find.text('Подписка исполнителя'), findsNothing);
    expect(
        t
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Продолжить'))
            .onPressed,
        isNull);
    await t.tap(find.text('Активные заказы'));
    expect(route, 'orders');
    await t.tap(find.text('Сохранить свои данные'));
    expect(route, 'export');
    await t.scrollUntilVisible(find.byType(CheckboxListTile), 200,
        scrollable: find.byType(Scrollable).first);
    await t.tap(find.byType(CheckboxListTile));
    await t.pumpAndSettle();
    await t.tap(find.text('Продолжить'));
    expect(route, 'delete-confirm');
    expect(posts, 0);
    await t.pumpWidget(const SizedBox());
    api.dispose();
  });
}
