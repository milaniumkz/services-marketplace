@TestOn('browser')
library;
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:web/web.dart' as web;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:services_marketplace/advertising/web_ads_web.dart';
import 'package:services_marketplace/core/api.dart';
@JS('JobaWebAds') external set bridge(JSObject value);
http.Response ok(Object value)=>http.Response(jsonEncode({'data':value}),200,headers:{'content-type':'application/json; charset=utf-8'});
void main(){
 testWidgets('ordinary banner loads by default without a consent POST and can be dismissed',(t)async{
  web.window.localStorage.removeItem('joba.web.ads.consent.v1');
  final posts=<String>[];
  final sdk=JSObject();sdk.setProperty('banner'.toJS,((JSString host,JSString block){expect(block.toDart,'R-A-20302217-1');return Future.value(true.toJS).toJS;}).toJS);bridge=sdk;
  final api=JobaApi('https://isolated.example',transport:MockClient((r)async{
   if(r.method=='POST')posts.add(r.url.path);
   return ok({'enabled':true,'rewarded_enabled':false,'banner_id':'R-A-20302217-1','consent':false,'consent_recorded':false});
  }))..session={'access_token':'isolated','user':{'id':'user'}};
  await t.pumpWidget(MaterialApp(home:Scaffold(body:SingleChildScrollView(child:WebAdsPanel(api:api,onReward:(){})))));await t.pumpAndSettle();await t.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:80)));await t.pumpAndSettle();expect(find.byType(HtmlElementView),findsOneWidget);expect(web.window.localStorage.getItem('joba.web.ads.consent.v1'),isNull);expect(find.text('Разрешить рекламные показы'),findsNothing);expect(posts,isEmpty);
  await t.tap(find.byTooltip('Скрыть баннер'));await t.pumpAndSettle();expect(find.byType(HtmlElementView),findsNothing);expect(posts,isEmpty);
  await t.pumpWidget(const SizedBox());api.dispose();
 });
 testWidgets('a previously recorded opt-out is retained without prompting or starting the SDK',(t)async{
  var banners=0;final sdk=JSObject();sdk.setProperty('banner'.toJS,((JSString h,JSString b){banners++;return Future.value(true.toJS).toJS;}).toJS);bridge=sdk;
  final api=JobaApi('https://isolated.example',transport:MockClient((r)async=>ok({'enabled':true,'banner_id':'R-A-20302217-1','consent':false,'consent_recorded':true})))..session={'access_token':'isolated','user':{'id':'user'}};
  await t.pumpWidget(MaterialApp(home:Scaffold(body:WebAdsPanel(api:api,onReward:(){})))) ;await t.pumpAndSettle();expect(banners,0);expect(find.text('Разрешить рекламные показы'),findsNothing);await t.pumpWidget(const SizedBox());api.dispose();
 });
 for(final completed in [false,true])testWidgets('web Rewarded submits only the actual SDK callback: $completed',(t)async{
  final completion=Completer<JSBoolean>(),outcomes=<Map<String,dynamic>>[];
  final sdk=JSObject();sdk.setProperty('platform'.toJS,(()=>Future.value('touch'.toJS).toJS).toJS);
  sdk.setProperty('rewarded'.toJS,((JSString block,JSString platform){expect(block.toDart,'R-A-20302217-2');expect(platform.toDart,'touch');return completion.future.toJS;}).toJS);bridge=sdk;
  final api=JobaApi('https://isolated.example',transport:MockClient((r)async{
   if(r.method=='GET')return ok({'enabled':true,'rewarded_enabled':true,'consent':true,'verification_status':'passed','offers':[{'target':'customer','title':'Подписка заказчика','required_views':5,'completed_views':0,'duration_days':30,'eligible':true}]});
   if(r.url.path.endsWith('/outcome')){outcomes.add(Map<String,dynamic>.from(jsonDecode(r.body)));return ok({'status':completed?'progress':'not_completed','completed_views':1,'required_views':5});}
   return ok({'id':'session','nonce':'session-nonce','block_id':'R-A-20302217-2','reward_seconds':3600});
  }))..session={'access_token':'isolated','user':{'id':'user'}};
  await t.pumpWidget(MaterialApp(home:Scaffold(body:WebRewardScreen(api:api))));await t.pumpAndSettle();
  await t.ensureVisible(find.text('Согласен, посмотреть ролик'));await t.tap(find.text('Согласен, посмотреть ролик'));await t.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:80)));await t.pumpAndSettle();expect(outcomes,isEmpty);
  completion.complete(completed.toJS);await t.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:80)));await t.pumpAndSettle();expect(outcomes.single,{'nonce':'session-nonce','completed':completed});
  expect(find.textContaining(completed?'Засчитано просмотров: 1 из 5':'Прогресс не изменился'),findsOneWidget);
  await t.pumpWidget(const SizedBox());api.dispose();
 });
 testWidgets('unknown confirmation outcome retries the same receipt without another ad view',(t)async{
  var played=0,reported=0;final keys=<String?>[];final completion=Completer<JSBoolean>();
  final sdk=JSObject();sdk.setProperty('platform'.toJS,(()=>Future.value('desktop'.toJS).toJS).toJS);sdk.setProperty('rewarded'.toJS,((JSString block,JSString platform){played++;return completion.future.toJS;}).toJS);bridge=sdk;
  final api=JobaApi('https://isolated.example',transport:MockClient((r)async{
   if(r.method=='GET')return ok({'enabled':true,'rewarded_enabled':true,'consent':true,'verification_status':'passed','offers':[{'target':'customer','title':'Подписка заказчика','required_views':5,'completed_views':0,'duration_days':30,'eligible':true}]});
   if(r.url.path.endsWith('/outcome')){keys.add(r.headers['Idempotency-Key']);reported++;if(reported==1)throw http.ClientException('isolated offline');return ok({'status':'granted'});}
   return ok({'id':'pending-session','nonce':'pending-nonce','block_id':'R-A-20302217-3','reward_seconds':3600});
  }))..session={'access_token':'isolated','user':{'id':'user'}};
  await t.pumpWidget(MaterialApp(home:Scaffold(body:WebRewardScreen(api:api))));await t.pumpAndSettle();await t.ensureVisible(find.text('Согласен, посмотреть ролик'));await t.tap(find.text('Согласен, посмотреть ролик'));await t.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:100)));await t.pumpAndSettle();
  expect(played,1);completion.complete(true.toJS);await t.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:100)));await t.pumpAndSettle();await t.ensureVisible(find.text('Повторить подтверждение просмотра'));await t.tap(find.text('Повторить подтверждение просмотра'));await t.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:100)));await t.pumpAndSettle();expect(played,1);expect(reported,2);expect(keys.first,isNotNull);expect(keys[0],keys[1]);expect(find.textContaining('Подписка активирована на 30 дней'),findsOneWidget);await t.pumpWidget(const SizedBox());api.dispose();
 });

}
