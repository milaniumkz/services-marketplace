import 'package:flutter/material.dart';
import 'api.dart';
import 'theme.dart';
import 'l10n.dart';

String referenceName(Json row) => '${row['name'] ?? row['title'] ?? ''}';
String _fold(String value) => value.toLowerCase().replaceAll('ё', 'е');

Future<Json?> pickReference(BuildContext context, List<Json> rows,
        {required bool cities, String initial = '', bool optional = false}) =>
    Navigator.push<Json>(
        context,
        MaterialPageRoute(
            builder: (context) => Scaffold(
                backgroundColor: canvas,
                appBar: AppBar(title: UiText(cities ? 'Город' : 'Категория')),
                body: ReferenceSelector(
                    rows: rows,
                    cities: cities,
                    initial: initial,
                    optional: optional,
                    onSave: (row) async => Navigator.pop(context, row)))));

/// All hierarchy and labels come from API records, never a bundled directory.
class ReferenceSelector extends StatefulWidget {
  final List<Json> rows;
  final bool cities, optional;
  final String initial, countryLabel;
  final Future<void> Function(Json) onSave;
  const ReferenceSelector(
      {required this.rows,
      required this.cities,
      required this.onSave,
      this.initial = '',
      this.countryLabel = '',
      this.optional = false,
      super.key});
  @override
  State<ReferenceSelector> createState() => _ReferenceSelectorState();
}

