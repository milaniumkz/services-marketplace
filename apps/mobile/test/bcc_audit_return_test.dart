import 'package:flutter_test/flutter_test.dart';
import 'package:services_marketplace/screens/bank_navigation.dart';
void main(){
 const id='00000000-0000-4000-8000-000000000001';
 final cases=<String,bool>{
 'https://joba.com.kz/api/v1/public/billing/bcc/return?payment_id=$id':true,
 'https://joba.com.kz:443/api/v1/public/billing/bcc/return?payment_id=$id':true,
 'https://joba.com.kz.evil.example/api/v1/public/billing/bcc/return?payment_id=$id':false,
 'https://evil.example/api/v1/public/billing/bcc/return?payment_id=$id':false,
 'http://joba.com.kz/api/v1/public/billing/bcc/return?payment_id=$id':false,
 'https://joba.com.kz:8443/api/v1/public/billing/bcc/return?payment_id=$id':false,
 'https://joba.com.kz/admin/?payment_id=$id':false,
 'https://joba.com.kz/api/v1/public/billing/bcc/return/extra?payment_id=$id':false,
 'https://joba.com.kz/api/v1/public/billing/bcc/return?payment_id=other':false,
 'https://joba.com.kz/api/v1/public/billing/bcc/return':false,
 'https://user:password@joba.com.kz/api/v1/public/billing/bcc/return?payment_id=$id':false,
 'https://3dsecure.bcc.kz/webview':false,
 'https://test3ds.bcc.kz:5445/cgi-bin/cgi_link':false,
 'https://joba.com.kz/?status=paid':false,
 };
 var n=0;for(final entry in cases.entries){n++;test('BCC-RETURN-${n.toString().padLeft(2,'0')}',()=>expect(bankReturn(Uri.parse(entry.key),id),entry.value));}
}
