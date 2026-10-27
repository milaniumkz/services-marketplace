import 'package:intl/intl.dart';
import 'design_widgets.dart' show JobaBadge;
import 'design_states.dart';
import '../screens/search_filters.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'l10n.dart';
import 'api.dart';
import 'theme.dart';
import 'design_icons.dart';
import 'resource_picker.dart';
import 'reference_picker.dart';

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
  final Widget? header, footer, emptyState, loadingState;
  final Widget Function(Json)? emptyStateBuilder;
  final Widget Function(List<Json>)? contentBuilder;
  final VoidCallback? onReset;
  final ValueChanged<Json>? onMetadata;
  final ValueChanged<String>? onStatus;
  final Widget Function(Object, VoidCallback)? errorState;
  const PagedList(
      {required this.api,
      required this.path,
      required this.tile,
      this.query = const {},
      this.empty = 'Пока здесь ничего нет',
      this.header,
      this.footer,
      this.emptyState,
      this.emptyStateBuilder,
      this.contentBuilder,
      this.onReset,
      this.onMetadata,
      this.onStatus,
      this.loadingState,
      this.errorState,
      super.key});
  @override
  State<PagedList> createState() => _PagedListState();
}

class _PagedListState extends State<PagedList> {
  final List<Json> rows = [];
  String? cursor;
  Json metadata = {};
  Object? error;
  bool busy = false, end = false;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    load();
  }

  void report(String status, int run) {
    if (widget.onStatus == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && run == generation && (status != 'loading' || busy))
        widget.onStatus?.call(status);
    });
  }

  Future<void> load({bool reset = false}) async {
    if (busy && !reset) return;
    if (reset) {
      widget.onReset?.call();
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
    if (rows.isEmpty) report('loading', run);
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
      metadata = Map<String, dynamic>.from(result['meta'] as Map? ?? {});
      widget.onMetadata?.call(metadata);
      cursor = result['meta']?['next_cursor'];
      end = cursor == null;
    } catch (e) {
      if (mounted && run == generation) error = e;
    } finally {
      if (mounted && run == generation) {
        setState(() => busy = false);
        final failure = error;
        report(
            rows.isNotEmpty
                ? 'data'
                : failure == null
                    ? 'empty'
                    : failure is ApiException && failure.code == 'OFFLINE'
                        ? 'offline'
                        : failure is ApiException &&
                                failure.status > 0 &&
                                failure.status < 500 &&
                                !['TIMEOUT', 'INVALID_RESPONSE']
                                    .contains(failure.code)
                            ? 'domain-error'
                            : 'error',
            run);
      }
    }
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
      onRefresh: () => load(reset: true),
      child: ListView(
          padding: const EdgeInsets.all(20),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            if (widget.header != null) widget.header!,
            if (!busy && error == null && rows.isEmpty)
              widget.emptyStateBuilder?.call(metadata) ??
                  widget.emptyState ??
                  Padding(
                      padding: const EdgeInsets.symmetric(vertical: 70),
                      child: Column(children: [
                        const Icon(Icons.inbox_outlined,
                            size: 48, color: primary),
                        const SizedBox(height: 16),
                        UiText(widget.empty, textAlign: TextAlign.center)
                      ])),
            if (widget.contentBuilder != null && rows.isNotEmpty)
              widget.contentBuilder!(rows)
            else ...rows.map(widget.tile),
            if (error != null)
              rows.isEmpty && widget.errorState != null
                  ? widget.errorState!(error!, () => load(reset: true))
                  : Notice(errorText(context, error!), error: true),
            if (busy && rows.isEmpty && widget.loadingState != null)
              widget.loadingState!
            else if (busy)
              const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: CircularProgressIndicator())),
            if (!busy &&
                (!end || error != null) &&
                !(rows.isEmpty && error != null && widget.errorState != null))
              OutlinedButton(
                  onPressed: () => load(
                      reset: error is ApiException &&
                          (error as ApiException).details['restart_required'] ==
                              true),
                  child: UiText(error == null ? 'Показать ещё' : 'Повторить')),
            if (widget.footer != null) widget.footer!,
          ]));
}

