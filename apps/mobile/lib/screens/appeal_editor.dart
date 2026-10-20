import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/design_states.dart';
import '../core/design_widgets.dart';
import '../core/l10n.dart';
import '../core/theme.dart';
import '../core/widgets.dart';

class AppealEditor extends StatefulWidget {
  final JobaApi api;
  final Json incident;
  final Future<Json?> Function() pickUpload;
  final VoidCallback onCases;
  const AppealEditor(
      {required this.api,
      required this.incident,
      required this.pickUpload,
      required this.onCases,
      super.key});
  @override
  State<AppealEditor> createState() => _AppealEditorState();
}

class _AppealEditorState extends State<AppealEditor> {
  late Json incident = Json.from(widget.incident);
  final attachments = <Json>[];
  bool uploading = false, submitting = false, stale = false, refreshing = false;
  Object? uploadError;
  Json? sent;
  bool get busy => uploading || submitting || refreshing;
  bool get allowed =>
      ['restricted', 'resolved'].contains(incident['status']) &&
      (incident['status'] == 'restricted' ||
          ['content_removed', 'sanction_upheld']
              .contains(incident['decision']));
  Future<void> attach() async {
    if (busy || attachments.length >= 10) return;
    setState(() {
      uploading = true;
      uploadError = null;
    });
    try {
      final file = await widget.pickUpload();
      if (mounted && file != null) setState(() => attachments.add(file));
    } catch (e) {
      if (mounted) setState(() => uploadError = e);
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }

  Future<void> refresh() async {
    if (busy) return;
    setState(() => refreshing = true);
    try {
      final fresh =
          await widget.api.request('/cases/${incident['id']}') as Json;
      if (mounted)
        setState(() {
          incident = fresh;
          stale = false;
          uploadError = null;
        });
    } catch (e) {
      if (mounted) setState(() => uploadError = e);
    } finally {
      if (mounted) setState(() => refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (sent != null)
      return Scaffold(
          backgroundColor: canvas,
          appBar: AppBar(
              leadingWidth: 72,
              title: Transform.translate(
                  offset: const Offset(0, -12),
                  child: const UiText('Апелляция отправлена'))),
          body: ListView(padding: const EdgeInsets.all(20), children: [
            JobaStatePanel(
                title: 'Мы получили\nваше обращение',
                message: 'Статус и ответ доступны в ваших обращениях.',
                icon: 'check',
                primaryLabel: 'Мои обращения',
                onPrimary: widget.onCases)
          ]));
    return Scaffold(
        backgroundColor: canvas,
        appBar: AppBar(
            leadingWidth: 72,
            title: Transform.translate(
                offset: const Offset(0, -12),
                child: const UiText('Обжаловать решение'))),
        body: ActionForm(
            externalBusy: busy,
            errorResetKey: incident['version'],
            submitEnabled: allowed && !stale,
            stickySubmit: true,
            button: 'Отправить апелляцию',
            before: [
              const UiHeading('Ваша позиция важна',
                  'Опишите, с чем вы не согласны. Обращение рассмотрит уполномоченный сотрудник.'),
              Container(
                  margin: const EdgeInsets.only(bottom: 20),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: line),
                      borderRadius: BorderRadius.circular(16)),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const UiText('Связанное решение',
                            style: TextStyle(fontSize: 12, color: muted)),
                        const SizedBox(height: 10),
                        Text(
                            '№ ${incident['id'].toString().split('-').first.toUpperCase()}',
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        UiText(
                            incident['decision'] == 'content_removed'
                                ? 'Ограничение материала'
                                : 'Ограничение аккаунта',
                            style: const TextStyle(fontSize: 14))
                      ])),
              if (!allowed)
                const Notice('Апелляция по этому решению сейчас недоступна.',
                    icon: 'info'),
              if (stale)
                OutlinedButton(
                    onPressed: busy ? null : refresh,
                    child: const UiText('Обновить решение')),
            ],
            fields: [
              InputSpec('reason', 'Почему решение нужно пересмотреть?',
                  multiline: true,
                  lines: 4,
                  minHeight: 120,
                  validate: (v) =>
                      v.trim().length < 10 || v.trim().length > 3000
                          ? 'Введите от 10 до 3000 символов'
                          : null)
            ],
            afterFields: [
              const UiText('Подтверждающие материалы',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              if (uploadError != null)
                Notice(errorText(context, uploadError!), error: true),
              for (final file in attachments)
                ListTile(
                    title: Text(
                        '${localize(context, 'Файл')} ${attachments.indexOf(file) + 1}'),
                    trailing: IconButton(
                        tooltip: localize(context, 'Удалить'),
                        onPressed: busy
                            ? null
                            : () => setState(() => attachments.remove(file)),
                        icon: const Icon(Icons.close))),
              JobaUploadButton(uploading ? 'Загрузка…' : 'Добавить материалы',
                  onPressed: busy || attachments.length >= 10 ? null : attach),
              const Padding(
                  padding: EdgeInsets.only(top: 20, bottom: 20),
                  child: UiText(
                      'Статус появится в «Моих обращениях». Повторная отправка не ускорит рассмотрение.',
                      style:
                          TextStyle(fontSize: 12, height: 1.55, color: muted))),
            ],
            submit: (values) async {
              setState(() => submitting = true);
              try {
                final result = await widget.api.request(
                    '/cases/${incident['id']}/appeals',
                    method: 'POST',
                    body: {
                      'expected_version': incident['version'],
                      'reason': values['reason']!.trim(),
                      'upload_ids': attachments.map((f) => f['id']).toList()
                    }) as Json;
                if (result['status'] != 'appealed')
                  throw ApiException('INVALID_RESPONSE',
                      'Не удалось подтвердить отправку апелляции');
                if (mounted) setState(() => sent = result);
              } catch (e) {
                if (mounted && e is ApiException && e.code == 'STATE_CONFLICT')
                  setState(() => stale = true);
                rethrow;
              } finally {
                if (mounted) setState(() => submitting = false);
              }
            }));
  }
}
