import '../core/design_states.dart';
import 'search_filters.dart';
import 'support_new.dart';
import 'legal_documents.dart';
import 'account_restrictions.dart';
import 'appeal_editor.dart';
import 'action_receipt.dart';
import 'portfolio_detail.dart';
import 'contractor_profile.dart';
import 'onboarding_consent.dart';
import 'city_selector.dart';
import '../core/share_invitation.dart';
import 'verification_editor.dart';
import 'dart:async';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../core/api.dart';
import '../core/regions.dart';
import 'profile_editor.dart';
import 'invite_editor.dart';
import '../core/theme.dart';
import '../core/design_icons.dart';
import '../core/design_widgets.dart';
import '../core/l10n.dart';
import '../core/widgets.dart';
import '../core/local_lock.dart';
import '../core/export_saver.dart';
import '../core/currency.dart';

const states = {
  'draft': 'Черновик',
  'not_started': 'Не начата',
  'busy': 'Занят',
  'archived': 'В архиве',
  'approved': 'Одобрено',
  'effective': 'Действует',
  'not_selected': 'Выбран другой исполнитель',
  'paused': 'На паузе',
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
  'expired': 'Срок истёк',
  'revoked': 'Отозвано',
  'restricted': 'Ограничено',
  'appealed': 'Апелляция на рассмотрении',
  'failed': 'Обработка не завершена',
  'available': 'Можно активировать',
  'redeemed': 'Активирована',
  'awaiting_retention_policy': 'Ожидается проверка сроков хранения',
  'limited_retention': 'Аккаунт закрыт; часть записей сохраняется по правилам'
};
const eventTitles = {
  'verification.updated': 'Результат проверки документа',
  'offer.created': 'Новый отклик на заказ',
  'order.selected': 'Вы выбраны исполнителем',
  'invite.created': 'Приглашение в заказ',
  'message.created': 'Новое сообщение',
  'support.message.created': 'Ответ поддержки',
  'case.message.created': 'Сообщение по обращению',
  'case.updated': 'Статус обращения обновлён',
  'content.moderated': 'Материал проверен модерацией',
  'privacy.export.ready': 'Архив данных готов',
  'cancel_request.accepted': 'Отмена согласована',
  'cancel_request.rejected': 'Отмена отклонена',
  'amendment.accepted': 'Новые условия согласованы',
  'amendment.rejected': 'Новые условия отклонены'
};
String status(Json r) => states[r['status']] ?? '${r['status'] ?? ''}';
String money(dynamic amount, [String currency = 'KZT', String locale = 'ru']) =>
    amount == null
        ? 'По договорённости'
        : formatMoney((amount as num).toInt(), currency, locale);
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
  final ValueChanged<String>? onLocaleChanged;
  final RegionGateway? regions;
  final DevicePreferences? preferences;
  const Marketplace(
      {this.api,
      this.onLocaleChanged,
      this.regions,
      this.preferences,
      super.key});
  @override
  State<Marketplace> createState() => _MarketplaceState();
}

