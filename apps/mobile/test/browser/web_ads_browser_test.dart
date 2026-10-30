@TestOn('browser')
library;
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:services_marketplace/advertising/web_ads_web.dart';
import 'package:services_marketplace/core/api.dart';
@JS('JobaWebAds') external set bridge(JSObject value);
http.Response ok(Object value)=>http.Response(jsonEncode({'data':value}),200,headers:{'content-type':'application/json; charset=utf-8'});
void main(){
 testWidgets('web ad panel asks for consent before rendering and revokes consent without granting paid access',(t)async{
  var accepted=false,banners=0;final posts=<String>[];
  final sdk=JSObject();sdk.setProperty('banner'.toJS,((JSString host,JSString block){banners++;expect(block.toDart,'R-A-20302217-1');return Future.value(true.toJS).toJS;}).toJS);bridge=sdk;
  final api=JobaApi('https://isolated.example',transport:MockClient((r)async{
   if(r.method=='POST'){posts.add(r.url.path);accepted=jsonDecode(r.body)['accepted'];return ok({'accepted':accepted});}
   return ok({'enabled':true,'rewarded_enabled':false,'banner_id':'R-A-20302217-1','consent':accepted,'server_time':DateTime.now().toUtc().toIso8601String(),'ad_free_until':null});
  }))..session={'access_token':'isolated','user':{'id':'user'}};
  await t.pumpWidget(MaterialApp(home:Scaffold(body:SingleChildScrollView(child:WebAdsPanel(api:api,onReward:(){})))));await t.pumpAndSettle();expect(banners,0);
  await t.tap(find.text('Разрешить рекламные показы'));await t.pumpAndSettle();await t.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:80)));await t.pumpAndSettle();expect(find.byType(HtmlElementView),findsOneWidget);expect(accepted,true);
  await t.tap(find.text('Отключить рекламные показы'));await t.pumpAndSettle();expect(accepted,false);expect(find.byType(HtmlElementView),findsNothing);expect(posts.every((p)=>p.endsWith('/consent')),true);
  await t.pumpWidget(const SizedBox());api.dispose();
 });
 for(final completed in [false,true])testWidgets('web Rewarded submits only the actual SDK callback: $completed',(t)async{
  final completion=Completer<JSBoolean>(),outcomes=<Map<String,dynamic>>[];
  final sdk=JSObject();sdk.setProperty('platform'.toJS,(()=>Future.value('touch'.toJS).toJS).toJS);
  sdk.setProperty('rewarded'.toJS,((JSString block,JSString platform){expect(block.toDart,'R-A-20302217-2');expect(platform.toDart,'touch');return completion.future.toJS;}).toJS);bridge=sdk;
  final api=JobaApi('https://isolated.example',transport:MockClient((r)async{
   if(r.method=='GET')return ok({'enabled':true,'rewarded_enabled':true,'reward_seconds':3600,'consent':true});
   if(r.url.path.endsWith('/outcome')){outcomes.add(Map<String,dynamic>.from(jsonDecode(r.body)));return ok({'status':completed?'granted':'not_completed'});}
   return ok({'id':'session','nonce':'session-nonce','block_id':'R-A-20302217-2','reward_seconds':3600});
  }))..session={'access_token':'isolated','user':{'id':'user'}};
  await t.pumpWidget(MaterialApp(home:Scaffold(body:WebRewardScreen(api:api))));await t.pumpAndSettle();
  await t.ensureVisible(find.text('Согласен, посмотреть рекламу'));await t.tap(find.text('Согласен, посмотреть рекламу'));await t.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:80)));await t.pumpAndSettle();expect(outcomes,isEmpty);
  completion.complete(completed.toJS);await t.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:80)));await t.pumpAndSettle();expect(outcomes.single,{'nonce':'session-nonce','completed':completed});
  expect(find.textContaining(completed?'Баннеры отключены':'Награда не начислена'),findsOneWidget);
  await t.pumpWidget(const SizedBox());api.dispose();
 });
 testWidgets('unknown confirmation outcome retries the same receipt without another ad view',(t)async{
  var played=0,reported=0;final keys=<String?>[];final completion=Completer<JSBoolean>();
  final sdk=JSObject();sdk.setProperty('platform'.toJS,(()=>Future.value('desktop'.toJS).toJS).toJS);sdk.setProperty('rewarded'.toJS,((JSString block,JSString platform){played++;return completion.future.toJS;}).toJS);bridge=sdk;
  final api=JobaApi('https://isolated.example',transport:MockClient((r)async{
   if(r.method=='GET')return ok({'enabled':true,'rewarded_enabled':true,'reward_seconds':3600,'consent':true});
   if(r.url.path.endsWith('/outcome')){keys.add(r.headers['Idempotency-Key']);reported++;if(reported==1)throw http.ClientException('isolated offline');return ok({'status':'granted'});}
   return ok({'id':'pending-session','nonce':'pending-nonce','block_id':'R-A-20302217-3','reward_seconds':3600});
  }))..session={'access_token':'isolated','user':{'id':'user'}};
  await t.pumpWidget(MaterialApp(home:Scaffold(body:WebRewardScreen(api:api))));await t.pumpAndSettle();await t.ensureVisible(find.text('Согласен, посмотреть рекламу'));await t.tap(find.text('Согласен, посмотреть рекламу'));await t.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:100)));await t.pumpAndSettle();
  expect(played,1);completion.complete(true.toJS);await t.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:100)));await t.pumpAndSettle();await t.ensureVisible(find.text('Повторить подтверждение просмотра'));await t.tap(find.text('Повторить подтверждение просмотра'));await t.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:100)));await t.pumpAndSettle();expect(played,1);expect(reported,2);expect(keys.first,isNotNull);expect(keys[0],keys[1]);expect(find.textContaining('Баннеры отключены'),findsOneWidget);await t.pumpWidget(const SizedBox());api.dispose();
 });

}
