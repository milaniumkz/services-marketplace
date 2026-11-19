import 'package:flutter/material.dart';
class VerifiedBadge extends StatelessWidget {
 const VerifiedBadge({super.key,this.size=20});
 final double size;
 @override Widget build(BuildContext context)=>Tooltip(message:'Верифицирован',child:Semantics(label:'Верифицирован',child:Icon(Icons.verified,color:Color(0xFF1D9BF0),size:size)));
}

/// Keeps the verification mark attached to the name, including wrapped names.
class VerifiedName extends StatelessWidget {
 const VerifiedName(this.name,{super.key,required this.verified,this.style});
 final String name;
 final bool verified;
 final TextStyle? style;
 @override Widget build(BuildContext context)=>Text.rich(TextSpan(children:[
  TextSpan(text:name),
  if(verified) const WidgetSpan(alignment:PlaceholderAlignment.middle,child:Padding(padding:EdgeInsets.only(left:6),child:VerifiedBadge())),
 ]),style:style);
}
