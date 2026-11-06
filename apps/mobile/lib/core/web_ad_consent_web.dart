import 'dart:convert';
import 'package:web/web.dart' as web;
void rememberWebAdConsent(bool accepted){try{web.window.localStorage.setItem('joba.web.ads.consent.v1',jsonEncode({'accepted':accepted,'notice_version':1}));}catch(_){}}
bool? rememberedWebAdConsent(){try{final raw=web.window.localStorage.getItem('joba.web.ads.consent.v1');if(raw==null)return null;final value=jsonDecode(raw)['accepted'];return value is bool?value:null;}catch(_){return null;}}
