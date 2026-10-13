import 'dart:async';
import 'package:flutter/material.dart';
import 'l10n.dart';
import 'api.dart';
import 'theme.dart';
import 'design_icons.dart';
import 'resource_picker.dart';

class ApiView extends StatefulWidget {
  final Future<dynamic> Function() load;
  final Widget Function(BuildContext, dynamic, VoidCallback) builder;
  const ApiView({required this.load, required this.builder, super.key});
  @override
  State<ApiView> createState() => _ApiViewState();
}

class _ApiViewState extends State<ApiView> {
  late Future<dynamic> future;
  @override
  void initState() {
    super.initState();
    reload();
  }

  void reload() {
    setState(() {
      future = widget.load();
    });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<dynamic>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done)
          return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError)
          return Center(
              child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Notice(errorText(context, snapshot.error!), error: true),
                    FilledButton(
                        onPressed: reload, child: const UiText('Повторить'))
                  ])));
        return widget.builder(context, snapshot.data, reload);
      });
}

class PagedList extends StatefulWidget {
  final JobaApi api;
  final String path;
  final Json query;
  final Widget Function(Json) tile;
  final String empty;
  const PagedList(
      {required this.api,
      required this.path,
      required this.tile,
      this.query = const {},
      this.empty = 'Пока здесь ничего нет',
      super.key});
  @override
  State<PagedList> createState() => _PagedListState();
}

class _PagedListState extends State<PagedList> {
  final List<Json> rows = [];
  String? cursor;
  Object? error;
  bool busy = false, end = false;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load({bool reset = false}) async {
    if (busy && !reset) return;
    if (reset) {
      generation++;
      rows.clear();
      cursor = null;
      end = false;
    }
    final run = generation;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.api.request(widget.path, query: {
        ...widget.query,
        'limit': 20,
        if (cursor != null) 'cursor': cursor
      });
      if (!mounted || run != generation) return;
      final batch = items(result);
      for (final row in batch) {
        if (!rows.any((r) => r['id'] == row['id'])) rows.add(row);
      }
      cursor = result['meta']?['next_cursor'];
      end = cursor == null;
    } catch (e) {
      if (mounted && run == generation) error = e;
    } finally {
      if (mounted && run == generation) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
      onRefresh: () => load(reset: true),
      child: ListView(
          padding: const EdgeInsets.all(20),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            if (!busy && error == null && rows.isEmpty)
              Padding(
                  padding: const EdgeInsets.symmetric(vertical: 70),
                  child: Column(children: [
                    const Icon(Icons.inbox_outlined, size: 48, color: primary),
                    const SizedBox(height: 16),
                    UiText(widget.empty, textAlign: TextAlign.center)
                  ])),
            ...rows.map(widget.tile),
            if (error != null) Notice(errorText(context, error!), error: true),
            if (busy)
              const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: CircularProgressIndicator())),
            if (!busy && (!end || error != null))
              OutlinedButton(
                  onPressed: () => load(
                      reset: error is ApiException &&
                          (error as ApiException).details['restart_required'] ==
                              true),
                  child: UiText(error == null ? 'Показать ещё' : 'Повторить')),
          ]));
}

class InputSpec {
  final String key, label;
  final String initial;
  final bool secret, multiline;
  final bool required, translateOptions;
  final String? hint;
  final IconData? prefixIcon;
  final String? originalIcon;
  final Map<String, String>? options;
  final JobaApi? pickerApi;
  final String? pickerPath;
  final Json pickerQuery;
  final TextInputType? keyboard;
  final String? Function(String)? validate;
  final void Function(String)? changed;
  const InputSpec(this.key, this.label,
      {this.initial = '',
      this.hint,
      this.prefixIcon,
      this.originalIcon,
      this.secret = false,
      this.multiline = false,
      this.required = true,
      this.translateOptions = true,
      this.options,
      this.pickerApi,
      this.pickerPath,
      this.pickerQuery = const {},
      this.keyboard,
      this.validate,
      this.changed});
}

class ActionForm extends StatefulWidget {
  final List<InputSpec> fields;
  final String button;
  final Future<void> Function(Map<String, String>) submit;
  final List<Widget> before, after, afterFields;
  final Map<String, List<Widget>> beforeField;
  final bool authLayout, stickySubmit, externalBusy, submitEnabled;
  const ActionForm(
      {required this.fields,
      required this.submit,
      this.button = 'Сохранить',
      this.authLayout = false,
      this.stickySubmit = false,
      this.externalBusy = false,
      this.submitEnabled = true,
      this.afterFields = const [],
      this.beforeField = const {},
      this.before = const [],
      this.after = const [],
      super.key});
  @override
  State<ActionForm> createState() => _ActionFormState();
}

