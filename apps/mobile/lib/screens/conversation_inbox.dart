import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/api.dart';
import '../core/design_icons.dart';
import '../core/design_widgets.dart';
import '../core/l10n.dart';
import '../core/theme.dart';
import '../core/widgets.dart';

class ConversationInbox extends StatefulWidget {
  final JobaApi api;
  final int revision;
  final void Function(String route, String? id) onGo;
  const ConversationInbox(
      {required this.api,
      required this.onGo,
      required this.revision,
      super.key});
  @override
  State<ConversationInbox> createState() => _ConversationInboxState();
}

class _ConversationInboxState extends State<ConversationInbox> {
  final search = TextEditingController();
  Timer? debounce;
  bool support = false;
  String query = '';
  @override
  void dispose() {
    debounce?.cancel();
    search.dispose();
    super.dispose();
  }

  String time(dynamic value) {
    final parsed = DateTime.tryParse('$value')?.toLocal();
    if (parsed == null) return '';
    final now = DateTime.now();
    return DateFormat(
            parsed.year == now.year &&
                    parsed.month == now.month &&
                    parsed.day == now.day
                ? 'HH:mm'
                : 'd MMM',
            Localizations.localeOf(context).languageCode)
        .format(parsed);
  }

  Widget tile(Json r, {bool help = false}) {
    final peer = r['peer'] as Json?;
    final message = r['last_message'] as Json?;
    final title = help
        ? localize(context, 'Поддержка JOBA')
        : '${peer?['display_name'] ?? localize(context, 'Участник заказа')}';
    final preview = help
        ? '${r['subject'] ?? ''}'
        : message == null
            ? localize(context, 'Начните разговор')
            : message['tombstone'] == true
                ? localize(context, 'Сообщение удалено')
                : message['hidden'] == true
                    ? localize(context, 'Сообщение временно скрыто')
                    : '${message['text'] ?? ''}'.isNotEmpty
                        ? '${message['text']}'
                        : message['has_attachments'] == true
                            ? localize(context, 'Вложение')
                            : '';
    return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Material(
            color: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: line)),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
                onTap: () =>
                    widget.onGo(help ? 'support-chat' : 'chat', r['id']),
                child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(children: [
                      if (help)
                        Container(
                            width: 52,
                            height: 48,
                            decoration: BoxDecoration(
                                color: const Color(0xFFEFF4FD),
                                borderRadius: BorderRadius.circular(15)),
                            child: const JobaIcon('help'))
                      else
                        JobaAvatar(
                            api: widget.api,
                            name: title,
                            id: peer?['avatar_id']),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Row(children: [
                              Expanded(
                                  child: Text(title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700))),
                              if (!help)
                                Text(time(message?['created_at']),
                                    style: const TextStyle(
                                        fontSize: 10,
                                        color: Color(0xFF627187))),
                            ]),
                            if (!help) ...[
                              const SizedBox(height: 4),
                              Text([r['order_title'], if(r['order_status'] != null) const {'open':'Открыт','assigned':'Исполнитель выбран','in_progress':'В работе','completed':'Завершён','completion_requested':'Ожидает подтверждения'}[r['order_status']] ?? '${r['order_status']}'].where((v)=>v!=null && v.toString().isNotEmpty).join(' · '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 10, color: primary))
                            ],
                            const SizedBox(height: 8),
                            Text(preview,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 12, color: Color(0xFF627187))),
                          ])),
                      if ((r['unread_count'] as num? ?? 0) > 0) ...[
                        const SizedBox(width: 10),
                        JobaBadge('${r['unread_count']}')
                      ],
                    ])))));
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const UiText('Сообщения',
                  style: TextStyle(
                      fontSize: 28, height: 1.25,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -.9)),
              const SizedBox(height: 20),
              TextField(
                  controller: search,
                  onChanged: (value) {
                    debounce?.cancel();
                    debounce = Timer(const Duration(milliseconds: 300), () {
                      if (mounted) setState(() => query = value.trim());
                    });
                  },
                  decoration: InputDecoration(
                      hintText: localize(context, 'Поиск по перепискам'),
                      prefixIcon: const Padding(
                          padding: EdgeInsets.all(14),
                          child: JobaIcon('search')),
                      filled: true,
                      fillColor: canvas,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: line)))),
              const SizedBox(height: 12),
              Row(children: [
                for (final entry
                    in const {false: 'Заказы', true: 'Поддержка'}.entries)
                  Padding(
                      padding: const EdgeInsets.only(right: 22),
                      child: InkWell(
                          onTap: () => setState(() => support = entry.key),
                          child: Container(
                              constraints: const BoxConstraints(minHeight: 48),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                  border: Border(
                                      bottom: BorderSide(
                                          color: support == entry.key
                                              ? primary
                                              : Colors.transparent,
                                          width: 2))),
                              child: UiText(entry.value,
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: support == entry.key
                                          ? FontWeight.w700
                                          : FontWeight.w400,
                                      color: support == entry.key
                                          ? primary
                                          : const Color(0xFF627187))))))
              ]),
              const Divider(height: 1, color: line),
            ])),
        Expanded(
            child: PagedList(
                key: ValueKey('inbox:$support:$query:${widget.revision}'),
                api: widget.api,
                path: support ? '/me/support-threads' : '/me/conversations',
                query: {if (query.isNotEmpty) 'q': query},
                empty: query.isEmpty
                    ? 'Переписок пока нет'
                    : 'Переписки не найдены',
                tile: (r) => tile(r, help: support),
                footer: support || query.isNotEmpty
                    ? null
                    : ApiView(
                        load: () => widget.api.request('/me/support-threads',
                            query: {'limit': '3'}),
                        builder: (context, data, reload) => Column(children: [
                              for (final r in items(data)) tile(r, help: true),
                              if (data['meta']?['next_cursor'] != null)
                                TextButton(
                                    onPressed: () =>
                                        setState(() => support = true),
                                    child: const UiText('Все обращения'))
                            ])))),
      ]);
}
