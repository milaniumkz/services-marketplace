import 'referral_rules.dart';
import 'referral_code.dart';
import 'referral_reward_card.dart';
import 'referral_hero_decoration.dart';
import 'service_area.dart';
import '../core/design_states.dart';
import 'search_filters.dart';
import 'support_new.dart';
import 'legal_documents.dart';
import 'account_restrictions.dart';
import 'appeal_editor.dart';
import 'action_receipt.dart';
import 'content_review_receipt.dart';
import 'privacy_export.dart';
import 'top_listings.dart';
import 'revoke_session.dart';
import 'device_setup.dart';
import 'commerce_states.dart';
import 'refunds.dart';
import 'executor_access.dart';
import 'order_overview.dart';
import 'conversation_inbox.dart';
import 'offer_editor.dart';
import 'offer_list.dart';
import 'promotion_purchase.dart';
import 'privacy_states.dart';
import 'geo_states.dart';
import '../core/commerce_gateway.dart';
import 'work_states.dart';
import 'portfolio_photos.dart';
import 'portfolio_editor.dart';
import 'promotions_history.dart';
import 'portfolio_detail.dart';
import 'contractor_profile.dart';
import 'onboarding_consent.dart';
import 'unlock_keypad.dart';
import 'pin_limit.dart';
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
  'order.completion_requested': 'Исполнитель прислал результат работы',
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
  final CommerceGateway commerceGateway;
  final JobaApi? api;
  final ValueChanged<String>? onLocaleChanged;
  final RegionGateway? regions;
  final DevicePreferences? preferences;
  const Marketplace(
      {this.api, this.commerceGateway=const DisconnectedCommerceGateway(),
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
  String exportTitle = 'Экспорт готовится';
  String ordersBucket = 'active';
  final List<String> draftPhotos = [];
  final Map<String, List<String>> verificationUploads = {};
  Json? draftWindow;
  bool selectionAcknowledged = false;
  String? acknowledgedSelection;
  String cancellationReason = 'plans';
  int reviewRating = 0;
  final List<(String, String?)> history = [];
  bool starting = true, executor = false, actionBusy = false;
  bool authSubmitting = false, authCredentialFailure = false;
  bool localSetupSubmitting = false, unlockSubmitting = false;
  int authFormRevision = 0, profilePending = 0;
  String authPhoneInitial = '';
  Json? profileDraft;
  String? profileDraftScope;
  bool get authNavigationBlocked =>
      unlockSubmitting ||
      (profilePending > 0 && ['onboarding', 'profile-edit'].contains(route)) ||
      (authSubmitting && ['login', 'register'].contains(route)) ||
      (localSetupSubmitting && ['pin-setup', 'lock-setup', 'biometric'].contains(route));
  Object? startupError;
  int revision = 0, sequence = 0;
  String? notificationReadBefore, notificationScope;
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
        authPhoneInitial = '';
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
        profileDraft = null; profileDraftScope = null;
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
    if (authNavigationBlocked) return;
    ScaffoldMessenger.maybeOf(context)?.removeCurrentSnackBar();
    if (next == 'languages') pendingLocale = null;
    setState(() {
      authCredentialFailure = false;
      history.add((route, objectId));
      route = next;
      if (next == 'catalog') catalogPresentation = 'loading';
      if (next == 'export-pending') exportTitle = 'Экспорт готовится';
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
    if (authNavigationBlocked) return;
    if (route == 'pin-limit') {
      leavePinLimit('login');
      return;
    }
    if (route == 'login' && authCredentialFailure) {
      setState(() { authCredentialFailure = false; authFormRevision++; });
      return;
    }
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

  Widget button(String label, VoidCallback onPressed, {bool outline = false, bool enabled = true}) =>
      Padding(
          padding: const EdgeInsets.only(top: 12),
          child: outline
              ? OutlinedButton(
                  onPressed: actionBusy || !enabled ? null : onPressed,
                  child: UiText(label))
              : FilledButton(
                  onPressed: actionBusy || !enabled ? null : onPressed,
                  child: UiText(label)));
  Widget page(String title, Widget body,
          {List<Widget> actions = const [],
          bool nav = false,
          bool chrome = true,
          double titleOffset = 0,
          Widget? titleWidget, double? toolbarHeight, double leadingWidth = 72}) =>
      PopScope(
          canPop: history.isEmpty && route != 'pin-limit' && !authNavigationBlocked && !(route == 'login' && authCredentialFailure),
          onPopInvokedWithResult: (popped, result) {
            if (!popped) back();
          },
          child: Scaffold(
              backgroundColor: canvas,
              appBar: chrome
                  ? AppBar(
                      leadingWidth: leadingWidth,
                      toolbarHeight: toolbarHeight,
                      titleSpacing: titleWidget == null ? null : 0,
                      centerTitle: titleWidget == null,
                      title: Transform.translate(
                          offset: Offset(0, titleOffset), child: titleWidget ?? UiText(title)),
                      leading: IconButton(
                          onPressed: authNavigationBlocked ? null : back,
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
      case 'pin-setup':
      case 'lock-setup':
        return lockSetup();
      case 'biometric':
        return page('Биометрия',BiometrySetup(onPin:()=>go(locked?'unlock':'pin-setup'),onEnable:()async{
          await completeLocalSetup(biometry: true);
        }),titleOffset:-12);
      case 'pin-limit':
        return page('Нужен полный вход', PinLimit(
          onLogin: () => leavePinLimit('login'),
          onHelp: () => leavePinLimit('recovery'),
        ), titleOffset: -12);
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
      case 'profile-pending':
      case 'portfolio-pending':
        return page(
            route == 'profile-pending'
                ? 'Изменения на проверке'
                : 'Проект на проверке',
            ContentReviewReceipt(
                key: ValueKey('$route:$objectId:$revision'),
                api: api,
                profile: route == 'profile-pending',
                id: objectId,
                onContinue: () =>
                    go(route == 'profile-pending' ? 'services' : 'portfolio')),
            titleOffset: -12);
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
      case 'invited':
      case 'offer-revision':
      case 'amendment':
      case 'frozen-chat':
      case 'rework':
      case 'cancel-pending':
        return page({'invited':'Приглашение отправлено','offer-revision':'Условия изменились','amendment':'Новые условия','frozen-chat':'Чат временно закрыт','rework':'Нужна доработка','cancel-pending':'Отмена на согласовании'}[route]!,WorkStateScreen(key:ValueKey('work-state:$route:$objectId'),api:api,mode:route,id:objectId!,onGo:(r,id)=>go(r,id),pickPhoto:()=>pickUpload('order')),titleOffset:-12);
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
                            () => go('offer-revision', r['id']),
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
      case 'service-area':
        return page('Зона обслуживания',ServiceArea(api:api,locate:()async=>await const MethodChannel('joba.location').invokeMapMethod<String,dynamic>('current'),onSaved:()=>go('services')));
      case 'country-unavailable':
      case 'gps-denied':
      case 'map':
        return page({'country-unavailable':'Доступность региона','gps-denied':'Геолокация выключена','map':'Специалисты на карте'}[route]!,GeoStates(key:ValueKey('geo-state:$route:$revision'),api:api,mode:route,country:country,filters:listingFilters,onGo:(r,id)=>go(r,id)),titleOffset:-12);
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
            actions:[IconButton(tooltip:localize(context,'На карте'),onPressed:()=>go('map'),icon:const JobaIcon('pin'))],
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
        return page('Сообщения', ConversationInbox(api: api, revision: revision,
            onGo: (r,id)=>go(r,id)), chrome:false, nav:true);
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
        return notificationsScreen();
      case 'access':
        return executor ? accessScreen() : customerAccessScreen();
      case 'refunds':
        return page('Платежи и возвраты', RefundsScreen(api: api, onSupport: () => go('support')), titleOffset: -12);
      case 'my-access':
        return executor ? accessScreen() : customerAccessScreen();
      case 'checkout':
      case 'manage-subscription':
      case 'subscription-canceled':
      case 'payment-pending':
      case 'restore':
      case 'reward-granted':
      case 'reward-nofill':
      case 'reward-pending':
      case 'reward':
        if (!executor) return customerAccessScreen();
        return page({'checkout':'Условия подписки','manage-subscription':'Управление подпиской','subscription-canceled':'Продление отключено','payment-pending':'Проверяем покупку','restore':'Восстановление покупки','reward-granted':'Награда получена','reward-nofill':'Реклама недоступна','reward-pending':'Подтверждение просмотра','reward':'Доступ за рекламу'}[route]!,CommerceStateScreen(key:ValueKey('commerce:$route:$objectId'),api:api,mode:route,id:objectId,gateway:widget.commerceGateway,onGo:(r,id)=>go(r,id)),titleOffset:-12);
      case 'export':
        return page('Экспорт моих данных',
            ExportIntro(onRequest: () => privacyRequest('export', () {})),
            titleOffset: -12);
      case 'export-pending':
        final exportRequestId = objectId;
        return page(
            exportTitle,
            ExportStatus(
                key: ValueKey('export:$objectId:$revision'),
                api: api,
                id: objectId!,
                busy: actionBusy,
                onTitle: (title) {
                  if (mounted &&
                      route == 'export-pending' &&
                      objectId == exportRequestId &&
                      exportTitle != title) setState(() => exportTitle = title);
                },
                onPrivacy: () => go('privacy'),
                onNewRequest: () => go('export'),
                onDownload: (id) => act(() async {
                      final result = await saveExport(api, id);
                      if (result == ExportResult.saved)
                        success('Архив сохранён');
                      if (result == ExportResult.started)
                        success('Загрузка передана браузеру');
                    })),
            titleOffset: -12);
      case 'consents':
      case 'delete-account':
      case 'delete-confirm':
      case 'delete-scheduled':
        return page({'consents':'Мои согласия','delete-account':'Удалить аккаунт','delete-confirm':'Подтвердить удаление','delete-scheduled':'Запрос на удаление'}[route]!,PrivacyStates(key:ValueKey('privacy-state:$route:$objectId'),api:api,mode:route,id:objectId,onGo:(r,id)=>go(r,id)),titleOffset:-12);
      case 'legal-holds':
        return page('Хранение данных',paged('/me/legal-holds',(r)=>DataCard('${r['basis']}',subtitle:'${localize(context, 'Дата пересмотра')}: ${dateLabel(r['review_at'])}',status:status(r)),empty:'Нет действующих записей об удержании данных'));
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
      case 'revoke-session':
        return page('Завершить сеанс?', RevokeSession(api: api, family: objectId ?? '',
          onCancel: back, onRevoked: (current) async {
            if (current) { await api.forget(); return; }
            go('sessions');
          }), titleOffset: -12);
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
      case 'portfolio-photos':
        return page('Фото проекта',PortfolioPhotos(key:ValueKey('photos:$objectId:$revision'),api:api,id:objectId!,onDone:()=>go('portfolio-edit',objectId)),titleOffset:-12);
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
        return page('Топ-100', TopListings(api: api, initialCity: me?['city'] ?? '',
          onOpen: (type, id) => go(type == 'orders' ? 'order' : 'contractor', id)));
      case 'promotion-history':
        return page('Мои продвижения', PromotionsHistory(api: api, dateLabel: dateLabel,
          onNew: () => go('promotion'), onTerms: () => go('promotion-terms'), onOpen: (r) => go(r['status'] == 'resolution_required' ? 'promotion-resolution' : 'promotion-pending', r['id'])), titleOffset: -12);
      case 'promotion-pending':
      case 'promotion-resolution':
        return page(route == 'promotion-resolution' ? 'Нужно решение по оплате' : 'Проверка продвижения', PromotionStatus(api: api, id: objectId ?? '',
          onHistory: () => go('promotion-history'), onSupport: () => go('support')), titleOffset: -12);
      case 'promotion-checkout':
      case 'promotion-no-slots':
      case 'promotion-terms':
      case 'promotion':
        return page({'promotion':'Продвинуть объявление','promotion-checkout':'Проверить продвижение','promotion-no-slots':'Нет доступных мест','promotion-terms':'Условия размещения'}[route]!,PromotionPurchase(key:ValueKey('promotion:$route:$objectId'),api:api,mode:route,id:objectId,gateway:widget.commerceGateway,now:()=>api.clock.now,onGo:(r,id)=>go(r,id)),titleOffset:-12);
      default:
        return page(
            'JOBA',
            listBody([
              const Notice('Экран не найден'),
              button('Главная', () => go('home'))
            ]));
    }
  }

  Widget countryCard(String code, String name, String currency) => Semantics(
    button: true,
    selected: country == code,
    enabled: !actionBusy,
    child: Container(
      margin: const EdgeInsets.only(bottom: 10),
      height: 76,
      decoration: BoxDecoration(
        color: country == code ? const Color(0xFFF1F5FE) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: country == code ? primary : line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: actionBusy ? null : () => act(() => chooseCountry(code)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              if (code == 'KZ') ...[
                const JobaIcon('globe'),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    UiText(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.4,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    UiText(
                      currency,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: Color(0xFF627187),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: country == code ? primary : const Color(0xFFBBC7D9),
                    width: 1.5,
                  ),
                ),
                child: country == code
                    ? Center(
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: primary,
                          ),
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    ),
  );
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
          countryCard('KG', 'Кыргызстан', 'KGS'),
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
            decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: line))),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
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
      AutofillGroup(
        onDisposeAction: AutofillContextAction.cancel,
        child: ActionForm(
          key: ValueKey(route),
          authLayout: true,
          loginLayout: !register,
          errorResetKey: authFormRevision,
          onErrorChanged: (error) {
            if (mounted)
              setState(
                () => authCredentialFailure =
                    !register &&
                    error is ApiException &&
                    [
                      'INVALID_CREDENTIALS',
                      'RATE_LIMITED',
                    ].contains(error.code),
              );
          },
          credentialFailureAfter: [
            TextButton(
              style: TextButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
              ),
              onPressed: authSubmitting ? null : () => go('recovery'),
              child: const UiText('Помощь со входом'),
            ),
          ],
          onBusyChanged: (busy) {
            if (mounted) setState(() => authSubmitting = busy);
          },
          before: [
            UiHeading(
              register ? 'Добро пожаловать' : 'С возвращением',
              register
                  ? 'Один аккаунт для ваших задач и работы.'
                  : 'Войдите в свой аккаунт, чтобы продолжить.',
            ),
          ],
          fields: [
            InputSpec(
              'phone',
              'Номер телефона',
              initial: authPhoneInitial,
              hint:
                  '${{'KZ': '+7', 'RU': '+7', 'BY': '+375', 'KG': '+996'}[country]} · ${localize(context, 'Номер телефона').toLowerCase()}',
              originalIcon: 'phone',
              keyboard: TextInputType.phone,
              inputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.username],
              validate: (value) => RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(value.trim())
                  ? null : 'Введите номер в международном формате с кодом страны',
            ),
            InputSpec(
              'password',
              register ? 'Придумайте пароль' : 'Пароль',
              hint: register ? 'Не менее 15 символов' : 'Введите пароль',
              secret: true,
              inputAction: register
                  ? TextInputAction.next
                  : TextInputAction.done,
              autofillHints: [
                register ? AutofillHints.newPassword : AutofillHints.password,
              ],
              validate: (v) =>
                  register && v.length < 15 ? 'Не менее 15 символов'
                      : register && v.length > 128 ? 'Не более 128 символов' : null,
            ),
            if (register)
              const InputSpec(
                'repeat',
                'Повторите пароль',
                hint: 'Введите пароль ещё раз',
                secret: true,
                inputAction: TextInputAction.done,
                autofillHints: [AutofillHints.newPassword],
              ),
          ],
          afterField: register
              ? const {
                  'phone': [
                    Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: UiText(
                        'Номер будет вашим логином, он не подтверждён.',
                        style: TextStyle(
                          fontSize: 10,
                          color: muted,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                  'password': [
                    Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: UiText(
                        'Можно использовать пробелы и длинную фразу.',
                        style: TextStyle(
                          fontSize: 10,
                          color: muted,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                }
              : const {},
          afterFields: register
              ? const [
                  Notice(
                    'Сохраните пароль в надёжном месте. Он нужен для входа на новом устройстве.',
                    icon: 'info',
                    margin: EdgeInsets.zero,
                  ),
                  SizedBox(height: 20),
                ]
              : const [],
          button: register ? 'Продолжить' : 'Войти',
          submit: (v) async {
            if (register && v['password'] != v['repeat'])
              throw ApiException('VALIDATION_ERROR', 'Пароли не совпадают');
            await api.setPersistence(false);
            await api.signIn({
              'country': country,
              'phone': v['phone']!.trim(),
              'password': v['password'],
              if (register) 'locale': locale,
            }, register: register);
            registrationInProgress = register;
            try {
              me = await api.request('/me') as Json;
              if (me!['locale'] != locale)
                me =
                    await api.request(
                          '/me',
                          method: 'PATCH',
                          body: {
                            'expected_version': me!['version'],
                            'locale': locale,
                          },
                        )
                        as Json;
            } catch (error, stack) {
              if (register) authPhoneInitial = v['phone']!.trim();
              // A credential response alone must not leave an unprotected local
              // session when profile/bootstrap fails. Server expiry is unchanged.
              await api.forget();
              if (register && mounted)
                success('Аккаунт создан. Войдите, чтобы продолжить.');
              Error.throwWithStackTrace(error, stack);
            }
            registrationInProgress = register || needsProfile(me!);
            authPhoneInitial = '';
            serviceCategories = null;
            draftCategory = null;
            objectId = null;
            executor = me!['active_role'] == 'executor';
            widget.onLocaleChanged?.call(locale);
            sequence = 0;
            TextInput.finishAutofillContext(shouldSave: true);
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
                    onPressed: authSubmitting ? null : () => go('login'),
                    child: const UiText('Уже есть аккаунт? Войти'),
                  ),
                ]
              : [
                  TextButton(
                    style: TextButton.styleFrom(
                      minimumSize: const Size(double.infinity, 52),
                    ),
                    onPressed: authSubmitting ? null : () => go('recovery'),
                    child: const UiText('Нужна помощь со входом?'),
                  ),
                  const Divider(height: 29),
                  const UiText(
                    'Ещё нет аккаунта?',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Color(0xFF627187)),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: OutlinedButton(
                      onPressed: authSubmitting ? null : () => go('register'),
                      child: const UiText('Зарегистрироваться'),
                    ),
                  ),
                  const Notice(
                    'Ваш номер используется как логин. Подтверждение кодом не требуется.',
                    icon: 'lock',
                    margin: const EdgeInsets.only(top: 24),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: Text(
                      '${localize(context, {'KZ': 'Казахстан', 'RU': 'Россия', 'BY': 'Беларусь', 'KG': 'Кыргызстан'}[country]!)} · ${{'ru': 'Русский', 'kk': 'Қазақша', 'sr': 'Српски', 'be': 'Беларуская'}[locale]}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF627187),
                      ),
                    ),
                  ),
                ],
        ),
      ),
      titleOffset: -12,
    );
  }
  bool needsProfile(Json profile) => profile['display_name'] is String &&
      (profile['display_name'] as String).trim().length < 2;

  void finishLocalSetup() {
    if (history.isNotEmpty && history.last.$1 == 'security')
      back();
    else
      go('terms');
  }

  Future<void> completeLocalSetup({String? pin, bool biometry = false, bool passwordOnly = false}) async {
    if (localSetupSubmitting) return;
    final client = api, protection = lock, generation = api.sessionGeneration;
    final owner = me?['id'], setupRoute = route;
    final wasPersistent = client.persistSession;
    bool current() => mounted && identical(_api, client) &&
        client.sessionGeneration == generation && client.authenticated &&
        me?['id'] == owner && route == setupRoute;
    if (!current()) return;
    setState(() => localSetupSubmitting = true);
    try {
      if (!passwordOnly) {
        if (protection == null) throw ApiException('LOCAL_PROTECTION_UNAVAILABLE', 'Используйте вход с номером и паролем');
        if (pin != null) await protection.configure(pin);
        if (!current()) { await protection.clear(); return; }
        if (biometry) {
          try {
            await protection.enableBiometry();
          } catch (_) {
            if (pin == null) rethrow;
            if (current()) success('PIN сохранён. Биометрия недоступна.');
          }
          if (!current()) { await protection.clear(); return; }
        }
      }
      await client.setPersistence(!passwordOnly);
      if (!current()) return;
      localProtected = !passwordOnly;
      setState(() => localSetupSubmitting = false);
      finishLocalSetup();
    } catch (_) {
      if (current() && client.persistSession != wasPersistent) {
        await client.setPersistence(wasPersistent);
      }
      rethrow;
    } finally {
      if (mounted) setState(() => localSetupSubmitting = false);
    }
  }

  Widget lockSetup() => page('Защитите приложение', PinSetup(
    onSave: (pin, bio) => completeLocalSetup(pin: pin, biometry: bio),
    onPassword: () => completeLocalSetup(passwordOnly: true),
  ), titleOffset: -12);
  void leavePinLimit(String target) {
    if (authNavigationBlocked) return;
    ScaffoldMessenger.maybeOf(context)?.removeCurrentSnackBar();
    setState(() {
      history.clear();
      if (target == 'recovery') history.add(('login', null));
      route = target;
      objectId = null;
      authCredentialFailure = false;
      authFormRevision++;
    });
  }

  Future<void> unlockSession({String? pin}) async {
    if (unlockSubmitting) return;
    final client = api, protection = lock, generation = api.sessionGeneration;
    final owner = api.session?['user']?['id'];
    bool current() =>
        mounted &&
        identical(_api, client) &&
        client.sessionGeneration == generation &&
        client.authenticated &&
        identical(lock, protection) &&
        client.session?['user']?['id'] == owner;
    if (!current() || protection == null) return;
    setState(() => unlockSubmitting = true);
    try {
      final valid = pin == null
          ? await protection.unlockBiometry(
              title: localize(context, 'Разблокировка JOBA'),
              cancel: localize(context, 'Отмена'),
            )
          : await protection.unlock(pin);
      if (!current()) return;
      if (!valid) {
        if (pin != null) throw ApiException('PIN_INVALID', 'Неверный PIN');
        return;
      }
      await client.refresh();
      if (!current()) return;
      final profile = await client.request('/me') as Json;
      if (!current()) return;
      if (profile['id'] != owner)
        throw ApiException(
          'SESSION_SUPERSEDED',
          'Сессия изменилась. Повторите вход',
          401,
        );
      setState(() {
        me = profile;
        country = profile['country'];
        locale = profile['locale'] ?? 'ru';
        serviceCategories = null;
        draftCategory = null;
        objectId = null;
        executor = profile['active_role'] == 'executor';
        locked = false;
        registrationInProgress = needsProfile(profile);
        route = registrationInProgress ? 'terms' : 'home';
        history.clear();
      });
      widget.onLocaleChanged?.call(locale);
      connectEvents();
    } catch (e) {
      if (!current()) return;
      if (e is ApiException && e.code == 'PIN_EXHAUSTED') {
        await client.forget();
        if (mounted &&
            identical(_api, client) &&
            client.sessionGeneration == generation + 1 &&
            !client.authenticated) {
          setState(() {
            locked = false;
            route = 'pin-limit';
            history.clear();
          });
        }
        return;
      }
      rethrow;
    } finally {
      if (mounted) setState(() => unlockSubmitting = false);
    }
  }

  Widget unlockScreen() => PopScope(
    canPop: !unlockSubmitting,
    child: Scaffold(backgroundColor: canvas, body: Column(children: [
      Container(height: MediaQuery.paddingOf(context).top, color: Colors.white),
      Expanded(child: UnlockKeypad(
        key: ValueKey('unlock:${api.sessionGeneration}:${api.session?['user']?['id']}'),
        name: api.session?['user']?['display_name'] ?? me?['display_name'] ?? '',
        busy: unlockSubmitting,
        loadLength: () => lock?.pinLength() ?? Future.value(6),
        onPin: (pin) => unlockSession(pin: pin),
        onBiometry: () => unlockSession(),
        onPassword: () => api.forget(),
      )),
      Container(height: MediaQuery.paddingOf(context).bottom, color: Colors.white),
    ])),
  );
  String countryName(String code) => localize(
      context,
      const {
            'KZ': 'Казахстан',
            'KG': 'Кыргызстан',
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
                      'Заказчик пользуется JOBA бесплатно. Подписка нужна только исполнителю.'),
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
                          padding: const EdgeInsets.symmetric(horizontal: 7),
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

  Future<void> nearMe() async {
    final scope=route;
    try {final value=await const MethodChannel('joba.location').invokeMapMethod<String,dynamic>('current');
      if(!mounted||route!=scope)return;
      if(value==null)throw ApiException('GPS_DENIED','Выберите город вручную');
      listingFilters={...listingFilters,'near_lat':((value['latitude'] as num)*100).round()/100,'near_lon':((value['longitude'] as num)*100).round()/100,'radius_km':50};go('map');
    } catch(_){if(mounted)go('gps-denied');}
  }
  Widget locationScreen() => page(
      'Где искать?',
      loaded(
          '/geo/cities',
          (data, reload) => Column(children:[Padding(padding:const EdgeInsets.all(12),child:OutlinedButton(onPressed:()=>act(nearMe),child:const UiText('Рядом со мной'))),Expanded(child:CitySelector(
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
              }))])));
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
                    Flexible(
                        child: Text(
                            '${me?['city'] ?? ''}${(me?['city'] ?? '').isEmpty ? '' : ', '}${countryName(country)}',
                            style:
                                const TextStyle(fontSize: 12, color: muted))),
                    const SizedBox(width: 8),
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
                                  JobaIcon('search', color: navy),
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
              if(!executor) PromotedListings(api:api,placement:'home.promoted.services',filters:{'city':me?['city']??''},onOpen:(type,id)=>go('contractor',id)),
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
                      Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: line, width: .5)),
                          child: JobaAvatar(
                              api: api, name: data['display_name'] ?? '',
                              id: data['avatar_id'], size: 73,
                              backgroundColor: const Color(0xFFE6E1F0),
                              foregroundColor: const Color(0xFF6F608A))),
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
                            Material(
                                color: const Color(0xFFEAF0FC),
                                borderRadius: BorderRadius.circular(7),
                                child: InkWell(
                                    onTap: () => go('roles'),
                                    borderRadius: BorderRadius.circular(7),
                                    child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                        child: Row(children: [
                                          UiText(executor ? 'Исполнитель' : 'Заказчик',
                                              style: const TextStyle(fontSize: 10, height: 1.6, fontWeight: FontWeight.w700, color: primary)),
                                          const SizedBox(width: 4),
                                          const JobaIcon('down', size: 14),
                                        ]))))
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
                    if (executor) JobaMenu([
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
                    if (executor) const SizedBox(height: 16),
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
                      JobaMenuEntry('Платежи и возвраты', 'card', () => go('refunds')),
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
        key: ValueKey('$route:${api.sessionGeneration}:${data['id']}'),
        api: api,
        onBusyChanged: (busy) {
          if (mounted) setState(() => profilePending += busy ? 1 : -1);
        },
        draft:
            profileDraftScope ==
                '$route:${api.base}:${api.sessionGeneration}:${data['id']}'
            ? profileDraft
            : null,
        onDraftChanged: (draft) {
          profileDraft = Json.from(draft);
          profileDraftScope =
              '$route:${api.base}:${api.sessionGeneration}:${data['id']}';
        },
        initial: data,
        onboarding: route == 'onboarding',
        pickAvatar: () => pickUpload('avatar'),
        onSaved: (saved) {
          profileDraft = null;
          profileDraftScope = null;
          me = saved;
          locale = saved['locale'] ?? locale;
          executor = saved['active_role'] == 'executor';
          widget.onLocaleChanged?.call(locale);
          success('Профиль сохранён');
          if (route == 'onboarding') {
            registrationInProgress = false;
            go(executor ? 'services' : 'home');
          } else
            back();
        },
      ),
    ),
    titleOffset: route == 'onboarding' ? -12 : 0,
  );
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
                            'KG': 'Asia/Bishkek',
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

  String compactWindowLabel(Json order) {
    final window = order['time_window'];
    if(window == null) return windowLabel(order);
    final start = DateTime.tryParse('${window['start_date']}');
    final end = DateTime.tryParse('${window['end_date']}');
    if(start == null || end == null) return windowLabel(order);
    final locale = Localizations.localeOf(context).languageCode;
    if(start.year == end.year && start.month == end.month) {
      final last = DateFormat(start.year == DateTime.now().year ? 'd MMMM' : 'd MMMM y', locale).format(end);
      return start.day == end.day ? last : '${start.day}–$last';
    }
    return '${DateFormat.MMMd(locale).format(start)} — ${DateFormat.yMMMd(locale).format(end)}';
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
          decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: line))),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
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
              Container(padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.white, border: Border.all(color: line), borderRadius: BorderRadius.circular(16)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
              const Divider(height: 28, thickness: 1, color: line),
              Text(order['title'],
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700)),
              fact('Стоимость работы',
                  price(offer['amount'], offer['currency'])),
              if(offer['proposed_start_local'] != null)
                fact('Начало', DateFormat('d MMMM, HH:mm', Localizations.localeOf(context).languageCode).format(DateTime.parse(offer['proposed_start_local'])))
              else fact('Когда', windowLabel(order)),
              if(offer['duration_minutes'] != null)
                fact('Длительность', '${offer['duration_minutes']} ${localize(context,'мин')}'),
              Text(
                  '${offer['time_zone'] ?? order['time_window']?['time_zone'] ?? ''} · ${localize(context, 'Версия')} ${order['revision']} · ${offer['version']}',
                  style: const TextStyle(fontSize: 10, color: muted)),
              ])),
              const SizedBox(height: 8),
              const Notice(
                  'Оплату услуги вы согласуете напрямую с исполнителем. JOBA не хранит и не переводит эти деньги.',
                  icon: 'info', warning: true),
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
  Future<void> submitCompletion(Json order, VoidCallback reload) async {
    final photos = <String>[];
    final sent = await Navigator.push<bool>(context, MaterialPageRoute(builder: (screenContext) =>
        StatefulBuilder(builder: (context, refresh) => Scaffold(
            backgroundColor: canvas,
            appBar: AppBar(title: const UiText('Результат работы')),
            body: ActionForm(
                stickySubmit: true,
                before: [UiHeading('Покажите результат', '${order['title']}')],
                fields: const [InputSpec('note', 'Сообщение заказчику', required: false, multiline: true,
                    hint: 'Что выполнено и что нужно проверить')],
                afterFields: [
                  for(final id in photos) Row(children: [
                    Expanded(child: SizedBox(height: 120, child: PrivatePhoto(api: api, id: id))),
                    IconButton(tooltip: localize(context, 'Удалить фото'), icon: const JobaIcon('close'),
                        onPressed: () => refresh(() => photos.remove(id))),
                  ]),
                  OutlinedButton.icon(onPressed: photos.length >= 8 ? null : () async {
                    final upload = await pickUpload('order');
                    if(upload != null && context.mounted) refresh(() => photos.add(upload['id']));
                  }, icon: const JobaIcon('camera'), label: const UiText('Добавить фото результата')),
                ],
                button: 'Отправить результат',
                submit: (values) async {
                  await api.request('/orders/${order['id']}/request-completion', method: 'POST', body: {
                    'expected_version': order['version'], 'note': values['note'] ?? '', 'upload_ids': photos,
                  });
                  if(screenContext.mounted) Navigator.pop(screenContext, true);
                })))));
    if(sent == true && mounted) reload();
  }
  Widget completionScreen() => page(
      'Результат работы',
      loaded('/orders/$objectId', (data, reload) {
        final order = data as Json;
        final allowed = order['status'] == 'completion_requested' && order['owner'] == me?['id'];
        final person = order['executor'] as Json?;
        final photos = order['completion_upload_ids'] as List? ?? [];
        return Column(children: [
          Expanded(child: listBody([
            Row(children: [
              JobaBadge(status(order), background: const Color(0xFFFFF4D4), foreground: const Color(0xFF705000)),
              const Spacer(),
              Text('№ ${order['id'].toString().substring(0, order['id'].toString().length.clamp(0,8))}',
                  style: const TextStyle(fontSize: 10, color: muted)),
            ]),
            const SizedBox(height: 16),
            Text(order['title'], style: const TextStyle(fontSize: 28, height: 1.25, letterSpacing: -.9, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('${person?['display_name'] ?? localize(context, 'Исполнитель')} ${localize(context, 'отметил работу выполненной.')}',
                style: const TextStyle(fontSize: 12, color: muted, height: 1.5)),
            if(photos.isNotEmpty) ...[
              const SizedBox(height: 20),
              for(final id in photos) Padding(padding: const EdgeInsets.only(bottom: 12),
                  child: ClipRRect(borderRadius: BorderRadius.circular(16),
                      child: PrivatePhoto(api: api, id: id, height: null, gallery: photos.cast<String>()))),
            ],
            if('${order['completion_note'] ?? ''}'.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.white, border: Border.all(color: line), borderRadius: BorderRadius.circular(16)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      JobaAvatar(api: api, name: person?['display_name'] ?? '', id: person?['avatar_id'], size: 42),
                      const SizedBox(width: 10),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const UiText('Сообщение исполнителя', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                        if(order['completion_requested_at'] != null) Text(dateLabel(order['completion_requested_at']),
                            style: const TextStyle(fontSize: 10, color: muted)),
                      ])),
                    ]),
                    const SizedBox(height: 12),
                    Text(order['completion_note'], style: const TextStyle(fontSize: 12, height: 1.5)),
                  ])),
            ],
            const SizedBox(height: 16),
            const UiText('Проверьте работу перед подтверждением. Если что-то осталось, запросите доработку.',
                style: TextStyle(fontSize: 12, color: muted, height: 1.5)),
            if (!allowed) const Notice('Состояние заказа изменилось.'),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: allowed && !actionBusy ? () => go('rework', order['id']) : null,
                child: const UiText('Нужна доработка')),
          ])),
          stickyActions([
            FilledButton(onPressed: allowed && !actionBusy ? () => act(() async {
              await api.request('/orders/${order['id']}/confirm-completion', method: 'POST', body: {'expected_version': order['version']});
              go('review', order['id']);
            }) : null, child: const UiText('Принять работу'))
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
              final result = await api.request('/orders/${order['id']}/$command',
                  method: 'POST',
                  body: {
                    'expected_version': order['version'],
                    'reason':
                        '${localize(context, reasons[cancellationReason]!)}. ${fields['comment'] ?? ''}'
                  });
              go(command == 'cancel' ? 'order' : 'cancel-pending',
                  command == 'cancel' ? order['id'] : result['id']);
            });
      }));
  Widget orderScreen() => page(
      route == 'publish' ? 'Проверьте заказ' : 'Детали заказа',
      loaded('/orders/$objectId', (data, reload) {
        final o = data as Json;
        final owner = o['owner'] == me!['id'],
            assigned = o['executor_id'] == me!['id'];
        final canOffer = !owner && o['status'] == 'open';
        return Column(children: [Expanded(child: listBody([
          OrderOverview(api: api, order: o, stateLabel: status(o),
              priceLabel: price(o['budget_amount'], o['currency']), timeLabel: compactWindowLabel(o),
              onReport: () => reportObject(o['id'], 'order')),
          if ((owner || assigned) && o['revision_reason'] != null) ...[
            const Heading('Комментарий исполнителю'),
            Text('${o['revision_reason']}'),
            for (final id in o['revision_upload_ids'] as List? ?? []) PrivatePhoto(api:api,id:id),
          ],
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
          if (owner && o['status'] == 'open')
            button('Список откликов', () => go('offers', o['id'])),
          if (assigned && o['status'] == 'assigned')
            button('Начать работу', () => orderCommand(o, 'start', reload)),
          if (assigned && o['status'] == 'in_progress')
            button('Запросить завершение',
                () => submitCompletion(o, reload)),
          if (owner && o['status'] == 'completion_requested') ...[
            button('Проверить результат', () => go('complete', o['id'])),
            button('Запросить доработку',
                () => go('rework',o['id']),
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
            button('Согласовать новые условия', () => go('amendment',o['id']),
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
        ])),
          if(canOffer) stickyActions([FilledButton(onPressed: () => go('offer', o['id']), child: const UiText('Откликнуться'))]),
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

  void editOffer(Json offer) => Navigator.push(context,MaterialPageRoute<void>(builder:(screenContext)=>Scaffold(
      backgroundColor:canvas,appBar:AppBar(title:const UiText('Редактировать отклик')),
      body:ApiView(load:()=>api.request('/offers/${offer['id']}'),builder:(context,current,reload)=>OfferEditor(
          api:api,order:Json.from(current['order']),offer:Json.from(current),onSaved:(saved){
            if(screenContext.mounted)Navigator.pop(screenContext);
            if(mounted)setState(()=>revision++);
          })))));

  Widget offerScreen() => page('Откликнуться',loaded('/orders/$objectId',(order,reload)=>OfferEditor(
      api:api,order:Json.from(order),onSaved:(offer)=>go('offer-sent',offer['id']))));
  Widget offersScreen() => ApiView(
      key:ValueKey('offers:$objectId:$revision'),
      load:()=>Future.wait([api.request('/orders/$objectId'),api.request('/orders/$objectId/offers')]),
      builder:(context,data,reload)=>page('${localize(context,'Отклики')} · ${items(data[1]).length}',
          OfferList(api:api,order:Json.from(data[0]),offers:items(data[1]),onGo:(route,id)=>go(route,id))));
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
                  }))), titleOffset:-12, actions:[IconButton(tooltip:localize(context,'Поделиться'),icon:const JobaIcon('share'),onPressed:()=>act(() async {
                    final profile=await api.request('/contractors/$objectId');
                    final shown=await shareInvitation('JOBA · ${profile['display_name']}\n${profile['title']} · ${profile['city'] ?? ''}\n${profile['description'] ?? ''}');
                    if(!shown && mounted) success('Профиль скопирован');
                  }))]);
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
                  if(p!=null) button('Зона обслуживания на карте',()=>go('service-area'),outline:true),
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
                        'KG': 'KGS',
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
                              go('profile-pending');
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
          onSent: (id) => go('invited',id)));

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
  Widget chatScreen(bool support) {
    if (support) return page('Поддержка JOBA', messageThread(true));
    return ApiView(
        key: ValueKey('conversation:$objectId'),
        load: () => api.request('/conversations/$objectId'),
        builder: (context, r, reload) {
          final peer = r['peer'] as Json?;
          final name = '${peer?['display_name'] ?? 'Участник заказа'}';
          return page(name,
              Column(children: [
                if (r['order_id'] != null)
                  Material(color: Colors.white, child: InkWell(
                      onTap: () => go('order', r['order_id']),
                      child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                          child: Row(children: [
                            const JobaIcon('brief', color: primary),
                            const SizedBox(width: 10),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              UiText('${r['order_title'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                              const SizedBox(height: 2),
                              UiText([if(r['order_status'] != null) status({'status': r['order_status']}),
                                if(r['order_amount'] != null) money(r['order_amount'], r['currency'] ?? 'KZT')].join(' · '),
                                  style: const TextStyle(fontSize: 10, color: muted)),
                            ])),
                            const JobaIcon('right', size: 18),
                          ])))),
                Expanded(child: r['blocked'] == true
                    ? WorkStateScreen(api: api, mode: 'frozen-chat', id: objectId!,
                        onGo: (r, id) => go(r, id), pickPhoto: () => pickUpload('order'))
                    : messageThread(false)),
              ]),
              toolbarHeight: 64, leadingWidth: 58,
              titleWidget: Row(children: [
                Container(width: 42, height: 42,
                    decoration: BoxDecoration(color: const Color(0xFFDDEFE9), borderRadius: BorderRadius.circular(14)),
                    clipBehavior: Clip.antiAlias,
                    child: peer?['avatar_id'] != null
                        ? PrivatePhoto(api: api, id: peer!['avatar_id'])
                        : Center(child: Text(name.trim().isEmpty ? '?' : name.trim().substring(0, 1),
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF487E70))))),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  UiText(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  const UiText('Участник заказа', style: TextStyle(fontSize: 10, color: muted, fontWeight: FontWeight.w400)),
                ])),
              ]),
              actions: [PopupMenuButton<String>(
                  tooltip: localize(context, 'Действия чата'),
                  icon: const JobaIcon('dots'),
                  onSelected: (value) => value == 'report'
                      ? reportObject(objectId!, 'conversation') : go('support-new'),
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'report', child: UiText(localize(context, 'Пожаловаться'))),
                    PopupMenuItem(value: 'support', child: UiText(localize(context, 'Поддержка'))),
                  ])]);
        });
  }
  Widget messageThread(bool support) => MessageThread(
          key: ValueKey('thread:$objectId'),
          api: api,
          path: support
              ? '/support/threads/$objectId/messages'
              : '/conversations/$objectId/messages',
          owner: me!['id'],
          conversationId: support ? null : objectId,
          revision: revision);
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

  Widget customerAccessScreen() => page(
      'JOBA для заказчика',
      listBody([
        const UiHeading('Для заказчика бесплатно'),
        const Notice(
            'Поиск исполнителей, публикация заказов и выбор исполнителя доступны без подписки.'),
        button('Найти исполнителя', () => go('catalog')),
        button('Мои заказы', () => go('orders'), outline: true),
      ]));

  Widget notificationsScreen() {
    final client = api, generation = api.sessionGeneration;
    final owner = api.session?['user']?['id'];
    final scope = '${identityHashCode(client)}:$generation:$owner:$revision';
    if (notificationScope != scope) {
      notificationScope = scope;
      notificationReadBefore = null;
    }
    bool current() =>
        mounted &&
        identical(_api, client) &&
        client.sessionGeneration == generation &&
        client.authenticated &&
        client.session?['user']?['id'] == owner &&
        route == 'notifications';
    Future<void> perform(Future<void> Function() job) => act(() async {
      try {
        await job();
      } catch (_) {
        if (current()) rethrow;
      }
    });
    return page(
      'Уведомления',
      PagedList(
        key: ValueKey('notifications:$revision'),
        api: client,
        path: '/me/notifications',
        onMetadata: (meta) {
          if (!current() || notificationScope != scope) return;
          final value = meta['read_before'];
          if (value is String && notificationReadBefore == null) {
            notificationReadBefore = value;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (current() && notificationScope == scope) setState(() {});
            });
          }
        },
        tile: (r) => DataCard(
          r['title'] ?? eventTitles[r['type']] ?? 'Новое событие JOBA',
          subtitle: '${r['body'] ?? ''}',
          status: r['read'] == true ? 'Прочитано' : 'Новое',
          onTap: () => perform(() async {
            if (!current()) return;
            await client.request(
              '/me/notifications/${r['id']}/read',
              method: 'POST',
            );
            if (!current()) return;
            setState(() => r['read'] = true);
            if (r['deep_link'] is Map) {
              await openCampaignLink(Map<String, dynamic>.from(r['deep_link']));
              return;
            }
            final type = '${r['type']}';
            if (type == 'message.created')
              go('chat', r['target_id']);
            else if (type == 'support.message.created')
              go('support-chat', r['target_id']);
            else if (type.startsWith('order.') || type == 'offer.created')
              go('order', r['target_id']);
            else if (type == 'privacy.export.ready')
              go('privacy');
            else if (type == 'case.message.created' || type == 'case.updated')
              go('case', r['target_id']);
            else if (type == 'verification.updated' ||
                type == 'content.moderated') {
              await refreshIdentity();
              if (current())
                go(type == 'verification.updated' ? 'verification' : 'account');
            } else if (type == 'invite.created')
              go('invitations');
            else if (type.startsWith('amendment.') ||
                type.startsWith('cancel_request.'))
              go('change-requests');
            else
              setState(() => revision++);
          }),
        ),
      ),
      actions: [
        IconButton(
          tooltip: localize(context, 'Прочитать все'),
          icon: const Icon(Icons.done_all),
          onPressed: actionBusy || notificationReadBefore == null
              ? null
              : () => perform(() async {
                  if (!current()) return;
                  final before = notificationReadBefore;
                  if (before == null) return;
                  await client.request(
                    '/me/notifications/read-all',
                    method: 'POST',
                    body: {'before': before},
                  );
                  if (current()) setState(() => revision++);
                }),
        ),
      ],
      nav: true,
    );
  }
  Widget accessScreen() => page(
      route == 'access' ? 'Доступ к JOBA' : 'Мой доступ',
      ApiView(
          key: ValueKey('access:$route:$revision'),
          load: () => Future.wait([
                api.request('/me/entitlements'),
                api.request('/me/monetization-config'),
                api.request('/me/subscriptions')
              ]),
          builder: (c, data, reload) => ExecutorAccess(
              choosing: route == 'access', grants: items(data[0]),
              config: Json.from(data[1]), subscriptions: items(data[2]),
              now: () => api.clock.now,
              onGo: (r, id) => go(r, id))), titleOffset: -12);
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
                      onTap: r['type'] == 'export'
                          ? () => go('export-pending', r['id'])
                          : () => go('delete-scheduled',r['id']),
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
                        if (['requested', 'awaiting_retention_policy','scheduled','awaiting_resolution']
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
                button('Экспортировать данные', () => go('export')),
                button(
                    'Удалить аккаунт', () => go('delete-account'),
                    outline: true),
                button('Правовые документы', () => go('legal'), outline: true),
                button('Хранение данных',()=>go('legal-holds'),outline:true),
                button('Согласия и документы', () => go('consents'),
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
                    final request = await api.request('/me/privacy-requests',
                        method: 'POST', body: {...v, 'type': type}) as Json;
                    if (c.mounted) Navigator.pop(c);
                    if (type == 'export') {
                      go('export-pending', request['id']);
                      return;
                    }
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
                  JobaMenuEntry('Биометрия', 'face', () => go('biometric'),
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
                          () => go('revoke-session', record['family']),
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
                          decoration: const BoxDecoration(
                              color: Colors.white,
                              border: Border(top: BorderSide(color: line))),
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
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
          'KG': 'Кыргызстан',
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
  Future<void> openCampaignLink(Json link) async {
    final client = api, generation = api.sessionGeneration;
    final owner = api.session?['user']?['id'], origin = route;
    bool current() =>
        mounted &&
        identical(_api, client) &&
        client.sessionGeneration == generation &&
        client.authenticated &&
        client.session?['user']?['id'] == owner &&
        route == origin;
    if (!current()) return;
    final target = link['id'];
    if (target != null &&
        (target is! String ||
            !RegExp(
              r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
            ).hasMatch(target)))
      throw ApiException('NOT_FOUND', 'Объект недоступен');
    switch (link['route']) {
      case 'order':
        if (target == null) break;
        go('order', target);
        return;
      case 'offer':
        if (target == null) break;
        final offer = await client.request('/offers/$target');
        if (current()) go('order', offer['order_id']);
        return;
      case 'conversation':
        if (target == null) break;
        go('chat', target);
        return;
      case 'profile':
        go(target == null ? 'account' : 'contractor', target);
        return;
      case 'notification':
        go('notifications');
        return;
      case 'subscription':
        go(target == null ? 'my-access' : 'manage-subscription', target);
        return;
      case 'help':
        go('support');
        return;
    }
    throw ApiException('NOT_FOUND', 'Объект недоступен');
  }
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
                              'KG': 'Asia/Bishkek',
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
      MaterialPageRoute<void>(builder: (c) => ReferralCodeScreen(
          api: api, onAccepted: () {
            if (mounted) {
              setState(() => revision++);
              success('Код приглашения принят');
            }
          })));
  Widget referralRulesScreen() => page(
      'Условия бонусов',
      loaded('/me/referrals', (data, reload) => ReferralRulesContent(
          campaigns: (data['campaigns'] as List).cast<Json>())),
      titleOffset: -11);
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
              decoration: const ReferralHeroDecoration(),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    UiText(localize(context, 'Вместе удобнее').toUpperCase(),
                        style: const TextStyle(
                            color: Color(0xFFC5D3EB),
                            fontSize: 12,
                            height: 1.5,
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
                          style: IconButton.styleFrom(
                            backgroundColor: const Color(0xFFF3F5FA),
                            fixedSize: const Size(48, 48),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          tooltip: localize(context, 'Скопировать код'),
                          onPressed: () => act(() async {
                                await Clipboard.setData(
                                    ClipboardData(text: data['code']));
                                success('Код скопирован');
                              }),
                          icon: const JobaIcon('file'))
                    ]),
                    const SizedBox(height: 16),
                    FilledButton(
                        onPressed: actionBusy ? null : () => act(() async {
                              final shown = await shareInvitation(
                                  '${localize(context, 'Код приглашения')} JOBA: ${data['code']}');
                              if (!shown && mounted) success('Код скопирован');
                            }),
                        child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          JobaIcon('share'), SizedBox(width: 10),
                          Flexible(child: UiText('Поделиться приглашением', textAlign: TextAlign.center))
                        ]))
                  ])),
          const SizedBox(height: 22),
          const UiText('Ваш прогресс',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: line),
                  borderRadius: BorderRadius.circular(16)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(child: Text(
                        '${localize(context, 'Приглашения')}: ${attributions.length}',
                        style: const TextStyle(fontWeight: FontWeight.w700))),
                      const SizedBox(width: 8),
                      if (attributions.isNotEmpty) Flexible(child: Align(alignment: Alignment.centerRight, child: JobaBadge(
                        qualified > 0 ? 'Выполнены условия' : 'Ожидает условия',
                        background: qualified > 0 ? const Color(0xFFEAF5EE) : const Color(0xFFFFF4D1),
                        foreground: qualified > 0 ? const Color(0xFF327453) : const Color(0xFF785800)))),
                    ]),
                    const SizedBox(height: 12),
                    Text(
                        '${localize(context, 'Выполнены условия')}: $qualified\n${localize(context, 'Ожидает условия')}: ${attributions.length - qualified}',
                        style: const TextStyle(color: muted, fontSize: 12, height: 1.5))
                  ])),
          const SizedBox(height: 16),
          for (final reward in rewards)
            ReferralRewardCard(now: () => api.clock.now,
                key: ValueKey('referral-reward:${reward['id']}'),
                reward: reward,
                onActivate: () async {
                  await api.request('/me/referral-rewards/${reward['id']}/redeem', method: 'POST');
                  reload();
                }),
          JobaMenu([
            JobaMenuEntry(
                'Как начисляются бонусы', 'info', () => go('referral-rules'),
                subtitle: 'Условия, сроки и ограничения', minHeight: 81),
            JobaMenuEntry('У меня есть код', 'gift', enterReferralCode,
                subtitle: 'Ввести приглашение друга')
          ])
        ]);
      }), titleOffset: -11);
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
                        go('portfolio-pending', project['id']);
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
      objectId == null ? 'Новый проект' : 'Редактировать проект',
      PortfolioEditor(key: ValueKey('project:$objectId:$revision'), api: api,
          id: objectId, pickPhoto: () => pickUpload('portfolio'),
          onGo: (route, id) => go(route, id)), titleOffset: -12);
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
          onAppeal: (session) => Navigator.push(context, MaterialPageRoute(builder: (c) => Scaffold(
              backgroundColor: canvas, appBar: AppBar(title: const UiText('Обжаловать решение')),
              body: SupportNew(api: api, executor: executor, initialTopic: 'account',
                initialText: 'Прошу пересмотреть решение по проверке документа № ${session['id']}.\nПричина отказа: ${session['reason'] ?? ''}\n',
                pickUpload: () => pickUpload('chat'),
                onCreated: (id) {Navigator.pop(c); go('support-chat', id);})))),
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
                  onReload: reload,
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
            final canContinue = requiredDocuments.any((d) => ['terms', 'terms_of_use'].contains(d['type'])) &&
                requiredDocuments.any((d) => ['privacy', 'privacy_policy'].contains(d['type'])) &&
                requiredDocuments.every(accepted);
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
  Widget promotionScreen() => page(
      'Продвинуть объявление',
      loaded(
          '/me/boosts',
          (data, reload) => listBody([
                const UiHeading('Больше внимания к вашей работе'),
                const Notice(
                    'Оплата продвижений станет доступна после подключения платёжной системы.'),
                button('Мои продвижения', () => go('promotion-history'), outline: true),
                for (final r in items(data))
                  DataCard('Размещение',
                      translateTitle: true,
                      status: status(r),
                      subtitle: '${r['starts_at']} — ${r['ends_at']}',
                      onTap: () => go('promotion-pending', r['id'])),
                button('Поддержка', () => go('support'), outline: true),
              ])));
}

