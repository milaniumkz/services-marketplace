import 'dart:async';
import 'server_clock.dart';
import 'session_refresh_lock.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:crypto/crypto.dart';

typedef Json = Map<String, dynamic>;
const uuid = Uuid();

class ApiException implements Exception {
  final String code, message;
  final int status;
  final Json details;
  ApiException(this.code, this.message,
      [this.status = 0, this.details = const {}]);
  bool get accessRedirected => code=='ENTITLEMENT_REQUIRED'&&details['access_redirected']==true;
  @override
  String toString() => message;
}

abstract class SessionVault {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> clear();
}

class SecureSessionVault implements SessionVault {
  final FlutterSecureStorage storage;
  final String key;
  SecureSessionVault(this.key,
      {this.storage = const FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: true),
        iOptions: IOSOptions(
            accessibility: KeychainAccessibility.first_unlock_this_device),
      )});
  @override
  Future<String?> read() => storage.read(key: key);
  @override
  Future<void> write(String value) => storage.write(key: key, value: value);
  @override
  Future<void> clear() => storage.delete(key: key);
}

/// One client per country endpoint. Never redirects credentials to another region.
class JobaApi extends ChangeNotifier {
  final Uri base;
  final http.Client transport;
  final SessionVault vault;
  Json? session;
  Future<void>? _refreshing;
  Future<void> _vaultQueue = Future.value();
  int _generation = 0;
  final Map<String, Future<dynamic>> _pendingReads = {};
  final Map<String, String> _retryKeys = {};
  final Map<String, Json> _pendingUploads = {};
  bool _sessionExpired = false;
  bool get sessionExpired => _sessionExpired;
  bool disposed = false;
  bool persistSession = true;
  bool Function()? onAccessRequired;
  final ServerClock clock;
  String? _serverTime;
  String? get serverTime => _serverTime;
  set serverTime(String? value) {
    final sample = DateTime.tryParse(value ?? '');
    if (sample == null || !sample.isUtc) return;
    final previous = DateTime.tryParse(_serverTime ?? '');
    if (previous == null || !sample.isBefore(previous)) _serverTime = value;
    clock.synchronize(value);
  }

  JobaApi(String endpoint,
      {http.Client? transport, SessionVault? vault, ServerClock? clock})
      : clock = clock ?? ServerClock(),
        base = Uri.parse(endpoint),
        transport = transport ?? http.Client(),
        vault = vault ?? SecureSessionVault('joba.session.$endpoint') {
    if (!['http', 'https'].contains(base.scheme) ||
        base.host.isEmpty ||
        base.userInfo.isNotEmpty ||
        base.hasQuery ||
        base.hasFragment) {
      throw ArgumentError('Invalid JOBA API endpoint');
    }
    if (kReleaseMode && base.scheme != 'https') {
      throw ArgumentError('Release builds require HTTPS');
    }
  }
  String? get accessToken => session?['access_token'];
  bool get authenticated => accessToken != null;
  int get sessionGeneration => _generation;
  Uri url(String path, [Json query = const {}]) => Uri.parse(
          '${base.toString().replaceFirst(RegExp(r"/$"), "")}/api/v1$path')
      .replace(
          queryParameters:
              query.isEmpty ? null : query.map((k, v) => MapEntry(k, '$v')));

  Future<void> restore({bool refreshSession = true}) async {
    final saved = await vault.read();
    if (saved == null) return;
    try {
      session = jsonDecode(saved) as Json;
    } catch (_) {
      await vault.clear();
      session = null;
      return;
    }
    if (!refreshSession) return;
    try {
      await refresh();
    } on ApiException catch (e) {
      if (e.status != 401) rethrow;
    }
  }

  Future<void> signIn(Json credentials, {bool register = false}) async {
    final generation = ++_generation;
    final result = await request(register ? '/auth/register' : '/auth/login',
        method: 'POST', body: credentials, authenticated: false);
    await _save(result as Json, generation);
  }

  Future<void> _vaultOperation(Future<void> Function() operation) {
    final pending = _vaultQueue.then((_) => operation());
    _vaultQueue = pending.catchError((Object _) {});
    return pending;
  }

