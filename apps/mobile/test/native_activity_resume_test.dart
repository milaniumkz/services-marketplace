import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:services_marketplace/core/api.dart';
import 'package:services_marketplace/core/external_activity.dart';
import 'package:services_marketplace/main.dart';
import 'package:services_marketplace/screens/marketplace.dart';
import 'widget_test.dart' show MemoryVault,ok;
void main(){
 testWidgets('camera return preserves profile editing instead of showing PIN or home',(t)async{
  final user={'id':'camera-user','country':'KZ','locale':'ru','active_role':'executor','roles':['executor'],'display_name':'Исполнитель','city':'Караганда','verification':'passed','version':1};
  final api=JobaApi('https://isolated.example',vault:MemoryVault(),transport:MockClient((r)async=>ok(r.url.path.endsWith('/me')?user:{'items':[]})));
  await t.pumpWidget(JobaApp(api:api));await t.pumpAndSettle();
  final dynamic state=t.state(find.byType(Marketplace));
  api.session={'access_token':'camera-access','refresh_token':'refresh','user':user};state.me=user;state.localProtected=true;state.route='profile-edit';state.locked=false;
  state.pausedAt=DateTime.now().subtract(const Duration(minutes:2));
  await t.runAsync(()async {await withExternalActivity(()async{state.didChangeAppLifecycleState(AppLifecycleState.resumed);expect(state.locked,false);expect(state.route,'profile-edit');});
  // Native activity result can arrive just before the lifecycle resume callback.
  state.pausedAt=DateTime.now().subtract(const Duration(minutes:2));state.didChangeAppLifecycleState(AppLifecycleState.resumed);
  expect(state.locked,false);expect(state.route,'profile-edit');});
  await t.pumpWidget(const SizedBox.shrink());api.dispose();
 });
 testWidgets('executor profile keeps subscription, Top-100 and referral menus with an active plan',(t)async{
  final user={'id':'paid-executor','country':'KZ','locale':'ru','active_role':'executor','roles':['executor'],'display_name':'Исполнитель','city':'Караганда','verification':'passed','version':1};
  final api=JobaApi('https://isolated.example',vault:MemoryVault(),transport:MockClient((r)async{
   if(r.url.path.endsWith('/me'))return ok(user);
   if(r.url.path.endsWith('/me/overview'))return ok({'orders':{},'rating':{'count':0},'subscription_until':'2030-12-04T00:00:00Z'});
   return ok({'items':[]});
  }));
  await t.pumpWidget(JobaApp(api:api));await t.pumpAndSettle();
  final dynamic state=t.state(find.byType(Marketplace));api.session={'access_token':'paid-access','user':user};state.me=user;state.executor=true;state.go('account');await t.pumpAndSettle();
  expect(find.text('Мой доступ'),findsOneWidget);expect(find.text('Подключить Топ-100'),findsOneWidget);
  await t.scrollUntilVisible(find.text('Приглашения и бонусы'),200,scrollable:find.byType(Scrollable).first);expect(find.text('Приглашения и бонусы'),findsOneWidget);
  await t.scrollUntilVisible(find.text('Мой доступ'),-300,scrollable:find.byType(Scrollable).first);await t.tap(find.text('Мой доступ'));await t.pumpAndSettle();expect(state.route,'my-access');
  await t.pumpWidget(const SizedBox.shrink());api.dispose();
 });

}
