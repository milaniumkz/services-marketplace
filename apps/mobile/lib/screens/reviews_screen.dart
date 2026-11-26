import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/api.dart';
import '../core/l10n.dart';
import '../core/widgets.dart';

class ReviewsScreen extends StatefulWidget {
  final JobaApi api;
  final String userId;
  final bool own;
  final ValueChanged<String> onReview;
  const ReviewsScreen(
      {required this.api,
      required this.userId,
      required this.own,
      required this.onReview,
      super.key});
  @override
  State<ReviewsScreen> createState() => _ReviewsScreenState();
}

class _ReviewsScreenState extends State<ReviewsScreen> {
  bool sent = false;
  @override
  void didUpdateWidget(covariant ReviewsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId || !widget.own) sent = false;
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        if (widget.own)
          Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Expanded(
                    child: ChoiceChip(
                        label: const UiText('Отзывы обо мне'),
                        selected: !sent,
                        onSelected: (_) => setState(() => sent = false))),
                const SizedBox(width: 8),
                Expanded(
                    child: ChoiceChip(
                        label: const UiText('Мои отзывы'),
                        selected: sent,
                        onSelected: (_) => setState(() => sent = true))),
              ])),
        Expanded(
            child: PagedList(
                key: ValueKey('${widget.userId}:$sent'),
                api: widget.api,
                path: '/users/${widget.userId}/reviews',
                query: sent ? {'direction': 'sent'} : {},
                empty: sent
                    ? 'Вы ещё не отправляли отзывы.'
                    : 'Опубликованных отзывов пока нет.',
                tile: (r) {
                  final hidden = ['quarantined', 'hidden', 'rejected']
                      .contains(r['moderation_status']);
                  final waiting = r['status'] == 'sealed' && !hidden;
                  final until =
                      DateTime.tryParse('${r['publish_after'] ?? ''}');
                  return DataCard('${r['rating']} ★',
                      subtitle: r['text'] ?? '',
                      status: hidden
                          ? (r['moderation_status'] == 'quarantined'
                              ? 'На проверке'
                              : r['moderation_status'] == 'rejected'
                                  ? 'Отклонён'
                                  : 'Скрыт')
                          : waiting
                              ? 'Ожидает публикации'
                              : r['status'] == 'published'
                                  ? 'Опубликован'
                                  : 'Сохранён',
                      onTap: sent ? () => widget.onReview(r['order_id']) : null,
                      footer: waiting
                          ? Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const UiText(
                                        'Отзыв сохранён и виден вам. Другой участник увидит его после встречного отзыва или окончания срока ожидания.'),
                                    if (until != null)
                                      Text(
                                          '${localize(context, 'Срок ожидания до')}: ${DateFormat('dd.MM.yyyy HH:mm').format(until.toLocal())}'),
                                  ]))
                          : null);
                }))
      ]);
}