class InputSpec {
  final String key, label;
  final String initial;
  final bool secret, multiline;
  final bool required, translateOptions;
  final int lines;
  final double? minHeight;
  final String? hint;
  final IconData? prefixIcon;
  final String? originalIcon;
  final Map<String, String>? options;
  final List<Json>? referenceItems;
  final bool cityReference;
  final JobaApi? pickerApi;
  final String? pickerPath;
  final Json pickerQuery;
  final TextInputType? keyboard;
  final TextInputAction? inputAction;
  final Iterable<String>? autofillHints;
  final String? Function(String)? validate;
  final void Function(String)? changed;
  const InputSpec(
    this.key,
    this.label, {
    this.initial = '',
    this.hint,
    this.prefixIcon,
    this.originalIcon,
    this.secret = false,
    this.multiline = false,
    this.lines = 5,
    this.minHeight,
    this.required = true,
    this.translateOptions = true,
    this.options,
    this.referenceItems,
    this.cityReference = false,
    this.pickerApi,
    this.pickerPath,
    this.pickerQuery = const {},
    this.keyboard,
    this.inputAction,
    this.autofillHints,
    this.validate,
    this.changed,
  });
}

class ActionForm extends StatefulWidget {
  final List<InputSpec> fields;
  final String button;
  final Future<void> Function(Map<String, String>) submit;
  final List<Widget> before, after, afterFields;
  final List<Widget>? credentialFailureAfter;
  final Map<String, List<Widget>> beforeField, afterField;
  final bool authLayout, loginLayout, stickySubmit, externalBusy, submitEnabled;
  final Object? errorResetKey;
  final ValueChanged<bool>? onBusyChanged;
  final ValueChanged<Object?>? onErrorChanged;
  final Map<String,String> initialValues;
  final ValueChanged<Map<String,String>>? onValuesChanged;
  const ActionForm({
    required this.fields,
    required this.submit,
    this.button = 'Сохранить',
    this.authLayout = false,
    this.loginLayout = false,
    this.errorResetKey,
    this.onBusyChanged,
    this.onErrorChanged,
    this.initialValues = const {},
    this.onValuesChanged,
    this.stickySubmit = false,
    this.externalBusy = false,
    this.submitEnabled = true,
    this.afterFields = const [],
    this.credentialFailureAfter,
    this.beforeField = const {},
    this.afterField = const {},
    this.before = const [],
    this.after = const [],
    super.key,
  });
  @override
  State<ActionForm> createState() => _ActionFormState();
}

class _ActionFormState extends State<ActionForm> {
  final form = GlobalKey<FormState>();
  late Map<String, TextEditingController> controllers;
  final Set<String> visible = {};
  final Map<String, String> pickedLabels = {};
  bool busy = false;
  int cooldownSeconds = 0;
  Timer? cooldownTimer;
  bool get disabled => busy || widget.externalBusy;
  bool get credentialError =>
      widget.loginLayout &&
      error is ApiException &&
      [
        'INVALID_CREDENTIALS',
        'RATE_LIMITED',
      ].contains((error as ApiException).code);
  Object? error;
  @override
  void initState() {
    super.initState();
    controllers = {
      for (final f in widget.fields)
        f.key: createController(f),
    };
  }

  TextEditingController createController(InputSpec field) {
    final controller=TextEditingController(text:widget.initialValues[field.key]??field.initial);
    if(widget.onValuesChanged!=null) controller.addListener(() {
      widget.onValuesChanged?.call(controllers.map((key,value)=>MapEntry(key,value.text)));
    });
    return controller;
  }

  @override
  void didUpdateWidget(ActionForm old) {
    super.didUpdateWidget(old);
    if (widget.errorResetKey != old.errorResetKey) {
      error = null;
      cooldownTimer?.cancel();
      cooldownSeconds = 0;
      if (widget.loginLayout) visible.clear();
    }
    final keys = widget.fields.map((f) => f.key).toSet();
    for (final key in controllers.keys.toList()) {
      if (!keys.contains(key)) controllers.remove(key)!.dispose();
    }
    for (final field in widget.fields) {
      controllers.putIfAbsent(
        field.key,
        () => createController(field),
      );
    }
  }

