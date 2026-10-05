import 'package:blackgrid/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Keeps content visible in a compact window with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 240);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(const MainApp());

    final content = tester.getRect(find.text('blackgrid'));
    expect(content.left, greaterThanOrEqualTo(0));
    expect(content.top, greaterThanOrEqualTo(0));
    expect(content.right, lessThanOrEqualTo(320));
    expect(content.bottom, lessThanOrEqualTo(240));
  });
}