class _ActionFormState extends State<ActionForm> {
  final form = GlobalKey<FormState>();
  late Map<String, TextEditingController> controllers;
  final Set<String> visible = {};
  final Map<String, String> pickedLabels = {};
  bool busy = false;
  bool get disabled => busy || widget.externalBusy;
  Object? error;
  @override
  void initState() {
    super.initState();
    controllers = {
      for (final f in widget.fields)
        f.key: TextEditingController(text: f.initial)
    };
  }

  @override
  void didUpdateWidget(ActionForm old) {
    super.didUpdateWidget(old);
    final keys = widget.fields.map((f) => f.key).toSet();
    for (final key in controllers.keys.toList()) {
      if (!keys.contains(key)) controllers.remove(key)!.dispose();
    }
    for (final field in widget.fields) {
      controllers.putIfAbsent(
          field.key, () => TextEditingController(text: field.initial));
    }
  }

  @override
  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> submit() async {
    if (disabled || !widget.submitEnabled || !form.currentState!.validate())
      return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.submit(controllers.map((k, v) => MapEntry(k, v.text)));
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget content(BuildContext context) =>
      ListView(padding: const EdgeInsets.all(20), children: [
        ...widget.before,
        if (error != null) Notice(errorText(context, error!), error: true),
        for (final field in widget.fields) ...[
          ...?widget.beforeField[field.key],
          Padding(
              padding: EdgeInsets.only(
                  bottom: widget.authLayout && field == widget.fields.last
                      ? 20
                      : 18),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: UiText(field.label,
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w700))),
                    if (field.pickerPath != null)
                      FormField<String>(
                          initialValue: controllers[field.key]!.text,
                          validator: (value) =>
                              field.required && (value ?? '').isEmpty
                                  ? localize(context, 'Выберите значение')
                                  : null,
                          builder: (state) => InkWell(
                              onTap: disabled
                                  ? null
                                  : () async {
                                      final result = await pickResource(
                                          context,
                                          field.pickerApi!,
                                          field.pickerPath!,
                                          field.pickerQuery,
                                          field.label,
                                          optional: !field.required);
                                      if (!mounted || result == null) return;
                                      final id = result['id'] as String;
                                      controllers[field.key]!.text = id;
                                      state.didChange(id);
                                      setState(() => pickedLabels[field.key] =
                                          result['title'] ?? id);
                                      field.changed?.call(id);
                                    },
                              child: InputDecorator(
                                  decoration: InputDecoration(
                                      errorText: state.errorText),
                                  child: Row(children: [
                                    Expanded(
                                        child: Text(
                                            pickedLabels[field.key] ??
                                                field.options?[
                                                    controllers[field.key]!
                                                        .text] ??
                                                (controllers[field.key]!
                                                        .text
                                                        .isEmpty
                                                    ? localize(
                                                        context,
                                                        field.required
                                                            ? 'Выберите значение'
                                                            : 'Без связи с заказом')
                                                    : localize(context,
                                                        'Выбранный заказ')),
                                            style:
                                                const TextStyle(fontSize: 14))),
                                    const JobaIcon('down', size: 18)
                                  ]))))
                    else if (field.options != null)
                      DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue:
                              field.options!.containsKey(field.initial)
                                  ? field.initial
                                  : null,
                          items: field.options!.entries
                              .map((e) => DropdownMenuItem(
                                  value: e.key,
                                  child: field.translateOptions
                                      ? UiText(e.value)
                                      : Text(e.value)))
                              .toList(),
                          onChanged: disabled
                              ? null
                              : (v) {
                                  controllers[field.key]!.text = v ?? '';
                                  field.changed?.call(v ?? '');
                                },
                          validator: (v) =>
                              field.required && (v == null || v.isEmpty)
                                  ? localize(context, 'Выберите значение')
                                  : null)
                    else
                      TextFormField(
                          controller: controllers[field.key],
                          enabled: !disabled,
                          onChanged: field.changed,
                          keyboardType: field.keyboard,
                          style: const TextStyle(
                              fontSize: 14, letterSpacing: 0, color: navy),
                          maxLines: field.multiline ? 5 : 1,
                          obscureText:
                              field.secret && !visible.contains(field.key),
                          autocorrect: !field.secret,
                          enableSuggestions: !field.secret,
                          decoration: InputDecoration(
                              constraints: widget.authLayout
                                  ? BoxConstraints(
                                      minHeight: field.secret ? 74 : 52)
                                  : null,
                              hintText: field.hint == null
                                  ? null
                                  : localize(context, field.hint!),
                              hintStyle: const TextStyle(
                                  color: Color(0xFF6B7890), fontSize: 14),
                              prefixIcon: field.originalIcon != null
                                  ? Padding(
                                      padding: const EdgeInsets.all(14),
                                      child: JobaIcon(field.originalIcon!))
                                  : field.prefixIcon == null
                                      ? null
                                      : Icon(field.prefixIcon, color: navy),
                              contentPadding: widget.authLayout && field.secret
                                  ? const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 25)
                                  : null,
                              suffixIcon: field.secret
                                  ? IconButton(
                                      tooltip: localize(
                                          context,
                                          visible.contains(field.key)
                                              ? 'Скрыть пароль'
                                              : 'Показать пароль'),
                                      onPressed: () => setState(() =>
                                          visible.contains(field.key)
                                              ? visible.remove(field.key)
                                              : visible.add(field.key)),
                                      icon: visible.contains(field.key)
                                          ? const Icon(
                                              Icons.visibility_off_outlined)
                                          : const JobaIcon('eye'))
                                  : null),
                          validator: (v) {
                            if (field.required && (v ?? '').trim().isEmpty)
                              return localize(context, 'Заполните поле');
                            final problem = field.validate?.call(v ?? '');
                            return problem == null
                                ? null
                                : localize(context, problem);
                          }),
                  ])),
        ],
        ...widget.afterFields,
        if (!widget.stickySubmit) submitButton(),
        if (!widget.stickySubmit) SizedBox(height: widget.authLayout ? 0 : 12),
        ...widget.after,
      ]);
  Widget submitButton() => FilledButton(
      onPressed: disabled || !widget.submitEnabled ? null : submit,
      child: disabled
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white))
          : UiText(widget.button));
  @override
  Widget build(BuildContext context) => Form(
      key: form,
      child: widget.stickySubmit
          ? Column(children: [
              Expanded(child: content(context)),
              SafeArea(
                  top: false,
                  child: Container(
                      color: Colors.white,
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                      child: submitButton()))
            ])
          : content(context));
}