  Future<void> _save(Json value, int generation) async {
    if (disposed || generation != _generation)
      throw ApiException(
          'SESSION_SUPERSEDED', 'Сессия изменилась. Повторите вход', 401);
    await _vaultOperation(() async {
      if (persistSession && generation == _generation)
        await vault.write(jsonEncode(value));
    });
    if (disposed || generation != _generation)
      throw ApiException(
          'SESSION_SUPERSEDED', 'Сессия изменилась. Повторите вход', 401);
    session = value;
    _sessionExpired = false;
    if (!disposed) notifyListeners();
  }

  Future<void> refresh() {
    if (_refreshing != null) return _refreshing!;
    late Future<void> pending;
    final owner = session?['user']?['id'] ?? 'unknown',
        generation = _generation;
    pending = withSessionRefreshLock('joba.refresh:$base:$owner', () async {
      if (generation != _generation || disposed) {
        throw ApiException('TOKEN_EXPIRED', 'Сессия изменилась', 401);
      }
      await _rotate();
    }).whenComplete(() {
      if (identical(_refreshing, pending)) _refreshing = null;
    });
    _refreshing = pending;
    return pending;
  }

  Future<void> _rotate() async {
    final generation = _generation;
    if (disposed) return;
    if (persistSession) {
      final saved = await vault.read();
      if (generation != _generation || disposed) {
        throw ApiException('TOKEN_EXPIRED', 'Сессия изменилась', 401);
      }
      if (saved != null) {
        Json? latest;
        try {
          final value = jsonDecode(saved);
          if (value is Map) latest = Map<String, dynamic>.from(value);
        } catch (_) {}
        if (latest?['user']?['id'] != null &&
            session?['user']?['id'] != null &&
            latest!['user']['id'] != session!['user']['id']) {
          await forget(expired: true);
          throw ApiException(
              'SESSION_SUPERSEDED', 'В другом окне открыт другой аккаунт', 409);
        }
        if (latest?['user']?['id'] == session?['user']?['id'] &&
            latest?['refresh_token'] != null) {
          if (latest!['refresh_token'] != session?['refresh_token']) {
            await _save(latest, generation);
            return;
          }
          if (latest['refresh_request_id'] is String)
            session = {
              ...session!,
              'refresh_request_id': latest['refresh_request_id']
            };
        }
      }
    }
    final token = session?['refresh_token'];
    if (token == null) {
      if (authenticated) await forget(expired: true);
      throw ApiException('TOKEN_EXPIRED', 'Войдите в аккаунт', 401);
    }
    try {
      final requestId = session?['refresh_request_id'] is String
          ? session!['refresh_request_id'] as String
          : uuid.v4();
      session = {...session!, 'refresh_request_id': requestId};
      await _vaultOperation(() async {
        if (persistSession && generation == _generation)
          await vault.write(jsonEncode(session));
      });
      if (generation != _generation || disposed) {
        throw ApiException('TOKEN_EXPIRED', 'Сессия изменилась', 401);
      }
      final result = await request('/auth/refresh',
          method: 'POST',
          body: {'refresh_token': token, 'request_id': requestId},
          authenticated: false);
      await _save(result as Json, generation);
    } on ApiException catch (e) {
      if (e.status == 401 &&
          generation == _generation &&
          ['TOKEN_EXPIRED', 'UNAUTHENTICATED', 'REFRESH_REPLAY']
              .contains(e.code)) await forget(expired: true);
      rethrow;
    }
  }

  Future<void> forget({bool expired = false}) async {
    final previousOwner = session?['user']?['id'];
    _sessionExpired = expired;
    _generation++;
    _refreshing = null;
    session = null;
    _pendingReads.clear();
    _retryKeys.clear();
    _pendingUploads.clear();
    await _vaultOperation(() async {
      final saved = await vault.read();
      if (previousOwner != null && saved != null) {
        try {
          final value = jsonDecode(saved);
          if (value is Map &&
              value['user'] is Map &&
              value['user']['id'] != previousOwner) return;
        } catch (_) {}
      }
      await vault.clear();
    });
    persistSession = true;
    if (!disposed) notifyListeners();
  }

  Future<void> setPersistence(bool enabled) async {
    persistSession = enabled;
    await _vaultOperation(() async {
      if (enabled && session != null) {
        await vault.write(jsonEncode(session));
      } else {
        await vault.clear();
      }
    });
  }

  Future<void> logout() async {
    // A failed logout is surfaced; it is not reported as a revoked server session.
    await request('/auth/logout', method: 'POST');
    await forget();
  }