class _ReferenceSelectorState extends State<ReferenceSelector> {
  final search = TextEditingController();
  String? parent;
  Json? selected;
  bool busy = false;
  Object? error;
  Map<String, Json> byId = {};
  String region(Json row) => '${row['region'] ?? ''}'.trim();
  String parentOf(Json row) => '${row['parent_id'] ?? ''}';
  @override
  void initState() {
    super.initState();
    for (final row in widget.rows) {
      if (row['id'] == widget.initial || referenceName(row) == widget.initial) {
        selected = row;
      }
    }
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  String path(Json row) {
    if (widget.cities) return region(row);
    final parts = <String>[];
    final seen = <String>{'${row['id']}'};
    final index = byId;
    var next = parentOf(row);
    while (next.isNotEmpty && seen.add(next) && index.containsKey(next)) {
      final ancestor = index[next]!;
      parts.insert(0, referenceName(ancestor));
      next = parentOf(ancestor);
    }
    return parts.join(' → ');
  }

  Future<void> save() async {
    if (selected == null || busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.onSave(selected!);
    } catch (failure) {
      if (mounted) setState(() => error = failure);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    byId = {for (final row in widget.rows) '${row['id']}': row};
    final parents = widget.rows.map(parentOf).toSet();
    final needle = _fold(search.text.trim());
    final index = byId;
    final groups = <String, int>{};
    final regionRanks = <String, int>{};
    final regionKinds = <String, String>{};
    if (widget.cities) {
      for (final row in widget.rows) {
        final name = region(row), rawRank = row['region_sort_order'];
        final rank = rawRank is num
            ? rawRank.toInt()
            : name.isEmpty
                ? 20000
                : 10000;
        groups.update(name, (n) => n + 1, ifAbsent: () => 1);
        regionRanks.update(name, (old) => rank < old ? rank : old,
            ifAbsent: () => rank);
        if (row['region_kind'] is String)
          regionKinds[name] = row['region_kind'];
      }
    }
    final regions = groups.keys.toList()
      ..sort((a, b) {
        final order = regionRanks[a]!.compareTo(regionRanks[b]!);
        return order != 0 ? order : a.compareTo(b);
      });
    final showingRegions = widget.cities && parent == null && needle.isEmpty;
    final visible = widget.rows.where((row) {
      if (needle.isNotEmpty) {
        return [
          referenceName(row),
          path(row),
          ...(row['aliases'] as List? ?? [])
        ].any((value) => _fold('$value').contains(needle));
      }
      if (widget.cities) return parent != null && region(row) == parent;
      final p = parentOf(row);
      return parent == null ? p.isEmpty || !index.containsKey(p) : p == parent;
    }).toList();
    final title = widget.cities
        ? (showingRegions ? 'Выберите область или регион' : 'Выберите город')
        : (parent == null
            ? 'Основные категории'
            : referenceName(index[parent] ?? {}));
    return Column(children: [
      Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            UiHeading(title),
            if (widget.countryLabel.isNotEmpty) UiText(widget.countryLabel),
            TextField(
                controller: search,
                enabled: !busy,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                    labelText: localize(context,
                        widget.cities ? 'Найти город' : 'Найти категорию'),
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: search.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: localize(context, 'Очистить'),
                            onPressed: () => setState(search.clear),
                            icon: const Icon(Icons.close)))),
            if (parent != null)
              TextButton.icon(
                  onPressed: busy
                      ? null
                      : () => setState(() {
                            parent = widget.cities
                                ? null
                                : (parentOf(index[parent] ?? {}).isEmpty
                                    ? null
                                    : parentOf(index[parent] ?? {}));
                            search.clear();
                          }),
                  icon: const Icon(Icons.arrow_back, size: 18),
                  label: UiText(widget.cities
                      ? 'Все области и регионы'
                      : 'Назад к категориям')),
            if (needle.isNotEmpty)
              const UiText('Поиск по всему справочнику',
                  style: TextStyle(fontSize: 11, color: Color(0xFF627187))),
            if (widget.optional)
              TextButton(
                  onPressed: busy
                      ? null
                      : () async {
                          setState(() => selected = <String, dynamic>{
                                'id': '',
                                'name': ''
                              });
                          await save();
                        },
                  child:
                      UiText(widget.cities ? 'Все города' : 'Все категории')),
          ])),
      Expanded(
          child: ListView.builder(
              key: ValueKey('${widget.cities}:$parent:$needle'),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: showingRegions
                  ? regions.length
                  : visible.length + (visible.isEmpty ? 1 : 0),
              itemBuilder: (context, i) {
                if (showingRegions) {
                  final name = regions[i];
                  return ListTile(
                      title: Text(name.isEmpty
                          ? localize(context, 'Без указанного региона')
                          : name),
                      subtitle: Text(regionKinds[name] == 'republican_city'
                          ? localize(context, 'Город республиканского значения')
                          : '${groups[name]}'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: busy
                          ? null
                          : () => setState(() {
                                parent = name;
                                selected = null;
                              }));
                }
                if (visible.isEmpty)
                  return const Padding(
                      padding: EdgeInsets.all(20),
                      child: UiText(
                          'Ничего не найдено. Попробуйте другое название.'));
                final row = visible[i];
                final hasChildren =
                    !widget.cities && parents.contains(row['id']);
                return ListTile(
                    selected: selected?['id'] == row['id'],
                    selectedTileColor: const Color(0xFFF0F4FF),
                    title: Text(referenceName(row),
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700)),
                    subtitle: path(row).isEmpty
                        ? null
                        : Text(path(row), style: const TextStyle(fontSize: 11)),
                    trailing: Icon(hasChildren
                        ? Icons.chevron_right
                        : (selected?['id'] == row['id']
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off)),
                    onTap: busy
                        ? null
                        : () => setState(() {
                              selected = row;
                              if (hasChildren) {
                                parent = '${row['id']}';
                                search.clear();
                              }
                            }));
              })),
      if (error != null)
        Padding(
            padding: const EdgeInsets.all(12),
            child: Notice(errorText(context, error!), error: true)),
      if (widget.cities && widget.rows.any((r) => r['geonames_id'] != null))
        const Padding(
            padding: EdgeInsets.only(top: 8),
            child: UiText('Географические данные: GeoNames · CC BY 4.0',
                style: TextStyle(fontSize: 10))),
      Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: SafeArea(
              top: false,
              child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                      onPressed: busy || selected == null ? null : save,
                      child: Text(busy
                          ? localize(context, 'Сохранение…')
                          : selected == null
                              ? localize(
                                  context,
                                  widget.cities
                                      ? 'Выбрать город'
                                      : 'Выбрать категорию')
                              : '${localize(context, 'Выбрать')} ${referenceName(selected!)}'))))),
    ]);
  }
}
