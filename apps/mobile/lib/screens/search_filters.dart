import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/currency.dart';
import '../core/design_icons.dart';
import '../core/design_widgets.dart';
import '../core/l10n.dart';
import '../core/theme.dart';
import '../core/widgets.dart';

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
  final lower = TextEditingController(), upper = TextEditingController();
  late String city, category, mode;
  late bool rated, verified;
  @override
  void initState() {
    super.initState();
    reset();
  }

  void reset() {
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
          title: const UiText('Фильтры'),
          leading: IconButton(
              onPressed: widget.onClose, icon: const JobaIcon('back')),
          actions: [
            TextButton(
                onPressed: () => setState(() {
                      city = '';
                      category = '';
                      mode = '';
                      rated = false;
                      verified = false;
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
                      DropdownButtonFormField<String>(
                          initialValue: city,
                          key: ValueKey('city:$city'),
                          style: const TextStyle(
                              fontFamily: 'Noto',
                              fontSize: 14,
                              color: Color(0xFF627187)),
                          icon: const JobaIcon('down', size: 18),
                          decoration: const InputDecoration(
                              prefixIcon: Padding(
                                  padding: EdgeInsets.all(14),
                                  child: JobaIcon('pin'))),
                          items: [
                            const DropdownMenuItem(
                                value: '', child: UiText('Все города')),
                            if (city.isNotEmpty &&
                                !items(data[0]).any((c) => c['name'] == city))
                              DropdownMenuItem(value: city, child: Text(city)),
                            for (final c in items(data[0]))
                              DropdownMenuItem(
                                  value: '${c['name']}',
                                  child: Text('${c['name']}'))
                          ],
                          onChanged: (value) => setState(() => city = value!)),
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
                                    'RS': 'RSD',
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
                      label('Категория'),
                      DropdownButtonFormField<String>(
                          initialValue:
                              items(data[1]).any((c) => c['id'] == category)
                                  ? category
                                  : '',
                          key: ValueKey('category:$category'),
                          items: [
                            const DropdownMenuItem(
                                value: '', child: UiText('Все категории')),
                            for (final c in items(data[1]))
                              DropdownMenuItem(
                                  value: '${c['id']}',
                                  child: Text('${c['name']}'))
                          ],
                          onChanged: (value) =>
                              setState(() => category = value!))
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
