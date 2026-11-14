import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:services_marketplace/core/api.dart';
import 'package:services_marketplace/core/widgets.dart';
import 'widget_test.dart' show MemoryVault;
class _PhotoApi extends JobaApi {
 _PhotoApi():super('https://isolated.example',vault:MemoryVault());
 @override Future<Uint8List> download(String id,{bool rotated=false,String variant='original',int? sessionGeneration})async=>base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=');
}
void main(){
 testWidgets('gallery thumbnails decode at their own size instead of retaining screen-sized bitmaps',(t)async{
  t.view.physicalSize=const Size(1170,2532);t.view.devicePixelRatio=3;
  addTearDown(t.view.resetPhysicalSize);addTearDown(t.view.resetDevicePixelRatio);
  final api=_PhotoApi();addTearDown(api.dispose);
  await t.pumpWidget(MaterialApp(home:Scaffold(body:Align(alignment:Alignment.topLeft,child:SizedBox(width:100,height:100,child:PrivatePhoto(api:api,id:'gallery-photo',height:100))))));
  await t.pumpAndSettle();
  final image=t.widget<Image>(find.byType(Image));expect(image.image,isA<ResizeImage>());expect((image.image as ResizeImage).width,300);expect(t.takeException(),isNull);
 });
}
