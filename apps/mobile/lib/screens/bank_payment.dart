import 'dart:async';
import 'package:flutter/material.dart';
import 'bank_form.dart';
import '../core/api.dart';
import '../core/currency.dart';
import '../core/external_activity.dart';
import '../core/widgets.dart';
import '../core/theme.dart';
import '../core/l10n.dart';

Future<void> openHostedBankCheckout(BuildContext context,JobaApi api,Json payment) async {
  if(['completed','sandbox_confirmed'].contains(payment['status']))return;
  final entry=Uri.tryParse('${payment['payment_url']??''}');
  if(entry==null||!trustedBankEntry(entry))throw ApiException('PAYMENT_URL_INVALID','Не удалось открыть банковскую страницу. Обновите условия оплаты.');
  final generation=api.sessionGeneration,owner=api.session?['user']?['id'];
  await withExternalActivity(()=>Navigator.of(context).push<bool>(MaterialPageRoute(builder:(_)=>BankForm(entry:entry,paymentId:payment['id'],testMode:payment['bank_test']==true))));
  if(!api.disposed&&api.authenticated&&api.sessionGeneration==generation&&api.session?['user']?['id']==owner)await api.request('/billing/${payment['provider']=='bcc'?'bcc':'vtb'}/payments/${payment['id']}');
}

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
  bool cancelAfterLoad=false;
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
    if (loading) { if(cancel)cancelAfterLoad=true; return; }
    setState(()=>loading=true);
    final api = widget.api, generation = api.sessionGeneration;
    String? bankUrl;
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
      if(widget.autoOpen&&!autoOpened&&payment!['payment_url'] is! String){WidgetsBinding.instance.addPostFrameCallback((_){if(mounted&&api==widget.api&&generation==api.sessionGeneration)widget.onGo(payment!['status']=='completed'?'my-access':'checkout',null);});}
      if (!cancelAfterLoad && !cancel && widget.autoOpen && !autoOpened && payment!['payment_url'] is String) {
        autoOpened = true;
        bankUrl = payment!['payment_url'] as String;
      }
    } catch (e) {
      if (mounted && api == widget.api && generation == api.sessionGeneration)
        setState(() => error = e);
    } finally {
      if(mounted)setState(()=>loading=false);else loading=false;
    }
    if(cancelAfterLoad&&mounted&&api==widget.api&&generation==api.sessionGeneration){cancelAfterLoad=false;await load(cancel:true);return;}
    if (bankUrl != null &&
        mounted &&
        api == widget.api &&
        generation == api.sessionGeneration) {
      await openBank(bankUrl);
    }
  }

  Future<void> openBank(String value) async {
    if (opening) return;
    setState(()=>opening = true);
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

      await withExternalActivity(() async {
        await navigator.push<bool>(MaterialPageRoute(
            builder: (_) => BankForm(
                entry: uri,
                paymentId: id,
                testMode: payment?['bank_test'] == true)));
      });
      if (mounted && api == widget.api && generation == api.sessionGeneration) {
        // A frame return only requests verification; the bank proves the payment.
        await load();
        if(widget.autoOpen&&mounted&&generation==api.sessionGeneration)widget.onGo(payment?['benefit']=='boost'?'promotion-history':'my-access',null);
      }
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if(mounted)setState(()=>opening = false);else opening=false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if(widget.autoOpen)return Center(child:error==null?const CircularProgressIndicator():Column(mainAxisSize:MainAxisSize.min,children:[Notice(errorText(context,error!),error:true),TextButton(onPressed:()=>widget.onGo('checkout',null),child:const Text('Вернуться к оплате'))]));
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
                            : (p?['provider'] == 'bcc'
                                ? 'Оплата в БЦК'
                                : 'Оплата в ВТБ');
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
              child: Text(autoOpened?'Продолжить оплату в банке':'Перейти к оплате в банке')),
        if (pending)
          OutlinedButton(
              onPressed: loading ? null : () => load(),
              child: const Text('Проверить оплату')),
        if (p['can_cancel'] == true)
          TextButton(
              onPressed: loading ? null : () => load(cancel: true),
              child: const Text('Отменить неоплаченный заказ')),
        if(p['can_retry']==true)
          FilledButton(onPressed:loading?null:()=>widget.onGo(p['benefit']=='boost'?'promotion':'checkout',null),child:const Text('Повторить оплату')),
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
