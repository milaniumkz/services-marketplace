import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/api.dart';
import '../core/commerce_gateway.dart';
import '../core/currency.dart';
import '../core/design_states.dart';
import '../core/design_icons.dart';
import '../core/design_widgets.dart';
import '../core/l10n.dart';
import '../core/theme.dart';
import '../core/widgets.dart';

class CommerceStateScreen extends StatefulWidget {
  final JobaApi api;
  final String mode;
  final String? id;
  final CommerceGateway gateway;
  final void Function(String route, String? id) onGo;
  const CommerceStateScreen(
      {required this.api,
      required this.mode,
      required this.onGo,
      this.id,
      this.gateway = const DisconnectedCommerceGateway(),
      super.key});
  @override
  State<CommerceStateScreen> createState() => _CommerceStateScreenState();
}

class _CommerceStateScreenState extends State<CommerceStateScreen> {
  bool busy = false;
  String? acceptedOffer;
  Object? error;
  String? selected;
  Timer? _ticker;
  @override
  void initState() {
    super.initState();
    if (['reward', 'reward-granted', 'reward-pending', 'manage-subscription']
        .contains(widget.mode)) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  bool Function() sessionGuard() {
    final api = widget.api;
    final generation = api.sessionGeneration;
    final owner = api.session?['user']?['id'];
    return () =>
        mounted &&
        identical(widget.api, api) &&
        !api.disposed &&
        api.authenticated &&
        api.sessionGeneration == generation &&
        api.session?['user']?['id'] == owner;
  }

  Future<void> run(Future<void> Function() job) async {
    if (busy) return;
    final current = sessionGuard();
    if (!current()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await job();
    } catch (e) {
      if (current()) setState(() => error = e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> purchase(Json offer) => run(() async {
        final api = widget.api;
        final current = sessionGuard();
        if (!current()) return;
        final receipt = await widget.gateway.purchase(offer);
        if (!current()) return;
        final result = await api.request('/billing/verify-purchase',
            method: 'POST', body: receipt);
        if (!current()) return;
        widget.onGo(result['pending'] == true ? 'payment-pending' : 'my-access',
            result['check']?['id']);
      });

  Widget panel(String icon, String title, String message, String label,
          VoidCallback action,
          {String? secondary, VoidCallback? onSecondary}) =>
      ListView(padding: const EdgeInsets.all(20), children: [
        JobaStatePanel(
            icon: icon,
            title: title,
            message: message,
            primaryLabel: label,
            onPrimary: action,
            busy: busy,
            secondaryLabel: secondary,
            onSecondary: onSecondary),
        if (error != null) Notice(errorText(context, error!), error: true)
      ]);
  Future<void> playReward() => run(() async {
        final api = widget.api;
        final gateway = widget.gateway;
        final current = sessionGuard();
        try {
          final session = await api.request('/ads/reward-sessions',
              method: 'POST', body: {'placement': 'access'});
          if (!current()) return;
          final completed = await gateway.playReward(session);
          if (!current()) return;
          await api.request('/ads/reward-sessions/${session['id']}/outcome',
              method: 'POST',
              body: {'outcome': completed ? 'completed' : 'no_fill'});
          if (current())
            widget.onGo(
                completed ? 'reward-pending' : 'reward-nofill', session['id']);
        } on ApiException catch (e) {
          if (['REWARDED_DISABLED', 'PROVIDER_UNAVAILABLE'].contains(e.code)) {
            if (current()) widget.onGo('reward-nofill', null);
            return;
          }
          rethrow;
        }
      });
  Widget rewardOffer(Json config, VoidCallback reload) {
    final policy = config['reward_policy'] as Json?;
    final usage = config['reward_usage'] as Json?;
    final seconds = policy?['duration_seconds'] as num?;
    final credits = policy?['credits'] as num?;
    final cooldown = DateTime.tryParse('${usage?['cooldown_until']}');
    final remaining = usage?['remaining_today'] as num?;
    final enabled = config['rewarded_access_enabled'] == true &&
        config['reward_provider_ready'] == true &&
        policy != null &&
        ((policy['kind'] == 'duration' && seconds != null && seconds > 0) ||
            (policy['kind'] == 'action_credits' &&
                credits != null &&
                credits > 0)) &&
        (remaining == null || remaining > 0) &&
        (cooldown == null || !cooldown.isAfter(widget.api.clock.now));
    final hours = seconds == null ? 0 : seconds ~/ 3600;
    final hourWord = hours % 10 == 1 && hours % 100 != 11
        ? 'час'
        : hours % 10 >= 2 &&
                hours % 10 <= 4 &&
                (hours % 100 < 12 || hours % 100 > 14)
            ? 'часа'
            : 'часов';
    final duration = seconds == null
        ? 'Не задан'
        : seconds % 3600 == 0
            ? '$hours ${localize(context, hourWord)}'
            : '${(seconds / 60).ceil()} мин';
    return Column(children: [
      Expanded(
          child: ListView(padding: const EdgeInsets.all(20), children: [
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 22),
            child: Column(children: [
              Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                      color: const Color(0xFFFFF4D5),
                      borderRadius: BorderRadius.circular(24)),
                  child: const Center(
                      child: JobaIcon('play',
                          size: 34, color: Color(0xFF8D6510)))),
              const SizedBox(height: 20),
              UiText(
                  policy == null
                      ? 'Один просмотр.\nБольше возможностей.'
                      : policy['kind'] == 'duration'
                          ? 'Один просмотр.\n$duration доступа.'
                          : 'Один просмотр.\n${credits ?? '—'} действий.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 28,
                      height: 1.25,
                      letterSpacing: -.9,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              const UiText(
                  'Доступ исполнителю начнётся после подтверждения просмотра рекламной сетью.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, height: 1.55, color: muted)),
            ])),
        Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: line),
                borderRadius: BorderRadius.circular(16)),
            child: Column(children: [
              checkoutFact(
                  'Награда',
                  policy?['kind'] == 'action_credits'
                      ? '${credits ?? '—'} ${localize(context, 'действий')}'
                      : localize(context, 'Доступ исполнителя')),
              checkoutFact('Срок', localize(context, duration)),
              checkoutFact(
                  'Доступно сегодня',
                  usage == null
                      ? '—'
                      : '${usage['remaining_today']} / ${usage['daily_cap']}',
                  last: true),
            ])),
        const SizedBox(height: 8),
        Notice(
            config['rewarded_access_enabled'] != true
                ? 'Рекламный доступ сейчас отключён. Награда не начислялась.'
                : config['reward_provider_ready'] != true
                    ? 'Рекламная сеть ещё не подключена.'
                    : remaining != null && remaining <= 0
                        ? 'Дневной лимит просмотров достигнут.'
                        : cooldown != null &&
                                cooldown.isAfter(widget.api.clock.now)
                            ? 'Перед следующим просмотром нужна пауза. Обновите условия позже.'
                            : 'Доступ выдаётся только после подтверждения рекламной сети.',
            warning: true,
            icon: 'info'),
        const UiText(
            'Можно отказаться. Просмотр не означает согласие на персонализацию рекламы.',
            style: TextStyle(fontSize: 12, height: 1.5, color: muted)),
        const SizedBox(height: 16),
        TextButton(
            onPressed: () => widget.onGo('access', null),
            child: const UiText('Выбрать подписку')),
        if (!enabled)
          TextButton(
              onPressed: busy ? null : reload,
              child: const UiText('Обновить условия')),
        if (error != null) Notice(errorText(context, error!), error: true),
      ])),
      Container(
          decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: line))),
          child: SafeArea(
              top: false,
              child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                  child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                          onPressed: enabled && !busy ? playReward : null,
                          child: const UiText('Посмотреть ролик')))))),
    ]);
  }

  String periodLabel(dynamic period) => switch (period) {
        'month' || 'P1M' => '1 месяц',
        'year' || 'P1Y' => '1 год',
        'week' || 'P1W' => '1 неделя',
        'days' => '30 дней',
        null => 'Уточняется у провайдера',
        _ => '$period',
      };

  Widget checkoutFact(String label, String value, {bool last = false}) =>
      Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
              border:
                  last ? null : const Border(bottom: BorderSide(color: line))),
          child: Row(children: [
            Expanded(
                child: UiText(label,
                    style: const TextStyle(fontSize: 12, color: navy))),
            const SizedBox(width: 12),
            Expanded(
                child: UiText(value,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        fontWeight: FontWeight.w700))),
          ]));

  String money(Json? r) => r?['amount_minor'] is int
      ? formatMoney(r!['amount_minor'], r['currency'],
          Localizations.localeOf(context).languageCode)
      : '—';
  @override
  Widget build(BuildContext context) {
    final mode = widget.mode;
    if (mode == 'restore')
      return panel(
          'refresh',
          'Проверим ваши покупки',
          'Восстановление не создаёт новое списание. Провайдер проверит принадлежность покупки этому аккаунту.',
          'Восстановить покупку',
          () => run(() async {
                final api = widget.api;
                final current = sessionGuard();
                final receipts = await widget.gateway.restore();
                if (!current()) return;
                String? pendingCheck;
                for (final r in receipts) {
                  if (!current()) return;
                  final result = await api.request('/billing/restore',
                      method: 'POST', body: r);
                  if (!current()) return;
                  if (result['pending'] == true) {
                    pendingCheck ??= result['check']?['id'];
                  }
                }
                if (current())
                  widget.onGo(
                      pendingCheck == null ? 'my-access' : 'payment-pending',
                      pendingCheck);
              }),
          secondary: 'Мой доступ',
          onSecondary: () => widget.onGo('my-access', null));
    if (mode == 'payment-pending')
      return ApiView(
          load: () => widget.api.request('/me/purchase-checks/${widget.id}'),
          builder: (context, r, reload) => panel(
              'clock',
              r['status'] == 'confirmed'
                  ? 'Доступ подтверждён'
                  : 'Ждём подтверждения',
              r['status'] == 'confirmed'
                  ? 'Право проверено сервером.'
                  : 'Право ещё не подтверждено сервером. Повторная оплата не нужна.',
              r['status'] == 'confirmed' ? 'Мой доступ' : 'Проверить статус',
              r['status'] == 'confirmed'
                  ? () => widget.onGo('my-access', null)
                  : reload));
    if (mode == 'reward-granted' || mode == 'reward-pending')
      return ApiView(
          load: () => widget.api.request('/ads/reward-sessions/${widget.id}'),
          builder: (context, r, reload) {
            final grant = r['grant'];
            final expired = r['status'] == 'granted';
            final valid = r['status'] == 'granted' &&
                grant != null &&
                DateTime.tryParse('${grant['valid_until']}')
                        ?.isAfter(widget.api.clock.now) ==
                    true &&
                (grant['balance'] == null || grant['balance'] > 0);
            return panel(
                valid ? 'check' : 'clock',
                valid
                    ? 'Доступ активен'
                    : expired
                        ? 'Срок доступа завершён'
                        : r['status'] == 'no_fill'
                            ? 'Сейчас нет ролика'
                            : 'Проверяем награду',
                valid
                    ? 'Подтверждено сервером. Срок доступа: ${grant['valid_until']}.'
                    : expired
                        ? 'Проверьте доступные способы продолжения в разделе «Мой доступ».'
                        : r['status'] == 'no_fill'
                            ? 'Просмотр не начался, награда не начислена.'
                            : 'Награда ещё не подтверждена. Повторно смотреть рекламу не нужно.',
                valid
                    ? 'Найти заказ'
                    : expired
                        ? 'Мой доступ'
                        : 'Проверить статус',
                valid
                    ? () => widget.onGo('jobs', null)
                    : expired
                        ? () => widget.onGo('my-access', null)
                        : reload);
          });
    if (mode == 'reward-nofill')
      return ApiView(
          load: () => widget.api.request('/me/monetization-config'),
          builder: (context, r, reload) => panel(
              'play',
              'Сейчас нет ролика',
              r['rewarded_access_enabled'] == true
                  ? 'Рекламный провайдер сейчас недоступен. Неподтверждённый просмотр не даёт награду.'
                  : 'Рекламный доступ сейчас отключён. Награда не начислялась.',
              'Выбрать подписку',
              () => widget.onGo('checkout', null)));
    if (mode == 'reward')
      return ApiView(
          load: () => widget.api.request('/me/monetization-config'),
          builder: (context, r, reload) => rewardOffer(r, reload));
    if (mode == 'manage-subscription' || mode == 'subscription-canceled')
      return ApiView(
          load: () => widget.id == null
              ? widget.api.request('/me/subscriptions')
              : widget.api.request('/me/subscriptions/${widget.id}'),
          builder: (context, data, reload) {
            final r = widget.id == null
                ? (items(data).isEmpty ? null : items(data).first)
                : data;
            final canceled = r?['status'] == 'canceled_at_period_end';
            final hasAccess = r != null &&
                ['active', 'grace'].contains(r['status']) &&
                DateTime.tryParse('${r['valid_until']}')
                        ?.isAfter(widget.api.clock.now) ==
                    true;
            if (mode == 'subscription-canceled')
              return panel(
                  canceled ? 'check' : 'info',
                  canceled ? 'Продление отключено' : 'Статус продления',
                  r == null
                      ? 'Подписка не найдена.'
                      : canceled
                          ? 'Оплаченный срок сохранён до ${r['valid_until']}.'
                          : 'Отключение продления ещё не подтверждено провайдером.',
                  'Мой доступ',
                  () => widget.onGo('my-access', null));
            return ListView(padding: const EdgeInsets.all(20), children: [
              const UiHeading(
                  'Всё под контролем', 'Исполнитель · поиск заказов и отклики'),
              if (r == null)
                const Notice('Подписка не найдена.')
              else ...[
                Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: line),
                        borderRadius: BorderRadius.circular(16)),
                    child: Column(children: [
                      Row(children: [
                        const Expanded(
                            child: UiText('Подписка JOBA',
                                style: TextStyle(
                                    fontSize: 16,
                                    height: 1.45,
                                    fontWeight: FontWeight.w700))),
                        JobaBadge(
                            canceled
                                ? 'Продление отключено'
                                : hasAccess
                                    ? 'Активна'
                                    : 'Не активна',
                            background: !canceled && hasAccess
                                ? const Color(0xFFE8F5EF)
                                : const Color(0xFFEAF0FC),
                            foreground: !canceled && hasAccess
                                ? const Color(0xFF147657)
                                : primary),
                      ]),
                      const SizedBox(height: 16),
                      checkoutFact(
                          'До',
                          DateTime.tryParse('${r['valid_until']}') == null
                              ? '—'
                              : DateFormat(
                                      'd MMMM',
                                      Localizations.localeOf(context)
                                          .languageCode)
                                  .format(DateTime.parse(r['valid_until'])
                                      .toLocal())),
                      checkoutFact('Цена',
                          '${money(r['price'])} · ${periodLabel(r['price']?['period'])}',
                          last: true),
                    ])),
                const SizedBox(height: 20),
                const UiText(
                    'Отключение автопродления не закрывает уже оплаченный срок. Для изменения условий откройте управление подпиской и дождитесь подтверждения провайдера.',
                    style: TextStyle(fontSize: 12, height: 1.5, color: muted)),
                const SizedBox(height: 20),
                OutlinedButton(
                    onPressed: busy
                        ? null
                        : () => run(() async {
                              final current = sessionGuard();
                              await widget.gateway.manage(r);
                              if (current()) reload();
                            }),
                    child: const UiText('Управлять подпиской')),
                TextButton(
                    onPressed: busy
                        ? null
                        : () => widget.onGo('subscription-canceled', r['id']),
                    child: const UiText('Проверить продление')),
                if (widget.gateway is DisconnectedCommerceGateway)
                  const Notice('Сервис ещё не подключён.', icon: 'info'),
              ],
              if (error != null) Notice(errorText(context, error!), error: true)
            ]);
          });
    return ApiView(
        load: () => widget.api.request('/billing/offers'),
        builder: (context, data, reload) {
          final offers =
              items(data).where((r) => r['product_type'] != 'boost').toList();
          final requested = selected ?? widget.id;
          final chosen = offers.where((r) => r['id'] == requested).toList();
          // A retired selection must never silently become another purchase.
          final offer = requested == null
              ? (offers.isEmpty ? null : offers.first)
              : (chosen.isEmpty ? null : chosen.first);
          final offerSnapshot = offer == null ? null : jsonEncode(offer);
          final accepted =
              offerSnapshot != null && acceptedOffer == offerSnapshot;
          return Column(children: [
            Expanded(
                child: ListView(padding: const EdgeInsets.all(20), children: [
              const UiText('Подписка JOBA',
                  style: TextStyle(
                      fontSize: 26,
                      height: 33 / 26,
                      letterSpacing: -.9,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              UiText((offer?['plan']=='customer'||(data['plans'] as List? ?? []).any((p)=>p['code']=='customer'))?'Доступ к анкетам исполнителей и размещению заказов.':'Поиск заказов и публикация услуг исполнителя.',
                  style: TextStyle(fontSize: 12, height: 1.5, color: muted)),
              const SizedBox(height: 20),
              if (offers.length > 1 || (offer == null && offers.isNotEmpty))
                for (final r in offers)
                  ListTile(
                      onTap: busy
                          ? null
                          : () => setState(() {
                                selected = r['id'];
                                acceptedOffer = null;
                              }),
                      leading: Icon(
                          offer?['id'] == r['id']
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          color: primary),
                      title: Text(r['plan'] == null
                          ? '${r['title'] ?? r['product_id']}'
                          : r['plan'] == 'customer' ? 'Заказчик' : r['plan'] == 'premium'
                              ? 'Премиум'
                              : 'Стандарт'),
                      subtitle: Text(
                          '${money(r)} · ${r['duration_days'] == 30 ? '30 дней' : r['period'] ?? ''}')),
              if (offer == null)
                const Notice('Действующие предложения пока недоступны.'),
              if (offer != null) ...[
                Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: line),
                        borderRadius: BorderRadius.circular(16)),
                    child: Column(children: [
                      checkoutFact('Полный доступ', offer['plan']=='customer'?'Заказчик':'Исполнитель'),
                      if (offer['plan'] != null)
                        checkoutFact(
                            'Тариф',
                            offer['plan'] == 'customer' ? 'Заказчик' : offer['plan'] == 'premium'
                                ? 'Премиум'
                                : 'Стандарт'),
                      checkoutFact(
                          'Период',
                          offer['duration_days'] == 30
                              ? '30 дней'
                              : periodLabel(offer['period'])),
                      if (offer['plan'] == 'premium')
                        checkoutFact('Топ-100', 'Приоритет услуг на 30 дней'),
                      checkoutFact('Цена', money(offer)),
                      checkoutFact('Продление', 'По условиям провайдера',
                          last: true),
                    ])),
                const SizedBox(height: 20),
                const UiText(
                    'Перед оплатой проверьте период, итоговую сумму и условия продления. Оплаченный срок сохраняется при отключении автопродления.',
                    style: TextStyle(fontSize: 12, height: 1.5, color: muted)),
                const SizedBox(height: 20),
              ],
              const Notice(
                  'Доступ активируется после подтверждения оплаты. Если платёж обрабатывается, повторная покупка не требуется.',
                  warning: true,
                  icon: 'info'),
              JobaMenu([
                JobaMenuEntry('Условия подписки', 'file',
                    () => widget.onGo('legal', null),
                    subtitle: 'Правила и отмена'),
                JobaMenuEntry('Восстановить покупку', 'refresh',
                    () => widget.onGo('restore', null),
                    subtitle: 'Без новой оплаты'),
              ]),
              const SizedBox(height: 12),
              CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: accepted,
                  onChanged: busy || offer == null
                      ? null
                      : (v) => setState(() =>
                          acceptedOffer = v == true ? offerSnapshot : null),
                  title: const UiText('Ознакомился с условиями подписки.',
                      style: TextStyle(fontSize: 12))),
              if (error != null) Notice(errorText(context, error!), error: true)
            ])),
            Container(
                decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: line))),
                child: SafeArea(
                    top: false,
                    child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                        child: FilledButton(
                            onPressed: busy || !accepted || offer == null
                                ? null
                                : () => purchase(offer),
                            child: const UiText('Продолжить оплату')))))
          ]);
        });
  }
}
