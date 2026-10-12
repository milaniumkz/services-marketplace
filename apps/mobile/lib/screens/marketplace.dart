import 'dart:async';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../core/api.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import '../core/local_lock.dart';

const states = {
  'draft': 'Черновик',
  'open': 'Открыт',
  'assigned': 'Исполнитель выбран',
  'in_progress': 'В работе',
  'completion_requested': 'Ожидает подтверждения',
  'completed': 'Завершён',
  'cancelled': 'Отменён',
  'pending': 'Ожидает ответа',
  'active': 'Активен',
  'passed': 'Проверен',
  'pending_review': 'На проверке',
  'published': 'Опубликован',
  'rejected': 'Отклонён',
  'new': 'Новое',
  'sealed': 'Ожидает публикации',
  'resolved': 'Решено',
  'requested': 'Запрос создан',
  'processing': 'Обрабатывается',
  'ready': 'Готово',
  'waiting_support': 'Ожидается ответ поддержки',
  'waiting_user': 'Ожидается ваш ответ',
  'waiting_for_user': 'Ожидается ваш ответ',
  'waiting_for_staff': 'Ожидается ответ поддержки',
  'accepted': 'Принято',
  'declined': 'Отклонено',
  'withdrawn': 'Отозван',
  'not_selected': 'Выбран другой исполнитель',
  'expired': 'Срок истёк',
  'revoked': 'Отозвано',
  'restricted': 'Ограничено',
  'appealed': 'Апелляция на рассмотрении',
  'available': 'Можно активировать',
  'redeemed': 'Активирована',
  'awaiting_retention_policy': 'Ожидается проверка сроков хранения',
  'limited_retention': 'Аккаунт закрыт; часть записей сохраняется по правилам'
};
const eventTitles = {
  'offer.created': 'Новый отклик на заказ',
  'order.selected': 'Вы выбраны исполнителем',
  'invite.created': 'Приглашение в заказ',
  'message.created': 'Новое сообщение',
  'support.message.created': 'Ответ поддержки',
  'cancel_request.accepted': 'Отмена согласована',
  'cancel_request.rejected': 'Отмена отклонена',
  'amendment.accepted': 'Новые условия согласованы',
  'amendment.rejected': 'Новые условия отклонены'
};
String status(Json r) => states[r['status']] ?? '${r['status'] ?? ''}';
String money(dynamic amount, [String currency = 'KZT']) =>
    amount == null ? 'По договорённости' : '${(amount as num) / 100} $currency';
int minor(String value) {
  final normalized = value.trim().replaceAll(',', '.');
  if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(normalized))
    throw ApiException(
        'VALIDATION_ERROR', 'Укажите сумму с точностью до сотых');
  final parts = normalized.split('.');
  return int.parse(parts[0]) * 100 +
      int.parse(parts.length == 2 ? parts[1].padRight(2, '0') : '0');
}

class Marketplace extends StatefulWidget {
  final JobaApi? api;
  const Marketplace({this.api, super.key});
  @override
  State<Marketplace> createState() => _MarketplaceState();
}