  @override
  void dispose() {
    cooldownTimer?.cancel();
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> submit() async {
    if (disabled ||
        cooldownSeconds > 0 ||
        !widget.submitEnabled ||
        !form.currentState!.validate())
      return;
    setState(() {
      busy = true;
      error = null;
    });
    widget.onErrorChanged?.call(null);
    widget.onBusyChanged?.call(true);
    try {
      await widget.submit(controllers.map((k, v) => MapEntry(k, v.text)));
    } catch (e) {
      if (mounted) {
        setState(() => error = e);
        widget.onErrorChanged?.call(e);
        final seconds = e is ApiException && e.code == 'RATE_LIMITED'
            ? e.details['retry_after_seconds']
            : null;
        if (widget.loginLayout &&
            seconds is int &&
            seconds > 0 &&
            seconds <= 86400) {
          cooldownTimer?.cancel();
          setState(() => cooldownSeconds = seconds);
          cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
            if (!mounted) {
              timer.cancel();
              return;
            }
            final remaining = seconds - timer.tick;
            setState(() => cooldownSeconds = remaining > 0 ? remaining : 0);
            if (remaining <= 0) timer.cancel();
          });
        }
      }
    } finally {
      if (mounted) setState(() => busy = false);
      widget.onBusyChanged?.call(false);
    }
  }

  String countdownMessage(BuildContext context) => localize(
    context,
    Intl.plural(
      cooldownSeconds,
      locale: 'ru',
      one: 'Слишком много попыток. Следующая попытка через {seconds} секунду.',
      few: 'Слишком много попыток. Следующая попытка через {seconds} секунды.',
      other: 'Слишком много попыток. Следующая попытка через {seconds} секунд.',
    ),
  ).replaceAll('{seconds}', '$cooldownSeconds');

  Widget content(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      if (credentialError)
        const UiHeading('Попробуйте ещё раз', 'Проверьте номер и пароль.')
      else
        ...widget.before,
      if (error != null && !credentialError)
        Notice(errorText(context, error!), error: true),
      for (final field in widget.fields) ...[
        ...?widget.beforeField[field.key],
        Padding(
          padding: EdgeInsets.only(
            bottom: widget.authLayout && field == widget.fields.last ? 20 : 18,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: UiText(
                  field.label,
                  style: TextStyle(
                    fontSize: 12,
                    height: widget.authLayout ? 1.5 : null,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (field.pickerPath != null || field.referenceItems != null)
                FormField<String>(
                  initialValue: controllers[field.key]!.text,
                  validator: (value) => field.required && (value ?? '').isEmpty
                      ? localize(context, 'Выберите значение')
                      : null,
                  builder: (state) => InkWell(
                    onTap: disabled
                        ? null
                        : () async {
                            final result = field.referenceItems != null
                                ? await pickReference(context, field.referenceItems!, cities: field.cityReference, initial: controllers[field.key]!.text, optional: !field.required)
                                : await pickResource(
                              context,
                              field.pickerApi!,
                              field.pickerPath!,
                              field.pickerQuery,
                              field.label,
                              optional: !field.required,
                            );
                            if (!mounted || result == null) return;
                            final id = result['id'] as String;
                            controllers[field.key]!.text = id;
                            state.didChange(id);
                            setState(
                              () => pickedLabels[field.key] =
                                  result['name'] ?? result['title'] ?? id,
                            );
                            field.changed?.call(id);
                          },
                    child: InputDecorator(
                      decoration: InputDecoration(errorText: state.errorText),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              pickedLabels[field.key] ??
                                  field.options?[controllers[field.key]!
                                      .text] ??
                                  (controllers[field.key]!.text.isEmpty
                                      ? localize(
                                          context,
                                          field.required
                                              ? 'Выберите значение'
                                              : 'Без связи с заказом',
                                        )
                                      : localize(context, 'Выбранный заказ')),
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                          const JobaIcon('down', size: 18),
                        ],
                      ),
                    ),
                  ),
                )
              else if (field.options != null)
                DropdownButtonFormField<String>(
                  style: const TextStyle(
                    fontSize: 14,
                    color: navy,
                    fontFamily: 'Noto',
                  ),
                  icon: const JobaIcon('down', size: 18),
                  isExpanded: true,
                  initialValue: field.options!.containsKey(field.initial)
                      ? field.initial
                      : null,
                  items: field.options!.entries
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.key,
                          child: field.translateOptions
                              ? UiText(e.value)
                              : Text(e.value),
                        ),
                      )
                      .toList(),
                  onChanged: disabled
                      ? null
                      : (v) {
                          controllers[field.key]!.text = v ?? '';
                          field.changed?.call(v ?? '');
                        },
                  validator: (v) => field.required && (v == null || v.isEmpty)
                      ? localize(context, 'Выберите значение')
                      : null,
                )
              else
                TextFormField(
                  controller: controllers[field.key],
                  enabled: !disabled,
                  onChanged: field.changed,
                  keyboardType: field.keyboard,
                  textInputAction: field.inputAction,
                  autofillHints: field.autofillHints,
                  onFieldSubmitted:
                      field == widget.fields.last &&
                          (widget.authLayout ||
                              field.inputAction == TextInputAction.done)
                      ? (_) => submit()
                      : null,
                  style: const TextStyle(
                    fontSize: 14,
                    letterSpacing: 0,
                    color: navy,
                  ),
                  maxLines: field.multiline ? field.lines : 1,
                  obscureText: field.secret && !visible.contains(field.key),
                  autocorrect: !field.secret,
                  enableSuggestions: !field.secret,
                  decoration: InputDecoration(
                    isDense: widget.authLayout ? true : null,
                    errorText: credentialError && field.secret
                        ? localize(
                            context,
                            'Не удалось войти. Проверьте данные или обратитесь за помощью.',
                          )
                        : null,
                    errorStyle: widget.loginLayout
                        ? const TextStyle(
                            fontSize: 11,
                            height: 1.45,
                            color: Color(0xFFB73838),
                          )
                        : null,
                    errorMaxLines: widget.loginLayout ? 3 : null,
                    errorBorder: widget.loginLayout
                        ? OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Color(0xFFB73838),
                            ),
                          )
                        : null,
                    focusedErrorBorder: widget.loginLayout
                        ? OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Color(0xFFB73838),
                              width: 2,
                            ),
                          )
                        : null,
                    enabledBorder: widget.authLayout
                        ? OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Color(0xFFDCE3EE),
                            ),
                          )
                        : null,
                    constraints: widget.authLayout
                        ? BoxConstraints(minHeight: field.secret ? 74 : 52)
                        : field.minHeight == null
                        ? null
                        : BoxConstraints(minHeight: field.minHeight!),
                    hintText: field.hint == null
                        ? null
                        : localize(context, field.hint!),
                    hintStyle: const TextStyle(
                      color: Color(0xFF627187),
                      fontSize: 14,
                    ),
                    prefixIconConstraints:
                        widget.authLayout && field.originalIcon != null
                        ? const BoxConstraints(minWidth: 44, maxWidth: 44)
                        : null,
                    prefixIcon: field.originalIcon != null
                        ? Padding(
                            padding: EdgeInsets.fromLTRB(
                              14,
                              14,
                              widget.authLayout ? 8 : 14,
                              14,
                            ),
                            child: JobaIcon(field.originalIcon!),
                          )
                        : field.prefixIcon == null
                        ? null
                        : Icon(field.prefixIcon, color: navy),
                    contentPadding: widget.authLayout
                        ? EdgeInsets.symmetric(
                            horizontal: field.secret ? 11 : 14,
                            vertical: field.secret ? 26 : 15,
                          )
                        : null,
                    suffixIcon: field.secret
                        ? Padding(
                            padding: EdgeInsets.only(
                              right: widget.authLayout ? 15 : 0,
                            ),
                            child: IconButton(
                              tooltip: localize(
                                context,
                                visible.contains(field.key)
                                    ? 'Скрыть пароль'
                                    : 'Показать пароль',
                              ),
                              onPressed: () => setState(
                                () => visible.contains(field.key)
                                    ? visible.remove(field.key)
                                    : visible.add(field.key),
                              ),
                              icon: visible.contains(field.key)
                                  ? const Icon(Icons.visibility_off_outlined)
                                  : const JobaIcon('eye'),
                            ),
                          )
                        : null,
                  ),
                  validator: (v) {
                    if (field.required && (v ?? '').trim().isEmpty)
                      return localize(context, 'Заполните поле');
                    final problem = field.validate?.call(v ?? '');
                    return problem == null ? null : localize(context, problem);
                  },
                ),
              ...?widget.afterField[field.key],
            ],
          ),
        ),
      ],
      ...widget.afterFields,
      if (cooldownSeconds > 0) ...[
        Notice(
          countdownMessage(context),
          warning: true,
          backgroundColor: const Color(0xFFFFF5D9),
          textColor: const Color(0xFF7B5B18),
          iconSize: 22,
          icon: 'clock',
          margin: EdgeInsets.zero,
        ),
        const SizedBox(height: 20),
      ],
      if (!widget.stickySubmit) submitButton(),
      if (!widget.stickySubmit) SizedBox(height: widget.authLayout ? 0 : 12),
      ...(credentialError && widget.credentialFailureAfter != null
          ? widget.credentialFailureAfter!
          : widget.after),
    ],
  );
  Widget submitButton() => FilledButton(
    style: widget.authLayout ? FilledButton.styleFrom(
        disabledBackgroundColor: line,
        disabledForegroundColor: const Color(0xFF738095)) : null,
    onPressed: disabled || cooldownSeconds > 0 || !widget.submitEnabled
        ? null
        : submit,
    child: disabled
        ? SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: widget.authLayout ? const Color(0xFF738095) : Colors.white,
            ),
          )
        : cooldownSeconds > 0
        ? Text(
            '${localize(context, 'Повторить через')} ${(cooldownSeconds ~/ 60).toString().padLeft(2, '0')}:${(cooldownSeconds % 60).toString().padLeft(2, '0')}',
          )
        : UiText(credentialError ? 'Повторить' : widget.button),
  );
  @override
  Widget build(BuildContext context) => Form(
    key: form,
    child: widget.stickySubmit
        ? Column(
            children: [
              Expanded(child: content(context)),
              SafeArea(
                top: false,
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: line)),
                  ),
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                  child: submitButton(),
                ),
              ),
            ],
          )
        : content(context),
  );
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
  final double? height;
  final VoidCallback? onOpen;
  final List<String> gallery;
  final String? caption;
  const PrivatePhoto(
      {required this.api,
      required this.id,
      this.height = 180,
      this.onOpen,
      this.gallery = const [],
      this.caption,
      super.key});
  void open(BuildContext context) {
    final photos = gallery.contains(id) ? gallery : [id];
    showDialog<void>(
        context: context,
        useSafeArea: false,
        builder: (_) => _PrivatePhotoViewer(
            api: api,
            photos: photos,
            initialIndex: photos.indexOf(id),
            caption: caption));
  }

  @override
  Widget build(BuildContext context) => ApiView(
      key: ValueKey('${api.sessionGeneration}:$id'),
      load: () => api.download(id, variant: 'preview'),
      builder: (c, bytes, reload) => InkWell(
          onTap: onOpen ?? () => open(context),
          child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.memory(bytes,
                  height: height,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  cacheWidth: (MediaQuery.sizeOf(context).width *
                          MediaQuery.devicePixelRatioOf(context))
                      .ceil()
                      .clamp(1, 1920),
                  errorBuilder: (c, error, stack) =>
                      const Notice('Не удалось показать фотографию')))));
}

