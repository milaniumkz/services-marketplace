import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/design_icons.dart';
import '../core/l10n.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import '../core/reference_picker.dart';

class TopListings extends StatefulWidget {
  final JobaApi api;
  final String initialCity;
  final void Function(String type, String id) onOpen;
  const TopListings(
      {required this.api,
      required this.onOpen,
      this.initialCity = '',
      super.key});
  @override
  State<TopListings> createState() => _TopListingsState();
}

class _TopListingsState extends State<TopListings> {
  String type = 'services',
      city = '',
      category = '',
      categoryLabel = '',
      sort = 'popular';
  final Set<String> busy = {};
  Object? voteError;
  late Future<dynamic> future;
  Future<dynamic> fetch() {
    final pending = widget.api.request('/top-listings', query: {
      'target_type': type,
      'sort': sort,
      if (city.isNotEmpty) 'city': city,
      if (category.isNotEmpty) 'category_id': category
    });
    // The lazy list may mount FutureBuilder after a fast failed response.
    // Observe errors immediately; FutureBuilder still receives the original error.
    pending.ignore();
    return pending;
  }

  void reload() {
    setState(() => future = fetch());
  }

  @override
  void initState() {
    super.initState();
    city = widget.initialCity;
    future = fetch();
  }

  Future<void> choose(String path, bool cities) async {
    final selected = await Navigator.push<Json>(context, MaterialPageRoute(
        builder: (context) => Scaffold(
            backgroundColor: canvas,
            appBar: AppBar(title: UiText(cities ? 'Город' : 'Категория')),
            body: ApiView(
                load: () => widget.api.request(path),
                builder: (context, data, reload) => ReferenceSelector(
                    rows: items(data), cities: cities, optional: true,
                    initial: cities ? city : category,
                    onSave: (row) async => Navigator.pop(context, row))))));
    if (!mounted || selected == null) return;
    setState(() {
      if (cities) {
        city = '${selected['name'] ?? ''}';
      } else {
        category = '${selected['id'] ?? ''}';
        categoryLabel = '${selected['name'] ?? selected['title'] ?? ''}';
      }
      future = fetch();
    });
  }

  Future<void> vote(Json row, int value, VoidCallback reload) async {
    final id = '${row['id']}';
    if (busy.contains(id)) return;
    setState(() {
      busy.add(id);
      voteError = null;
    });
    try {
      await widget.api.request('/listing-votes/$type/$id',
          method: row['my_vote'] == value ? 'DELETE' : 'PUT',
          body: {'value': value});
      if (mounted) reload();
    } catch (e) {
      if (mounted) setState(() => voteError = e);
    } finally {
      if (mounted) setState(() => busy.remove(id));
    }
  }

  Widget chip(String label, VoidCallback onTap, {bool active = false}) =>
      OutlinedButton(
          style: OutlinedButton.styleFrom(
              minimumSize: Size.zero,
              textStyle: const TextStyle(
                  fontFamily: 'Noto',
                  fontSize: 13,
                  fontWeight: FontWeight.w400),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              backgroundColor: active ? const Color(0xFFEAF0FC) : Colors.white,
              foregroundColor: active ? primary : navy,
              side: BorderSide(color: active ? const Color(0xFFD8E3FF) : line),
              shape: const StadiumBorder()),
          onPressed: onTap,
          child: UiText(label));

