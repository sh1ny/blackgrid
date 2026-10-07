import 'package:flutter_test/flutter_test.dart';
import 'package:blackgrid/domain/raid_exfil_matcher.dart';
import 'package:blackgrid/domain/raid_panel_text_parser.dart';

final _matcher = RaidExfilMatcher([
  RaidExitIdentity(id: 'road', name: 'Road to Customs', transit: false),
  RaidExitIdentity(id: 'rail', name: 'Railway Exfil', transit: false),
  RaidExitIdentity(id: 'boat', name: "Smuggler's Boat (Co-op)", transit: false),
  RaidExitIdentity(id: 'woods', name: 'Transit to Woods', transit: true),
]);

RaidPanelEvidence _recognized({
  List<String> extracts = const [],
  List<String> transits = const [],
  String raw = '',
}) => RaidPanelEvidence(
  state: RaidPanelState.recognized,
  extractNames: extracts,
  transitNames: transits,
  rawText: raw,
);

void main() {
  test('exact and OCR-noisy names resolve current-map identities', () {
    final result = _matcher.match(
      _recognized(extracts: ['Road to Custorns'], transits: ['Woods']),
    );
    expect(result.state, RaidPanelState.recognized);
    expect(result.ids, {'road', 'woods'});
  });

  test('raw engine text supplements names the row parser missed', () {
    final result = _matcher.match(
      _recognized(raw: 'Find an extraction point\nRailway Exfil 10:00'),
    );
    expect(result.ids, {'rail'});
  });

  test('parenthetical qualifiers are optional in raw text', () {
    final result = _matcher.match(_recognized(raw: "Smuggler's Boat"));
    expect(result.ids, {'boat'});
  });

  test('transit names only match transits and extract names only extracts', () {
    expect(
      _matcher.match(_recognized(transits: ['Road to Customs'])).ids,
      isEmpty,
    );
    expect(
      _matcher.match(_recognized(extracts: ['Transit to Woods'])).ids,
      isEmpty,
    );
  });

  test('a read panel without a current-map match publishes no ids', () {
    final result = _matcher.match(_recognized(extracts: ['Lighthouse Pier']));
    expect(result.state, RaidPanelState.unreadable);
    expect(result.ids, isEmpty);
  });

  test('non-recognized evidence never publishes ids', () {
    for (final state in RaidPanelState.values) {
      if (state == RaidPanelState.recognized) continue;
      final result = _matcher.match(
        RaidPanelEvidence(state: state, extractNames: ['Road to Customs']),
      );
      expect(result.state, state);
      expect(result.ids, isEmpty);
    }
  });

  test('similarity threshold rejects unrelated short names', () {
    expect(RaidExfilMatcher.namesMatch('Tunnel', 'Road to Customs'), isFalse);
    expect(
      RaidExfilMatcher.namesMatch('Railway Exfl', 'Railway Exfil'),
      isTrue,
    );
  });
}
