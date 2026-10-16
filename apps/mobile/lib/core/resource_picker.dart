import 'dart:async';
import 'package:flutter/material.dart';
import 'api.dart';
import 'design_icons.dart';
import 'l10n.dart';
import 'theme.dart';
import 'widgets.dart';

Future<Json?> pickResource(BuildContext context, JobaApi api, String path,
        Json query, String label, {bool optional = false}) =>
    Navigator.push<Json>(
        context,
        MaterialPageRoute(
            builder: (_) => _ResourcePicker(
                api: api,
                path: path,
                query: query,
                label: label,
                optional: optional)));

class _ResourcePicker extends StatefulWidget {
  final JobaApi api;
  final String path, label;
  final Json query;
  final bool optional;
  const _ResourcePicker(
      {required this.api,
      required this.path,
      required this.query,
      required this.label,
      required this.optional});
  @override
  State<_ResourcePicker> createState() => _ResourcePickerState();
}

class _ResourcePickerState extends State<_ResourcePicker> {
  final text = TextEditingController();
  String search = '';
  Timer? debounce;
  @override
  void dispose() {
    debounce?.cancel();
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: canvas,
      appBar: AppBar(
          title: UiText(widget.label),
          leading: IconButton(
              tooltip: localize(context, 'Назад'),
              onPressed: () => Navigator.pop(context),
              icon: const JobaIcon('back'))),
      body: Column(children: [
        Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: TextField(
                controller: text,
                decoration: InputDecoration(
                    hintText: localize(context, 'Поиск'),
                    prefixIcon: const JobaIcon('search')),
                onChanged: (value) {
                  debounce?.cancel();
                  debounce = Timer(const Duration(milliseconds: 300), () {
                    if (mounted) setState(() => search = value.trim());
                  });
                })),
        if (widget.optional)
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextButton(
                  onPressed: () => Navigator.pop(context, <String, dynamic>{
                        'id': '',
                        'title': localize(context, 'Без связи с заказом')
                      }),
                  child: const UiText('Без связи с заказом'))),
        Expanded(
            child: PagedList(
                key: ValueKey('${widget.path}:$search'),
                api: widget.api,
                path: widget.path,
                query: {...widget.query, if (search.isNotEmpty) 'q': search},
                tile: (item) => DataCard(item['title'] ?? '',
                    subtitle: item['city'] ?? '',
                    onTap: () => Navigator.pop(context, item))))
      ]));
}
