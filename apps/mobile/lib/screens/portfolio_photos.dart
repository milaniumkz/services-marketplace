import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/design_icons.dart';
import '../core/design_widgets.dart';
import '../core/l10n.dart';
import '../core/theme.dart';
import '../core/widgets.dart';

class PortfolioPhotos extends StatefulWidget {
  final JobaApi api;
  final String id;
  final VoidCallback onDone;
  const PortfolioPhotos(
      {required this.api, required this.id, required this.onDone, super.key});
  @override
  State<PortfolioPhotos> createState() => _PortfolioPhotosState();
}

class _PortfolioPhotosState extends State<PortfolioPhotos> {
  List<String>? photos;
  String? cover;
  int index = 0;
  bool busy = false;
  Object? error;
  Json? record;
  Future<void> save() async {
    if (busy || record == null) return;
    setState(() => busy = true);
    try {
      await widget.api.request('/me/portfolio-projects/${widget.id}',
          method: 'PATCH',
          body: {
            'expected_version': record!['version'],
            'upload_ids': photos,
            'cover_id': cover
          });
      if (mounted) widget.onDone();
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> crop() async {
    if (busy || photos == null || photos!.isEmpty) return;
    setState(() => busy = true);
    try {
      final result = await widget.api.request('/uploads/${photos![index]}/crop',
          method: 'POST', body: {'mode': 'square'});
      if (mounted)
        setState(() {
          final old = photos![index];
          photos![index] = result['id'];
          if (cover == old) cover = result['id'];
          error = null;
        });
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ApiView(
      load: () => widget.api.request('/me/portfolio-projects/${widget.id}'),
      builder: (context, r, reload) {
        record ??= r;
        photos ??= (r['photos'] as List).cast<String>().toList();
        cover ??= r['cover_id'] ?? (photos!.isEmpty ? null : photos!.first);
        return Column(children: [
          Expanded(
              child: ListView(padding: const EdgeInsets.all(20), children: [
            const UiHeading(
                'Выберите обложку', 'Порядок фотографий можно менять.'),
            if (photos!.isNotEmpty) ...[
              PrivatePhoto(
                  key: ValueKey(photos![index]),
                  api: widget.api,
                  id: photos![index],
                  height: 220,
                  gallery: photos!),
              const SizedBox(height: 12),
              Row(children: [
                if (cover == photos![index])
                  const JobaBadge('Обложка',
                      background: Color(0xFFE8F5EF),
                      foreground: Color(0xFF147657)),
                const Spacer(),
                Text('${index + 1} / ${photos!.length}',
                    style: const TextStyle(fontSize: 12, color: muted)),
              ]),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(
                    child: OutlinedButton(
                        onPressed: busy ? null : crop,
                        child: const UiText('Обрезать'))),
                const SizedBox(width: 10),
                Expanded(
                    child: FilledButton(
                        style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFFBECEC),
                            foregroundColor: const Color(0xFFB73838)),
                        onPressed: busy
                            ? null
                            : () => setState(() {
                                  final old = photos!.removeAt(index);
                                  if (cover == old)
                                    cover =
                                        photos!.isEmpty ? null : photos!.first;
                                  index = 0;
                                }),
                        child: const UiText('Убрать фото'))),
              ]),
              const SizedBox(height: 18),
            ],
            const UiText('Порядок показа',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            if (photos!.isEmpty)
              const Notice(
                  'Фотографий пока нет. Добавьте их в редакторе проекта.'),
            if (photos!.isNotEmpty)
              Container(
                  decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: line),
                      borderRadius: BorderRadius.circular(16)),
                  clipBehavior: Clip.antiAlias,
                  child: Column(children: [
                    for (final e in photos!.indexed) ...[
                      if (e.$1 > 0) const Divider(height: 1, color: line),
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 6),
                        onTap: busy ? null : () => setState(() => index = e.$1),
                        leading: const JobaIcon('image'),
                        title: UiText(
                            '${localize(context, 'Фото')} ${e.$1 + 1}',
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w700)),
                        subtitle: Text(
                            '${e.$1 + 1}${cover == e.$2 ? ' · ${localize(context, 'Обложка')}' : ''}',
                            style: const TextStyle(fontSize: 10, color: muted)),
                        trailing: PopupMenuButton<String>(
                            enabled: !busy,
                            tooltip: localize(context, 'Действия с фото'),
                            icon: const JobaIcon('right', size: 18),
                            itemBuilder: (_) => [
                                  PopupMenuItem(
                                      value: 'cover',
                                      child: const UiText('Сделать обложкой')),
                                  if (e.$1 > 0)
                                    const PopupMenuItem(
                                        value: 'up', child: UiText('Выше')),
                                  if (e.$1 < photos!.length - 1)
                                    const PopupMenuItem(
                                        value: 'down', child: UiText('Ниже')),
                                ],
                            onSelected: (action) => setState(() {
                                  if (action == 'cover') {
                                    cover = e.$2;
                                    index = e.$1;
                                    return;
                                  }
                                  final next = e.$1 + (action == 'up' ? -1 : 1);
                                  photos!.removeAt(e.$1);
                                  photos!.insert(next, e.$2);
                                  index = next;
                                })),
                      ),
                    ]
                  ])),
            const Notice('Фотографии проходят проверку до публикации.'),
            if (error != null) ...[
              Notice(errorText(context, error!), error: true),
              if (error is ApiException &&
                  (error as ApiException).code == 'STATE_CONFLICT')
                TextButton(
                    onPressed: () => setState(() {
                          photos = null;
                          cover = null;
                          record = null;
                          index = 0;
                          error = null;
                          reload();
                        }),
                    child: const UiText('Загрузить актуальную версию'))
            ]
          ])),
          Container(
              decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: line))),
              child: SafeArea(
                  top: false,
                  child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                      child: SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                              onPressed: busy ? null : save,
                              child: const UiText('Готово'))))))
        ]);
      });
}
