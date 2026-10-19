import 'dart:async';
import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/commerce_gateway.dart';
import '../core/currency.dart';
import '../core/design_states.dart';
import '../core/design_widgets.dart';
import '../core/design_icons.dart';
import '../core/l10n.dart';
import '../core/theme.dart';
import '../core/widgets.dart';

class PromotionPurchase extends StatefulWidget {
  final JobaApi api;
  final String mode;
  final String? id;
  final CommerceGateway gateway;
  final DateTime Function() now;
  final void Function(String route, String? id) onGo;
  const PromotionPurchase(
      {required this.api,
      required this.mode,
      required this.onGo,
      this.id,
      this.now = DateTime.now,
      this.gateway = const DisconnectedCommerceGateway(),
      super.key});
  @override
  State<PromotionPurchase> createState() => _PromotionPurchaseState();
}

class _PromotionPurchaseState extends State<PromotionPurchase> {
  bool accepted = false, busy = false;
  Object? error;
  String? target, price, placement;
  Json? receipt;
  Timer? timer;
  late final bool Function() ownsScreen;
  @override
  void initState() {
    super.initState();
    final api = widget.api;
    final generation = api.sessionGeneration;
    final owner = api.session?['user']?['id'];
    ownsScreen = () =>
        mounted &&
        identical(widget.api, api) &&
        !api.disposed &&
        api.authenticated &&
        api.sessionGeneration == generation &&
        api.session?['user']?['id'] == owner;
    if (widget.mode == 'promotion-checkout')
      timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  String periodLabel(Json p) => localize(
      context,
      const {'week': 'Неделя', 'month': 'Месяц', 'year': 'Год'}[p['period']] ??
          '${p['duration_days'] ?? '—'} дн.');
  String placeLabel(dynamic id) => localize(
      context,
      const {
            'search.services.promoted': 'Каталог услуг',
            'search.orders.promoted': 'Лента заказов',
            'home.promoted.services': 'Услуги на главной',
            'top.services.promoted': 'Топ услуг',
            'top.orders.promoted': 'Топ заказов'
          }[id] ??
          'Продвижение');
  Widget fieldLabel(String title) => Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: UiText(title,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)));
  Widget facts(List<Widget> children) => Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: line),
          borderRadius: BorderRadius.circular(16)),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: children));
  Widget fact(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(children: [
        Expanded(
            child: UiText(label,
                style: const TextStyle(fontSize: 12, color: muted))),
        const SizedBox(width: 10),
        Flexible(
            child: Text(value,
                textAlign: TextAlign.right,
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)))
      ]));
  String dateRange(Json r) {
    final start = DateTime.tryParse('${r['starts_local'] ?? r['starts_at']}'),
        end = DateTime.tryParse('${r['ends_local'] ?? r['ends_at']}');
    if (start == null || end == null) return '—';
    final loc = MaterialLocalizations.of(context);
    return '${loc.formatMediumDate(start)} — ${loc.formatMediumDate(end)}';
  }

  String remaining(DateTime? end) {
    final seconds = end?.difference(widget.now()).inSeconds ?? 0;
    if (seconds <= 0) return '00:00';
    return '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  Future<void> run(Future<void> Function() f) async {
    if (busy) return;
    if (!ownsScreen()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await f();
    } catch (e) {
      if (ownsScreen()) setState(() => error = e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void openTerms() => Navigator.push(
      context,
      MaterialPageRoute(
          builder: (c) => Scaffold(
              backgroundColor: canvas,
              appBar: AppBar(title: const UiText('Условия размещения')),
              body: terms(onReturn: () => Navigator.pop(c)))));
  Widget terms({VoidCallback? onReturn}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
            child: ListView(padding: const EdgeInsets.all(20), children: [
          const UiHeading('Что важно знать', 'Условия показаны до покупки.'),
          for (final e in const {
            'Отдельный рекламный блок':
                'Карточка помечается «Продвигается». Органический топ и звёздный рейтинг не меняются.',
            'Без гарантии результата':
                'Продвижение не гарантирует первое место, число показов, клики или заказы.',
            'Паузы и окончание':
                'При скрытии объекта или утрате допуска показ останавливается. Календарный срок сам не продлевается.',
            'Возврат и помощь':
                'Возврат подтверждает провайдер. Поддержка рассматривает сбои и спорные ситуации по применимым условиям.'
          }.entries)
            DataCard(e.key,
                translateTitle: true, subtitle: localize(context, e.value)),
        ])),
        SafeArea(
            top: false,
            child: Container(
                decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: line))),
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                child: FilledButton(
                    onPressed: onReturn ?? () => widget.onGo('promotion', null),
                    child: const UiText('Вернуться к размещению'))))
      ]);
  @override
  Widget build(BuildContext context) {
    if (widget.mode == 'promotion-terms') return terms();
    if (widget.mode == 'promotion-no-slots')
      return ListView(padding: const EdgeInsets.all(20), children: [
        JobaStatePanel(
            icon: 'clock',
            title: 'Это место занято',
            message:
                'В выбранный период нет свободного размещения. Деньги не списаны. Выберите другую площадку или срок.',
            primaryLabel: 'Изменить размещение',
            onPrimary: () => widget.onGo('promotion', null)),
      ]);
    if (widget.mode == 'promotion-checkout')
      return ApiView(
          load: () => widget.api.request('/me/boosts/${widget.id}'),
          builder: (context, r, reload) {
            final p = r['price'] as Json?;
            final end = DateTime.tryParse('${r['reservation_expires_at']}');
            final active =
                r['status'] == 'reserved' && end?.isAfter(widget.now()) == true;
            final connected = widget.gateway is! DisconnectedCommerceGateway;
            return ActionForm(
                stickySubmit: true,
                externalBusy: busy,
                submitEnabled: accepted &&
                    p != null &&
                    (receipt != null || active && connected),
                fields: const [],
                button:
                    receipt == null ? 'Продолжить оплату' : 'Проверить оплату',
                before: [
                  JobaBadge(
                      active
                          ? '${localize(context, 'Место зарезервировано')} · ${remaining(end)}'
                          : localize(context, 'Резерв больше не доступен'),
                      background: const Color(0xFFFFF4D4),
                      foreground: const Color(0xFF705000)),
                  const SizedBox(height: 16),
                  Text(
                      '${localize(context, 'Продвижение')}\n${p == null ? '' : periodLabel(p)}',
                      style: const TextStyle(
                          fontSize: 28,
                          height: 1.24,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -.7)),
                  const SizedBox(height: 20),
                  facts([
                    Text('${r['title'] ?? ''}',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Text('${r['city'] ?? ''}',
                        style: const TextStyle(fontSize: 12, color: muted)),
                    const SizedBox(height: 14),
                    const Divider(height: 1),
                    fact('Размещение', placeLabel(r['placement_id'])),
                    fact('Период', dateRange(r)),
                    fact('Время', '${p?['time_zone'] ?? 'UTC'}'),
                    fact(
                        'Итого',
                        p?['currency'] == null
                            ? '—'
                            : formatMoney(p!['amount_minor'], p['currency'],
                                Localizations.localeOf(context).languageCode)),
                  ]),
                  const SizedBox(height: 20),
                  const UiText(
                      'Разовая покупка, без автопродления. При скрытии профиля показ остановится; срок автоматически не продлевается.',
                      style:
                          TextStyle(fontSize: 12, height: 1.5, color: muted)),
                  const SizedBox(height: 12),
                  const UiText(
                      'Возврат и компенсация рассматриваются по условиям провайдера. Место и результат не гарантированы.',
                      style:
                          TextStyle(fontSize: 12, height: 1.5, color: muted)),
                ],
                afterFields: [
                  CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: accepted,
                      onChanged: busy
                          ? null
                          : (v) => setState(() => accepted = v == true),
                      title: const UiText('Ознакомился с условиями размещения.',
                          style: TextStyle(fontSize: 12, height: 1.5))),
                  TextButton(
                      onPressed: busy ? null : openTerms,
                      child: const UiText('Условия размещения')),
                  if (!connected && receipt == null)
                    const Notice(
                        'Платёжный провайдер ещё не подключён. Оплата недоступна.'),
                  if (!active && receipt == null)
                    TextButton(
                        onPressed: () => widget.onGo('promotion', null),
                        child: const UiText('Проверить новое размещение')),
                  if (receipt != null)
                    const Notice(
                        'Подтверждение покупки сохранено на этом экране. Повторная проверка не запускает новую оплату.'),
                ],
                submit: (_) async {
                  if (!ownsScreen()) {
                    throw ApiException(
                        'SESSION_EXPIRED', 'Войдите в аккаунт заново');
                  }
                  final api = widget.api;
                  final reservationId = widget.id;
                  setState(() => busy = true);
                  try {
                    if (receipt == null) {
                      final proof = await widget.gateway.purchase(p!);
                      if (!ownsScreen()) return;
                      receipt = proof;
                    }
                    if (!ownsScreen()) return;
                    try {
                      await api.request('/boost-purchases/verify',
                          method: 'POST',
                          body: {...receipt!, 'reservation_id': reservationId});
                    } on ApiException catch (e) {
                      if (e.code != 'PAYMENT_PENDING') rethrow;
                    }
                    if (ownsScreen())
                      widget.onGo('promotion-pending', reservationId);
                  } finally {
                    if (mounted) setState(() => busy = false);
                  }
                });
          });
    return ApiView(
        load: () => Future.wait([
              widget.api.request('/boost-offers'),
              widget.api.request('/me/contractor-profile'),
              widget.api.request('/me/orders',
                  query: {'bucket': 'open', 'limit': 100})
            ]),
        builder: (context, data, reload) {
          final options = data[0], profile = data[1]['profile'];
          final targets = <Json>[
            if (profile?['status'] == 'published') profile,
            ...items(data[2])
          ];
          final prices = items(options),
              places = (options['placements'] as List).cast<Json>();
          if (target == null && targets.length == 1)
            target = targets.first['id'];
          if (price == null && prices.isNotEmpty) price = prices.first['id'];
          final chosen = targets.where((r) => r['id'] == target).firstOrNull;
          final kind = chosen?['kind'] ??
              (chosen?['id'] == profile?['id'] ? 'contractor' : 'order');
          final compatible = places
              .where((p) =>
                  ('${p['payload']['placement_id']}'.contains('.orders.')
                      ? 'order'
                      : 'contractor') ==
                  kind)
              .toList();
          if (!compatible.any((p) => p['payload']['placement_id'] == placement))
            placement = compatible.length == 1
                ? compatible.first['payload']['placement_id']
                : null;
          final selected = prices.where((r) => r['id'] == price).firstOrNull;
          return ActionForm(
              stickySubmit: true,
              externalBusy: busy,
              submitEnabled:
                  chosen != null && selected != null && placement != null,
              before: [
                const UiText('Больше видимости',
                    style: TextStyle(
                        fontSize: 26,
                        height: 1.269,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -.9)),
                const SizedBox(height: 8),
                const UiText('Отдельное размещение с отметкой «Продвигается».',
                    style: TextStyle(fontSize: 12, height: 1.5, color: muted)),
                if (error != null)
                  Notice(errorText(context, error!), error: true),
                fieldLabel('Что продвигаем'),
                DropdownButtonFormField<String>(
                    key: ValueKey('target:$target'),
                    initialValue: target,
                    isExpanded: true,
                    style: const TextStyle(
                        fontFamily: 'Noto', fontSize: 14, color: muted),
                    icon: const JobaIcon('down'),
                    items: [
                      for (final r in targets)
                        DropdownMenuItem(
                            value: '${r['id']}', child: Text('${r['title']}'))
                    ],
                    onChanged: busy ? null : (v) => setState(() => target = v)),
                fieldLabel('Где показывать'),
                DropdownButtonFormField<String>(
                    key: ValueKey('place:$placement'),
                    initialValue: placement,
                    isExpanded: true,
                    style: const TextStyle(
                        fontFamily: 'Noto', fontSize: 14, color: muted),
                    icon: const JobaIcon('down'),
                    items: [
                      for (final r in compatible)
                        DropdownMenuItem(
                            value: '${r['payload']['placement_id']}',
                            child: Text(
                                '${r['title'] ?? placeLabel(r['payload']['placement_id'])}'))
                    ],
                    onChanged:
                        busy ? null : (v) => setState(() => placement = v)),
                fieldLabel('Разовый срок'),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final r in prices)
                    ChoiceChip(
                        showCheckmark: false,
                        selectedColor: primary,
                        backgroundColor: Colors.white,
                        side: const BorderSide(color: line),
                        shape: const StadiumBorder(),
                        labelStyle: TextStyle(
                            fontFamily: 'Noto',
                            fontSize: 12,
                            color: price == r['id'] ? Colors.white : navy),
                        label: Text(periodLabel(r)),
                        selected: price == r['id'],
                        onSelected: busy
                            ? null
                            : (_) => setState(() => price = r['id']))
                ]),
                const SizedBox(height: 20),
                facts([
                  Row(children: [
                    const Expanded(
                        child: UiText('Стоимость',
                            style: TextStyle(fontSize: 12, color: muted))),
                    Text(
                        selected == null
                            ? '—'
                            : formatMoney(
                                selected['amount_minor'],
                                selected['currency'],
                                Localizations.localeOf(context).languageCode),
                        style: const TextStyle(
                            fontSize: 23, fontWeight: FontWeight.w700))
                  ]),
                  const SizedBox(height: 14),
                  const Divider(height: 1),
                  const SizedBox(height: 14),
                  const UiText('Точные даты будут показаны перед оплатой.',
                      style: TextStyle(fontSize: 12, height: 1.5)),
                  const SizedBox(height: 8),
                  const UiText(
                      'Без автопродления. Финальная доступность подтверждается перед покупкой.',
                      style: TextStyle(fontSize: 10, color: muted)),
                ]),
                const Notice(
                    'Продвижение не добавляет реакции и звёзды. Первое место, показы и заказы не гарантируются.',
                    warning: true,
                    icon: 'info',
                    margin: EdgeInsets.symmetric(vertical: 16)),
                JobaMenu([
                  JobaMenuEntry('Условия размещения', 'file', openTerms,
                      subtitle: 'Срок, пауза, возврат и раннее закрытие'),
                  JobaMenuEntry('Мои продвижения', 'clock',
                      () => widget.onGo('promotion-history', null),
                      subtitle: 'История и статусы'),
                ]),
                if (targets.isEmpty)
                  const Notice('Нет доступных объявлений для продвижения.'),
                if (prices.isEmpty || compatible.isEmpty)
                  const Notice('Действующие предложения пока недоступны.'),
              ],
              fields: const [],
              button: 'Проверить размещение',
              submit: (_) => run(() async {
                    try {
                      if (!ownsScreen()) return;
                      final reserved = await widget.api.request(
                          '/boost-reservations',
                          method: 'POST',
                          body: {
                            'target_id': target,
                            'price_id': price,
                            'placement_id': placement
                          });
                      if (ownsScreen())
                        widget.onGo('promotion-checkout', reserved['id']);
                    } on ApiException catch (e) {
                      if (e.code == 'PLACEMENT_FULL') {
                        if (ownsScreen())
                          widget.onGo('promotion-no-slots', null);
                        return;
                      }
                      rethrow;
                    }
                  }));
        });
  }
}
