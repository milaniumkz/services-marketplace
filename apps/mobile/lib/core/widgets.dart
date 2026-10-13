import 'dart:async';
import 'package:flutter/material.dart';
import 'l10n.dart';
import 'api.dart';
import 'theme.dart';

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
                  onPressed: load,
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
  final Map<String, String>? options;
  final TextInputType? keyboard;
  final String? Function(String)? validate;
  final void Function(String)? changed;
  const InputSpec(this.key, this.label,
      {this.initial = '',
      this.hint,
      this.prefixIcon,
      this.secret = false,
      this.multiline = false,
      this.required = true,
      this.translateOptions = true,
      this.options,
      this.keyboard,
      this.validate,
      this.changed});
}

class ActionForm extends StatefulWidget {
  final List<InputSpec> fields;
  final String button;
  final Future<void> Function(Map<String, String>) submit;
  final List<Widget> before, after;
  final bool authLayout;
  const ActionForm(
      {required this.fields,
      required this.submit,
      this.button = 'Сохранить',
      this.authLayout = false,
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
  bool busy = false;
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
    if (busy || !form.currentState!.validate()) return;
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

  @override
  Widget build(BuildContext context) => Form(
      key: form,
      child: ListView(padding: const EdgeInsets.all(20), children: [
        ...widget.before,
        if (error != null) Notice(errorText(context, error!), error: true),
        for (final field in widget.fields)
          Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: UiText(field.label,
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w700))),
                    if (field.options != null)
                      DropdownButtonFormField<String>(
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
                          onChanged: busy
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
                          enabled: !busy,
                          keyboardType: field.keyboard,
                          maxLines: field.multiline ? 5 : 1,
                          obscureText:
                              field.secret && !visible.contains(field.key),
                          autocorrect: !field.secret,
                          enableSuggestions: !field.secret,
                          decoration: InputDecoration(
                              hintText: field.hint == null
                                  ? null
                                  : localize(context, field.hint!),
                              hintStyle: const TextStyle(
                                  color: Color(0xFF6B7890), fontSize: 14),
                              prefixIcon: field.prefixIcon == null
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
                                      icon: Icon(visible.contains(field.key)
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined))
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
        FilledButton(
            onPressed: busy ? null : submit,
            child: busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : UiText(widget.button)),
        const SizedBox(height: 12),
        ...widget.after,
      ]));
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
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: line)),
      child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (status.isNotEmpty)
                      Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                              color: canvas,
                              borderRadius: BorderRadius.circular(8)),
                          child: UiText(status,
                              style: const TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.w700))),
                    Text(translateTitle ? localize(context, title) : title,
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w700)),
                    if (subtitle.isNotEmpty)
                      Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(subtitle,
                              style: const TextStyle(
                                  color: Color(0xFF6B7890),
                                  fontSize: 13,
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
  @override
  Widget build(BuildContext context) => ApiView(
      key: ValueKey(id),
      load: () => api.download(id),
      builder: (c, bytes, reload) => ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.memory(bytes,
              height: 180,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (c, e, stack) =>
                  const Notice('Не удалось показать фотографию'))));
}

class SearchListings extends StatefulWidget {
  final JobaApi api;
  final String path;
  final Widget Function(Json) tile;
  const SearchListings(
      {required this.api, required this.path, required this.tile, super.key});
  @override
  State<SearchListings> createState() => _SearchListingsState();
}

class _SearchListingsState extends State<SearchListings> {
  final search = TextEditingController();
  Json filters = {};
  String query = '';
  Timer? debounce;
  Future<void> chooseFilters() async {
    try {
      final data = await Future.wait([
        widget.api.request('/catalog/categories'),
        widget.api.request('/geo/cities')
      ]);
      var category = filters['category_id'] as String? ?? '',
          city = filters['city'] as String? ?? '';
      if (!mounted) return;
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
