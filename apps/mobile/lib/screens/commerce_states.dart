import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/commerce_gateway.dart';
import '../core/currency.dart';
import '../core/design_states.dart';
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
  bool busy = false, accepted = false;
  Object? error;
  String? selected;
  Future<void> run(Future<void> Function() job) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await job();
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

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
                final receipts = await widget.gateway.restore();
                for (final r in receipts) {
                  await widget.api
                      .request('/billing/restore', method: 'POST', body: r);
                }
                if (mounted) widget.onGo('my-access', null);
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
                        ?.isAfter(DateTime.now()) ==
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
                    ? 'Найти специалиста'
                    : expired
                        ? 'Мой доступ'
                        : 'Проверить статус',
                valid
                    ? () => widget.onGo('catalog', null)
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
          builder: (context, r, reload) => panel(
              'play',
              'Больше возможностей',
              'Доступ выдаётся только после подтверждения рекламной сети.',
              'Посмотреть ролик',
              () => run(() async {
                    try {
                      final session = await widget.api.request(
                          '/ads/reward-sessions',
                          method: 'POST',
                          body: {'placement': 'access'});
                      final completed =
                          await widget.gateway.playReward(session);
                      await widget.api.request(
                          '/ads/reward-sessions/${session['id']}/outcome',
                          method: 'POST',
                          body: {
                            'outcome': completed ? 'completed' : 'no_fill'
                          });
                      if (mounted)
                        widget.onGo(
                            completed ? 'reward-pending' : 'reward-nofill',
                            session['id']);
                    } on ApiException catch (e) {
                      if (['REWARDED_DISABLED', 'PROVIDER_UNAVAILABLE']
                          .contains(e.code)) {
                        if (mounted) widget.onGo('reward-nofill', null);
                        return;
                      }
                      rethrow;
                    }
                  }),
              secondary: 'Мой доступ',
              onSecondary: () => widget.onGo('my-access', null)));
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
              const UiHeading('Всё под контролем'),
              if (r == null)
                const Notice('Подписка не найдена.')
              else ...[
                DataCard('Подписка JOBA',
                    subtitle: '${r['status']} · ${r['valid_until']}',
                    footer: Text(money(r['price']))),
                const Notice(
                    'Отключение автопродления не закрывает уже оплаченный срок.'),
                FilledButton(
                    onPressed: busy
                        ? null
                        : () => run(() async {
                              await widget.gateway.manage(r);
                              reload();
                            }),
                    child: const UiText('Управлять подпиской')),
                OutlinedButton(
                    onPressed: () =>
                        widget.onGo('subscription-canceled', r['id']),
                    child: const UiText('Проверить продление'))
              ],
              if (error != null) Notice(errorText(context, error!), error: true)
            ]);
          });
    return ApiView(
        load: () => widget.api.request('/billing/offers'),
        builder: (context, data, reload) {
          final offers =
              items(data).where((r) => r['product_type'] != 'boost').toList();
          final chosen =
              offers.where((r) => r['id'] == (selected ?? widget.id)).toList();
          final offer = chosen.isEmpty
              ? (offers.isEmpty ? null : offers.first)
              : chosen.first;
          return Column(children: [
            Expanded(
                child: ListView(padding: const EdgeInsets.all(20), children: [
              const UiHeading(
                  'Подписка JOBA', 'Полный доступ для обеих ролей.'),
              for (final r in offers)
                ListTile(
                    onTap:
                        busy ? null : () => setState(() => selected = r['id']),
                    leading: Icon(
                        offer?['id'] == r['id']
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        color: primary),
                    title: Text('${r['title'] ?? r['product_id']}'),
                    subtitle: Text('${money(r)} · ${r['period'] ?? ''}')),
              if (offer == null)
                const Notice('Действующие предложения пока недоступны.'),
              const Notice(
                  'Доступ активируется только после серверного подтверждения оплаты. Условия и итоговая сумма показываются платёжным провайдером.'),
              CheckboxListTile(
                  value: accepted,
                  onChanged:
                      busy ? null : (v) => setState(() => accepted = v == true),
                  title: const UiText('Ознакомился с условиями подписки.')),
              TextButton(
                  onPressed: () => widget.onGo('legal', null),
                  child: const UiText('Условия подписки')),
              TextButton(
                  onPressed: () => widget.onGo('restore', null),
                  child: const UiText('Восстановить покупку')),
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
                                : () => run(() async {
                                      final receipt =
                                          await widget.gateway.purchase(offer);
                                      final result = await widget.api.request(
                                          '/billing/verify-purchase',
                                          method: 'POST',
                                          body: receipt);
                                      if (mounted)
                                        widget.onGo(
                                            result['pending'] == true
                                                ? 'payment-pending'
                                                : 'my-access',
                                            result['check']?['id']);
                                    }),
                            child: const UiText('Продолжить оплату')))))
          ]);
        });
  }
}
