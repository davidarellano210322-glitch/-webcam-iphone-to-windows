import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/main.dart';

void main() {
  testWidgets('Smoke test NeoCamo app', (WidgetTester tester) async {
    await tester.pumpWidget(const NeoCamoApp());
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