class _MarketplaceState extends State<Marketplace> with WidgetsBindingObserver {
  JobaApi? _api;
  JobaApi get api => _api!;
  RegionGateway? regions;
  DevicePreferences? preferences;
  Json? me, recovery;
  String country = 'KZ', route = 'welcome';
  String locale = 'ru';
  String? pendingLocale;
  bool registrationInProgress = false;
  String? draftCategory;
  Set<String>? serviceCategories;
  String? objectId;
  Json listingFilters = {};
  bool? ordersHasAny;
  String catalogPresentation = 'loading';
  String ordersBucket = 'active';
  final List<String> draftPhotos = [];
  final Map<String, List<String>> verificationUploads = {};
  Json? draftWindow;
  bool offerAcknowledged = false, selectionAcknowledged = false;
  int? acknowledgedOrderRevision;
  String? acknowledgedSelection;
  String cancellationReason = 'plans';
  int reviewRating = 0;
  final List<(String, String?)> history = [];
  bool starting = true, executor = false, actionBusy = false;
  Object? startupError;
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
    _api = widget.api;
    regions = widget.regions ??
        (widget.api == null ? RegionGateway.environment() : null);
    preferences = widget.preferences ??
        (widget.api == null
            ? DevicePreferences(SecureSessionVault('joba.device.preferences'))
            : null);
    _api?.addListener(sessionChanged);
    initialize();
  }

  Future<void> initialize() async {
    try {
      if (preferences != null) {
        final saved = await preferences!.read();
        if (!mounted) return;
        country = saved['country'];
        locale = saved['locale'];
        widget.onLocaleChanged?.call(locale);
      }
      if (regions != null && widget.api == null)
        replaceApi(regions!.create(country));
      await api.restore(refreshSession: false);
      if (!mounted) return;
      if (regions != null &&
          api.authenticated &&
          api.session?['user']?['country'] != country) await api.forget();
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
      startupError = e;
    }
    if (mounted) setState(() => starting = false);
  }

  void replaceApi(JobaApi next) {
    closeEvents();
    final previous = _api;
    previous?.removeListener(sessionChanged);
    _api = next;
    api.addListener(sessionChanged);
    if (widget.api != previous) previous?.dispose();
    sequence = 0;
  }

  Future<void> chooseCountry(String next) async {
    if (next == country && _api != null) return;
    final replacement = regions?.create(next);
    try {
      if (_api?.authenticated == true) await api.logout();
      await preferences?.save(next, locale);
      if (!mounted) {
        replacement?.dispose();
        return;
      }
      if (replacement != null) replaceApi(replacement);
      setState(() {
        country = next;
        recovery = null;
        objectId = null;
        listingFilters = {};
        serviceCategories = null;
        draftCategory = null;
        draftPhotos.clear();
        verificationUploads.clear();
        draftWindow = null;
        history.clear();
        reportUploads.clear();
        pendingLocale = null;
        revision++;
      });
    } catch (_) {
      replacement?.dispose();
      rethrow;
    }
  }

  Future<void> chooseGuestLocale(String next) async {
    await preferences?.save(country, next);
    if (!mounted) return;
    setState(() => locale = next);
    widget.onLocaleChanged?.call(next);
  }

  void sessionChanged() {
    if (!mounted) return;
    if (!api.authenticated) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
      });
      closeEvents();
      sequence = 0;
      lock?.clear();
      locked = false;
      localProtected = false;
      setState(() {
        me = null;
        ordersHasAny = null;
        recovery = null;
        draftPhotos.clear();
        verificationUploads.clear();
        draftWindow = null;
        registrationInProgress = false;
        route = api.sessionExpired ? 'session-expired' : 'login';
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

  Future<void> refreshIdentity() async {
    final client = api, generation = api.sessionGeneration, id = me?['id'];
    try {
      final profile = await client.request('/me') as Json;
      if (mounted &&
          identical(_api, client) &&
          client.sessionGeneration == generation &&
          profile['id'] == id) {
        setState(() {
          me = profile;
          executor = profile['active_role'] == 'executor';
        });
      }
    } catch (_) {/* Background refresh retains the last confirmed state. */}
  }

  void connectEvents() {
    closeEvents();
    if (!api.authenticated || !mounted || locked) return;
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
        if ([
          'content.moderated',
          'verification.updated',
          'entitlement.changed',
          'case.updated',
          'sanction.created'
        ].contains(event['type'])) refreshIdentity();
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
    if (api.authenticated && mounted && !locked)
      reconnect = Timer(const Duration(seconds: 5), () async {
        if (locked || !mounted || !api.authenticated) return;
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
    if (state == AppLifecycleState.resumed && _api?.authenticated == true) {
      if (pausedAt != null &&
          DateTime.now().difference(pausedAt!).inSeconds >= 60) {
        if (localProtected) {
          setState(() => locked = true);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted)
              Navigator.of(context).popUntil((route) => route.isFirst);
          });
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
    _api?.removeListener(sessionChanged);
    if (widget.api != _api) _api?.dispose();
    super.dispose();
  }

  void go(String next, [String? id]) {
    ScaffoldMessenger.maybeOf(context)?.removeCurrentSnackBar();
    if (next == 'languages') pendingLocale = null;
    setState(() {
      history.add((route, objectId));
      route = next;
      if (next == 'catalog') catalogPresentation = 'loading';
      if (next == 'offer') {
        offerAcknowledged = false;
        acknowledgedOrderRevision = null;
      }
      if (next == 'select-contractor') {
        selectionAcknowledged = false;
        acknowledgedSelection = null;
      }
      if (next == 'cancel') cancellationReason = 'plans';
      if (next == 'review') reviewRating = 0;
      if (next == 'services') serviceCategories = null;
      if (next == 'create') {
        draftPhotos.clear();
        verificationUploads.clear();
        draftWindow = null;
        draftCategory = null;
      }
      objectId = id;
      revision++;
    });
  }

  void back() {
    ScaffoldMessenger.maybeOf(context)?.removeCurrentSnackBar();
    setState(() {
      if (history.isNotEmpty) {
        final previous = history.removeLast();
        route = previous.$1;
        objectId = previous.$2;
      } else {
        route = _api?.authenticated == true ? 'home' : 'welcome';
        objectId = null;
      }
      revision++;
    });
  }

  void success(String text) {
    if (mounted)
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: UiText(text)));
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
                    title: const UiText('Не удалось выполнить действие'),
                    content: Text(errorText(context, e)),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(c),
                          child: const UiText('Понятно'))
                    ]));
    } finally {
      if (mounted) setState(() => actionBusy = false);
    }
  }

  String price(dynamic amount, [String currency = 'KZT']) => amount == null
      ? localize(context, 'По договорённости')
      : money(amount, currency, locale);

  Widget button(String label, VoidCallback onPressed, {bool outline = false}) =>
      Padding(
          padding: const EdgeInsets.only(top: 12),
          child: outline
              ? OutlinedButton(
                  onPressed: actionBusy ? null : onPressed,
                  child: UiText(label))
              : FilledButton(
                  onPressed: actionBusy ? null : onPressed,
                  child: UiText(label)));
  Widget page(String title, Widget body,
          {List<Widget> actions = const [],
          bool nav = false,
          bool chrome = true,
          double titleOffset = 0}) =>
      PopScope(
          canPop: history.isEmpty,
          onPopInvokedWithResult: (popped, result) {
            if (!popped) back();
          },
          child: Scaffold(
              backgroundColor: canvas,
              appBar: chrome
                  ? AppBar(
                      leadingWidth: 72,
                      title: Transform.translate(
                          offset: Offset(0, titleOffset), child: UiText(title)),
                      leading: IconButton(
                          onPressed: back,
                          tooltip: localize(context, 'Назад'),
                          icon: const JobaIcon('back')),
                      actions: actions)
                  : null,
              body: chrome
                  ? body
                  : Container(
                      color: Colors.white,
                      child: SafeArea(
                          bottom: false,
                          child: Container(color: canvas, child: body))),
              bottomNavigationBar: nav
                  ? JobaNavigation(
                      route: route,
                      executor: executor,
                      onSelect: (next) {
                        listingFilters = {};
                        go(next);
                      })
                  : null));
  Widget listBody(List<Widget> content) =>
      ListView(padding: const EdgeInsets.all(20), children: content);
  Widget loaded(String path, Widget Function(dynamic, VoidCallback) render,
          {Json query = const {}}) =>
      ApiView(
          key: ValueKey('$route:$objectId:$revision:$path'),
          load: () => api.request(path, query: query),
          builder: (c, data, reload) => render(data, reload));
  Widget orderCard(Json order) => Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: line),
          borderRadius: BorderRadius.circular(16)),
      child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => go(
              ['assigned', 'in_progress', 'completion_requested']
                      .contains(order['status'])
                  ? 'work'
                  : 'order',
              order['id']),
          child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      JobaBadge(status(order)),
                      const Spacer(),
                      Text(
                          '№ ${order['id'].toString().split('-').first.toUpperCase()}',
                          style: const TextStyle(fontSize: 10, color: muted))
                    ]),
                    const SizedBox(height: 11),
                    Text(order['title'] ?? '',
                        style: const TextStyle(
                            fontSize: 16,
                            height: 1.44,
                            letterSpacing: -.2,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Text(order['city'] ?? '',
                        style: const TextStyle(
                            fontSize: 12, color: muted, height: 1.5)),
                    const SizedBox(height: 16),
                    Row(children: [
                      Expanded(
                          child: Text(
                              price(order['budget_amount'],
                                  order['currency'] ?? 'KZT'),
                              style: const TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.w700))),
                      const UiText('Подробнее',
                          style: TextStyle(fontSize: 12, color: primary)),
                      const SizedBox(width: 4),
                      const JobaIcon('right', size: 14, color: primary)
                    ])
                  ]))));
  Widget ordersScreen() => page(
          'Мои заказы',
          Column(children: [
            if (executor || ordersHasAny != false)
              Container(
                  color: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(children: [
                    for (final entry in const {
                      'active': 'Активные',
                      'completed': 'Завершённые',
                      'drafts': 'Черновики'
                    }.entries)
                      if (!executor || entry.key != 'drafts')
                        Expanded(
                            child: InkWell(
                                onTap: () =>
                                    setState(() => ordersBucket = entry.key),
                                child: Container(
                                    constraints:
                                        const BoxConstraints(minHeight: 48),
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                        border: Border(
                                            bottom: BorderSide(
                                                width: 2,
                                                color: ordersBucket == entry.key
                                                    ? primary
                                                    : line))),
                                    child: UiText(entry.value,
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: ordersBucket == entry.key
                                                ? primary
                                                : muted,
                                            fontWeight: ordersBucket == entry.key ? FontWeight.w700 : FontWeight.w400)))))
                  ])),
            Expanded(
                child: PagedList(
                    key: ValueKey('orders:$executor:$ordersBucket:$revision'),
                    api: api,
                    path: executor ? '/me/assigned-orders' : '/me/orders',
                    query: {'bucket': ordersBucket},
                    tile: orderCard,
                    onMetadata: (meta) {
                      if (!executor &&
                          meta['has_any'] is bool &&
                          mounted &&
                          (ordersHasAny != meta['has_any'] ||
                              meta['has_any'] == false &&
                                  ordersBucket != 'active')) {
                        setState(() {
                          ordersHasAny = meta['has_any'];
                          if (ordersHasAny == false) ordersBucket = 'active';
                        });
                      }
                    },
                    emptyStateBuilder: !executor && ordersBucket == 'active'
                        ? (meta) => JobaStatePanel(
                            title: 'Начнём с одной\nзадачи',
                            message:
                                'Опишите, что нужно сделать. Подходящие специалисты предложат свои условия.',
                            icon: 'brief',
                            brand: true,
                            primaryLabel: meta['has_any'] == false
                                ? 'Создать первый заказ'
                                : 'Создать заказ',
                            onPrimary: () => go('create'))
                        : null,
                    empty: ordersBucket == 'drafts'
                        ? 'Черновиков пока нет'
                        : 'Заказов пока нет'))
          ]),
          nav: executor || ordersHasAny != false,
          actions: [
            if (!executor && ordersHasAny != false)
              IconButton(
                  tooltip: localize(context, 'Создать заказ'),
                  onPressed: () => go('create'),
                  icon: const JobaIcon('plus'))
          ]);
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
            Notice(errorText(context, startupError!), error: true),
            button('Повторить', () {
              setState(() {
                starting = true;
                startupError = null;
              });
              initialize();
            }),
            button(
                'Выбрать страну',
                () => setState(() {
                      startupError = null;
                      route = 'welcome';
                    }),
                outline: true)
          ]));
    return screen();
  }

  Widget screen() {
    switch (route) {
      case 'lock-setup':
        return lockSetup();
      case 'unlock':
        return unlockScreen();
      case 'banned':
        return page(
            'Ограничение аккаунта',
            AccountRestrictions(
                key: ValueKey('restrictions:$revision'),
                api: api,
                onSupport: () => go('support'),
                onPrivacy: () => go('privacy'),
                onOrders: () => go('orders'),
                onCase: (id) => go('case', id),
                onAppeal: (id) => act(() async {
                      final incident = await api.request('/cases/$id') as Json;
                      if (mounted)
                        caseForm(true, incident, () => go('case', id));
                    }),
                dateLabel: (value) {
                  final date = DateTime.tryParse('$value');
                  return date == null
                      ? ''
                      : '${DateFormat(date.toUtc().year == DateTime.now().toUtc().year ? 'd MMMM, HH:mm' : 'd MMMM y, HH:mm', locale).format(date.toUtc())} UTC';
                }),
            titleOffset: -12);
      case 'legal':
        return page(
            'Правовые документы',
            LegalDocuments(
                api: api,
                country: country,
                locale: locale,
                countryLabel: countryName(country),
                localeLabel: {
                      'ru': 'Русский',
                      'kk': 'Қазақша',
                      'sr': 'Srpski',
                      'be': 'Беларуская'
                    }[locale] ??
                    locale),
            titleOffset: -12);
      case 'support-new':
        return page(
            'Новое обращение',
            SupportNew(
                api: api,
                executor: executor,
                pickUpload: () => pickUpload('chat'),
                onCreated: (id) => go('support-chat', id)),
            titleOffset: -12);
      case 'logout-confirm':
        return logoutConfirmation();
      case 'session-expired':
        return page(
            'Сессия завершена',
            ListView(padding: const EdgeInsets.all(20), children: [
              JobaStatePanel(
                  title: 'Сессия больше\nне действует',
                  message:
                      'Войдите номером и паролем. PIN и биометрия не восстанавливают отозванную сессию.',
                  icon: 'lock',
                  primaryLabel: 'Войти снова',
                  onPrimary: () => go('login'))
            ]),
            titleOffset: -12);
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
      case 'executor-home':
        return homeScreen();
      case 'account':
        return accountScreen();
      case 'onboarding':
      case 'profile-edit':
        return profileForm();
      case 'orders':
        return ordersScreen();
      case 'jobs':
        return page(
            'Заказы рядом',
            SearchListings(
                key: ValueKey('jobs:$revision'),
                api: api,
                path: '/orders',
                initialFilters: listingFilters,
                tile: orderCard),
            nav: true);
      case 'create':
        return createScreen();
      case 'edit-order':
        return editOrderScreen();
      case 'change-requests':
        return changeRequestsScreen();
      case 'order':
      case 'work':
        return orderScreen();
      case 'published':
      case 'offer-sent':
      case 'review-sent':
        return page(
            route == 'published'
                ? 'Готово'
                : route == 'offer-sent'
                    ? 'Отклик отправлен'
                    : 'Отзыв сохранён',
            ActionReceipt(
                key: ValueKey('$route:$objectId:$revision'),
                api: api,
                id: objectId!,
                kind: route == 'published'
                    ? ReceiptKind.published
                    : route == 'offer-sent'
                        ? ReceiptKind.offer
                        : ReceiptKind.review,
                onOrders: () => go('orders'),
                onOffers: () => go('offers', objectId),
                onJobs: () => go('jobs'),
                onOrder: (id) => go('order', id)),
            titleOffset: route == 'published' ? 0 : -12);
      case 'publish':
        return publishScreen();
      case 'select-contractor':
        return selectionScreen();
      case 'complete':
        return completionScreen();
      case 'cancel':
        return cancellationScreen();
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
                    subtitle: price(r['amount'], r['currency']),
                    onTap: () => go('order', r['order_id']),
                    footer: Column(children: [
                      button(
                          'Открыть чат', () => go('chat', r['conversation_id']),
                          outline: true),
                      if (r['status'] == 'active') ...[
                        button('Редактировать отклик', () => editOffer(r),
                            outline: true),
                        button(
                            'Подтвердить актуальные условия',
                            () => act(() async {
                                  final order = await api.request(
                                      '/orders/${r['order_id']}') as Json;
                                  if (!mounted) return;
                                  final confirmed = await showDialog<bool>(
                                      context: context,
                                      builder: (c) => AlertDialog(
                                              title: const UiText(
                                                  'Условия заказа'),
                                              content: Text(
                                                  '${order['title']}\n${order['description']}'),
                                              actions: [
                                                TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(c, false),
                                                    child:
                                                        const UiText('Отмена')),
                                                TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(c, true),
                                                    child: const UiText(
                                                        'Подтвердить'))
                                              ]));
                                  if (confirmed != true) return;
                                  await api.request(
                                      '/offers/${r['id']}/acknowledge',
                                      method: 'POST',
                                      body: {
                                        'expected_version': r['version'],
                                        'order_revision': order['revision']
                                      });
                                  if (mounted) setState(() => revision++);
                                }),
                            outline: true),
                      ],
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
      case 'roles':
        return rolesScreen();
      case 'location':
        return locationScreen();
      case 'filters':
        return SearchFilters(
            api: api,
            initial: listingFilters,
            onClose: back,
            onApply: (filters) {
              listingFilters = filters;
              go('catalog');
            });
      case 'catalog':
        return page(
            catalogPresentation == 'offline'
                ? 'Нет подключения'
                : catalogPresentation == 'error'
                    ? 'Не удалось загрузить'
                    : 'Специалисты',
            SearchListings(
                key: ValueKey('catalog:$revision'),
                onStatus: (status) {
                  if (mounted &&
                      route == 'catalog' &&
                      catalogPresentation != status)
                    setState(() => catalogPresentation = status);
                },
                api: api,
                path: '/contractors',
                onCreate: () => go('create'),
                initialFilters: listingFilters,
                tile: contractorCard),
            nav: !['empty', 'error', 'offline'].contains(catalogPresentation));
      case 'contractor':
        return contractorScreen();
      case 'public-project':
        return publicProjectScreen();
      case 'public-portfolio':
        return page(
            'Портфолио исполнителя',
            paged(
                '/contractors/$objectId/portfolio',
                (project) => DataCard('${project['title']}',
                    onTap: () =>
                        go('public-project', '$objectId/${project['id']}'),
                    subtitle: '${project['description']}',
                    footer: Column(children: [
                      UiText(project['linked_completed_order'] == true
                          ? 'Связано с завершённым заказом в JOBA'
                          : 'Работа заявлена исполнителем'),
                      for (final photo in (project['photos'] as List? ?? []))
                        Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: PrivatePhoto(api: api, id: photo))
                    ]))));
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
                    translateTitle: true,
                    status: status(r),
                    onTap: () => go('chat', r['id']))),
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
        return casesScreen();
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
                          if (!mounted) return;
                          final type = '${r['type']}';
                          if (type == 'message.created') {
                            go('chat', r['target_id']);
                          } else if (type == 'support.message.created') {
                            go('support-chat', r['target_id']);
                          } else if (type.startsWith('order.') ||
                              type == 'offer.created') {
                            go('order', r['target_id']);
                          } else if (type == 'privacy.export.ready') {
                            go('privacy');
                          } else if (type == 'case.message.created' ||
                              type == 'case.updated') {
                            go('case', r['target_id']);
                          } else if (type == 'verification.updated') {
                            await refreshIdentity();
                            if (mounted) go('verification');
                          } else if (type == 'content.moderated') {
                            await refreshIdentity();
                            if (mounted) go('account');
                          } else if (type == 'invite.created') {
                            go('invitations');
                          } else if (type.startsWith('amendment.') ||
                              type.startsWith('cancel_request.')) {
                            go('change-requests');
                          } else {
                            setState(() => revision++);
                          }
                        }))),
            actions: [
              IconButton(
                  tooltip: localize(context, 'Прочитать все'),
                  icon: const Icon(Icons.done_all),
                  onPressed: () => act(() async {
                        final before = api.serverTime;
                        if (before == null) return;
                        await api.request('/me/notifications/read-all',
                            method: 'POST', body: {'before': before});
                        if (mounted) setState(() => revision++);
                      }))
            ],
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
                      const UiHeading('Больше возможностей',
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
      case 'languages':
        return languageScreen();
      case 'country':
        return countryScreen();
      case 'about':
        return aboutScreen();
      case 'sessions':
        return sessionsScreen();
      case 'notification-settings':
        return notificationSettings();
      case 'referral-rules':
        return referralRulesScreen();
      case 'referrals':
        return referralsScreen();
      case 'portfolio':
        return portfolioScreen();
      case 'portfolio-edit':
        return projectScreen();
      case 'portfolio-project':
        return objectId == null ? projectScreen() : ownProjectDetailScreen();
      case 'verification':
        return verificationScreen();
      case 'content-history':
        return page(
            'История опубликованных версий',
            paged(
                '/me/content-revisions',
                (record) => DataCard('${record['content']['title']}',
                    subtitle:
                        '${localize(context, 'Версия')} ${record['source_version']}',
                    footer: ExpansionTile(title: const UiText('Посмотреть версию'), children: [
                      Text('${record['content']['description'] ?? ''}'),
                      for (final id in (record['content']['photos'] ??
                          record['content']['gallery_ids'] ??
                          []) as List)
                        PrivatePhoto(api: api, id: id)
                    ])),
                query: {'source_id': objectId}));
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
                          tooltip: localize(context, 'Нравится'),
                          icon: const Icon(Icons.thumb_up_outlined),
                          onPressed: () => vote(r, 1)),
                      IconButton(
                          tooltip: localize(context, 'Не нравится'),
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
          onTap: actionBusy ? null : () => act(() => chooseCountry(code)),
          child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                if (code == 'KZ') ...[
                  const JobaIcon('globe'),
                  const SizedBox(width: 12)
                ],
                Expanded(
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      UiText(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 14,
                              height: 1.4,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      UiText(currency,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13,
                              height: 1.4,
                              color: Color(0xFF627187)))
                    ])),
                Icon(
                    country == code
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: country == code ? primary : line,
                    size: 24),
              ]))));
  Widget welcomeScreen() => Scaffold(
      backgroundColor: canvas,
      body: SafeArea(
          child: Column(children: [
        Expanded(
            child: listBody([
          const Text.rich(
              TextSpan(children: [
                TextSpan(text: 'JOBA'),
                TextSpan(text: '•', style: TextStyle(color: yellow))
              ]),
              style: TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1.8,
                  color: primary)),
          const SizedBox(height: 24),
          Center(
              child: ClipRRect(
                  borderRadius: BorderRadius.circular(31),
                  child: Image.asset('assets/joba-logo-original.jpeg',
                      width: 140, height: 140, fit: BoxFit.contain))),
          const SizedBox(height: 24),
          const UiHeading('Дела становятся проще',
              'Находите специалистов и заказы в вашем городе.'),
          const UiText('Страна услуг',
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
          const UiText('Язык интерфейса',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
              initialValue: locale,
              style: const TextStyle(
                  fontFamily: 'Noto',
                  fontSize: 14,
                  letterSpacing: 0,
                  color: navy),
              icon: const JobaIcon('down'),
              items: const [
                DropdownMenuItem(value: 'ru', child: UiText('Русский')),
                DropdownMenuItem(value: 'kk', child: UiText('Қазақша')),
                DropdownMenuItem(value: 'sr', child: Text('Srpski')),
                DropdownMenuItem(value: 'be', child: UiText('Беларуская'))
              ],
              onChanged:
                  actionBusy ? null : (v) => act(() => chooseGuestLocale(v!))),
          const SizedBox(height: 16),
          const UiText(
              'Страна и язык выбираются отдельно. Доступность функций зависит от региона.',
              style: TextStyle(fontSize: 11, color: Color(0xFF627187))),
        ])),
        Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: FilledButton(
                onPressed: actionBusy
                    ? null
                    : () => act(() async {
                          if (_api == null) await chooseCountry(country);
                          go('login');
                        }),
                child: const UiText('Продолжить'))),
      ])));
  Widget authScreen() {
    final register = route == 'register';
    return page(
        register ? 'Новый аккаунт' : 'Вход в JOBA',
        ActionForm(
            key: ValueKey(route),
            authLayout: true,
            before: [
              UiHeading(
                  register ? 'Добро пожаловать' : 'С возвращением',
                  register
                      ? 'Один аккаунт для ваших задач и работы.'
                      : 'Войдите в свой аккаунт, чтобы продолжить.')
            ],
            fields: [
              InputSpec('phone', 'Номер телефона',
                  hint: '${{
                    'KZ': '+7',
                    'RU': '+7',
                    'BY': '+375',
                    'RS': '+381'
                  }[country]} · ${localize(context, 'Номер телефона').toLowerCase()}',
                  originalIcon: 'phone',
                  keyboard: TextInputType.phone),
              InputSpec('password', register ? 'Придумайте пароль' : 'Пароль',
                  hint: register ? 'Не менее 15 символов' : 'Введите пароль',
                  secret: true,
                  validate: (v) => register && v.length < 15
                      ? 'Не менее 15 символов'
                      : null),
              if (register)
                const InputSpec('repeat', 'Повторите пароль',
                    hint: 'Введите пароль ещё раз', secret: true)
            ],
            afterField: register
                ? const {
                    'phone': [
                      Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: UiText(
                              'Номер будет вашим логином, он не подтверждён.',
                              style: TextStyle(
                                  fontSize: 10, color: muted, height: 1.4)))
                    ],
                    'password': [
                      Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: UiText(
                              'Можно использовать пробелы и длинную фразу.',
                              style: TextStyle(
                                  fontSize: 10, color: muted, height: 1.4)))
                    ]
                  }
                : const {},
            afterFields: register
                ? const [
                    Notice(
                        'Сохраните пароль в надёжном месте. Он нужен для входа на новом устройстве.',
                        icon: 'info',
                        margin: EdgeInsets.zero),
                    SizedBox(height: 20)
                  ]
                : const [],
            button: register ? 'Продолжить' : 'Войти',
            submit: (v) async {
              if (register && v['password'] != v['repeat'])
                throw ApiException('VALIDATION_ERROR', 'Пароли не совпадают');
              await api.signIn({
                'country': country,
                'phone': v['phone']!.trim(),
                'password': v['password'],
                if (register) 'locale': locale
              }, register: register);
              registrationInProgress = register;
              me = await api.request('/me') as Json;
              if (me!['locale'] != locale)
                me = await api.request('/me', method: 'PATCH', body: {
                  'expected_version': me!['version'],
                  'locale': locale
                }) as Json;
              serviceCategories = null;
              draftCategory = null;
              objectId = null;
              executor = me!['active_role'] == 'executor';
              widget.onLocaleChanged?.call(locale);
              sequence = 0;
              connectEvents();
              lock = LocalLock('${api.base}:${me!['id']}');
              if (mounted)
                setState(() {
                  route = 'lock-setup';
                  history.clear();
                });
            },
            after: register
                ? [
                    TextButton(
                        onPressed: () => go('login'),
                        child: const UiText('Уже есть аккаунт? Войти'))
                  ]
                : [
                    TextButton(
                        style: TextButton.styleFrom(
                            minimumSize: const Size(double.infinity, 52)),
                        onPressed: () => go('recovery'),
                        child: const UiText('Нужна помощь со входом?')),
                    const Divider(height: 29),
                    const UiText('Ещё нет аккаунта?',
                        textAlign: TextAlign.center,
                        style:
                            TextStyle(fontSize: 12, color: Color(0xFF627187))),
                    button('Зарегистрироваться', () => go('register'),
                        outline: true),
                    const Notice(
                        'Ваш номер используется как логин. Подтверждение кодом не требуется.',
                        icon: 'lock',
                        margin: const EdgeInsets.only(top: 24)),
                    Padding(
                        padding: const EdgeInsets.only(top: 24),
                        child: Text(
                            '${localize(context, {
                                  'KZ': 'Казахстан',
                                  'RU': 'Россия',
                                  'BY': 'Беларусь',
                                  'RS': 'Сербия'
                                }[country]!)} · ${{
                              'ru': 'Русский',
                              'kk': 'Қазақша',
                              'sr': 'Српски',
                              'be': 'Беларуская'
                            }[locale]}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 12, color: Color(0xFF627187))))
                  ]),
        titleOffset: -12);
  }

  void finishLocalSetup() {
    if (history.isNotEmpty && history.last.$1 == 'security')
      back();
    else
      go('terms');
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
            UiHeading('Быстрый вход', 'PIN хранится только на этом устройстве.')
          ],
          button: 'Сохранить PIN',
          submit: (v) async {
            if (v['pin'] != v['repeat'])
              throw ApiException('PIN_INVALID', 'PIN не совпадает');
            await lock!.configure(v['pin']!);
            await api.setPersistence(true);
            localProtected = true;
            finishLocalSetup();
          },
          after: [
            button(
                'Использовать биометрию',
                () => act(() async {
                      await lock!.enableBiometry();
                      await api.setPersistence(true);
                      localProtected = true;
                      finishLocalSetup();
                    }),
                outline: true),
            button(
                'Входить с паролем',
                () => act(() async {
                      await api.setPersistence(false);
                      localProtected = false;
                      finishLocalSetup();
                    }),
                outline: true)
          ]));
  Widget unlockScreen() => Scaffold(
      appBar: AppBar(title: const UiText('Разблокировка JOBA')),
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
              locale = me!['locale'] ?? 'ru';
              widget.onLocaleChanged?.call(locale);
              serviceCategories = null;
              draftCategory = null;
              objectId = null;
              executor = me!['active_role'] == 'executor';
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
                        if (!await lock!.unlockBiometry(
                            title: localize(context, 'Разблокировка JOBA'),
                            cancel: localize(context, 'Отмена'))) return;
                        await api.refresh();
                        me = await api.request('/me') as Json;
                        country = me!['country'];
                        locale = me!['locale'] ?? 'ru';
                        widget.onLocaleChanged?.call(locale);
                        serviceCategories = null;
                        draftCategory = null;
                        objectId = null;
                        executor = me!['active_role'] == 'executor';
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
  String countryName(String code) => localize(
      context,
      const {
            'KZ': 'Казахстан',
            'RS': 'Сербия',
            'RU': 'Россия',
            'BY': 'Беларусь'
          }[code] ??
          code);
  String dateLabel(dynamic value) {
    final date = DateTime.tryParse('$value');
    return date == null ? '' : DateFormat.yMMMMd(locale).format(date.toLocal());
  }

  Future<void> switchRole([String? requested]) async {
    final target = requested ?? (executor ? 'customer' : 'executor');
    if ((me?['active_role'] ?? 'customer') == target) return;
    if (!(me?['roles'] as List? ?? []).contains(target)) {
      go('services');
      return;
    }
    final fresh = await api.request('/me') as Json;
    final updated = await api.request('/me',
            method: 'PATCH',
            body: {'expected_version': fresh['version'], 'active_role': target})
        as Json;
    if (!mounted) return;
    setState(() {
      me = updated;
      executor = target == 'executor';
      if (executor && ordersBucket == 'drafts') ordersBucket = 'active';
      revision++;
    });
  }

  Widget rolesScreen() => page(
      'Моя роль',
      loaded(
          '/me/contractor-profile',
          (data, reload) => Column(children: [
                Expanded(
                    child: listBody([
                  const UiHeading('Сегодня вы…',
                      'Роли используют один аккаунт и общую подписку.'),
                  JobaMenu([
                    JobaMenuEntry(
                        'Заказчик',
                        'search',
                        () => act(() async {
                              await switchRole('customer');
                              go('home');
                            }),
                        subtitle: 'Найти мастера и опубликовать задачу'),
                    JobaMenuEntry(
                        'Исполнитель',
                        'brief',
                        () => act(() async {
                              await switchRole('executor');
                              if (executor) go('home');
                            }),
                        subtitle: 'Находить заказы и предлагать услуги')
                  ]),
                  const SizedBox(height: 20),
                  const UiText('Для исполнителя',
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                  const SizedBox(height: 12),
                  Row(children: [
                    JobaIcon(
                        data['profile'] != null &&
                                '${data['profile']['title'] ?? ''}'.isNotEmpty
                            ? 'check'
                            : 'clock',
                        color: primary),
                    const SizedBox(width: 8),
                    UiText(data['profile'] != null &&
                            '${data['profile']['title'] ?? ''}'.isNotEmpty
                        ? 'Профиль услуг заполнен'
                        : 'Заполните профиль услуг')
                  ]),
                  const SizedBox(height: 12),
                  Row(children: [
                    JobaIcon(
                        me?['verification'] == 'passed' ? 'check' : 'clock',
                        color: primary),
                    const SizedBox(width: 8),
                    UiText(me?['verification'] == 'passed'
                        ? 'Документ проверен'
                        : 'Требуется проверка документа')
                  ])
                ])),
                SafeArea(
                    top: false,
                    child: Container(
                        color: Colors.white,
                        padding: const EdgeInsets.all(20),
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          button(
                              'Остаться заказчиком',
                              () => act(() async {
                                    await switchRole('customer');
                                    go('home');
                                  }),
                              outline: true),
                          button(
                              'Перейти к заказам',
                              () => act(() async {
                                    await switchRole('executor');
                                    if (executor)
                                      go(me?['verification'] == 'passed'
                                          ? 'jobs'
                                          : 'verification');
                                  }))
                        ])))
              ])));

  Widget roleButton() => Semantics(
      button: true,
      child: Material(
          color: Colors.transparent,
          child: InkWell(
              onTap: actionBusy ? null : () => go('roles'),
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                  height: 44,
                  child: Align(
                      alignment: Alignment.topRight,
                      widthFactor: 1,
                      child: Container(
                          height: 36,
                          padding: const EdgeInsets.symmetric(horizontal: 9),
                          decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(color: line),
                              borderRadius: BorderRadius.circular(10)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            UiText(executor ? 'Исполнитель' : 'Заказчик',
                                style: const TextStyle(
                                    fontSize: 11, fontWeight: FontWeight.w400)),
                            const SizedBox(width: 4),
                            const JobaIcon('down', size: 14)
                          ])))))));
  Widget contractorCard(Json record) => Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: line),
          borderRadius: BorderRadius.circular(16)),
      child: InkWell(
          onTap: () => go('contractor', record['id']),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          JobaAvatar(
                              api: api,
                              name: record['display_name'] ??
                                  record['title'] ??
                                  '',
                              id: record['owner_avatar_id'] ??
                                  record['avatar_id'],
                              size: 52),
                          const SizedBox(width: 10),
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Row(children: [
                                  Expanded(
                                      child: Text(
                                          record['display_name'] ??
                                              record['title'] ??
                                              '',
                                          style: const TextStyle(
                                              fontSize: 16,
                                              height: 1.44,
                                              letterSpacing: -.2,
                                              fontWeight: FontWeight.w700))),
                                  const JobaIcon('shield',
                                      size: 18, color: primary)
                                ]),
                                if (record['display_name'] != null)
                                  Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(record['title'] ?? '',
                                          style: const TextStyle(
                                              fontSize: 12,
                                              height: 1.5,
                                              color: muted))),
                                if ((record['rating']?['count'] ?? 0) > 0)
                                  Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Row(children: [
                                        const JobaIcon('star',
                                            size: 14, color: Color(0xFFCC941A)),
                                        const SizedBox(width: 4),
                                        Text(
                                            '${NumberFormat('0.0', locale).format(record['rating']['average'])} (${record['rating']['count']})',
                                            style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700))
                                      ]))
                              ]))
                        ]),
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Text(record['description'] ?? '',
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12, height: 1.5, color: muted))),
                    Row(children: [
                      Expanded(
                          child: Text(
                              price(
                                  record['price']?['amount_min'],
                                  record['price']?['currency'] ??
                                      record['currency'] ??
                                      'KZT'),
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w700))),
                      const JobaIcon('pin', size: 14, color: muted),
                      const SizedBox(width: 4),
                      Flexible(
                          child: Text(record['city'] ?? '',
                              style:
                                  const TextStyle(fontSize: 11, color: muted)))
                    ])
                  ]))));
  Widget homeCategory(Json? category, int index) {
    final icons = ['tool', 'spark', 'truck', 'brush', 'book', 'grid'];
    final colors = [
      const Color(0xFFEFF4FD),
      const Color(0xFFEAF5F1),
      const Color(0xFFFFF5DA),
      const Color(0xFFF1EEFA),
      const Color(0xFFFFF5DA),
      const Color(0xFFEFF4FD)
    ];
    return Expanded(
        child: InkWell(
            onTap: () {
              listingFilters = {
                if (category != null) 'category_id': category['id'],
                if ((me?['city'] ?? '').isNotEmpty) 'city': me!['city']
              };
              go('catalog');
            },
            borderRadius: BorderRadius.circular(14),
            child: Padding(
                padding: EdgeInsets.zero,
                child: Column(children: [
                  Container(
                      width: 52,
                      height: 44,
                      decoration: BoxDecoration(
                          color: colors[index],
                          borderRadius: BorderRadius.circular(15)),
                      child: Center(
                          child:
                              JobaIcon(icons[index], size: 25, color: navy))),
                  const SizedBox(height: 8),
                  Text(category?['name'] ?? localize(context, 'Все услуги'),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, height: 1.36))
                ]))));
  }

  Widget locationScreen() => page(
      'Где искать?',
      loaded(
          '/geo/cities',
          (data, reload) => CitySelector(
              cities: items(data),
              countryLabel: countryName(country),
              initial: me?['city'] ?? '',
              onSave: (city) async {
                final user = await api.request('/me', method: 'PATCH', body: {
                  'city': city['name'],
                  'expected_version': me!['version']
                }) as Json;
                if (!mounted) return;
                setState(() => me = user);
                back();
              })));
  Widget homeScreen() => page(
      'JOBA',
      ListView(children: [
        if (me?['status'] != null && me?['status'] != 'active')
          Padding(
              padding: const EdgeInsets.all(20),
              child: OutlinedButton(
                  onPressed: () => go('banned'),
                  child: const UiText('Ограничение аккаунта'))),
        Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Column(children: [
              Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Text.rich(
                            TextSpan(children: [
                              TextSpan(text: 'JOBA'),
                              TextSpan(
                                  text: '•', style: TextStyle(color: yellow))
                            ]),
                            style: TextStyle(
                                fontSize: 25,
                                height: 1.28,
                                letterSpacing: -1.8,
                                fontWeight: FontWeight.w700,
                                color: primary))),
                    roleButton()
                  ]),
              const SizedBox(height: 6),
              InkWell(
                  onTap: () => go('location'),
                  child: Row(children: [
                    const JobaIcon('pin', size: 14, color: navy),
                    const SizedBox(width: 5),
                    Expanded(
                        child: Text(
                            '${me?['city'] ?? ''}${(me?['city'] ?? '').isEmpty ? '' : ', '}${countryName(country)}',
                            style:
                                const TextStyle(fontSize: 12, color: muted))),
                    const JobaIcon('down', size: 14)
                  ]))
            ])),
        if (!executor)
          Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const JobaHomeHeadline(),
                    Material(
                        color: canvas,
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                            onTap: () => go('catalog'),
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                                constraints:
                                    const BoxConstraints(minHeight: 52),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 12),
                                decoration: BoxDecoration(
                                    border: Border.all(color: line),
                                    borderRadius: BorderRadius.circular(14)),
                                child: const Row(children: [
                                  JobaIcon('search', color: muted),
                                  SizedBox(width: 10),
                                  Expanded(
                                      child: UiText('Какая услуга нужна?',
                                          style: TextStyle(
                                              fontSize: 14, color: muted)))
                                ])))),
                    const SizedBox(height: 20),
                    ApiView(
                        key: ValueKey('home-categories:$locale'),
                        load: () => api.request('/catalog/categories',
                            query: {'locale': locale}),
                        builder: (c, data, retry) {
                          final categories = items(data).take(5).toList();
                          return Column(children: [
                            for (var start = 0;
                                start < categories.length;
                                start += 3)
                              Padding(
                                  padding:
                                      EdgeInsets.only(top: start == 0 ? 0 : 19),
                                  child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        for (var i = start;
                                            i < start + 3;
                                            i++) ...[
                                          if (i > start)
                                            const SizedBox(width: 10),
                                          if (i < categories.length)
                                            homeCategory(categories[i], i)
                                          else if (i == categories.length)
                                            homeCategory(null, 5)
                                          else
                                            const Spacer()
                                        ]
                                      ])),
                            if (categories.length == 3 || categories.isEmpty)
                              Row(children: [
                                homeCategory(null, 5),
                                const SizedBox(width: 10),
                                const Spacer(),
                                const SizedBox(width: 10),
                                const Spacer()
                              ])
                          ]);
                        })
                  ])),
        if (executor)
          Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
              child: Column(children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Expanded(
                      child: UiHeading('Найдём ваш\nследующий заказ')),
                  JobaAvatar(
                      api: api,
                      name: me?['display_name'] ?? '',
                      id: me?['avatar_id'])
                ]),
                loaded('/me/contractor-profile', (data, retry) {
                  final profile = data['profile'];
                  return Row(children: [
                    const Expanded(
                        child: UiText('Принимаю новые заказы',
                            style: TextStyle(fontSize: 12, color: muted))),
                    Switch(
                        value: profile != null &&
                            profile['availability'] == 'available',
                        onChanged: actionBusy
                            ? null
                            : (value) => act(() async {
                                  if (profile == null) {
                                    go('services');
                                    return;
                                  }
                                  await api.request(
                                      '/me/contractor-profile/availability',
                                      method: 'PATCH',
                                      body: {
                                        'availability':
                                            value ? 'available' : 'paused',
                                        'expected_version': profile['version']
                                      });
                                  retry();
                                }))
                  ]);
                })
              ])),
        Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (!executor)
                Container(
                    margin: const EdgeInsets.only(top: 16),
                    clipBehavior: Clip.antiAlias,
                    width: double.infinity,
                    padding: const EdgeInsets.all(19),
                    decoration: BoxDecoration(
                        color: navy, borderRadius: BorderRadius.circular(18)),
                    child: Stack(clipBehavior: Clip.none, children: [
                      Positioned(
                          right: -25,
                          bottom: 5,
                          child: Transform.rotate(
                              angle: .32,
                              child: Container(
                                  width: 125,
                                  height: 125,
                                  decoration: BoxDecoration(
                                      border: Border.all(
                                          color: const Color(0xFF4D648B)),
                                      borderRadius:
                                          BorderRadius.circular(40))))),
                      Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const UiText('Расскажите о задаче',
                                style: TextStyle(
                                    fontSize: 20,
                                    letterSpacing: -.4,
                                    height: 1.35,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white)),
                            const SizedBox(height: 6),
                            const SizedBox(
                                width: 214,
                                child: UiText(
                                    'Специалисты сами предложат цену и удобное время',
                                    style: TextStyle(
                                        fontSize: 12,
                                        height: 1.5,
                                        color: Color(0xFFDAE3F5)))),
                            const SizedBox(height: 12),
                            FilledButton(
                                style: FilledButton.styleFrom(
                                    backgroundColor: yellow,
                                    foregroundColor: navy,
                                    minimumSize:
                                        const Size(double.infinity, 48),
                                    textStyle: const TextStyle(
                                        fontFamily: 'Noto',
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700)),
                                onPressed: () => go('create'),
                                child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      UiText('Создать заказ'),
                                      SizedBox(width: 8),
                                      JobaIcon('plus', size: 16)
                                    ]))
                          ])
                    ])),
              if (executor)
                loaded(
                    '/me/overview',
                    (data, retry) => Row(children: [
                          Expanded(
                              child: homeMetric(
                                  '${data['assigned_orders']?['active'] ?? 0}',
                                  'заказов в работе',
                                  () => go('orders'))),
                          const SizedBox(width: 12),
                          Expanded(
                              child: homeMetric(
                                  '${data['invitations']?['pending'] ?? 0}',
                                  'новых приглашений',
                                  () => go('invitations')))
                        ])),
              JobaSection(executor ? 'Подходящие заказы' : 'Рядом с вами',
                  () => go(executor ? 'jobs' : 'catalog'),
                  action: executor ? 'Фильтры' : 'Все'),
              homeListings(),
              if (executor)
                JobaMenu([
                  JobaMenuEntry('Мои отклики', 'chat', () => go('my-offers')),
                  JobaMenuEntry('Топ-100', 'crown', () => go('top'))
                ])
            ]))
      ]),
      nav: true,
      chrome: false);
  Widget homeMetric(String value, String label, VoidCallback onTap) => Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  border: Border.all(color: line),
                  borderRadius: BorderRadius.circular(14)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(value,
                        style: const TextStyle(
                            fontSize: 24, fontWeight: FontWeight.w700)),
                    UiText(label,
                        style: const TextStyle(fontSize: 11, color: muted))
                  ]))));
  Widget homeListings() => ApiView(
      key: ValueKey('home-listings:$executor:$revision'),
      load: () async {
        try {
          return await api.request(executor ? '/orders' : '/contractors',
              query: {
                'limit': 3,
                if ((me?['city'] ?? '').isNotEmpty) 'city': me!['city']
              });
        } on ApiException catch (error) {
          if (error.code == 'ENTITLEMENT_REQUIRED')
            return {'access_required': true};
          rethrow;
        }
      },
      builder: (c, data, retry) {
        if (data['access_required'] == true)
          return JobaMenu([
            JobaMenuEntry('Мой доступ', 'card', () => go('my-access'),
                subtitle: 'Выбор доступа')
          ]);
        if (items(data).isEmpty)
          return Notice(executor ? 'Заказов пока нет' : 'Пока здесь ничего нет',
              icon: 'search');
        return Column(
            children: items(data)
                .map(executor ? orderCard : contractorCard)
                .toList());
      });
  Widget accountScreen() => page(
      'Мой профиль',
      ApiView(
          key: ValueKey('account:$revision'),
          load: () =>
              Future.wait([api.request('/me'), api.request('/me/overview')]),
          builder: (c, result, reload) {
            final data = result[0] as Json, summary = result[1] as Json;
            me = data;
            final orders = summary['orders'] ?? {},
                rating = summary['rating'] ?? {};
            return ListView(children: [
              Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(20),
                  child: Column(children: [
                    Row(children: [
                      const Expanded(
                          child: UiText('Мой профиль',
                              style: TextStyle(
                                  fontSize: 26,
                                  height: 1.269,
                                  letterSpacing: -.9,
                                  fontWeight: FontWeight.w700))),
                      IconButton(
                          tooltip: localize(context, 'Настройки'),
                          onPressed: () => go('settings'),
                          icon: const JobaIcon('dots'))
                    ]),
                    const SizedBox(height: 20),
                    Row(children: [
                      JobaAvatar(
                          api: api,
                          name: data['display_name'] ?? '',
                          id: data['avatar_id'],
                          size: 68),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(data['display_name'] ?? '',
                                style: const TextStyle(
                                    fontSize: 20,
                                    height: 1.35,
                                    letterSpacing: -.4,
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            Text(
                                '${data['city'] ?? ''}${(data['city'] ?? '').isEmpty ? '' : ' · '}${countryName(country)}',
                                style: const TextStyle(
                                    fontSize: 12, color: muted)),
                            const SizedBox(height: 8),
                            roleButton()
                          ]))
                    ]),
                    const SizedBox(height: 16),
                    OutlinedButton(
                        onPressed: () => go('profile-edit'),
                        child: const UiText('Редактировать профиль'))
                  ])),
              Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(children: [
                    JobaMenu([
                      JobaMenuEntry(
                          summary['subscription_until'] == null
                              ? 'Мой доступ'
                              : 'Подписка активна',
                          'card',
                          () => go('my-access'),
                          subtitle: summary['subscription_until'] == null
                              ? 'Выбор доступа'
                              : dateLabel(summary['subscription_until']),
                          translateSubtitle:
                              summary['subscription_until'] == null)
                    ]),
                    const SizedBox(height: 16),
                    JobaMenu([
                      JobaMenuEntry('Мои заказы', 'brief', () => go('orders'),
                          subtitle:
                              '${orders['active'] ?? 0} · ${localize(context, 'Активные')} · ${orders['open'] ?? 0} · ${localize(context, 'Открыт')}',
                          translateSubtitle: false),
                      JobaMenuEntry('Мои услуги и портфолио', 'tool',
                          () => go('services'),
                          subtitle: summary['contractor'] == null
                              ? 'Настройте профиль исполнителя'
                              : states[summary['contractor']['status']]),
                      JobaMenuEntry(
                          'Отзывы обо мне', 'star', () => go('reviews'),
                          subtitle: (rating['count'] ?? 0) == 0
                              ? 'Отзывов пока нет'
                              : '${NumberFormat('0.0', locale).format(rating['average'])} · ${rating['count']}',
                          translateSubtitle: (rating['count'] ?? 0) == 0),
                      JobaMenuEntry('Топ-100', 'crown', () => go('top'),
                          subtitle: 'Популярные услуги и заказы'),
                      JobaMenuEntry(
                          'Продвижение', 'spark', () => go('promotion'),
                          subtitle: 'Ваши размещения'),
                      JobaMenuEntry(
                          'Приглашения и бонусы', 'gift', () => go('referrals'),
                          subtitle: 'Пригласить друга')
                    ]),
                    const SizedBox(height: 16),
                    JobaMenu([
                      JobaMenuEntry(
                          'Безопасность', 'lock', () => go('security'),
                          subtitle: 'PIN, пароль и устройства'),
                      JobaMenuEntry('Поддержка', 'help', () => go('support'),
                          subtitle: 'Поможем с вашим вопросом'),
                      JobaMenuEntry(
                          'Приватность', 'shield', () => go('privacy'),
                          subtitle: 'Ваши данные и согласия'),
                      JobaMenuEntry('Настройки', 'globe', () => go('settings'),
                          subtitle: 'Язык, страна, уведомления')
                    ]),
                    const SizedBox(height: 16),
                    JobaMenu([
                      JobaMenuEntry('Мои обращения', 'flag', () => go('cases'))
                    ])
                  ]))
            ]);
          }),
      nav: true,
      chrome: false);
  Widget profileForm() => page(
      route == 'onboarding' ? 'Расскажите о себе' : 'Редактировать профиль',
      loaded(
          '/me',
          (data, reload) => ProfileEditor(
              api: api,
              initial: data,
              onboarding: route == 'onboarding',
              pickAvatar: () => pickUpload('avatar'),
              onSaved: (saved) {
                me = saved;
                locale = saved['locale'] ?? locale;
                executor = saved['active_role'] == 'executor';
                widget.onLocaleChanged?.call(locale);
                success('Профиль сохранён');
                if (route == 'onboarding') {
                  registrationInProgress = false;
                  go('access');
                } else
                  back();
              })));
  Widget createScreen() => page(
      'Новый заказ',
      ApiView(
          key: ValueKey('create:$revision'),
          load: () => Future.wait(
              [api.request('/catalog/categories'), api.request('/geo/cities')]),
          builder: (c, data, reload) => ActionForm(
              stickySubmit: true,
              externalBusy: actionBusy,
              beforeField: {
                'budget': [draftDateField()]
              },
              afterFields: [
                const UiText('Фотографии задачи',
                    style:
                        TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                if (draftPhotos.isNotEmpty)
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final id in draftPhotos)
                      SizedBox(
                          width: 100,
                          child: Column(children: [
                            PrivatePhoto(api: api, id: id),
                            IconButton(
                                tooltip: localize(context, 'Удалить фото'),
                                onPressed: actionBusy
                                    ? null
                                    : () =>
                                        setState(() => draftPhotos.remove(id)),
                                icon: const JobaIcon('close', size: 18))
                          ]))
                  ]),
                OutlinedButton(
                    onPressed: actionBusy || draftPhotos.length >= 10
                        ? null
                        : () => act(() async {
                              final run = revision;
                              final file = await pickUpload('order');
                              if (file != null &&
                                  mounted &&
                                  route == 'create' &&
                                  run == revision)
                                setState(() => draftPhotos.add(file['id']));
                            }),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      JobaIcon('camera'),
                      SizedBox(width: 10),
                      UiText('Добавить фото')
                    ])),
                const Notice('Точный адрес не будет виден в открытом каталоге.',
                    icon: 'shield')
              ],
              before: const [
                Row(children: [
                  UiText('Шаг 1 из 2',
                      style: TextStyle(fontSize: 12, color: muted)),
                  Spacer(),
                  JobaBadge('Черновик')
                ]),
                SizedBox(height: 22),
                UiHeading('Что нужно сделать?')
              ],
              fields: [
                InputSpec('category_id', 'Категория',
                    translateOptions: false,
                    initial: draftCategory ?? '',
                    options: {
                      for (final r in items(data[0])) r['id']: r['name']
                    },
                    changed: (v) => setState(() => draftCategory = v)),
                ...attributeFields(items(data[0])),
                const InputSpec('title', 'Название', validate: titleCheck),
                const InputSpec('description', 'Опишите задачу',
                    multiline: true, validate: descriptionCheck),
                InputSpec('city_id', 'Город',
                    translateOptions: false,
                    options: {
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
                  'upload_ids': List<String>.from(draftPhotos),
                  if (draftWindow != null) 'time_window': draftWindow
                }) as Json;
                go('publish', order['id']);
              })));
  Widget draftDateField() => Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const UiText('Срок',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        OutlinedButton(
            style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                alignment: Alignment.centerLeft),
            onPressed: actionBusy
                ? null
                : () async {
                    final today = DateUtils.dateOnly(DateTime.now());
                    final initial = draftWindow == null
                        ? null
                        : DateTimeRange(
                            start: DateTime.parse(draftWindow!['start_date']),
                            end: DateTime.parse(draftWindow!['end_date']));
                    final range = await showDateRangePicker(
                        context: context,
                        firstDate: today,
                        lastDate: today.add(const Duration(days: 365)),
                        initialDateRange: initial);
                    if (range == null || !mounted) return;
                    setState(() => draftWindow = {
                          'start_date':
                              DateFormat('yyyy-MM-dd').format(range.start),
                          'end_date':
                              DateFormat('yyyy-MM-dd').format(range.end),
                          'time_zone': const {
                            'KZ': 'Asia/Almaty',
                            'RS': 'Europe/Belgrade',
                            'RU': 'Europe/Moscow',
                            'BY': 'Europe/Minsk'
                          }[country]
                        });
                  },
            child: Row(children: [
              const JobaIcon('clock', size: 18),
              const SizedBox(width: 10),
              Expanded(
                  child: draftWindow == null
                      ? const UiText('Выберите даты')
                      : Text(
                          '${dateLabel(draftWindow!['start_date'])} — ${dateLabel(draftWindow!['end_date'])}',
                          style: const TextStyle(fontSize: 14)))
            ])),
        if (draftWindow != null)
          TextButton(
              onPressed: () => setState(() => draftWindow = null),
              child: const UiText('Очистить срок'))
      ]));
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
  String windowLabel(Json order) {
    final window = order['time_window'];
    if (window == null) return localize(context, 'По договорённости');
    return '${dateLabel(window['start_date'] ?? window['start'])} — ${dateLabel(window['end_date'] ?? window['end'])}';
  }

  Widget fact(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
            child: UiText(label,
                style: const TextStyle(fontSize: 12, color: muted))),
        Expanded(
            child: Text(value,
                textAlign: TextAlign.right,
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)))
      ]));
  Widget stickyActions(List<Widget> actions) => SafeArea(
      top: false,
      child: Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Row(children: [
            for (var index = 0; index < actions.length; index++) ...[
              if (index > 0) const SizedBox(width: 10),
              Expanded(child: actions[index])
            ]
          ])));
  Widget publishScreen() => page(
      'Проверьте заказ',
      loaded('/orders/$objectId', (data, reload) {
        final order = data as Json;
        return Column(children: [
          Expanded(
              child: listBody([
            const Row(children: [
              UiText('Шаг 2 из 2',
                  style: TextStyle(fontSize: 12, color: muted)),
              Spacer(),
              JobaBadge('Предпросмотр')
            ]),
            const SizedBox(height: 22),
            Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: line),
                    borderRadius: BorderRadius.circular(16)),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Heading(order['title']),
                      Text(order['description'],
                          style: const TextStyle(
                              fontSize: 12, color: muted, height: 1.55)),
                      const SizedBox(height: 14),
                      fact('Бюджет',
                          price(order['budget_amount'], order['currency'])),
                      const Divider(height: 1),
                      fact('Город', order['city']),
                      const Divider(height: 1),
                      fact('Когда', windowLabel(order))
                    ])),
            for (final id in order['upload_ids'] as List? ?? [])
              Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: PrivatePhoto(api: api, id: id)),
            const Notice('После проверки заказ появится в поиске.',
                icon: 'shield'),
            const UiText(
                'Цена услуги согласуется с исполнителем. JOBA не принимает оплату за работу.',
                style: TextStyle(fontSize: 12, color: muted, height: 1.5)),
            button('Изменить заказ', () => go('edit-order', order['id']),
                outline: true)
          ])),
          stickyActions([
            FilledButton(
                onPressed: actionBusy
                    ? null
                    : () => act(() async {
                          if (order['status'] != 'draft') {
                            go('order', order['id']);
                            return;
                          }
                          await api.request('/orders/${order['id']}/publish',
                              method: 'POST',
                              body: {'expected_version': order['version']});
                          go('published', order['id']);
                        }),
                child: UiText(order['status'] == 'draft'
                    ? 'Опубликовать заказ'
                    : 'Открыть заказ'))
          ])
        ]);
      }));
  Widget selectionScreen() => page(
      'Подтвердить исполнителя',
      loaded('/offers/$objectId', (data, reload) {
        final offer = data as Json, order = offer['order'] as Json;
        return ActionForm(
            stickySubmit: true,
            submitEnabled: order['owner'] == me?['id'] &&
                selectionAcknowledged &&
                acknowledgedSelection ==
                    '${order['version']}:${offer['version']}' &&
                order['status'] == 'open' &&
                offer['status'] == 'active',
            fields: const [],
            before: [
              const UiHeading('Договоримся о главном',
                  'После выбора остальные отклики закроются.'),
              Row(children: [
                JobaAvatar(
                    api: api,
                    name: offer['executor']?['display_name'] ?? '',
                    id: offer['executor']?['avatar_id']),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(offer['executor']?['display_name'] ?? '',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)))
              ]),
              const SizedBox(height: 16),
              Text(order['title'],
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700)),
              fact('Стоимость работы',
                  price(offer['amount'], offer['currency'])),
              const Divider(height: 1),
              fact('Когда', windowLabel(order)),
              Text(
                  '${localize(context, 'Версия')} ${order['revision']} · ${offer['version']}',
                  style: const TextStyle(fontSize: 10, color: muted)),
              const Notice(
                  'Оплату услуги вы согласуете напрямую с исполнителем. JOBA не хранит и не переводит эти деньги.',
                  icon: 'info'),
              CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: selectionAcknowledged &&
                      acknowledgedSelection ==
                          '${order['version']}:${offer['version']}',
                  onChanged: (value) => setState(() {
                        selectionAcknowledged = value == true;
                        acknowledgedSelection =
                            '${order['version']}:${offer['version']}';
                      }),
                  title: const UiText(
                      'Условия понятны. Подтверждаю выбор исполнителя.',
                      style: TextStyle(fontSize: 12, height: 1.58)))
            ],
            button: 'Выбрать исполнителя',
            submit: (fields) async {
              await api.request('/orders/${order['id']}/select-offer',
                  method: 'POST',
                  body: {
                    'expected_version': order['version'],
                    'offer_id': offer['id'],
                    'offer_version': offer['version']
                  });
              go('work', order['id']);
            });
      }));
  Widget completionScreen() => page(
      'Результат работы',
      loaded('/orders/$objectId', (data, reload) {
        final order = data as Json;
        final allowed = order['status'] == 'completion_requested' &&
            order['owner'] == me?['id'];
        return Column(children: [
          Expanded(
              child: listBody([
            JobaBadge(status(order)),
            const SizedBox(height: 16),
            Heading(order['title']),
            if (order['executor'] != null)
              Row(children: [
                JobaAvatar(
                    api: api,
                    name: order['executor']['display_name'] ?? '',
                    id: order['executor']['avatar_id']),
                const SizedBox(width: 10),
                Expanded(child: Text(order['executor']['display_name'] ?? ''))
              ]),
            const Notice(
                'Проверьте работу перед подтверждением. Если что-то осталось, запросите доработку.',
                icon: 'shield'),
            if (!allowed) const Notice('Состояние заказа изменилось.'),
            button(
                'Открыть чат',
                () => go(order['conversation_id'] == null ? 'messages' : 'chat',
                    order['conversation_id']),
                outline: true)
          ])),
          stickyActions([
            OutlinedButton(
                onPressed: allowed && !actionBusy
                    ? () => reasonCommand(order, 'request-revision',
                        () => go('work', order['id']))
                    : null,
                child: const UiText('Нужна доработка')),
            FilledButton(
                onPressed: allowed && !actionBusy
                    ? () => act(() async {
                          await api.request(
                              '/orders/${order['id']}/confirm-completion',
                              method: 'POST',
                              body: {'expected_version': order['version']});
                          go('review', order['id']);
                        })
                    : null,
                child: const UiText('Принять работу'))
          ])
        ]);
      }));
  Widget cancellationScreen() => page(
      'Отмена заказа',
      loaded('/orders/$objectId', (data, reload) {
        final order = data as Json;
        const reasons = {
          'plans': 'Изменились планы',
          'agreement': 'Не удалось договориться',
          'problem': 'Проблема с исполнителем',
          'other': 'Другая причина'
        };
        return ActionForm(
            stickySubmit: true,
            submitEnabled:
                [order['owner'], order['executor_id']].contains(me?['id']) &&
                    [
                      'draft',
                      'open',
                      'assigned',
                      'in_progress',
                      'completion_requested'
                    ].contains(order['status']),
            before: [
              const UiHeading('Почему отменяете?'),
              Text(order['title'],
                  style: const TextStyle(fontSize: 12, color: muted)),
              const SizedBox(height: 16),
              RadioGroup<String>(
                  groupValue: cancellationReason,
                  onChanged: (value) =>
                      setState(() => cancellationReason = value!),
                  child: Column(children: [
                    for (final entry in reasons.entries)
                      RadioListTile<String>(
                          contentPadding: EdgeInsets.zero,
                          title: UiText(entry.value,
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w700)),
                          value: entry.key)
                  ]))
            ],
            fields: [
              InputSpec('comment', 'Комментарий',
                  multiline: true,
                  required: false,
                  validate: (value) =>
                      cancellationReason == 'other' && value.trim().length < 5
                          ? 'Укажите причину подробнее'
                          : null)
            ],
            afterFields: const [
              Notice(
                  'Исполнитель получит запрос. При несогласии откроется дело поддержки. Отмена не означает возврат оплаты за услугу.',
                  icon: 'info')
            ],
            button: ['draft', 'open'].contains(order['status'])
                ? 'Отменить заказ'
                : 'Отправить запрос',
            submit: (fields) async {
              final command = ['draft', 'open'].contains(order['status'])
                  ? 'cancel'
                  : 'cancel-requests';
              await api.request('/orders/${order['id']}/$command',
                  method: 'POST',
                  body: {
                    'expected_version': order['version'],
                    'reason':
                        '${localize(context, reasons[cancellationReason]!)}. ${fields['comment'] ?? ''}'
                  });
              go(command == 'cancel' ? 'order' : 'change-requests',
                  order['id']);
            });
      }));
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
                  '${o['city']} · ${price(o['budget_amount'], o['currency'])}'),
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
            button('Проверить результат', () => go('complete', o['id'])),
            button('Запросить доработку',
                () => reasonCommand(o, 'request-revision', reload),
                outline: true)
          ],
          if ((owner || assigned) &&
              ['assigned', 'in_progress', 'completion_requested']
                  .contains(o['status']))
            button('Запросить отмену', () => go('cancel', o['id']),
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
            button('Отменить заказ', () => go('cancel', o['id']),
                outline: true),
          if ((owner || assigned) && o['status'] == 'completed')
            button('Оставить отзыв', () => go('review', o['id'])),
          if (owner || assigned)
            button(
                'Сообщения',
                () => go(o['conversation_id'] == null ? 'messages' : 'chat',
                    o['conversation_id']),
                outline: true),
          button('Пожаловаться', () => reportObject(o['id'], 'order'),
              outline: true),
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
              appBar: AppBar(title: const UiText('Новые условия')),
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
        if (command == 'publish') {
          go('published', o['id']);
          return;
        }
        success('Изменения сохранены');
        reload();
      });
  void reasonCommand(Json o, String command, VoidCallback reload) {
    Navigator.push(
        context,
        MaterialPageRoute<void>(
            builder: (c) => Scaffold(
                appBar: AppBar(title: const UiText('Укажите причину')),
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

  void editOffer(Json offer) => Navigator.push(
      context,
      MaterialPageRoute<void>(
          builder: (c) => Scaffold(
              appBar: AppBar(title: const UiText('Редактировать отклик')),
              body: ActionForm(
                  fields: [
                    InputSpec('amount', 'Ваша цена',
                        initial:
                            ((offer['amount'] as num) / 100).toStringAsFixed(2),
                        keyboard: TextInputType.number),
                    InputSpec('text', 'Комментарий',
                        initial: '${offer['text']}', multiline: true)
                  ],
                  button: 'Сохранить',
                  submit: (v) async {
                    await api.request('/offers/${offer['id']}',
                        method: 'PATCH',
                        body: {
                          'expected_version': offer['version'],
                          'amount': minor(v['amount']!),
                          'text': v['text']
                        });
                    if (c.mounted) Navigator.pop(c);
                    if (mounted) setState(() => revision++);
                  }))));

  Widget offerScreen() => page(
      'Отклик на заказ',
      loaded(
          '/orders/$objectId',
          (o, reload) => ActionForm(
              stickySubmit: true,
              submitEnabled: offerAcknowledged &&
                  acknowledgedOrderRevision == o['revision'],
              afterFields: [
                CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: offerAcknowledged &&
                        acknowledgedOrderRevision == o['revision'],
                    onChanged: (value) => setState(() {
                          offerAcknowledged = value == true;
                          acknowledgedOrderRevision = o['revision'];
                        }),
                    title: const UiText(
                        'Подтверждаю текущую версию условий заказа.',
                        style: TextStyle(fontSize: 12, height: 1.58)))
              ],
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
                final offer = await api
                    .request('/orders/$objectId/offers', method: 'POST', body: {
                  'amount': minor(v['amount']!),
                  'text': v['text'],
                  'acknowledged_revision': o['revision']
                }) as Json;
                go('offer-sent', offer['id']);
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
                          subtitle: price(offer['amount'], offer['currency']),
                          status: status(offer),
                          footer: Column(children: [
                            button('Открыть чат',
                                () => go('chat', offer['conversation_id']),
                                outline: true),
                            if (offer['status'] == 'active' &&
                                order['status'] == 'open')
                              button('Выбрать исполнителя',
                                  () => go('select-contractor', offer['id']))
                          ])),
                  ]))));
  Widget contractorScreen() => page(
      'Профиль мастера',
      loaded(
          '/contractors/$objectId',
          (record, reload) => ContractorProfile(
              api: api,
              profile: record,
              locale: locale,
              onOverview: reload,
              onProject: (project) =>
                  go('public-project', '${record['id']}/${project['id']}'),
              onInvite: () => go('invite', record['id']),
              onPortfolio: () => go('public-portfolio', record['id']),
              onReviews: () => go('reviews', record['owner']),
              onReport: () => reportObject(record['id'], 'contractor'),
              onBlock: () => act(() async {
                    await api.request('/me/blocks',
                        method: 'POST',
                        body: {'target_user_id': record['owner']});
                    success('Контакт заблокирован');
                  }))));
  Widget publicProjectScreen() {
    final ids = (objectId ?? '').split('/');
    if (ids.length != 2)
      return page('Проект портфолио', const Notice('Проект недоступен'));
    return page(
        'Проект портфолио',
        loaded(
            '/contractors/${ids[0]}/portfolio/${ids[1]}',
            (project, reload) => PortfolioDetail(
                api: api,
                project: project,
                author: project['contractor_name'] ?? '',
                avatarId: project['contractor_avatar_id'],
                onAuthor: () => go('contractor', project['contractor_id']))),
        actions: [
          IconButton(
              tooltip: localize(context, 'Пожаловаться'),
              onPressed: () => reportObject(ids[1], 'portfolio'),
              icon: const JobaIcon('shield'))
        ]);
  }

  Widget servicesScreen() => page(
      'Мои услуги',
      loaded('/me/contractor-profile', (result, reload) {
        final p = result['profile'] as Json?;
        serviceCategories ??=
            Set<String>.from(p?['category_ids'] as List? ?? []);
        return ApiView(
            load: () => api.request('/catalog/categories'),
            builder: (c, data, refresh) => ActionForm(
                before: [
                  if (p != null) Notice(status(p)),
                  if (p?['public_status'] == 'paused')
                    const Notice('Приём новых предложений приостановлен'),
                  if (p != null &&
                      ['published', 'paused'].contains(p['public_status']))
                    button(
                        p['public_status'] == 'paused'
                            ? 'Возобновить приём предложений'
                            : 'Приостановить приём предложений',
                        () => act(() async {
                              await api.request(
                                  '/me/contractor-profile/availability',
                                  method: 'PATCH',
                                  body: {
                                    'expected_version': p['version'],
                                    'availability':
                                        p['public_status'] == 'paused'
                                            ? 'available'
                                            : 'paused'
                                  });
                              reload();
                            }),
                        outline: true),
                  if (p?['public_status'] == 'published' &&
                      p?['status'] != 'published')
                    const Notice(
                        'Изменения сохраняются в черновике. Публичная версия обновится после одобрения.'),
                  if (p?['reason'] != null) Text('${p!['reason']}'),
                  if (p != null)
                    button('История опубликованных версий',
                        () => go('content-history', p['id']),
                        outline: true),
                  const UiHeading('Категории услуг',
                      'Выберите дополнительные направления.'),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final category in items(data))
                      FilterChip(
                          label: Text(category['name']),
                          selected: serviceCategories!.contains(category['id']),
                          onSelected: (selected) => setState(() {
                                if (selected) {
                                  serviceCategories!.add(category['id']);
                                } else {
                                  serviceCategories!.remove(category['id']);
                                }
                              }))
                  ])
                ],
                fields: [
                  InputSpec('title', 'Название услуги',
                      initial: p?['title'] ?? '', validate: titleCheck),
                  InputSpec('description', 'О себе и опыте',
                      initial: p?['description'] ?? '',
                      multiline: true,
                      validate: descriptionCheck),
                  InputSpec('category_id', 'Категория',
                      translateOptions: false,
                      initial: p?['category_id'] ?? '',
                      options: {
                        for (final r in items(data)) r['id']: r['name']
                      }),
                  InputSpec('city', 'Город',
                      initial: p?['city'] ?? me!['city']),
                  InputSpec('work_mode', 'Формат работы',
                      initial: (p?['work_modes'] as List?)?.first ?? 'onsite',
                      options: const {
                        'onsite': 'На месте',
                        'workshop': 'У исполнителя',
                        'remote': 'Удалённо',
                        'hybrid': 'На месте и удалённо'
                      }),
                  InputSpec(
                      'service_cities', 'Города обслуживания (через запятую)',
                      initial: (p?['service_cities'] as List?)?.join(', ') ??
                          me!['city']),
                  InputSpec('travel_radius_km', 'Радиус выезда, км',
                      initial: '${p?['travel_radius_km'] ?? 0}',
                      keyboard: TextInputType.number),
                  InputSpec('experience_years',
                      'Опыт работы, лет (со слов исполнителя)',
                      initial: '${p?['experience_years'] ?? ''}',
                      required: false,
                      keyboard: TextInputType.number),
                  InputSpec('languages', 'Языки общения (ru, kk, sr, be, en)',
                      initial: (p?['languages'] as List?)?.join(', ') ?? 'ru'),
                  InputSpec('availability', 'Доступность',
                      initial: p?['availability'] ?? 'available',
                      options: const {
                        'available': 'Принимаю предложения',
                        'busy': 'Занят',
                        'paused': 'Приостановлено'
                      }),
                  InputSpec('price_mode', 'Тип цены',
                      initial: p?['price']?['mode'] ?? 'negotiable',
                      options: const {
                        'negotiable': 'По договорённости',
                        'fixed': 'За работу',
                        'hourly': 'За час',
                        'per_unit': 'За единицу'
                      }),
                  InputSpec('price_min', 'Ориентировочная цена от',
                      initial: p?['price']?['amount_min'] == null
                          ? ''
                          : ((p!['price']['amount_min'] as num) / 100)
                              .toStringAsFixed(2),
                      required: false,
                      keyboard: TextInputType.number),
                  InputSpec('price_max', 'Ориентировочная цена до',
                      initial: p?['price']?['amount_max'] == null
                          ? ''
                          : ((p!['price']['amount_max'] as num) / 100)
                              .toStringAsFixed(2),
                      required: false,
                      keyboard: TextInputType.number),
                  InputSpec('price_unit', 'Единица',
                      initial: p?['price']?['unit'] ?? 'job',
                      options: const {
                        'job': 'Работа',
                        'hour': 'Час',
                        'day': 'День',
                        'piece': 'Штука',
                        'm2': 'м²',
                        'm3': 'м³',
                        'meter': 'Метр',
                        'visit': 'Выезд'
                      })
                ],
                submit: (v) async {
                  await api
                      .request('/me/contractor-profile', method: 'PUT', body: {
                    'title': v['title'],
                    'description': v['description'],
                    'category_id': v['category_id'],
                    'category_ids': [
                      v['category_id'],
                      ...serviceCategories!
                          .where((id) => id != v['category_id'])
                    ],
                    'city': v['city'],
                    'work_modes': v['work_mode'] == 'hybrid'
                        ? ['hybrid', 'onsite', 'remote']
                        : [v['work_mode']],
                    'service_cities': v['service_cities']!
                        .split(',')
                        .map((e) => e.trim())
                        .where((e) => e.isNotEmpty)
                        .toList(),
                    'languages': v['languages']!
                        .split(',')
                        .map((e) => e.trim())
                        .where((e) => e.isNotEmpty)
                        .toList(),
                    'travel_radius_km': double.tryParse(
                        v['travel_radius_km']!.replaceAll(',', '.')),
                    'experience_years': v['experience_years']!.isEmpty
                        ? null
                        : int.tryParse(v['experience_years']!),
                    'availability': v['availability'],
                    'price': {
                      'mode': v['price_mode'],
                      'currency': const {
                        'KZ': 'KZT',
                        'RS': 'RSD',
                        'RU': 'RUB',
                        'BY': 'BYN'
                      }[me!['country']],
                      if (v['price_mode'] != 'negotiable')
                        'amount_min': minor(v['price_min']!),
                      if (v['price_mode'] != 'negotiable' &&
                          v['price_max']!.isNotEmpty)
                        'amount_max': minor(v['price_max']!),
                      'unit': v['price_unit']
                    },
                    if (p != null) 'expected_version': p['version']
                  });
                  me = await api.request('/me') as Json;
                  success('Черновик сохранён');
                  serviceCategories = null;
                  reload();
                },
                after: [
                  if (p != null) ...[
                    const UiHeading('Галерея профиля'),
                    for (final photo in (p['gallery_ids'] as List? ?? [])) ...[
                      PrivatePhoto(api: api, id: photo),
                      button(
                          'Удалить фотографию',
                          () => updateGallery(
                              p,
                              (p['gallery_ids'] as List)
                                  .where((id) => id != photo)
                                  .cast<String>()
                                  .toList(),
                              reload),
                          outline: true)
                    ],
                    if ((p['gallery_ids'] as List? ?? []).length < 20)
                      button(
                          'Добавить фотографию',
                          () => act(() async {
                                final photo = await pickUpload('portfolio');
                                if (photo == null) return;
                                await api.request('/me/contractor-profile',
                                    method: 'PUT',
                                    body: {
                                      ...p,
                                      'expected_version': p['version'],
                                      'gallery_ids': [
                                        ...(p['gallery_ids'] as List? ?? []),
                                        photo['id']
                                      ]
                                    });
                                reload();
                              }),
                          outline: true),
                  ],
                  if (p != null && ['draft', 'rejected'].contains(p['status']))
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
  void updateGallery(Json profile, List<String> photos, VoidCallback reload) =>
      act(() async {
        await api.request('/me/contractor-profile', method: 'PUT', body: {
          ...profile,
          'expected_version': profile['version'],
          'gallery_ids': photos
        });
        reload();
      });
  Widget inviteScreen() => page(
      'Предложить заказ',
      InviteEditor(
          key: ValueKey('invite:$objectId'),
          api: api,
          contractorId: objectId!,
          locale: locale,
          period: windowLabel,
          onCreateOrder: () => go('create'),
          onSent: () {
            success('Приглашение отправлено');
            back();
          }));

  Widget invitationsScreen() => page(
      'Приглашения',
      PagedList(
          key: ValueKey('invitations:$revision'),
          api: api,
          path: '/me/order-invites',
          header: const Padding(
              padding: EdgeInsets.only(bottom: 22),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    UiText('Вас приглашают',
                        style: TextStyle(
                            fontSize: 26,
                            height: 1.35,
                            letterSpacing: -.9,
                            fontWeight: FontWeight.w700)),
                    SizedBox(height: 12),
                    UiText('Заказчики предлагают вам работу.',
                        style:
                            TextStyle(color: muted, fontSize: 12, height: 1.55))
                  ])),
          tile: (i) {
            final order = i['order'] as Json?;
            final customer = i['customer'] as Json?;
            final pending = i['status'] == 'pending' && order != null;
            return Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: line),
                    borderRadius: BorderRadius.circular(16)),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        if (customer != null) ...[
                          JobaAvatar(
                              api: api,
                              name: customer['display_name'] ?? '',
                              id: customer['avatar_id'],
                              size: 42),
                          const SizedBox(width: 10),
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text(customer['display_name'] ?? '',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13)),
                                const SizedBox(height: 4),
                                Text(dateLabel(i['created_at']),
                                    style: const TextStyle(
                                        color: muted, fontSize: 10))
                              ])),
                        ] else
                          const Spacer(),
                        JobaBadge(pending ? 'Новое' : status(i))
                      ]),
                      const SizedBox(height: 18),
                      Text(
                          order?['title'] ??
                              localize(context, 'Приглашение в заказ'),
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 18,
                              height: 1.4)),
                      if (order != null) ...[
                        const SizedBox(height: 10),
                        Text(
                            [order['city'], windowLabel(order)]
                                .where((v) =>
                                    v != null &&
                                    v.toString().isNotEmpty &&
                                    v != '—')
                                .join(' · '),
                            style: const TextStyle(
                                color: muted, fontSize: 12, height: 1.55)),
                        if (order['budget_amount'] != null) ...[
                          const SizedBox(height: 14),
                          Text(price(order['budget_amount'], order['currency']),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 16))
                        ],
                        if ((i['message'] ?? '').toString().isNotEmpty)
                          Padding(
                              padding: const EdgeInsets.only(top: 14),
                              child: Text('«${i['message']}»',
                                  style: const TextStyle(
                                      fontSize: 12, height: 1.55))),
                        if (pending) ...[
                          const SizedBox(height: 10),
                          Row(children: [
                            for (final entry in {
                              'decline': 'Отказаться',
                              'accept': 'Ответить'
                            }.entries) ...[
                              if (entry.key == 'accept')
                                const SizedBox(width: 12),
                              Expanded(
                                  child: button(
                                      entry.value,
                                      () => act(() async {
                                            await api.request(
                                                '/order-invites/${i['id']}/respond',
                                                method: 'POST',
                                                body: {
                                                  'expected_version':
                                                      i['version'],
                                                  'decision': entry.key
                                                });
                                            setState(() => revision++);
                                            if (entry.key == 'accept') {
                                              go('offer', i['order_id']);
                                            } else {
                                              success('Ответ сохранён');
                                            }
                                          }),
                                      outline: entry.key == 'decline')),
                            ]
                          ])
                        ] else
                          button('Подробнее', () => go('order', i['order_id']),
                              outline: true),
                      ],
                      if (i['expires_at'] != null)
                        Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                                '${localize(context, 'Приглашение действует до')} ${dateLabel(i['expires_at'])}',
                                style: const TextStyle(
                                    fontSize: 10, color: muted)))
                    ]));
          }));
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
            child: button('Начать обращение', () => go('support-new'))),
        Expanded(
            child: paged(
                '/me/support-threads',
                (t) => DataCard('${t['subject']}',
                    status: status(t),
                    onTap: () => go('support-chat', t['id']))))
      ]));
  Widget reviewScreen() => page(
      'Как всё прошло?',
      loaded('/orders/$objectId', (data, reload) {
        final order = data as Json;
        final own = order['my_review'];
        final person =
            order['owner'] == me?['id'] ? order['executor'] : order['customer'];
        if (own != null)
          return listBody([
            const UiHeading('Отзыв сохранён'),
            JobaBadge(status(own)),
            const Notice(
                'Отзывы участников публикуются одновременно или после окончания срока ожидания.',
                icon: 'info'),
            DataCard('${own['rating']} ★', subtitle: own['text'] ?? ''),
            button(
                'Редактировать отзыв',
                () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                        builder: (c) => Scaffold(
                            appBar: AppBar(
                                title: const UiText('Редактировать отзыв')),
                            body: ActionForm(
                                fields: [
                                  InputSpec('rating', 'Оценка',
                                      initial: '${own['rating']}',
                                      options: {
                                        for (var value = 1; value <= 5; value++)
                                          '$value': '$value ★'
                                      }),
                                  InputSpec('text', 'Ваш отзыв',
                                      initial: own['text'] ?? '',
                                      required: false,
                                      multiline: true)
                                ],
                                submit: (fields) async {
                                  await api.request('/reviews/${own['id']}',
                                      method: 'PATCH',
                                      body: {
                                        'expected_version': own['version'],
                                        'rating': int.parse(fields['rating']!),
                                        'text': fields['text']
                                      });
                                  if (c.mounted) Navigator.pop(c);
                                  reload();
                                })))),
                outline: true)
          ]);
        return ActionForm(
            stickySubmit: true,
            submitEnabled: reviewRating > 0 &&
                order['status'] == 'completed' &&
                [order['owner'], order['executor_id']].contains(me?['id']),
            before: [
              Center(
                  child: JobaAvatar(
                      api: api,
                      name: person?['display_name'] ?? '',
                      id: person?['avatar_id'],
                      size: 68)),
              const SizedBox(height: 16),
              Center(
                  child: Text(person?['display_name'] ?? '',
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w700))),
              const SizedBox(height: 4),
              Center(
                  child: Text(order['title'] ?? '',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12, color: muted))),
              const SizedBox(height: 20),
              Row(children: [
                for (var value = 1; value <= 5; value++)
                  Expanded(
                      child: IconButton(
                          tooltip: '${localize(context, 'Оценка')} $value',
                          onPressed: () => setState(() => reviewRating = value),
                          icon: JobaIcon('star',
                              size: 37,
                              color: reviewRating >= value
                                  ? const Color(0xFFC39119)
                                  : line,
                              fill: reviewRating >= value ? yellow : null)))
              ])
            ],
            fields: const [
              InputSpec('text', 'Ваш отзыв', multiline: true, required: false)
            ],
            afterFields: const [
              Notice(
                  'Отзывы участников публикуются одновременно или после окончания срока ожидания.',
                  icon: 'info')
            ],
            button: 'Отправить отзыв',
            submit: (fields) async {
              await api.request('/orders/${order['id']}/reviews',
                  method: 'POST',
                  body: {'rating': reviewRating, 'text': fields['text']});
              go('review-sent', order['id']);
            });
      }));
  String reportTargetType = 'order', reportReason = 'agreement';
  final List<String> reportUploads = [];
  void reportObject(String id, String type) {
    reportTargetType = type;
    reportReason = 'agreement';
    reportUploads.clear();
    go('report', id);
  }

  Widget reportScreen() => page(
      'Сообщить о проблеме',
      ActionForm(
          stickySubmit: true,
          externalBusy: actionBusy,
          before: [
            const UiHeading('Поможем разобраться',
                'Обращение будет видно только вам и поддержке.'),
            const UiText('Причина',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
            const SizedBox(height: 8),
            RadioGroup<String>(
                groupValue: reportReason,
                onChanged: (value) => setState(() => reportReason = value!),
                child: Column(children: [
                  for (final reason in {
                    'agreement': [
                      'Нарушение договорённости',
                      'Сроки, результат или условия'
                    ],
                    'unsafe': [
                      'Небезопасное поведение',
                      'Угрозы, оскорбления или подозрительные действия'
                    ],
                    'content': [
                      'Недопустимый контент',
                      'Фото, текст или контакты'
                    ]
                  }.entries)
                    Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                            color: reportReason == reason.key
                                ? const Color(0xFFF0F4FF)
                                : Colors.white,
                            border: Border.all(
                                color: reportReason == reason.key
                                    ? primary
                                    : line),
                            borderRadius: BorderRadius.circular(14)),
                        child: RadioListTile<String>(
                            value: reason.key,
                            controlAffinity: ListTileControlAffinity.trailing,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 6),
                            fillColor: WidgetStateProperty.resolveWith(
                                (states) =>
                                    states.contains(WidgetState.selected)
                                        ? primary
                                        : const Color(0xFFB8C8E3)),
                            enabled: !actionBusy,
                            title: UiText(reason.value.first,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 14)),
                            subtitle: UiText(reason.value.last,
                                style: const TextStyle(
                                    color: muted, fontSize: 12))))
                ]))
          ],
          fields: [
            InputSpec('description', 'Что произошло?',
                multiline: true,
                lines: 4,
                validate: (value) => value.trim().length < 10
                    ? localize(context, 'Опишите ситуацию подробнее')
                    : null)
          ],
          afterFields: [
            const UiText('Материалы',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
            for (final id in reportUploads)
              Row(children: [
                Expanded(child: AttachmentView(api: api, id: id)),
                IconButton(
                    onPressed: actionBusy
                        ? null
                        : () => setState(() => reportUploads.remove(id)),
                    tooltip: localize(context, 'Удалить'),
                    icon: const JobaIcon('trash'))
              ]),
            if (reportUploads.length < 10)
              JobaUploadButton('Добавить файл или фото',
                  onPressed: actionBusy
                      ? null
                      : () => act(() async {
                            final scope = objectId;
                            final file = await pickUpload('chat');
                            if (file != null &&
                                mounted &&
                                route == 'report' &&
                                objectId == scope)
                              setState(() => reportUploads.add(file['id']));
                          })),
            const SizedBox(height: 8),
            const UiText('Безопасные вложения проверяются перед показом.',
                style: TextStyle(color: muted, fontSize: 10))
          ],
          button: 'Отправить обращение',
          submit: (fields) async {
            final record = await api.request('/cases', method: 'POST', body: {
              ...fields,
              'target_type': reportTargetType,
              'target_id': objectId,
              'reason_code': reportReason,
              'upload_ids': reportUploads
            }) as Json;
            reportUploads.clear();
            success('Жалоба отправлена');
            go('case', record['id']);
          }));
  String casesBucket = 'open';
  Widget casesScreen() => page(
      'Мои обращения',
      loaded(
          '/me/cases/overview',
          (data, reload) => PagedList(
              key: ValueKey('cases:$casesBucket:$revision'),
              api: api,
              path: '/me/cases',
              query: {'bucket': casesBucket},
              header: Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Row(children: [
                    for (final entry in {
                      'open': 'Открытые',
                      'resolved': 'Решённые'
                    }.entries) ...[
                      if (entry.key == 'resolved') const SizedBox(width: 8),
                      ChoiceChip(
                          selected: casesBucket == entry.key,
                          onSelected: (_) =>
                              setState(() => casesBucket = entry.key),
                          label: Text(
                              '${localize(context, entry.value)} · ${data[entry.key]}'),
                          showCheckmark: false,
                          selectedColor: navy,
                          backgroundColor: Colors.white,
                          labelStyle: TextStyle(
                              color: casesBucket == entry.key
                                  ? Colors.white
                                  : navy,
                              fontSize: 12),
                          side: BorderSide(
                              color: casesBucket == entry.key ? navy : line),
                          shape: const StadiumBorder())
                    ]
                  ])),
              tile: caseCard,
              footer: button('Новое обращение', () => go('support'),
                  outline: true))));
  Widget caseCard(Json record) => Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: line),
          borderRadius: BorderRadius.circular(16)),
      child: Material(
          color: Colors.transparent,
          child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => go('case', record['id']),
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          JobaBadge(status(record)),
                          const Spacer(),
                          Text(
                              '№ ${record['id'].toString().substring(0, 8).toUpperCase()}',
                              style:
                                  const TextStyle(fontSize: 10, color: muted))
                        ]),
                        const SizedBox(height: 12),
                        UiText(
                            const {
                                  'agreement': 'Нарушение договорённости',
                                  'unsafe': 'Небезопасное поведение',
                                  'content': 'Недопустимый контент',
                                  'spam': 'Спам',
                                  'fraud': 'Подозрение на обман',
                                  'dictionary_match': 'Проверка содержания'
                                }[record['reason_code']] ??
                                'Обращение',
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        Text(record['description'] ?? record['reason'] ?? '',
                            style: const TextStyle(
                                fontSize: 12, color: muted, height: 1.55)),
                        if (record['response_due_at'] != null)
                          Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(
                                  '${localize(context, 'Ответить до')} ${dateLabel(record['response_due_at'])}',
                                  style: const TextStyle(
                                      fontSize: 12, color: primary)))
                      ])))));
  Widget caseScreen() => page(
      'Обращение',
      loaded(
          '/cases/$objectId',
          (data, reload) => listBody([
                DataCard('${data['reason_code'] ?? 'Обращение'}',
                    status: status(data),
                    subtitle: '${data['description'] ?? ''}'),
                for (final id in data['upload_ids'] as List? ?? [])
                  AttachmentView(api: api, id: id),
                if (data['appeal_reason'] != null)
                  DataCard('Ваша апелляция',
                      translateTitle: true, subtitle: data['appeal_reason']),
                for (final id in data['appeal_upload_ids'] as List? ?? [])
                  AttachmentView(api: api, id: id),
                SizedBox(
                    height: 280,
                    child: paged(
                        '/cases/${data['id']}/messages',
                        (message) => DataCard(
                            message['owner'] == me!['id']
                                ? 'Вы'
                                : 'Участник обращения',
                            subtitle: '${message['text']}',
                            status: '${message['created_at']}'))),
                button('Написать по обращению',
                    () => caseForm(false, data, reload),
                    outline: true),
                if (data['subject_user_id'] == me!['id'] &&
                    (['resolved', 'restricted'].contains(data['status'])) &&
                    (data['status'] == 'restricted' ||
                        ['content_removed', 'sanction_upheld']
                            .contains(data['decision'])))
                  button(
                      'Обжаловать решение', () => caseForm(true, data, reload)),
              ])));
  void caseForm(bool appeal, Json data, VoidCallback reload) {
    if (appeal) {
      Navigator.push<void>(
          context,
          MaterialPageRoute(
              builder: (c) => AppealEditor(
                  api: api,
                  incident: data,
                  pickUpload: () => pickUpload('chat'),
                  onCases: () {
                    Navigator.pop(c);
                    go('cases');
                  }))).then((_) {
        if (mounted) setState(() => revision++);
      });
      return;
    }
    Navigator.push(
        context,
        MaterialPageRoute<void>(
            builder: (c) => Scaffold(
                appBar: AppBar(
                    title: UiText(
                        appeal ? 'Апелляция' : 'Сообщение по обращению')),
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
  }

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
                const UiHeading('Ваши возможности'),
                if (items(data[0]).isEmpty)
                  const Notice('Активных прав доступа пока нет.'),
                for (final r in items(data[0]))
                  DataCard('Доступ JOBA',
                      translateTitle: true,
                      status: status(r),
                      subtitle:
                          '${r['valid_until'] ?? r['ends_at'] ?? r['expires_at'] ?? ''}'),
                for (final r in items(data[2]))
                  DataCard('Подписка',
                      translateTitle: true,
                      status: status(r),
                      subtitle: '${r['ends_at'] ?? ''}'),
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
                const UiHeading('Ваши данные'),
                for (final r in items(data))
                  DataCard(
                      r['type'] == 'export'
                          ? 'Экспорт данных'
                          : 'Удаление аккаунта',
                      translateTitle: true,
                      status: status(r),
                      footer: Column(children: [
                        if (r['type'] == 'export' &&
                            r['status'] == 'completed' &&
                            r['upload_id'] != null)
                          button(
                              'Сохранить архив',
                              () => act(() async {
                                    final result =
                                        await saveExport(api, r['upload_id']);
                                    if (result == ExportResult.saved)
                                      success('Архив сохранён');
                                    if (result == ExportResult.started)
                                      success('Загрузка передана браузеру');
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
                button('Правовые документы', () => go('legal'), outline: true),
                button('Согласия и документы', () => go('terms'),
                    outline: true),
              ])));
  void privacyRequest(String type, VoidCallback reload) => Navigator.push(
      context,
      MaterialPageRoute<void>(
          builder: (c) => Scaffold(
              appBar: AppBar(
                  title: UiText(type == 'export'
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
      ApiView(
          key: ValueKey('security:$revision'),
          load: () => Future.wait([
                api.request('/me/sessions'),
                lock?.hasPin() ?? Future.value(false),
                lock?.hasBiometry() ?? Future.value(false)
              ]),
          builder: (c, result, reload) => listBody([
                const UiHeading('Вы управляете доступом',
                    'Один аккаунт, только ваши устройства.'),
                JobaMenu([
                  JobaMenuEntry(
                      'PIN приложения', 'lock', () => go('lock-setup'),
                      subtitle: result[1] == true ? 'Настроен' : 'Не настроен'),
                  JobaMenuEntry('Биометрия', 'face', () => go('lock-setup'),
                      subtitle: result[2] == true
                          ? 'Включена на этом устройстве'
                          : 'Не настроена'),
                  JobaMenuEntry('Пароль', 'lock', () => go('password'),
                      subtitle: 'Изменить пароль аккаунта'),
                  JobaMenuEntry(
                      'Устройства и сессии', 'phone', () => go('sessions'),
                      subtitle:
                          '${items(result[0]).length} · ${localize(context, 'Активные')}',
                      translateSubtitle: false)
                ]),
                const SizedBox(height: 20),
                Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: line),
                        borderRadius: BorderRadius.circular(16)),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(children: [
                            JobaIcon('shield', size: 30, color: primary),
                            SizedBox(width: 10),
                            Expanded(
                                child: UiText('Сохранённая сессия',
                                    style: TextStyle(
                                        fontSize: 20,
                                        height: 1.35,
                                        letterSpacing: -.4,
                                        fontWeight: FontWeight.w700)))
                          ]),
                          const SizedBox(height: 14),
                          const UiText(
                              'PIN или биометрия открывают приложение только на этом устройстве. Для нового устройства нужен полный вход.',
                              style: TextStyle(
                                  fontSize: 12, color: muted, height: 1.55))
                        ])),
                const Notice(
                    'Проверка документа исполнителя выполняется отдельно от PIN и биометрии.',
                    icon: 'info',
                    margin: EdgeInsets.only(top: 16, bottom: 0)),
                const SizedBox(height: 20),
                JobaMenu([
                  JobaMenuEntry(
                      'Изменить номер телефона', 'phone', () => go('phone')),
                  JobaMenuEntry(
                      'Заблокированные контакты', 'shield', () => go('blocks')),
                  JobaMenuEntry(
                      'Документ исполнителя', 'file', () => go('verification'))
                ])
              ])));
  Widget sessionsScreen() => page(
      'Устройства и сессии',
      loaded(
          '/me/sessions',
          (data, reload) => listBody([
                const UiHeading('Активные сессии',
                    'Завершите сеансы, которые вам не нужны.'),
                for (final record in items(data))
                  DataCard('Сессия',
                      translateTitle: true,
                      subtitle: dateLabel(record['expires_at']),
                      footer: button(
                          'Завершить сессию',
                          () => act(() async {
                                await api.request(
                                    '/me/sessions/${record['family']}',
                                    method: 'DELETE');
                                if (record['current'] == true) {
                                  await api.forget();
                                  return;
                                }
                                reload();
                              }),
                          outline: true)),
                button('Завершить все сессии', () => go('logout-all'),
                    outline: true)
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
        JobaMenu([
          JobaMenuEntry('Язык интерфейса', 'globe', () => go('languages'),
              subtitle: const {
                'ru': 'Русский',
                'kk': 'Қазақша',
                'sr': 'Српски',
                'be': 'Беларуская'
              }[locale]),
          JobaMenuEntry('Страна услуг', 'pin', () => go('country'),
              subtitle: countryName(country), translateSubtitle: false),
          JobaMenuEntry(
              'Уведомления', 'bell', () => go('notification-settings'),
              subtitle: 'События заказов и сообщения'),
          JobaMenuEntry('Безопасность', 'lock', () => go('security'),
              subtitle: 'PIN, биометрия, пароль'),
          JobaMenuEntry('О приложении', 'info', () => go('about'),
              subtitle: 'JOBA · 0.1.0', translateSubtitle: false)
        ]),
        const Notice(
            'Смена страны не переносит данные автоматически. Проверьте доступность и условия нового региона.',
            icon: 'info',
            margin: EdgeInsets.only(top: 24, bottom: 24)),
        OutlinedButton(
            onPressed: actionBusy ? null : confirmLogout,
            child: const UiText('Выйти из аккаунта'))
      ]));
  void confirmLogout() => go('logout-confirm');

  Widget logoutConfirmation() => page(
      'Выйти из аккаунта?',
      listBody([
        JobaStatePanel(
            title: 'Завершить сеанс\nна этом устройстве?',
            message:
                'Локальный PIN и приватный кэш будут удалены. Для следующего входа понадобится номер и пароль.',
            icon: 'logout',
            primaryLabel: 'Выйти',
            destructive: true,
            onPrimary: () => act(() => api.logout()),
            secondaryLabel: 'Остаться',
            onSecondary: back)
      ]),
      titleOffset: -12);

  Widget languageScreen() {
    var selected = pendingLocale ?? locale;
    return page(
        'Язык приложения',
        StatefulBuilder(
            builder: (c, update) => Column(children: [
                  Expanded(
                      child: listBody([
                    const UiHeading('Выберите язык',
                        'Язык интерфейса не меняет страну услуги.'),
                    for (final language in const {
                      'ru': 'Русский',
                      'kk': 'Қазақша',
                      'sr': 'Српски',
                      'be': 'Беларуская'
                    }.entries)
                      Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Material(
                              color: selected == language.key
                                  ? const Color(0xFFF1F5FE)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              child: InkWell(
                                  onTap: () => update(() {
                                        selected = language.key;
                                        pendingLocale = selected;
                                      }),
                                  borderRadius: BorderRadius.circular(14),
                                  child: Container(
                                      constraints:
                                          const BoxConstraints(minHeight: 76),
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                          border: Border.all(
                                              color: selected == language.key
                                                  ? primary
                                                  : line),
                                          borderRadius:
                                              BorderRadius.circular(14)),
                                      child: Row(children: [
                                        Expanded(
                                            child: Text(language.value,
                                                style: const TextStyle(
                                                    fontSize: 14,
                                                    fontWeight:
                                                        FontWeight.w700))),
                                        Icon(
                                            selected == language.key
                                                ? Icons.radio_button_checked
                                                : Icons.radio_button_off,
                                            size: 20,
                                            color: selected == language.key
                                                ? primary
                                                : line)
                                      ])))))
                  ])),
                  SafeArea(
                      top: false,
                      child: Container(
                          color: Colors.white,
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                          child: FilledButton(
                              onPressed: actionBusy
                                  ? null
                                  : () => act(() async {
                                        final current =
                                            await api.request('/me') as Json;
                                        final result = await api.request('/me',
                                            method: 'PATCH',
                                            body: {
                                              'expected_version':
                                                  current['version'],
                                              'locale': selected
                                            }) as Json;
                                        if (!mounted) return;
                                        me = result;
                                        locale = selected;
                                        widget.onLocaleChanged?.call(selected);
                                        await preferences?.save(
                                            country, selected);
                                        back();
                                      }),
                              child: const UiText('Сохранить выбор'))))
                ])));
  }

  Widget countryScreen() => page(
      'Страна услуг',
      listBody([
        const UiHeading(
            'Выберите страну', 'Страна и язык выбираются отдельно.'),
        const Notice(
            'Смена страны не переносит данные автоматически. Проверьте доступность и условия нового региона.',
            icon: 'info'),
        for (final entry in const {
          'KZ': 'Казахстан',
          'RS': 'Сербия',
          'RU': 'Россия',
          'BY': 'Беларусь'
        }.entries)
          Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: OutlinedButton(
                  onPressed: actionBusy
                      ? null
                      : () => act(() async {
                            if (entry.key == country) return;
                            final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (c) => AlertDialog(
                                        title: const UiText(
                                            'Сменить страну услуг?'),
                                        content: const UiText(
                                            'Для смены страны завершите текущую сессию и войдите в аккаунт выбранного региона.'),
                                        actions: [
                                          TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(c, false),
                                              child: const UiText('Отмена')),
                                          TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(c, true),
                                              child: const UiText('Продолжить'))
                                        ]));
                            if (confirmed != true) return;
                            await chooseCountry(entry.key);
                          }),
                  child: UiText(entry.value)))
      ]));
  Widget aboutScreen() => page(
      'О приложении',
      listBody([
        Center(
            child: Image.asset('assets/joba-logo-original.jpeg',
                width: 140, height: 140)),
        const SizedBox(height: 24),
        const UiHeading(
            'JOBA', 'Находите специалистов и заказы в вашем городе.'),
        const Center(
            child: Text('0.1.0 · 1',
                style: TextStyle(fontSize: 12, color: muted))),
        const SizedBox(height: 24),
        JobaMenu([
          JobaMenuEntry('Правовые документы', 'file', () => go('legal')),
          JobaMenuEntry('Документы и согласия', 'shield', () => go('terms')),
          JobaMenuEntry('Поддержка', 'help', () => go('support'))
        ])
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
                          }),
                    InputSpec('quiet_enabled', 'Часы тишины',
                        initial:
                            data[1]['quiet_hours'] == null ? 'false' : 'true',
                        options: const {
                          'false': 'Отключены',
                          'true': 'Включены'
                        }),
                    InputSpec('quiet_start', 'Начало (ЧЧ:ММ)',
                        initial:
                            '${data[1]['quiet_hours']?['start'] ?? '22:00'}'),
                    InputSpec('quiet_end', 'Окончание (ЧЧ:ММ)',
                        initial:
                            '${data[1]['quiet_hours']?['end'] ?? '08:00'}'),
                    InputSpec('time_zone', 'Часовой пояс IANA',
                        initial: '${data[1]['quiet_hours']?['time_zone'] ?? {
                              'KZ': 'Asia/Almaty',
                              'RS': 'Europe/Belgrade',
                              'RU': 'Europe/Moscow',
                              'BY': 'Europe/Minsk'
                            }[me?['country']] ?? 'UTC'}')
                  ],
                  submit: (v) async {
                    await api.request('/me/notification-preferences',
                        method: 'PATCH',
                        body: {
                          'expected_version': data[0]['version'],
                          'preferences': {
                            for (final key in ['chat', 'service', 'marketing'])
                              key: v[key] == 'true',
                            'quiet_hours': v['quiet_enabled'] == 'true'
                                ? {
                                    'start': v['quiet_start'],
                                    'end': v['quiet_end'],
                                    'time_zone': v['time_zone']
                                  }
                                : null
                          }
                        });
                    success('Настройки сохранены');
                    back();
                  })));
  void enterReferralCode() => Navigator.push(
      context,
      MaterialPageRoute<void>(
          builder: (c) => Scaffold(
              appBar: AppBar(title: const UiText('Код приглашения')),
              body: ActionForm(
                  fields: const [
                    InputSpec('code', 'Код')
                  ],
                  before: const [
                    UiHeading('Вас пригласил друг?',
                        'Введите его код, чтобы проверить условия бонуса.'),
                    Notice(
                        'Бонус появится после выполнения правил программы. Нельзя использовать собственный код или активировать приглашение повторно.')
                  ],
                  button: 'Проверить код',
                  submit: (values) async {
                    await api.request('/referrals/attribute',
                        method: 'POST', body: {'code': values['code']?.trim()});
                    if (c.mounted) Navigator.pop(c);
                    if (mounted) setState(() => revision++);
                  }))));
  Widget referralRulesScreen() => page(
      'Условия бонусов',
      loaded(
          '/me/referrals',
          (data, reload) => listBody([
                const UiHeading('Как получить бонус'),
                if ((data['campaigns'] as List).isEmpty)
                  const Notice('Активных программ приглашений пока нет.'),
                for (final campaign in (data['campaigns'] as List).cast<Json>())
                  DataCard('Условия программы',
                      translateTitle: true,
                      subtitle:
                          '${localize(context, 'Приглашений для награды')}: ${campaign['threshold']}\n${localize(context, 'Условие')}: ${localize(context, campaign['qualifying_event'] == 'executor_verified' ? 'Проверка исполнителя' : 'Завершённый заказ')}\n${localize(context, 'Срок доступа, мин')}: ${(campaign['reward_duration_seconds'] as num).toInt() ~/ 60}'),
                const Notice(
                    'Самоприглашение недопустимо. Бонус не превращается в деньги и не меняет рейтинг.')
              ])));
  Widget referralsScreen() => page(
      'Приглашения и бонусы',
      loaded('/me/referrals', (data, reload) {
        final attributions = (data['attributions'] as List).cast<Json>(),
            rewards = (data['rewards'] as List).cast<Json>();
        final qualified =
            attributions.where((r) => r['status'] == 'qualified').length;
        return listBody([
          Container(
              constraints: const BoxConstraints(minHeight: 165),
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                  color: navy, borderRadius: BorderRadius.circular(18)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const UiText('Вместе удобнее',
                        style: TextStyle(
                            color: Color(0xFFC5D3EB),
                            fontSize: 12,
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 16),
                    const UiText('Пригласите друга',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            height: 1.27,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),
                    UiText(
                        (data['campaigns'] as List).isEmpty
                            ? 'Активных программ приглашений пока нет.'
                            : 'Бонус доступа после выполнения условий программы.',
                        style: const TextStyle(
                            color: Color(0xFFC5D3EB),
                            fontSize: 12,
                            height: 1.5))
                  ])),
          const SizedBox(height: 20),
          Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: line),
                  borderRadius: BorderRadius.circular(16)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const UiText('Ваш код',
                        style: TextStyle(color: muted, fontSize: 12)),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                          child: SelectableText('${data['code']}',
                              style: const TextStyle(
                                  fontSize: 20,
                                  letterSpacing: 1,
                                  fontWeight: FontWeight.w700))),
                      IconButton(
                          tooltip: localize(context, 'Скопировать код'),
                          onPressed: () => act(() async {
                                await Clipboard.setData(
                                    ClipboardData(text: data['code']));
                                success('Код скопирован');
                              }),
                          icon: const JobaIcon('file'))
                    ]),
                    const SizedBox(height: 12),
                    button(
                        'Поделиться приглашением',
                        () => act(() async {
                              final shown = await shareInvitation(
                                  '${localize(context, 'Код приглашения')} JOBA: ${data['code']}');
                              if (!shown && mounted) success('Код скопирован');
                            }))
                  ])),
          const SizedBox(height: 24),
          const UiText('Ваш прогресс',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: line),
                  borderRadius: BorderRadius.circular(16)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        '${localize(context, 'Приглашения')}: ${attributions.length}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    Text(
                        '${localize(context, 'Выполнены условия')}: $qualified · ${localize(context, 'Ожидает условия')}: ${attributions.length - qualified}',
                        style: const TextStyle(color: muted, fontSize: 12))
                  ])),
          const SizedBox(height: 16),
          for (final reward in rewards)
            DataCard('Награда',
                translateTitle: true,
                status: status(reward),
                footer: reward['status'] == 'available'
                    ? button(
                        'Активировать',
                        () => act(() async {
                              await api.request(
                                  '/me/referral-rewards/${reward['id']}/redeem',
                                  method: 'POST');
                              reload();
                            }))
                    : null),
          JobaMenu([
            JobaMenuEntry(
                'Как начисляются бонусы', 'info', () => go('referral-rules'),
                subtitle: 'Условия, сроки и ограничения'),
            JobaMenuEntry('У меня есть код', 'gift', enterReferralCode,
                subtitle: 'Ввести приглашение друга')
          ])
        ]);
      }));
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
                          tooltip: localize(context, 'Выше'),
                          onPressed: i == 0
                              ? null
                              : () =>
                                  reorderProject(projects, i, i - 1, reload),
                          icon: const Icon(Icons.arrow_upward)),
                      IconButton(
                          tooltip: localize(context, 'Ниже'),
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
                tooltip: localize(context, 'Добавить проект'),
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
  Widget ownProjectDetailScreen() => page(
      'Проект портфолио',
      loaded(
          '/me/portfolio-projects/$objectId',
          (project, reload) => PortfolioDetail(
              api: api,
              project: project,
              author: me?['display_name'] ?? '',
              avatarId: me?['avatar_id'],
              onAuthor: () => go('services'),
              onEdit: () => go('portfolio-edit', project['id']),
              onSubmit: ['draft', 'rejected'].contains(project['status'])
                  ? () => act(() async {
                        await api.request(
                            '/me/portfolio-projects/${project['id']}/submit',
                            method: 'POST',
                            body: {'expected_version': project['version']});
                        reload();
                      })
                  : null,
              onDelete: () => act(() async {
                    final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (c) => AlertDialog(
                                title: const UiText('Удалить проект?'),
                                actions: [
                                  TextButton(
                                      onPressed: () => Navigator.pop(c, false),
                                      child: const UiText('Отмена')),
                                  TextButton(
                                      onPressed: () => Navigator.pop(c, true),
                                      child: const UiText('Удалить'))
                                ]));
                    if (confirmed != true) return;
                    await api.request('/me/portfolio-projects/${project['id']}',
                        method: 'DELETE',
                        body: {'expected_version': project['version']});
                    if (mounted) go('portfolio');
                  }))));
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
                      translateOptions: false,
                      initial: p?['category_id'] ?? '',
                      options: {
                        for (final r in items(data[0])) r['id']: r['name']
                      }),
                  InputSpec('order_id', 'Связать с выполненным заказом',
                      pickerApi: api,
                      pickerPath: '/me/completed-orders',
                      pickerQuery: const {'role': 'executor'},
                      translateOptions: false,
                      initial: p?['order_id'] ?? '',
                      required: false,
                      options: const {'': 'Без связи с заказом'}),
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
                        'order_id':
                            v['order_id']!.isEmpty ? null : v['order_id'],
                        'rights_confirmed': v['rights_confirmed'] == 'true',
                        if (p != null) 'expected_version': p['version']
                      }) as Json;
                  success('Проект сохранён');
                  go('portfolio-project', saved['id']);
                },
                after: [
                  if (p != null) ...[
                    Notice(
                        '${localize(context, status(p))} · ${(p['photos'] as List).length} ${localize(context, 'фото')}'),
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
                    button('История опубликованных версий',
                        () => go('content-history', p['id']),
                        outline: true),
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
        allowedExtensions: purpose == 'identity' || purpose == 'chat'
            ? ['jpg', 'jpeg', 'png', 'pdf']
            : ['jpg', 'jpeg', 'png'],
        withData: true);
    if (selected == null) return null;
    final f = selected.files.single;
    if (f.bytes == null)
      throw ApiException('FILE_UNAVAILABLE', 'Не удалось прочитать файл');
    return api.upload(
        f.bytes!,
        f.extension?.toLowerCase() == 'pdf'
            ? 'application/pdf'
            : f.extension?.toLowerCase() == 'png'
                ? 'image/png'
                : 'image/jpeg',
        purpose,
        verificationId: verificationId);
  }

  String verificationTitle = 'Проверка исполнителя';
  Widget verificationScreen() => page(
      verificationTitle,
      VerificationEditor(
          api: api,
          country: country,
          uploads: verificationUploads,
          revision: revision,
          onTitle: (value) {
            if (mounted && value != verificationTitle)
              setState(() => verificationTitle = value);
          },
          pick: (id) => pickUpload('identity', verificationId: id),
          onTerms: () => go('terms'),
          onProfile: () => go('services'),
          onSupport: () => go('support')));
  Widget termsScreen() => page(
      registrationInProgress ? 'Перед началом' : 'Документы и согласия',
      ApiView(
          load: () async => Future.wait([
                api.request('/legal/documents', query: {
                  'country': country,
                  'locale': me?['locale'] ?? locale,
                  'required': 'true'
                }),
                api.request('/me/consents')
              ]),
          builder: (context, result, reload) {
            final documents = items(result[0]), consents = items(result[1]);
            bool accepted(Json document) {
              final relevant = consents
                  .where((consent) => consent['document_id'] == document['id'])
                  .toList()
                ..sort((a, b) =>
                    (b['sequence'] as num).compareTo(a['sequence'] as num));
              return relevant.isNotEmpty &&
                  relevant.first['accepted'] == true &&
                  relevant.first['document_hash'] == document['hash'];
            }

            final needsAge = documents.any((d) {
              if (d['minimum_age'] != 18) return false;
              final relevant = consents
                  .where((c) => c['document_id'] == d['id'])
                  .toList()
                ..sort((a, b) =>
                    (b['sequence'] as num).compareTo(a['sequence'] as num));
              return relevant.isEmpty ||
                  relevant.first['accepted'] != true ||
                  relevant.first['document_hash'] != d['hash'] ||
                  relevant.first['age_confirmed'] != true;
            });
            if (registrationInProgress || needsAge)
              return OnboardingConsent(
                  api: api,
                  documents: documents,
                  countryLabel: countryName(country),
                  localeLabel: {
                        'ru': 'Русский',
                        'kk': 'Қазақша',
                        'sr': 'Srpski',
                        'be': 'Беларуская'
                      }[locale] ??
                      locale,
                  onAccepted: () =>
                      go(registrationInProgress ? 'onboarding' : 'home'));
            final requiredDocuments = documents.where((d) => [
                  'privacy',
                  'privacy_policy',
                  'terms',
                  'terms_of_use'
                ].contains(d['type']));
            final canContinue = requiredDocuments.every(accepted);
            return listBody([
              const UiHeading('Условия JOBA'),
              if (documents.isEmpty)
                const Notice('Утверждённые документы ещё не опубликованы.'),
              for (final document in documents)
                DataCard('${document['title'] ?? document['type']}',
                    subtitle: '${document['content'] ?? ''}',
                    footer: Column(children: [
                      UiText(accepted(document)
                          ? 'Эта версия принята'
                          : 'Эта версия не принята'),
                      button(
                          accepted(document)
                              ? 'Отозвать согласие'
                              : 'Принять эту версию',
                          () => act(() async {
                                await api.request('/me/consents',
                                    method: 'POST',
                                    body: {
                                      'document_id': document['id'],
                                      'document_hash': document['hash'],
                                      'accepted': !accepted(document)
                                    });
                                reload();
                              }),
                          outline: accepted(document))
                    ])),
              if (!canContinue)
                const Notice(
                    'Чтобы продолжить, примите условия использования и политику конфиденциальности.'),
              FilledButton(
                  onPressed: canContinue
                      ? () => go(registrationInProgress ? 'onboarding' : 'home')
                      : null,
                  child: const UiText('Продолжить')),
              TextButton(
                  onPressed: () => go('support'),
                  child: const UiText('Поддержка'))
            ]);
          }));
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
                const UiHeading('Больше внимания к вашей работе'),
                const Notice(
                    'Оплата продвижений станет доступна после подключения платёжной системы.'),
                for (final r in items(data))
                  DataCard('Размещение',
                      translateTitle: true,
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
  Object? error;
  String? pendingId;
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
      if (mounted) setState(() => error = e);
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
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => historyBusy = false);
      resumePending();
    }
  }

  void edit(Json message) => Navigator.push(
      context,
      MaterialPageRoute<void>(
          builder: (c) => Scaffold(
              appBar: AppBar(title: const UiText('Изменить сообщение')),
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
                  title: const UiText('Изменить'),
                  onTap: () => Navigator.pop(c, 'edit')),
              ListTile(
                  title: const UiText('Удалить'),
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
        if (mounted) setState(() => error = e);
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
      if (mounted) setState(() => error = e);
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
      if (mounted) setState(() => error = e);
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
      if (mounted) setState(() => error = e);
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
              child: Notice(errorText(context, error!), error: true)),
        Expanded(
            child: messages.isEmpty
                ? Center(
                    child: loading
                        ? const CircularProgressIndicator()
                        : const UiText('Начните разговор'))
                : ListView.builder(
                    controller: scroll,
                    padding: const EdgeInsets.all(20),
                    itemCount: messages.length + (moreHistory ? 1 : 0),
                    itemBuilder: (c, i) {
                      if (moreHistory && i == 0)
                        return TextButton(
                            onPressed: historyBusy ? null : older,
                            child: UiText(historyBusy
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
                                            ? localize(
                                                context, 'Сообщение удалено')
                                            : m['hidden'] == true
                                                ? localize(context,
                                                    'Сообщение временно скрыто')
                                                : m['text'] ?? ''),
                                        for (final id
                                            in (m['upload_ids'] as List? ?? []))
                                          AttachmentView(
                                              api: widget.api, id: id),
                                        if (own)
                                          UiText(
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
                        tooltip: localize(context, 'Добавить файл'),
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
                          decoration: InputDecoration(
                              hintText: localize(context, 'Сообщение')))),
                  IconButton(
                      tooltip: localize(context, 'Отправить'),
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
                      label: UiText(file['mime'].startsWith('image/')
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
            label: const UiText('Сохранить вложение'),
            onPressed: () async {
              try {
                final bytes = await api.download(id);
                await FilePicker.platform.saveFile(
                    dialogTitle: 'Сохранить вложение JOBA',
                    fileName: 'joba-attachment.pdf',
                    bytes: bytes);
              } catch (e) {
                if (context.mounted)
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(errorText(context, e))));
              }
            });
      });
}
