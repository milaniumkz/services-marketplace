import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:services_marketplace/core/api.dart';

class Vault implements SessionVault {
  String? value;
  Future<String?> read() async => value;
  Future<void> write(String text) async {
    value = text;
  }

  Future<void> clear() async {
    value = null;
  }
}

http.Response ok(dynamic data) => http.Response(jsonEncode({'data': data}), 200,
    headers: {'content-type': 'application/json'});
http.Response expired() => http.Response(
    '{"error":{"code":"TOKEN_EXPIRED","message":"expired"}}', 401);
Json credentials(String access, String refresh) => {
      'access_token': access,
      'refresh_token': refresh,
      'user': {'id': 'same-owner'}
    };
Future<void> until(bool Function() ready) async {
  for (var i = 0; i < 5000 && !ready(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  expect(ready(), isTrue);
}

void main() {
  test(
      'late 401 from a parallel request reuses the replacement token without a second rotation',
      () async {
    final held = Completer<http.Response>();
    var refreshes = 0;
    bool sent = false;
    final api = JobaApi('https://isolated.example', vault: Vault(),
        transport: MockClient((request) async {
      if (request.url.path.endsWith('/auth/refresh')) {
        refreshes++;
        return ok(credentials('new', 'r2'));
      }
      if (request.url.path.endsWith('/late') &&
          request.headers['authorization'] == 'Bearer old') {
        sent = true;
        return held.future;
      }
      if (request.headers['authorization'] == 'Bearer old') return expired();
      return ok({'success': true});
    }))
      ..session = credentials('old', 'r1');
    final late = api.request('/late');
    await until(() => sent);
    expect((await api.request('/me'))['success'], true);
    held.complete(expired());
    expect((await late)['success'], true);
    expect(refreshes, 1);
    expect(api.accessToken, 'new');
    expect(api.authenticated, isTrue);
    api.dispose();
  });
  test(
      'separate clients sharing a persisted session serialize and adopt one rotation',
      () async {
    final vault = Vault()..value = jsonEncode(credentials('old', 'r1'));
    var refreshes = 0;
    final transport = MockClient((request) async {
      refreshes++;
      await Future<void>.delayed(const Duration(milliseconds: 5));
      return ok(credentials('new', 'r2'));
    });
    final first =
        JobaApi('https://isolated.example', vault: vault, transport: transport)
          ..session = credentials('old', 'r1');
    final second =
        JobaApi('https://isolated.example', vault: vault, transport: transport)
          ..session = credentials('old', 'r1');
    await Future.wait([first.refresh(), second.refresh()]);
    expect(refreshes, 1);
    expect(first.accessToken, 'new');
    expect(second.accessToken, 'new');
    first.dispose();
    second.dispose();
  });
  test('lost response retains a persisted retry ID across app restoration',
      () async {
    final vault = Vault()..value = jsonEncode(credentials('old', 'r1'));
    String? requestId;
    var attempts = 0;
    final transport = MockClient((request) async {
      final body = jsonDecode(request.body);
      if (attempts++ == 0) {
        requestId = body['request_id'];
        throw http.ClientException('isolated response lost');
      }
      expect(body['request_id'], requestId);
      return ok(credentials('new', 'r2'));
    });
    final first =
        JobaApi('https://isolated.example', vault: vault, transport: transport)
          ..session = credentials('old', 'r1');
    await expectLater(first.refresh(), throwsA(isA<ApiException>()));
    expect(first.authenticated, isTrue);
    expect(jsonDecode(vault.value!)['refresh_request_id'], requestId);
    first.dispose();
    final restored =
        JobaApi('https://isolated.example', vault: vault, transport: transport);
    await restored.restore();
    expect(restored.accessToken, 'new');
    expect(jsonDecode(vault.value!).containsKey('refresh_request_id'), isFalse);
    restored.dispose();
  });
  test('an old account cannot clear another account stored by a different tab',
      () async {
    final vault = Vault()
      ..value = jsonEncode({
        'access_token': 'other',
        'refresh_token': 'other-refresh',
        'user': {'id': 'another-owner'}
      });
    final api = JobaApi('https://isolated.example',
        vault: vault,
        transport: MockClient(
            (_) async => throw StateError('must not refresh another account')))
      ..session = credentials('old', 'r1');
    await expectLater(api.refresh(), throwsA(isA<ApiException>()));
    expect(jsonDecode(vault.value!)['user']['id'], 'another-owner');
    expect(api.authenticated, isFalse);
    api.dispose();
  });
  test(
      'selfie bytes retry with a current token when a parallel refresh completes first',
      () async {
    final uploadResponse = Completer<http.Response>();
    var uploadStarted = false, refreshes = 0, puts = 0;
    String? firstKey;
    final api = JobaApi('https://isolated.example', vault: Vault(),
        transport: MockClient((request) async {
      if (request.url.path.endsWith('/auth/refresh')) {
        refreshes++;
        return ok(credentials('new', 'r2'));
      }
      if (request.url.path.endsWith('/uploads/initiate'))
        return ok({'id': 'photo', 'status': 'initiated'});
      if (request.url.path.endsWith('/content')) {
        puts++;
        firstKey ??= request.headers['Idempotency-Key'];
        expect(request.headers['Idempotency-Key'], firstKey);
        if (puts == 1) {
          uploadStarted = true;
          return uploadResponse.future;
        }
        expect(request.headers['authorization'], 'Bearer new');
        return ok({});
      }
      if (request.url.path.endsWith('/finalize'))
        return ok({'id': 'photo', 'status': 'clean'});
      return request.headers['authorization'] == 'Bearer old'
          ? expired()
          : ok({'success': true});
    }))
      ..session = credentials('old', 'r1');
    final uploaded = api.upload(
        Uint8List.fromList([1, 2, 3]), 'image/jpeg', 'identity',
        verificationId: 'verification');
    await until(() => uploadStarted);
    await api.request('/me');
    uploadResponse.complete(expired());
    expect((await uploaded)['status'], 'clean');
    expect(refreshes, 1);
    expect(puts, 2);
    expect(api.authenticated, isTrue);
    api.dispose();
  });
}
