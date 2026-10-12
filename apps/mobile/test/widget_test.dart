import 'package:flutter_test/flutter_test.dart';
import 'package:services_marketplace/main.dart';

void main() {
  testWidgets('demo screen is visible', (tester) async {
    await tester.pumpWidget(const MarketplaceDemo());
    expect(find.text('JOBA · DEMO'), findsOneWidget);
  });
}