class _PrivatePhotoViewer extends StatefulWidget {
  final JobaApi api;
  final List<String> photos;
  final int initialIndex;
  final String? caption;
  const _PrivatePhotoViewer(
      {required this.api,
      required this.photos,
      required this.initialIndex,
      this.caption});
  @override
  State<_PrivatePhotoViewer> createState() => _PrivatePhotoViewerState();
}

class _PrivatePhotoViewerState extends State<_PrivatePhotoViewer> {
  late int index = widget.initialIndex;
  late final int generation = widget.api.sessionGeneration;
  final transform = TransformationController();
  bool enlarged = false;
  @override
  void dispose() {
    transform.dispose();
    super.dispose();
  }

  void select(int next) {
    if (next < 0 || next >= widget.photos.length) return;
    setState(() {
      index = next;
      enlarged = false;
      transform.value = Matrix4.identity();
    });
  }

  void zoom() => setState(() {
        enlarged = !enlarged;
        transform.value = enlarged
            ? (Matrix4.identity()..scaleByDouble(2.0, 2.0, 1.0, 1.0))
            : Matrix4.identity();
      });
  @override
  Widget build(BuildContext context) => Dialog.fullscreen(
      backgroundColor: Colors.white,
      child: SafeArea(
          child: ColoredBox(
              color: navy,
              child: AnimatedBuilder(
                  animation: widget.api,
                  builder: (context, _) {
                    final valid = widget.api.authenticated &&
                        widget.api.sessionGeneration == generation;
                    return ListView(
                        padding: const EdgeInsets.all(20),
                        children: [
                          Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                if (valid)
                                  Text(
                                      '${index + 1} ${localize(context, 'из')} ${widget.photos.length}',
                                      style: const TextStyle(
                                          color: Colors.white, fontSize: 12)),
                                IconButton(
                                    tooltip: localize(context, 'Закрыть'),
                                    onPressed: () => Navigator.pop(context),
                                    icon: const JobaIcon('close',
                                        color: Colors.white))
                              ]),
                          if (!valid)
                            const Notice('Файл недоступен')
                          else ...[
                            const SizedBox(height: 70),
                            SizedBox(
                                height: 330,
                                child: ApiView(
                                    key: ValueKey(
                                        'gallery:$generation:${widget.photos[index]}'),
                                    load: () => widget.api.download(
                                        widget.photos[index]),
                                    builder: (_, bytes, retry) =>
                                        InteractiveViewer(
                                            transformationController: transform,
                                            minScale: 1,
                                            maxScale: 5,
                                            child: Center(
                                                child: Image.memory(
                                                    bytes,
                                                    fit: BoxFit.contain,
                                                    semanticLabel:
                                                        widget.caption))))),
                            const SizedBox(height: 20),
                            Container(
                                constraints:
                                    const BoxConstraints(minHeight: 52),
                                decoration: BoxDecoration(
                                    color: Colors.white,
                                    border: Border.all(color: line),
                                    borderRadius: BorderRadius.circular(14)),
                                child: Row(children: [
                                  IconButton(
                                      tooltip:
                                          localize(context, 'Предыдущее фото'),
                                      onPressed: index > 0
                                          ? () => select(index - 1)
                                          : null,
                                      icon: JobaIcon('back',
                                          color: index > 0
                                              ? navy
                                              : const Color(0xFF627187))),
                                  Expanded(
                                      child: TextButton(
                                          onPressed: zoom,
                                          child: UiText(
                                              enlarged
                                                  ? 'Уменьшить'
                                                  : 'Увеличить',
                                              style: const TextStyle(
                                                  color: navy,
                                                  fontWeight:
                                                      FontWeight.w700)))),
                                  IconButton(
                                      tooltip:
                                          localize(context, 'Следующее фото'),
                                      onPressed:
                                          index + 1 < widget.photos.length
                                              ? () => select(index + 1)
                                              : null,
                                      icon: JobaIcon('right',
                                          color:
                                              index + 1 < widget.photos.length
                                                  ? navy
                                                  : const Color(0xFF627187)))
                                ])),
                            if (widget.caption?.isNotEmpty == true)
                              Padding(
                                  padding: const EdgeInsets.only(top: 20),
                                  child: Text(widget.caption!,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          height: 1.55)))
                          ]
                        ]);
                  }))));
}

