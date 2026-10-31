import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:services_marketplace/core/design_widgets.dart';
import 'package:services_marketplace/core/navigation_shell.dart';
void main(){
 NavigationState nav({String? placement='home:user'})=>NavigationState(route:'home',executor:false,enabled:true,messages:0,notifications:0,onSelect:(_){},bannerPlacement:placement,banner:placement==null?null:const SizedBox(key:ValueKey('banner'),height:50,child:Text('Реклама')));
 test('shell refreshes a placement change even when the selected navigation tab stays the same',(){expect(nav().sameAs(nav(placement:null)),false);expect(nav().sameAs(nav()),true);});
 testWidgets('banner stays above persistent navigation while content scrolls; keyboard reclaims the ad space',(t)async{
  t.view.physicalSize=const Size(393,852);t.view.devicePixelRatio=1;addTearDown(t.view.resetPhysicalSize);addTearDown(t.view.resetDevicePixelRatio);
  Widget app(double keyboard) => MaterialApp(
    home: const SizedBox(),
    builder: (context, child) => MediaQuery(
      data: MediaQueryData(size: const Size(393,852), viewInsets: EdgeInsets.only(bottom: keyboard)),
      child: NavigationFrame(
        navigation: nav(),
        child: Scaffold(
          body: ListView(
            key: const ValueKey('content'),
            children: List.generate(30, (i) => SizedBox(height: 60, child: Text('Строка $i'))),
          ),
        ),
      ),
    ),
  );
  await t.pumpWidget(app(0));await t.pumpAndSettle();final initial=t.getRect(find.byKey(const ValueKey('banner'))),menu=t.getRect(find.byType(JobaNavigation));expect(initial.height,50);expect(initial.bottom,lessThanOrEqualTo(menu.top));
  await t.drag(find.byKey(const ValueKey('content')),const Offset(0,-300));await t.pumpAndSettle();expect(t.getRect(find.byKey(const ValueKey('banner'))),initial);expect(find.byType(JobaNavigation),findsOneWidget);
  await t.pumpWidget(app(300));await t.pumpAndSettle();expect(find.byKey(const ValueKey('banner')),findsNothing);expect(find.byType(JobaNavigation),findsOneWidget);expect(t.takeException(),isNull);
 });
}