class DataCard extends StatelessWidget {
  final String title, subtitle, status;
  final bool translateTitle;
  final VoidCallback? onTap;
  final Widget? footer;
  const DataCard(this.title,
      {this.subtitle = '',
      this.translateTitle = false,
      this.status = '',
      this.onTap,
      this.footer,
      super.key});
  @override
  Widget build(BuildContext context) => Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: line)),
      child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (status.isNotEmpty)
                      Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                              color: const Color(0xFFEAF0FC),
                              borderRadius: BorderRadius.circular(7)),
                          child: UiText(status,
                              style: const TextStyle(
                                  fontSize: 10,
                                  height: 1.6,
                                  color: primary,
                                  fontWeight: FontWeight.w700))),
                    Text(translateTitle ? localize(context, title) : title,
                        style: const TextStyle(
                            fontSize: 16,
                            height: 1.44,
                            letterSpacing: -.2,
                            fontWeight: FontWeight.w700)),
                    if (subtitle.isNotEmpty)
                      Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(subtitle,
                              style: const TextStyle(
                                  color: Color(0xFF627187),
                                  fontSize: 12,
                                  height: 1.5))),
                    if (footer != null)
                      Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: footer),
                  ]))));
}

class PrivatePhoto extends StatelessWidget {
  final JobaApi api;
  final String id;
  const PrivatePhoto({required this.api, required this.id, super.key});
  void open(BuildContext context) {
    final generation = api.sessionGeneration;
    showDialog<void>(
        context: context,
        builder: (dialogContext) => Dialog.fullscreen(
            backgroundColor: Colors.black,
            child: AnimatedBuilder(
                animation: api,
                builder: (_, __) => SafeArea(
                        child: Column(children: [
                      Align(
                          alignment: Alignment.centerRight,
                          child: IconButton(
                              tooltip: localize(dialogContext, 'Закрыть'),
                              onPressed: () => Navigator.pop(dialogContext),
                              icon: const JobaIcon('close',
                                  color: Colors.white))),
                      Expanded(
                          child: !api.authenticated ||
                                  api.sessionGeneration != generation
                              ? const Center(child: Notice('Файл недоступен'))
                              : ApiView(
                                  load: () => api.download(id),
                                  builder: (_, full, retry) =>
                                      InteractiveViewer(
                                          minScale: .5,
                                          maxScale: 5,
                                          child: Center(
                                              child: Image.memory(full,
                                                  fit: BoxFit.contain)))))
                    ])))));
  }

