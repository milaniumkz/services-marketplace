import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/design_icons.dart';
import '../core/design_widgets.dart';
import '../core/l10n.dart';
import '../core/resource_picker.dart';
import '../core/reference_picker.dart';
import '../core/theme.dart';
import '../core/widgets.dart';

/// Keeps the editable draft through failed saves and moderation requests.
class PortfolioEditor extends StatefulWidget {
  final JobaApi api;
  final String? id;
  final Future<Json?> Function() pickPhoto;
  final void Function(String route, String id) onGo;
  const PortfolioEditor(
      {required this.api,
      required this.pickPhoto,
      required this.onGo,
      this.id,
      super.key});
  @override
  State<PortfolioEditor> createState() => _PortfolioEditorState();
}

class _PortfolioEditorState extends State<PortfolioEditor> {
  final form = GlobalKey<FormState>();
  final title = TextEditingController(), description = TextEditingController();
  Json? record;
  List<String> photos = [];
  String? cover, category, orderId, orderLabel;
  bool initialized = false, rights = false, busy = false;
  Object? error;
  @override
  void dispose() {
    title.dispose();
    description.dispose();
    super.dispose();
  }

  Future<Json> persist() async {
    final fields = <String, dynamic>{
      'title': title.text.trim(),
      'description': description.text.trim(),
      'category_id': category,
      'order_id': orderId,
      'rights_confirmed': rights,
    };
    // Creation has no upload fields; save its returned version before attaching.
    if (record == null) {
      record = Json.from(await widget.api
          .request('/me/portfolio-projects', method: 'POST', body: fields));
    }
    record = Json.from(await widget.api.request(
        '/me/portfolio-projects/${record!['id']}',
        method: 'PATCH',
        body: {
          ...fields,
          'expected_version': record!['version'],
          'upload_ids': photos,
          if (cover != null) 'cover_id': cover
        }));
    return record!;
  }

  Future<void> run(Future<void> Function() task, {bool validate = true}) async {
    if (busy || (validate && !form.currentState!.validate())) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await task();
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save({bool submit = false, bool openPhotos = false}) =>
      run(() async {
        final saved = await persist();
        if (submit) {
          record = Json.from(await widget.api.request(
              '/me/portfolio-projects/${saved['id']}/submit',
              method: 'POST',
              body: {'expected_version': saved['version']}));
        }
        if (mounted)
          widget.onGo(
              submit
                  ? 'portfolio-pending'
                  : openPhotos
                      ? 'portfolio-photos'
                      : 'portfolio-project',
              saved['id']);
      });

  Widget label(String text) => Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: UiText(text,
          style: const TextStyle(
              fontSize: 12, fontWeight: FontWeight.w700, height: 1.45)));

