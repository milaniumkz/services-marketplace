import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:services_marketplace/core/share_invitation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'invitation opens the native chooser with the real code and propagates a failure',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    const channel = MethodChannel('joba.share');
    final calls = <MethodCall>[];
    var unavailable = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (unavailable) throw PlatformException(code: 'SHARE_UNAVAILABLE');
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    expect(await shareInvitation('JOBA: isolated-code-37'), true);
    expect(calls.single.method, 'text');
    expect(calls.single.arguments, {'text': 'JOBA: isolated-code-37'});
    unavailable = true;
    await expectLater(shareInvitation('JOBA: isolated-code-37'),
        throwsA(isA<PlatformException>()));
  });
}