  @override
  Widget build(BuildContext context) => ApiView(
      key: ValueKey('${api.sessionGeneration}:$id'),
      load: () => api.download(id, variant: 'preview'),
      builder: (c, bytes, reload) => InkWell(
          onTap: () => open(context),
          child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.memory(bytes,
                  height: 180,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  cacheWidth: (MediaQuery.sizeOf(context).width *
                          MediaQuery.devicePixelRatioOf(context))
                      .ceil()
                      .clamp(1, 1920),
                  errorBuilder: (c, error, stack) =>
                      const Notice('Не удалось показать фотографию')))));
}

class SearchListings extends StatefulWidget {
  final JobaApi api;
  final String path;
  final Json initialFilters;
  final Widget Function(Json) tile;
  const SearchListings(
      {required this.api,
      required this.path,
      required this.tile,
      this.initialFilters = const {},
      super.key});
  @override
  State<SearchListings> createState() => _SearchListingsState();
}

class _SearchListingsState extends State<SearchListings> {
  final search = TextEditingController();
  Json filters = {};
  String query = '';
  Timer? debounce;
  @override
  void initState() {
    super.initState();
    filters = Map<String, dynamic>.from(widget.initialFilters);
  }

  Future<void> chooseFilters() async {
    try {
      final data = await Future.wait([
        widget.api.request('/catalog/categories'),
        widget.api.request('/geo/cities')
      ]);
      var category = filters['category_id'] as String? ?? '',
          city = filters['city'] as String? ?? '';
      if (!mounted) return;
      if (category.isNotEmpty &&
          !items(data[0]).any((item) => item['id'] == category)) category = '';
      final result = await showModalBottomSheet<Json>(
          context: context,
          isScrollControlled: true,
          builder: (c) => SafeArea(
              child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Heading('Фильтры поиска'),
                    DropdownButtonFormField<String>(
                        initialValue: category,
                        decoration: InputDecoration(
                            labelText: localize(context, 'Категория')),
                        items: [
                          const DropdownMenuItem(
                              value: '', child: UiText('Все категории')),
                          for (final item in items(data[0]))
                            DropdownMenuItem(
                                value: item['id'], child: Text(item['name']))
                        ],
                        onChanged: (v) => category = v!),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                        initialValue: city,
                        decoration: InputDecoration(
                            labelText: localize(context, 'Город')),
                        items: [
                          const DropdownMenuItem(
                              value: '', child: UiText('Все города')),
                          if (city.isNotEmpty &&
                              !items(data[1])
                                  .any((item) => item['name'] == city))
                            DropdownMenuItem(value: city, child: Text(city)),
                          for (final item in items(data[1]))
                            DropdownMenuItem(
                                value: item['name'], child: Text(item['name']))
                        ],
                        onChanged: (v) => city = v!),
                    const SizedBox(height: 20),
                    FilledButton(
                        onPressed: () => Navigator.pop(c, {
                              if (category.isNotEmpty) 'category_id': category,
                              if (city.isNotEmpty) 'city': city
                            }),
                        child: const UiText('Показать результаты')),
                  ]))));
      if (result != null && mounted) setState(() => filters = result);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(errorText(context, e))));
    }
  }

  @override
  void dispose() {
    debounce?.cancel();
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: TextField(
                controller: search,
                decoration: InputDecoration(
                    hintText: localize(context, 'Что ищете?'),
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                        tooltip: localize(context, 'Фильтры'),
                        onPressed: chooseFilters,
                        icon: const Icon(Icons.tune))),
                onChanged: (v) {
                  debounce?.cancel();
                  debounce = Timer(const Duration(milliseconds: 300), () {
                    if (mounted) setState(() => query = v.trim());
                  });
                })),
        if (filters.isNotEmpty)
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(children: [
                Expanded(
                    child: Text(filters['city'] ??
                        localize(context, 'Выбрана категория'))),
                TextButton(
                    onPressed: () => setState(() => filters = {}),
                    child: const UiText('Сбросить'))
              ])),
        Expanded(
            child: PagedList(
                key: ValueKey('${widget.path}:$query:$filters'),
                api: widget.api,
                path: widget.path,
                query: {...filters, if (query.isNotEmpty) 'q': query},
                tile: widget.tile,
                empty: 'По вашему запросу ничего не найдено')),
      ]);
}