  Future<dynamic> request(String path,
      {String method = 'GET',
      Json? body,
      Json query = const {},
      String? key,
      bool authenticated = true,
      String? capability}) {
    final uri = url(path, query);
    if (method != 'GET') {
      if (key != null || !authenticated)
        return _send(uri, method, body, key ?? uuid.v4(), authenticated,
            capability: capability);
      final scope = sha256
          .convert(utf8.encode(
              '${session?['user']?['id']}:$method:$uri:${jsonEncode(body)}'))
          .toString();
      if (_retryKeys.length > 500) _retryKeys.remove(_retryKeys.keys.first);
      final retryKey = _retryKeys.putIfAbsent(scope, uuid.v4);
      return _send(uri, method, body, retryKey, authenticated,
              capability: capability)
          .then((result) {
        _retryKeys.remove(scope);
        return result;
      }, onError: (Object error, StackTrace stack) {
        if (error is ApiException &&
            error.status > 0 &&
            error.status < 500 &&
            error.status != 429) _retryKeys.remove(scope);
        Error.throwWithStackTrace(error, stack);
      });
    }
    // Coalesce concurrent reads without retaining private responses on disk.
    final scope = '${capability ?? accessToken ?? "anonymous"}:$uri';
    return _pendingReads.putIfAbsent(
        scope,
        () => _send(uri, method, body, null, authenticated,
                    capability: capability)
                .whenComplete(() {
              _pendingReads.remove(scope);
            }));
  }

