import 'dart:async';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import '../core/api.dart';
import '../core/osm_map.dart';
import '../core/l10n.dart';
import '../core/theme.dart';

Future<Json?> chooseMapAddress(BuildContext context, JobaApi api,
        {Json? initial, String? city}) =>
    Navigator.of(context).push<Json>(MaterialPageRoute(
        builder: (_) =>
            OsmLocationPicker(api: api, initial: initial, cityName: city)));

class OsmLocationPicker extends StatefulWidget {
  final JobaApi api;
  final Json? initial;
  final String? cityName;
  final Future<Json?> Function()? locate;
  final TileProvider? tileProvider;
  const OsmLocationPicker(
      {super.key,
      required this.api,
      this.initial,
      this.cityName,
      this.locate,
      this.tileProvider});
  @override
  State<OsmLocationPicker> createState() => _OsmLocationPickerState();
}

class _OsmLocationPickerState extends State<OsmLocationPicker> {
  final search = TextEditingController(), address = TextEditingController();
  LatLng? selected, center;
  Json? city;
  List<Json> results = [];
  bool searching = false, resolving = false, touched = false;
  Object? error;
  int generation = 0, addressEdits = 0;
  Timer? debounce;
  @override
  void initState() {
    super.initState();
    selected = mapPoint(widget.initial);
    center = selected;
    address.text = widget.initial?['address'] ?? '';
    city = widget.initial?['city'];
    loadCenter();
  }

  Future<void> loadCenter() async {
    try {
      final data = items(await widget.api.request('/geo/cities'));
      final found = data
          .where((c) => c['name'] == widget.cityName && mapPoint(c) != null);
      final fallback = data.where((c) => mapPoint(c) != null);
      final point = found.isNotEmpty
          ? mapPoint(found.first)
          : fallback.isNotEmpty
              ? mapPoint(fallback.first)
              : null;
      if (mounted && center == null) setState(() => center = point);
    } catch (_) {}
  }

  void select(LatLng point, {bool device = false}) {
    if (device && touched) return;
    if (!device) touched = true;
    debounce?.cancel();
    final version = ++generation, edits = addressEdits;
    setState(() {
      selected = point;
      city = null;
      address.text = '';
      error = null;
      resolving = true;
      results = [];
    });
    debounce = Timer(const Duration(milliseconds: 600), () async {
      try {
        final data = items(
            await widget.api.request('/geo/reverse', query: pointJson(point)));
        if (!mounted || version != generation) return;
        if (data.isNotEmpty) {
          setState(() {
            city = data.first['city'];
            if (edits == addressEdits)
              address.text = data.first['address'] ?? '';
          });
        }
      } catch (e) {
        if (mounted && version == generation) {
          setState(() => error = e);
          try {
            final r = await widget.api
                .request('/geo/nearest-city', query: pointJson(point));
            if (mounted && version == generation)
              setState(() => city = r['city']);
          } catch (_) {}
        }
      } finally {
        if (mounted && version == generation) setState(() => resolving = false);
      }
    });
  }

  Future<void> find() async {
    if (searching || search.text.trim().length < 3) return;
    FocusScope.of(context).unfocus();
    final version = ++generation;
    debounce?.cancel();
    touched = true;
    setState(() {
      searching = true;
      resolving = false;
      error = null;
    });
    try {
      final data = items(await widget.api
          .request('/geo/search', query: {'q': search.text.trim()}));
      if (!mounted || version != generation) return;
      setState(() {
        results = data;
        if (data.isEmpty)
          error = ApiException('NOT_FOUND',
              'Адрес не найден. Уточните запрос или выберите точку на карте.');
      });
    } catch (e) {
      if (mounted && version == generation) setState(() => error = e);
    } finally {
      if (mounted) setState(() => searching = false);
    }
  }

  @override
  void dispose() {
    generation++;
    debounce?.cancel();
    search.dispose();
    address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const UiText('Адрес на карте')),
      body: SafeArea(
          child: Column(children: [
        Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(
                  child: TextField(
                      controller: search,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => find(),
                      decoration: InputDecoration(
                          labelText: localize(context, 'Поиск адреса'),
                          hintText: localize(context, 'Город, улица, дом')))),
              const SizedBox(width: 8),
              IconButton(
                  tooltip: localize(context, 'Найти адрес'),
                  onPressed: searching ? null : find,
                  icon: searching
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.search))
            ])),
        if (results.isNotEmpty)
          ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 160),
              child: ListView(
                  shrinkWrap: true,
                  children: results
                      .map((r) => ListTile(
                          title: Text(r['address'],
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                          onTap: () {
                            generation++;
                            debounce?.cancel();
                            touched = true;
                            setState(() {
                              selected = mapPoint(r);
                              city = r['city'];
                              address.text = r['address'];
                              results = [];
                              resolving = false;
                              error = null;
                            });
                          }))
                      .toList())),
        Expanded(
            child: OsmMap(
                initialCenter: center,
                selected: selected,
                locate: widget.locate,
                tileProvider: widget.tileProvider,
                onSelected: select,
                onLocated: (point) {
                  if (selected == null && !touched) select(point, device: true);
                })),
        if (resolving) const LinearProgressIndicator(),
        if (error != null)
          ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 84),
              child: SingleChildScrollView(
                  child: Notice(errorText(context, error!)))),
        Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
                controller: address,
                onChanged: (_) => addressEdits++,
                maxLength: 500,
                maxLines: 1,
                decoration: InputDecoration(
                    labelText: localize(context, 'Адрес'),
                    hintText:
                        localize(context, 'Уточните улицу, дом, квартиру'),
                    counterText: ''))),
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: UiText(
                city == null
                    ? 'Выберите точку на карте. Город можно указать отдельно.'
                    : 'Город: ${city!['name']}',
                style: const TextStyle(fontSize: 11))),
        Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                    onPressed: selected == null || resolving || searching
                        ? null
                        : () => Navigator.pop(context, {
                              ...pointJson(selected!),
                              'address': address.text.trim(),
                              if (city != null) 'city': city
                            }),
                    child: const UiText('Использовать этот адрес'))))
      ])));
}