class _MarketplaceState extends State<Marketplace> with WidgetsBindingObserver {
  late JobaApi api;
  Json? me, recovery;
  String country = 'KZ', route = 'welcome';
  String locale = 'ru';
  String? draftCategory;
  String? objectId;
  final List<(String, String?)> history = [];
  bool starting = true, executor = false, actionBusy = false;
  String? startupError;
  int revision = 0, sequence = 0;
  WebSocketChannel? channel;
  StreamSubscription? subscription;
  Timer? reconnect;
  LocalLock? lock;
  bool locked = false;
  bool localProtected = false;
  DateTime? pausedAt;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    api = widget.api ??
        JobaApi(const String.fromEnvironment('JOBA_API_URL',
            defaultValue: 'http://localhost:3000'));
    api.addListener(sessionChanged);
    initialize();
  }

  Future<void> initialize() async {
    try {
      await api.restore(refreshSession: false);
      if (api.authenticated) {
        lock = LocalLock('${api.base}:${api.session?['user']?['id']}');
        if (await lock!.configured()) {
          locked = true;
          localProtected = true;
          route = 'unlock';
        } else {
          await api.forget();
        }
      }
    } catch (e) {
      startupError = '$e';
    }
    if (mounted) setState(() => starting = false);
  }

  void sessionChanged() {
    if (!mounted) return;
    if (!api.authenticated) {
      closeEvents();
      sequence = 0;
      lock?.clear();
      locked = false;
      localProtected = false;
      setState(() {
        me = null;
        route = 'login';
        objectId = null;
        history.clear();
      });
    } else if (channel != null) {
      connectEvents();
    }
  }

  void closeEvents() {
    reconnect?.cancel();
    subscription?.cancel();
    channel?.sink.close();
    channel = null;
  }

  void connectEvents() {
    closeEvents();
    if (!api.authenticated || !mounted) return;
    final uri = api
        .url('/events/ws')
        .replace(scheme: api.base.scheme == 'https' ? 'wss' : 'ws');
    channel = WebSocketChannel.connect(uri,
        protocols: ['joba.v1', 'auth.${api.accessToken}']);
    final current = channel!;
    current.ready.then((_) {
      current.sink
          .add(jsonEncode({'type': 'resume', 'after_sequence': sequence}));
    }).catchError((Object _) {});
    subscription = current.stream.listen((raw) {
      try {
        final event = jsonDecode(raw as String) as Json;
        final next = event['sequence'] as int;
        if (next <= sequence) return;
        sequence = next;
        if (mounted &&
            ![
              'create',
              'edit-order',
              'lock-setup',
              'unlock',
              'onboarding',
              'services',
              'portfolio-project',
              'password',
              'phone',
              'review',
              'report',
              'offer'
            ].contains(route)) setState(() => revision++);
      } catch (_) {/* Invalid events never become user records. */}
    }, onError: (Object _) => scheduleReconnect(), onDone: scheduleReconnect);
  }

  void scheduleReconnect() {
    reconnect?.cancel();
    if (api.authenticated && mounted)
      reconnect = Timer(const Duration(seconds: 5), () async {
        try {
          await api.refresh();
          connectEvents();
        } catch (_) {
          scheduleReconnect();
        }
      });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && api.authenticated) {
      if (pausedAt != null &&
          DateTime.now().difference(pausedAt!).inSeconds >= 60) {
        if (localProtected) {
          setState(() => locked = true);
          closeEvents();
        } else {
          api.forget();
        }
      } else if (!locked) {
        connectEvents();
      }
    }
    if (state == AppLifecycleState.paused) {
      pausedAt = DateTime.now();
      closeEvents();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    closeEvents();
    api.removeListener(sessionChanged);
    if (widget.api == null) api.dispose();
    super.dispose();
  }

  void go(String next, [String? id]) {
    setState(() {
      history.add((route, objectId));
      route = next;
      objectId = id;
      revision++;
    });
  }

  void back() {
    setState(() {
      if (history.isNotEmpty) {
        final previous = history.removeLast();
        route = previous.$1;
        objectId = previous.$2;
      } else {
        route = api.authenticated ? 'home' : 'welcome';
        objectId = null;
      }
      revision++;
    });
  }

  void success(String text) {
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> act(Future<void> Function() action) async {
    if (actionBusy) return;
    setState(() => actionBusy = true);
    try {
      await action();
    } catch (e) {
      if (mounted)
        await showDialog<void>(
            context: context,
            builder: (c) => AlertDialog(
                    title: const Text('Не удалось выполнить действие'),
                    content: Text('$e'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(c),
                          child: const Text('Понятно'))
                    ]));
    } finally {
      if (mounted) setState(() => actionBusy = false);
    }
  }

  Widget button(String label, VoidCallback onPressed, {bool outline = false}) =>
      Padding(
          padding: const EdgeInsets.only(top: 12),
          child: outline
              ? OutlinedButton(
                  onPressed: actionBusy ? null : onPressed, child: Text(label))
              : FilledButton(
                  onPressed: actionBusy ? null : onPressed,
                  child: Text(label)));
  Widget page(String title, Widget body,
          {List<Widget> actions = const [], bool nav = false}) =>
      PopScope(
          canPop: history.isEmpty,
          onPopInvokedWithResult: (popped, result) {
            if (!popped) back();
          },
          child: Scaffold(
              appBar: AppBar(
                  title: Text(title),
                  leading: IconButton(
                      onPressed: back,
                      tooltip: 'Назад',
                      icon: const Icon(Icons.chevron_left)),
                  actions: actions),
              body: body,
              bottomNavigationBar: nav
                  ? SafeArea(
                      top: false,
                      child: Container(
                          height: 60,
                          decoration: const BoxDecoration(
                              color: Colors.white,
                              border: Border(top: BorderSide(color: line))),
                          child: Row(children: [
                            for (final item in [
                              ('home', 'Главная', Icons.home_outlined),
                              ('catalog', 'Поиск', Icons.search),
                              (
                                'messages',
                                'Сообщения',
                                Icons.chat_bubble_outline
                              ),
                              (
                                'notifications',
                                'События',
                                Icons.notifications_outlined
                              ),
                              ('account', 'Профиль', Icons.person_outline)
                            ])
                              Expanded(
                                  child: InkWell(
                                      onTap: () => go(item.$1),
                                      child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(item.$3,
                                                color: route == item.$1
                                                    ? primary
                                                    : const Color(0xFF6B7890),
                                                size: 23),
                                            const SizedBox(height: 4),
                                            Text(item.$2,
                                                style: TextStyle(
                                                    fontSize: 10,
                                                    color: route == item.$1
                                                        ? primary
                                                        : const Color(
                                                            0xFF6B7890)))
                                          ]))),
                          ])))
                  : null));
  Widget listBody(List<Widget> content) =>
      ListView(padding: const EdgeInsets.all(20), children: content);
  Widget loaded(String path, Widget Function(dynamic, VoidCallback) render,
          {Json query = const {}}) =>
      ApiView(
          key: ValueKey('$route:$objectId:$revision:$path'),
          load: () => api.request(path, query: query),
          builder: (c, data, reload) => render(data, reload));
  Widget orderCard(Json order) => DataCard('${order['title']}',
      subtitle:
          '${order['city']} · ${money(order['budget_amount'], order['currency'] ?? 'KZT')}',
      status: status(order),
      onTap: () => go('order', order['id']));
  Widget paged(String path, Widget Function(Json) tile,
          {Json query = const {}, String empty = 'Пока здесь ничего нет'}) =>
      PagedList(
          key: ValueKey('$route:$objectId:$revision:$path'),
          api: api,
          path: path,
          query: query,
          tile: tile,
          empty: empty);
  @override
  Widget build(BuildContext context) {
    if (starting)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (locked) return unlockScreen();
    if (startupError != null)
      return page(
          'Соединение',
          listBody([
            Notice(startupError!, error: true),
            button('Повторить', () {
              setState(() {
                starting = true;
                startupError = null;
              });
              initialize();
            })
          ]));
    return screen();
  }

  Widget screen() {
    switch (route) {
      case 'lock-setup':
        return lockSetup();
      case 'unlock':
        return unlockScreen();
      case 'welcome':
        return welcomeScreen();
      case 'login':
      case 'register':
        return authScreen();
      case 'recovery':
        return page(
            'Помощь со входом',
            ActionForm(
                fields: const [
                  InputSpec('subject', 'Тема обращения'),
                  InputSpec('text', 'Как мы можем помочь?', multiline: true)
                ],
                before: const [
                  Notice(
                      'Не отправляйте пароль, PIN или документ. Обращение не даёт доступ к аккаунту.')
                ],
                button: 'Создать обращение',
                submit: (v) async {
                  recovery = await api.request('/public/recovery-threads',
                      method: 'POST',
                      authenticated: false,
                      body: {...v, 'country': country}) as Json;
                  go('recovery-chat', recovery!['id']);
                }));
      case 'recovery-chat':
        return recoveryChat();
      case 'home':
        return homeScreen();
      case 'account':
        return accountScreen();
      case 'onboarding':
        return profileForm();
      case 'orders':
        return page('Мои заказы',
            paged(executor ? '/me/assigned-orders' : '/me/orders', orderCard),
            actions: [
              IconButton(
                  tooltip: 'Создать заказ',
                  onPressed: () => go('create'),
                  icon: const Icon(Icons.add))
            ]);
      case 'jobs':
        return page('Заказы рядом',
            SearchListings(api: api, path: '/orders', tile: orderCard));
      case 'create':
        return createScreen();
      case 'edit-order':
        return editOrderScreen();
      case 'change-requests':
        return changeRequestsScreen();
      case 'order':
      case 'work':
      case 'publish':
        return orderScreen();
      case 'offer':
        return offerScreen();
      case 'offers':
        return offersScreen();
      case 'my-offers':
        return page(
            'Мои отклики',
            paged(
                '/me/offers',
                (r) => DataCard('${r['text']}',
                    status: status(r),
                    subtitle: money(r['amount'], r['currency']),
                    onTap: () => go('order', r['order_id']),
                    footer: Column(children: [
                      button(
                          'Открыть чат', () => go('chat', r['conversation_id']),
                          outline: true),
                      if (r['status'] == 'active')
                        button(
                            'Отозвать отклик',
                            () => act(() async {
                                  await api.request(
                                      '/offers/${r['id']}/withdraw',
                                      method: 'POST',
                                      body: {'expected_version': r['version']});
                                  setState(() => revision++);
                                }),
                            outline: true)
                    ]))));
      case 'catalog':
        return page(
            'Специалисты',
            SearchListings(
                api: api,
                path: '/contractors',
                tile: (r) => DataCard('${r['title']}',
                    subtitle: '${r['city']}\n${r['description']}',
                    onTap: () => go('contractor', r['id']))),
            nav: true);
      case 'contractor':
        return contractorScreen();
      case 'services':
        return servicesScreen();
      case 'invitations':
        return invitationsScreen();
      case 'invite':
        return inviteScreen();
      case 'messages':
        return page(
            'Сообщения',
            paged(
                '/me/conversations',
                (r) => DataCard('Чат заказа',
                    status: status(r), onTap: () => go('chat', r['id']))),
            nav: true);
      case 'chat':
        return chatScreen(false);
      case 'support-chat':
        return chatScreen(true);
      case 'support':
        return supportScreen();
      case 'review':
        return reviewScreen();
      case 'reviews':
        return page(
            'Отзывы',
            paged(
                '/users/${objectId ?? me!['id']}/reviews',
                (r) => DataCard('${r['rating']} ★',
                    subtitle: '${r['text']}', status: status(r))));
      case 'report':
        return reportScreen();
      case 'cases':
        return page(
            'Мои обращения',
            paged(
                '/me/cases',
                (r) => DataCard(
                    '${r['reason_code'] ?? r['type'] ?? 'Обращение'}',
                    subtitle: '${r['description'] ?? r['reason'] ?? ''}',
                    status: status(r),
                    onTap: () => go('case', r['id']))));
      case 'case':
        return caseScreen();
      case 'notifications':
        return page(
            'Уведомления',
            paged(
                '/me/notifications',
                (r) => DataCard(eventTitles[r['type']] ?? 'Новое событие JOBA',
                    status: r['read'] == true ? 'Прочитано' : 'Новое',
                    onTap: () => act(() async {
                          await api.request('/me/notifications/${r['id']}/read',
                              method: 'POST');
                          setState(() => revision++);
                        }))),
            nav: true);
      case 'access':
      case 'my-access':
        return accessScreen();
      case 'reward':
        return page(
            'Рекламная награда',
            loaded(
                '/me/monetization-config',
                (data, reload) => listBody([
                      const Heading('Больше возможностей',
                          'Доступ выдаётся только после подтверждения рекламной сети.'),
                      Notice(data['rewarded_access_enabled'] == true
                          ? 'Рекламная сеть ещё не подключена.'
                          : 'Рекламные награды сейчас отключены.'),
                      button('Мой доступ', () => go('my-access'), outline: true)
                    ])));
      case 'privacy':
        return privacyScreen();
      case 'security':
        return securityScreen();
      case 'password':
        return passwordScreen();
      case 'blocks':
        return page(
            'Заблокированные контакты',
            paged(
                '/me/blocks',
                (r) => DataCard(
                    (r['display_name'] as String).isEmpty
                        ? 'Без имени'
                        : r['display_name'],
                    footer: button(
                        'Разблокировать',
                        () => act(() async {
                              await api.request('/me/blocks/${r['target_id']}',
                                  method: 'DELETE');
                              setState(() => revision++);
                            }),
                        outline: true))));
      case 'logout-all':
        return page(
            'Завершить все сессии',
            ActionForm(
                fields: const [
                  InputSpec('current_password', 'Текущий пароль', secret: true)
                ],
                button: 'Завершить все сессии',
                submit: (v) async {
                  await api.request('/auth/logout-all',
                      method: 'POST', body: v);
                  await api.forget();
                }));
      case 'phone':
        return phoneScreen();
      case 'settings':
        return settingsScreen();
      case 'notification-settings':
        return notificationSettings();
      case 'referrals':
        return referralsScreen();
      case 'portfolio':
        return portfolioScreen();
      case 'portfolio-project':
        return projectScreen();
      case 'verification':
        return verificationScreen();
      case 'terms':
        return termsScreen();
      case 'top':
        return page(
            'Топ-100',
            paged(
                '/top-listings',
                (r) => DataCard('${r['title']}',
                    subtitle: '${r['likes']} 👍 · ${r['dislikes']} 👎',
                    onTap: () => go(executor ? 'order' : 'contractor', r['id']),
                    footer: Row(children: [
                      IconButton(
                          tooltip: 'Нравится',
                          icon: const Icon(Icons.thumb_up_outlined),
                          onPressed: () => vote(r, 1)),
                      IconButton(
                          tooltip: 'Не нравится',
                          icon: const Icon(Icons.thumb_down_outlined),
                          onPressed: () => vote(r, -1))
                    ])),
                query: {'target_type': executor ? 'orders' : 'services'}));
      case 'promotion':
        return promotionScreen();
      default:
        return page(
            'JOBA',
            listBody([
              const Notice('Экран не найден'),
              button('Главная', () => go('home'))
            ]));
    }
  }

  Widget countryCard(String code, String name, String currency) => Container(
      margin: const EdgeInsets.only(bottom: 10),
      height: 76,
      decoration: BoxDecoration(
          color: country == code ? const Color(0xFFF1F5FE) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: country == code ? primary : line)),
      child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() => country = code),
          child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                if (code == 'KZ') ...[
                  const Icon(Icons.public, size: 24),
                  const SizedBox(width: 12)
                ],
                Expanded(
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(name,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(currency,
                          style: const TextStyle(
                              fontSize: 13, color: Color(0xFF6B7890)))
                    ])),
                Icon(
                    country == code
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: country == code ? primary : line,
                    size: 20),
              ]))));
  Widget welcomeScreen() => Scaffold(
          body: SafeArea(
              child: Column(children: [
        Expanded(
            child: listBody([
          const Text('JOBA',
              style: TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1.8,
                  color: primary)),
          const SizedBox(height: 24),
          Image.asset('assets/joba-logo-original.jpeg',
              height: 140, fit: BoxFit.contain),
          const SizedBox(height: 24),
          const Heading('Дела становятся проще',
              'Находите специалистов и заказы в вашем городе.'),
          const Text('Страна услуг',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 8),
          countryCard('KZ', 'Казахстан', 'KZT · локальные услуги'),
          countryCard('RS', 'Сербия', 'RSD'),
          Row(children: [
            Expanded(child: countryCard('RU', 'Россия', 'RUB')),
            const SizedBox(width: 12),
            Expanded(child: countryCard('BY', 'Беларусь', 'BYN'))
          ]),
          const SizedBox(height: 16),
          const Text('Язык интерфейса',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          DropdownButtonFormField<String>(
              initialValue: locale,
              items: const [
                DropdownMenuItem(value: 'ru', child: Text('Русский')),
                DropdownMenuItem(value: 'kk', child: Text('Қазақша')),
                DropdownMenuItem(value: 'sr', child: Text('Srpski')),
                DropdownMenuItem(value: 'be', child: Text('Беларуская'))
              ],
              onChanged: (v) => setState(() => locale = v!)),
          const SizedBox(height: 16),
          const Text(
              'Страна и язык выбираются отдельно. Доступность функций зависит от региона.',
              style: TextStyle(fontSize: 11, color: Color(0xFF6B7890))),
        ])),
        Padding(
            padding: const EdgeInsets.all(20),
            child: FilledButton(
                onPressed: () => go('login'), child: const Text('Продолжить'))),
      ])));
  Widget authScreen() {
    final register = route == 'register';
    return page(
        register ? 'Новый аккаунт' : 'Вход в JOBA',
        ActionForm(
            key: ValueKey(route),
            before: [
              Heading(
                  register ? 'Добро пожаловать' : 'С возвращением',
                  register
                      ? 'Создайте аккаунт, чтобы начать.'
                      : 'Войдите в свой аккаунт, чтобы продолжить.')
            ],
            fields: [
              if (register)
                const InputSpec('display_name', 'Как к вам обращаться'),
              const InputSpec('phone', 'Номер телефона',
                  keyboard: TextInputType.phone),
              InputSpec('password', 'Пароль',
                  secret: true,
                  validate: (v) => register && v.length < 15
                      ? 'Не менее 15 символов'
                      : null),
              if (register)
                const InputSpec('repeat', 'Повторите пароль', secret: true)
            ],
            button: register ? 'Создать аккаунт' : 'Войти',
            submit: (v) async {
              if (register && v['password'] != v['repeat'])
                throw ApiException('VALIDATION_ERROR', 'Пароли не совпадают');
              await api.signIn({
                'country': country,
                'phone': v['phone']!.trim(),
                'password': v['password'],
                if (register) 'display_name': v['display_name'],
                if (register) 'locale': locale
              }, register: register);
              me = await api.request('/me') as Json;
              sequence = 0;
              connectEvents();
              lock = LocalLock('${api.base}:${me!['id']}');
              if (mounted)
                setState(() {
                  route = 'lock-setup';
                  history.clear();
                });
            },
            after: [
              TextButton(
                  onPressed: () => go('recovery'),
                  child: const Text('Нужна помощь со входом?')),
              const Divider(height: 32),
              button(
                  register ? 'Уже есть аккаунт? Войти' : 'Зарегистрироваться',
                  () => go(register ? 'login' : 'register'),
                  outline: true),
              const Notice(
                  'Ваш номер используется как логин. Подтверждение кодом не требуется.')
            ]));
  }

  Widget lockSetup() => page(
      'Защитите вход',
      ActionForm(
          fields: const [
            InputSpec('pin', 'PIN · 6–8 цифр',
                secret: true, keyboard: TextInputType.number),
            InputSpec('repeat', 'Повторите PIN',
                secret: true, keyboard: TextInputType.number)
          ],
          before: const [
            Heading('Быстрый вход', 'PIN хранится только на этом устройстве.')
          ],
          button: 'Сохранить PIN',
          submit: (v) async {
            if (v['pin'] != v['repeat'])
              throw ApiException('PIN_INVALID', 'PIN не совпадает');
            await lock!.configure(v['pin']!);
            await api.setPersistence(true);
            localProtected = true;
            go('terms');
          },
          after: [
            button(
                'Использовать биометрию',
                () => act(() async {
                      await lock!.enableBiometry();
                      await api.setPersistence(true);
                      localProtected = true;
                      go('terms');
                    }),
                outline: true),
            button(
                'Входить с паролем',
                () => act(() async {
                      await api.setPersistence(false);
                      localProtected = false;
                      go('terms');
                    }),
                outline: true)
          ]));
  Widget unlockScreen() => Scaffold(
      appBar: AppBar(title: const Text('Разблокировка JOBA')),
      body: ActionForm(
          fields: const [
            InputSpec('pin', 'PIN',
                secret: true, keyboard: TextInputType.number)
          ],
          button: 'Разблокировать',
          submit: (v) async {
            try {
              if (!await lock!.unlock(v['pin']!))
                throw ApiException('PIN_INVALID', 'Неверный PIN');
              await api.refresh();
              me = await api.request('/me') as Json;
              country = me!['country'];
              if (mounted)
                setState(() {
                  locked = false;
                  route = 'home';
                  objectId = null;
                  history.clear();
                });
              connectEvents();
            } on ApiException catch (e) {
              if (e.code == 'PIN_EXHAUSTED') await api.forget();
              rethrow;
            }
          },
          after: [
            button(
                'Разблокировать биометрией',
                () => act(() async {
                      try {
                        if (!await lock!.unlockBiometry()) return;
                        await api.refresh();
                        me = await api.request('/me') as Json;
                        country = me!['country'];
                        if (mounted)
                          setState(() {
                            locked = false;
                            route = 'home';
                            objectId = null;
                            history.clear();
                          });
                        connectEvents();
                      } on ApiException catch (e) {
                        if (e.code == 'PIN_EXHAUSTED') await api.forget();
                        rethrow;
                      }
                    }),
                outline: true),
            button('Войти с номером и паролем', () => act(() => api.forget()),
                outline: true)
          ]));
  Widget homeScreen() => page(
      'JOBA',
      loaded(
          executor ? '/me/assigned-orders' : '/me/orders',
          (result, reload) => listBody([
                Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(me?['city'] ?? country),
                      TextButton(
                          onPressed: () => setState(() {
                                executor = !executor;
                                revision++;
                              }),
                          child: Text(executor ? 'Исполнитель' : 'Заказчик'))
                    ]),
                Heading(executor
                    ? 'Новые заказы.\nВаши возможности.'
                    : 'Хорошие мастера.\nВаши задачи.'),
                Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                        color: yellow, borderRadius: BorderRadius.circular(20)),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              executor
                                  ? 'Найдите следующую работу'
                                  : 'Расскажите о задаче',
                              style: const TextStyle(
                                  fontSize: 22, fontWeight: FontWeight.w700)),
                          button(executor ? 'Найти заказ' : 'Создать заказ',
                              () => go(executor ? 'jobs' : 'create'))
                        ])),
                const SizedBox(height: 24),
                Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Ваши заказы',
                          style: TextStyle(
                              fontSize: 19, fontWeight: FontWeight.w700)),
                      TextButton(
                          onPressed: () => go('orders'),
                          child: const Text('Все'))
                    ]),
                if (items(result).isEmpty) const Notice('Заказов пока нет'),
                ...items(result).take(3).map(orderCard),
                if (executor)
                  button('Мои отклики', () => go('my-offers'), outline: true),
                button('Входящие приглашения', () => go('invitations'),
                    outline: true),
              ])),
      actions: [
        IconButton(
            tooltip: 'Уведомления',
            onPressed: () => go('notifications'),
            icon: const Icon(Icons.notifications_outlined))
      ],
      nav: true);
  Widget accountScreen() => page(
      'Мой профиль',
      loaded('/me', (data, reload) {
        me = data as Json;
        return listBody([
          Heading(
              me!['display_name'] ?? '', '${me!['city']} · ${me!['country']}'),
          Text('${me!['phone']}'),
          const Notice(
              'Телефон используется как неподтверждённый идентификатор входа.'),
          for (final entry in {
            'onboarding': 'Редактировать профиль',
            'services': 'Мои услуги',
            'verification': 'Документ исполнителя',
            'portfolio': 'Моё портфолио',
            'reviews': 'Отзывы',
            'my-access': 'Мой доступ',
            'referrals': 'Приглашения и бонусы',
            'top': 'Топ-100',
            'promotion': 'Продвинуть объявление',
            'cases': 'Мои обращения',
            'support': 'Поддержка',
            'privacy': 'Приватность',
            'security': 'Безопасность',
            'settings': 'Настройки'
          }.entries)
            ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(entry.value),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => go(entry.key)),
          button('Выйти', () => act(() => api.logout()), outline: true)
        ]);
      }),
      nav: true);
  Widget profileForm() => page(
      'Мой профиль',
      loaded(
          '/me',
          (data, reload) => ActionForm(
                  fields: [
                    InputSpec('display_name', 'Имя',
                        initial: data['display_name']),
                    InputSpec('city', 'Город',
                        initial: data['city'], required: false),
                    InputSpec('locale', 'Язык',
                        initial: data['locale'],
                        options: const {
                          'ru': 'Русский',
                          'kk': 'Қазақша',
                          'sr': 'Srpski',
                          'be': 'Беларуская'
                        })
                  ],
                  submit: (v) async {
                    me = await api.request('/me',
                            method: 'PATCH',
                            body: {...v, 'expected_version': data['version']})
                        as Json;
                    success('Профиль сохранён');
                    back();
                  })));
  Widget createScreen() => page(
      'Новый заказ',
      ApiView(
          key: ValueKey('create:$revision'),
          load: () => Future.wait(
              [api.request('/catalog/categories'), api.request('/geo/cities')]),
          builder: (c, data, reload) => ActionForm(
                  before: const [
                    Heading('Что нужно сделать?')
                  ],
                  fields: [
                    InputSpec('category_id', 'Категория',
                        initial: draftCategory ?? '',
                        options: {
                          for (final r in items(data[0])) r['id']: r['name']
                        },
                        changed: (v) => setState(() => draftCategory = v)),
                    ...attributeFields(items(data[0])),
                    const InputSpec('title', 'Название', validate: titleCheck),
                    const InputSpec('description', 'Опишите задачу',
                        multiline: true, validate: descriptionCheck),
                    InputSpec('city_id', 'Город', options: {
                      for (final r in items(data[1])) r['id']: r['name']
                    }),
                    const InputSpec('work_mode', 'Формат работы',
                        initial: 'onsite',
                        options: {
                          'onsite': 'На месте',
                          'remote': 'Удалённо',
                          'hybrid': 'Смешанный'
                        }),
                    const InputSpec('budget', 'Бюджет',
                        required: false, keyboard: TextInputType.number)
                  ],
                  button: 'Предпросмотр заказа',
                  submit: (v) async {
                    final order =
                        await api.request('/orders', method: 'POST', body: {
                      'title': v['title'],
                      'description': v['description'],
                      'category_id': v['category_id'],
                      'city_id': v['city_id'],
                      'work_mode': v['work_mode'],
                      'budget_amount':
                          v['budget']!.isEmpty ? null : minor(v['budget']!),
                      'attributes': attributeValues(items(data[0]), v),
                      'upload_ids': []
                    }) as Json;
                    go('publish', order['id']);
                  })));
  Json categorySchema(List<Json> categories) {
    for (final category in categories) {
      if (category['id'] == draftCategory) return category['schema'] as Json;
    }
    return {'properties': <String, dynamic>{}, 'required': []};
  }

  List<InputSpec> attributeFields(List<Json> categories) {
    final schema = categorySchema(categories),
        properties = schema['properties'] as Json? ?? {};
    return properties.entries.map((entry) {
      final spec = entry.value as Json, type = spec['type'];
      final required = (schema['required'] as List? ?? []).contains(entry.key);
      Map<String, String>? options;
      if (spec['enum'] is List)
        options = {for (final value in spec['enum']) '$value': '$value'};
      if (type == 'boolean') options = {'true': 'Да', 'false': 'Нет'};
      if (options != null && !required)
        options = {'': 'Не указано', ...options};
      return InputSpec(
          'attr:$draftCategory:${entry.key}', spec['title'] ?? entry.key,
          required: required,
          options: options,
          keyboard: ['number', 'integer'].contains(type)
              ? TextInputType.number
              : null, validate: (v) {
        if (v.isEmpty && !required) return null;
        if (type == 'integer' && int.tryParse(v) == null ||
            type == 'number' && num.tryParse(v.replaceAll(',', '.')) == null)
          return 'Проверьте число';
        return null;
      });
    }).toList();
  }

  Json attributeValues(List<Json> categories, Map<String, String> form) {
    final schema = categorySchema(categories), result = <String, dynamic>{};
    for (final entry in (schema['properties'] as Json? ?? {}).entries) {
      final value = form['attr:$draftCategory:${entry.key}'];
      if (value == null || value.isEmpty) continue;
      result[entry.key] = switch (entry.value['type']) {
        'integer' => int.parse(value),
        'number' => num.parse(value.replaceAll(',', '.')),
        'boolean' => value == 'true',
        _ => value
      };
    }
    return result;
  }

  static String? titleCheck(String v) =>
      v.trim().length < 5 || v.length > 120 ? 'От 5 до 120 символов' : null;
  static String? descriptionCheck(String v) =>
      v.trim().length < 20 || v.length > 5000 ? 'От 20 до 5000 символов' : null;
  Widget orderScreen() => page(
      route == 'publish' ? 'Проверьте заказ' : 'Карточка заказа',
      loaded('/orders/$objectId', (data, reload) {
        final o = data as Json;
        final owner = o['owner'] == me!['id'],
            assigned = o['executor_id'] == me!['id'];
        return listBody([
          Heading('${o['title']}'),
          DataCard(status(o),
              subtitle:
                  '${o['city']} · ${money(o['budget_amount'], o['currency'])}'),
          Text('${o['description']}', style: const TextStyle(height: 1.6)),
          if (owner && o['status'] == 'draft')
            button(
                'Опубликовать заказ', () => orderCommand(o, 'publish', reload)),
          if (owner && ['draft', 'open'].contains(o['status']))
            button('Изменить заказ', () => go('edit-order', o['id']),
                outline: true),
          if (owner)
            button(
                'Повторить заказ',
                () => act(() async {
                      final cloned = await api.request(
                          '/orders/${o['id']}/clone',
                          method: 'POST',
                          body: {'expected_version': o['version']}) as Json;
                      go('publish', cloned['id']);
                    }),
                outline: true),
          if (!owner && o['status'] == 'open')
            button('Откликнуться', () => go('offer', o['id'])),
          if (owner && o['status'] == 'open')
            button('Список откликов', () => go('offers', o['id'])),
          if (assigned && o['status'] == 'assigned')
            button('Начать работу', () => orderCommand(o, 'start', reload)),
          if (assigned && o['status'] == 'in_progress')
            button('Запросить завершение',
                () => orderCommand(o, 'complete', reload)),
          if (owner && o['status'] == 'completion_requested') ...[
            button('Подтвердить завершение',
                () => orderCommand(o, 'confirm-completion', reload)),
            button('Запросить доработку',
                () => reasonCommand(o, 'request-revision', reload),
                outline: true)
          ],
          if ((owner || assigned) &&
              ['assigned', 'in_progress', 'completion_requested']
                  .contains(o['status']))
            button('Запросить отмену',
                () => reasonCommand(o, 'cancel-requests', reload),
                outline: true),
          if ((owner || assigned) &&
              ['assigned', 'in_progress', 'completion_requested']
                  .contains(o['status'])) ...[
            button('Согласовать новые условия', () => amendmentForm(o, reload),
                outline: true),
            button('Запросы изменения и отмены',
                () => go('change-requests', o['id']),
                outline: true)
          ],
          if (owner && ['draft', 'open'].contains(o['status']))
            button('Отменить заказ', () => reasonCommand(o, 'cancel', reload),
                outline: true),
          if ((owner || assigned) && o['status'] == 'completed')
            button('Оставить отзыв', () => go('review', o['id'])),
          if (owner || assigned)
            button('Сообщения', () => go('messages'), outline: true),
          button('Пожаловаться', () => go('report', o['id']), outline: true),
        ]);
      }));
  Widget editOrderScreen() => page(
      'Изменить заказ',
      loaded(
          '/orders/$objectId',
          (o, reload) => ActionForm(
              fields: [
                InputSpec('title', 'Название',
                    initial: o['title'], validate: titleCheck),
                InputSpec('description', 'Описание',
                    initial: o['description'],
                    multiline: true,
                    validate: descriptionCheck),
                InputSpec('city', 'Город', initial: o['city']),
                InputSpec('budget', 'Бюджет',
                    initial: o['budget_amount'] == null
                        ? ''
                        : '${o['budget_amount'] / 100}',
                    required: false,
                    keyboard: TextInputType.number)
              ],
              submit: (v) async {
                await api.request('/orders/$objectId', method: 'PATCH', body: {
                  'expected_version': o['version'],
                  'title': v['title'],
                  'description': v['description'],
                  'city': v['city'],
                  'budget_amount':
                      v['budget']!.isEmpty ? null : minor(v['budget']!)
                });
                success('Заказ изменён');
                back();
              },
              after: [
                button(
                    'Добавить фото задачи',
                    () => act(() async {
                          final file = await pickUpload('order');
                          if (file == null) return;
                          await api.request('/orders/${o['id']}',
                              method: 'PATCH',
                              body: {
                                'expected_version': o['version'],
                                'upload_ids': [...o['upload_ids'], file['id']]
                              });
                          reload();
                        }),
                    outline: true)
              ])));
  void amendmentForm(Json o, VoidCallback reload) => Navigator.push(
      context,
      MaterialPageRoute<void>(
          builder: (c) => Scaffold(
              appBar: AppBar(title: const Text('Новые условия')),
              body: ActionForm(
                  fields: const [
                    InputSpec('amount', 'Согласуемая цена',
                        keyboard: TextInputType.number),
                    InputSpec('description', 'Новые условия', multiline: true),
                    InputSpec('reason', 'Причина изменения', multiline: true)
                  ],
                  button: 'Предложить изменение',
                  submit: (v) async {
                    await api.request('/orders/${o['id']}/amendments',
                        method: 'POST',
                        body: {
                          ...v,
                          'amount': minor(v['amount']!),
                          'expected_version': o['version']
                        });
                    if (c.mounted) Navigator.pop(c);
                    reload();
                    success('Ожидается ответ второй стороны');
                  }))));
  Widget changeRequestsScreen() => page(
      'Изменения и отмена',
      paged(
          '/me/order-change-requests',
          (r) => DataCard(
              r['kind'] == 'amendment' ? 'Новые условия' : 'Запрос отмены',
              status: status(r),
              subtitle: '${r['reason']}\n${r['description'] ?? ''}',
              footer: r['status'] == 'pending' && r['recipient_id'] == me!['id']
                  ? Column(children: [
                      for (final e in {
                        'accept': 'Согласен',
                        'reject': 'Отклонить'
                      }.entries)
                        button(
                            e.value,
                            () => act(() async {
                                  await api.request(
                                      '/${r['kind'] == 'amendment' ? 'amendments' : 'cancel-requests'}/${r['id']}/respond',
                                      method: 'POST',
                                      body: {
                                        'expected_version': r['version'],
                                        'decision': e.key
                                      });
                                  setState(() => revision++);
                                }),
                            outline: e.key == 'reject')
                    ])
                  : null)));
  void orderCommand(Json o, String command, VoidCallback reload) =>
      act(() async {
        await api.request('/orders/${o['id']}/$command',
            method: 'POST', body: {'expected_version': o['version']});
        success('Изменения сохранены');
        reload();
      });
  void reasonCommand(Json o, String command, VoidCallback reload) {
    Navigator.push(
        context,
        MaterialPageRoute<void>(
            builder: (c) => Scaffold(
                appBar: AppBar(title: const Text('Укажите причину')),
                body: ActionForm(
                    fields: const [
                      InputSpec('reason', 'Причина', multiline: true)
                    ],
                    button: 'Отправить',
                    submit: (v) async {
                      await api.request('/orders/${o['id']}/$command',
                          method: 'POST',
                          body: {...v, 'expected_version': o['version']});
                      if (c.mounted) Navigator.pop(c);
                      reload();
                      success('Запрос сохранён');
                    }))));
  }

  Widget offerScreen() => page(
      'Отклик на заказ',
      loaded(
          '/orders/$objectId',
          (o, reload) => ActionForm(
                  before: [
                    Heading('${o['title']}'),
                    const Notice(
                        'Отправляя отклик, вы подтверждаете актуальные условия заказа.')
                  ],
                  fields: const [
                    InputSpec('amount', 'Ваша цена',
                        keyboard: TextInputType.number),
                    InputSpec('text', 'Комментарий', multiline: true)
                  ],
                  button: 'Отправить отклик',
                  submit: (v) async {
                    final offer = await api.request('/orders/$objectId/offers',
                        method: 'POST',
                        body: {
                          'amount': minor(v['amount']!),
                          'text': v['text'],
                          'acknowledged_revision': o['revision']
                        }) as Json;
                    success('Отклик отправлен');
                    go('chat', offer['conversation_id']);
                  })));
  Widget offersScreen() => page(
      'Список откликов',
      loaded(
          '/orders/$objectId',
          (order, reload) => loaded(
              '/orders/$objectId/offers',
              (data, refresh) => listBody([
                    if (items(data).isEmpty) const Notice('Откликов пока нет'),
                    for (final offer in items(data))
                      DataCard('${offer['text']}',
                          subtitle: money(offer['amount'], offer['currency']),
                          status: status(offer),
                          footer: Column(children: [
                            button('Открыть чат',
                                () => go('chat', offer['conversation_id']),
                                outline: true),
                            if (offer['status'] == 'active' &&
                                order['status'] == 'open')
                              button(
                                  'Выбрать исполнителя',
                                  () => act(() async {
                                        final approved = await showDialog<bool>(
                                            context: context,
                                            builder: (c) => AlertDialog(
                                                    title: const Text(
                                                        'Выбрать исполнителя?'),
                                                    content: const Text(
                                                        'Другие отклики будут закрыты. Условия выбранного отклика будут закреплены в заказе.'),
                                                    actions: [
                                                      TextButton(
                                                          onPressed: () =>
                                                              Navigator.pop(
                                                                  c, false),
                                                          child: const Text(
                                                              'Назад')),
                                                      FilledButton(
                                                          onPressed: () =>
                                                              Navigator.pop(
                                                                  c, true),
                                                          child: const Text(
                                                              'Выбрать'))
                                                    ]));
                                        if (approved != true) return;
                                        await api.request(
                                            '/orders/${order['id']}/select-offer',
                                            method: 'POST',
                                            body: {
                                              'expected_version':
                                                  order['version'],
                                              'offer_id': offer['id'],
                                              'offer_version': offer['version']
                                            });
                                        go('work', order['id']);
                                      }))
                          ])),
                  ]))));
  Widget contractorScreen() => page(
      'Карточка исполнителя',
      loaded(
          '/contractors/$objectId',
          (r, reload) => listBody([
                Heading('${r['title']}', '${r['city']}'),
                Text('${r['description']}'),
                button('Пригласить в заказ', () => go('invite', r['id'])),
                button('Отзывы', () => go('reviews', r['owner']),
                    outline: true),
                button('Пожаловаться', () => go('report', r['id']),
                    outline: true),
                button(
                    'Заблокировать контакт',
                    () => act(() async {
                          await api.request('/me/blocks',
                              method: 'POST',
                              body: {'target_user_id': r['owner']});
                          success('Контакт заблокирован');
                        }),
                    outline: true)
              ])));
  Widget servicesScreen() => page(
      'Мои услуги',
      loaded('/me/contractor-profile', (result, reload) {
        final p = result['profile'] as Json?;
        return ApiView(
            load: () => api.request('/catalog/categories'),
            builder: (c, data, refresh) => ActionForm(
                before: [if (p != null) Notice(status(p))],
                fields: [
                  InputSpec('title', 'Название услуги',
                      initial: p?['title'] ?? '', validate: titleCheck),
                  InputSpec('description', 'О себе и опыте',
                      initial: p?['description'] ?? '',
                      multiline: true,
                      validate: descriptionCheck),
                  InputSpec('category_id', 'Категория',
                      initial: p?['category_id'] ?? '',
                      options: {
                        for (final r in items(data)) r['id']: r['name']
                      }),
                  InputSpec('city', 'Город', initial: p?['city'] ?? me!['city'])
                ],
                submit: (v) async {
                  await api.request('/me/contractor-profile',
                      method: 'PUT',
                      body: {
                        ...v,
                        if (p != null) 'expected_version': p['version']
                      });
                  success('Черновик сохранён');
                  reload();
                },
                after: [
                  if (p != null && p['status'] == 'draft')
                    button(
                        'Отправить на проверку',
                        () => act(() async {
                              await api.request(
                                  '/me/contractor-profile/publish',
                                  method: 'POST',
                                  body: {'expected_version': p['version']});
                              reload();
                            }))
                ]));
      }));
  Widget inviteScreen() {
    final contractor = objectId;
    return page(
        'Пригласить исполнителя',
        paged(
            '/me/orders',
            (o) => DataCard('${o['title']}',
                status: status(o),
                footer: o['status'] == 'open'
                    ? button(
                        'Пригласить',
                        () => act(() async {
                              await api.request('/orders/${o['id']}/invites',
                                  method: 'POST',
                                  body: {'contractor_id': contractor});
                              success('Приглашение отправлено');
                              back();
                            }))
                    : const Text('Для приглашения заказ должен быть открыт'))));
  }

  Widget invitationsScreen() => page(
      'Входящие приглашения',
      paged(
          '/me/order-invites',
          (i) => DataCard('Приглашение в заказ',
              status: status(i),
              onTap: () => go('order', i['order_id']),
              footer: i['status'] == 'pending'
                  ? Column(children: [
                      for (final entry in {
                        'accept': 'Принять',
                        'decline': 'Отклонить'
                      }.entries)
                        button(
                            entry.value,
                            () => act(() async {
                                  await api.request(
                                      '/order-invites/${i['id']}/respond',
                                      method: 'POST',
                                      body: {
                                        'expected_version': i['version'],
                                        'decision': entry.key
                                      });
                                  setState(() => revision++);
                                  success('Ответ сохранён');
                                }),
                            outline: entry.key == 'decline')
                    ])
                  : null)));
  Widget chatScreen(bool support) => page(
      support ? 'Поддержка JOBA' : 'Чат заказа',
      MessageThread(
          key: ValueKey('thread:$objectId'),
          api: api,
          path: support
              ? '/support/threads/$objectId/messages'
              : '/conversations/$objectId/messages',
          owner: me!['id'],
          conversationId: support ? null : objectId,
          revision: revision));
  Widget recoveryChat() {
    if (recovery == null)
      return page(
          'Помощь со входом',
          listBody([
            const Notice('Обращение недоступно. Создайте новое обращение.')
          ]));
    return page(
        'Помощь со входом',
        MessageThread(
            api: api,
            path: '/public/recovery-threads/${recovery!['id']}/messages',
            owner: 'anonymous',
            capability: recovery!['capability'],
            revision: revision));
  }

  Widget supportScreen() => page(
      'Поддержка JOBA',
      Column(children: [
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: button('Начать обращение', () {
              Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                      builder: (c) => Scaffold(
                          appBar: AppBar(title: const Text('Новое обращение')),
                          body: ActionForm(
                              fields: const [
                                InputSpec('subject', 'Тема обращения')
                              ],
                              submit: (v) async {
                                final t = await api.request('/support/threads',
                                    method: 'POST', body: v) as Json;
                                if (c.mounted) Navigator.pop(c);
                                go('support-chat', t['id']);
                              }))));
            })),
        Expanded(
            child: paged(
                '/me/support-threads',
                (t) => DataCard('${t['subject']}',
                    status: status(t),
                    onTap: () => go('support-chat', t['id']))))
      ]));
  Widget reviewScreen() => page(
      'Оценить работу',
      ActionForm(
          fields: const [
            InputSpec('rating', 'Оценка', initial: '5', options: {
              '1': '1 ★',
              '2': '2 ★',
              '3': '3 ★',
              '4': '4 ★',
              '5': '5 ★'
            }),
            InputSpec('text', 'Ваш отзыв', multiline: true, required: false)
          ],
          button: 'Отправить отзыв',
          before: const [
            Notice(
                'Отзывы участников публикуются одновременно или после окончания срока ожидания.')
          ],
          submit: (v) async {
            await api.request('/orders/$objectId/reviews',
                method: 'POST',
                body: {'rating': int.parse(v['rating']!), 'text': v['text']});
            success('Отзыв сохранён');
            back();
          }));
  Widget reportScreen() => page(
      'Сообщить о проблеме',
      ActionForm(
          fields: const [
            InputSpec('target_type', 'Тип объекта', initial: 'order', options: {
              'order': 'Заказ',
              'contractor': 'Услуга',
              'user': 'Пользователь',
              'message': 'Сообщение'
            }),
            InputSpec('reason_code', 'Причина', initial: 'other', options: {
              'spam': 'Спам',
              'fraud': 'Подозрение на обман',
              'content': 'Нарушение содержания',
              'other': 'Другая причина'
            }),
            InputSpec('description', 'Опишите ситуацию', multiline: true)
          ],
          button: 'Отправить жалобу',
          submit: (v) async {
            await api.request('/cases',
                method: 'POST', body: {...v, 'target_id': objectId});
            success('Жалоба отправлена');
            go('cases');
          }));
  Widget caseScreen() => page(
      'Обращение',
      loaded(
          '/cases/$objectId',
          (data, reload) => listBody([
                DataCard('${data['reason_code'] ?? 'Обращение'}',
                    status: status(data),
                    subtitle: '${data['description'] ?? ''}'),
                button('Написать по обращению',
                    () => caseForm(false, data, reload),
                    outline: true),
                if (data['subject_user_id'] == me!['id'] &&
                    ['resolved', 'restricted'].contains(data['status']))
                  button(
                      'Обжаловать решение', () => caseForm(true, data, reload)),
              ])));
  void caseForm(bool appeal, Json data, VoidCallback reload) => Navigator.push(
      context,
      MaterialPageRoute<void>(
          builder: (c) => Scaffold(
              appBar: AppBar(
                  title: Text(appeal ? 'Апелляция' : 'Сообщение по обращению')),
              body: ActionForm(
                  fields: [
                    InputSpec(appeal ? 'reason' : 'text', 'Ваше сообщение',
                        multiline: true)
                  ],
                  submit: (v) async {
                    await api.request(
                        '/cases/${data['id']}/${appeal ? 'appeals' : 'messages'}',
                        method: 'POST',
                        body: {
                          ...v,
                          if (appeal) 'expected_version': data['version']
                        });
                    if (c.mounted) Navigator.pop(c);
                    reload();
                  }))));
  Widget accessScreen() => page(
      'Мой доступ',
      ApiView(
          key: ValueKey('access:$revision'),
          load: () => Future.wait([
                api.request('/me/entitlements'),
                api.request('/me/monetization-config'),
                api.request('/me/subscriptions')
              ]),
          builder: (c, data, reload) => listBody([
                const Heading('Ваши возможности'),
                if (items(data[0]).isEmpty)
                  const Notice('Активных прав доступа пока нет.'),
                for (final r in items(data[0]))
                  DataCard('Доступ JOBA',
                      status: status(r),
                      subtitle:
                          '${r['valid_until'] ?? r['ends_at'] ?? r['expires_at'] ?? ''}'),
                for (final r in items(data[2]))
                  DataCard('Подписка',
                      status: status(r), subtitle: '${r['ends_at'] ?? ''}'),
                const Notice(
                    'Оплата и восстановление покупок станут доступны после подключения платёжной системы.'),
                button('Рекламная награда', () => go('reward'), outline: true),
                button('Поддержка', () => go('support'), outline: true),
              ])));
  Widget privacyScreen() => page(
      'Приватность',
      loaded(
          '/me/privacy-requests',
          (data, reload) => listBody([
                const Heading('Ваши данные'),
                for (final r in items(data))
                  DataCard(
                      r['type'] == 'export'
                          ? 'Экспорт данных'
                          : 'Удаление аккаунта',
                      status: status(r),
                      footer: Column(children: [
                        if (r['type'] == 'export' &&
                            r['status'] == 'completed' &&
                            r['upload_id'] != null)
                          button(
                              'Сохранить архив',
                              () => act(() async {
                                    final bytes =
                                        await api.download(r['upload_id']);
                                    final saved = await FilePicker.platform
                                        .saveFile(
                                            dialogTitle:
                                                'Сохранить данные JOBA',
                                            fileName: 'joba-export.json',
                                            type: FileType.custom,
                                            allowedExtensions: ['json'],
                                            bytes: bytes);
                                    if (saved != null)
                                      success('Архив сохранён');
                                  })),
                        if (['requested', 'awaiting_retention_policy']
                            .contains(r['status']))
                          button(
                              'Отменить запрос',
                              () => act(() async {
                                    await api.request(
                                        '/me/privacy-requests/${r['id']}/cancel',
                                        method: 'POST',
                                        body: {
                                          'expected_version': r['version']
                                        });
                                    reload();
                                  }),
                              outline: true),
                      ])),
                button('Обновить статус', reload, outline: true),
                button('Экспортировать данные',
                    () => privacyRequest('export', reload)),
                button(
                    'Удалить аккаунт', () => privacyRequest('delete', reload),
                    outline: true),
                button('Согласия и документы', () => go('terms'),
                    outline: true),
              ])));
  void privacyRequest(String type, VoidCallback reload) => Navigator.push(
      context,
      MaterialPageRoute<void>(
          builder: (c) => Scaffold(
              appBar: AppBar(
                  title: Text(type == 'export'
                      ? 'Экспорт данных'
                      : 'Удаление аккаунта')),
              body: ActionForm(
                  before: [
                    Notice(type == 'export'
                        ? 'Запрос будет обработан сервером. Пароли и закрытые служебные данные не включаются.'
                        : 'Запрос затрагивает обе роли. Обработка зависит от действующих сроков хранения и открытых дел.')
                  ],
                  fields: const [
                    InputSpec('current_password', 'Текущий пароль',
                        secret: true)
                  ],
                  button: 'Создать запрос',
                  submit: (v) async {
                    await api.request('/me/privacy-requests',
                        method: 'POST', body: {...v, 'type': type});
                    if (c.mounted) Navigator.pop(c);
                    success('Запрос создан');
                    reload();
                  }))));
  Widget securityScreen() => page(
      'Безопасность',
      loaded(
          '/me/sessions',
          (data, reload) => listBody([
                button('Изменить пароль', () => go('password'), outline: true),
                button('Изменить номер телефона', () => go('phone'),
                    outline: true),
                button('Настроить PIN и биометрию', () => go('lock-setup'),
                    outline: true),
                button('Заблокированные контакты', () => go('blocks'),
                    outline: true),
                button('Завершить все сессии', () => go('logout-all'),
                    outline: true),
                for (final r in items(data))
                  DataCard('Сессия',
                      subtitle: 'Действует до ${r['expires_at']}',
                      footer: button(
                          'Завершить сессию',
                          () => act(() async {
                                await api.request('/me/sessions/${r['family']}',
                                    method: 'DELETE');
                                reload();
                              }),
                          outline: true)),
              ])));
  Widget passwordScreen() => page(
      'Изменить пароль',
      ActionForm(
          fields: const [
            InputSpec('current_password', 'Текущий пароль', secret: true),
            InputSpec('new_password', 'Новый пароль', secret: true),
            InputSpec('repeat', 'Повторите новый пароль', secret: true)
          ],
          submit: (v) async {
            if (v['new_password'] != v['repeat'])
              throw ApiException('VALIDATION_ERROR', 'Пароли не совпадают');
            await api.request('/me/password/change', method: 'POST', body: {
              'current_password': v['current_password'],
              'new_password': v['new_password']
            });
            success('Пароль изменён');
            back();
          }));
  Widget phoneScreen() => page(
      'Изменить номер',
      ActionForm(
          fields: const [
            InputSpec('new_phone', 'Новый номер',
                keyboard: TextInputType.phone),
            InputSpec('current_password', 'Текущий пароль', secret: true)
          ],
          before: const [
            Notice(
                'Номер остаётся неподтверждённым идентификатором. Другие сессии будут завершены.')
          ],
          submit: (v) async {
            await api.request('/me/phone-change-requests',
                method: 'POST', body: v);
            success('Номер изменён');
            back();
          }));
  Widget settingsScreen() => page(
      'Настройки',
      listBody([
        button('Язык и профиль', () => go('onboarding'), outline: true),
        button('Уведомления', () => go('notification-settings'), outline: true),
        button('Безопасность', () => go('security'), outline: true),
        button('Документы и согласия', () => go('terms'), outline: true),
        Notice('Страна услуг: ${me?['country'] ?? country}')
      ]));
  Widget notificationSettings() => page(
      'Уведомления',
      ApiView(
          load: () => Future.wait([
                api.request('/me'),
                api.request('/me/notification-preferences')
              ]),
          builder: (c, data, reload) => ActionForm(
                  fields: [
                    for (final e in {
                      'chat': 'Сообщения чата',
                      'service': 'Сервисные уведомления',
                      'marketing': 'Реклама'
                    }.entries)
                      InputSpec(e.key, e.value,
                          initial: '${data[1][e.key]}',
                          options: const {
                            'true': 'Включены',
                            'false': 'Отключены'
                          })
                  ],
                  submit: (v) async {
                    await api.request('/me/notification-preferences',
                        method: 'PATCH',
                        body: {
                          'expected_version': data[0]['version'],
                          'preferences': {
                            for (final e in v.entries) e.key: e.value == 'true'
                          }
                        });
                    success('Настройки сохранены');
                    back();
                  })));
  Widget referralsScreen() => page(
      'Приглашения и бонусы',
      loaded(
          '/me/referrals',
          (data, reload) => listBody([
                const Heading('Пригласите друзей'),
                DataCard('Ваш код',
                    subtitle: '${data['code']}',
                    footer: button(
                        'Скопировать код',
                        () => act(() async {
                              await Clipboard.setData(
                                  ClipboardData(text: data['code']));
                              success('Код скопирован');
                            }),
                        outline: true)),
                if ((data['campaigns'] as List).isEmpty)
                  const Notice('Активных программ приглашений пока нет.'),
                for (final r in (data['rewards'] as List).cast<Json>())
                  DataCard('Награда',
                      status: status(r),
                      footer: r['status'] == 'available'
                          ? button(
                              'Активировать',
                              () => act(() async {
                                    await api.request(
                                        '/me/referral-rewards/${r['id']}/redeem',
                                        method: 'POST');
                                    reload();
                                  }))
                          : null),
                button(
                    'Ввести код приглашения',
                    () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                            builder: (c) => Scaffold(
                                appBar: AppBar(
                                    title: const Text('Код приглашения')),
                                body: ActionForm(
                                    fields: const [InputSpec('code', 'Код')],
                                    submit: (v) async {
                                      await api.request('/referrals/attribute',
                                          method: 'POST', body: v);
                                      if (c.mounted) Navigator.pop(c);
                                      reload();
                                    })))),
                    outline: true),
              ])));
  Widget portfolioScreen() => page(
          'Моё портфолио',
          loaded('/me/portfolio-projects', (data, reload) {
            final projects = items(data)
              ..sort((a, b) =>
                  (a['position'] as int).compareTo(b['position'] as int));
            return listBody([
              if (projects.isEmpty) const Notice('Добавьте свой первый проект'),
              for (var i = 0; i < projects.length; i++)
                DataCard(projects[i]['title'],
                    subtitle: projects[i]['description'],
                    status: status(projects[i]),
                    onTap: () => go('portfolio-project', projects[i]['id']),
                    footer: Row(children: [
                      IconButton(
                          tooltip: 'Выше',
                          onPressed: i == 0
                              ? null
                              : () =>
                                  reorderProject(projects, i, i - 1, reload),
                          icon: const Icon(Icons.arrow_upward)),
                      IconButton(
                          tooltip: 'Ниже',
                          onPressed: i == projects.length - 1
                              ? null
                              : () =>
                                  reorderProject(projects, i, i + 1, reload),
                          icon: const Icon(Icons.arrow_downward)),
                    ])),
            ]);
          }),
          actions: [
            IconButton(
                tooltip: 'Добавить проект',
                onPressed: () => go('portfolio-project'),
                icon: const Icon(Icons.add))
          ]);
  void reorderProject(
          List<Json> projects, int from, int to, VoidCallback reload) =>
      act(() async {
        final ids = projects.map((p) => p['id']).toList();
        final id = ids.removeAt(from);
        ids.insert(to, id);
        await api
            .request('/me/portfolio-projects/reorder', method: 'POST', body: {
          'project_ids': ids,
          'expected_versions': {for (final p in projects) p['id']: p['version']}
        });
        reload();
      });
  Widget projectScreen() => page(
      objectId == null ? 'Новый проект' : 'Проект и фото',
      ApiView(
          key: ValueKey('project:$objectId:$revision'),
          load: () => Future.wait([
                api.request('/catalog/categories'),
                objectId == null
                    ? Future.value(null)
                    : api.request('/me/portfolio-projects/$objectId')
              ]),
          builder: (c, data, reload) {
            final p = data[1] as Json?;
            return ActionForm(
                fields: [
                  InputSpec('title', 'Название проекта',
                      initial: p?['title'] ?? '', validate: titleCheck),
                  InputSpec('description', 'Описание',
                      initial: p?['description'] ?? '',
                      multiline: true,
                      required: false),
                  InputSpec('category_id', 'Категория',
                      initial: p?['category_id'] ?? '',
                      options: {
                        for (final r in items(data[0])) r['id']: r['name']
                      }),
                  InputSpec('rights_confirmed',
                      'У меня есть права на публикацию материалов',
                      initial: '${p?['rights_confirmed'] ?? false}',
                      options: const {
                        'false': 'Не подтверждено',
                        'true': 'Подтверждаю'
                      })
                ],
                submit: (v) async {
                  final saved = await api.request(
                      p == null
                          ? '/me/portfolio-projects'
                          : '/me/portfolio-projects/${p['id']}',
                      method: p == null ? 'POST' : 'PATCH',
                      body: {
                        ...v,
                        'rights_confirmed': v['rights_confirmed'] == 'true',
                        if (p != null) 'expected_version': p['version']
                      }) as Json;
                  success('Проект сохранён');
                  go('portfolio-project', saved['id']);
                },
                after: [
                  if (p != null) ...[
                    Notice(
                        '${status(p)} · ${(p['photos'] as List).length} фото'),
                    for (final photo in p['photos'] as List) ...[
                      PrivatePhoto(api: api, id: photo),
                      Row(children: [
                        Expanded(
                            child: button(
                                'Обложка',
                                () => act(() async {
                                      await api.request(
                                          '/me/portfolio-projects/${p['id']}',
                                          method: 'PATCH',
                                          body: {
                                            'expected_version': p['version'],
                                            'cover_id': photo
                                          });
                                      reload();
                                    }),
                                outline: true)),
                        const SizedBox(width: 12),
                        Expanded(
                            child: button(
                                'Удалить фото',
                                () => act(() async {
                                      final photos = (p['photos'] as List)
                                          .where((id) => id != photo)
                                          .toList();
                                      await api.request(
                                          '/me/portfolio-projects/${p['id']}',
                                          method: 'PATCH',
                                          body: {
                                            'expected_version': p['version'],
                                            'upload_ids': photos,
                                            if (photos.isNotEmpty &&
                                                p['cover_id'] == photo)
                                              'cover_id': photos.first
                                          });
                                      reload();
                                    }),
                                outline: true))
                      ]),
                      const SizedBox(height: 16),
                    ],
                    button(
                        'Добавить фотографию',
                        () => act(() async {
                              final upload = await pickUpload('portfolio');
                              if (upload == null) return;
                              await api.request(
                                  '/me/portfolio-projects/${p['id']}',
                                  method: 'PATCH',
                                  body: {
                                    'expected_version': p['version'],
                                    'upload_ids': [...p['photos'], upload['id']]
                                  });
                              reload();
                            }),
                        outline: true),
                    button(
                        'Отправить на проверку',
                        () => act(() async {
                              await api.request(
                                  '/me/portfolio-projects/${p['id']}/submit',
                                  method: 'POST',
                                  body: {'expected_version': p['version']});
                              reload();
                            })),
                    button(
                        'Удалить проект',
                        () => act(() async {
                              await api.request(
                                  '/me/portfolio-projects/${p['id']}',
                                  method: 'DELETE',
                                  body: {'expected_version': p['version']});
                              go('portfolio');
                            }),
                        outline: true)
                  ]
                ]);
          }));
  Future<Json?> pickUpload(String purpose, {String? verificationId}) async {
    final selected = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png'],
        withData: true);
    if (selected == null) return null;
    final f = selected.files.single;
    if (f.bytes == null)
      throw ApiException('FILE_UNAVAILABLE', 'Не удалось прочитать файл');
    return api.upload(
        f.bytes!,
        f.extension?.toLowerCase() == 'png' ? 'image/png' : 'image/jpeg',
        purpose,
        verificationId: verificationId);
  }

  Widget verificationScreen() => page(
      'Документ исполнителя',
      loaded(
          '/me/verification',
          (data, reload) => listBody([
                const Heading('Проверка исполнителя',
                    'Документы доступны только уполномоченным сотрудникам.'),
                Notice(states[data['status']] ?? '${data['status']}'),
                for (final r in items(data))
                  DataCard('${r['document_type']}',
                      status: status(r),
                      footer: ['draft', 'rejected'].contains(r['status'])
                          ? button(
                              'Загрузить и отправить документ',
                              () => act(() async {
                                    final file = await pickUpload('identity',
                                        verificationId: r['id']);
                                    if (file == null) return;
                                    await api.request(
                                        '/me/verification-sessions/${r['id']}/submit',
                                        method: 'POST',
                                        body: {
                                          'expected_version': r['version'],
                                          'upload_ids': [file['id']]
                                        });
                                    reload();
                                  }))
                          : null),
                button(
                    'Начать проверку',
                    () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                            builder: (c) => Scaffold(
                                appBar:
                                    AppBar(title: const Text('Тип документа')),
                                body: ActionForm(
                                    fields: const [
                                      InputSpec(
                                          'document_type', 'Тип документа')
                                    ],
                                    before: const [
                                      Notice(
                                          'Разрешённые типы и основание проверки определяются утверждённой политикой страны.')
                                    ],
                                    submit: (v) async {
                                      await api.request(
                                          '/me/verification-sessions',
                                          method: 'POST',
                                          body: v);
                                      if (c.mounted) Navigator.pop(c);
                                      reload();
                                    })))),
                    outline: true),
                button('Документы и согласие', () => go('terms'),
                    outline: true),
              ])));
  Widget termsScreen() => page(
      'Документы и согласия',
      loaded(
          '/legal/documents',
          (data, reload) => listBody([
                const Heading('Условия JOBA'),
                if (items(data).isEmpty)
                  const Notice('Утверждённые документы ещё не опубликованы.'),
                for (final d in items(data))
                  DataCard('${d['title'] ?? d['type']}',
                      subtitle: '${d['content'] ?? d['text'] ?? ''}',
                      footer: button(
                          'Принять эту версию',
                          () => act(() async {
                                await api.request('/me/consents',
                                    method: 'POST',
                                    body: {
                                      'document_id': d['id'],
                                      'document_hash': d['hash'],
                                      'accepted': true
                                    });
                                success('Согласие сохранено');
                              }))),
                button('Продолжить', () => go('home')),
              ]),
          query: {'country': country, 'locale': me?['locale'] ?? 'ru'}));
  void vote(Json r, int value) => act(() async {
        await api.request(
            '/listing-votes/${executor ? 'orders' : 'services'}/${r['id']}',
            method: 'PUT',
            body: {'value': value});
        setState(() => revision++);
      });
  Widget promotionScreen() => page(
      'Продвинуть объявление',
      loaded(
          '/me/boosts',
          (data, reload) => listBody([
                const Heading('Больше внимания к вашей работе'),
                const Notice(
                    'Оплата продвижений станет доступна после подключения платёжной системы.'),
                for (final r in items(data))
                  DataCard('Размещение',
                      status: status(r),
                      subtitle: '${r['starts_at']} — ${r['ends_at']}'),
                button('Поддержка', () => go('support'), outline: true),
              ])));
}

