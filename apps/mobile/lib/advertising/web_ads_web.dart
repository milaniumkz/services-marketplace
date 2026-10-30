import 'dart:async';
import 'dart:js_interop';
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;
import 'package:url_launcher/url_launcher.dart';
import '../core/api.dart';

@JS('JobaWebAds.banner') external JSPromise<JSBoolean> _banner(JSString element,JSString block);
@JS('JobaWebAds.platform') external JSPromise<JSString> _platform();
@JS('JobaWebAds.rewarded') external JSPromise<JSBoolean> _rewarded(JSString block,JSString platform);
Widget _privacyLinks(VoidCallback? onPrivacy)=>Wrap(children:[if(onPrivacy!=null)TextButton(onPressed:onPrivacy,child:const Text('Документы JOBA')),TextButton(onPressed:()=>launchUrl(Uri.parse('https://yandex.ru/legal/confidential/'),mode:LaunchMode.externalApplication),child:const Text('Политика Яндекса'))]);
String _message(Object e)=>e is ApiException?e.message:'Рекламу не удалось загрузить. Проверьте соединение или попробуйте позже.';

class WebAdsPanel extends StatefulWidget {
 final JobaApi api; final VoidCallback onReward; final VoidCallback? onPrivacy;
 const WebAdsPanel({required this.api,required this.onReward,this.onPrivacy,super.key});
 @override State<WebAdsPanel> createState()=>_WebAdsPanelState();
}
class _WebAdsPanelState extends State<WebAdsPanel> {
 Json? config; String? error; bool busy=false,expanded=false; int attempt=0; double bannerHeight=180; Timer? refresh; web.ResizeObserver? resize;
 @override void initState(){super.initState();load();}
 @override void dispose(){refresh?.cancel();resize?.disconnect();super.dispose();}
 Future<void> load() async {
  try {final c=await widget.api.request('/me/web-ads');if(!mounted)return;
   refresh?.cancel();final until=DateTime.tryParse(c['ad_free_until']??''),now=DateTime.tryParse(c['server_time']??'');
   if(until!=null&&now!=null&&until.isAfter(now))refresh=Timer(Duration(seconds:until.difference(now).inSeconds.clamp(1,86400)+1),load);
   setState((){config=c;error=null;});
  }catch(_){/* Advertising failure must never block the marketplace. */}
 }
 bool get adFree {
  final until=DateTime.tryParse(config?['ad_free_until']??''),now=DateTime.tryParse(config?['server_time']??'');
  return until!=null&&now!=null&&until.isAfter(now);
 }
 Future<void> consent(bool accepted) async {
  if(busy)return;setState(()=>busy=true);
  try{await widget.api.request('/me/web-ads/consent',method:'POST',body:{'accepted':accepted});if(!accepted){resize?.disconnect();resize=null;}if(mounted)setState((){expanded=false;config={...?config,'consent':accepted,'consent_recorded':true};});await load();}
  catch(e){if(mounted)setState(()=>error=_message(e));}
  finally{if(mounted)setState(()=>busy=false);}
 }
 @override Widget build(BuildContext context) {
  final c=config;if(c==null||c['enabled']!=true)return const SizedBox.shrink();
  return Padding(padding:const EdgeInsets.symmetric(vertical:16),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
   if(c['consent']!=true && c['consent_recorded']==true && !expanded)...[
    const Text('Реклама отключена.'),TextButton(onPressed:(){setState(()=>expanded=true);},child:const Text('Настроить рекламу')),
   ]else if(c['consent']!=true)...[
    const Text('Реклама Яндекса',style:TextStyle(fontWeight:FontWeight.bold)),
    Text(c['notice'] as String? ?? 'Реклама Яндекса загружается с передачей технических данных браузера. Согласие добровольное.'),
    _privacyLinks(widget.onPrivacy),
    TextButton(onPressed:busy?null:()=>consent(true),child:const Text('Разрешить рекламные показы')),
    TextButton(onPressed:busy?null:()=>consent(false),child:const Text('Не сейчас')),
   ]else ...[
    if(adFree)const Text('Баннеры временно отключены после просмотра рекламы.')
    else if(error==null)...[
     const Text('Реклама',style:TextStyle(fontSize:11,color:Colors.grey)),
     SizedBox(height:bannerHeight,child:HtmlElementView.fromTagName(key:ValueKey(attempt),tagName:'div',onElementCreated:(element){
      final host=element as web.HTMLDivElement;host.id='joba-banner-${identityHashCode(this)}-$attempt';host.style.width='100%';host.style.height='auto';host.style.minHeight='90px';
      void measure(){final box=host.getBoundingClientRect(),scroll=host.scrollHeight.toDouble();final height=scroll>box.height?scroll:box.height;if(mounted&&host.isConnected&&config?['consent']==true&&height.isFinite&&height>=50&&(height-bannerHeight).abs()>1)setState(()=>bannerHeight=height);}
      resize?.disconnect();resize=web.ResizeObserver(((JSArray<web.ResizeObserverEntry> entries,web.ResizeObserver observer)=>measure()).toJS);resize!.observe(host);
      final renderAttempt=attempt;
      _banner(host.id.toJS,(c['banner_id'] as String).toJS).toDart.then<void>((shown){if(shown.toDart)measure();if(!shown.toDart&&mounted&&config?['consent']==true&&renderAttempt==attempt)setState(()=>error='Сейчас нет доступного объявления или загрузка не удалась. Можно попробовать позже.');}).catchError((Object e){if(mounted&&config?['consent']==true&&renderAttempt==attempt)setState(()=>error=_message(e));});
     })),
    ],
    if(c['rewarded_enabled']==true)OutlinedButton(onPressed:busy?null:widget.onReward,child:Text('Посмотреть рекламу — без баннеров ${_duration(c['reward_seconds'] as int)}')),
    TextButton(onPressed:busy?null:()=>consent(false),child:const Text('Отключить рекламные показы')),
   ],
   if(error!=null)...[Text(error!,style:const TextStyle(color:Colors.red)),TextButton(onPressed:(){setState((){error=null;attempt++;});},child:const Text('Повторить загрузку рекламы'))],
  ]));
 }
}
String _duration(int seconds)=>seconds%3600==0?'${seconds~/3600} ч.':'${(seconds/60).ceil()} мин.';

