import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/api.dart';
import '../core/l10n.dart';
import '../core/widgets.dart';
import 'referral_terms.dart';

class ReferralRewardCard extends StatefulWidget {
  final Json reward;
  final Future<void> Function() onActivate;
  final DateTime Function() now;
  const ReferralRewardCard(
      {required this.reward,
      required this.onActivate,
      this.now = DateTime.now,
      super.key});
  @override
  State<ReferralRewardCard> createState() => _ReferralRewardCardState();
}

class _ReferralRewardCardState extends State<ReferralRewardCard>
    with WidgetsBindingObserver {
  Timer? _expiry;
  bool _busy = false, _redeemed = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _schedule();
  }

  @override
  void didUpdateWidget(covariant ReferralRewardCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reward['id'] != widget.reward['id']) _redeemed = false;
    _schedule();
  }

  void _schedule() {
    _expiry?.cancel();
    if (!referralRewardAvailable(widget.reward, widget.now()) || _redeemed)
      return;
    final remaining =
        DateTime.parse(widget.reward['expires_at']).difference(widget.now());
    _expiry = Timer(
        remaining > const Duration(days: 1)
            ? const Duration(days: 1)
            : remaining, () {
      if (!mounted) return;
      setState(() {});
      _schedule();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() {});
      _schedule();
    }
  }

  @override
  void dispose() {
    _expiry?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _activate() async {
    if (_busy ||
        _redeemed ||
        !referralRewardAvailable(widget.reward, widget.now())) return;
    setState(() => _busy = true);
    try {
      await widget.onActivate();
      if (mounted) setState(() => _redeemed = true);
    } catch (error) {
      if (mounted)
        await showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
                  title: const UiText('Не удалось выполнить действие'),
                  content: Text(errorText(context, error)),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const UiText('Понятно'))
                  ],
                ));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _schedule();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final reward = widget.reward;
    final expiry = DateTime.tryParse('${reward['expires_at'] ?? ''}');
    final available =
        !_redeemed && referralRewardAvailable(reward, widget.now());
    final redeemed = _redeemed || reward['status'] == 'redeemed';
    final expired = reward['status'] == 'available' &&
        expiry != null &&
        !expiry.isAfter(widget.now()) &&
        !redeemed;
    return DataCard('Награда',
        translateTitle: true,
        subtitle:
            referralTerms(context, (reward['policy_snapshot'] as Json?) ?? {}) +
                '\n' +
                localize(context, 'Активировать до') +
                ': ' +
                (expiry == null
                    ? '—'
                    : DateFormat('dd.MM.yyyy HH:mm').format(expiry.toLocal())),
        status: localize(
            context,
            redeemed
                ? 'Использована'
                : expired
                    ? 'Срок истёк'
                    : available
                        ? 'Доступна'
                        : 'Недоступно'),
        footer: available
            ? FilledButton(
                onPressed: _busy ? null : _activate,
                child: UiText(_busy ? 'Загрузка…' : 'Активировать'))
            : null);
  }
}
