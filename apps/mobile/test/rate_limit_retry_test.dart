import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:services_marketplace/core/api.dart';

void main() {
  test(
      'a rate limit between a lost mutation response and its retry preserves the original command key',
      () async {
    final keys = <String>[], saved = <String, Json>{};
    var attempts = 0, writes = 0;
    final api = JobaApi('https://isolated.example',
        transport: MockClient((request) async {
      final key = request.headers['Idempotency-Key']!;
      keys.add(key);
      attempts++;
      if (attempts == 2)
        return http.Response(
            jsonEncode({
              'error': {
                'code': 'RATE_LIMITED',
                'message': 'Try later',
                'details': {'retry_after_seconds': 30}
              }
            }),
            429);
      final result = saved.putIfAbsent(key, () {
        writes++;
        return {'id': 'stored-command-$writes'};
      });
      if (attempts == 1)
        throw http.ClientException('response lost after commit');
      return http.Response(jsonEncode({'data': result}), 200);
    }))
      ..session = {
        'access_token': 'isolated',
        'user': {'id': 'owner'}
      };
    const body = {'title': 'Owned mutation'};
    await expectLater(api.request('/orders', method: 'POST', body: body),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'OFFLINE')));
    await expectLater(api.request('/orders', method: 'POST', body: body),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 429)));
    final result = await api.request('/orders', method: 'POST', body: body);
    expect(keys.toSet().length, 1);
    expect(writes, 1);
    expect(result['id'], 'stored-command-1');
    api.dispose();
  });
}
