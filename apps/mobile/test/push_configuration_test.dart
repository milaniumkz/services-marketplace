import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import '../lib/core/api.dart';
import '../lib/core/push_notifications.dart';
class Vault implements SessionVault {
  Future<String?> read() async => null;
  Future<void> write(String value) async {}
  Future<void> clear() async {}
}
void main() {
  test('unconfigured Firebase never registers a fabricated token or interrupts a session', () async {
    var registered = false;
    final api = JobaApi('https://isolated.example', vault: Vault(), transport: MockClient((r) async {
      if (r.method == 'POST') registered = true;
      return http.Response(jsonEncode({'data': {'enabled': false, 'platforms': {}}}), 200);
    }))..session = {'access_token': 'isolated', 'user': {'id': 'owner'}};
    final push = JobaPush();
    await push.attach(api);
    expect(push.configured, false);
    expect(api.authenticated, true);
    expect(registered, false);
    await expectLater(push.enable(), throwsA(isA<ApiException>()));
    push.detach();
    await expectLater(push.enable(), throwsA(isA<ApiException>()));
    api.dispose();push.dispose();
  });
}
