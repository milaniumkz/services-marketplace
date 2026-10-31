import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/design_widgets.dart';
import '../core/l10n.dart';
import '../core/theme.dart';
import '../core/widgets.dart';

class PortfolioDetail extends StatefulWidget {
  final JobaApi api;
  final Json project;
  final String author;
  final String? avatarId;
  final VoidCallback onAuthor;
  final VoidCallback? onEdit, onDelete, onSubmit;
  const PortfolioDetail(
      {required this.api,
      required this.project,
      required this.author,
      required this.onAuthor,
      this.avatarId,
      this.onEdit,
      this.onDelete,
      this.onSubmit,
      super.key});
  @override
  State<PortfolioDetail> createState() => _PortfolioDetailState();
}

class _PortfolioDetailState extends State<PortfolioDetail> {
  int selected = 0;
  @override
  void didUpdateWidget(covariant PortfolioDetail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.project['id'] != widget.project['id']) selected = 0;
  }

  @override
  Widget build(BuildContext context) {
    final photos = List<String>.from(widget.project['photos'] as List? ?? []);
    final index = selected < photos.length ? selected : 0;
    final linked = widget.project['linked_completed_order'] == true;
    return ListView(padding: const EdgeInsets.all(20), children: [
      if (photos.isNotEmpty) ...[
        PrivatePhoto(
            api: widget.api,
            id: photos[index],
            height: 256,
            gallery: photos,
            caption: widget.project['title']),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 0; i < photos.length; i++)
            Semantics(
                selected: i == index,
                button: true,
                label: '${localize(context, 'Фото')} ${i + 1}',
                child: InkWell(
                    onTap: () => setState(() => selected = i),
                    child: SizedBox(
                        width: 44,
                        height: 44,
                        child: Center(
                            child: Container(
                                width: i == index ? 18 : 5,
                                height: 5,
                                decoration: BoxDecoration(
                                    color: i == index
                                        ? primary
                                        : const Color(0xFFBAC8DF),
                                    borderRadius: BorderRadius.circular(5)))))))
        ])
      ],
      Row(children: [
        Expanded(
            child: Text(widget.project['category_name'] ?? '',
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700, color: muted))),
        if (photos.isNotEmpty)
          TextButton(
              onPressed: () => PrivatePhoto(
                      api: widget.api,
                      id: photos[index],
                      gallery: photos,
                      caption: widget.project['title'])
                  .open(context),
              child: const UiText('Увеличить'))
      ]),
      Text(widget.project['title'] ?? '',
          style: const TextStyle(
              fontSize: 25,
              height: 1.3,
              letterSpacing: -.65,
              fontWeight: FontWeight.w700)),
      const SizedBox(height: 12),
      if (linked)
        const JobaBadge('Связано с заказом JOBA',
            background: Color(0xFFE8F6EF), foreground: Color(0xFF147657)),
      if (widget.project['status'] != 'published')
        JobaBadge(const {
              'draft': 'Черновик',
              'pending_review': 'На проверке',
              'pending_moderation': 'На проверке',
              'rejected': 'Отклонено',
              'archived': 'В архиве'
            }[widget.project['status']] ??
            'Статус недоступен'),
      const SizedBox(height: 16),
      Text(widget.project['description'] ?? '',
          style: const TextStyle(fontSize: 12, height: 1.5)),
      if (linked)
        const Padding(
            padding: EdgeInsets.only(top: 12),
            child: UiText(
                'Значок подтверждает связь с завершённым заказом, но не гарантирует качество или авторские права.',
                style: TextStyle(fontSize: 10, height: 1.4, color: muted))),
      const Padding(
          padding: EdgeInsets.symmetric(vertical: 20),
          child: Divider(height: 1)),
      Row(children: [
        JobaAvatar(
            api: widget.api,
            name: widget.author,
            id: widget.avatarId,
            size: 40),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.author,
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          const UiText('Автор проекта',
              style: TextStyle(fontSize: 10, color: muted))
        ])),
        TextButton(onPressed: widget.onAuthor, child: const UiText('Профиль'))
      ]),
      if (widget.onEdit != null)
        OutlinedButton(
            onPressed: widget.onEdit,
            child: const UiText('Редактировать проект')),
      if (widget.onSubmit != null)
        FilledButton(
            onPressed: widget.onSubmit,
            child: const UiText('Отправить на проверку')),
      if (widget.onDelete != null)
        TextButton(
            onPressed: widget.onDelete, child: const UiText('Удалить проект'))
    ]);
  }
}
