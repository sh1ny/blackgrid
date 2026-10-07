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

  group('competing exit names', () {
    // Factory's exits share "Gate"; Gate 3 has two spatial marker copies.
    final factory = RaidExfilMatcher([
      RaidExitIdentity(id: 'med', name: 'Med Tent Gate', transit: false),
      RaidExitIdentity(id: 'g3a', name: 'Gate 3', transit: false),
      RaidExitIdentity(id: 'g3b', name: 'Gate 3', transit: false),
      RaidExitIdentity(id: 'court', name: 'Courtyard Gate', transit: false),
      RaidExitIdentity(id: 'g2', name: 'Gate 2', transit: false),
      RaidExitIdentity(id: 'g0', name: 'Gate 0', transit: false),
    ]);

    test('a fragment shared by several exits authorizes none', () {
      for (final evidence in [
        _recognized(extracts: ['Gate']),
        _recognized(raw: 'Find an extraction point\nGate 10:00'),
      ]) {
        final result = factory.match(evidence);
        expect(result.state, RaidPanelState.ambiguous);
        expect(result.ids, isEmpty);
      }
    });

    test('one ambiguous row withholds the whole panel', () {
      final result = factory.match(_recognized(extracts: ['Gate 0', 'Gate']));
      expect(result.state, RaidPanelState.ambiguous);
      expect(result.ids, isEmpty);
    });

    test('a specific name authorizes every spatial copy of only that exit', () {
      for (final evidence in [
        _recognized(extracts: ['Gate 3']),
        _recognized(extracts: ['Gate 3 10:00']),
        _recognized(raw: 'Find an extraction point\nGate 3 10:00'),
      ]) {
        final result = factory.match(evidence);
        expect(result.state, RaidPanelState.recognized);
        expect(result.ids, {'g3a', 'g3b'});
      }
      expect(factory.match(_recognized(extracts: ['Med Tent Gate'])).ids, {
        'med',
      });
    });

    test('fuzzy rows resolve to the uniquely closest exit', () {
      expect(factory.match(_recognized(extracts: ['Courtyard Gatc'])).ids, {
        'court',
      });
    });

    test('shared words do not cancel a distinctive raw hit', () {
      final matcher = RaidExfilMatcher([
        RaidExitIdentity(id: 'rail', name: 'Railway Exfil', transit: false),
        RaidExitIdentity(id: 'boat', name: 'Boat Exfil', transit: false),
      ]);
      final result = matcher.match(_recognized(raw: 'Railway 10:00 Exfil'));
      expect(result.state, RaidPanelState.recognized);
      expect(result.ids, {'rail'});
    });
  });
}
