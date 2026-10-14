import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A shown system chooser does not establish that a message was sent.
Future<bool> shareInvitation(String text) async {
  if (!kIsWeb &&
      [TargetPlatform.android, TargetPlatform.iOS]
          .contains(defaultTargetPlatform)) {
    await const MethodChannel('joba.share')
        .invokeMethod<void>('text', {'text': text});
    return true;
  }
  await Clipboard.setData(ClipboardData(text: text));
  return false;
}
