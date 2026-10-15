import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/design_widgets.dart';
import '../core/l10n.dart';
import '../core/theme.dart';
import '../core/widgets.dart';

class SupportNew extends StatefulWidget {
  final JobaApi api;
  final bool executor;
  final Future<Json?> Function() pickUpload;
  final ValueChanged<String> onCreated;
  const SupportNew(
      {required this.api,
      required this.executor,
      required this.pickUpload,
      required this.onCreated,
      super.key});
  @override
  State<SupportNew> createState() => _SupportNewState();
}

class _SupportNewState extends State<SupportNew> {
  static const topics = {
    'orders': 'Заказы и договорённости',
    'account': 'Аккаунт и безопасность',
    'payment': 'Оплата и доступ',
    'technical': 'Технический вопрос',
    'other': 'Другой вопрос'
  };
  final attachments = <Json>[];
  bool uploading = false, submitting = false;
  bool get busy => uploading || submitting;
  Object? uploadError;
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

  @override
  Widget build(BuildContext context) => ActionForm(
      externalBusy: busy,
      stickySubmit: true,
      button: 'Начать чат',
      before: const [
        UiHeading(
            'Чем помочь?', 'Опишите вопрос, и мы передадим его специалисту.')
      ],
      fields: [
        const InputSpec('topic', 'Тема', initial: 'orders', options: topics),
        InputSpec('order_id', 'Связанный заказ',
            required: false,
            pickerApi: widget.api,
            pickerPath: widget.executor ? '/me/assigned-orders' : '/me/orders'),
        InputSpec('text', 'Ваш вопрос',
            multiline: true,
            lines: 4,
            minHeight: 120,
            validate: (value) =>
                value.trim().isEmpty || value.trim().length > 3000
                    ? 'Введите от 1 до 3000 символов'
                    : null),
      ],
      afterFields: [
        const UiText('Вложения',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        if (uploadError != null)
          Notice(errorText(context, uploadError!), error: true),
        for (final file in attachments)
          ListTile(
              title: UiText('Файл ${attachments.indexOf(file) + 1}'),
              subtitle: UiText(file['status'] == 'clean'
                  ? 'Файл проверен'
                  : 'Ожидает проверки'),
              trailing: IconButton(
                  tooltip: localize(context, 'Удалить'),
                  onPressed: busy
                      ? null
                      : () => setState(() => attachments.remove(file)),
                  icon: const Icon(Icons.close))),
        JobaUploadButton(uploading ? 'Загрузка…' : 'Фото или файл',
            onPressed: busy || attachments.length >= 10 ? null : attach),
        const Notice(
            'Не прикладывайте пароли, PIN и документы личности. Для документа есть защищённая проверка.',
            icon: 'info',
            margin: EdgeInsets.only(top: 20, bottom: 20)),
      ],
      submit: (values) async {
        setState(() => submitting = true);
        try {
          final topic = values['topic']!;
          final thread = await widget.api
              .request('/support/threads', method: 'POST', body: {
            'topic': topic,
            'subject': topics[topic],
            'text': values['text']!.trim(),
            if (values['order_id']!.isNotEmpty) 'order_id': values['order_id'],
            'upload_ids': attachments.map((f) => f['id']).toList(),
          }) as Json;
          if (mounted) widget.onCreated(thread['id']);
        } finally {
          if (mounted) setState(() => submitting = false);
        }
      });
}
