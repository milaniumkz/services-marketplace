import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:services_marketplace/core/api.dart';
import 'package:services_marketplace/screens/bank_payment.dart';
import 'package:services_marketplace/screens/commerce_states.dart';
import 'widget_test.dart' show MemoryVault, ok;

void main() {
  for(final provider in ['vtb','bcc'])testWidgets('hosted $provider checkout sends accepted server quote without disconnected SDK purchase', (t) async {
    Json? purchase;
    final offer={'id':'server-quote','plan':'customer','role':'customer','provider':provider,'hosted_checkout':true,'bank_test':true,'product_type':'subscription','period':'days','duration_days':30,'amount_minor':50000,'currency':'KZT','is_test':false};
    final api=JobaApi('https://isolated.example',vault:MemoryVault(),transport:MockClient((r) async {
      if(r.url.path.endsWith('/billing/vtb/pending'))return ok({'items':[]});
      if(r.url.path.endsWith('/billing/offers'))return ok({'items':[offer]});
      if(r.url.path.endsWith('/billing/$provider/checkout')){purchase=jsonDecode(r.body);return ok({'id':'own-payment','status':'pending'});}
      fail('Unexpected request: ${r.url.path}');
    }));
    addTearDown(api.dispose);api.session={'access_token':'isolated','user':{'id':'customer','active_role':'customer'}};
    String? route,id;
    await t.pumpWidget(MaterialApp(home:Scaffold(body:CommerceStateScreen(api:api,mode:'checkout',onGo:(r,v){route=r;id=v;}))));await t.pumpAndSettle();
    expect(purchase,isNull);if(provider=='bcc'){await t.scrollUntilVisible(find.byType(TextField),200,scrollable:find.byType(Scrollable).first);await t.enterText(find.byType(TextField),'Алматы, Тестовая, 12');await t.pumpAndSettle();}await t.scrollUntilVisible(find.byType(CheckboxListTile),200,scrollable:find.byType(Scrollable).first);await t.tap(find.byType(CheckboxListTile));await t.pumpAndSettle();await t.ensureVisible(find.text('Продолжить оплату'));await t.tap(find.text('Продолжить оплату'));await t.pumpAndSettle();
    expect(purchase,{'offer_id':'server-quote','amount_minor':50000,'currency':'KZT','accepted':true,if(provider=='bcc')'billing_address':'Алматы, Тестовая, 12'});expect(route,'bank-payment-open');expect(id,'own-payment');
  });
  testWidgets('bank return polls authenticated proof and cancellation never grants a subscription', (t) async {
    var status='pending',canceled=false;
    final api=JobaApi('https://isolated.example',vault:MemoryVault(),transport:MockClient((r) async {
      expect(r.headers['Authorization'],'Bearer isolated');
      if(r.url.path.endsWith('/cancel')){expect(r.method,'POST');canceled=true;status='canceled';}
      return ok({'id':'own-payment','status':status,'title':'Стандарт','amount_minor':50000,'currency':'KZT','bank_test':true,'can_cancel':status=='pending','benefit':'subscription'});
    }));
    addTearDown(api.dispose);api.session={'access_token':'isolated','user':{'id':'customer'}};
    await t.pumpWidget(MaterialApp(home:Scaffold(body:BankPaymentScreen(api:api,id:'own-payment',onGo:(_,__){}))));await t.pumpAndSettle();
    expect(find.text('Оплата подтверждена'),findsNothing);await t.ensureVisible(find.text('Отменить неоплаченный заказ'));await t.tap(find.text('Отменить неоплаченный заказ'));await t.pumpAndSettle();expect(canceled,true);expect(find.text('Оплата отменена'),findsOneWidget);expect(find.text('Оплата подтверждена'),findsNothing);
    await t.pumpWidget(const SizedBox.shrink());
  });
}
