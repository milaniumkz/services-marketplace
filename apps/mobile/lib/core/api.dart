import 'dart:async';
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
  ApiException(this.code, this.message, [this.status = 0]);
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
  bool disposed = false;
  bool persistSession = true;
  String? serverTime;
  JobaApi(String endpoint, {http.Client? transport, SessionVault? vault})
      : base = Uri.parse(endpoint),
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
    if (!disposed) notifyListeners();
  }

  Future<void> refresh() {
    if (_refreshing != null) return _refreshing!;
    late Future<void> pending;
    pending = _rotate().whenComplete(() {
      if (identical(_refreshing, pending)) _refreshing = null;
    });
    _refreshing = pending;
    return pending;
  }

  Future<void> _rotate() async {
    final generation = _generation;
    final token = session?['refresh_token'];
    if (token == null)
      throw ApiException('TOKEN_EXPIRED', 'Войдите в аккаунт', 401);
    try {
      final result = await request('/auth/refresh',
          method: 'POST', body: {'refresh_token': token}, authenticated: false);
      await _save(result as Json, generation);
    } on ApiException catch (e) {
      if (e.status == 401 && generation == _generation) await forget();
      rethrow;
    }
  }

  Future<void> forget() async {
    _generation++;
    _refreshing = null;
    session = null;
    _pendingReads.clear();
    _retryKeys.clear();
    await _vaultOperation(vault.clear);
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
        if (error is ApiException && error.status > 0 && error.status < 500)
          _retryKeys.remove(scope);
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
      {bool rotated = false, String? capability}) async {
    if (authenticated && !this.authenticated)
      throw ApiException('TOKEN_EXPIRED', 'Войдите в аккаунт', 401);
    final request = http.Request(method, uri)..followRedirects = false;
    request.headers.addAll({
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      if (authenticated) 'Authorization': 'Bearer $accessToken',
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
    if (response.statusCode == 401 && authenticated && !rotated) {
      await refresh();
      // Keep the original idempotency key when replaying a mutation.
      return _send(uri, method, body, key, authenticated, rotated: true);
    }
    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      throw ApiException('INVALID_RESPONSE', 'Сервер вернул некорректный ответ',
          response.statusCode);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 401 && authenticated) await forget();
      throw ApiException(
          decoded['error']?['code'] ?? 'SERVER_ERROR',
          decoded['error']?['message'] ?? 'Не удалось выполнить запрос',
          response.statusCode);
    }
    serverTime = decoded['meta']?['server_time'];
    return decoded['data'];
  }

  Future<Json> upload(Uint8List bytes, String mime, String purpose,
      {String? verificationId}) async {
    final record = await request('/uploads/initiate', method: 'POST', body: {
      'size': bytes.length,
      'mime': mime,
      'purpose': purpose,
      if (verificationId != null) 'verification_id': verificationId,
    }) as Json;
    final key = uuid.v4();
    Future<http.Response> put() async {
      final req = http.Request('PUT', url('/uploads/${record['id']}/content'))
        ..followRedirects = false
        ..headers.addAll({
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/octet-stream',
          'Idempotency-Key': key
        })
        ..bodyBytes = bytes;
      return http.Response.fromStream(
          await transport.send(req).timeout(const Duration(seconds: 60)));
    }

    var response = await put();
    if (response.statusCode == 401) {
      await refresh();
      response = await put();
    }
    if (response.statusCode != 200 && response.statusCode != 201) {
      final data = jsonDecode(response.body);
      throw ApiException(
          data['error']?['code'] ?? 'UPLOAD_FAILED',
          data['error']?['message'] ?? 'Загрузка не удалась',
          response.statusCode);
    }
    return await request('/uploads/${record['id']}/finalize', method: 'POST')
        as Json;
  }

  Future<Uint8List> download(String id, {bool rotated = false}) async {
    final req = http.Request('GET', url('/uploads/$id/download'))
      ..followRedirects = false
      ..headers['Authorization'] = 'Bearer $accessToken';
    final response = await http.Response.fromStream(
        await transport.send(req).timeout(const Duration(seconds: 30)));
    if (response.statusCode == 401 && !rotated) {
      await refresh();
      return download(id, rotated: true);
    }
    if (response.statusCode != 200)
      throw ApiException(
          'DOWNLOAD_UNAVAILABLE', 'Файл недоступен', response.statusCode);
    return response.bodyBytes;
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
