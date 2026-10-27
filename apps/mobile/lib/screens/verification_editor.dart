import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/design_icons.dart';
import '../core/l10n.dart';
import '../core/theme.dart';

class VerificationEditor extends StatefulWidget {
  final JobaApi api;
  final String country;
  final int revision;
  final Future<Json?> Function(String) pick;
  final VoidCallback onTerms, onProfile, onSupport;
  final ValueChanged<String>? onTitle;
  final ValueChanged<Json>? onAppeal;
  final Map<String, List<String>> uploads;
  const VerificationEditor(
      {required this.api,
      this.revision = 0,
      required this.country,
      required this.pick,
      required this.onTerms,
      required this.onProfile,
      required this.onSupport,
      required this.uploads,
      this.onTitle,
      this.onAppeal,
      super.key});
  @override
  State<VerificationEditor> createState() => _VerificationEditorState();
}

class _VerificationEditorState extends State<VerificationEditor> {
  Json? data, session;
  String? type;
  bool consent = false, busy = false;
  Object? error;
  int epoch = 0;
  bool refreshQueued = false, retrying = false;
  String? rejectedSession;
  @override
  void initState() {
    super.initState();
    widget.api.addListener(authChanged);
    load();
  }

  @override
  void didUpdateWidget(covariant VerificationEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision) {
      if (busy) {
        refreshQueued = true;
      } else {
        load();
      }
    }
  }

  @override
  void dispose() {
    epoch++;
    widget.api.removeListener(authChanged);
    super.dispose();
  }

  void authChanged() {
    if (!widget.api.authenticated) {
      epoch++;
      session = null;
      widget.uploads.clear();
    }
  }

  Future<void> load() async {
    final current = ++epoch;
    try {
      final result = await widget.api.request('/me/verification') as Json;
      if (!mounted || current != epoch) return;
      final records = (result['items'] as List).cast<Json>().toList()
        ..sort((a, b) => '${b['created_at']}'.compareTo('${a['created_at']}'));
      setState(() {
        data = result;
        error = null;
        session = records.isEmpty ? null : records.first;
        if (session?['id'] != rejectedSession) {
          retrying = false;
          rejectedSession = session?['id'];
        }
        final types = (result['policy']?['document_types'] as List?) ?? [];
        type = types.contains(type)
            ? type
            : types.contains(session?['document_type'])
                ? session!['document_type']
                : types.isEmpty
                    ? null
                    : types.first;
        consent = result['policy']?['consent_accepted'] == true;
      });
      widget.onTitle?.call(
          result['status'] == 'passed' || session?['status'] == 'pending_review'
              ? 'Проверка документа'
              : session?['status'] == 'rejected'
                  ? 'Нужно новое фото'
                  : 'Проверка личности');
    } catch (e) {
      if (mounted && current == epoch) setState(() => error = e);
    }
  }

  List<String> get pages {
    final policy = data?['policy'] as Json?;
    final requirements = policy?['required_pages'] as Json?;
    final snapshot =
        session?['document_type'] == type ? (session?['required_pages']) : null;
    return ((snapshot ?? requirements?[type] ?? ['Документ']) as List)
        .cast<String>();
  }

  List<String> get selected =>
      session == null || session!['document_type'] != type
          ? []
          : widget.uploads.putIfAbsent(session!['id'], () => []);
  Future<void> execute(Future<void> Function(int) command) async {
    if (busy) return;
    final current = epoch;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await command(current);
    } catch (e) {
      if (mounted && current == epoch) setState(() => error = e);
    } finally {
      if (mounted && current == epoch) {
        setState(() => busy = false);
        if (refreshQueued) {
          refreshQueued = false;
          await load();
        }
      }
    }
  }

  bool valid(int current) =>
      mounted && epoch == current && widget.api.authenticated;
  Future<void> ensureSession(int current) async {
    final policy = data!['policy'] as Json;
    if (!consent) throw StateError('Требуется согласие на проверку документа');
    if (policy['consent_accepted'] != true) {
      final document = await widget.api.request('/legal/documents',
          query: {'country': widget.country, 'all_versions': 'true'}) as Json;
      final matches = (document['items'] as List)
          .cast<Json>()
          .where((d) => d['id'] == policy['document_id']);
      if (matches.isEmpty)
        throw StateError('Правовое основание проверки недоступно');
      await widget.api.request('/me/consents', method: 'POST', body: {
        'document_id': matches.first['id'],
        'document_hash': matches.first['hash'],
        'accepted': true
      });
      if (!valid(current)) return;
      policy['consent_accepted'] = true;
    }
    if (session == null ||
        session!['document_type'] != type ||
        !['draft', 'rejected'].contains(session!['status']) ||
        session!['policy_id'] != policy['id'] ||
        session!['policy_version'] != policy['version']) {
      final created = await widget.api.request('/me/verification-sessions',
          method: 'POST', body: {'document_type': type}) as Json;
      if (valid(current)) setState(() => session = created);
    }
  }

  Future<void> changeConsent(bool value) async {
    final policy = data?['policy'] as Json?;
    final previous = consent;
    if (value || policy?['consent_accepted'] != true) {
      setState(() => consent = value);
      return;
    }
    setState(() => consent = false);
    await execute((current) async {
      try {
        final documents = await widget.api.request('/legal/documents',
            query: {'country': widget.country, 'all_versions': 'true'}) as Json;
        if (!valid(current)) return;
        final document = (documents['items'] as List)
            .cast<Json>()
            .firstWhere((d) => d['id'] == policy!['document_id']);
        await widget.api.request('/me/consents', method: 'POST', body: {
          'document_id': document['id'],
          'document_hash': document['hash'],
          'accepted': false
        });
        if (valid(current)) policy!['consent_accepted'] = false;
      } catch (e) {
        if (valid(current)) setState(() => consent = previous);
        rethrow;
      }
    });
  }

  Future<void> addPhoto(int index) => execute((current) async {
        await ensureSession(current);
        if (!valid(current)) return;
        final file = await widget.pick(session!['id']);
        if (!valid(current) || file == null) return;
        setState(() {
          if (index < selected.length) {
            selected[index] = file['id'];
          } else {
            selected.add(file['id']);
          }
        });
      });
  Future<void> submit() => execute((current) async {
        await ensureSession(current);
        if (!valid(current)) return;
        await widget.api.request(
            '/me/verification-sessions/${session!['id']}/submit',
            method: 'POST',
            body: {
              'expected_version': session!['version'],
              'upload_ids': List<String>.of(selected)
            });
        if (!valid(current)) return;
        widget.uploads.remove(session!['id']);
        busy = false;
        await load();
      });
  Widget action(String title, VoidCallback? callback) => SizedBox(
      width: double.infinity,
      child: FilledButton(onPressed: callback, child: UiText(title)));
  Widget heading(String title, String description) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        UiText(title,
            style: const TextStyle(
                fontSize: 26,
                height: 1.27,
                letterSpacing: -.7,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        UiText(description,
            style: const TextStyle(
                color: Color(0xFF627187), fontSize: 12, height: 1.5)),
        const SizedBox(height: 20)
      ]);
  Widget _resultRow(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Expanded(
            child: UiText(label,
                style:
                    const TextStyle(color: Color(0xFF627187), fontSize: 12))),
        Text(value,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))
      ]));
  Widget rejectionSummary() =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
            child: ListView(padding: const EdgeInsets.all(20), children: [
          Notice(
              session?['reason'] ??
                  'Для проверки нужны новые фотографии документа.',
              warning: true,
              icon: 'info',
              margin: EdgeInsets.zero),
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 25),
              child: Column(children: [
                Container(
                    width: 94,
                    height: 94,
                    decoration: BoxDecoration(
                        color: const Color(0xFFEAF0FC),
                        borderRadius: BorderRadius.circular(30)),
                    child: const Center(
                        child: JobaIcon('camera', size: 42, color: primary))),
                const SizedBox(height: 23),
                const UiText('Давайте попробуем\nещё раз',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 25,
                        height: 1.28,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -.7)),
                const SizedBox(height: 12),
                const UiText(
                    'Снимите документ при рассеянном свете. Все края должны быть в кадре.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 13, height: 1.45, color: Color(0xFF627187))),
              ])),
          Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: line),
                  borderRadius: BorderRadius.circular(16)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const UiText('Что исправить',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Text(
                        session?['reason'] ??
                            localize(context,
                                'Загрузите читаемые фотографии всех необходимых страниц.'),
                        style: const TextStyle(
                            fontSize: 13,
                            height: 1.45,
                            color: Color(0xFF627187))),
                  ])),
          const SizedBox(height: 20),
          TextButton(
              onPressed: () {
                if (widget.onAppeal != null) {
                  widget.onAppeal!(session!);
                } else {
                  widget.onSupport();
                }
              },
              child: const UiText('Обжаловать решение')),
        ])),
        SafeArea(
            top: false,
            child: Container(
                decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: line))),
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                child: action('Загрузить заново', () {
                  setState(() => retrying = true);
                  widget.onTitle?.call('Проверка личности');
                }))),
      ]);
  @override
  Widget build(BuildContext context) {
    if (data == null)
      return error == null
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('$error'),
              TextButton(onPressed: load, child: const UiText('Повторить'))
            ]));
    final status = data!['status'],
        pending = session?['status'] == 'pending_review',
        passed = status == 'passed';
    final rejected = session?['status'] == 'rejected';
    if (rejected && !retrying && !passed && !pending) return rejectionSummary();
    if (pending || passed)
      return Column(children: [
        Expanded(
            child: ListView(padding: const EdgeInsets.all(20), children: [
          const SizedBox(height: 48),
          Center(
              child: JobaIcon(passed ? 'shield' : 'clock',
                  size: 64, color: primary)),
          const SizedBox(height: 24),
          heading(
              passed ? 'Документ проверен' : 'Проверяем документ',
              passed
                  ? 'Вы можете публиковать профиль и портфолио, искать заказы и откликаться.'
                  : 'Фотографии получены. Решение появится здесь и в уведомлениях. Пока можно заполнить черновик профиля.'),
          if (passed)
            Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: line),
                    borderRadius: BorderRadius.circular(16)),
                child: Column(children: [
                  _resultRow('Результат', localize(context, 'Пройдено')),
                  if (session?['decided_at'] != null)
                    _resultRow(
                        'Дата',
                        MaterialLocalizations.of(context).formatMediumDate(
                            DateTime.parse(session!['decided_at']).toLocal())),
                  if (session?['expires_at'] != null)
                    _resultRow(
                        'Следующая проверка',
                        MaterialLocalizations.of(context).formatMediumDate(
                            DateTime.parse(session!['expires_at']).toLocal()))
                ])),
          if (passed)
            const Notice(
                'В профиле виден только факт проверки. Изображение документа не публикуется.'),
          TextButton(
              onPressed: widget.onSupport,
              child: const UiText('Вопрос по проверке'))
        ])),
        Padding(
            padding: const EdgeInsets.all(20),
            child: action(passed ? 'К моим услугам' : 'Заполнить профиль',
                widget.onProfile))
      ]);
    final policy = data!['policy'] as Json?;
    return Column(children: [
      Expanded(
          child: ListView(padding: const EdgeInsets.all(20), children: [
        Row(
            children: List.generate(
                3,
                (i) => Expanded(
                    child: Container(
                        height: 4,
                        margin:
                            EdgeInsets.only(right: i == 2 ? 0 : 5, bottom: 24),
                        decoration: BoxDecoration(
                            color: i == 0 ? primary : line,
                            borderRadius: BorderRadius.circular(4)))))),
        heading(
            rejected ? 'Давайте попробуем ещё раз' : 'Подтвердите документ',
            rejected
                ? 'Снимите документ при рассеянном свете. Все края должны быть в кадре.'
                : 'Для заказчиков и исполнителей: две стороны удостоверения и селфи. После одобрения селфи станет фотографией профиля.'),
        const Notice(
            'Удостоверение видят только сотрудники проверки. В профиле будет только селфи после одобрения.',
            icon: 'shield',
            margin: EdgeInsets.zero),
        if (rejected && session?['reason'] != null)
          Notice('${session!['reason']}'),
        const SizedBox(height: 20),
        Text(
            'Документ · ${{
                  'KZ': 'Казахстан',
                  'KG': 'Кыргызстан',
                  'RU': 'Россия',
                  'BY': 'Беларусь'
                }[widget.country] ?? widget.country}',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (policy == null)
          const Notice(
              'Разрешённые типы и основание проверки определяются утверждённой политикой страны.'),
        for (final value in (policy?['document_types'] as List?) ?? [])
          Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
                  color: type == value ? const Color(0xFFEFF4FF) : Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: type == value ? primary : line)),
                  child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: busy ? null : () => setState(() => type = value),
                      child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(children: [
                            JobaIcon(value == 'passport' ? 'file' : 'card'),
                            const SizedBox(width: 12),
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  UiText(
                                      value == 'passport'
                                          ? 'Паспорт'
                                          : 'Удостоверение личности',
                                      style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 5),
                                  Text(
                                      (((policy?['required_pages']
                                                  as Json?)?[value] as List?) ??
                                              ['Документ'])
                                          .join(' · '),
                                      style: const TextStyle(
                                          color: Color(0xFF627187),
                                          fontSize: 12))
                                ])),
                            Container(
                                width: 20,
                                height: 20,
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: type == value
                                            ? primary
                                            : const Color(0xFFBAC8DF),
                                        width: 1.5)),
                                child: type == value
                                    ? Container(
                                        decoration: const BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: primary))
                                    : null)
                          ]))))),
        const SizedBox(height: 10),
        const UiText('Документ и селфи',
            style: TextStyle(fontWeight: FontWeight.w700)),
        if (selected.length < pages.length)
          Padding(
              padding: const EdgeInsets.only(top: 10),
              child: CustomPaint(
                  painter: _UploadOutline(),
                  child: SizedBox(
                      height: 98,
                      width: double.infinity,
                      child: TextButton(
                          onPressed: busy || policy == null || !consent
                              ? null
                              : () => addPhoto(selected.length),
                          child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const JobaIcon('camera', color: navy),
                                const SizedBox(width: 12),
                                Flexible(
                                    child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                      const UiText('Добавить фотографии',
                                          style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w400)),
                                      const SizedBox(height: 5),
                                      Text(
                                          localize(
                                              context, pages[selected.length]),
                                          style: const TextStyle(
                                              fontSize: 11,
                                              color: Color(0xFF627187)))
                                    ]))
                              ]))))),
        for (var i = 0; i < selected.length; i++)
          TextButton(
              onPressed: busy ? null : () => addPhoto(i),
              child: Row(children: [
                const JobaIcon('check', color: primary),
                const SizedBox(width: 8),
                Expanded(child: Text('${localize(context, pages[i])} · ✓'))
              ])),
        const SizedBox(height: 8),
        const UiText('Все края видны, текст читается, без бликов.',
            style: TextStyle(fontSize: 11, color: Color(0xFF627187))),
        CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: consent,
            onChanged:
                busy || policy == null ? null : (v) => changeConsent(v == true),
            title: const UiText(
                'Согласен на проверку документа и селфи. После одобрения селфи станет фото профиля.',
                style: TextStyle(fontSize: 12, height: 1.55))),
        TextButton(
            onPressed: widget.onTerms, child: const UiText('Условия проверки')),
        if (rejected)
          TextButton(
              onPressed: () {
                if (widget.onAppeal != null) {
                  widget.onAppeal!(session!);
                } else {
                  widget.onSupport();
                }
              },
              child: const UiText('Обжаловать решение')),
        if (error != null) Notice('$error')
      ])),
      Container(
          color: Colors.white,
          padding: const EdgeInsets.all(20),
          child: action(
              busy ? 'Загрузка…' : 'Отправить на проверку',
              busy ||
                      policy == null ||
                      !consent ||
                      selected.length != pages.length
                  ? null
                  : submit))
    ]);
  }
}

class _UploadOutline extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
          Offset.zero & size, const Radius.circular(16)));
    final paint = Paint()
      ..color = const Color(0xFFBACDF1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    for (final metric in path.computeMetrics()) {
      for (double distance = 0; distance < metric.length; distance += 9) {
        canvas.drawPath(
            metric.extractPath(
                distance, (distance + 5).clamp(0, metric.length)),
            paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _UploadOutline oldDelegate) => false;
}
