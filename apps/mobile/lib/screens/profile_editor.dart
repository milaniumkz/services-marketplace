import 'city_selector.dart';
import '../core/widgets.dart' show ApiView;
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
  final ValueChanged<bool>? onBusyChanged;
  final Json? draft;
  final ValueChanged<Json>? onDraftChanged;
  const ProfileEditor(
      {required this.api,
      required this.initial,
      required this.onboarding,
      required this.pickAvatar,
      required this.onSaved,
      this.onBusyChanged,
      this.draft,
      this.onDraftChanged,
      super.key});
  @override
  State<ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<ProfileEditor> {
  final form = GlobalKey<FormState>();
  late Json record;
  late TextEditingController name, city, languages;
  late String role;
  bool busy = false, choosing = false;
  Object? error;
  Json? pendingAvatar;
  @override
  void initState() {
    super.initState();
    record = Map<String, dynamic>.from(widget.initial);
    name = TextEditingController(
        text: widget.draft?['name'] ?? record['display_name'] ?? '');
    city = TextEditingController(
        text: widget.draft?['city'] ?? record['city'] ?? '');
    languages = TextEditingController(
        text: widget.draft?['languages'] ??
            (record['languages'] as List? ?? [record['locale'] ?? 'ru'])
                .join(', '));
    role = widget.draft?['role'] ?? record['active_role'] ?? 'customer';
    pendingAvatar = widget.draft?['pending_avatar'] is Map
        ? Json.from(widget.draft!['pending_avatar'])
        : null;
  }

  @override
  void dispose() {
    name.dispose();
    city.dispose();
    languages.dispose();
    super.dispose();
  }

  void notifyDraft() {
    if (!mounted ||
        !widget.api.authenticated ||
        widget.api.session?['user']?['id'] != record['id']) return;
    widget.onDraftChanged?.call({
      'name': name.text,
      'city': city.text,
      'languages': languages.text,
      'role': role,
      'pending_avatar': pendingAvatar
    });
  }

  bool current(JobaApi api, int generation) =>
      mounted &&
      identical(widget.api, api) &&
      !api.disposed &&
      api.sessionGeneration == generation &&
      api.authenticated &&
      api.session?['user']?['id'] == record['id'];
  void start({bool selecting = false}) {
    setState(() {
      busy = true;
      choosing = selecting;
      error = null;
    });
    widget.onBusyChanged?.call(true);
  }

  void finish() {
    if (mounted)
      setState(() {
        busy = false;
        choosing = false;
      });
    widget.onBusyChanged?.call(false);
  }

  Future<void> conflict(Object failure, JobaApi api, int generation) async {
    if (!current(api, generation)) return;
    error = failure;
    if (failure is ApiException && failure.code == 'STATE_CONFLICT') {
      try {
        final fresh = await api.request('/me') as Json;
        if (current(api, generation) && fresh['id'] == record['id'])
          record = Json.from(fresh);
      } catch (e) {
        if (current(api, generation)) error = e;
      }
    }
  }

  Future<void> avatar({bool remove = false}) async {
    if (busy) return;
    final api = widget.api, generation = widget.api.sessionGeneration;
    if (!current(api, generation)) return;
    start();
    try {
      final file = remove ? null : pendingAvatar ?? await widget.pickAvatar();
      if (!current(api, generation) || (!remove && file == null)) return;
      pendingAvatar = file;
      final updated = await api.request('/me', method: 'PATCH', body: {
        'expected_version': record['version'],
        'avatar_id': file?['id'],
      }) as Json;
      if (!current(api, generation) || updated['id'] != record['id']) return;
      record = {...record, ...updated};
      pendingAvatar = null;
    } catch (failure) {
      await conflict(failure, api, generation);
    } finally {
      if (current(api, generation)) notifyDraft();
      finish();
    }
  }

  Future<void> save() async {
    if (busy || !form.currentState!.validate()) return;
    final api = widget.api, generation = widget.api.sessionGeneration;
    if (!current(api, generation)) return;
    start();
    bool released = false;
    try {
      final result = await api.request('/me', method: 'PATCH', body: {
        'expected_version': record['version'],
        if (pendingAvatar != null) 'avatar_id': pendingAvatar!['id'],
        'display_name': name.text.trim(),
        if (widget.onboarding) 'active_role': role,
        if (widget.onboarding)
          'roles': {...record['roles'] as List? ?? [], role}.toList(),
        if (!widget.onboarding) 'city': city.text.trim(),
        if (!widget.onboarding)
          'languages': languages.text
              .split(',')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toSet()
              .toList(),
      }) as Json;
      if (current(api, generation) && result['id'] == record['id']) {
        pendingAvatar = null;
        finish();
        released = true;
        widget.onSaved({...record, ...result});
      }
    } catch (failure) {
      await conflict(failure, api, generation);
    } finally {
      if (!released) finish();
    }
  }

  Future<void> chooseCity() async {
    if (busy) return;
    final api = widget.api, generation = api.sessionGeneration;
    start(selecting: true);
    try {
      final selected = await Navigator.of(context).push<Json>(MaterialPageRoute(
          builder: (context) => Scaffold(
              appBar: AppBar(title: const UiText('Город')),
              body: ApiView(
                  load: () => api.request('/geo/cities'),
                  builder: (context, data, reload) => CitySelector(
                      cities: (data['items'] as List).cast<Json>(),
                      initial: city.text,
                      onSave: (value) async =>
                          Navigator.pop(context, value))))));
      if (selected != null && current(api, generation)) {
        setState(() => city.text = selected['name']);
        notifyDraft();
      }
    } finally {
      finish();
    }
  }

  Future<void> chooseLanguages() async {
    if (busy) return;
    final api = widget.api, generation = api.sessionGeneration;
    final selected = languages.text
        .split(',')
        .map((v) => v.trim())
        .where((v) => v.isNotEmpty)
        .toSet();
    start(selecting: true);
    try {
      final result = await showDialog<List<String>>(
          context: context,
          builder: (context) => StatefulBuilder(
              builder: (context, update) => AlertDialog(
                      title: const UiText('Языки общения'),
                      content: SingleChildScrollView(
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                        for (final entry in languageNames.entries)
                          CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              title: UiText(entry.value),
                              value: selected.contains(entry.key),
                              onChanged: (value) => update(() => value == true
                                  ? selected.add(entry.key)
                                  : selected.remove(entry.key)))
                      ])),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const UiText('Отмена')),
                        TextButton(
                            onPressed: selected.isEmpty
                                ? null
                                : () =>
                                    Navigator.pop(context, selected.toList()),
                            child: const UiText('Выбрать'))
                      ])));
      if (result != null && current(api, generation)) {
        setState(() => languages.text = result.join(', '));
        notifyDraft();
      }
    } finally {
      finish();
    }
  }

  static const languageNames = {
    'ru': 'Русский',
    'kk': 'Қазақша',
    'sr': 'Српски',
    'be': 'Беларуская',
    'en': 'English'
  };
  Widget selector(
          String label, TextEditingController controller, VoidCallback pick,
          {bool location = false}) =>
      Padding(
          padding: const EdgeInsets.only(top: 18),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            UiText(label,
                style: const TextStyle(
                    fontSize: 12, height: 1.45, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Semantics(
                button: true,
                child: InkWell(
                    key: ValueKey(controller == city
                        ? 'profile-city-selector'
                        : 'profile-languages-selector'),
                    onTap: busy ? null : pick,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                        constraints: const BoxConstraints(minHeight: 52),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(color: const Color(0xFFDCE3EE)),
                            borderRadius: BorderRadius.circular(12)),
                        child: Row(children: [
                          if (location) ...[
                            const JobaIcon('pin'),
                            const SizedBox(width: 10)
                          ],
                          Expanded(
                              child: Text(
                                  controller == languages
                                      ? controller.text
                                          .split(',')
                                          .map((s) =>
                                              languageNames[s.trim()] ??
                                              s.trim())
                                          .join(', ')
                                      : controller.text,
                                  style: const TextStyle(
                                      fontSize: 14,
                                      height: 22 / 14,
                                      color: navy))),
                          const SizedBox(width: 10),
                          const JobaIcon('down')
                        ]))))
          ]));
  Widget field(String label, TextEditingController controller,
          {bool required = true}) =>
      Padding(
          padding: EdgeInsets.only(
              top: !widget.onboarding && controller == name ? 0 : 18),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            UiText(label,
                style: const TextStyle(
                    fontSize: 12, height: 1.45, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            TextFormField(
                controller: controller,
                onChanged: (_) => notifyDraft(),
                enabled: !busy,
                style: TextStyle(fontSize: 14, height: 1.45, color: muted),
                decoration: InputDecoration(
                    isDense: true,
                    constraints: const BoxConstraints(minHeight: 52),
                    contentPadding: EdgeInsets.symmetric(
                        horizontal: widget.onboarding ? 11 : 14, vertical: 16),
                    enabledBorder: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                        borderSide: BorderSide(color: Color(0xFFDCE3EE)))),
                validator: (value) {
                  final text = (value ?? '').trim();
                  if (required && text.length < 2)
                    return localize(context, 'Заполните поле');
                  if (controller == name && text.length > 60)
                    return localize(context, 'Не более 60 символов');
                  if (controller == city && text.length > 100)
                    return localize(context, 'Не более 100 символов');
                  if (controller == languages &&
                      text
                          .split(',')
                          .map((s) => s.trim())
                          .where((s) => s.isNotEmpty)
                          .any((s) =>
                              !['ru', 'kk', 'sr', 'be', 'en'].contains(s)))
                    return localize(context, 'Проверьте языки общения');
                  return null;
                })
          ]));
  Widget roleChoice(String value, String title, String subtitle, String icon) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Semantics(
              checked: role == value,
              inMutuallyExclusiveGroup: true,
              selected: role == value,
              button: true,
              child: Material(
                  color: role == value ? const Color(0xFFF1F5FE) : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                      onTap: busy
                          ? null
                          : () {
                              setState(() => role = value);
                              notifyDraft();
                            },
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
                            Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: role == value
                                            ? primary
                                            : const Color(0xFFBBC7D9),
                                        width: 1.5)),
                                child: role == value
                                    ? Center(
                                        child: Container(
                                            width: 10,
                                            height: 10,
                                            decoration: const BoxDecoration(
                                                color: primary,
                                                shape: BoxShape.circle)))
                                    : null),
                          ]))))));
  @override
  Widget build(BuildContext context) => Form(
      key: form,
      child: Column(children: [
        Expanded(
            child: ListView(padding: const EdgeInsets.all(20), children: [
          if (widget.onboarding) ...[
            const SizedBox(height: 3),
            Row(children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(width: 5),
                Expanded(
                    child: Container(
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 22),
                        decoration: BoxDecoration(
                            color: i == 0 ? primary : const Color(0xFFDFE6F0),
                            borderRadius: BorderRadius.circular(3)))),
              ]
            ]),
            Center(
                child: Semantics(
                    button: true,
                    label: localize(context, 'Добавить фото'),
                    child: InkWell(
                        onTap: busy ? null : () => avatar(),
                        borderRadius: BorderRadius.circular(24),
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          Container(
                              width: 82,
                              height: 82,
                              decoration: BoxDecoration(
                                  color: const Color(0xFFEAF0FC),
                                  border:
                                      Border.all(color: Colors.white, width: 4),
                                  borderRadius: BorderRadius.circular(24)),
                              clipBehavior: Clip.antiAlias,
                              child: record['avatar_id'] == null
                                  ? Stack(children: [
                                      const Center(
                                          child: JobaIcon('camera', size: 22)),
                                      Positioned(
                                          right: -35,
                                          bottom: -25,
                                          child: Container(
                                              width: 70,
                                              height: 70,
                                              decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  border: Border.all(
                                                      color: const Color(
                                                          0x65FFFFFF)))))
                                    ])
                                  : JobaAvatar(
                                      api: widget.api,
                                      name: name.text,
                                      id: record['avatar_id'],
                                      size: 74)),
                          const SizedBox(height: 8),
                          UiText(
                              pendingAvatar == null
                                  ? 'Добавить фото'
                                  : 'Повторить',
                              style: const TextStyle(
                                  fontSize: 12, height: 1.5, color: primary)),
                          const SizedBox(height: 4),
                          const UiText('Необязательно',
                              style: TextStyle(
                                  fontSize: 10, height: 1.4, color: muted)),
                        ])))),
            if (record['avatar_id'] != null)
              TextButton(
                  onPressed: busy ? null : () => avatar(remove: true),
                  child: const UiText('Удалить фото профиля')),
            if (pendingAvatar != null)
              TextButton(
                  onPressed: busy
                      ? null
                      : () {
                          setState(() => pendingAvatar = null);
                          notifyDraft();
                        },
                  child: const UiText('Отменить выбор фото')),
          ] else ...[
            Center(
                child: Column(children: [
              Container(
                  width: 82,
                  height: 82,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24)),
                  child: JobaAvatar(
                      api: widget.api,
                      name: name.text,
                      id: record['avatar_id'],
                      size: 74,
                      backgroundColor: const Color(0xFFE6E1F0),
                      foregroundColor: const Color(0xFF6F608A))),
              TextButton(
                  onPressed: busy ? null : () => avatar(),
                  child: UiText(
                      pendingAvatar == null ? 'Изменить фото' : 'Повторить',
                      style: const TextStyle(
                          fontSize: 12,
                          height: 1.5,
                          fontWeight: FontWeight.w400))),
              if (record['avatar_id'] != null)
                TextButton(
                    onPressed: busy ? null : () => avatar(remove: true),
                    child: const UiText('Удалить фото профиля')),
              if (pendingAvatar != null)
                TextButton(
                    onPressed: busy
                        ? null
                        : () {
                            setState(() => pendingAvatar = null);
                            notifyDraft();
                          },
                    child: const UiText('Отменить выбор фото'))
            ]))
          ],
          if (error != null) Notice(errorText(context, error!), error: true),
          field(widget.onboarding ? 'Как к вам обращаться' : 'Имя в профиле',
              name),
          if (!widget.onboarding) ...[
            selector('Город', city, chooseCity, location: true),
            selector('Языки общения', languages, chooseLanguages)
          ],
          if (widget.onboarding) ...[
            const SizedBox(height: 18),
            const UiText('Что вам интересно?',
                style: TextStyle(
                    fontSize: 12, height: 1.45, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            roleChoice('customer', 'Найти специалиста',
                'Разместить заказ или выбрать мастера', 'search'),
            roleChoice('executor', 'Найти заказы',
                'Предлагать услуги и откликаться', 'brief'),
            const Padding(
                padding: EdgeInsets.only(top: 6),
                child: UiText(
                    'Роль можно переключить позже. Для работы исполнителем потребуется проверка документа.',
                    style: TextStyle(fontSize: 12, height: 1.5, color: muted)))
          ] else ...[
            Container(
                margin: const EdgeInsets.only(top: 20),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: line),
                    borderRadius: BorderRadius.circular(16)),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const UiText('Номер телефона',
                          style: TextStyle(
                              fontSize: 12, height: 1.5, color: muted)),
                      const SizedBox(height: 8),
                      Text(record['phone'] ?? 'Номер недоступен',
                          style: const TextStyle(
                              fontSize: 16,
                              height: 23 / 16,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      const UiText(
                          'Используется как логин. Статус номера: не подтверждён.',
                          style: TextStyle(
                              fontSize: 10, height: 1.4, color: muted))
                    ])),
            const SizedBox(height: 20),
            const UiText(
                'Ваш номер не виден в публичном профиле. Документ обязателен только для работы исполнителем.',
                style: TextStyle(fontSize: 12, height: 1.5, color: muted))
          ]
        ])),
        Container(
            decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: line))),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: SafeArea(
                top: false,
                child: FilledButton(
                    onPressed: busy ? null : save,
                    child: busy && !choosing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const UiText('Сохранить профиль')))),
      ]));
}
