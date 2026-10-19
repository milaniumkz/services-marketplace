import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/l10n.dart';
import '../core/theme.dart';

class NotificationSettingsContent extends StatefulWidget {
  final JobaApi api;
  final VoidCallback onSaved;
  const NotificationSettingsContent(
      {required this.api, required this.onSaved, super.key});
  @override
  State<NotificationSettingsContent> createState() =>
      _NotificationSettingsContentState();
}

class _NotificationSettingsContentState
    extends State<NotificationSettingsContent> {
  Json? preferences;
  dynamic version;
  Object? error;
  bool saving = false, loading = true, refreshFailed = false;
  late int generation;
  String? owner;
  final start = TextEditingController(),
      end = TextEditingController(),
      zone = TextEditingController();
  bool quiet = false;
  bool get current =>
      mounted &&
      !widget.api.disposed &&
      widget.api.authenticated &&
      widget.api.sessionGeneration == generation &&
      widget.api.session?['user']?['id'] == owner;
  @override
  void initState() {
    super.initState();
    generation = widget.api.sessionGeneration;
    owner = widget.api.session?['user']?['id'];
    load();
  }

  @override
  void dispose() {
    start.dispose();
    end.dispose();
    zone.dispose();
    super.dispose();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final data = await Future.wait([
        widget.api.request('/me'),
        widget.api.request('/me/notification-preferences')
      ]);
      if (!current) return;
      final user = data[0], p = Map<String, dynamic>.from(data[1]);
      setState(() {
        version = p.remove('version') ?? user['version'];
        refreshFailed = false;
        preferences = {
          'chat': true,
          'service': true,
          'marketing': false,
          ...p,
          'orders': p['orders'] ?? p['service'] ?? true,
          'support': p['support'] ?? p['service'] ?? true
        };
        quiet = p['quiet_hours'] != null;
        start.text = p['quiet_hours']?['start'] ?? '22:00';
        end.text = p['quiet_hours']?['end'] ?? '08:00';
        zone.text = p['quiet_hours']?['time_zone'] ??
            const {
              'KZ': 'Asia/Almaty',
              'KG': 'Asia/Bishkek',
              'RU': 'Europe/Moscow',
              'BY': 'Europe/Minsk'
            }[user['country']] ??
            'UTC';
        loading = false;
      });
    } catch (e) {
      if (current)
        setState(() {
          error = e;
          refreshFailed = preferences != null;
          loading = false;
        });
    }
  }

  Future<void> save() async {
    if (saving || loading || refreshFailed || !current) return;
    if (quiet &&
        (!RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(start.text.trim()) ||
            !RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(end.text.trim()) ||
            start.text.trim() == end.text.trim() ||
            zone.text.trim().isEmpty)) {
      setState(() =>
          error = ApiException('VALIDATION_ERROR', 'Проверьте часы тишины'));
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.api
          .request('/me/notification-preferences', method: 'PATCH', body: {
        'expected_version': version,
        'preferences': {
          ...preferences!,
          'quiet_hours': quiet
              ? {
                  'start': start.text.trim(),
                  'end': end.text.trim(),
                  'time_zone': zone.text.trim()
                }
              : null
        }
      });
      if (current) widget.onSaved();
    } catch (e) {
      if (current) setState(() => error = e);
    } finally {
      if (current) setState(() => saving = false);
    }
  }

  Widget toggle(String key, String title, String subtitle) =>
      NotificationPreferenceToggle(
          title: title,
          subtitle: subtitle,
          value: preferences![key] == true,
          onChanged:
              saving ? null : (v) => setState(() => preferences![key] = v));
  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (preferences == null)
      return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(errorText(context, error!)),
        TextButton(onPressed: load, child: const UiText('Повторить'))
      ]));
    return Column(children: [
      Expanded(
          child: ListView(padding: const EdgeInsets.all(20), children: [
        const UiText('Только важное',
            style: TextStyle(
                fontSize: 26,
                height: 33 / 26,
                letterSpacing: -.9,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        const UiText('Управляйте событиями JOBA на устройстве.',
            style:
                TextStyle(fontSize: 12, height: 1.5, color: Color(0xFF627187))),
        const SizedBox(height: 24),
        Container(
            decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: line),
                borderRadius: BorderRadius.circular(16)),
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              toggle('chat', 'Сообщения', 'Новые сообщения по заказам'),
              const Divider(height: 1),
              toggle('orders', 'Заказы', 'Отклики, выбор и завершение'),
              const Divider(height: 1),
              toggle('support', 'Поддержка', 'Ответы и важные сроки'),
              const Divider(height: 1),
              toggle('marketing', 'Новости и предложения',
                  'Необязательные сообщения')
            ])),
        const SizedBox(height: 20),
        const UiText(
            'Важные события также сохраняются внутри приложения. Разрешение системных push настраивается отдельно.',
            style:
                TextStyle(fontSize: 12, height: 1.5, color: Color(0xFF627187))),
        const SizedBox(height: 20),
        ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const UiText('Часы тишины'),
            children: [
              toggle('service', 'Другие сервисные события',
                  'Профиль, безопасность и доступ'),
              SwitchListTile(
                  value: quiet,
                  title: const UiText('Включены'),
                  onChanged: saving ? null : (v) => setState(() => quiet = v)),
              if (quiet) ...[
                for (final entry in {
                  start: 'Начало (ЧЧ:ММ)',
                  end: 'Окончание (ЧЧ:ММ)',
                  zone: 'Часовой пояс IANA'
                }.entries)
                  Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TextField(
                          controller: entry.key,
                          enabled: !saving,
                          decoration: InputDecoration(
                              labelText: localize(context, entry.value))))
              ]
            ]),
        if (error != null) ...[
          Text(errorText(context, error!),
              style: const TextStyle(color: Colors.red)),
          if (refreshFailed ||
              (error is ApiException && (error as ApiException).status == 409))
            TextButton(
                onPressed: saving ? null : load,
                child: const UiText('Обновить настройки'))
        ]
      ])),
      Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 26),
          decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: line))),
          child: FilledButton(
              onPressed: saving || refreshFailed ? null : save,
              child: UiText(saving ? 'Сохранение…' : 'Сохранить')))
    ]);
  }
}

