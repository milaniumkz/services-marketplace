import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:services_marketplace/core/api.dart';
import 'package:services_marketplace/core/theme.dart';
import 'package:services_marketplace/screens/contractor_profile.dart';

void main() {
  for (final paused in [false, true]) {
    testWidgets('public profile actions use actual records; paused=$paused',
        (t) async {
      final events = <String>[];
      final api =
          JobaApi('https://isolated.example', transport: MockClient((r) async {
        if (r.url.path.endsWith('/download'))
          return http.Response.bytes(
              base64Decode(
                  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII='),
              200);
        expect(r.url.path, '/api/v1/contractors/service/portfolio');
        return http.Response(
            jsonEncode({
              'data': {
                'items': [
                  {
                    'id': 'actual-project',
                    'title': 'Моя работа',
                    'photos': ['photo'],
                    'cover_id': 'photo',
                    'linked_completed_order': true
                  }
                ]
              },
              'meta': {}
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }))
            ..session = {'access_token': 'isolated'};
      await t.pumpWidget(MaterialApp(
          theme: jobaTheme(),
          home: Scaffold(
              body: ContractorProfile(
                  api: api,
                  locale: 'ru',
                  profile: {
                    'id': 'service',
                    'owner': 'executor',
                    'display_name': 'Мастер',
                    'title': 'Ремонт',
                    'description': 'Описание услуги',
                    'city': 'Алматы',
                    'verification': {'status': 'passed'},
                    'rating': {'average': 4.9, 'count': 32},
                    'completed_orders': 38,
                    'portfolio_count': 1,
                    'experience_years': 5,
                    'availability': paused ? 'paused' : 'available',
                    'price': {'mode': 'negotiable'}
                  },
                  onProject: (p) => events.add(p['id']),
                  onInvite: () => events.add('invite'),
                  onPortfolio: () => events.add('portfolio'),
                  onReviews: () => events.add('reviews'),
                  onReport: () => events.add('report'),
                  onBlock: () => events.add('block'),
                  onOverview: () => events.add('overview')))));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Пожаловаться'));
      expect(events, ['report']);
      await t.tap(find.text('Обзор'));
      await t.tap(find.text('Портфолио · 1'));
      await t.tap(find.text('Отзывы'));
      expect(events, ['report', 'overview', 'portfolio', 'reviews']);
      final invite = t.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Предложить заказ'));
      expect(invite.onPressed, paused ? isNull : isNotNull);
      if (!paused) {
        await t.tap(find.text('Предложить заказ'));
        expect(events.last, 'invite');
      }
      await t.scrollUntilVisible(find.text('Моя работа'), 200,
          scrollable: find.byType(Scrollable).first);
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Моя работа'));
      await t.drag(find.byType(ListView).first, const Offset(0, -150));
      await t.pumpAndSettle();
      await t.tap(find.text('Моя работа'));
      expect(events.last, 'actual-project');
      await t.scrollUntilVisible(find.text('Заблокировать контакт'), 150,
          scrollable: find.byType(Scrollable).first);
      await t.tap(find.text('Заблокировать контакт'));
      expect(events.last, 'block');
      await t.pumpWidget(const SizedBox());
      api.dispose();
    });
  }
}
