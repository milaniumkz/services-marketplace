import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:services_marketplace/main.dart';
import 'package:services_marketplace/core/api.dart';
import 'package:services_marketplace/core/design_widgets.dart';
import 'package:services_marketplace/core/photo_picker.dart';
import 'package:services_marketplace/screens/marketplace.dart';
import 'package:services_marketplace/screens/verification_editor.dart';
import 'widget_test.dart' show MemoryVault;

void main() {
  testWidgets(
      'global navigation stays on nested pages, exposes real unread counts and profile rating',
      (t) async {
    t.view.physicalSize = const Size(393, 852);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final user = {
      'id': 'worker',
      'country': 'KZ',
      'locale': 'ru',
      'roles': ['executor'],
      'active_role': 'executor',
      'verification': 'passed',
      'display_name': 'Тестовый исполнитель',
      'city': 'Караганда',
      'version': 1
    };
    var unread = 3;
    final api = JobaApi('https://isolated.example', vault: MemoryVault(),
        transport: MockClient((r) async {
      final path = r.url.path.replaceFirst('/api/v1', '');
      final dynamic data = path == '/me'
          ? user
          : path == '/me/overview'
              ? {
                  'rating': {'count': 2, 'average': 4.5},
                  'orders': {}
                }
              : path == '/me/unread-counts'
                  ? {'messages': unread, 'notifications': 7}
                  : path == '/orders/order'
                      ? {
                          'id': 'order',
                          'owner': 'worker',
                          'status': 'completion_requested',
                          'version': 1,
                          'title': 'Побелить стены',
                          'description': 'Описание заказа',
                          'upload_ids': [],
                          'currency': 'KZT'
                        }
                      : {'items': []};
      return http.Response(jsonEncode({'data': data}), 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    }));
    addTearDown(api.dispose);
    await t.pumpWidget(JobaApp(api: api));
    await t.pumpAndSettle();
    api.session = {'access_token': 'fixture', 'user': user};
    final dynamic state = t.state(find.byType(Marketplace));
    state.me = user;
    state.executor = true;
    state.go('account');
    await t.pumpAndSettle();
    await state.refreshUnread();
    await t.pumpAndSettle();
    expect(find.text('Рейтинг: 4.5 / 5 · Отзывов: 2'), findsOneWidget);
    expect(
        t.widget<JobaNavigation>(find.byType(JobaNavigation)).messageCount, 3);
    expect(
        t.widget<JobaNavigation>(find.byType(JobaNavigation)).notificationCount,
        7);
    final context = t.element(find.byType(Marketplace));
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Вложенная форма'))));
    await t.pumpAndSettle();
    expect(find.text('Вложенная форма'), findsOneWidget);
    expect(find.byType(JobaNavigation), findsOneWidget);
    await t.tap(find.descendant(
        of: find.byType(JobaNavigation), matching: find.text('Профиль')));
    await t.pumpAndSettle();
    expect(find.text('Вложенная форма'), findsNothing);
    expect(state.route, 'account');
    for (final route in [
      'review',
      'complete',
      'verification',
      'notifications'
    ]) {
      state.go(route, 'order');
      await t.pumpAndSettle();
      expect(find.byType(JobaNavigation), findsOneWidget, reason: route);
    }
    unread = 0;
    await state.refreshUnread();
    await t.pumpAndSettle();
    expect(
        t.widget<JobaNavigation>(find.byType(JobaNavigation)).messageCount, 0);
  });
  testWidgets(
      'new executor is routed to identity before categories and can fill services while documents wait',
      (t) async {
    var profile = <String, dynamic>{
      'id': 'new-worker',
      'country': 'KZ',
      'locale': 'ru',
      'roles': ['customer'],
      'active_role': 'customer',
      'verification': 'not_started',
      'display_name': 'Новичок',
      'city': 'Алматы',
      'version': 1
    };
    final api = JobaApi('https://isolated.example', vault: MemoryVault(),
        transport: MockClient((r) async {
      final path = r.url.path.replaceFirst('/api/v1', '');
      if (path == '/me' && r.method == 'PATCH')
        profile = {
          ...profile,
          ...Map<String, dynamic>.from(jsonDecode(r.body)),
          'version': profile['version'] + 1
        };
      final dynamic data = path == '/me'
          ? profile
          : path == '/me/verification'
              ? {
                  'status': profile['verification'],
                  'items': [],
                  'policy': {
                    'id': 'policy',
                    'document_types': ['id_card'],
                    'required_pages': {
                      'id_card': [
                        'Лицевая сторона',
                        'Обратная сторона',
                        'Селфи'
                      ]
                    },
                    'consent_accepted': false
                  }
                }
              : path == '/me/contractor-profile'
                  ? {'profile': null}
                  : {'items': []};
      return http.Response(jsonEncode({'data': data}), 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    }));
    addTearDown(api.dispose);
    await t.pumpWidget(JobaApp(api: api));
    await t.pumpAndSettle();
    api.session = {'access_token': 'fixture', 'user': profile};
    final dynamic state = t.state(find.byType(Marketplace));
    state.me = profile;
    await state.switchRole('executor');
    state.go('services');
    await t.pumpAndSettle();
    expect(find.byType(VerificationEditor), findsOneWidget);
    expect(find.text('Категории услуг'), findsNothing);
    profile = {...profile, 'verification': 'pending_review'};
    state.me = profile;
    state.go('services');
    await t.pumpAndSettle();
    expect(find.byType(VerificationEditor), findsNothing);
    expect(find.text('Категории услуг'), findsOneWidget);
  });
  testWidgets(
      'native identity and selfie open camera directly without gallery options',
      (t) async {
    for (final selfie in [false, true]) {
      PhotoSource? selected;
      bool? front;
      await t.pumpWidget(MaterialApp(
          home: Builder(
              builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () => choosePhoto(context,
                              identity: true, selfie: selfie, sourcePicker:
                                  (source, {required bool selfie}) async {
                            selected = source;
                            front = selfie;
                            return null;
                          }),
                      child: const Text('Снять'))))));
      await t.tap(find.text('Снять'));
      await t.pumpAndSettle();
      expect(selected, PhotoSource.camera);
      expect(front, selfie);
      expect(find.text('Выбрать из галереи'), findsNothing);
    }
  });
}