class WebRewardScreen extends StatefulWidget {
 final JobaApi api; final VoidCallback? onPrivacy;
 const WebRewardScreen({required this.api,this.onPrivacy,super.key});
 @override State<WebRewardScreen> createState()=>_WebRewardScreenState();
}
class _WebRewardScreenState extends State<WebRewardScreen> {
 Json? config,pending; bool? pendingCompleted; int? pendingGeneration; String? message; bool busy=false;
 @override void initState(){super.initState();load();}
 Future<void> load() async {
  try{final c=await widget.api.request('/me/web-ads');if(mounted)setState(()=>config=c);}
  catch(e){if(mounted&&config==null)setState(()=>message=_message(e));}
 }
 Future<void> play() async {
  if(busy)return;setState((){busy=true;message=null;});
  final api=widget.api,generation=widget.api.sessionGeneration;
  bool current()=>mounted&&api.authenticated&&api.sessionGeneration==generation;
  try{
   if(pending!=null&&pendingGeneration!=generation){pending=null;pendingCompleted=null;}
   if(pending!=null){await confirm(current);return;}
   if(config?['consent']!=true)await api.request('/me/web-ads/consent',method:'POST',body:{'accepted':true});
   final platform=(await _platform().toDart).toDart;
   if(!current())return;
   final session=await api.request('/me/web-ads/reward-sessions',method:'POST',body:{'platform':platform});
   if(!current())return;
   final completed=(await _rewarded((session['block_id'] as String).toJS,platform.toJS).toDart).toDart;
   if(!current())return;
   pending=session;pendingCompleted=completed;pendingGeneration=generation;
   await confirm(current);
  }catch(e){if(current())setState(()=>message=_message(e));}
  finally{if(mounted)setState(()=>busy=false);}
 }
 Future<void> confirm(bool Function() current) async {
  final session=pending!,completed=pendingCompleted!;
  final result=await widget.api.request('/me/web-ads/reward-sessions/${session['id']}/outcome',method:'POST',body:{'nonce':session['nonce'],'completed':completed});
  if(!current())return;
  setState((){pending=null;pendingCompleted=null;message=result['status']=='granted'?'Просмотр завершён. Баннеры отключены на ${_duration(session['reward_seconds'] as int)}.':'Просмотр не завершён или объявления сейчас нет. Награда не начислена.';});
  await load();
 }
 @override Widget build(BuildContext context)=>ListView(padding:const EdgeInsets.all(20),children:[
  const Icon(Icons.ondemand_video,size:44),const SizedBox(height:18),
  const Text('Без баннеров за просмотр',style:TextStyle(fontSize:24,fontWeight:FontWeight.bold)),const SizedBox(height:12),
  if(config!=null)Text('Посмотрите рекламу полностью — баннеры Яндекса в JOBA не будут показываться ${_duration(config!['reward_seconds'] as int)}. Платная подписка и деньги не выдаются.'),
  const SizedBox(height:12),
  Text(config?['notice'] as String? ?? 'Просмотр добровольный. При раннем закрытии награда не начисляется.'),
  _privacyLinks(widget.onPrivacy),
  const SizedBox(height:20),
  if(config==null&&message==null)const Center(child:CircularProgressIndicator()),
  FilledButton(onPressed:busy||(pending==null&&config?['rewarded_enabled']!=true)?null:play,child:Text(busy?'Ожидаем завершения просмотра…':pending!=null?'Повторить подтверждение просмотра':'Согласен, посмотреть рекламу')),
  if(config!=null&&config!['rewarded_enabled']!=true)const Text('Просмотр с вознаграждением пока выключен. Пожалуйста, попробуйте позже.'),
  if(message!=null)Padding(padding:const EdgeInsets.only(top:16),child:Text(message!,semanticsLabel:message)),
  if(config==null)TextButton(onPressed:busy?null:load,child:const Text('Повторить')),
 ]);
}