class MessageThread extends StatefulWidget {
  final JobaApi api;
  final String path, owner;
  final String? capability, conversationId;
  final int revision;
  const MessageThread(
      {required this.api,
      required this.path,
      required this.owner,
      this.capability,
      this.conversationId,
      required this.revision,
      super.key});
  @override
  State<MessageThread> createState() => _MessageThreadState();
}

class _MessageThreadState extends State<MessageThread> {
  final text = TextEditingController();
  final scroll = ScrollController();
  final List<Json> messages = [];
  final List<Json> attachments = [];
  String? error, pendingId;
  bool loading = false, sending = false, uploading = false;
  bool readBusy = false;
  int lastReadSequence = 0;
  String? updatedSince;
  bool moreHistory = false, historyBusy = false;
  bool reloadPending = false, scrollPending = false;
  Timer? polling;
  @override
  void initState() {
    super.initState();
    scroll.addListener(markRead);
    load();
    polling = Timer.periodic(const Duration(seconds: 5), (_) => load());
  }

  @override
  void didUpdateWidget(MessageThread old) {
    super.didUpdateWidget(old);
    if (old.revision != widget.revision) load();
  }

  Future<void> load({bool forceScroll = false}) async {
    if (loading || historyBusy) {
      reloadPending = true;
      scrollPending = scrollPending || forceScroll;
      return;
    }
    loading = true;
    final atBottom = forceScroll ||
        messages.isEmpty ||
        scroll.hasClients && scroll.position.extentAfter < 60;
    try {
      final initial = messages.isEmpty;
      var after = initial ? 0 : messages.last['sequence'] as int;
      while (mounted) {
        var result = await widget.api.request(widget.path,
            query: {
              if (!initial) 'after_sequence': after,
              if (updatedSince != null) 'updated_since': updatedSince
            },
            authenticated: widget.capability == null,
            capability: widget.capability) as Json;
        final reset = result['meta']?['updates_truncated'] == true;
        if (reset) {
          result = await widget.api.request(widget.path) as Json;
          messages.clear();
        }
        final batch = items(result);
        for (final m in batch) merge(m);
        for (final m in ((result['updates'] as List?) ?? []).cast<Json>()) {
          if (messages.any((old) => old['id'] == m['id'])) merge(m);
        }
        messages.sort(
            (a, b) => (a['sequence'] as int).compareTo(b['sequence'] as int));
        updatedSince = result['meta']?['server_time'] ?? updatedSince;
        if (initial || reset) moreHistory = result['meta']?['has_more'] == true;
        if (initial || batch.length < 100 || widget.capability != null) break;
        after = batch.last['sequence'];
      }
      if (mounted) setState(() => error = null);
      if (mounted)
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !scroll.hasClients) return;
          if (atBottom) scroll.jumpTo(scroll.position.maxScrollExtent);
          markRead();
        });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      loading = false;
      resumePending();
    }
  }

  void resumePending() {
    if (!mounted || !reloadPending || loading || historyBusy) return;
    final scroll = scrollPending;
    reloadPending = false;
    scrollPending = false;
    load(forceScroll: scroll);
  }

  void merge(Json message) {
    final index = messages.indexWhere((m) => m['id'] == message['id']);
    if (index < 0) {
      messages.add(message);
    } else {
      messages[index] = message;
    }
  }

  Future<void> older() async {
    if (historyBusy || loading || messages.isEmpty) return;
    setState(() => historyBusy = true);
    final oldPixels = scroll.hasClients ? scroll.position.pixels : 0.0;
    final oldMax = scroll.hasClients ? scroll.position.maxScrollExtent : 0.0;
    try {
      final result = await widget.api.request(widget.path,
          query: {'before_sequence': messages.first['sequence']}) as Json;
      for (final m in items(result)) merge(m);
      messages.sort(
          (a, b) => (a['sequence'] as int).compareTo(b['sequence'] as int));
      if (mounted)
        setState(() => moreHistory = result['meta']?['has_more'] == true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && scroll.hasClients)
          scroll.jumpTo((oldPixels + scroll.position.maxScrollExtent - oldMax)
              .clamp(0, scroll.position.maxScrollExtent));
      });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => historyBusy = false);
      resumePending();
    }
  }

  void edit(Json message) => Navigator.push(
      context,
      MaterialPageRoute<void>(
          builder: (c) => Scaffold(
              appBar: AppBar(title: const Text('Изменить сообщение')),
              body: ActionForm(
                  fields: [
                    InputSpec('text', 'Сообщение',
                        initial: message['text'], multiline: true)
                  ],
                  submit: (v) async {
                    final saved = await widget.api.request(
                        '/messages/${message['id']}',
                        method: 'PATCH',
                        body: {
                          ...v,
                          'expected_version': message['version']
                        }) as Json;
                    merge(saved);
                    if (c.mounted) Navigator.pop(c);
                    await load();
                  }))));
  Future<void> messageMenu(Json message) async {
    if (message['owner'] != widget.owner ||
        widget.conversationId == null ||
        message['tombstone'] == true) return;
    final choice = await showModalBottomSheet<String>(
        context: context,
        builder: (c) => SafeArea(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(
                  title: const Text('Изменить'),
                  onTap: () => Navigator.pop(c, 'edit')),
              ListTile(
                  title: const Text('Удалить'),
                  onTap: () => Navigator.pop(c, 'delete')),
            ])));
    if (!mounted) return;
    if (choice == 'edit') edit(message);
    if (choice == 'delete') {
      try {
        final saved = await widget.api.request('/messages/${message['id']}',
            method: 'DELETE',
            body: {'expected_version': message['version']}) as Json;
        merge(saved);
        await load();
      } catch (e) {
        if (mounted) setState(() => error = '$e');
      }
    }
  }

  Future<void> markRead() async {
    if (!mounted ||
        readBusy ||
        widget.conversationId == null ||
        messages.isEmpty ||
        !scroll.hasClients ||
        scroll.position.extentAfter > 60) return;
    final sequence = messages.last['sequence'] as int;
    if (sequence <= lastReadSequence) return;
    readBusy = true;
    try {
      await widget.api.request('/conversations/${widget.conversationId}/read',
          method: 'POST', body: {'sequence': sequence});
      lastReadSequence = sequence;
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      readBusy = false;
    }
  }

  Future<void> send() async {
    if (sending || uploading || text.text.trim().isEmpty && attachments.isEmpty)
      return;
    setState(() => sending = true);
    pendingId ??= uuid.v4();
    try {
      final saved = await widget.api.request(widget.path,
          method: 'POST',
          body: {
            'text': text.text,
            'client_message_id': pendingId,
            'upload_ids': attachments.map((f) => f['id']).toList()
          },
          key: pendingId,
          authenticated: widget.capability == null,
          capability: widget.capability) as Json;
      merge(saved);
      text.clear();
      attachments.clear();
      pendingId = null;
      await load(forceScroll: true);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> attach() async {
    if (uploading || sending) return;
    setState(() => uploading = true);
    try {
      final selection = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
          withData: true);
      if (selection == null) return;
      final file = selection.files.single;
      if (file.bytes == null)
        throw ApiException('FILE_UNAVAILABLE', 'Не удалось прочитать файл');
      final mime = file.extension?.toLowerCase() == 'pdf'
          ? 'application/pdf'
          : file.extension?.toLowerCase() == 'png'
              ? 'image/png'
              : 'image/jpeg';
      final uploaded = await widget.api.upload(file.bytes!, mime, 'chat');
      if (uploaded['status'] != 'clean')
        throw ApiException('UNSAFE_UPLOAD', 'Файл не прошёл проверку');
      if (mounted)
        setState(() {
          attachments.add(uploaded);
          pendingId = null;
          error = null;
        });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }

  @override
  void dispose() {
    polling?.cancel();
    text.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        if (error != null)
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Notice(error!, error: true)),
        Expanded(
            child: messages.isEmpty
                ? Center(
                    child: loading
                        ? const CircularProgressIndicator()
                        : const Text('Начните разговор'))
                : ListView.builder(
                    controller: scroll,
                    padding: const EdgeInsets.all(20),
                    itemCount: messages.length + (moreHistory ? 1 : 0),
                    itemBuilder: (c, i) {
                      if (moreHistory && i == 0)
                        return TextButton(
                            onPressed: historyBusy ? null : older,
                            child: Text(historyBusy
                                ? 'Загрузка…'
                                : 'Показать ранние сообщения'));
                      final m = messages[i - (moreHistory ? 1 : 0)],
                          own = m['owner'] == widget.owner;
                      return GestureDetector(
                          onLongPress: () => messageMenu(m),
                          child: Align(
                              alignment: own
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: Container(
                                  constraints:
                                      const BoxConstraints(maxWidth: 290),
                                  padding: const EdgeInsets.all(12),
                                  margin: const EdgeInsets.only(bottom: 12),
                                  decoration: BoxDecoration(
                                      color: own
                                          ? const Color(0xFFEFF4FD)
                                          : canvas,
                                      borderRadius: BorderRadius.circular(14)),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(m['tombstone'] == true
                                            ? 'Сообщение удалено'
                                            : m['hidden'] == true
                                                ? 'Сообщение временно скрыто'
                                                : m['text'] ?? ''),
                                        for (final id
                                            in (m['upload_ids'] as List? ?? []))
                                          AttachmentView(
                                              api: widget.api, id: id),
                                        if (own)
                                          Text(
                                              const {
                                                    'sent': 'Отправлено',
                                                    'delivered': 'Доставлено',
                                                    'read': 'Прочитано',
                                                    'quarantined': 'На проверке'
                                                  }[m['delivery_state']] ??
                                                  'Отправлено',
                                              style:
                                                  const TextStyle(fontSize: 10))
                                      ]))));
                    })),
        SafeArea(
            top: false,
            child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  if (widget.capability == null)
                    IconButton(
                        tooltip: 'Добавить файл',
                        onPressed: sending || uploading ? null : attach,
                        icon: uploading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.attach_file)),
                  Expanded(
                      child: TextField(
                          controller: text,
                          minLines: 1,
                          maxLines: 4,
                          enabled: !sending,
                          onChanged: (_) => pendingId = null,
                          decoration:
                              const InputDecoration(hintText: 'Сообщение'))),
                  IconButton(
                      tooltip: 'Отправить',
                      onPressed: sending ? null : send,
                      icon: sending
                          ? const CircularProgressIndicator()
                          : const Icon(Icons.send, color: primary)),
                ]))),
        if (attachments.isNotEmpty)
          Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Wrap(children: [
                for (final file in attachments)
                  InputChip(
                      label: Text(file['mime'].startsWith('image/')
                          ? 'Фотография'
                          : 'PDF'),
                      onDeleted: sending
                          ? null
                          : () => setState(() {
                                attachments.remove(file);
                                pendingId = null;
                              })),
              ])),
      ]);
}

class AttachmentView extends StatelessWidget {
  final JobaApi api;
  final String id;
  const AttachmentView({required this.api, required this.id, super.key});
  @override
  Widget build(BuildContext context) => ApiView(
      load: () => api.request('/uploads/$id/metadata'),
      builder: (c, meta, reload) {
        if (meta['mime'].startsWith('image/'))
          return PrivatePhoto(api: api, id: id);
        return TextButton.icon(
            icon: const Icon(Icons.file_download_outlined),
            label: const Text('Сохранить вложение'),
            onPressed: () async {
              try {
                final bytes = await api.download(id);
                await FilePicker.platform.saveFile(
                    dialogTitle: 'Сохранить вложение JOBA',
                    fileName: 'joba-attachment.pdf',
                    bytes: bytes);
              } catch (e) {
                if (context.mounted)
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text('$e')));
              }
            });
      });
}
