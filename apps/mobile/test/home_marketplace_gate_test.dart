import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:services_marketplace/core/api.dart';
import 'package:services_marketplace/screens/home_marketplace_gate.dart';
void main(){
 for(final mode in ['unverified','unsubscribed','customer','executor','wrong-role','expired'])testWidgets('home access preflight: $mode',(t)async{
  final calls=<String>[];var mountedPrivate=false;
  final grant={'role':mode=='executor'?'executor':'customer','plan':mode=='executor'?'standard':'customer','capabilities':mode=='executor'?['search_full']:['view_contractors'],'valid_until':DateTime.now().toUtc().add(Duration(days:mode=='expired'?-1:1)).toIso8601String()};
  final api=JobaApi('https://isolated.example',transport:MockClient((r)async{final path=r.url.path.replaceFirst('/api/v1','');calls.add(path);return http.Response(jsonEncode({'data':path=='/me'?{'verification':mode=='unverified'?'not_started':'passed'}:{'items':mode=='unsubscribed'?[]:[grant]}}),200,headers:{'content-type':'application/json; charset=utf-8'});}))..session={'access_token':'isolated','user':{'id':'user'}};
  await t.pumpWidget(MaterialApp(home:Scaffold(body:HomeMarketplaceGate(api:api,executor:mode=='executor'||mode=='wrong-role',onAccess:(){},onVerification:(){},content:(){mountedPrivate=true;return const Text('Закрытый список');}))));await t.pumpAndSettle();
  expect(mountedPrivate,mode=='customer'||mode=='executor');expect(calls,mode=='unverified'?['/me']:['/me','/me/entitlements']);
  if(mode=='unverified')expect(find.text('Подтвердить личность'),findsOneWidget);
  if(['unsubscribed','wrong-role','expired'].contains(mode))expect(find.text('Мой доступ'),findsOneWidget);
  await t.pumpWidget(const SizedBox());api.dispose();
 });
}
