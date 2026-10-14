import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/theme.dart';
import '../core/l10n.dart';
import '../core/design_icons.dart';

class CitySelector extends StatefulWidget {
  final List<Json> cities;
  final String initial;
  final Future<void> Function(Json) onSave;
  const CitySelector(
      {required this.cities,
      required this.initial,
      required this.onSave,
      super.key});
  @override
  State<CitySelector> createState() => _CitySelectorState();
}

class _CitySelectorState extends State<CitySelector> {
  String query = '';
  Json? selected;
  bool busy = false;
  Object? error;
  @override
  void initState() {
    super.initState();
    for (final city in widget.cities) {
      if (city['name'] == widget.initial) selected = city;
    }
  }

  Future<void> save() async {
    if (selected == null || busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.onSave(selected!);
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        Expanded(
            child: ListView(padding: const EdgeInsets.all(20), children: [
          const UiHeading('Ваш город', 'Точный адрес для поиска не нужен.'),
          TextField(
              onChanged: (value) => setState(() => query = value),
              decoration: InputDecoration(
                  labelText: localize(context, 'Найти город'),
                  prefixIcon: const Padding(
                      padding: EdgeInsets.all(12), child: JobaIcon('search')))),
          const SizedBox(height: 20),
          for (final city in widget.cities.where((city) => '${city['name']}'
              .toLowerCase()
              .contains(query.trim().toLowerCase())))
            Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Material(
                    color: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(
                            color: selected?['id'] == city['id']
                                ? primary
                                : line)),
                    child: InkWell(
                        onTap:
                            busy ? null : () => setState(() => selected = city),
                        borderRadius: BorderRadius.circular(14),
                        child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(children: [
                              const JobaIcon('pin'),
                              const SizedBox(width: 12),
                              Expanded(child: Text('${city['name']}')),
                              if (selected?['id'] == city['id'])
                                const JobaIcon('check', color: primary)
                            ]))))),
          const Notice(
              'Вы можете выбрать город вручную и пользоваться поиском без геолокации.'),
          if (error != null) Notice('$error')
        ])),
        Container(
            color: Colors.white,
            padding: const EdgeInsets.all(20),
            child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                    onPressed: busy || selected == null ? null : save,
                    child: Text(selected == null
                        ? localize(context, 'Выбрать город')
                        : '${localize(context, 'Выбрать')} ${selected!['name']}'))))
      ]);
}