class SearchListings extends StatefulWidget {
  final JobaApi api;
  final String path;
  final Json initialFilters;
  final VoidCallback? onCreate;
  final ValueChanged<String>? onStatus;
  final ValueChanged<Json>? onFiltersChanged;
  final Widget Function(Json) tile;
  const SearchListings(
      {required this.api,
      required this.path,
      required this.tile,
      this.initialFilters = const {},
      this.onCreate,
      this.onStatus,
      this.onFiltersChanged,
      super.key});
  @override
  State<SearchListings> createState() => _SearchListingsState();
}

class _SearchListingsState extends State<SearchListings> {
  final search = TextEditingController();
  Json filters = {};
  String query = '';
  String presentation = 'loading';
  Timer? debounce;
  @override
  void initState() {
    super.initState();
    filters = Map<String, dynamic>.from(widget.initialFilters);
    query = '${filters.remove('q') ?? ''}'.trim();
    search.text = query;
  }

  void changed() => widget.onFiltersChanged?.call({...filters, if(query.isNotEmpty) 'q':query});

  Future<void> chooseFilters() async {
    final result = await Navigator.push<Json>(
        context,
        MaterialPageRoute(
            builder: (c) => SearchFilters(
                api: widget.api,
                initial: {...filters, 'q': query},
                onClose: () => Navigator.pop(c),
                onApply: (value) => Navigator.pop(c, value))));
    if (result != null && mounted) {
      setState(() {
        query = '${result.remove('q') ?? query}'.trim();
        search.text = query;
        filters = result;
      });
      changed();
    }
  }

