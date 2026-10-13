import 'package:intl/intl.dart';

const currencySymbols = {'KZT': '₸', 'RUB': '₽', 'BYN': 'Br', 'RSD': 'RSD'};

/// Keep minor units as integers so even large values retain their exact cents.
String formatMoney(int amount, String currency, String locale) {
  final format = NumberFormat.decimalPattern(locale), absolute = amount.abs();
  final whole = format.format(absolute ~/ 100), fraction = absolute % 100;
  return '${amount < 0 ? '-' : ''}$whole${fraction == 0 ? '' : '${format.symbols.DECIMAL_SEP}${fraction.toString().padLeft(2, '0')}'} ${currencySymbols[currency] ?? currency}';
}
