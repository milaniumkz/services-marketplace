import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:services_marketplace/core/api.dart';
import 'package:services_marketplace/core/design_widgets.dart';
import 'package:services_marketplace/main.dart';
import 'package:services_marketplace/screens/marketplace.dart';
import 'widget_test.dart' show MemoryVault, ok;

void main(){
 testWidgets('order tabs preserve unsaved input, committed preview and publication return to orders rather than the form', (t) async {
  t.view.physicalSize=const Size(390,844);t.view.devicePixelRatio=1;
  addTearDown(t.view.resetPhysicalSize);addTearDown(t.view.resetDevicePixelRatio);addTearDown(t.view.resetViewInsets);
  final user={'id':'customer','country':'KZ','locale':'ru','active_role':'customer','roles':['customer'],'display_name':'Заказчик','city':'Караганда','verification':'passed','version':1};
  final values=<String,String>{'category_id':'cat','city_id':'city','title':'Покрасить стены квартиры','description':'Нужно покрасить стены в двух комнатах, материалы куплены.','work_mode':'onsite','budget':'5000'};
  var status='draft',created=0;
  final gate=Completer<void>();
  Json order()=>{'id':'order','owner':'customer','status':status,'version':1,'title':values['title'],'description':values['description'],'city':'Караганда','currency':'KZT','budget_amount':500000,'upload_ids':[]};
  final api=JobaApi('https://isolated.example',vault:MemoryVault(),transport:MockClient((r) async{
   final path=r.url.path.replaceFirst('/api/v1','');
   if(path=='/me')return ok(user);
   if(path=='/me/overview')return ok({'orders':{}});
   if(path=='/catalog/categories')return ok({'items':[{'id':'cat','name':'Ремонт','schema':{'properties':{},'required':[]}}]});
   if(path=='/geo/cities')return ok({'items':[{'id':'city','name':'Караганда'}]});
   if(path=='/orders'&&r.method=='POST'){created++;expect(jsonDecode(r.body)['title'],values['title']);return ok(order());}
   if(path=='/orders/order/publish'){await gate.future;status='open';return ok(order());}
   if(path=='/orders/order')return ok(order());
   if(path=='/me/orders')return ok({'items':created>0?[order()]:[],'meta':{'has_any':true}});
   return ok({'items':[]});
  }));addTearDown(api.dispose);
  await t.pumpWidget(JobaApp(api:api));await t.pumpAndSettle();
  api.session={'access_token':'token','user':user};final dynamic state=t.state(find.byType(Marketplace));state.me=user;
  state.ensureOrderFormsScope();state.newOrderValues.addAll(values);state.draftCategory='cat';
  state.go('create');await t.pumpAndSettle();
  expect(find.byType(JobaNavigation),findsOneWidget);
  await t.enterText(find.widgetWithText(TextFormField,values['title']!),'Покрасить стены кухни');values['title']='Покрасить стены кухни';await t.pump();
  expect(state.newOrderValues['title'],values['title']);
  t.view.viewInsets=const FakeViewPadding(bottom:300);await t.pumpAndSettle();
  expect(t.getBottomLeft(find.byType(JobaNavigation)).dy,lessThanOrEqualTo(544));
  t.view.resetViewInsets();await t.pumpAndSettle();
  await t.tap(find.descendant(of:find.byType(JobaNavigation),matching:find.text('Профиль')));await t.pumpAndSettle();
  expect(state.route,'account');expect(state.history.any((entry)=>entry.$1=='create'),false);
  state.go('create');await t.pumpAndSettle();
  expect(find.text(values['title']!),findsOneWidget);
  await t.ensureVisible(find.text('Предпросмотр заказа'));await t.tap(find.text('Предпросмотр заказа'));await t.pumpAndSettle();
  expect(state.route,'publish');expect(created,1);expect(state.newOrderValues,isEmpty);expect(find.byType(JobaNavigation),findsOneWidget);
  state.back();await t.pumpAndSettle();expect(state.route,'orders');expect(state.ordersBucket,'drafts');
  state.go('publish','order');await t.pumpAndSettle();
  await t.tap(find.text('Опубликовать заказ'));await t.pump();
  state.selectMainTab('account');state.back();expect(state.route,'publish');
  gate.complete();await t.pumpAndSettle();
  expect(state.route,'published');expect(state.ordersBucket,'active');expect(find.byType(JobaNavigation),findsOneWidget);
  state.back();await t.pumpAndSettle();expect(state.route,'orders');
  expect(state.history.any((entry)=>['create','publish','edit-order'].contains(entry.$1)),false);
  state.go('edit-order','order');await t.pumpAndSettle();
  await t.enterText(find.widgetWithText(TextFormField,values['title']!),'Изменённый текст заказа');await t.pump();
  await t.tap(find.descendant(of:find.byType(JobaNavigation),matching:find.text('Профиль')));await t.pumpAndSettle();
  state.go('edit-order','order');await t.pumpAndSettle();expect(find.text('Изменённый текст заказа'),findsOneWidget);
  state.selectMainTab('account');await t.pumpAndSettle();state.back();await t.pumpAndSettle();expect(state.route,'home');
  state.selectMainTab('account');await t.pumpAndSettle();state.go('create');await t.pumpAndSettle();
  expect(find.text(values['title']!),findsNothing);
  state.go('checkout');await t.pumpAndSettle();state.go('test-payment-success','subscription');await t.pumpAndSettle();
  expect(find.byType(JobaNavigation),findsOneWidget);state.back();await t.pumpAndSettle();expect(state.route,'my-access');
  expect(state.history.any((entry)=>entry.$1=='checkout'),false);
  await api.forget();await t.pumpAndSettle();expect(state.newOrderValues,isEmpty);expect(state.editedOrderValues,isEmpty);
 });
}
