import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/design_widgets.dart';
import '../core/widgets.dart';

/// Check the account and its access before mounting private home-page listings.
class HomeMarketplaceGate extends StatelessWidget {
 final JobaApi api;
 final bool executor;
 final Widget Function() content;
 final VoidCallback onAccess,onVerification;
 const HomeMarketplaceGate({required this.api,required this.executor,required this.content,required this.onAccess,required this.onVerification,super.key});
 Future<Json> load()async{
  final user=await api.request('/me');
  if(user['verification']!='passed')return {'verification_required':true};
  final grants=items(await api.request('/me/entitlements')),now=api.clock.now.toUtc();
  final allowed=grants.any((g){
   final until=DateTime.tryParse(g['valid_until'] as String? ?? ''),from=DateTime.tryParse(g['valid_from'] as String? ?? '');
   if(until==null||!until.isAfter(now)||from!=null&&from.isAfter(now)||(g['balance'] is num&&g['balance']<=0))return false;
   final caps=g['capabilities'] as List? ?? [];
   return executor?g['role']!='customer'&&g['plan']!='customer'&&caps.contains('search_full'):(g['role']=='customer'||g['plan']=='customer'||g['source']=='admin_compensation')&&caps.contains('view_contractors');
  });
  return {'access_required':!allowed};
 }
 @override Widget build(BuildContext context)=>ApiView(load:load,builder:(context,data,retry){
  if(data['verification_required']==true)return JobaMenu([JobaMenuEntry('Подтвердить личность','shield',onVerification,subtitle:'Удостоверение с двух сторон и селфи')]);
  if(data['access_required']==true)return JobaMenu([JobaMenuEntry('Мой доступ','card',onAccess,subtitle:'Подключить подписку')]);
  return content();
 });
}
