import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:services_marketplace/main.dart';
import 'package:services_marketplace/core/api.dart';
import 'package:services_marketplace/screens/marketplace.dart';
import 'widget_test.dart' show MemoryVault;
void main(){
 for(final executor in [false,true])testWidgets('${executor?'executor':'customer'} access errors open purchase page without an error dialog',(t)async{
  final user={'id':'owner','country':'KZ','locale':'ru','roles':[executor?'executor':'customer'],'active_role':executor?'executor':'customer','verification':'passed','display_name':'Пользователь','city':'Караганда','version':1};
  final api=JobaApi('https://isolated.example',vault:MemoryVault(),transport:MockClient((r)async{
   final path=r.url.path.replaceFirst('/api/v1','');
   if(['/orders','/contractors','/restricted-command'].contains(path))return http.Response('{"error":{"code":"ENTITLEMENT_REQUIRED","message":"Нужен действующий доступ"}}',403,headers:{'content-type':'application/json; charset=utf-8'});
   return http.Response(jsonEncode({'data':path=='/me'?user:{'items':[]}}),200,headers:{'content-type':'application/json; charset=utf-8'});
  }));addTearDown(api.dispose);
  await t.pumpWidget(JobaApp(api:api));await t.pumpAndSettle();api.session={'access_token':'fixture','user':user};final dynamic state=t.state(find.byType(Marketplace));state.me=user;state.executor=executor;state.go(executor?'jobs':'catalog');await t.pumpAndSettle();expect(state.route,'access');expect(find.byType(AlertDialog),findsNothing);expect(find.text('Нужен действующий доступ'),findsNothing);expect(api.authenticated,true);
  state.go('account');await t.pumpAndSettle();final operation=state.act(()async{await api.request('/restricted-command',method:'POST');});await t.pumpAndSettle();await operation;expect(state.route,'access');expect(find.byType(AlertDialog),findsNothing);expect(api.authenticated,true);
 });
}
