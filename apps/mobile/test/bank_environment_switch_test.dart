import 'package:flutter_test/flutter_test.dart';
import 'package:services_marketplace/screens/bank_navigation.dart';
void main(){test('the same compiled client accepts server-selected sandbox/live BCC and VTB entrypoints',(){
 for(final url in ['https://vtbkz.rbsuat.com/payment/merchants/joba/payment.html?mdOrder=fixture','https://payment.vtb.kz/payment/merchants/joba/payment.html?mdOrder=fixture','https://test3ds.bcc.kz:5445/cgi-bin/cgi_link','https://3dsecure.bcc.kz/webview','https://joba.com.kz/api/v1/public/billing/bcc/form?payment_id=00000000-0000-4000-8000-000000000001&token=${'a'*64}']){expect(trustedBankEntry(Uri.parse(url)),isTrue,reason:url);}
 for(final url in ['http://payment.vtb.kz/payment/x','https://payment.vtb.kz.evil.invalid/payment/x','https://3dsecure.bcc.kz:8443/webview','https://user:pass@3dsecure.bcc.kz/webview']){expect(trustedBankEntry(Uri.parse(url)),isFalse,reason:url);}
 });}
