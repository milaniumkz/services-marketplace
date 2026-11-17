import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:services_marketplace/core/api.dart';
import 'package:services_marketplace/screens/presence_status.dart';
void main(){testWidgets('real server status refreshes online/offline; failures become unknown rather than stale online',(t)async{
 bool online=true,fail=false;final api=JobaApi('https://isolated.example',transport:MockClient((r)async{expect(r.url.path,'/api/v1/users/person/presence');return fail?http.Response('{}',503):http.Response(jsonEncode({'data':{'online':online}}),200,headers:{'content-type':'application/json'});}))..session={'access_token':'isolated'};
 await t.pumpWidget(MaterialApp(home:Scaffold(body:PresenceStatus(api:api,userId:'person'))));await t.pumpAndSettle();expect(find.text('Онлайн'),findsOneWidget);expect(t.widget<Icon>(find.byIcon(Icons.circle)).color,const Color(0xFF21A566));online=false;await t.pump(const Duration(seconds:10));await t.pumpAndSettle();expect(find.text('Не в сети'),findsOneWidget);expect(t.widget<Icon>(find.byIcon(Icons.circle)).color,const Color(0xFFCB5361));fail=true;await t.pump(const Duration(seconds:10));await t.pumpAndSettle();expect(find.text('Статус уточняется'),findsOneWidget);expect(find.text('Онлайн'),findsNothing);await t.pumpWidget(const SizedBox());api.dispose();
});}
