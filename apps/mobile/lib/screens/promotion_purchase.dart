import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/commerce_gateway.dart';
import '../core/currency.dart';
import '../core/design_states.dart';
import '../core/l10n.dart';
import '../core/theme.dart';
import '../core/widgets.dart';

class PromotionPurchase extends StatefulWidget {
  final JobaApi api;
  final String mode;
  final String? id;
  final CommerceGateway gateway;
  final void Function(String route, String? id) onGo;
  const PromotionPurchase(
      {required this.api,
      required this.mode,
      required this.onGo,
      this.id,
      this.gateway = const DisconnectedCommerceGateway(),
      super.key});
  @override
  State<PromotionPurchase> createState() => _PromotionPurchaseState();
}

class _PromotionPurchaseState extends State<PromotionPurchase> {
  bool accepted = false, busy = false;
  Object? error;
  String? target, price, placement;
  Future<void> run(Future<void> Function() f) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await f();
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget terms() => ListView(padding: const EdgeInsets.all(20), children: [
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
        OutlinedButton(
            onPressed: () => widget.onGo('promotion', null),
            child: const UiText('Вернуться к размещению')),
        TextButton(
            onPressed: () => widget.onGo('legal', null),
            child: const UiText('Правовые документы'))
      ]);
  @override
  Widget build(BuildContext context) {
    if (widget.mode == 'promotion-terms') return terms();
    if (widget.mode == 'promotion-no-slots')
      return ApiView(
          load: () => widget.api.request('/boost-offers'),
          builder: (context, r, reload) =>
              ListView(padding: const EdgeInsets.all(20), children: [
                JobaStatePanel(
                    icon: 'clock',
                    title: 'Проверьте доступность',
                    message:
                        'В выбранный период размещение не было подтверждено. Деньги этим действием не списаны. Выберите другую площадку или период.',
                    primaryLabel: 'Изменить размещение',
                    onPrimary: () => widget.onGo('promotion', null))
              ]));
    if (widget.mode == 'promotion-checkout')
      return ApiView(
          load: () => widget.api.request('/me/boosts/${widget.id}'),
          builder: (context, r, reload) {
            final p = r['price'];
            final active = r['status'] == 'reserved' &&
                DateTime.tryParse('${r['reservation_expires_at']}')
                        ?.isAfter(DateTime.now()) ==
                    true;
            return ActionForm(
                stickySubmit: true,
                submitEnabled: accepted && active,
                before: [
                  Notice(active
                      ? 'Место зарезервировано до ${r['reservation_expires_at']}'
                      : 'Резерв больше не доступен.'),
                  const UiHeading('Продвижение'),
                  DataCard('${r['title']}', subtitle: '${r['city']}'),
                  DataCard('Период',
                      translateTitle: true,
                      subtitle: '${r['starts_at']} — ${r['ends_at']}'),
                  DataCard('Итого',
                      translateTitle: true,
                      subtitle: p?['currency'] != null
                          ? formatMoney(p['amount_minor'], p['currency'],
                              Localizations.localeOf(context).languageCode)
                          : '—'),
                  const Notice(
                      'Разовая покупка, без автопродления. Подтверждение оплаты проверяется сервером.'),
                  TextButton(
                      onPressed: () => widget.onGo('promotion-terms', null),
                      child: const UiText('Условия размещения'))
                ],
                afterFields: [
                  CheckboxListTile(
                      value: accepted,
                      onChanged: (v) => setState(() => accepted = v == true),
                      title:
                          const UiText('Ознакомился с условиями размещения.'))
                ],
                button: 'Продолжить оплату',
                fields: const [],
                submit: (_) async {
                  final receipt = await widget.gateway.purchase(p);
                  try {
                    await widget.api.request('/boost-purchases/verify',
                        method: 'POST',
                        body: {...receipt, 'reservation_id': widget.id});
                  } on ApiException catch (e) {
                    if (e.code != 'PAYMENT_PENDING') rethrow;
                  }
                  if (mounted) widget.onGo('promotion-pending', widget.id);
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
          return ActionForm(
              stickySubmit: true,
              submitEnabled:
                  target != null && price != null && placement != null,
              before: [
                const UiHeading('Больше внимания к вашей работе',
                    'Продвижение не меняет органический рейтинг.'),
                DropdownButtonFormField<String>(
                    initialValue: target,
                    decoration: InputDecoration(
                        labelText: localize(context, 'Объявление')),
                    items: [
                      for (final r in targets)
                        DropdownMenuItem(
                            value: r['id'], child: Text('${r['title']}'))
                    ],
                    onChanged: (v) => setState(() => target = v)),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                    initialValue: placement,
                    decoration: InputDecoration(
                        labelText: localize(context, 'Размещение')),
                    items: [
                      for (final r in places)
                        DropdownMenuItem(
                            value: r['payload']['placement_id'],
                            child: Text(
                                '${r['title'] ?? localize(context, 'Размещение')}'))
                    ],
                    onChanged: (v) => setState(() => placement = v)),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                    initialValue: price,
                    decoration: InputDecoration(
                        labelText: localize(context, 'Период и стоимость')),
                    items: [
                      for (final r in prices)
                        DropdownMenuItem(
                            value: r['id'],
                            child: Text(
                                '${r['period']} · ${formatMoney(r['amount_minor'], r['currency'], Localizations.localeOf(context).languageCode)}'))
                    ],
                    onChanged: (v) => setState(() => price = v)),
                if (targets.isEmpty)
                  const Notice('Нет доступных объявлений для продвижения.'),
                if (prices.isEmpty || places.isEmpty)
                  const Notice('Действующие предложения пока недоступны.'),
                TextButton(
                    onPressed: () => widget.onGo('promotion-terms', null),
                    child: const UiText('Условия размещения')),
                TextButton(
                    onPressed: () => widget.onGo('promotion-history', null),
                    child: const UiText('Мои продвижения'))
              ],
              fields: const [],
              button: 'Проверить размещение',
              submit: (_) async {
                try {
                  final reserved = await widget.api
                      .request('/boost-reservations', method: 'POST', body: {
                    'target_id': target,
                    'price_id': price,
                    'placement_id': placement
                  });
                  if (mounted)
                    widget.onGo('promotion-checkout', reserved['id']);
                } on ApiException catch (e) {
                  if (e.code == 'PLACEMENT_FULL') {
                    if (mounted) widget.onGo('promotion-no-slots', null);
                    return;
                  }
                  rethrow;
                }
              });
        });
  }
}
