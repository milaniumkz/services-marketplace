import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:services_marketplace/core/crash_report_queue.dart';

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('joba-crash-test-');
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });
  CrashReportQueue open(http.Client client) => CrashReportQueue(
      file: File('${directory.path}/queue.json'),
      transport: client,
      endpoint:
          Uri.parse('https://isolated.example/api/v1/public/mobile-crashes'),
      metadata: {'platform': 'android', 'app_version': '1.0.3', 'build': '5'});
  test(
      'offline crash survives restart, strips credentials, and only clears after matching durable server acknowledgement',
      () async {
    final first =
        open(MockClient((_) async => throw const SocketException('offline')));
    first.add({
      'kind': 'flutter',
      'fatal': true,
      'screen': 'create',
      'message':
          'password=secret-value +77479275358 test@example.com Bearer abcdef https://private.test?a=1',
      'stack': '#0 createOrder (package:app/order.dart:12:5)'
    });
    await first.flush();
    expect(first.pending, 1);
    first.close();
    final bytes = File('${directory.path}/queue.json').readAsStringSync();
    expect(bytes, isNot(contains('secret-value')));
    expect(bytes, isNot(contains('77479275358')));
    expect(bytes, isNot(contains('test@example.com')));
    expect(bytes, isNot(contains('abcdef')));
    expect(bytes, isNot(contains('private.test')));
    final stored = jsonDecode(bytes), id = stored['reports'][0]['id'];
    var correct = false;
    final second = open(MockClient((request) async {
      expect(request.headers.containsKey('authorization'), false);
      expect(jsonDecode(request.body)['id'], id);
      return http.Response(
          jsonEncode({
            'data': {'accepted': true, 'id': correct ? id : 'wrong'}
          }),
          200);
    }));
    expect(second.pending, 1);
    await second.flush();
    expect(second.pending, 1);
    correct = true;
    await second.flush();
    expect(second.pending, 0);
    second.close();
    final restored = open(MockClient(
        (_) async => throw StateError('no pending report should be sent')));
    expect(restored.pending, 0);
    expect(restored.installationId, stored['installation_id']);
    await restored.flush();
    restored.close();
  });
  test(
      'concurrent flushes do not duplicate deliveries and new reports are retained during an in-flight send',
      () async {
    final gate = Completer<void>();
    var calls = 0;
    final queue = open(MockClient((request) async {
      calls++;
      if (calls == 1) await gate.future;
      return http.Response(
          jsonEncode({
            'data': {'accepted': true, 'id': jsonDecode(request.body)['id']}
          }),
          200);
    }));
    queue.add({'kind': 'flutter', 'fatal': true, 'message': 'first'});
    final sending = queue.flush();
    await Future<void>.delayed(Duration.zero);
    queue.add({'kind': 'android_java', 'fatal': true, 'message': 'second'});
    await queue.flush();
    expect(calls, 1);
    gate.complete();
    await sending;
    expect(calls, 2);
    expect(queue.pending, 0);
    queue.close();
  });
  test(
      'bounded disk spool prioritizes fatal reports and rejects duplicate native report IDs',
      () async {
    final queue = open(MockClient((_) async => http.Response('offline', 503)));
    queue.add({
      'id': 'native-fixed',
      'kind': 'android_java',
      'fatal': true,
      'message': 'original'
    });
    queue.add({
      'id': 'native-fixed',
      'kind': 'android_java',
      'fatal': true,
      'message': 'duplicate'
    });
    expect(queue.pending, 1);
    for (var i = 0; i < 60; i++) {
      queue.add({'kind': 'flutter', 'fatal': false, 'message': 'frame $i'});
    }
    final data =
        jsonDecode(File('${directory.path}/queue.json').readAsStringSync());
    expect(queue.pending, 50);
    expect(
        (data['reports'] as List)
            .where((r) => r['id'] == 'native-fixed')
            .single['message'],
        'original');
    queue.close();
  });
  test('an interrupted atomic write restores a valid temporary snapshot and ignores a partial one', () async {
    final file = File('${directory.path}/queue.json');
    file.writeAsStringSync(jsonEncode({'installation_id':'old','reports':[]}));
    final temporary=File('${file.path}.tmp');
    temporary.writeAsStringSync(jsonEncode({'installation_id':'new','reports':[{'id':'crash-before-rename','kind':'android_java','fatal':true}]}));
    final restored=open(MockClient((_)async=>http.Response('offline',503)));
    expect(restored.pending,1);expect(restored.installationId,'new');restored.close();
    temporary.writeAsStringSync('{partial');
    final fallback=open(MockClient((_)async=>http.Response('offline',503)));
    expect(fallback.pending,0);expect(fallback.installationId,'old');fallback.close();
  });

}
