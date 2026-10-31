import 'package:blackgrid/ui/app_logo.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_graphics/vector_graphics.dart';

/// Pumps a row holding [logo] beside the `BLACKGRID` text, as the header does.
Future<void> _pumpRow(WidgetTester tester, AppLogo logo) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: Row(
        children: [logo, const SizedBox(width: 12), const Text('BLACKGRID')],
      ),
    ),
  ),
);

Future<ByteData> _realBytes(WidgetTester tester) async =>
    (await tester.runAsync(() => rootBundle.load(appLogoAsset)))!;

void main() {
  testWidgets('the logo adds no semantics node', (tester) async {
    final handle = tester.ensureSemantics();
    final bytes = await _realBytes(tester);
    await _pumpRow(tester, AppLogo(load: (_) async => bytes));
    await tester.pump();

    expect(tester.getSize(find.byType(AppLogo)), const Size(32, 32));
    final graphic = find.descendant(
      of: find.byType(AppLogo),
      matching: find.byType(VectorGraphic),
    );
    expect(graphic, findsOneWidget);
    expect(tester.widget<VectorGraphic>(graphic).excludeFromSemantics, isTrue);
    expect(
      find.descendant(
        of: find.byType(AppLogo),
        matching: find.byType(Semantics),
      ),
      findsNothing,
    );
    handle.dispose();
  });

  testWidgets(
    'a failed load leaves an empty box of the same size with no error',
    (tester) async {
      final bytes = await _realBytes(tester);
      await _pumpRow(tester, AppLogo(load: (_) async => bytes));
      await tester.pump();
      final expected = tester.getTopLeft(find.text('BLACKGRID'));

      final reported = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = reported.add;
      try {
        await _pumpRow(
          tester,
          AppLogo(
            key: UniqueKey(),
            load: (_) => Future<ByteData>.error(StateError('missing')),
          ),
        );
        await tester.pump();
        await tester.pump();
      } finally {
        FlutterError.onError = previous;
      }

      final box = find.descendant(
        of: find.byType(AppLogo),
        matching: find.byType(SizedBox),
      );
      expect(box, findsOneWidget);
      expect(tester.getSize(box), const Size(32, 32));
      expect(tester.getSize(find.byType(AppLogo)), const Size(32, 32));
      expect(find.byType(VectorGraphic), findsNothing);
      expect(tester.getTopLeft(find.text('BLACKGRID')), expected);
      expect(find.byType(ErrorWidget), findsNothing);
      expect(reported, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