  Future<dynamic> _send(
      Uri uri, String method, Json? body, String? key, bool authenticated,
      {bool rotated = false,
      int authRetries = 0,
      String? capability,
      int? sessionGeneration}) async {
    final generation = sessionGeneration ?? _generation;
    if (authenticated && capability == null && generation != _generation)
      throw ApiException(
          'SESSION_SUPERSEDED', 'Сессия изменилась. Повторите вход', 401);
    if (authenticated && !this.authenticated)
      throw ApiException('TOKEN_EXPIRED', 'Войдите в аккаунт', 401);
    final sentAccessToken = accessToken;
    final request = http.Request(method, uri)..followRedirects = false;
    request.headers.addAll({
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      if (authenticated) 'Authorization': 'Bearer $sentAccessToken',
      if (capability != null) 'Authorization': 'Bearer $capability',
      if (key != null) 'Idempotency-Key': key
    });
    if (method != 'GET') request.body = jsonEncode(body ?? {});
    http.Response response;
    try {
      response = await http.Response.fromStream(await transport
              .send(request)
              .timeout(const Duration(seconds: 20)))
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw ApiException('TIMEOUT',
          'Сервер не ответил. Проверьте соединение и повторите запрос.');
    } on http.ClientException {
      throw ApiException(
          'OFFLINE', 'Нет соединения с сервером. Проверьте сеть.');
    }
    if (authenticated && capability == null && generation != _generation)
      throw ApiException(
          'SESSION_SUPERSEDED', 'Сессия изменилась. Повторите вход', 401);
    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      throw ApiException('INVALID_RESPONSE', 'Сервер вернул некорректный ответ',
          response.statusCode);
    }
    if (decoded is! Map)
      throw ApiException('INVALID_RESPONSE', 'Сервер вернул некорректный ответ',
          response.statusCode);
    final responseError =
        decoded['error'] is Map ? decoded['error'] as Map : const {};
    final errorCode = responseError['code'];
    if (response.statusCode == 401 &&
        authenticated &&
        capability == null &&
        errorCode == 'TOKEN_EXPIRED' &&
        sentAccessToken != accessToken) {
      if (authRetries >= 3)
        throw ApiException(
            'SESSION_UPDATING', 'Сессия обновляется. Повторите действие.', 503);
      return _send(uri, method, body, key, authenticated,
          rotated: rotated,
          authRetries: authRetries + 1,
          capability: capability,
          sessionGeneration: generation);
    }
    if (response.statusCode == 401 &&
        authenticated &&
        capability == null &&
        errorCode == 'TOKEN_EXPIRED' &&
        !rotated) {
      await refresh();
      return _send(uri, method, body, key, authenticated,
          rotated: true, capability: capability, sessionGeneration: generation);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 401 &&
          authenticated &&
          capability == null &&
          ['TOKEN_EXPIRED', 'UNAUTHENTICATED', 'REFRESH_REPLAY']
              .contains(errorCode)) await forget(expired: true);
      final details=responseError['details'] is Map?Map<String,dynamic>.from(responseError['details']):<String,dynamic>{};
      if(errorCode=='ENTITLEMENT_REQUIRED'&&onAccessRequired?.call()==true)details['access_redirected']=true;
      throw ApiException(
          responseError['code'] ?? 'SERVER_ERROR',
          responseError['message'] ?? 'Не удалось выполнить запрос',
          response.statusCode,
          details);
    }
    final metadata = decoded['meta'];
    final timestamp = metadata is Map ? metadata['server_time'] : null;
    if (timestamp is String) serverTime = timestamp;
    return decoded['data'];
  }

  String? _authCode(String body) {
    try {
      final value = jsonDecode(body);
      return value is Map && value['error'] is Map
          ? value['error']['code'] as String?
          : null;
    } catch (_) {
      return null;
    }
  }

  Future<Json> upload(Uint8List bytes, String mime, String purpose,
      {String? verificationId}) async {
    final generation = _generation;
    final digest = await compute(_uploadDigest, bytes);
    void checkSession() {
      if (disposed || generation != _generation)
        throw ApiException(
            'SESSION_SUPERSEDED', 'Сессия изменилась. Повторите вход', 401);
    }

    checkSession();
    final fingerprint =
        '${session?['user']?['id']}:$purpose:$mime:$verificationId:$digest';
    Json? record = _pendingUploads[fingerprint];
    if (record != null) {
      try {
        record = await request('/uploads/${record['id']}/metadata') as Json;
      } on ApiException catch (error) {
        if (error.status != 404) rethrow;
        record = null;
        _pendingUploads.remove(fingerprint);
      }
    }
    checkSession();
    record ??= await request('/uploads/initiate', method: 'POST', body: {
      'size': bytes.length,
      'mime': mime,
      'purpose': purpose,
      if (verificationId != null) 'verification_id': verificationId,
    }) as Json;
    checkSession();
    Json current = record;
    _pendingUploads[fingerprint] = current;
    while (_pendingUploads.length > 20)
      _pendingUploads.remove(_pendingUploads.keys.first);
    final id = current['id'];
    if (current['status'] == 'initiated') {
      final key = uuid.v4();
      String? uploadAccessToken;
      Future<http.Response> put() async {
        checkSession();
        uploadAccessToken = accessToken;
        final request = http.Request('PUT', url('/uploads/$id/content'))
          ..followRedirects = false;
        request.headers.addAll({
          'Authorization': 'Bearer $uploadAccessToken',
          'Content-Type': 'application/octet-stream',
          'Idempotency-Key': key
        });
        request.bodyBytes = bytes;
        try {
          return await http.Response.fromStream(await transport.send(request))
              .timeout(const Duration(seconds: 60));
        } on TimeoutException {
          throw ApiException('TIMEOUT',
              'Сервер не ответил. Проверьте соединение и повторите запрос.');
        } on http.ClientException {
          throw ApiException(
              'OFFLINE', 'Нет соединения с сервером. Проверьте сеть.');
        }
      }

      var response = await put();
      checkSession();
      for (var attempt = 0;
          response.statusCode == 401 && attempt < 3;
          attempt++) {
        final error = _authCode(response.body);
        if (error != 'TOKEN_EXPIRED') break;
        if (uploadAccessToken == accessToken) await refresh();
        response = await put();
        checkSession();
      }
      checkSession();
      if (response.statusCode != 200 && response.statusCode != 201) {
        final data = jsonDecode(response.body);
        throw ApiException(
            data['error']?['code'] ?? 'UPLOAD_FAILED',
            data['error']?['message'] ?? 'Загрузка не удалась',
            response.statusCode);
      }
      current = {...current, 'status': 'uploaded'};
    }
    if (current['status'] == 'uploaded') {
      try {
        current =
            await request('/uploads/$id/finalize', method: 'POST') as Json;
      } on ApiException catch (error) {
        if (!['TIMEOUT', 'OFFLINE'].contains(error.code)) rethrow;
        current = await request('/uploads/$id/metadata') as Json;
      }
    }
    final deadline = DateTime.now().add(const Duration(minutes: 2));
    while (['processing', 'scanning'].contains(current['status']) &&
        DateTime.now().isBefore(deadline)) {
      checkSession();
      if (current['failure_code'] != null)
        throw ApiException(current['failure_code'],
            'Файл ещё не прошёл безопасную проверку.', 503);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      current = await request('/uploads/$id/metadata') as Json;
    }
    checkSession();
    if (current['status'] != 'clean') {
      if (['infected', 'rejected', 'expired'].contains(current['status']))
        _pendingUploads.remove(fingerprint);
      throw ApiException(
          'UNSAFE_UPLOAD', 'Файл ещё не прошёл безопасную проверку.');
    }
    _pendingUploads.remove(fingerprint);
    return current;
  }

  Future<Uint8List> download(String id,
      {bool rotated = false,
      String variant = 'original',
      int? sessionGeneration}) async {
    final generation = sessionGeneration ?? _generation;
    void guard() {
      if (disposed || generation != _generation || !authenticated)
        throw ApiException(
            'SESSION_SUPERSEDED', 'Сессия изменилась. Повторите вход', 401);
    }

    guard();
    final sentAccessToken = accessToken;
    final req =
        http.Request('GET', url('/uploads/$id/download', {'variant': variant}))
          ..followRedirects = false
          ..headers['Authorization'] = 'Bearer $sentAccessToken';
    late http.Response response;
    try {
      response = await transport
          .send(req)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw ApiException('TIMEOUT', 'Сервис не ответил вовремя');
    } on http.ClientException {
      throw ApiException('OFFLINE', 'Нет соединения с сервером');
    }
    guard();
    if (response.statusCode == 401 &&
        !rotated &&
        _authCode(response.body) == 'TOKEN_EXPIRED') {
      if (sentAccessToken == accessToken) await refresh();
      guard();
      return download(id,
          rotated: true, variant: variant, sessionGeneration: generation);
    }
    if (response.statusCode != 200)
      throw ApiException(
          'DOWNLOAD_UNAVAILABLE', 'Файл недоступен', response.statusCode);
    return response.bodyBytes;
  }

  Future<void> downloadToSink(String id, StreamConsumer<List<int>> sink,
      {void Function(int, int?)? onProgress,
      bool rotated = false,
      int? sessionGeneration}) async {
    final generation = sessionGeneration ?? _generation;
    void guard() {
      if (disposed || generation != _generation || !authenticated)
        throw ApiException(
            'SESSION_SUPERSEDED', 'Сессия изменилась. Повторите вход', 401);
    }

    guard();
    final sentAccessToken = accessToken;
    final request = http.Request('GET', url('/uploads/$id/download'))
      ..followRedirects = false
      ..headers['Authorization'] = 'Bearer $sentAccessToken';
    late http.StreamedResponse response;
    try {
      response =
          await transport.send(request).timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw ApiException('TIMEOUT', 'Сервис не ответил вовремя');
    } on http.ClientException {
      throw ApiException('OFFLINE', 'Нет соединения с сервером');
    }
    try {
      guard();
    } catch (_) {
      await response.stream.listen(null).cancel();
      rethrow;
    }
    if (response.statusCode == 401 && !rotated) {
      final body = await response.stream
          .bytesToString()
          .timeout(const Duration(seconds: 30));
      if (_authCode(body) != 'TOKEN_EXPIRED')
        throw ApiException('DOWNLOAD_UNAVAILABLE', 'Файл недоступен', 401);
      if (sentAccessToken == accessToken) await refresh();
      guard();
      return downloadToSink(id, sink,
          onProgress: onProgress, rotated: true, sessionGeneration: generation);
    }
    if (response.statusCode != 200) {
      await response.stream.drain<void>().timeout(const Duration(seconds: 30));
      throw ApiException(
          'DOWNLOAD_UNAVAILABLE', 'Файл недоступен', response.statusCode);
    }
    var received = 0;
    try {
      await sink.addStream(
          response.stream.timeout(const Duration(seconds: 30)).map((chunk) {
        guard();
        received += chunk.length;
        onProgress?.call(received, response.contentLength);
        return chunk;
      }));
    } on TimeoutException {
      throw ApiException('TIMEOUT', 'Сервис не ответил вовремя');
    }
    guard();
  }

  @override
  void dispose() {
    disposed = true;
    transport.close();
    super.dispose();
  }
}

List<Json> items(dynamic value) =>
    ((value as Json?)?['items'] as List? ?? []).cast<Json>();

String _uploadDigest(Uint8List bytes) => sha256.convert(bytes).toString();
