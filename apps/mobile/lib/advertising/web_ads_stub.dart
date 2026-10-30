import 'package:flutter/material.dart';
import '../core/api.dart';
class WebAdsPanel extends StatelessWidget {
 final JobaApi api; final VoidCallback onReward; final VoidCallback? onPrivacy;
 const WebAdsPanel({required this.api,required this.onReward,this.onPrivacy,super.key});
 @override Widget build(BuildContext context)=>const SizedBox.shrink();
}
class WebRewardScreen extends StatelessWidget {
 final JobaApi api; final VoidCallback? onPrivacy;
 const WebRewardScreen({required this.api,this.onPrivacy,super.key});
 @override Widget build(BuildContext context)=>const SizedBox.shrink();
}
