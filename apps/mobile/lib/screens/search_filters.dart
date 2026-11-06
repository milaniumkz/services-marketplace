import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/currency.dart';
import '../core/design_icons.dart';
import '../core/design_widgets.dart';
import '../core/l10n.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import '../core/reference_picker.dart';

class SearchFilters extends StatefulWidget {
  final JobaApi api;
  final Json initial;
  final VoidCallback onClose;
  final ValueChanged<Json> onApply;
  const SearchFilters(
      {required this.api,
      required this.onClose,
      required this.onApply,
      this.initial = const {},
      super.key});
  @override
  State<SearchFilters> createState() => _SearchFiltersState();
}

class _SearchFiltersState extends State<SearchFilters> {
  final form = GlobalKey<FormState>();
  final lower = TextEditingController(),
      upper = TextEditingController(),
      query = TextEditingController();
  late String city, category, mode;
  late bool rated, verified;
  @override
  void initState() {
    super.initState();
    reset();
  }

  void reset() {
    query.text = '${widget.initial['q'] ?? ''}';
    city = widget.initial['city'] ?? '';
    category = widget.initial['category_id'] ?? '';
    mode = widget.initial['work_mode'] ?? '';
    rated = widget.initial['rating_min'] != null;
    verified = widget.initial['verified_only'] == 'true';
    String priceInput(dynamic value) {
      final minor = int.tryParse('$value');
      if (minor == null || minor < 0) return '';
      return '${(minor ~/ 100).toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ' ')}${minor % 100 == 0 ? '' : '.${(minor % 100).toString().padLeft(2, '0')}'}';
    }

    lower.text = priceInput(widget.initial['price_min']);
    upper.text = priceInput(widget.initial['price_max']);
  }

  @override
  void dispose() {
    query.dispose();
    lower.dispose();
    upper.dispose();
    super.dispose();
  }

