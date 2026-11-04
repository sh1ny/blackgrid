import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:blackgrid/domain/map_coordinates.dart';
import 'package:blackgrid/maps/marker_presentation.dart';
import 'package:blackgrid/maps/prepared_map.dart';
import 'package:blackgrid/ui/marker_popup.dart';

void main() {
  testWidgets(
    'long quest instruction remains readable in the collapsed popup summary',
    (tester) async {
      const instruction =
          'Travel to the north ridge, search the marked area, inspect the old '
          'stone shelter, and retrieve the sealed objective package. '
          'Continue along the eastern path and confirm the final marker '
          'before leaving the area. End of complete quest instruction.';
      final marker = PreparedMarker(
        id: 'quest-objective-3ef16a317852',
        category: 'questObjectives',
        filterKey: 'QuestObjectives',
        name: instruction,
        position: GamePoint(1, 2),
        details: const {'description': instruction},
        source: const {'mapId': 'map-a'},
        outline: const [],
      );
      final presentation = presentMarker(marker);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              height: 240,
              child: MarkerPopup(
                presentation: presentation,
                anchor: const Offset(160, 120),
                detailsExpanded: false,
                onDetailsExpandedChanged: (_) {},
                onClose: () {},
                detailsBuilder: (_) => const Text('Raw bounded details.'),
              ),
            ),
          ),
        ),
      );

      final scrollable = find.byKey(const ValueKey('marker-popup-scroll'));
      final scrollableInstruction = find.descendant(
        of: scrollable,
        matching: find.text(instruction),
      );
      expect(scrollableInstruction, findsOneWidget);
      expect(find.text('Raw bounded details.'), findsNothing);
      final scrollController = tester
          .state<ScrollableState>(
            find.descendant(of: scrollable, matching: find.byType(Scrollable)),
          )
          .position;
      expect(scrollController.maxScrollExtent, greaterThan(0));

      await tester.drag(scrollable, const Offset(0, -10000));
      await tester.pump();

      expect(scrollController.pixels, scrollController.maxScrollExtent);
      final instructionRect = tester.getRect(scrollableInstruction);
      final scrollRect = tester.getRect(scrollable);
      expect(instructionRect.bottom, greaterThan(scrollRect.top));
      expect(instructionRect.bottom, lessThanOrEqualTo(scrollRect.bottom));
      expect(find.text('Raw bounded details.'), findsNothing);
    },
  );
}
