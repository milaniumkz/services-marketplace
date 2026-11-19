import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:services_marketplace/core/api.dart';
import 'package:services_marketplace/screens/nearby_contractors.dart';
import 'widget_test.dart' show MemoryVault;
void main(){
 testWidgets('nearby uses precise GPS and 20 km without city fallback',(t)async{
  Uri? sent;final api=JobaApi('https://isolated.example',vault:MemoryVault(),transport:MockClient((r)async{sent=r.url;return http.Response(jsonEncode({'data':{'items':[{'id':'near','title':'Мастер рядом'}]}}),200,headers:{'content-type':'application/json; charset=utf-8'});}))..session={'access_token':'token','user':{'id':'owner','city':'Караганда'}};addTearDown(api.dispose);
  await t.pumpWidget(MaterialApp(home:Scaffold(body:NearbyContractors(api:api,locate:()async=>{'latitude':49.812345,'longitude':73.123456},itemBuilder:(r)=>Text(r['title']),onAccess:(){},onVerification:(){}))));await t.pumpAndSettle();
  expect(sent!.queryParameters['radius_km'],'20');expect(sent!.queryParameters['near_lat'],'49.812345');expect(sent!.queryParameters['near_lon'],'73.123456');expect(sent!.queryParameters.containsKey('city'),false);expect(find.text('Мастер рядом'),findsOneWidget);
 });
 testWidgets('denied GPS never requests distant fallback and retry is available',(t)async{
  var denied=true,calls=0;final api=JobaApi('https://isolated.example',vault:MemoryVault(),transport:MockClient((r)async{calls++;return http.Response('{"data":{"items":[]}}',200);}))..session={'access_token':'token','user':{'id':'owner'}};addTearDown(api.dispose);
  await t.pumpWidget(MaterialApp(home:Scaffold(body:NearbyContractors(api:api,locate:()async{if(denied)throw ApiException('GPS_DENIED','denied');return {'latitude':49.8,'longitude':73.1};},itemBuilder:(r)=>Text(r['title']),onAccess:(){},onVerification:(){}))));await t.pumpAndSettle();expect(calls,0);expect(find.text('Определить местоположение'),findsOneWidget);
  denied=false;await t.tap(find.text('Определить местоположение'));await t.pumpAndSettle();expect(calls,1);expect(find.text('В радиусе 20 км пока нет исполнителей.'),findsOneWidget);
 });
}
