import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:services_marketplace/core/api.dart';
import 'package:services_marketplace/core/verified_badge.dart';
import 'package:services_marketplace/screens/online_counter.dart';
void main(){
 testWidgets('online uses server count, refreshes and clears stale number on failure',(t)async{
  var count=7,failed=false;final api=JobaApi('https://isolated.example',transport:MockClient((r)async=>failed?http.Response('unavailable',503):http.Response(jsonEncode({'data':{'count':count}}),200,headers:{'content-type':'application/json'})));
  await t.pumpWidget(MaterialApp(home:Scaffold(body:OnlineCounter(api:api))));await t.pumpAndSettle();expect(find.text('Сейчас онлайн: 7'),findsOneWidget);count=3;await t.pump(const Duration(seconds:15));await t.pumpAndSettle();expect(find.text('Сейчас онлайн: 3'),findsOneWidget);failed=true;await t.pump(const Duration(seconds:15));await t.pumpAndSettle();expect(find.text('Онлайн: уточняем…'),findsOneWidget);expect(find.text('Сейчас онлайн: 3'),findsNothing);await t.pumpWidget(const SizedBox());api.dispose();
 });
 testWidgets('verification badge is a blue verified check with accessible meaning',(t)async{await t.pumpWidget(const MaterialApp(home:Scaffold(body:VerifiedBadge())));final icon=t.widget<Icon>(find.byIcon(Icons.verified));expect(icon.color,const Color(0xFF1D9BF0));expect(find.byTooltip('Верифицирован'),findsOneWidget);});
}