  Widget card(Json row, int position, VoidCallback reload) {
    final name = '${row['display_name'] ?? ''}'.trim();
    final title =
        type == 'services' && name.isNotEmpty ? name : '${row['title'] ?? ''}';
    final initials = title
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .take(2)
        .map((s) => s.characters.first)
        .join();
    final rating = row['rating'] is Map ? row['rating'] as Map : null;
    return Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: line),
            borderRadius: BorderRadius.circular(22)),
        child: Column(children: [
          InkWell(
              onTap: () => widget.onOpen(type, '${row['id']}'),
              child: Row(children: [
                Text('$position',
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: primary)),
                const SizedBox(width: 16),
                Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        color: const Color(0xFFDCE8F5),
                        borderRadius: BorderRadius.circular(16)),
                    child: Text(initials,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF3D6075)))),
                const SizedBox(width: 10),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                      Text(
                          type == 'services'
                              ? '${row['title'] ?? ''}'
                              : '${row['city'] ?? ''}',
                          maxLines: 2,
                          style: const TextStyle(
                              fontSize: 11, color: Color(0xFF627187)))
                    ])),
                if (rating?['average'] != null) ...[
                  const Icon(Icons.star, color: yellow, size: 15),
                  const SizedBox(width: 4),
                  Text(
                      '${(rating!['average'] as num).toStringAsFixed(1)} (${rating['count']})',
                      style: const TextStyle(fontSize: 12))
                ]
              ])),
          const SizedBox(height: 16),
          Row(children: [
            for (final value in [1, -1])
              Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                          minimumSize: const Size(86, 48),
                          textStyle: const TextStyle(
                              fontFamily: 'Noto',
                              fontSize: 13,
                              fontWeight: FontWeight.w400),
                          backgroundColor: row['my_vote'] == value
                              ? const Color(0xFFEAF0FC)
                              : Colors.white,
                          shape: const StadiumBorder(),
                          side: const BorderSide(color: line)),
                      onPressed: busy.contains('${row['id']}')
                          ? null
                          : () => vote(row, value, reload),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        RotatedBox(
                            quarterTurns: value == 1 ? 0 : 2,
                            child: const JobaIcon('thumb', size: 16)),
                        const SizedBox(width: 6),
                        Text('${row[value == 1 ? 'likes' : 'dislikes'] ?? 0}')
                      ]))),
            const Expanded(
                child: UiText('Реакции к карточке',
                    style: TextStyle(fontSize: 10, color: Color(0xFF627187))))
          ])
        ]));
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
      onRefresh: () async {
        reload();
        await future;
      },
      child: ListView(padding: const EdgeInsets.all(20), children: [
        PromotedListings(
            key: ValueKey('top-promoted:$type:$city:$category'),
            api: widget.api,
            placement: type == 'orders'
                ? 'top.orders.promoted'
                : 'top.services.promoted',
            filters: {
              'city': city,
              if (category.isNotEmpty) 'category_id': category
            },
            onOpen: widget.onOpen),
        const Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
                width: 280,
                child: UiText('Кого выбирают чаще',
                    style: TextStyle(
                        fontSize: 28,
                        height: 1.25,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -.9)))),
        const SizedBox(height: 10),
        const UiText('Популярность по реакциям сообщества',
            style: TextStyle(fontSize: 13, color: Color(0xFF627187))),
        const SizedBox(height: 16),
        Container(
            color: Colors.white,
            child: Row(children: [
              for (final entry
                  in const {'services': 'Услуги', 'orders': 'Заказы'}.entries)
                InkWell(
                    onTap: () => setState(() {
                          type = entry.key;
                          voteError = null;
                          future = fetch();
                        }),
                    child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        margin: const EdgeInsets.only(right: 22),
                        decoration: BoxDecoration(
                            border: Border(
                                bottom: BorderSide(
                                    width: 2,
                                    color: type == entry.key
                                        ? primary
                                        : Colors.transparent))),
                        child: UiText(entry.value,
                            style: TextStyle(
                                fontSize: 13,
                                color: type == entry.key
                                    ? primary
                                    : const Color(0xFF627187),
                                fontWeight: type == entry.key
                                    ? FontWeight.w700
                                    : FontWeight.w400))))
            ])),
        const SizedBox(height: 16),
        Wrap(spacing: 8, runSpacing: 8, children: [
          chip(city.isEmpty ? 'Все города' : city,
              () => choose('/geo/cities', true)),
          chip(categoryLabel.isEmpty ? 'Все категории' : categoryLabel,
              () => choose('/catalog/categories', false)),
          chip(
              sort == 'popular' ? 'Популярные' : 'Новые',
              () => setState(() {
                    sort = sort == 'popular' ? 'new' : 'popular';
                    future = fetch();
                  }),
              active: true)
        ]),
        const SizedBox(height: 20),
        if (voteError != null) Notice(errorText(context, voteError!)),
        FutureBuilder<dynamic>(
            future: future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done)
                return const Center(child: CircularProgressIndicator());
              if (snapshot.hasError)
                return Column(children: [
                  Notice(errorText(context, snapshot.error!), error: true),
                  FilledButton(
                      onPressed: reload, child: const UiText('Повторить'))
                ]);
              final rows = items(snapshot.data);
              final calculated = DateTime.tryParse(
                      '${snapshot.data['meta']?['calculated_at'] ?? ''}')
                  ?.toLocal();
              return Column(children: [
                Row(children: [
                  const Expanded(
                      child: UiText('Органический топ',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w700))),
                  if (calculated != null)
                    Text(
                        '${localize(context, 'Обновлён')} ${calculated.hour.toString().padLeft(2, '0')}:${calculated.minute.toString().padLeft(2, '0')}',
                        style: const TextStyle(
                            fontSize: 10, color: Color(0xFF627187)))
                ]),
                const SizedBox(height: 16),
                if (rows.isEmpty)
                  const Notice('По выбранным условиям пока нет объявлений.'),
                for (final entry in rows.indexed)
                  card(entry.$2, entry.$1 + 1, reload)
              ]);
            }),
        const UiText(
            'Реакции не являются отзывами и не меняют звёздный рейтинг.',
            style: TextStyle(fontSize: 11, color: Color(0xFF627187)))
      ]));
}
