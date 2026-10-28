import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'api.dart';

@pragma('vm:entry-point')
Future<void> jobaBackgroundPush(RemoteMessage message) async {
  await Firebase.initializeApp();
  // FCM displays notification payloads. Account data is fetched only after login.
}

/// Permission is requested only by an explicit tap in notification settings.
class JobaPush extends ChangeNotifier {
  static final instance = JobaPush();
  FirebaseMessaging? _messaging;
  JobaApi? _api;
  String? _scope, _registeredToken;
  Future<void>? _initializing;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  String _vapid = '';
  String status = 'Push-уведомления ещё не подключены';
  VoidCallback? onEvent, onOpen;
  bool get configured => _messaging != null;

  String scope(JobaApi api) => '${api.base}:${api.sessionGeneration}:${api.session?['user']?['id']}';
  Future<void> attach(JobaApi api) async {
    _api = api;
    if (!api.authenticated) return;
    final expected = scope(api);
    if (_scope != expected) { _scope = expected; _registeredToken = null; }
    try {
      if (_messaging == null) {
        _initializing ??= _initialize(api).whenComplete(() => _initializing = null);
        await _initializing;
      }
      if (_api != api || !api.authenticated || scope(api) != expected || _messaging == null) return;
      final permission = await _messaging!.getNotificationSettings();
      if (permission.authorizationStatus == AuthorizationStatus.authorized || permission.authorizationStatus == AuthorizationStatus.provisional) await _register();
    } catch (_) { status = 'Не удалось подключить push. Попробуйте ещё раз в настройках уведомлений.'; }
  }
  Future<void> _initialize(JobaApi api) async {
    final config = await api.request('/public/push-config');
    final platform = kIsWeb ? 'web' : defaultTargetPlatform == TargetPlatform.android ? 'android' : defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : '';
    final options = config['platforms']?[platform];
    if (config['enabled'] != true || options == null) return;
    _vapid = config['vapid_key'] ?? '';
    if (kIsWeb && _vapid.isEmpty) return;
    if (Firebase.apps.isEmpty) await Firebase.initializeApp(options: FirebaseOptions(apiKey: options['apiKey'], appId: options['appId'], messagingSenderId: options['messagingSenderId'], projectId: options['projectId'], authDomain: options['authDomain'], storageBucket: options['storageBucket'], iosBundleId: options['iosBundleId']));
    if (!await FirebaseMessaging.instance.isSupported()) { status = 'Этот браузер не поддерживает push-уведомления'; return; }
    _messaging = FirebaseMessaging.instance;
    if (!kIsWeb) FirebaseMessaging.onBackgroundMessage(jobaBackgroundPush);
    _subscriptions.add(_messaging!.onTokenRefresh.listen((_) { _registeredToken = null; unawaited(_register().catchError((Object _) {})); }));
    _subscriptions.add(FirebaseMessaging.onMessage.listen((_) { if (_api?.authenticated == true) onEvent?.call(); }));
    _subscriptions.add(FirebaseMessaging.onMessageOpenedApp.listen((_) { if (_api?.authenticated == true) onOpen?.call(); }));
    final initial = await _messaging!.getInitialMessage();
    if (initial != null && _api?.authenticated == true) onOpen?.call();
    status = 'Push-уведомления готовы к включению';
  }
  Future<void> enable() async {
    final api = _api;
    if (api == null || !api.authenticated) throw ApiException('PUSH_LOGIN_REQUIRED', 'Войдите в аккаунт');
    if (_messaging == null) await attach(api);
    final messaging = _messaging;
    if (messaging == null) throw ApiException('PUSH_NOT_CONFIGURED', status);
    final result = await messaging.requestPermission(alert: true, badge: true, sound: true);
    if (result.authorizationStatus == AuthorizationStatus.denied) {
      status = 'Уведомления запрещены. Разрешите их в настройках браузера или телефона.';
      notifyListeners(); return;
    }
    await _register();
    notifyListeners();
  }
  Future<void> _register() async {
    final api = _api, messaging = _messaging;
    if (api == null || messaging == null || !api.authenticated) return;
    final expected = scope(api);
    final token = await messaging.getToken(vapidKey: kIsWeb ? _vapid : null);
    if (_api != api || !api.authenticated || expected != scope(api) || token == null || token == _registeredToken) return;
    await api.request('/me/push-tokens', method: 'POST', body: {'token': token, 'platform': kIsWeb ? 'web' : defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android', 'environment': 'production'});
    if (_api == api && expected == scope(api)) { _registeredToken = token; status = 'Push-уведомления включены'; }
  }
  void detach() { _api = null; _scope = null; _registeredToken = null; onEvent = null; onOpen = null; }
}
