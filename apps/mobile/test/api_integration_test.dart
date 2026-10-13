import 'dart:math';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:services_marketplace/core/api.dart';
import 'widget_test.dart' show MemoryVault, RecordingSink;

void main() {
  const endpoint = String.fromEnvironment('JOBA_TEST_API_URL');
  test(
      'Real HTTP register, profile, draft, support, privacy, session rotation and logout',
      () async {
    final api = JobaApi(endpoint, vault: MemoryVault());
    final number = '+7701${(1000000 + Random.secure().nextInt(8999999))}';
    const password = 'Local integration password 2026!';
    await api.signIn({
      'country': 'KZ',
      'phone': number,
      'password': password,
      'display_name': 'Проверка клиента'
    }, register: true);
    final user = await api.request('/me') as Json;
    final categories = items(await api.request('/catalog/categories'));
    final cities = items(await api.request('/geo/cities'));
    final draft = await api.request('/orders', method: 'POST', body: {
      'title': 'Проверка мобильного API',
      'description': 'Реальный запрос из Flutter-клиента к локальному серверу.',
      'category_id': categories.first['id'],
      'city_id': cities.first['id'],
      'budget_amount': 12500,
      'work_mode': 'onsite',
      'attributes': {},
      'upload_ids': []
    }) as Json;
    expect(draft['status'], 'draft');
    final overview = await api.request('/me/overview') as Json;
    expect(overview['orders']['draft'], 1);
    expect(overview['rating']['count'], 0);
    expect(items(await api.request('/me/sessions')).single['current'], true);
    expect(
        items(await api.request('/me/orders'))
            .any((o) => o['id'] == draft['id']),
        true);
    await expectLater(
        api.request('/orders/${draft['id']}/publish',
            method: 'POST', body: {'expected_version': draft['version']}),
        throwsA(isA<ApiException>()));
    final updated = await api.request('/me', method: 'PATCH', body: {
      'expected_version': user['version'],
      'display_name': 'Новое имя',
      'city': cities.first['name']
    }) as Json;
    expect(updated['display_name'], 'Новое имя');
    final image = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAACXBIWXMAAAPoAAAD6AG1e1JrAAAAEklEQVQImWNQib6tEn2bAUIBACMKBWmBjKz3AAAAAElFTkSuQmCC');
    final avatar = await api.upload(image, 'image/png', 'avatar');
    expect(avatar['status'], 'clean');
    final profileWithPhoto = await api.request('/me', method: 'PATCH', body: {
      'expected_version': updated['version'],
      'avatar_id': avatar['id']
    }) as Json;
    expect(profileWithPhoto['avatar_id'], avatar['id']);
    expect((await api.download(avatar['id'])).isNotEmpty, true);

    expect((await api.request('/me/contractor-profile'))['profile'], isNull);
    expect(items(await api.request('/me/assigned-orders')), isEmpty);
    expect(items(await api.request('/me/offers')), isEmpty);
    final thread = await api.request('/support/threads',
        method: 'POST', body: {'subject': 'Проверка поддержки'}) as Json;
    final key = uuid.v4();
    final message = await api.request(
            '/support/threads/${thread['id']}/messages',
            method: 'POST',
            key: key,
            body: {'text': 'Сообщение из Flutter', 'client_message_id': key})
        as Json;
    expect(message['text'], 'Сообщение из Flutter');
    final report = await api.request('/cases', method: 'POST', body: {
      'target_type': 'order',
      'target_id': draft['id'],
      'reason_code': 'other',
      'description': 'Проверка обработки жалобы из приложения'
    }) as Json;
    expect((await api.request('/cases/${report['id']}'))['id'], report['id']);
    final privacy = await api.request('/me/privacy-requests',
        method: 'POST',
        body: {'type': 'export', 'current_password': password}) as Json;
    expect(privacy['status'], 'requested');
    Json exported = privacy;
    for (var attempt = 0; attempt < 50; attempt++) {
      exported =
          await api.request('/me/privacy-requests/${privacy['id']}') as Json;
      if (exported['status'] == 'completed') break;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(exported['status'], 'completed');
    final archive = RecordingSink();
    await api.downloadToSink(exported['upload_id'], archive);
    expect(archive.bytes.take(2).toList(), [0x50, 0x4b]);
    expect(archive.bytes.length, greaterThan(500));

    final old = api.accessToken;
    await api.refresh();
    expect(api.accessToken, isNot(old));
    await api.logout();
    expect(api.authenticated, false);
    api.dispose();
  },
      skip: endpoint.isEmpty
          ? 'Run against an isolated JOBA API with JOBA_TEST_API_URL'
          : false);
}
