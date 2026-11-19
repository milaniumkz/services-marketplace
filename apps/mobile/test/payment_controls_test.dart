import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:services_marketplace/core/api.dart';
import 'package:services_marketplace/screens/executor_access.dart';
import 'package:services_marketplace/screens/commerce_states.dart';
import 'widget_test.dart' show MemoryVault,ok;
void main(){
 for(final screen in ['access','checkout'])testWidgets('disabled card payments keep advertising access available on $screen without prices or pay buttons',(t)async{
  var writes=0;String? destination,target;
  final api=JobaApi('https://isolated.example',vault:MemoryVault(),transport:MockClient((r)async{
   if(r.method!='GET')writes++;
   if(r.url.path.endsWith('/me/web-ads'))return ok({'enabled':true,'rewarded_enabled':true,'offers':[{'target':'customer','title':'Доступ за рекламу','required_views':5,'completed_views':2}]});
   if(r.url.path.endsWith('/billing/offers'))return ok({'paid_checkout_enabled':false,'items':[]});
   if(r.url.path.endsWith('/billing/vtb/pending'))return ok({'enabled':true,'items':[]});
   return ok({'items':[]});
  }))..session={'access_token':'isolated','user':{'id':'customer','active_role':'customer'}};
  addTearDown(api.dispose);
  final Widget child=screen=='access'?ExecutorAccess(api:api,choosing:true,customer:true,grants:const[],subscriptions:const[],config:const{'paid_checkout_enabled':false,'offers':[],'plans':[{'code':'customer','amount_minor':50000,'currency':'KZT'}]},onGo:(r,id){destination=r;target=id;}):CommerceStateScreen(api:api,mode:'checkout',onGo:(r,id){destination=r;target=id;});
  await t.pumpWidget(MaterialApp(home:Scaffold(body:child)));await t.pumpAndSettle();
  expect(find.text('Подписка за рекламу'),findsOneWidget);expect(find.text('Доступ за рекламу · 2/5 просмотров · 30 дней'),findsOneWidget);
  expect(find.text('Продолжить оплату'),findsNothing);expect(find.text('Посмотреть условия'),findsNothing);expect(find.byType(FilledButton),findsNothing);
  await t.tap(find.text('Доступ за рекламу · 2/5 просмотров · 30 дней'));await t.pumpAndSettle();expect(destination,'reward');expect(target,'customer');expect(writes,0);expect(t.takeException(),isNull);
  await t.pumpWidget(const SizedBox());
 });
}