  bool choosing = false;
  Future<void> chooseReference(bool cities) async {
    if (choosing) return;
    setState(() => choosing = true);
    try {
      final data = await widget.api
          .request(cities ? '/geo/cities' : '/catalog/categories');
      if (!mounted) return;
      final row = await pickReference(context, items(data),
          cities: cities,
          initial: '${filters[cities ? 'city' : 'category_id'] ?? ''}',
          optional: true);
      if (!mounted || row == null) return;
      setState(() {
        final key = cities ? 'city' : 'category_id';
        if ('${row['id'] ?? ''}'.isEmpty) {
          filters.remove(key);
        } else {
          filters[key] = cities ? referenceName(row) : row['id'];
        }
        if (cities) {
          filters.remove('near_lat');
          filters.remove('near_lon');
          filters.remove('radius_km');
        }
      });
      changed();
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(errorText(context, error))));
    } finally {
      if (mounted) setState(() => choosing = false);
    }
  }

  Future<void> chooseNearby() async {
    if (choosing) return;
    setState(() => choosing = true);
    try {
      final point = await const MethodChannel('joba.location')
          .invokeMapMethod<String, dynamic>('current');
      if (!mounted) return;
      if (point == null)
        throw ApiException('GPS_DENIED', 'Выберите город вручную');
      setState(() {
        filters.remove('city');
        filters.addAll({
          'near_lat': ((point['latitude'] as num) * 100).round() / 100,
          'near_lon': ((point['longitude'] as num) * 100).round() / 100,
          'radius_km': 50
        });
      });
      changed();
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: UiText(
                'Не удалось определить местоположение. Выберите город.')));
    } finally {
      if (mounted) setState(() => choosing = false);
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
            padding: widget.path == '/contractors' && presentation == 'loading'
                ? const EdgeInsets.fromLTRB(20, 20, 20, 0)
                : const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: Row(children: [
              Expanded(
                  child: TextField(
                      controller: search,
                      style: const TextStyle(
                          fontSize: 14, color: Color(0xFF627187)),
                      decoration: InputDecoration(
                          hintText: localize(context, 'Что ищете?'),
                          fillColor: canvas,
                          prefixIcon: const Padding(
                              padding: EdgeInsets.all(14),
                              child: JobaIcon('search'))),
                      onChanged: (v) {
                        debounce?.cancel();
                        debounce = Timer(const Duration(milliseconds: 300), () {
                          if (mounted) {setState(() => query = v.trim());changed();}
                        });
                      })),
              if (widget.path != '/orders') ...[
                const SizedBox(width: 8),
                IconButton(
                    tooltip: localize(context, 'Фильтры'),
                    onPressed: choosing ? null : chooseFilters,
                    icon: const JobaIcon('filter'))
              ]
            ])),
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Wrap(spacing: 8, runSpacing: 4, children: [
              OutlinedButton.icon(
                  onPressed: choosing ? null : () => chooseReference(true),
                  icon: const Icon(Icons.location_city, size: 18),
                  label:
                      Text('${filters['city'] ?? localize(context, 'Город')}')),
              OutlinedButton.icon(
                  onPressed: choosing ? null : () => chooseReference(false),
                  icon: const Icon(Icons.category_outlined, size: 18),
                  label: UiText(filters.containsKey('category_id')
                      ? 'Категория выбрана'
                      : 'Категория')),
              OutlinedButton.icon(
                  onPressed: choosing ? null : chooseNearby,
                  icon: const Icon(Icons.near_me_outlined, size: 18),
                  label: const UiText('Рядом со мной')),
            ])),
        if (filters.containsKey('near_lat'))
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: UiText(widget.path == '/orders'
                  ? 'В радиусе 50 км. Расположение заказа — по городу.'
                  : 'В радиусе 50 км')),
        if (filters.isNotEmpty)
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(children: [
                Expanded(
                    child: Text(filters['city'] ??
                        localize(context, 'Выбрана категория'))),
                TextButton(
                    onPressed: choosing ? null : () {setState(() => filters = {});changed();},
                    child: const UiText('Сбросить'))
              ])),
        Expanded(
            child: PagedList(
                key: ValueKey('${widget.path}:$query:$filters'),
                api: widget.api,
                path: widget.path,
                query: {...filters, if (query.isNotEmpty) 'q': query},
                header: PromotedListings(
                    key: ValueKey('promoted:${widget.path}:$filters:$query'),
                    api: widget.api,
                    placement: widget.path == '/orders'
                        ? 'search.orders.promoted'
                        : 'search.services.promoted',
                    filters: filters,
                    tile: widget.tile),
                tile: widget.tile,
                onStatus: (status) {
                  if (mounted && presentation != status)
                    setState(() => presentation = status);
                  widget.onStatus?.call(status);
                },
                loadingState: widget.path == '/contractors'
                    ? const JobaSearchSkeleton()
                    : null,
                errorState: (error, retry) =>
                    JobaReadFailure(error: error, onRetry: retry),
                emptyState: widget.path == '/contractors'
                    ? JobaStatePanel(
                        title: 'Пока никого не нашли',
                        message:
                            'Попробуйте выбрать другую категорию. Можно создать заказ, и специалисты откликнутся сами.',
                        icon: 'search',
                        primaryLabel: 'Изменить фильтры',
                        onPrimary: chooseFilters,
                        secondaryLabel:
                            widget.onCreate == null ? null : 'Создать заказ',
                        onSecondary: widget.onCreate)
                    : null,
                empty: 'По вашему запросу ничего не найдено')),
      ]);
}

