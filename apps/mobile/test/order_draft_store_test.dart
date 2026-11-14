import 'package:flutter_test/flutter_test.dart';
import 'package:services_marketplace/core/order_draft_store.dart';
import 'widget_test.dart' show MemoryVault;

void main(){
 test('encrypted device drafts survive recreation, serialize writes and stay isolated by UUID and country',()async{
  final storage=<String,MemoryVault>{};
  MemoryVault vault(String key)=>storage.putIfAbsent(key,MemoryVault.new);
  final first=OrderDraftStore(vault:vault);
  final scope='KZ:https://joba.com.kz:user-1';
  await Future.wait([first.save(scope,{'values':{'title':'Первый'}}),first.save(scope,{'values':{'title':'Итоговый черновик'},'photos':['photo-1'],'location':{'address':'Личный адрес'}})]);
  final restored=OrderDraftStore(vault:vault);
  expect((await restored.read(scope))!['values']['title'],'Итоговый черновик');
  expect((await restored.read(scope))!['photos'],['photo-1']);
  expect(await restored.read('BY:https://joba.com.kz:user-1'),isNull);
  expect(await restored.read('KZ:https://joba.com.kz:user-2'),isNull);
  await restored.clear(scope);expect(await first.read(scope),isNull);
 });
 test('invalid stored draft does not prevent opening the order form',()async{
  final vault=MemoryVault()..value='invalid';
  expect(await OrderDraftStore(vault:(_)=>vault).read('scope'),isNull);
 });
}