class MessageThread extends StatefulWidget {
  final CommerceGateway commerceGateway;
  final JobaApi api;
  final String path, owner;
  final String? capability, conversationId;
  final int revision;
  const MessageThread(
      {this.commerceGateway=const DisconnectedCommerceGateway(), required this.api,
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
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
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
                      final bubble = GestureDetector(
                          onLongPress: () => messageMenu(m),
                          child: Align(
                              alignment: own
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: Container(
                                  constraints:
                                      const BoxConstraints(maxWidth: 312),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                  margin: const EdgeInsets.only(bottom: 12),
                                  decoration: BoxDecoration(
                                      color: own ? primary : Colors.white,
                                      border: own ? null : Border.all(color: line),
                                      borderRadius: BorderRadius.only(
                                          topLeft: const Radius.circular(16),
                                          topRight: const Radius.circular(16),
                                          bottomLeft: Radius.circular(own ? 16 : 4),
                                          bottomRight: Radius.circular(own ? 4 : 16))),
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
                                                : m['text'] ?? '',
                                            style: TextStyle(fontSize: 13, height: 20/13, color: own ? Colors.white : navy)),
                                        for (final id
                                            in (m['upload_ids'] as List? ?? []))
                                          AttachmentView(
                                              api: widget.api, id: id),
                                        Padding(padding: const EdgeInsets.only(top: 4),
                                            child: Text([
                                              if(DateTime.tryParse('${m['created_at']}') case final DateTime created)
                                                DateFormat.Hm(Localizations.localeOf(context).languageCode).format(created.toLocal()),
                                              if(own) localize(context, const {
                                                'sent':'Отправлено','delivered':'Доставлено','read':'Прочитано','quarantined':'На проверке'
                                              }[m['delivery_state']] ?? 'Отправлено'),
                                            ].join(' · '), style: TextStyle(fontSize: 9, height: 13/9,
                                                color: own ? const Color(0xFFD6E4FF) : muted))),
                                      ]))));
                      final date = DateTime.tryParse('${m['created_at']}')?.toLocal();
                      final previous = i - (moreHistory ? 1 : 0) - 1;
                      final before = previous < 0 ? null : DateTime.tryParse('${messages[previous]['created_at']}')?.toLocal();
                      final showDate = date != null && (before == null || date.year != before.year || date.month != before.month || date.day != before.day);
                      return Column(children: [
                        if(showDate) Padding(padding: const EdgeInsets.only(bottom: 20, top: 4),
                            child: Text(DateFormat.yMMMMd(Localizations.localeOf(context).languageCode).format(date),
                                style: const TextStyle(fontSize: 10, color: muted))),
                        bubble,
                      ]);
                    })),
        SafeArea(
            top: false,
            child: Container(
                decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: line))),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
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
                            : const JobaIcon('plus')),
                  Expanded(
                      child: TextField(
                          controller: text,
                          minLines: 1,
                          maxLines: 4,
                          enabled: !sending,
                          onChanged: (_) => pendingId = null,
                          decoration: InputDecoration(
                              hintText: localize(context, 'Сообщение'),
                              filled: true, fillColor: canvas,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: line))))),
                  const SizedBox(width: 8),
                  IconButton.filled(
                      style: IconButton.styleFrom(backgroundColor: primary, minimumSize: const Size(48,48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                      tooltip: localize(context, 'Отправить'),
                      onPressed: sending ? null : send,
                      icon: sending
                          ? const CircularProgressIndicator()
                          : const JobaIcon('send', color: Colors.white)),
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