class NotificationPreferenceToggle extends StatelessWidget {
  final String title, subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  const NotificationPreferenceToggle(
      {required this.title,
      required this.subtitle,
      required this.value,
      this.onChanged,
      super.key});
  @override
  Widget build(BuildContext context) => Semantics(
      label: localize(context, title),
      value: localize(context, subtitle),
      toggled: value,
      enabled: onChanged != null,
      child: InkWell(
          onTap: onChanged == null ? null : () => onChanged!(!value),
          child: ConstrainedBox(
              constraints: BoxConstraints(
                  minHeight: title == 'Новости и предложения' ? 81 : 63),
              child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
                  child: Row(children: [
                    Expanded(
                        child: ExcludeSemantics(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                          UiText(title,
                              style: const TextStyle(
                                  fontSize: 13,
                                  height: 20 / 13,
                                  letterSpacing: -.2,
                                  fontWeight: FontWeight.w700)),
                          UiText(subtitle,
                              style: const TextStyle(
                                  fontSize: 11,
                                  height: 17 / 11,
                                  color: Color(0xFF627187)))
                        ]))),
                    const SizedBox(width: 12),
                    ExcludeSemantics(
                        child: Container(
                            width: 39,
                            height: 24,
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                                color:
                                    value ? primary : const Color(0xFFCBD4E1),
                                borderRadius: BorderRadius.circular(20)),
                            alignment: value
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                                width: 18,
                                height: 18,
                                decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.white,
                                    boxShadow: [
                                      BoxShadow(
                                          color: Color(0x25142847),
                                          offset: Offset(0, 1),
                                          blurRadius: 3)
                                    ]))))
                  ])))));
}
