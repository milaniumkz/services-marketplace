import 'package:flutter/material.dart';
class VerifiedBadge extends StatelessWidget {
 const VerifiedBadge({super.key,this.size=20});
 final double size;
 @override Widget build(BuildContext context)=>Tooltip(message:'Верифицирован',child:Semantics(label:'Верифицирован',child:Icon(Icons.verified,color:Color(0xFF1D9BF0),size:size)));
}
