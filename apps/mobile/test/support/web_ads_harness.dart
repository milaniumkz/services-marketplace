// Isolated browser harness. Never used by the production entry point.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:services_marketplace/core/api.dart';
import 'package:services_marketplace/advertising/web_ads.dart';
void main(){runApp(MaterialApp(theme:ThemeData(fontFamily:'Noto'),home:const Harness()));}
class Harness extends StatefulWidget{const Harness({super.key});@override State<Harness> createState()=>_HarnessState();}
class _HarnessState extends State<Harness>{
 bool accepted=false,reward=false,recorded=false;String? until;late final JobaApi api;
 @override void initState(){super.initState();api=JobaApi('https://isolated.example',transport:MockClient((r)async{
  Object result;
  if(r.method=='GET')result={'enabled':true,'rewarded_enabled':true,'banner_id':'R-A-20302217-1','reward_seconds':3600,'consent':accepted,'consent_recorded':recorded,'notice':'Изолированный тест согласия','server_time':DateTime.now().toUtc().toIso8601String(),'ad_free_until':until};
  else if(r.url.path.endsWith('/consent')){accepted=jsonDecode(r.body)['accepted'];recorded=true;result={'accepted':accepted};}
  else if(r.url.path.endsWith('/outcome')){final completed=jsonDecode(r.body)['completed']==true;if(completed)until=DateTime.now().toUtc().add(const Duration(hours:1)).toIso8601String();result={'status':completed?'granted':'not_completed'};}
  else{final platform=jsonDecode(r.body)['platform'];result={'id':'isolated-session','nonce':'isolated-nonce','block_id':platform=='desktop'?'R-A-20302217-3':'R-A-20302217-2','reward_seconds':3600};}
  return http.Response(jsonEncode({'data':result}),200,headers:{'content-type':'application/json; charset=utf-8'});
 }))..session={'access_token':'isolated','user':{'id':'isolated-user'}};}
 @override void dispose(){api.dispose();super.dispose();}
 @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Изолированный тест рекламы'),leading:reward?IconButton(onPressed:()=>setState(()=>reward=false),icon:const Icon(Icons.arrow_back),tooltip:'Назад'):null),body:reward?WebRewardScreen(api:api):SingleChildScrollView(child:Padding(padding:const EdgeInsets.all(20),child:WebAdsPanel(api:api,onReward:()=>setState(()=>reward=true)))));
}
