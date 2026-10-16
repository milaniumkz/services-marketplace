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
  Future<void> write(String value) async {}
  Future<void> clear() async {}
}
void main() {
  testWidgets('customer subscription links show free access without requesting billing', (tester) async {
    final requests = <String>[];
    final user = <String,dynamic>{'id':'customer','country':'KZ','locale':'ru','active_role':'customer','roles':['customer','executor'],'display_name':'Заказчик','city':'Алматы','version':1};
    final api = JobaApi('https://isolated.example', vault:_Vault(), transport:MockClient((r) async {
      final path = r.url.path.replaceFirst('/api/v1','');requests.add(path);
      final dynamic data = path=='/me'?user:path=='/me/overview'?{'orders':{},'subscription_until':'2030-01-01T00:00:00Z'}:{'items':[]};
      return http.Response(jsonEncode({'data':data,'meta':{}}),200,headers:{'content-type':'application/json; charset=utf-8'});
    }));
    await tester.pumpWidget(JobaApp(api:api));await tester.pumpAndSettle();
    final dynamic state = tester.state(find.byType(Marketplace));
    api.session={'access_token':'isolated-customer-token','user':user};state.me=user;state.executor=false;
    state.go('account');await tester.pumpAndSettle();
    expect(find.text('Подписка активна'),findsNothing);expect(find.text('Мой доступ'),findsNothing);
    await tester.tap(find.ancestor(of:find.text('Заказчик'),matching:find.byType(InkWell)));await tester.pumpAndSettle();expect(state.route,'roles');
    for (final route in ['my-access','checkout','restore','manage-subscription']) {
      state.go(route);await tester.pumpAndSettle();
      expect(find.text('Для заказчика бесплатно'),findsOneWidget);
      expect(find.text('Подписка JOBA'),findsNothing);
    }
    await tester.tap(find.text('Найти исполнителя'));await tester.pumpAndSettle();expect(state.route,'catalog');
    state.go('my-access');await tester.pumpAndSettle();await tester.tap(find.text('Мои заказы'));await tester.pumpAndSettle();expect(state.route,'orders');
    expect(requests.any((p)=>p.startsWith('/billing/')||p=='/me/subscriptions'||p=='/me/entitlements'),false);
    state.executor=true;state.go('my-access');await tester.pumpAndSettle();
    expect(find.text('Подписка JOBA'),findsOneWidget);expect(requests.contains('/me/subscriptions'),true);
    await tester.pumpWidget(const SizedBox());api.dispose();
  });
}
