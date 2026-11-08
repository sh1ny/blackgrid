import 'package:blackgrid/maps/map_palette.dart';
import 'package:blackgrid/ui/ember/ember_tokens.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mapSelectionColour equals the dark-room Ember accent', () {
    // The map is dark in both rooms, so selection takes the dark-room value
    // and not the room's own accent. The literal lives in `lib/maps`, which
    // imports nothing from `lib/ui`; this test is the only link between them.
    expect(mapSelectionColour, EmberColors.dark.accent);
    expect(mapSelectionColour.toARGB32(), 0xFFE9A14B);
  });

  test('the popup leader line takes the selection colour', () {
    expect(mapPopupLeaderLine, mapSelectionColour);
  });
}
