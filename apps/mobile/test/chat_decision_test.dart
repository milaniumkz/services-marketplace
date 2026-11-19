import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:services_marketplace/main.dart';
import 'package:services_marketplace/core/api.dart';
import 'package:services_marketplace/core/design_widgets.dart';
import 'package:services_marketplace/screens/marketplace.dart';
import 'widget_test.dart' show MemoryVault;
void main(){
 for(final accept in [false,true])testWidgets('chat header ${accept?'accepts with consent':'declines'} actual offer and leaves chat',(t)async{
  final user={'id':'customer','country':'KZ','locale':'ru','roles':['customer'],'active_role':'customer','verification':'passed','display_name':'Заказчик','city':'Алматы','version':1};Json? sent;
  final api=JobaApi('https://isolated.example',vault:MemoryVault(),transport:MockClient((r)async{
   final path=r.url.path.replaceFirst('/api/v1','');if(r.method=='POST'&&(path.endsWith('/select')||path.endsWith('/decline')))sent=jsonDecode(r.body);
   final dynamic data=path=='/me'?user:path=='/conversations/thread'?{'id':'thread','status':'open','peer':{'id':'worker','display_name':'Мастер'},'order_id':'order','order_title':'Побелить стены','order_amount':50000000,'currency':'KZT','can_decide':true,'blocked':false,'order_version':4,'offer_id':'off','offer_version':2}:path=='/orders/order'?{'id':'order','owner':'customer','title':'Побелить стены','description':'Описание заказа','city':'Алматы','status':'assigned','version':5,'currency':'KZT','upload_ids':[]}:path=='/me/unread-counts'?{'messages':0,'notifications':0}:{'items':[]};
   return http.Response(jsonEncode({'data':data}),200,headers:{'content-type':'application/json; charset=utf-8'});
  }));addTearDown(api.dispose);
  await t.pumpWidget(JobaApp(api:api));await t.pumpAndSettle();api.session={'access_token':'fixture','user':user};final dynamic state=t.state(find.byType(Marketplace));state.me=user;state.go('chat','thread');await t.pumpAndSettle();expect(find.text('Побелить стены'),findsOneWidget);expect(find.text('Принять исполнителя'),findsOneWidget);expect(find.text('Отказать'),findsOneWidget);
  await t.tap(find.text(accept?'Принять исполнителя':'Отказать'));await t.pumpAndSettle();
  if(accept){final button=find.descendant(of:find.byType(AlertDialog),matching:find.widgetWithText(FilledButton,'Принять исполнителя'));expect(t.widget<FilledButton>(button).onPressed,isNull);await t.tap(find.byType(CheckboxListTile));await t.pumpAndSettle();await t.tap(button);await t.pumpAndSettle();expect(sent!['expected_version'],4);expect(sent!['offer_version'],2);expect(sent!['contact_consent'],true);expect(state.route,'order');}else{expect(sent!['expected_version'],2);expect(sent!['order_version'],4);expect(state.route,'messages');}
  expect(find.byType(JobaNavigation),findsOneWidget);
 });
 testWidgets('closed chat shows readable history without message composer',(t)async{
  final user={'id':'customer','country':'KZ','locale':'ru','roles':['customer'],'active_role':'customer','verification':'passed','display_name':'Заказчик','city':'Алматы','version':1};var read=0;
  final api=JobaApi('https://isolated.example',vault:MemoryVault(),transport:MockClient((r)async{final path=r.url.path.replaceFirst('/api/v1','');if(path.endsWith('/read'))read=jsonDecode(r.body)['sequence'];final dynamic data=path=='/me'?user:path=='/conversations/thread'?{'id':'thread','status':'closed','peer':{'id':'worker','display_name':'Мастер'},'order_id':'order','order_title':'Побелить стены','blocked':true,'blocked_reason':'conversation_closed'}:path.endsWith('/messages')?{'items':[{'id':'msg','owner':'worker','sequence':1,'text':'Старая переписка','created_at':'2026-10-28T10:00:00Z'}]}:{'items':[]};return http.Response(jsonEncode({'data':data}),200,headers:{'content-type':'application/json; charset=utf-8'});}));addTearDown(api.dispose);
  await t.pumpWidget(JobaApp(api:api));await t.pumpAndSettle();api.session={'access_token':'fixture','user':user};final dynamic state=t.state(find.byType(Marketplace));state.me=user;state.go('chat','thread');await t.pumpAndSettle();expect(find.text('Старая переписка'),findsOneWidget);expect(find.byType(TextField),findsNothing);expect(read,1);expect(find.byType(JobaNavigation),findsOneWidget);
 });
}
