@TestOn('browser')
library;

import 'dart:js_interop';
import 'package:web/web.dart' as web;
import 'package:flutter_test/flutter_test.dart';
import 'package:services_marketplace/screens/bank_frame_web.dart';

void main() {
  test('bank stays in its frame and accepts only its own scoped return', () {
    final frame = createBankFrame(Uri.parse('about:blank'));
    final other = createBankFrame(Uri.parse('about:blank'));
    web.document.body!.append(frame);
    web.document.body!.append(other);
    addTearDown(() {
      frame.remove();
      other.remove();
    });
    expect(frame.referrerPolicy, 'no-referrer');
    expect(frame.getAttribute('sandbox'),
        'allow-forms allow-scripts allow-same-origin');
    expect(
        frame.getAttribute('sandbox'), isNot(contains('allow-top-navigation')));
    expect(frame.getAttribute('sandbox'), isNot(contains('allow-popups')));
    web.MessageEvent message(
            {String origin = 'https://joba.com.kz',
            String id = 'own',
            String type = 'joba.bank.return',
            bool foreign = false}) =>
        web.MessageEvent(
            'message',
            web.MessageEventInit(
                origin: origin,
                source: foreign ? other.contentWindow : frame.contentWindow,
                data: {'type': type, 'payment_id': id}.jsify()));
    expect(
        isOwnBankReturn(message(), frame, 'own', 'https://joba.com.kz'), true);
    for (final event in [
      message(origin: 'https://bank.example'),
      message(id: 'other'),
      message(type: 'paid'),
      message(foreign: true)
    ]) {
      expect(
          isOwnBankReturn(event, frame, 'own', 'https://joba.com.kz'), false);
    }
  });
}
