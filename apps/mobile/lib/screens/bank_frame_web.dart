import 'dart:js_interop';
import 'package:web/web.dart' as web;

/// Bank content may submit forms and run 3DS scripts, but cannot navigate JOBA
/// or create another tab. Card fields remain on the bank's origin.
web.HTMLIFrameElement createBankFrame(Uri entry) {
  return web.HTMLIFrameElement()
    ..title = 'Защищённая форма оплаты банка'
    ..setAttribute('data-joba-bank-frame', 'true')
    ..setAttribute('sandbox', 'allow-forms allow-scripts allow-same-origin')
    ..setAttribute('allow', 'payment')
    ..referrerPolicy = 'no-referrer'
    ..style.border = '0'
    ..style.width = '100%'
    ..style.height = '100%'
    ..style.backgroundColor = '#ffffff'
    ..src = entry.toString();
}

bool isOwnBankReturn(web.MessageEvent event, web.HTMLIFrameElement frame,
    String paymentId, String origin) {
  if (frame.contentWindow == null ||
      event.origin != origin ||
      event.source != frame.contentWindow) return false;
  try {
    final data = event.data.dartify();
    return data is Map &&
        data['type'] == 'joba.bank.return' &&
        data['payment_id'] == paymentId;
  } catch (_) {
    return false;
  }
}
