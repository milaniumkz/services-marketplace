import 'package:flutter/foundation.dart';
import '../advertising/web_ads.dart';
import 'dart:async';
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
class ExecutorAccess extends StatefulWidget {
  final JobaApi? api;
  final bool choosing, customer;
  final List<Json> grants, subscriptions;
  final Json config;
  final DateTime Function() now;
  final void Function(String route, String? id) onGo;
  const ExecutorAccess(
      {this.api,this.customer = false, required this.choosing,
      required this.grants,
      required this.subscriptions,
      required this.config,
      required this.onGo,
      this.now = DateTime.now,
      super.key});
  @override
  State<ExecutorAccess> createState() => _ExecutorAccessState();
}

class _ExecutorAccessState extends State<ExecutorAccess> {
  Timer? _ticker;
  bool get choosing => widget.choosing;
  List<Json> get grants => widget.grants.where((r)=>widget.customer ? (r['capabilities'] as List? ?? []).contains('view_contractors') : r['role']!='customer' && r['plan']!='customer').toList();
  List<Json> get subscriptions => widget.subscriptions.where((r)=>(r['plan']=='customer')==widget.customer).toList();
  Json get config => widget.config;
  void onGo(String route, String? id) => widget.onGo(route, id);
  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(covariant ExecutorAccess oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.choosing != choosing) _schedule();
  }

  void _schedule() {
    _ticker?.cancel();
    if (!choosing)
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  DateTime? until(Json r) => DateTime.tryParse('${r['valid_until'] ?? ''}');
  bool valid(Json r) =>
      until(r)?.isAfter(widget.now()) == true &&
      (DateTime.tryParse('${r['valid_from']??''}')?.isAfter(widget.now())!=true) &&
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
  String period(Json? price) => price?['period'] == 'days'
      ? '/ ${price?['duration_days'] ?? 30} дней'
      : switch (price?['period']) {
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
                  DataCard(r['plan']=='top100'?'Топ-100 отдельно':r['is_upgrade']==true?'Доплата до Премиума':r['plan'] == 'customer' ? 'Заказчик' : r['plan'] == 'premium' ? 'Премиум' : 'Стандарт',
                      translateTitle: true,
                      subtitle: '${switch(r['status']){'active'=>'Действует','scheduled'=>'Ожидает начала','grace'=>'Льготный период','expired'=>'Завершена','revoked'=>'Отозвана','canceled_at_period_end'=>'До конца оплаченного срока',_=>'Не активна'}} · ${date(context, r)}'),
                for (final r in grants)
                  DataCard(r['is_test']==true?'Тестовая подписка':sourceLabel(r),
                      translateTitle: true,
                      subtitle:
                          '${date(context, r)}${r['balance'] == null ? '' : ' · ${r['balance']}'}')
              ]))));
  String sourceLabel(Json r) => switch (r['source']) {
        'subscription' || 'subscription_promotion' => 'Подписка',
        'referral_privilege' => 'Бонус за приглашение',
        'verified_ad_reward' => 'Рекламная награда',
        'web_ad_reward' => 'Подписка за рекламу',
        _ => 'Доступ JOBA'
      };
  List<Widget> extraPurchases(BuildContext context,List<Json> offers){
    if(widget.customer)return [];
    final upgrade=offers.where((o)=>o['offer_kind']=='upgrade').toList(),top=offers.where((o)=>o['plan']=='top100').toList();
    final activeBase=subscriptions.where((s)=>valid(s)&&s['is_upgrade']!=true&&s['plan']!='top100'&&['active','grace','canceled_at_period_end'].contains(s['status'])).toList();
    final premium=activeBase.isNotEmpty&&subscriptions.any((s)=>valid(s)&&s['plan']=='premium'&&['active','grace','canceled_at_period_end'].contains(s['status']));
    final standard=activeBase.any((s)=>s['plan']=='standard');
    final topPeriods=subscriptions.where((s)=>s['plan']=='top100'&&until(s)?.isAfter(widget.now())==true&&['active','scheduled','grace','canceled_at_period_end'].contains(s['status'])).toList()..sort((a,b)=>until(b)!.compareTo(until(a)!));
    final configured=(config['addons'] as List? ?? []).cast<Json>().where((p)=>p['code']=='top100').toList();
    final Json? topPrice=top.isNotEmpty?top.first:configured.isEmpty?null:configured.first;
    if(choosing&&activeBase.isEmpty&&top.isEmpty)return [const Notice('Отдельный Топ-100 доступен после подключения Стандарта. В Премиуме он уже включён.',icon:'crown')];
    return [
      Padding(padding:const EdgeInsets.only(bottom:16),child:card([
        text('Топ-100 отдельно',size:18,bold:true),const SizedBox(height:8),
        if(premium) ...[text('Топ-100 уже включён в Премиум',size:16,bold:true),text('Дополнительно оплачивать его не нужно.')]
        else ...[
          if(topPrice!=null)text('${money(context,topPrice)} / 30 дней',size:22,bold:true),
          text('Приоритет услуг в Топ-100 при активном Стандарте. Основная подписка не продлевается.'),
          if(topPeriods.isNotEmpty)text('Отдельный Топ-100 оплачен до ${date(context,topPeriods.first)}. Для размещения нужен активный основной доступ.'),
          if(top.isNotEmpty) ...[
            if(top.first['discount_percent'] is num&&top.first['discount_percent']>0)text('Учтена персональная скидка ${top.first['discount_percent']}%.'),
            action(topPeriods.isEmpty?'Подключить Топ-100':'Продлить Топ-100','checkout',id:top.first['id'])
          ]else if(!standard) ...[
            text(choosing?'Сначала выберите Стандарт ниже. Затем Топ-100 можно оплатить отдельно.':'Для отдельного Топ-100 сначала подключите Стандарт. В Премиуме Топ-100 уже включён.'),
            if(!choosing)action('Выбрать Стандарт','access')
          ]else text('Оплата Топ-100 пока недоступна. Действующий основной доступ сохраняется.'),
        ]
      ])),
      if(upgrade.isNotEmpty&&!choosing)Padding(padding:const EdgeInsets.only(bottom:16),child:card([text('Повысить до Премиума',size:18,bold:true),const SizedBox(height:8),text(money(context,upgrade.first),size:24,bold:true),text('Премиум включится сразу после оплаты. Доплата рассчитана за оставшийся срок Стандарта; дата окончания доступа сохраняется.'),if(upgrade.first['discount_percent'] is num&&upgrade.first['discount_percent']>0)text('Учтена персональная скидка ${upgrade.first['discount_percent']}%.'),action('Перейти на Премиум','checkout',id:upgrade.first['id'])])),
    ];
  }
  @override
  Widget build(BuildContext context) {
    final active = subscriptions
        .where((r) =>
            r['is_addon']!=true&&r['is_upgrade']!=true&&r['plan']!='top100'&&valid(r) &&
            ['active', 'grace', 'canceled_at_period_end'].contains(r['status']))
        .toList()
      ..sort((a, b) => until(b)!.compareTo(until(a)!));
    final baseSubscription = active.isEmpty ? null : active.first;
    final upgrades=subscriptions.where((r)=>r['is_upgrade']==true&&valid(r)&&r['status']=='active').toList();
    final Json? subscription=baseSubscription==null?null:{...baseSubscription,if(upgrades.isNotEmpty)'plan':'premium'};
    final offers = (config['offers'] as List? ?? [])
        .cast<Json>()
        .where((r) => r['product_type'] != 'boost')
        .toList();
    final price = subscription?['price'] as Json?;
    if (choosing)
      return ListView(padding: const EdgeInsets.all(20), children: [
        if(widget.api!=null)WebRewardEntry(api:widget.api!,onSelect:(target)=>onGo('reward',target)),
        if(offers.any((r)=>r['is_test']==true)) const Notice('Тестовый режим оплаты — без списания денег.',icon:'info'),
        const UiText('Ваши возможности',
            style: TextStyle(
                fontSize: 26,
                height: 33 / 26,
                letterSpacing: -.9,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        text(widget.customer ? 'Анкеты исполнителей и размещение заказов на 30 дней.' : 'Поиск заказов, публикация услуг и отклики.', color: muted),
        const SizedBox(height: 20),
        if(config['verification_status']!=null&&config['verification_status']!='passed') ...[text('Перед использованием подписки подтвердите личность.'),const SizedBox(height:8),action('Подтвердить личность','verification'),const SizedBox(height:16)],
      if(subscription?['is_ad_supported']==true)const Notice('Подписка получена за рекламу. Деньги не списывались.'),
      ...extraPurchases(context,offers),
        for (final plan in (widget.customer ? const ['customer'] : const ['standard', 'premium']))
          Builder(builder: (context) {
            final matching =
                offers.where((r) => (r['plan'] ?? 'standard') == plan).toList()..sort((a,b)=>(a['offer_kind']=='upgrade'?0:1).compareTo(b['offer_kind']=='upgrade'?0:1));
            final configured = (config['plans'] as List? ?? [])
                .where((r) => r['code'] == plan)
                .toList();
            final Json? displayPrice = matching.isNotEmpty
                ? matching.first
                : configured.isEmpty
                    ? null
                    : Json.from(configured.first);
            final offer = matching.isEmpty ? null : matching.first;
            final upgrading=offer?['offer_kind']=='upgrade';
            final downgrading=offer?['offer_kind']=='downgrade';
            return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: card([
                  Row(children: [
                    Expanded(
                        child: text(plan == 'customer' ? 'Заказчик' : plan == 'premium' ? 'Премиум' : 'Стандарт',
                            size: 16, bold: true)),
                    badge(widget.customer ? 'Заказчик' : 'Исполнитель')
                  ]),
                  const SizedBox(height: 16),
                  Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Flexible(
                            child: text(money(context, displayPrice),
                                size: 30, bold: true)),
                        const SizedBox(width: 6),
                        text(upgrading?'за оставшийся срок':downgrading?'с зачётом остатка':'/ 30 дней', color: muted)
                      ]),
                  const SizedBox(height: 8),
                  text(
                      offer == null
                          ? (displayPrice == null
                              ? 'Цена ещё не установлена'
                              : 'Оплата пока не подключена')
                          : 'Итоговая цена будет показана перед оплатой.',
                      size: 10,
                      color: muted),
                  const Divider(height: 29, thickness: 1),
                  benefit(widget.customer ? 'Просматривайте анкеты исполнителей' : 'Находите подходящие заказы'),
                  benefit(widget.customer ? 'Размещайте заказы' : 'Публикуйте услуги и откликайтесь'),
                  benefit('Общайтесь по вашим заказам'),
                  if (plan == 'premium')
                    benefit(upgrading?'Топ-100 включается сразу на оставшийся срок':'Приоритет услуг в Топ-100 на 30 дней'),
                  const SizedBox(height: 6),
                  if(offer?['discount_percent'] is num&&offer!['discount_percent']>0)text('Ваша персональная скидка ${offer['discount_percent']}% уже учтена.'),
                  if(offer?['starts_at']!=null)text('Новый период начнётся ${date(context,{'valid_until':offer!['starts_at']})}. Уже оплаченные дни сохраняются.'),
                  if(downgrading)text('Стандарт включится сразу. Остаток ${money(context, {...offer!, 'amount_minor':offer['credit_amount_minor']})} добавит ${(offer['bonus_seconds']/86400).toStringAsFixed(1)} дней. Доступ до ${date(context,offer)}. Топ-100 отключится.'),
                  if(upgrading)text('Премиум включится сразу после оплаты. Оплаченный срок сохраняется.'),
                  action(downgrading?'Перейти на Стандарт сейчас':upgrading?'Перейти на Премиум сейчас':subscription==null?'Посмотреть условия':'Продлить на 30 дней', 'checkout', id: offer?['id']),
                  const SizedBox(height: 12),
                  text(
                      'Автопродление можно отменить. Оплаченный срок сохраняется.',
                      size: 10,
                      color: muted),
                ], selected: plan == 'premium'));
          }),
        const SizedBox(height: 12),
        if(!kIsWeb||widget.api==null)Material(
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
                  onPressed: () => onGo(offers.any((r)=>r['is_test']==true)?'my-access':'restore', null),
                  child: UiText(offers.any((r)=>r['is_test']==true)?'Мой доступ':'Восстановить'))),
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
    final bases=subscriptions.where((r)=>r['is_addon']!=true&&r['is_upgrade']!=true&&r['plan']!='top100').toList();
    final known=subscription ?? (bases.isEmpty?null:bases.first);
    return ListView(padding: const EdgeInsets.all(20), children: [
      if(widget.api!=null)WebRewardEntry(api:widget.api!,onSelect:(target)=>onGo('reward',target)),
      if(subscription?['is_ad_supported']==true)const Notice('Подписка получена за рекламу. Деньги не списывались.'),
      ...extraPurchases(context,offers),
      for(final queued in bases.where((r)=>r['status']=='scheduled')) DataCard('Запланировано продление',subtitle:'${queued['plan']=='premium'?'Премиум':queued['plan']=='customer'?'Заказчик':'Стандарт'} · с ${date(context,{'valid_until':queued['valid_from']})} до ${date(context,queued)}'),
      if(subscription?['is_test']==true) const Notice('Тестовая подписка активна. Деньги не списывались.',icon:'info'),
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
        text(subscription==null?'Исполнитель · доступ не активен':'Исполнитель · '+(subscription['plan']=='premium'?'Премиум':'Стандарт'),
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
                ? 'Выберите подписку для своей роли.'
                : subscription['is_ad_supported']==true?'Оплата завершёнными просмотрами рекламы.':'Условия подтверждены платёжным провайдером.',
            size: 10,
            color: const Color(0xFFAEBFD9)),
      ], dark: true),
      const SizedBox(height: 20),
      JobaMenu([
        JobaMenuEntry(widget.customer?'Продлить доступ':'Продлить или сменить тариф','card',()=>onGo('access',null),subtitle:'Смена тарифа сразу с пересчётом остатка; продление сохраняет оплаченный срок'),
        JobaMenuEntry(
            known == null ? 'Выбрать доступ' : 'Управление подпиской',
            'card',
            () => onGo(
                known == null ? 'access' : 'manage-subscription', known?['id']),
            subtitle: known == null
                ? (widget.customer?'Анкеты исполнителей и размещение заказов':'Стандарт или Премиум для исполнителя')
                : 'Проверить или отменить автопродление'),
        if(known?['is_test']!=true&&!offers.any((r)=>r['is_test']==true)) JobaMenuEntry(
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
