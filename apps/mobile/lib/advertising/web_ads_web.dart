import 'dart:async';
import 'dart:js_interop';
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;
import 'package:url_launcher/url_launcher.dart';
import '../core/api.dart';
import '../core/web_ad_consent.dart';

@JS('JobaWebAds.banner') external JSPromise<JSBoolean> _banner(JSString element,JSString block);
@JS('JobaWebAds.platform') external JSPromise<JSString> _platform();
@JS('JobaWebAds.rewarded') external JSPromise<JSBoolean> _rewarded(JSString block,JSString platform);
Widget _privacyLinks(VoidCallback? onPrivacy)=>Wrap(children:[if(onPrivacy!=null)TextButton(onPressed:onPrivacy,child:const Text('Документы JOBA')),TextButton(onPressed:()=>launchUrl(Uri.parse('https://yandex.ru/legal/confidential/'),mode:LaunchMode.externalApplication),child:const Text('Политика Яндекса'))]);
String _message(Object e)=>e is ApiException?e.message:'Рекламу не удалось загрузить. Проверьте соединение или попробуйте позже.';

class WebAdsPanel extends StatefulWidget {
 final JobaApi api; final VoidCallback onReward; final VoidCallback? onPrivacy; final bool compact;
 const WebAdsPanel({required this.api,required this.onReward,this.onPrivacy,this.compact=false,super.key});
 @override State<WebAdsPanel> createState()=>_WebAdsPanelState();
}
class _WebAdsPanelState extends State<WebAdsPanel> {
 Json? config; String? error; bool busy=false,expanded=false,dismissed=false; int attempt=0; double bannerHeight=180; web.ResizeObserver? resize;
 @override void initState(){super.initState();load();}
 @override void dispose(){resize?.disconnect();super.dispose();}
 Future<void> load() async {
  try {var c=Json.from(await widget.api.request('/me/web-ads'));if(!mounted)return;if(c['consent']==false&&c['consent_recorded']==true)rememberWebAdConsent(false);if(rememberedWebAdConsent()==false)c={...c,'consent':false,'consent_recorded':true};
   setState((){config=c;error=null;});
  }catch(_){/* Advertising failure must never block the marketplace. */}
 }
 Future<void> consent(bool accepted) async {
  if(busy)return;setState(()=>busy=true);
  try{await widget.api.request('/me/web-ads/consent',method:'POST',body:{'accepted':accepted});rememberWebAdConsent(accepted);if(!accepted){resize?.disconnect();resize=null;}if(mounted)setState((){expanded=false;config={...?config,'consent':accepted,'consent_recorded':true};});await load();}
  catch(e){if(mounted)setState(()=>error=_message(e));}
  finally{if(mounted)setState(()=>busy=false);}
 }
 @override Widget build(BuildContext context) {
  final c=config;if(c==null||c['enabled']!=true||dismissed)return const SizedBox.shrink();
  return Padding(padding:const EdgeInsets.symmetric(vertical:16),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
   if(widget.compact)Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[const Text('Реклама',style:TextStyle(fontSize:11,color:Colors.grey)),IconButton(onPressed:()=>setState(()=>dismissed=true),tooltip:'Скрыть баннер',icon:const Icon(Icons.close,size:16))]),
   if(c['consent']!=true && (c['consent_recorded']==true||widget.compact) && !expanded)...[
    const Text('Реклама отключена.'),TextButton(onPressed:(){setState(()=>expanded=true);},child:const Text('Настроить рекламу')),
   ]else if(c['consent']!=true)...[
    const Text('Реклама Яндекса',style:TextStyle(fontWeight:FontWeight.bold)),
    Text(c['notice'] as String? ?? 'Реклама Яндекса загружается с передачей технических данных браузера. Согласие добровольное.'),
    _privacyLinks(widget.onPrivacy),
    TextButton(onPressed:busy?null:()=>consent(true),child:const Text('Разрешить рекламные показы')),
    TextButton(onPressed:busy?null:()=>consent(false),child:const Text('Не сейчас')),
   ]else ...[
    if(error==null)...[
     const Text('Реклама',style:TextStyle(fontSize:11,color:Colors.grey)),
     SizedBox(height:bannerHeight,child:HtmlElementView.fromTagName(key:ValueKey(attempt),tagName:'div',onElementCreated:(element){
      final host=element as web.HTMLDivElement;host.id='joba-banner-${identityHashCode(this)}-$attempt';host.style.width='100%';host.style.height='auto';host.style.minHeight='90px';
      void measure(){final box=host.getBoundingClientRect(),scroll=host.scrollHeight.toDouble();final height=scroll>box.height?scroll:box.height;if(mounted&&host.isConnected&&config?['consent']==true&&height.isFinite&&height>=50&&(height-bannerHeight).abs()>1)setState(()=>bannerHeight=height);}
      resize?.disconnect();resize=web.ResizeObserver(((JSArray<web.ResizeObserverEntry> entries,web.ResizeObserver observer)=>measure()).toJS);resize!.observe(host);
      final renderAttempt=attempt;
      Future<JSBoolean>.sync(()=>_banner(host.id.toJS,(c['banner_id'] as String).toJS).toDart).then<void>((shown){if(shown.toDart)measure();if(!shown.toDart&&mounted&&config?['consent']==true&&renderAttempt==attempt)setState(()=>error='Сейчас нет доступного объявления или загрузка не удалась. Можно попробовать позже.');}).catchError((Object e){if(mounted&&config?['consent']==true&&renderAttempt==attempt)setState(()=>error=_message(e));});
     })),
    ],
    TextButton(onPressed:busy?null:()=>consent(false),child:const Text('Отключить рекламные показы')),
   ],
   if(error!=null)...[Text(error!,style:const TextStyle(color:Colors.red)),TextButton(onPressed:(){setState((){error=null;attempt++;});},child:const Text('Повторить загрузку рекламы'))],
  ]));
 }
}
class WebRewardEntry extends StatefulWidget {
 final JobaApi api; final void Function(String) onSelect; final String? target;
 const WebRewardEntry({required this.api,required this.onSelect,this.target,super.key});
 @override State<WebRewardEntry> createState()=>_WebRewardEntryState();
}
class _WebRewardEntryState extends State<WebRewardEntry>{
 Json? config;
 @override void initState(){super.initState();load();}
 Future<void> load()async{try{final c=await widget.api.request('/me/web-ads');if(mounted)setState(()=>config=c);}catch(_){}}
 @override Widget build(BuildContext context){final c=config;if(c?['rewarded_enabled']!=true)return const SizedBox.shrink();final offers=(c!['offers'] as List? ?? []).cast<Json>().where((o)=>widget.target==null||o['target']==widget.target);return Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[const Text('Подписка за рекламу',style:TextStyle(fontWeight:FontWeight.bold,fontSize:18)),const Text('Деньги не списываются. Доступ выдаётся после всех завершённых просмотров.'),for(final o in offers)Padding(padding:const EdgeInsets.only(top:10),child:OutlinedButton(onPressed:()=>widget.onSelect(o['target']),child:Text('${o['title']} на 30 дней · ${o['completed_views']}/${o['required_views']} просмотров')))])));}
}
class WebRewardScreen extends StatefulWidget {
 final JobaApi api; final VoidCallback? onPrivacy; final void Function(String)? onNavigate; final String? target;
 const WebRewardScreen({required this.api,this.onPrivacy,this.onNavigate,this.target,super.key});
 @override State<WebRewardScreen> createState()=>_WebRewardScreenState();
}
class _WebRewardScreenState extends State<WebRewardScreen> {
 Json? config,pending; bool? pendingCompleted; int? pendingGeneration; String? message,selected; bool busy=false;
 @override void initState(){super.initState();selected=widget.target;load();}
 List<Json> get offers=>(config?['offers'] as List? ?? []).cast<Json>();
 Json? get offer {final matching=offers.where((o)=>o['target']==selected);return matching.isNotEmpty?matching.first:offers.isNotEmpty?offers.first:null;}
 Future<void> load()async{try{final c=await widget.api.request('/me/web-ads');if(mounted)setState(()=>config=c);}catch(e){if(mounted&&config==null)setState(()=>message=_message(e));}}
 Future<void> play()async{
  if(busy||offer==null)return;setState((){busy=true;message=null;});
  final api=widget.api,generation=api.sessionGeneration;Json? sdkSession;
  bool current()=>mounted&&api.authenticated&&api.sessionGeneration==generation;
  try{
   if(pending!=null&&pendingGeneration!=generation){pending=null;pendingCompleted=null;}
   if(pending!=null){await confirm(current);return;}
   if(offer!['ready']==true){final result=await api.request('/me/web-ads/redeem',method:'POST',body:{'target':offer!['target']});if(current()){showReceipt(result);await load();}return;}
   if(config?['consent']!=true)await api.request('/me/web-ads/consent',method:'POST',body:{'accepted':true});rememberWebAdConsent(true);
   final platform=(await _platform().toDart).toDart;if(!current())return;
   final session=await api.request('/me/web-ads/reward-sessions',method:'POST',body:{'platform':platform,'target':offer!['target']});sdkSession=session;if(!current())return;
   final completed=(await _rewarded((session['block_id'] as String).toJS,platform.toJS).toDart).toDart;if(!current())return;
   pending=session;pendingCompleted=completed;pendingGeneration=generation;await confirm(current);
  }catch(e){if(current()){if(sdkSession!=null&&pending==null){try{await api.request('/me/web-ads/reward-sessions/${sdkSession['id']}/outcome',method:'POST',body:{'nonce':sdkSession['nonce'],'completed':false});}catch(_){}}if(current())setState(()=>message=_message(e));}}
  finally{if(mounted)setState(()=>busy=false);}
 }
 void showReceipt(Json r){setState(()=>message=r['status']=='granted'?(r['scheduled']==true?'Новые 30 дней получены. Они начнутся после действующего оплаченного периода.':'Подписка активирована на 30 дней. Деньги не списывались.'):r['status']=='progress'?'Засчитано просмотров: ${r['completed_views']} из ${r['required_views']}. До полного набора доступ не выдаётся.':r['status']=='ready'?'Все просмотры сохранены. ${r['message']??'Нажмите «Активировать».'}':'Ролик не завершён или не подобран. Прогресс не изменился.');}
 Future<void> confirm(bool Function() current)async{
  final s=pending!;final result=await widget.api.request('/me/web-ads/reward-sessions/${s['id']}/outcome',method:'POST',body:{'nonce':s['nonce'],'completed':pendingCompleted});if(!current())return;
  setState((){pending=null;pendingCompleted=null;});showReceipt(result);await load();
 }
 @override Widget build(BuildContext context){final o=offer,count=(o?['completed_views'] as num? ?? 0).toInt(),required=(o?['required_views'] as num? ?? 1).toInt();return ListView(padding:const EdgeInsets.all(20),children:[
  const Text('Подписка за рекламу',style:TextStyle(fontSize:24,fontWeight:FontWeight.bold)),
  if(o!=null)DropdownButtonFormField<String>(key:ValueKey(o['target']),initialValue:o['target'],decoration:const InputDecoration(labelText:'Что получить за рекламу'),items:offers.map((option)=>DropdownMenuItem<String>(value:option['target'],child:Text('${option['title']} · 30 дней'))).toList(),onChanged:busy?null:(v)=>setState(()=>selected=v)),
  if(o!=null)...[Text('Завершено $count из $required просмотров',style:const TextStyle(fontWeight:FontWeight.bold)),LinearProgressIndicator(value:(count/required).clamp(0,1).toDouble()),const SizedBox(height:12),Text('Доступ выдаётся только после $required полностью завершённых просмотров. Неполный ролик не засчитывается. Прогресс сохраняется в аккаунте. Подписка и Топ-100 оплачиваются просмотрами отдельно.')],
  const SizedBox(height:12),Text(config?['notice'] as String? ?? 'Просмотр добровольный.'),_privacyLinks(widget.onPrivacy),
  if(o?['reason']!=null)Text(o!['reason'],style:const TextStyle(color:Colors.red)),
  if(config?['verification_status']!='passed'&&widget.onNavigate!=null)TextButton(onPressed:()=>widget.onNavigate!('verification'),child:const Text('Подтвердить личность')),
  FilledButton(onPressed:busy||o==null||(pending==null&&(config?['rewarded_enabled']!=true||o['eligible']!=true))?null:play,child:Text(busy?'Ожидаем завершения…':pending!=null?'Повторить подтверждение просмотра':o?['ready']==true?'Активировать':'Согласен, посмотреть ролик')),
  if(config==null&&message==null)const Center(child:CircularProgressIndicator()),
  if(config!=null&&config!['rewarded_enabled']!=true)const Text('Оплата рекламой сейчас выключена.'),
  if(message!=null)Padding(padding:const EdgeInsets.only(top:16),child:Text(message!)),
  if(widget.onNavigate!=null)TextButton(onPressed:busy?null:()=>widget.onNavigate!('my-access'),child:const Text('Моя подписка')),
  if(config==null)TextButton(onPressed:busy?null:load,child:const Text('Повторить')),
 ]);}
}
