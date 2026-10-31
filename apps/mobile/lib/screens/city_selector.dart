import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/reference_picker.dart';

class CitySelector extends StatelessWidget {
  final List<Json> cities;
  final String initial, countryLabel;
  final Future<void> Function(Json) onSave;
  const CitySelector(
      {required this.cities,
      required this.initial,
      this.countryLabel = '',
      required this.onSave,
      super.key});
  @override
  Widget build(BuildContext context) => ReferenceSelector(
      rows: cities,
      cities: true,
      initial: initial,
      countryLabel: countryLabel,
      onSave: onSave);
}
