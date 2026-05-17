import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campus_mesh/app.dart';

void main() {
  testWidgets('CampusMesh app launches', (WidgetTester tester) async {
    await tester.pumpWidget(const CampusMeshApp());
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
