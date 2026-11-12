import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumalink/main.dart';

void main() {
  testWidgets('LumaLink opens and switches appearance', (tester) async {
    await tester.pumpWidget(const LumaApp());
    expect(find.text(Platform.isWindows ? 'Windows host' : 'Connect to your PC'), findsOneWidget);
    await tester.tap(find.text('Night'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Dark'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
