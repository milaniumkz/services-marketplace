import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:services_marketplace/core/api.dart';
import 'package:services_marketplace/core/verified_badge.dart';
import 'package:services_marketplace/main.dart';
import 'package:services_marketplace/screens/marketplace.dart';
import 'widget_test.dart' show MemoryVault, ok;

void main() {
  for (final role in ['customer', 'executor'])
    for (final verified in [false, true]) {
      testWidgets(
          '$role voluntary document verification is visible and confirmed profile has blue badge: $verified',
          (t) async {
        final user = {
          'id': 'owner',
          'country': 'KZ',
          'locale': 'ru',
          'version': 1,
          'display_name': 'Имя профиля',
          'roles': [role],
          'active_role': role,
          'verification': verified ? 'passed' : 'unverified'
        };
        var writes = 0;
        final api = JobaApi('https://isolated.example', vault: MemoryVault(),
            transport: MockClient((r) async {
          if (r.method == 'POST' &&
              r.url.path.endsWith('/me/verification-sessions')) writes++;
          if (r.url.path.endsWith('/me')) return ok(user);
          if (r.url.path.endsWith('/me/overview'))
            return ok({
              'orders': {},
              'rating': {'count': 0}
            });
          if (r.url.path.endsWith('/me/verification'))
            return ok(
                {'status': user['verification'], 'policy': null, 'items': []});
          return ok({'items': []});
        }));
        await t.pumpWidget(JobaApp(api: api));
        await t.pumpAndSettle();
        api.session = {'access_token': 'test', 'user': user};
        final dynamic state = t.state(find.byType(Marketplace));
        state.me = user;
        state.go('account');
        await t.pumpAndSettle();
        final name = t.widget<VerifiedName>(find.byType(VerifiedName).first);
        expect(name.verified, verified);
        await t.scrollUntilVisible(
            find.text('Добровольная проверка документов'), 200,
            scrollable: find.byType(Scrollable).first);
        await t.tap(find.text('Добровольная проверка документов'));
        await t.pumpAndSettle();
        expect(state.route, 'verification');
        expect(writes, 0);
        await t.pumpWidget(const SizedBox());
        api.dispose();
      });
    }
}
