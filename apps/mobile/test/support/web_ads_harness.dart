// Isolated browser harness. Never used by the production entry point.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:services_marketplace/core/api.dart';
import 'package:services_marketplace/advertising/web_ads.dart';
import 'package:services_marketplace/core/navigation_shell.dart';
void main(){runApp(MaterialApp(theme:ThemeData(fontFamily:'Noto'),home:const Harness()));}
class Harness extends StatefulWidget{const Harness({super.key});@override State<Harness> createState()=>_HarnessState();}
class _HarnessState extends State<Harness>{
 bool accepted=false,reward=false,recorded=false;int count=0,bannerRevision=0;late final JobaApi api;
 @override void initState(){super.initState();api=JobaApi('https://isolated.example',transport:MockClient((r)async{
  Object result;
  if(r.method=='GET')result={'enabled':true,'rewarded_enabled':true,'banner_id':'R-A-20302217-1','verification_status':'passed','offers':[{'target':'standard','title':'Стандарт исполнителя','required_views':5,'completed_views':count,'eligible':true,'duration_days':30}],'consent':accepted,'consent_recorded':recorded,'notice':'Изолированный тест согласия','server_time':DateTime.now().toUtc().toIso8601String()};
  else if(r.url.path.endsWith('/consent')){accepted=jsonDecode(r.body)['accepted'];recorded=true;result={'accepted':accepted};}
  else if(r.url.path.endsWith('/outcome')){final completed=jsonDecode(r.body)['completed']==true;if(completed)count++;result={'status':!completed?'not_completed':count<5?'progress':'granted','completed_views':count,'required_views':5};}
  else{final platform=jsonDecode(r.body)['platform'];result={'id':'isolated-session','nonce':'isolated-nonce','block_id':platform=='desktop'?'R-A-20302217-3':'R-A-20302217-2','reward_seconds':3600};}
  return http.Response(jsonEncode({'data':result}),200,headers:{'content-type':'application/json; charset=utf-8'});
 }))..session={'access_token':'isolated','user':{'id':'isolated-user'}};}
 @override void dispose(){api.dispose();super.dispose();}
 @override Widget build(BuildContext context)=>NavigationFrame(navigation:reward?null:NavigationState(route:'home',executor:true,enabled:true,messages:0,notifications:0,onSelect:(_){},bannerPlacement:'home:$bannerRevision',banner:WebAdsPanel(key:ValueKey(bannerRevision),api:api,compact:true,onReward:()=>setState(()=>reward=true))),child:Scaffold(appBar:AppBar(title:const Text('Изолированный тест рекламы'),leading:reward?IconButton(onPressed:()=>setState(()=>reward=false),icon:const Icon(Icons.arrow_back),tooltip:'Назад'):null),

  body:reward?WebRewardScreen(api:api):ListView(padding:const EdgeInsets.all(20),children:[WebRewardEntry(api:api,onSelect:(_)=>setState(()=>reward=true)),TextButton(onPressed:()=>setState(()=>bannerRevision++),child:const Text('Обновить рекламу в тесте')),for(var i=0;i<25;i++)Padding(padding:const EdgeInsets.all(12),child:Text('Содержимое раздела: строка $i'))])));
}
