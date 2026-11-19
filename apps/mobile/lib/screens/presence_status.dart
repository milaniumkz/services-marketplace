import 'dart:async';
import 'package:flutter/material.dart';
import '../core/api.dart';

/// Connection presence is separate from verification and historical activity.
class PresenceStatus extends StatefulWidget {
 const PresenceStatus({super.key,required this.api,required this.userId,this.initial,this.compact=false});
 final JobaApi api;final String userId;final bool? initial;final bool compact;
 @override State<PresenceStatus> createState()=>_PresenceStatusState();
}
class _PresenceStatusState extends State<PresenceStatus> with WidgetsBindingObserver {
 Timer? timer;bool? online;bool pending=false,foreground=true;int generation=0;
 @override void initState(){super.initState();online=widget.initial;WidgetsBinding.instance.addObserver(this);load();timer=Timer.periodic(const Duration(seconds:10),(_)=>load());}
 @override void didUpdateWidget(PresenceStatus old){super.didUpdateWidget(old);if(old.userId!=widget.userId||old.api!=widget.api){generation++;pending=false;online=widget.initial;load();}}
 Future<void> load()async{if(pending||!foreground||widget.userId.isEmpty)return;pending=true;final current=generation;try{final data=await widget.api.request('/users/${widget.userId}/presence');if(mounted&&current==generation)setState(()=>online=data['online'] is bool?data['online']:null);}catch(_){if(mounted&&current==generation)setState(()=>online=null);}finally{if(current==generation)pending=false;}}
 @override void didChangeAppLifecycleState(AppLifecycleState state){foreground=state==AppLifecycleState.resumed;if(foreground)load();}
 @override void dispose(){generation++;timer?.cancel();WidgetsBinding.instance.removeObserver(this);super.dispose();}
 @override Widget build(BuildContext context){final label=online==true?'Онлайн':online==false?'Не в сети':'Статус уточняется';return Semantics(label:label,child:Tooltip(message:label,child:Row(mainAxisSize:MainAxisSize.min,children:[Icon(Icons.circle,size:8,color:online==true?const Color(0xFF21A566):online==false?const Color(0xFFCB5361):const Color(0xFF8A96A8)),if(!widget.compact)...[const SizedBox(width:5),Text(label,style:const TextStyle(fontSize:11,color:Color(0xFF627187)))]])));}
}
