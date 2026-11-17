import 'dart:convert';
import 'widget_test.dart' show MemoryVault;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:services_marketplace/main.dart';
import 'package:services_marketplace/core/api.dart';
import 'package:services_marketplace/screens/marketplace.dart';

void main(){
 testWidgets('unverified customer sees active orders and deletes own open order; executor can open services without document onboarding',(t)async{
  t.view.physicalSize=const Size(393,852);t.view.devicePixelRatio=1;addTearDown(t.view.resetPhysicalSize);addTearDown(t.view.resetDevicePixelRatio);
  var deleted=false;final requests=<String>[];
  final user=<String,dynamic>{'id':'customer','country':'KZ','locale':'ru','active_role':'customer','roles':['customer'],'display_name':'Заказчик','city':'Астана','verification':'not_started','version':1};
  final order={'id':'own-order','owner':'customer','country':'KZ','version':2,'revision':2,'status':'open','title':'Установка новой двери','description':'Нужно установить новую входную дверь в квартире.','city':'Астана','currency':'KZT','budget_amount':null,'upload_ids':[]};
  final api=JobaApi('https://isolated.example',vault:MemoryVault(),transport:MockClient((r)async{
   final path=r.url.path.replaceFirst('/api/v1','');requests.add('${r.method} $path');Object data={'items':[]};
   if(path=='/me')data=user;
   if(path=='/me/overview')data={'orders':{'active':deleted?0:1}};
   if(path=='/me/orders')data={'items':deleted?[]:[order],'meta':{'has_any':!deleted}};
   if(path=='/orders/own-order'){if(r.method=='DELETE'){expect(jsonDecode(r.body)['expected_version'],2);deleted=true;}data={...order,'status':deleted?'deleted':'open'};}
   if(path=='/me/contractor-profile')data={'profile':null,'communication_languages':[]};
   if(path=='/catalog/categories')data={'items':[{'id':'cat','name':'Ремонт','schema':{'properties':{},'required':[]}}]};
   return http.Response(jsonEncode({'data':data,'meta':{}}),200,headers:{'content-type':'application/json; charset=utf-8'});
  }));
  await t.pumpWidget(JobaApp(api:api));await t.pumpAndSettle();
  final dynamic state=t.state(find.byType(Marketplace));api.session={'access_token':'isolated','user':user};state.me=user;state.executor=false;
  state.go('home');await t.pumpAndSettle();expect(find.text('Мои активные заказы'),findsOneWidget);expect(find.text('Установка новой двери'),findsOneWidget);expect(find.text('Рядом с вами'),findsNothing);expect(find.text('Подтвердить личность'),findsNothing);expect(t.takeException(),isNull);
  state.go('account');await t.pumpAndSettle();expect(find.text('Добровольная проверка документов'),findsNothing);
  state.go('order','own-order');await t.pumpAndSettle();await t.scrollUntilVisible(find.text('Удалить заказ'),250,scrollable:find.byType(Scrollable).first);await t.pumpAndSettle();await t.tap(find.text('Удалить заказ'));await t.pumpAndSettle();expect(deleted,true);expect(state.route,'orders');expect(requests.where((r)=>r=='DELETE /orders/own-order').length,1);
  user['roles']=['customer','executor'];user['active_role']='executor';state.me=user;state.executor=true;state.go('services');await t.pumpAndSettle();expect(state.route,'services');expect(find.text('Мои услуги'),findsOneWidget);expect(requests,contains('GET /me/contractor-profile'));expect(requests.any((r)=>r.contains('/me/verification')),false);expect(t.takeException(),isNull);
  await t.pumpWidget(const SizedBox());api.dispose();
 });
}
