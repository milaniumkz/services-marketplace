import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:services_marketplace/advertising/reward_entry_card.dart';
import 'package:services_marketplace/core/theme.dart';
void main() {
  setUpAll(() async {
    if(Platform.environment['JOBA_REWARD_CAPTURE']!=null){
      await (FontLoader('Noto')..addFont(rootBundle.load('assets/NotoSans-Regular.ttf'))).load();
      await (FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    }
  });
  testWidgets('reward entry actions remain visible on a narrow screen and select the correct subscription or Top-100', (t) async {
    t.view.physicalSize=const Size(320,900);t.view.devicePixelRatio=1;
    addTearDown(t.view.resetPhysicalSize);addTearDown(t.view.resetDevicePixelRatio);
    String? target;final boundary=GlobalKey();
    await t.pumpWidget(MaterialApp(theme:jobaTheme(),home:MediaQuery(data:const MediaQueryData(textScaler:TextScaler.linear(1.5)),child:Scaffold(body:SingleChildScrollView(child:RepaintBoundary(key:boundary,child:Padding(padding:const EdgeInsets.all(16),child:RewardEntryCard(offers:const [
      {'target':'standard','title':'Стандарт исполнителя','required_views':5,'completed_views':0},
      {'target':'top100','title':'Топ-100 отдельно','required_views':3,'completed_views':3,'ready':true},
    ],onSelect:(v)=>target=v))))))));
    await t.pumpAndSettle();expect(t.takeException(),isNull);
    await t.ensureVisible(find.text('Смотреть рекламу'));await t.tap(find.text('Смотреть рекламу'));expect(target,'standard');
    await t.ensureVisible(find.text('Получить доступ'));await t.tap(find.text('Получить доступ'));expect(target,'top100');await t.pumpAndSettle();expect(t.takeException(),isNull);
    final output=Platform.environment['JOBA_REWARD_CAPTURE'];if(output!=null)await t.runAsync(()async{
      final image=await (boundary.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage(pixelRatio:2);
      final bytes=await image.toByteData(format:ui.ImageByteFormat.png);await File(output).writeAsBytes(bytes!.buffer.asUint8List());image.dispose();
    });
    await t.pumpWidget(const SizedBox());
  });
}
