import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/design_icons.dart';
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
                  id: photos![index]),
              Row(children: [
                Expanded(child: Text('${index + 1} / ${photos!.length}')),
                TextButton(
                    onPressed: busy
                        ? null
                        : () async {
                            setState(() => busy = true);
                            try {
                              final result = await widget.api.request(
                                  '/uploads/${photos![index]}/crop',
                                  method: 'POST',
                                  body: {'mode': 'square'});
                              if (mounted)
                                setState(() {
                                  final old = photos![index];
                                  photos![index] = result['id'];
                                  if (cover == old) cover = result['id'];
                                });
                            } catch (e) {
                              if (mounted) setState(() => error = e);
                            } finally {
                              if (mounted) setState(() => busy = false);
                            }
                          },
                    child: const UiText('Обрезать')),
                TextButton(
                    onPressed: busy
                        ? null
                        : () => setState(() {
                              final old = photos!.removeAt(index);
                              if (cover == old)
                                cover = photos!.isEmpty ? null : photos!.first;
                              index = 0;
                            }),
                    child: const UiText('Убрать фото'))
              ])
            ],
            const UiHeading('Порядок показа'),
            for (final e in photos!.indexed)
              Card(
                  child: ListTile(
                      onTap: () => setState(() => index = e.$1),
                      title: Text('${localize(context, 'Фото')} ${e.$1 + 1}'),
                      leading: IconButton(
                          tooltip: localize(context, 'Обложка'),
                          onPressed:
                              busy ? null : () => setState(() => cover = e.$2),
                          icon: Icon(
                              cover == e.$2
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_unchecked,
                              color: primary)),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(
                            tooltip: localize(context, 'Выше'),
                            onPressed: busy || e.$1 == 0
                                ? null
                                : () => setState(() {
                                      photos!.removeAt(e.$1);
                                      photos!.insert(e.$1 - 1, e.$2);
                                      index = e.$1 - 1;
                                    }),
                            icon: const JobaIcon('up')),
                        IconButton(
                            tooltip: localize(context, 'Ниже'),
                            onPressed: busy || e.$1 == photos!.length - 1
                                ? null
                                : () => setState(() {
                                      photos!.removeAt(e.$1);
                                      photos!.insert(e.$1 + 1, e.$2);
                                      index = e.$1 + 1;
                                    }),
                            icon: const JobaIcon('down'))
                      ]))),
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
                      child: FilledButton(
                          onPressed: busy ? null : save,
                          child: const UiText('Готово')))))
        ]);
      });
}