  int? amount(String value) {
    final text = value.replaceAll(RegExp(r'\s'), '').replaceAll(',', '.');
    if (text.isEmpty) return null;
    if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(text)) return -1;
    final parts = text.split('.');
    final whole = int.tryParse(parts.first);
    if (whole == null || whole > 90071992547409) return -1;
    final result = whole * 100 +
        (parts.length == 1 ? 0 : int.parse(parts[1].padRight(2, '0')));
    return result <= 9007199254740991 ? result : -1;
  }

  String? validate(String? text) => amount(text ?? '') == -1
      ? localize(context, 'Проверьте диапазон цены')
      : null;
  void apply() {
    if (!form.currentState!.validate()) return;
    final min = amount(lower.text), max = amount(upper.text);
    if (min == -1 || max == -1 || min != null && max != null && min > max) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: UiText('Проверьте диапазон цены')));
      return;
    }
    widget.onApply({
      if (widget.initial.containsKey('q')) 'q': query.text.trim(),
      if (city.isNotEmpty) 'city': city,
      if (category.isNotEmpty) 'category_id': category,
      if (mode.isNotEmpty) 'work_mode': mode,
      if (min != null) 'price_min': min,
      if (max != null) 'price_max': max,
      if (rated) 'rating_min': '4.8',
      if (verified) 'verified_only': 'true',
    });
  }

  Widget label(String text) => Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: UiText(text,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)));
  Widget choice(String value, String title, String subtitle) => Padding(
      padding: EdgeInsets.only(bottom: value == 'remote' ? 0 : 10),
      child: Material(
          color: mode == value ? const Color(0xFFF0F4FF) : Colors.white,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: mode == value ? primary : line)),
          child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => setState(() => mode = mode == value ? '' : value),
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(children: [
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          UiText(title,
                              style: const TextStyle(
                                  fontSize: 14,
                                  height: 1.45,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 6),
                          UiText(subtitle,
                              style: const TextStyle(
                                  fontSize: 12, height: 1.45, color: muted))
                        ])),
                    const SizedBox(width: 12),
                    Icon(
                        mode == value
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        color:
                            mode == value ? primary : const Color(0xFFBBC8DE),
                        size: 22)
                  ])))));
  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: canvas,
      appBar: AppBar(
          leadingWidth: 72,
          title: const UiText('Фильтры'),
          leading: IconButton(
              tooltip: localize(context, 'Назад'),
              onPressed: widget.onClose,
              icon: const JobaIcon('back')),
          actions: [
            TextButton(
                onPressed: () => setState(() {
                      form.currentState?.reset();
                      ScaffoldMessenger.of(context).hideCurrentSnackBar();
                      city = '';
                      category = '';
                      mode = '';
                      rated = false;
                      verified = false;
                      query.clear();
                      lower.clear();
                      upper.clear();
                    }),
                child: const UiText('Сбросить'))
          ]),
      body: ApiView(
          load: () => Future.wait([
                widget.api.request('/geo/cities'),
                widget.api.request('/catalog/categories')
              ]),
          builder: (context, data, retry) => Form(
              key: form,
              child: Column(children: [
                Expanded(
                    child: ListView(
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                        children: [
                      label('Город'),
                      OutlinedButton.icon(
                          icon: const JobaIcon('pin'),
                          label: Text(city.isEmpty
                              ? localize(context, 'Все города')
                              : city),
                          onPressed: () async {
                            final row = await pickReference(
                                context, items(data[0]),
                                cities: true, initial: city, optional: true);
                            if (mounted && row != null)
                              setState(() => city = referenceName(row));
                          }),
                      label('Расстояние'),
                      Wrap(spacing: 8, children: [
                        for (final title in ['5 км', '10 км'])
                          OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(0, 48),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14),
                                  textStyle: const TextStyle(
                                      fontFamily: 'Noto',
                                      fontSize: 12,
                                      fontWeight: FontWeight.w400),
                                  shape: const StadiumBorder()),
                              onPressed: () => ScaffoldMessenger.of(context)
                                  .showSnackBar(SnackBar(
                                      content: UiText(
                                          'Для поиска по расстоянию нужны координаты. Выберите город.'))),
                              child: UiText(title)),
                        FilledButton(
                            style: FilledButton.styleFrom(
                                minimumSize: const Size(0, 48),
                                backgroundColor: navy,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 14),
                                shape: const StadiumBorder(),
                                textStyle: const TextStyle(
                                    fontFamily: 'Noto',
                                    fontSize: 12,
                                    fontWeight: FontWeight.w400)),
                            onPressed: () => ScaffoldMessenger.of(context)
                                .showSnackBar(SnackBar(
                                    content: UiText(
                                        'Поиск по всему выбранному городу'))),
                            child: const UiText('Весь город'))
                      ]),
                      label('Формат услуги'),
                      choice('onsite', 'С выездом ко мне',
                          'Специалист приедет по адресу'),
                      choice('workshop', 'У исполнителя',
                          'В мастерской или студии'),
                      choice('remote', 'Дистанционно',
                          'Город не ограничивает поиск'),
                      Padding(
                          padding: const EdgeInsets.only(top: 18, bottom: 8),
                          child: Text(
                              '${localize(context, 'Стоимость')}, ${currencySymbols[const {
                                    'KG': 'KGS',
                                    'RU': 'RUB',
                                    'BY': 'BYN'
                                  }[widget.api.session?['user']?['country']] ?? 'KZT']}',
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w700))),
                      Row(children: [
                        Expanded(
                            child: TextFormField(
                                key: const ValueKey('search-price-min'),
                                style: const TextStyle(fontSize: 14),
                                controller: lower,
                                validator: validate,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                decoration: InputDecoration(
                                    hintText: localize(context, 'От')))),
                        const SizedBox(width: 12),
                        Expanded(
                            child: TextFormField(
                                key: const ValueKey('search-price-max'),
                                style: const TextStyle(fontSize: 14),
                                controller: upper,
                                validator: validate,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                decoration: InputDecoration(
                                    hintText: localize(context, 'До'))))
                      ]),
                      label('Рейтинг'),
                      Wrap(spacing: 8, children: [
                        ChoiceChip(
                            label: const UiText('Любой'),
                            selected: !rated,
                            onSelected: (_) => setState(() => rated = false)),
                        ChoiceChip(
                            label: const UiText('4,8 и выше'),
                            selected: rated,
                            onSelected: (_) => setState(() => rated = true))
                      ]),
                      const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: UiText(
                              'Рейтинг учитывается вместе с количеством отзывов.',
                              style: TextStyle(fontSize: 10, color: muted))),
                      CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title:
                              const UiText('Только с проверенным документом'),
                          value: verified,
                          onChanged: (value) =>
                              setState(() => verified = value!)),
                      if (widget.initial.containsKey('q')) ...[
                        label('Что ищете?'),
                        TextFormField(
                            key: const ValueKey('search-filter-query'),
                            controller: query,
                            decoration: InputDecoration(
                                hintText: localize(context, 'Что ищете?')))
                      ],
                      label('Категория'),
                      OutlinedButton.icon(
                          icon: const JobaIcon('down'),
                          label: Text(items(data[1])
                                  .where((r) => r['id'] == category)
                                  .map(referenceName)
                                  .firstOrNull ??
                              localize(context, 'Все категории')),
                          onPressed: () async {
                            final row = await pickReference(
                                context, items(data[1]),
                                cities: false,
                                initial: category,
                                optional: true);
                            if (mounted && row != null)
                              setState(() => category = '${row['id']}');
                          })
                    ])),
                Container(
                    decoration: const BoxDecoration(
                        color: Colors.white,
                        border: Border(top: BorderSide(color: line))),
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                    child: SafeArea(
                        top: false,
                        child: SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                                onPressed: apply,
                                child: const UiText('Показать специалистов')))))
              ]))));
}
