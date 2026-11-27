import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:services_marketplace/core/api.dart';
import 'package:services_marketplace/screens/bank_payment.dart';
import 'package:services_marketplace/screens/commerce_states.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';
import 'bank_form_test.dart' show TestPlatform;
import 'widget_test.dart' show MemoryVault, ok;

void main() {
  for(final provider in ['vtb','bcc'])testWidgets('hosted $provider checkout sends accepted server quote without disconnected SDK purchase', (t) async {
    Json? purchase;var proofReads=0;WebViewPlatform.instance=TestPlatform();
    final offer={'id':'server-quote','plan':'customer','role':'customer','provider':provider,'hosted_checkout':true,'bank_test':true,'product_type':'subscription','period':'days','duration_days':30,'amount_minor':50000,'currency':'KZT','is_test':false};
    final api=JobaApi('https://isolated.example',vault:MemoryVault(),transport:MockClient((r) async {
      if(r.url.path.endsWith('/billing/vtb/pending'))return ok({'items':[]});
      if(r.url.path.endsWith('/billing/offers'))return ok({'items':[offer]});
      if(r.url.path.endsWith('/billing/$provider/checkout')){purchase=jsonDecode(r.body);return ok({'id':'00000000-0000-4000-8000-000000000001','provider':provider,'status':'pending','payment_url':provider=='bcc'?'https://joba.com.kz/api/v1/public/billing/bcc/form?payment_id=00000000-0000-4000-8000-000000000001&token=${'a'*64}':'https://vtbkz.rbsuat.com/payment/merchants/ecom/payment.html?mdOrder=synthetic'});}
      if(r.url.path.contains('/payments/')){proofReads++;return ok({'status':'pending'});}
      fail('Unexpected request: ${r.url.path}');
    }));
    addTearDown(api.dispose);api.session={'access_token':'isolated','user':{'id':'customer','active_role':'customer'}};
    String? route;
    await t.pumpWidget(MaterialApp(home:Scaffold(body:CommerceStateScreen(api:api,mode:'checkout',onGo:(r,v){route=r;}))));await t.pumpAndSettle();
    expect(purchase,isNull);await t.scrollUntilVisible(find.byType(CheckboxListTile),200,scrollable:find.byType(Scrollable).first);await t.tap(find.byType(CheckboxListTile));await t.pumpAndSettle();await t.ensureVisible(find.text('Продолжить оплату'));await t.tap(find.text('Продолжить оплату'));await t.pumpAndSettle();
    expect(purchase,{'offer_id':'server-quote','amount_minor':50000,'currency':'KZT','accepted':true});expect(route,isNull);expect(proofReads,0);expect(find.text('Bank-owned web content'),findsOneWidget);expect(find.text('Отменить неоплаченный заказ'),findsNothing);await t.tap(find.byTooltip('Вернуться к оплате'));await t.pumpAndSettle();expect(route,'my-access');expect(proofReads,1);
  });
  testWidgets('bank return polls authenticated proof and cancellation never grants a subscription', (t) async {
    var status='pending',canceled=false;String? next;
    final api=JobaApi('https://isolated.example',vault:MemoryVault(),transport:MockClient((r) async {
      expect(r.headers['Authorization'],'Bearer isolated');
      if(r.url.path.endsWith('/cancel')){expect(r.method,'POST');canceled=true;status='canceled';}
      return ok({'id':'own-payment','status':status,'title':'Стандарт','amount_minor':50000,'currency':'KZT','bank_test':true,'can_cancel':status=='pending','can_retry':status=='canceled','benefit':'subscription'});
    }));
    addTearDown(api.dispose);api.session={'access_token':'isolated','user':{'id':'customer'}};
    await t.pumpWidget(MaterialApp(home:Scaffold(body:BankPaymentScreen(api:api,id:'own-payment',onGo:(r,_)=>next=r))));await t.pumpAndSettle();
    expect(find.text('Оплата подтверждена'),findsNothing);await t.ensureVisible(find.text('Отменить неоплаченный заказ'));await t.tap(find.text('Отменить неоплаченный заказ'));await t.pumpAndSettle();expect(canceled,true);expect(find.text('Оплата отменена'),findsOneWidget);expect(find.text('Оплата подтверждена'),findsNothing);
    await t.ensureVisible(find.text('Повторить оплату'));await t.tap(find.text('Повторить оплату'));expect(next,'checkout');
    await t.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('a cancellation requested during a background poll is serialized and not lost', (t) async {
    final waiting=Completer<Json>();var reads=0,cancels=0;
    Json result()=>{'id':'own-payment','provider':'bcc','status':cancels>0?'canceled':'pending','amount_minor':50000,'currency':'KZT','can_cancel':cancels==0,'can_retry':cancels>0};
    final api=JobaApi('https://isolated.example',vault:MemoryVault(),transport:MockClient((r)async{
      if(r.method=='POST'){cancels++;return ok(result());}
      reads++;if(reads==2)return ok(await waiting.future);return ok(result());
    }));addTearDown(api.dispose);api.session={'access_token':'isolated','user':{'id':'customer'}};
    await t.pumpWidget(MaterialApp(home:Scaffold(body:BankPaymentScreen(api:api,id:'own-payment',onGo:(_,__){}))));await t.pumpAndSettle();
    final cancel=t.widget<TextButton>(find.widgetWithText(TextButton,'Отменить неоплаченный заказ')).onPressed!;
    await t.pump(const Duration(seconds:5));expect(reads,2);cancel();expect(cancels,0);
    waiting.complete(result());await t.pumpAndSettle();expect(cancels,1);expect(find.text('Оплата отменена'),findsOneWidget);expect(find.text('Повторить оплату'),findsOneWidget);
  });

}