/// Optional promoted inventory is independent of the organic list and its rank.
class PromotedListings extends StatefulWidget {
  final JobaApi api;
  final String placement;
  final Json filters;
  final Widget Function(Json)? tile;
  final void Function(String type, String id)? onOpen;
  const PromotedListings(
      {required this.api,
      required this.placement,
      this.filters = const {},
      this.tile,
      this.onOpen,
      super.key});
  @override
  State<PromotedListings> createState() => _PromotedListingsState();
}

class _PromotedListingsState extends State<PromotedListings> {
  late final Future<List<Json>> future = load();
  Future<List<Json>> load() async {
    try {
      final data = await widget.api.request('/promoted-listings',
          query: {...widget.filters, 'placement_id': widget.placement});
      return items(data)
          .where((r) => r['promoted'] == true && r['target'] is Map)
          .toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Json>>(
      future: future,
      builder: (context, snapshot) {
        final rows = snapshot.data ?? [];
        if (rows.isEmpty) return const SizedBox.shrink();
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const UiHeading('Продвигается'),
          for (final r in rows)
            Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const JobaBadge('Продвигается'),
                      const SizedBox(height: 6),
                      widget.tile?.call(r['target']) ??
                          DataCard('${r['target']['title']}',
                              subtitle: '${r['target']['city'] ?? ''}',
                              onTap: widget.onOpen == null
                                  ? null
                                  : () => widget.onOpen!(
                                      r['target_type'] == 'order'
                                          ? 'orders'
                                          : 'services',
                                      r['target']['id']))
                    ]))
        ]);
      });
}
