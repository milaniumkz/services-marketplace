import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:services_marketplace/core/api.dart';
import 'package:services_marketplace/core/currency.dart';
import 'package:services_marketplace/screens/commerce_states.dart';
import 'widget_test.dart' show MemoryVault, ok;

void main() {
  testWidgets('RUB checkout discloses frozen KZT bank amount and official rate before consent', (t) async {
    final offer = {'id':'fx-quote','plan':'customer','provider':'vtb','hosted_checkout':true,'product_type':'subscription','amount_minor':50000,'currency':'RUB','duration_days':30,'bank_settlement':{'bank_amount_minor':279500,'bank_currency':'KZT','rate':'5.59','units':1,'rate_date':'2026-11-27'}};
    final api=JobaApi('https://isolated.example',vault:MemoryVault(),transport:MockClient((r)async=>ok(r.url.path.endsWith('/billing/offers')?{'items':[offer]}:{'items':[]})));
    addTearDown(api.dispose);api.session={'access_token':'isolated','user':{'id':'russian-fixture','country':'RU','active_role':'customer'}};
    await t.pumpWidget(MaterialApp(home:Scaffold(body:CommerceStateScreen(api:api,mode:'checkout',onGo:(_,__){}))));await t.pumpAndSettle();
    await t.scrollUntilVisible(find.text('На странице банка'),200);
    expect(find.text(formatMoney(279500,'KZT','en')),findsOneWidget);
    expect(find.text('Курс НБ РК'),findsOneWidget);
    expect(find.textContaining('5.59'),findsOneWidget);
    expect(t.takeException(),isNull);
  });
}
