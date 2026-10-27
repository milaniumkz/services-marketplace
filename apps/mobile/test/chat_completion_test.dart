import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:services_marketplace/core/api.dart';
import 'package:services_marketplace/main.dart';
import 'package:services_marketplace/screens/marketplace.dart';
import 'package:services_marketplace/screens/conversation_inbox.dart';

class _Vault implements SessionVault {
  Future<String?> read() async => null;
  Future<void> write(String value) async {}
  Future<void> clear() async {}
}

void main() {
  testWidgets(
      'chat renders authorized peer and order context and opens the order',
      (t) async {
    final user = {
      'id': 'customer',
      'country': 'KZ',
      'locale': 'ru',
      'active_role': 'customer',
      'roles': ['customer'],
      'display_name': 'Заказчик',
      'city': 'Алматы',
      'version': 1
    };
    final api = JobaApi('https://isolated.example', vault: _Vault(),
        transport: MockClient((r) async {
      final path = r.url.path.replaceFirst('/api/v1', '');
      final dynamic data = path == '/me'
          ? user
          : path == '/conversations/chat-id'
              ? {
                  'id': 'chat-id',
                  'peer': {'id': 'executor', 'display_name': 'Имя из API'},
                  'order_id': 'order-id',
                  'order_title': 'Заказ из API',
                  'order_status': 'assigned',
                  'order_amount': 4500000,
                  'currency': 'KZT',
                  'blocked': false,
                }
              : path == '/orders/order-id'
                  ? {
                      'id': 'order-id',
                      'owner': 'customer',
                      'title': 'Заказ из API',
                      'description': 'Подробное описание',
                      'city': 'Алматы',
                      'currency': 'KZT',
                      'status': 'assigned',
                      'version': 1
                    }
                  : {
                      'items': [],
                      'meta': {'has_more': false}
                    };
      return http.Response(jsonEncode({'data': data, 'meta': {}}), 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    }));
    await t.pumpWidget(JobaApp(api: api));
    await t.pumpAndSettle();
    final dynamic state = t.state(find.byType(Marketplace));
    api.session = {'access_token': 'isolated', 'user': user};
    state.me = user;
    state.executor = false;
    state.go('chat', 'chat-id');
    await t.pumpAndSettle();
    expect(find.text('Имя из API'), findsOneWidget);
    expect(find.text('Заказ из API'), findsOneWidget);
    expect(find.byTooltip('Действия чата'), findsOneWidget);
    await t.tap(find.text('Заказ из API'));
    await t.pumpAndSettle();
    expect(state.route, 'order');
    expect(state.objectId, 'order-id');
    await t.pumpWidget(const SizedBox());
    api.dispose();
  });
  testWidgets(
      'executor result retains rejected draft and customer confirms current version',
      (t) async {
    final user = <String, dynamic>{
      'id': 'executor',
      'country': 'KZ',
      'locale': 'ru',
      'active_role': 'executor',
      'roles': ['customer', 'executor'],
      'display_name': 'Исполнитель',
      'city': 'Алматы',
      'version': 1
    };
    var attempts = 0;
    Json? body;
    var status = 'in_progress';
    var version = 4;
    final api = JobaApi('https://isolated.example', vault: _Vault(),
        transport: MockClient((r) async {
      final path = r.url.path.replaceFirst('/api/v1', '');
      dynamic data;
      if (path == '/me')
        data = user;
      else if (path == '/orders/order-id/request-completion') {
        body = Json.from(jsonDecode(r.body));
        attempts++;
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
        status = 'completion_requested';
        version = 5;
        data = {'id': 'order-id', 'status': status, 'version': version};
      } else if (path == '/orders/order-id/confirm-completion') {
        body = Json.from(jsonDecode(r.body));
        status = 'completed';
        version = 6;
        data = {'id': 'order-id', 'status': status, 'version': version};
      } else if (path == '/orders/order-id')
        data = {
          'id': 'order-id',
          'owner': 'customer',
          'executor_id': 'executor',
          'version': version,
          'status': status,
          'title': 'Реальная работа',
          'description': 'Подробное описание работы',
          'city': 'Алматы',
          'currency': 'KZT',
          'executor': {'id': 'executor', 'display_name': 'Исполнитель'},
          'completion_note': 'Соединения проверены',
          'completion_requested_at': '2026-10-15T10:00:00Z',
          'completion_upload_ids': []
        };
      else
        data = {'items': []};
      return http.Response(jsonEncode({'data': data, 'meta': {}}), 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    }));
    await t.pumpWidget(JobaApp(api: api));
    await t.pumpAndSettle();
    final dynamic state = t.state(find.byType(Marketplace));
    api.session = {'access_token': 'isolated', 'user': user};
    state.me = user;
    state.executor = true;
    state.go('order', 'order-id');
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Запросить завершение'));
    await t.pumpAndSettle();
    await t.tap(find.text('Запросить завершение'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextFormField), 'Соединения проверены');
    await t.tap(find.text('Отправить результат'));
    await t.pumpAndSettle();
    expect(find.text('Соединения проверены'), findsOneWidget);
    await t.tap(find.text('Отправить результат'));
    await t.pumpAndSettle();
    expect(attempts, 2);
    expect(body?['note'], 'Соединения проверены');
    expect(body?['expected_version'], 4);
    expect(body?['upload_ids'], isEmpty);
    state.me = {...user, 'id': 'customer', 'active_role': 'customer'};
    state.executor = false;
    state.go('complete', 'order-id');
    await t.pumpAndSettle();
    expect(find.text('Соединения проверены'), findsOneWidget);
    await t.tap(find.text('Принять работу'));
    await t.pumpAndSettle();
    expect(body?['expected_version'], 5);
    expect(state.route, 'review');
    expect(status, 'completed');
    await t.pumpWidget(const SizedBox());
    api.dispose();
  });
  testWidgets(
      'selection requires consent and submits both actual record versions',
      (t) async {
    final user = <String, dynamic>{
      'id': 'customer',
      'country': 'KZ',
      'locale': 'ru',
      'active_role': 'customer',
      'roles': ['customer'],
      'display_name': 'Заказчик',
      'city': 'Алматы',
      'version': 1
    };
    Json? submitted;
    final api = JobaApi('https://isolated.example', vault: _Vault(),
        transport: MockClient((r) async {
      final path = r.url.path.replaceFirst('/api/v1', '');
      dynamic data;
      if (path == '/me')
        data = user;
      else if (path == '/offers/offer-id')
        data = {
          'id': 'offer-id',
          'version': 3,
          'status': 'active',
          'amount': 4500000,
          'currency': 'KZT',
          'executor': {'id': 'executor', 'display_name': 'Имя исполнителя'},
          'order': {
            'id': 'order-id',
            'owner': 'customer',
            'status': 'open',
            'version': 7,
            'revision': 4,
            'title': 'Заказ из API'
          }
        };
      else if (path == '/orders/order-id/select-offer') {
        submitted = Json.from(jsonDecode(r.body));
        data = {'id': 'order-id', 'status': 'assigned', 'version': 8};
      } else if (path == '/orders/order-id')
        data = {
          'id': 'order-id',
          'owner': 'customer',
          'status': 'assigned',
          'version': 8,
          'title': 'Заказ из API',
          'city': 'Алматы',
          'currency': 'KZT'
        };
      else
        data = {'items': []};
      return http.Response(jsonEncode({'data': data, 'meta': {}}), 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    }));
    await t.pumpWidget(JobaApp(api: api));
    await t.pumpAndSettle();
    final dynamic state = t.state(find.byType(Marketplace));
    api.session = {'access_token': 'isolated', 'user': user};
    state.me = user;
    state.executor = false;
    state.go('select-contractor', 'offer-id');
    await t.pumpAndSettle();
    final button = find.widgetWithText(FilledButton, 'Выбрать исполнителя');
    expect(t.widget<FilledButton>(button).onPressed, isNull);
    expect(submitted, isNull);
    await t.scrollUntilVisible(find.byType(CheckboxListTile), 150);
    await t.pumpAndSettle();
    await t.tap(find.byType(CheckboxListTile));
    await t.pumpAndSettle();
    await t.tap(button);
    await t.pumpAndSettle();
    expect(submitted,
        {'expected_version': 7, 'offer_id': 'offer-id', 'offer_version': 3});
    expect(state.route, 'work');
    await t.pumpWidget(const SizedBox());
    api.dispose();
  });
  testWidgets(
      'inbox searches through API, opens the exact chat and switches to support',
      (t) async {
    final requests = <String>[];
    String? destination, selectedId;
    final api = JobaApi('https://isolated.example', vault: _Vault(),
        transport: MockClient((r) async {
      requests.add(r.url.toString());
      final support = r.url.path.endsWith('/me/support-threads');
      final dynamic data = {
        'items': support
            ? []
            : [
                {
                  'id': 'actual-chat',
                  'peer': {'display_name': 'Собеседник из API'},
                  'order_title': 'Заказ из API',
                  'unread_count': 2,
                  'last_message': {
                    'text': 'Последнее сообщение',
                    'created_at': '2026-10-15T09:32:00Z'
                  }
                }
              ]
      };
      return http.Response(jsonEncode({'data': data, 'meta': {}}), 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    }))
      ..session = {'access_token': 'isolated'};
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ConversationInbox(
                api: api,
                revision: 1,
                onGo: (route, id) {
                  destination = route;
                  selectedId = id;
                }))));
    await t.pumpAndSettle();
    expect(find.text('Собеседник из API'), findsOneWidget);
    expect(find.text('Последнее сообщение'), findsOneWidget);
    await t.tap(find.text('Собеседник из API'));
    expect(destination, 'chat');
    expect(selectedId, 'actual-chat');
    await t.enterText(find.byType(TextField), 'кухня');
    await t.pump(const Duration(milliseconds: 350));
    await t.pumpAndSettle();
    expect(
        requests.any((url) => Uri.parse(url).queryParameters['q'] == 'кухня'),
        true);
    await t.tap(find.text('Поддержка'));
    await t.pumpAndSettle();
    expect(Uri.parse(requests.last).path.endsWith('/me/support-threads'), true);
    expect(find.text('Собеседник из API'), findsNothing);
    await t.pumpWidget(const SizedBox());
    api.dispose();
  });
}
