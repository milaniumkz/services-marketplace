import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/design_icons.dart';
import '../core/design_widgets.dart';
import '../core/l10n.dart';
import '../core/theme.dart';

class ProfileEditor extends StatefulWidget {
  final JobaApi api;
  final Json initial;
  final bool onboarding;
  final Future<Json?> Function() pickAvatar;
  final ValueChanged<Json> onSaved;
  const ProfileEditor(
      {required this.api,
      required this.initial,
      required this.onboarding,
      required this.pickAvatar,
      required this.onSaved,
      super.key});
  @override
  State<ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<ProfileEditor> {
  final form = GlobalKey<FormState>();
  late Json record;
  late TextEditingController name, city, languages;
  late String role;
  bool busy = false;
  Object? error;
  @override
  void initState() {
    super.initState();
    record = Map<String, dynamic>.from(widget.initial);
    name = TextEditingController(text: record['display_name'] ?? '');
    city = TextEditingController(text: record['city'] ?? '');
    languages = TextEditingController(
        text: (record['languages'] as List? ?? [record['locale'] ?? 'ru'])
            .join(', '));
    role = record['active_role'] ?? 'customer';
  }

  @override
  void dispose() {
    name.dispose();
    city.dispose();
    languages.dispose();
    super.dispose();
  }

  Future<void> avatar({bool remove = false}) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final file = remove ? null : await widget.pickAvatar();
      if (!remove && file == null) return;
      final updated = await widget.api.request('/me', method: 'PATCH', body: {
        'expected_version': record['version'],
        'avatar_id': file?['id']
      }) as Json;
      if (!mounted) return;
      record = {
        ...record,
        'avatar_id': updated['avatar_id'],
        'version': updated['version']
      };
    } catch (failure) {
      if (mounted) error = failure;
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.api.request('/me', method: 'PATCH', body: {
        'expected_version': record['version'],
        'display_name': name.text.trim(),
        'active_role': role,
        'roles': {...record['roles'] as List? ?? [], role}.toList(),
        if (!widget.onboarding) 'city': city.text.trim(),
        if (!widget.onboarding)
          'languages': languages.text
              .split(',')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toSet()
              .toList()
      }) as Json;
      if (mounted) widget.onSaved(result);
    } catch (failure) {
      if (mounted) error = failure;
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget field(String label, TextEditingController controller,
          {bool required = true}) =>
      Padding(
          padding: const EdgeInsets.only(top: 18),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            UiText(label,
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            TextFormField(
                controller: controller,
                enabled: !busy,
                style: const TextStyle(fontSize: 14),
                validator: (value) =>
                    required && (value ?? '').trim().length < 2
                        ? localize(context, 'Заполните поле')
                        : null)
          ]));
  Widget roleChoice(String value, String title, String subtitle, String icon) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Semantics(
              selected: role == value,
              button: true,
              child: Material(
                  color: role == value ? const Color(0xFFF1F5FE) : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                      onTap: busy ? null : () => setState(() => role = value),
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                          constraints: const BoxConstraints(minHeight: 76),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                              border: Border.all(
                                  color: role == value ? primary : line),
                              borderRadius: BorderRadius.circular(14)),
                          child: Row(children: [
                            JobaIcon(icon),
                            const SizedBox(width: 12),
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  UiText(title,
                                      style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 4),
                                  UiText(subtitle,
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: muted,
                                          height: 1.5))
                                ])),
                            const SizedBox(width: 8),
                            Icon(
                                role == value
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_off,
                                size: 20,
                                color: role == value
                                    ? primary
                                    : const Color(0xFFBBC7D9))
                          ]))))));
  @override
  Widget build(BuildContext context) => Form(
      key: form,
      child: Column(children: [
        Expanded(
            child: ListView(padding: const EdgeInsets.all(20), children: [
          if (widget.onboarding) ...[
            Row(
                children: List.generate(
                    3,
                    (i) => Expanded(
                        child: Container(
                            height: 4,
                            margin: EdgeInsets.only(
                                right: i == 2 ? 0 : 5, bottom: 22),
                            decoration: BoxDecoration(
                                color: i == 0 ? primary : line,
                                borderRadius: BorderRadius.circular(4)))))),
            Center(
                child: Column(children: [
              record['avatar_id'] == null
                  ? Material(
                      color: const Color(0xFFEAF0FC),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side:
                              const BorderSide(color: Colors.white, width: 2)),
                      child: InkWell(
                          onTap: busy ? null : () => avatar(),
                          borderRadius: BorderRadius.circular(16),
                          child: const SizedBox(
                              width: 56,
                              height: 56,
                              child:
                                  Center(child: JobaIcon('camera', size: 22)))))
                  : JobaAvatar(
                      api: widget.api,
                      name: name.text,
                      id: record['avatar_id'],
                      size: 56,
                      onTap: busy ? null : () => avatar()),
              TextButton(
                  onPressed: busy ? null : () => avatar(),
                  child: const Column(children: [
                    UiText('Добавить фото',
                        style: TextStyle(fontSize: 11, color: primary)),
                    UiText('Необязательно',
                        style: TextStyle(fontSize: 10, color: muted))
                  ])),
              if (record['avatar_id'] != null)
                TextButton(
                    onPressed: busy ? null : () => avatar(remove: true),
                    child: const UiText('Удалить фото профиля'))
            ]))
          ] else
            Row(children: [
              JobaAvatar(
                  api: widget.api,
                  name: name.text,
                  id: record['avatar_id'],
                  size: 56),
              const SizedBox(width: 12),
              Expanded(
                  child: TextButton(
                      onPressed: busy ? null : () => avatar(),
                      child: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            UiText('Добавить фото',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: primary)),
                            SizedBox(height: 4),
                            UiText('Необязательно',
                                style: TextStyle(fontSize: 11, color: muted))
                          ]))),
              if (record['avatar_id'] != null)
                IconButton(
                    tooltip: localize(context, 'Удалить фото профиля'),
                    onPressed: busy ? null : () => avatar(remove: true),
                    icon: const JobaIcon('trash', size: 20))
            ]),
          if (error != null) Notice(errorText(context, error!), error: true),
          field('Как к вам обращаться', name),
          if (!widget.onboarding) ...[
            field('Город', city, required: false),
            field('Языки общения (ru, kk, sr, be, en)', languages)
          ],
          const SizedBox(height: 24),
          const UiText('Что вам интересно?',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          roleChoice('customer', 'Найти специалиста',
              'Разместить заказ или выбрать мастера', 'search'),
          roleChoice('executor', 'Найти заказы',
              'Предлагать услуги и откликаться', 'brief'),
          if (widget.onboarding)
            const UiText(
                'Роль можно переключить позже. Для работы исполнителем потребуется проверка документа.',
                style: TextStyle(fontSize: 11, height: 1.55, color: muted))
          else
            const Notice(
                'Роль можно переключить позже. Для работы исполнителем потребуется проверка документа.',
                icon: 'info')
        ])),
        SafeArea(
            top: false,
            child: Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: FilledButton(
                    onPressed: busy ? null : save,
                    child: busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const UiText('Сохранить профиль'))))
      ]));
}
