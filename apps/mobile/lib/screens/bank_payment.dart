import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'bank_form.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/api.dart';
import '../core/currency.dart';
import '../core/external_activity.dart';
import '../core/widgets.dart';
import '../core/theme.dart';
import '../core/l10n.dart';

class BankPaymentScreen extends StatefulWidget {
  final JobaApi api;
  final String id;
  final bool autoOpen;
  final void Function(String, String?) onGo;
  const BankPaymentScreen(
      {super.key,
      required this.api,
      required this.id,
      required this.onGo,
      this.autoOpen = false});
  @override
  State<BankPaymentScreen> createState() => _BankPaymentState();
}

class _BankPaymentState extends State<BankPaymentScreen>
    with WidgetsBindingObserver {
  Json? payment;
  Object? error;
  bool loading = false, opening = false, autoOpened = false;
  Timer? timer;
  bool get pending =>
      payment == null ||
      ['registering', 'pending'].contains(payment!['status']);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    load();
    timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (pending &&
          (WidgetsBinding.instance.lifecycleState == null ||
              WidgetsBinding.instance.lifecycleState ==
                  AppLifecycleState.resumed)) load();
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) load();
  }

  Future<void> load({bool cancel = false}) async {
    if (loading) return;
    loading = true;
    final api = widget.api, generation = api.sessionGeneration;
    try {
      final result = await api.request(
          '/billing/vtb/payments/${widget.id}${cancel ? '/cancel' : ''}',
          method: cancel ? 'POST' : 'GET');
      if (!mounted || api != widget.api || generation != api.sessionGeneration)
        return;
      setState(() {
        payment = Json.from(result);
        error = null;
      });
      if (widget.autoOpen && !autoOpened && payment!['payment_url'] is String) {
        autoOpened = true;
        final url = payment!['payment_url'] as String;
        await openBank(url);
      }
    } catch (e) {
      if (mounted && api == widget.api && generation == api.sessionGeneration)
        setState(() => error = e);
    } finally {
      loading = false;
    }
  }

  Future<void> openBank(String value) async {
    if (opening) return;
    opening = true;
    try {
      final uri = Uri.parse(value);
      if (!trustedBankEntry(uri))
        throw ApiException(
            'PAYMENT_URL_INVALID', 'Некорректный адрес банковской страницы');
      // Capture the root navigator before replacing the auto-open route.
      final navigator = Navigator.of(context);
      final api = widget.api,
          generation = api.sessionGeneration,
          id = widget.id;
      if (widget.autoOpen) widget.onGo('bank-payment', id);
      final opened = kIsWeb
          ? await launchUrl(uri, webOnlyWindowName: '_self')
          : await withExternalActivity(() async {
              await navigator.push<bool>(MaterialPageRoute(
                  builder: (_) => BankForm(
                      entry: uri,
                      paymentId: id,
                      testMode: payment?['bank_test'] == true)));
              return true;
            });
      if (!kIsWeb &&
          mounted &&
          api == widget.api &&
          generation == api.sessionGeneration) {
        // Always ask the server; neither a URL redirect nor closing the form is proof.
        unawaited(load());
      }
      if (!opened)
        throw ApiException('PAYMENT_OPEN_FAILED',
            'Не удалось открыть банк. Нажмите «Перейти к оплате» ещё раз.');
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      opening = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = payment, status = p?['status'];
    final title = status == 'completed'
        ? 'Оплата подтверждена'
        : status == 'resolution_required'
            ? 'Оплата требует сверки'
            : status == 'refunded'
                ? 'Оплата возвращена'
                : status == 'canceled'
                    ? 'Оплата отменена'
                    : status == 'declined'
                        ? 'Банк отклонил оплату'
                        : status == 'expired'
                            ? 'Время оплаты истекло'
                            : (p?['provider']=='bcc'?'Оплата в БЦК':'Оплата в ВТБ');
    return ListView(padding: const EdgeInsets.all(20), children: [
      Text(title,
          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
      if (p == null && error == null)
        const Center(child: CircularProgressIndicator()),
      if (p != null) ...[
        if (p['bank_test'] == true)
          const Notice(
              'Тестовый шлюз банка. Используйте только тестовые карты: реальные деньги не списываются.'),
        DataCard('${p['title'] ?? 'Услуга JOBA'}',
            subtitle: formatMoney(p['amount_minor'], p['currency'], 'ru')),
        if (p['message'] != null) Notice(p['message']),
        if (status == 'completed')
          const Notice(
              'Банк подтвердил операцию. Услуга активирована по показанным условиям.'),
        if (pending)
          const Notice(
              'Сумма и назначение сохранены. После оплаты вернитесь в JOBA: результат проверяется напрямую в банке, повторно оплачивать не нужно.'),
        if (p['payment_url'] is String)
          FilledButton(
              onPressed: opening ? null : () => openBank(p['payment_url']),
              child: const Text('Перейти к оплате в банке')),
        if (pending)
          OutlinedButton(
              onPressed: loading ? null : () => load(),
              child: const Text('Проверить оплату')),
        if (p['can_cancel'] == true)
          TextButton(
              onPressed: loading ? null : () => load(cancel: true),
              child: const Text('Отменить неоплаченный заказ')),
        if (status == 'completed' && p['benefit'] == 'boost')
          FilledButton(
              onPressed: () => widget.onGo('promotion-pending', p['boost_id']),
              child: const Text('Моё продвижение')),
        FilledButton(
            onPressed: () => widget.onGo('my-access', null),
            child: Text(pending ? 'Вернуться в JOBA' : 'Мой доступ')),
        if (status == 'resolution_required' || status == 'refunded')
          TextButton(
              onPressed: () => widget.onGo('refunds', null),
              child: const Text('Платежи и возвраты')),
      ],
      if (error != null) ...[
        Notice(errorText(context, error!), error: true),
        OutlinedButton(
            onPressed: loading ? null : () => load(),
            child: const Text('Повторить проверку'))
      ],
    ]);
  }
}

class PendingBankPayments extends StatelessWidget {
  final JobaApi api;
  final void Function(String, String?) onGo;
  const PendingBankPayments({super.key, required this.api, required this.onGo});
  @override
  Widget build(BuildContext context) => FutureBuilder<dynamic>(
      future: api.request('/billing/vtb/pending'),
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data is! Map) return const SizedBox.shrink();
        return Column(children: [
          for (final row in items(data))
            Card(
                child: ListTile(
                    title: Text(row['status'] == 'resolution_required'
                        ? 'Проверить оплаченную услугу'
                        : 'Незавершённая банковская оплата'),
                    subtitle: Text(
                        '${row['title']} · ${formatMoney(row['amount_minor'], row['currency'], 'ru')}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => onGo('bank-payment', row['id'])))
        ]);
      });
}
