import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:services_marketplace/screens/profile_views.dart';

void main() {
  testWidgets('profile view count stays readable on narrow screens',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: Center(
      child: SizedBox(width: 200, child: ProfileViews(count: 12)),
    ))));
    expect(find.text('Просмотры анкеты: 12'), findsOneWidget);
    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
