import 'package:flutter/material.dart';
import '../core/api.dart';
class WebAdsPanel extends StatelessWidget {
 final JobaApi api; final VoidCallback onReward; final VoidCallback? onPrivacy; final bool compact;
 const WebAdsPanel({required this.api,required this.onReward,this.onPrivacy,this.compact=false,super.key});
 @override Widget build(BuildContext context)=>const SizedBox.shrink();
}
class WebRewardScreen extends StatelessWidget {
 final JobaApi api; final VoidCallback? onPrivacy; final void Function(String)? onNavigate; final String? target;
 const WebRewardScreen({required this.api,this.onPrivacy,this.onNavigate,this.target,super.key});
 @override Widget build(BuildContext context)=>const SizedBox.shrink();
}

class WebRewardEntry extends StatelessWidget{final JobaApi api;final void Function(String) onSelect;final String? target;const WebRewardEntry({required this.api,required this.onSelect,this.target,super.key});@override Widget build(BuildContext context)=>const SizedBox.shrink();}
