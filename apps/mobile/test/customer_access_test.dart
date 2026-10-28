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
void main(){
 testWidgets('customer sees the 500/30-day plan and executor sees only Standard and Premium', (tester) async {
  tester.view.physicalSize=const Size(390,844);tester.view.devicePixelRatio=1;
  addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
  final requests=<String>[];
  final user=<String,dynamic>{'id':'customer','country':'KZ','locale':'ru','active_role':'customer','roles':['customer','executor'],'display_name':'Заказчик','city':'Алматы','version':1,'verification':'passed'};
  final api=JobaApi('https://isolated.example',vault:_Vault(),transport:MockClient((r) async{
   final path=r.url.path.replaceFirst('/api/v1','');requests.add(path);if(path=='/me'&&r.method=='PATCH'){final changes=jsonDecode(r.body);user['active_role']=changes['active_role'];user['roles']=changes['roles'];user['version']=user['version']+1;}
   final dynamic data=path=='/me/monetization-config'?{'plans':user['active_role']=='customer'?[{'code':'customer','title':'Заказчик','amount_minor':50000,'currency':'KZT','duration_days':30}]:[{'code':'standard','amount_minor':100000,'currency':'KZT','duration_days':30},{'code':'premium','amount_minor':150000,'currency':'KZT','duration_days':30}],'offers':[]}:path=='/me/verification'?{'status':'passed','items':[]}:path=='/me'?user:path=='/me/overview'?{'orders':{}}:{'items':[]};
   return http.Response(jsonEncode({'data':data,'meta':{}}),200,headers:{'content-type':'application/json; charset=utf-8'});
  }));
  await tester.pumpWidget(JobaApp(api:api));await tester.pumpAndSettle();
  final dynamic state=tester.state(find.byType(Marketplace));api.session={'access_token':'isolated-token','user':user};state.me=user;state.executor=false;
  state.go('account');await tester.pumpAndSettle();expect(find.text('Мой доступ'),findsOneWidget);expect(find.text('Проверка личности'),findsOneWidget);expect(find.text('Мои услуги и портфолио'),findsNothing);
  state.go('services');await tester.pumpAndSettle();expect(find.text('Вы вошли как заказчик'),findsOneWidget);
  expect(requests.contains('/me/contractor-profile'),false);
  state.go('verification');await tester.pumpAndSettle();expect(find.text('К моим услугам'),findsNothing);
  await tester.tap(find.text('Разместить заказ'));await tester.pumpAndSettle();expect(state.route,'create');
  state.go('access');await tester.pumpAndSettle();expect(find.text('Стандарт'),findsNothing);expect(find.text('Премиум'),findsNothing);expect(find.textContaining('500'),findsWidgets);expect(find.text('Размещайте заказы'),findsOneWidget);expect(find.text('Для заказчика бесплатно'),findsNothing);
  expect(requests.contains('/me/entitlements'),true);expect(requests.contains('/me/subscriptions'),true);
  user['active_role']='executor';state.executor=true;state.go('access');await tester.pumpAndSettle();expect(find.text('Стандарт'),findsOneWidget);expect(find.text('Премиум'),findsOneWidget);expect(find.text('Размещайте заказы'),findsNothing);
  user['roles']=['customer'];user['active_role']='customer';state.me=user;state.executor=false;
  await state.switchRole('executor');await tester.pumpAndSettle();
  expect(state.executor,true);expect(user['roles'],contains('executor'));state.go('services');await tester.pumpAndSettle();expect(find.text('Вы вошли как заказчик'),findsNothing);await state.switchRole('customer');
  state.go('account');await tester.pumpAndSettle();expect(state.executorSetupRequested,false);expect(find.text('Мои услуги и портфолио'),findsNothing);
  await tester.pumpWidget(const SizedBox());api.dispose();
 });
}
