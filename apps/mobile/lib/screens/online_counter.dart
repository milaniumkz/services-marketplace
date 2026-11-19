import 'dart:async';
import 'package:flutter/material.dart';
import '../core/api.dart';
class OnlineCounter extends StatefulWidget {
 const OnlineCounter({required this.api,super.key});
 final JobaApi api;
 @override State<OnlineCounter> createState()=>_OnlineCounterState();
}
class _OnlineCounterState extends State<OnlineCounter> with WidgetsBindingObserver {
 Timer? timer;int? count;bool pending=false,foreground=true;
 @override void initState(){super.initState();WidgetsBinding.instance.addObserver(this);load();timer=Timer.periodic(const Duration(seconds:15),(_)=>load());}
 Future<void> load()async{if(pending||!foreground)return;pending=true;try{final data=await widget.api.request('/public/online',authenticated:false);if(mounted&&data['count'] is int&&data['count']>=0)setState(()=>count=data['count']);}catch(_){if(mounted)setState(()=>count=null);}finally{pending=false;}}
 @override void didChangeAppLifecycleState(AppLifecycleState state){foreground=state==AppLifecycleState.resumed;if(foreground)load();}
 @override void dispose(){timer?.cancel();WidgetsBinding.instance.removeObserver(this);super.dispose();}
 @override Widget build(BuildContext context)=>Padding(padding:const EdgeInsets.only(bottom:12),child:Row(children:[const Icon(Icons.circle,size:8,color:Color(0xFF21A566)),const SizedBox(width:6),Flexible(child:Text(count==null?'Онлайн: уточняем…':'Сейчас онлайн: $count',style:const TextStyle(fontSize:12,color:Color(0xFF627187))))]));
}