  @override
  Widget build(BuildContext context) => ApiView(
      load: () => Future.wait([
            widget.api.request('/catalog/categories'),
            (record?['id'] ?? widget.id) == null
                ? Future.value(null)
                : widget.api.request(
                    '/me/portfolio-projects/${record?['id'] ?? widget.id}')
          ]),
      builder: (context, data, reload) {
        if (!initialized) {
          record = data[1] == null ? null : Json.from(data[1]);
          title.text = record?['title'] ?? '';
          description.text = record?['description'] ?? '';
          category = record?['category_id'];
          orderId = record?['order_id'];
          orderLabel = orderId == null ? null : '№ $orderId · завершён';
          photos = ((record?['photos'] ?? []) as List).cast<String>().toList();
          cover = record?['cover_id'] ?? (photos.isEmpty ? null : photos.first);
          rights = record?['rights_confirmed'] == true;
          initialized = true;
        }
        final categories = items(data[0]);
        final available = categories.any((c) => c['id'] == category);
        final status = record?['status'] ?? 'draft';
        final statusLabel = {
              'draft': 'Черновик',
              'pending_review': 'На проверке',
              'rejected': 'Нужны изменения',
              'published': 'Опубликован'
            }[status] ??
            '$status';
        return Form(
            key: form,
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                      child: ListView(
                          padding: const EdgeInsets.all(20),
                          children: [
                        SizedBox(
                            height: 24,
                            child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  JobaBadge(statusLabel,
                                      background: const Color(0xFFEDF0F5),
                                      foreground: muted),
                                  TextButton(
                                      onPressed: busy ? null : () => save(),
                                      style: TextButton.styleFrom(
                                          padding: EdgeInsets.zero,
                                          minimumSize: const Size(72, 24)),
                                      child: const UiText('Сохранить',
                                          style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w400))),
                                ])),
                        if (error != null)
                          Notice(errorText(context, error!), error: true),
                        if (error is ApiException &&
                            (error as ApiException).status == 409)
                          TextButton(
                              onPressed: busy
                                  ? null
                                  : () => setState(() {
                                        initialized = false;
                                        error = null;
                                        reload();
                                      }),
                              child:
                                  const UiText('Загрузить актуальную версию')),
                        label('Название проекта'),
                        TextFormField(
                            controller: title,
                            style: const TextStyle(fontSize: 14),
                            enabled: !busy,
                            maxLength: 120,
                            decoration: const InputDecoration(counterText: ''),
                            validator: (v) => (v ?? '').trim().length < 5
                                ? localize(context, 'От 5 до 120 символов')
                                : null),
                        label('Категория'),
                        FormField<String>(
                            initialValue: available ? category : null,
                            validator: (_) => category == null
                                ? localize(context, 'Выберите значение')
                                : null,
                            builder: (field) => InkWell(
                                onTap: busy
                                    ? null
                                    : () async {
                                        final row = await pickReference(
                                            context, categories,
                                            cities: false,
                                            initial: category ?? '');
                                        if (!mounted || row == null) return;
                                        setState(
                                            () => category = '${row['id']}');
                                        field.didChange(category);
                                      },
                                child: InputDecorator(
                                    decoration: InputDecoration(
                                        errorText: field.errorText),
                                    child: Text(categories
                                            .where((r) => r['id'] == category)
                                            .map(referenceName)
                                            .firstOrNull ??
                                        localize(
                                            context, 'Выберите категорию'))))),
                        label('Фотографии · ${photos.length} из 10'),
                        Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                  child: cover == null
                                      ? Container(
                                          height: 117,
                                          decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                              border: Border.all(color: line)),
                                          child: const Center(
                                              child: JobaIcon('image')))
                                      : Stack(children: [
                                          PrivatePhoto(
                                              api: widget.api,
                                              id: cover!,
                                              height: 117,
                                              onOpen: busy
                                                  ? () {}
                                                  : () =>
                                                      save(openPhotos: true)),
                                          const Positioned(
                                              left: 8,
                                              bottom: 8,
                                              child: JobaBadge('Обложка',
                                                  background: Color(0xFFEAF0FC),
                                                  foreground: primary)),
                                        ])),
                              const SizedBox(width: 12),
                              Expanded(
                                  child: CustomPaint(
                                foregroundPainter: const _PhotoAddBorder(),
                                child: SizedBox(
                                    height: 117,
                                    child: OutlinedButton(
                                      style: OutlinedButton.styleFrom(
                                          foregroundColor: primary,
                                          backgroundColor:
                                              const Color(0xFFF7F9FE),
                                          side: BorderSide.none),
                                      onPressed: busy || photos.length >= 10
                                          ? null
                                          : () => run(() async {
                                                final uploaded =
                                                    await widget.pickPhoto();
                                                if (mounted && uploaded != null)
                                                  setState(() {
                                                    photos.add(uploaded['id']);
                                                    cover ??= uploaded['id'];
                                                  });
                                              }, validate: false),
                                      child: const Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            JobaIcon('plus'),
                                            SizedBox(width: 10),
                                            UiText('Добавить',
                                                style: TextStyle(
                                                    fontSize: 14,
                                                    fontWeight:
                                                        FontWeight.w400))
                                          ]),
                                    )),
                              )),
                            ]),
                        label('Описание'),
                        TextFormField(
                            controller: description,
                            style:
                                const TextStyle(fontSize: 14, height: 22 / 14),
                            enabled: !busy,
                            maxLines: 4,
                            maxLength: 3000,
                            decoration: const InputDecoration(counterText: '')),
                        label('Связать с заказом'),
                        InkWell(
                            onTap: busy
                                ? null
                                : () async {
                                    final selected = await pickResource(
                                        context,
                                        widget.api,
                                        '/me/completed-orders',
                                        const {'role': 'executor'},
                                        'Связать с заказом',
                                        optional: true);
                                    if (mounted && selected != null)
                                      setState(() {
                                        orderId = '${selected['id']}'.isEmpty
                                            ? null
                                            : selected['id'];
                                        orderLabel = selected['title'];
                                      });
                                  },
                            child: InputDecorator(
                                decoration: const InputDecoration(),
                                child: Row(children: [
                                  Expanded(
                                      child: Text(
                                          orderLabel ??
                                              localize(context,
                                                  'Без связи с заказом'),
                                          style:
                                              const TextStyle(fontSize: 14))),
                                  const JobaIcon('down')
                                ]))),
                        const SizedBox(height: 18),
                        CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            value: rights,
                            onChanged: busy
                                ? null
                                : (v) => setState(() => rights = v == true),
                            title: const UiText(
                                'У меня есть права на фотографии и необходимые разрешения.',
                                style: TextStyle(fontSize: 12, height: 1.5))),
                        const UiText(
                            'Уберите личные данные, точные адреса и фотографии клиентов без разрешения.',
                            style: TextStyle(
                                fontSize: 10, height: 1.4, color: muted)),
                      ])),
                  SafeArea(
                      top: false,
                      child: Container(
                          decoration: const BoxDecoration(
                              color: Colors.white,
                              border: Border(top: BorderSide(color: line))),
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                          child: FilledButton(
                              onPressed: busy || !rights || photos.isEmpty
                                  ? null
                                  : () => save(submit: true),
                              child: busy
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: Colors.white))
                                  : const UiText('Отправить на проверку')))),
                ]));
      });
}

class _PhotoAddBorder extends CustomPainter {
  const _PhotoAddBorder();
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(.75), const Radius.circular(16)));
    final paint = Paint()
      ..color = const Color(0xFFB8CCF2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final metric in path.computeMetrics()) {
      for (double start = 0; start < metric.length; start += 9) {
        canvas.drawPath(metric.extractPath(start, start + 4.5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PhotoAddBorder oldDelegate) => false;
}
