import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/currency.dart';
import '../core/design_icons.dart';
import '../core/design_widgets.dart';
import '../core/l10n.dart';
import '../core/theme.dart';
import '../core/widgets.dart';

class InviteEditor extends StatefulWidget {
  final JobaApi api;
  final String contractorId, locale;
  final VoidCallback onCreateOrder, onSent;
  final String Function(Json) period;
  const InviteEditor(
      {required this.api,
      required this.contractorId,
      required this.locale,
      required this.period,
      required this.onCreateOrder,
      required this.onSent,
      super.key});
  @override
  State<InviteEditor> createState() => _InviteEditorState();
}

class _InviteEditorState extends State<InviteEditor> {
  final message = TextEditingController();
  String? selected;
  Object? error;
  bool sending = false;
  @override
  void dispose() {
    message.dispose();
    super.dispose();
  }

  Future<void> send() async {
    if (sending || selected == null) return;
    setState(() {
      sending = true;
      error = null;
    });
    try {
      await widget.api.request('/orders/$selected/invites',
          method: 'POST',
          body: {
            'contractor_id': widget.contractorId,
            'message': message.text
          });
      if (mounted) widget.onSent();
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => ApiView(
      load: () => widget.api.request('/contractors/${widget.contractorId}'),
      builder: (context, data, reload) {
        final profile = data as Json;
        return Column(children: [
          Expanded(
              child: PagedList(
                  api: widget.api,
                  path: '/me/orders',
                  query: const {'bucket': 'open'},
                  header: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          JobaAvatar(
                              api: widget.api,
                              name: profile['display_name'] ?? '',
                              id: profile['avatar_id'],
                              size: 42),
                          const SizedBox(width: 10),
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text(profile['display_name'] ?? '',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14)),
                                Text(profile['title'] ?? '',
                                    style: const TextStyle(
                                        color: muted, fontSize: 12))
                              ]))
                        ]),
                        const SizedBox(height: 22),
                        const UiText('Выберите задачу',
                            style: TextStyle(
                                fontSize: 26,
                                height: 1.35,
                                letterSpacing: -.9,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 12),
                        const UiText(
                            'Приглашение не назначает исполнителя. Сначала он подтвердит условия.',
                            style: TextStyle(color: muted, fontSize: 12)),
                        const SizedBox(height: 20)
                      ]),
                  tile: (order) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Material(
                          color: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(
                                  color: selected == order['id']
                                      ? primary
                                      : line)),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                              onTap: sending
                                  ? null
                                  : () =>
                                      setState(() => selected = order['id']),
                              child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Row(children: [
                                    Expanded(
                                        child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                          Text(order['title'] ?? '',
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 14)),
                                          const SizedBox(height: 6),
                                          Text(
                                              [
                                                if (order['budget_amount'] !=
                                                    null)
                                                  formatMoney(
                                                      order['budget_amount'],
                                                      order['currency'],
                                                      widget.locale),
                                                widget.period(order)
                                              ].join(' · '),
                                              style: const TextStyle(
                                                  color: muted, fontSize: 12))
                                        ])),
                                    const SizedBox(width: 12),
                                    Icon(
                                        selected == order['id']
                                            ? Icons.radio_button_checked
                                            : Icons.radio_button_unchecked,
                                        color: selected == order['id']
                                            ? primary
                                            : muted,
                                        size: 22)
                                  ]))))),
                  footer: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 8),
                        const UiText('Сообщение',
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        TextField(
                            controller: message,
                            enabled: !sending,
                            minLines: 3,
                            maxLines: 5,
                            maxLength: 2000,
                            decoration: InputDecoration(
                                counterText: '',
                                hintText: localize(context, 'Сообщение'),
                                hintStyle: const TextStyle(
                                    color: muted, fontSize: 14))),
                        const SizedBox(height: 16),
                        OutlinedButton(
                            onPressed: sending ? null : widget.onCreateOrder,
                            child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  JobaIcon('plus'),
                                  SizedBox(width: 8),
                                  UiText('Создать новый заказ')
                                ])),
                        if (error != null)
                          Notice(errorText(context, error!), error: true)
                      ]))),
          Container(
              color: Colors.white,
              child: SafeArea(
                  top: false,
                  child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                              onPressed:
                                  sending || selected == null ? null : send,
                              child: UiText(sending
                                  ? 'Подождите…'
                                  : 'Отправить приглашение'))))))
        ]);
      });
}
