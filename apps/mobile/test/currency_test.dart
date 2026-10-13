import 'package:flutter_test/flutter_test.dart';
import 'package:services_marketplace/core/currency.dart';

void main() {
  test('Prices use local grouping and retain exact minor units', () {
    String compact(String value) => value.replaceAll(RegExp(r'\s+'), ' ');
    expect(compact(formatMoney(1400000, 'KZT', 'ru')), '14 000 ₸');
    expect(formatMoney(125, 'RSD', 'sr'), '1,25 RSD');
    expect(compact(formatMoney(9007199254740991, 'RUB', 'ru')),
        '90 071 992 547 409,91 ₽');
    expect(compact(formatMoney(0, 'BYN', 'be')), '0 Br');
  });
}
