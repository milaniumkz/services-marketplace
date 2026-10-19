import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/api.dart';
import '../core/currency.dart';
import '../core/design_icons.dart';
import '../core/design_widgets.dart';
import '../core/l10n.dart';
import '../core/theme.dart';
import '../core/widgets.dart';

/// S05 and S32 share data, but represent choosing access and managing it.
class ExecutorAccess extends StatelessWidget {
  final bool choosing;
  final List<Json> grants, subscriptions;
  final Json config;
  final void Function(String route, String? id) onGo;
  const ExecutorAccess(
      {required this.choosing,
      required this.grants,
      required this.subscriptions,
      required this.config,
      required this.onGo,
      super.key});
  DateTime? until(Json r) => DateTime.tryParse('${r['valid_until'] ?? ''}');
  bool valid(Json r) =>
      until(r)?.isAfter(DateTime.now()) == true &&
      (r['balance'] == null || r['balance'] > 0);
  String date(BuildContext context, Json r, {bool short = false}) {
    final value = until(r);
    return value == null
        ? '—'
        : DateFormat(short ? 'dd.MM' : 'd MMMM',
                Localizations.localeOf(context).languageCode)
            .format(value.toLocal());
  }

  String money(BuildContext context, Json? price) =>
      price?['amount_minor'] is int
          ? formatMoney(price!['amount_minor'], '${price['currency']}',
              Localizations.localeOf(context).languageCode)
          : '—';
  String period(Json? price) => switch (price?['period']) {
        'year' || 'yearly' || 'P1Y' => '/ год',
        'week' || 'weekly' || 'P1W' => '/ неделю',
        'month' || 'monthly' || 'P1M' => '/ месяц',
        null => '',
        _ => '/ ${price!['period']}'
      };
  Widget card(List<Widget> children,
          {bool dark = false, bool selected = false}) =>
      Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: dark ? navy : Colors.white,
              border: Border.all(
                  color: selected ? primary : line, width: selected ? 2 : 1),
              borderRadius: BorderRadius.circular(16)),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children));
  Widget text(String value,
          {double size = 12, Color color = navy, bool bold = false}) =>
      UiText(value,
          style: TextStyle(
              fontSize: size,
              height: size == 10
                  ? 1.4
                  : size == 30
                      ? 1.45
                      : 1.5,
              color: color,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w400));
  Widget badge(String value, {bool green = false}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
          color: green ? const Color(0xFFE8F5EF) : const Color(0xFFEAF0FC),
          borderRadius: BorderRadius.circular(7)),
      child: text(value,
          size: 10,
          bold: true,
          color: green ? const Color(0xFF147657) : primary));
  Widget action(String label, String route, {String? id}) => SizedBox(
      width: double.infinity,
      child:
          FilledButton(onPressed: () => onGo(route, id), child: UiText(label)));
  Widget benefit(String label) => Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const JobaIcon('check', color: primary, size: 14),
        const SizedBox(width: 10),
        Expanded(child: text(label))
      ]));
  void history(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
          child: SizedBox(
              height: MediaQuery.sizeOf(context).height * .75,
              child: ListView(padding: const EdgeInsets.all(20), children: [
                Row(children: [
                  const Expanded(child: UiHeading('История доступа')),
                  IconButton(
                      tooltip: localize(context, 'Закрыть'),
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close))
                ]),
                if (grants.isEmpty && subscriptions.isEmpty)
                  const Notice('История доступа пока пуста.'),
                for (final r in subscriptions)
                  DataCard('Подписка JOBA',
                      translateTitle: true,
                      subtitle: '${r['status']} · ${date(context, r)}'),
                for (final r in grants)
                  DataCard(sourceLabel(r),
                      translateTitle: true,
                      subtitle:
                          '${date(context, r)}${r['balance'] == null ? '' : ' · ${r['balance']}'}')
              ]))));
  String sourceLabel(Json r) => switch (r['source']) {
        'subscription' || 'subscription_promotion' => 'Подписка',
        'referral_privilege' => 'Бонус за приглашение',
        'verified_ad_reward' => 'Рекламная награда',
        _ => 'Доступ JOBA'
      };
  @override
  Widget build(BuildContext context) {
    final active = subscriptions
        .where((r) =>
            valid(r) &&
            ['active', 'grace', 'canceled_at_period_end'].contains(r['status']))
        .toList()
      ..sort((a, b) => until(b)!.compareTo(until(a)!));
    final subscription = active.isEmpty ? null : active.first;
    final offers = (config['offers'] as List? ?? [])
        .cast<Json>()
        .where((r) => r['product_type'] != 'boost')
        .toList();
    final offer = offers.isEmpty ? null : offers.first;
    final price = subscription?['price'] as Json?;
    if (choosing)
      return ListView(padding: const EdgeInsets.all(20), children: [
        const UiText('Ваши возможности',
            style: TextStyle(
                fontSize: 26,
                height: 33 / 26,
                letterSpacing: -.9,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        text('Поиск заказов, публикация услуг и отклики.', color: muted),
        const SizedBox(height: 20),
        card([
          Row(children: [
            Expanded(child: text('Подписка JOBA', size: 16, bold: true)),
            badge('Исполнитель')
          ]),
          const SizedBox(height: 16),
          Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(
                    child: text(money(context, offer), size: 30, bold: true)),
                const SizedBox(width: 6),
                text(period(offer), color: muted)
              ]),
          const SizedBox(height: 8),
          text(
              offer == null
                  ? 'Тариф ещё не опубликован'
                  : 'Итоговая цена будет показана перед оплатой.',
              size: 10,
              color: muted),
          const Divider(height: 29, thickness: 1),
          benefit('Находите подходящие заказы'),
          benefit('Публикуйте услуги и откликайтесь'),
          benefit('Общайтесь по вашим заказам'),
          const SizedBox(height: 6),
          action('Посмотреть условия', 'checkout', id: offer?['id']),
          const SizedBox(height: 12),
          text('Автопродление можно отменить. Оплаченный срок сохраняется.',
              size: 10, color: muted),
        ], selected: true),
        const SizedBox(height: 12),
        Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(
              side: const BorderSide(color: line),
              borderRadius: BorderRadius.circular(16)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => onGo('reward', null),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Container(
                    width: 52,
                    height: 48,
                    decoration: BoxDecoration(
                        color: const Color(0xFFFFF5DA),
                        borderRadius: BorderRadius.circular(15)),
                    child: const Center(child: JobaIcon('play', size: 25))),
                const SizedBox(width: 10),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      text('Доступ за рекламу', size: 13, bold: true),
                      const SizedBox(height: 4),
                      text(
                          config['rewarded_access_enabled'] == true &&
                                  config['reward_provider_ready'] == true
                              ? 'Условия и срок доступа'
                              : 'Пока недоступен',
                          size: 10,
                          color: muted),
                    ])),
                const SizedBox(width: 10),
                const JobaIcon('right', size: 14),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 12),
        text(
            'Рекламный способ доступен только после проверки правил провайдера для страны.',
            size: 10,
            color: muted),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
              child: TextButton(
                  style: TextButton.styleFrom(
                      minimumSize: const Size(0, 52),
                      textStyle: const TextStyle(
                          fontFamily: 'Noto',
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                  onPressed: () => onGo('restore', null),
                  child: const UiText('Восстановить'))),
          const SizedBox(width: 10),
          Expanded(
              child: TextButton(
                  style: TextButton.styleFrom(
                      minimumSize: const Size(0, 52),
                      textStyle: const TextStyle(
                          fontFamily: 'Noto',
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                  onPressed: () => onGo('support', null),
                  child: const UiText('Поддержка')))
        ]),
      ]);
    final known =
        subscription ?? (subscriptions.isEmpty ? null : subscriptions.first);
    return ListView(padding: const EdgeInsets.all(20), children: [
      card([
        Row(children: [
          Expanded(
              child: text('Подписка JOBA',
                  size: 16, color: Colors.white, bold: true)),
          badge(
              subscription == null
                  ? 'Не активна'
                  : subscription['status'] == 'canceled_at_period_end'
                      ? 'Продление отключено'
                      : 'Активна',
              green: subscription != null)
        ]),
        const SizedBox(height: 20),
        text(
            subscription == null
                ? 'Выберите доступ'
                : '${localize(context, 'До')} ${date(context, subscription)}',
            size: 28,
            color: Colors.white,
            bold: true),
        const SizedBox(height: 8),
        text('Исполнитель · поиск заказов и отклики',
            color: const Color(0xFFD5DFEE)),
        const Divider(height: 40, color: Color(0x26FFFFFF)),
        Row(children: [
          Expanded(
              child: text(
                  subscription?['status'] == 'canceled_at_period_end'
                      ? 'Автопродление'
                      : 'Следующее продление',
                  color: Colors.white)),
          text(
              subscription == null
                  ? 'Не оформлено'
                  : subscription['status'] == 'canceled_at_period_end'
                      ? 'Отключено'
                      : '${money(context, price)} ${period(price)}',
              color: Colors.white,
              bold: true)
        ]),
        const SizedBox(height: 8),
        text(
            subscription == null
                ? 'Заказчик пользуется JOBA бесплатно.'
                : 'Условия подтверждены платёжным провайдером.',
            size: 10,
            color: const Color(0xFFAEBFD9)),
      ], dark: true),
      const SizedBox(height: 20),
      JobaMenu([
        JobaMenuEntry(
            known == null ? 'Выбрать доступ' : 'Управление подпиской',
            'card',
            () => onGo(
                known == null ? 'access' : 'manage-subscription', known?['id']),
            subtitle: known == null
                ? 'Подписка только для исполнителя'
                : 'Проверить или отменить автопродление'),
        JobaMenuEntry(
            'Восстановить покупки', 'refresh', () => onGo('restore', null),
            subtitle: 'Не создаёт новую покупку'),
        JobaMenuEntry('История доступа', 'clock', () => history(context),
            subtitle: 'Подписка, реклама и бонусы'),
      ]),
      const SizedBox(height: 20),
      card([
        text('Источники доступа', size: 16, bold: true),
        const SizedBox(height: 8),
        for (final source in [
          'Подписка',
          'Бонус за приглашение',
          'Рекламная награда'
        ]) ...[
          if (source != 'Подписка') const Divider(height: 24),
          Builder(builder: (_) {
            final available = grants
                .where((r) => valid(r) && sourceLabel(r) == source)
                .toList()
              ..sort((a, b) => until(b)!.compareTo(until(a)!));
            final entry = available.isEmpty
                ? (source == 'Подписка' ? subscription : null)
                : available.first;
            return Row(children: [
              Expanded(child: text(source)),
              entry == null
                  ? text('Нет активных', color: muted)
                  : badge(
                      '${localize(context, 'До')} ${date(context, entry, short: true)}',
                      green: true)
            ]);
          }),
        ],
      ]),
      const SizedBox(height: 16),
      text(
          'Продвижение оплачивается отдельно и не заменяет доступ исполнителя.',
          color: muted),
      const SizedBox(height: 12),
      TextButton(
          onPressed: () => onGo('support', null),
          child: const UiText('Поддержка')),
    ]);
  }
}
