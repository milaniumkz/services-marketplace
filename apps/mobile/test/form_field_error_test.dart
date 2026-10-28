import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:services_marketplace/core/api.dart';
import 'package:services_marketplace/core/widgets.dart';
import 'package:services_marketplace/core/field_validation.dart';
void main(){
 testWidgets('server error highlights matching field and clears after correction',(t)async{
  var calls=0;
  await t.pumpWidget(MaterialApp(home:Scaffold(body:ActionForm(fields:const[InputSpec('description','Описание задачи',initial:'Коротко')],submit:(v)async{calls++;if(calls==1)throw ApiException('VALIDATION_ERROR','Проверьте поле description',400,{'field':'description','min':20,'max':5000});}))));
  await t.tap(find.text('Сохранить'));await t.pumpAndSettle();expect(find.textContaining('Добавьте ещё 13'),findsOneWidget);expect(t.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,true);
  await t.enterText(find.byType(TextFormField),'Подробное описание задачи для исполнителя');await t.pumpAndSettle();expect(find.textContaining('Добавьте ещё 13'),findsNothing);
  await t.ensureVisible(find.text('Сохранить'));await t.tap(find.text('Сохранить'));await t.pumpAndSettle();expect(calls,2);
 });
 testWidgets('client error explains exact minimum and blocks submission',(t)async{
  var sent=false;await t.pumpWidget(MaterialApp(home:Scaffold(body:ActionForm(fields:[InputSpec('description','Описание задачи',initial:'Мало',validate:(v)=>textLengthProblem(v,20,5000,'Описание задачи'))],submit:(v)async{sent=true;}))));
  await t.tap(find.text('Сохранить'));await t.pumpAndSettle();expect(sent,false);expect(find.textContaining('Сейчас 4. Добавьте ещё 16'),findsOneWidget);
 });
}
