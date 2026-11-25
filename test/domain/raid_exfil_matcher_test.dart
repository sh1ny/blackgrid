import 'dart:convert';
import 'dart:io';

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

  test('a short row matches only an exit with that exact name', () {
    final matcher = RaidExfilMatcher([
      RaidExitIdentity(id: 'd2', name: 'D-2', transit: false),
      RaidExitIdentity(
        id: 'terminal',
        name: 'Transit to Terminal',
        transit: true,
      ),
      RaidExitIdentity(
        id: 'lighthouse',
        name: 'Transit to Lighthouse',
        transit: true,
      ),
    ]);
    expect(matcher.match(_recognized(extracts: ['D-2'])).ids, {'d2'});
    final stray = matcher.match(_recognized(transits: ['I']));
    expect(stray.state, RaidPanelState.unreadable);
    expect(stray.ids, isEmpty);
    expect(RaidExfilMatcher.namesMatch('I', 'Transit to Terminal'), isFalse);
  });

  test('a merged row matches every whole exit name in it', () {
    final matcher = RaidExfilMatcher([
      RaidExitIdentity(id: 'tl', name: 'Transit to Lighthouse', transit: true),
      RaidExitIdentity(id: 'ti', name: 'Transit to Icebreaker', transit: true),
      RaidExitIdentity(id: 'tt', name: 'Transit to Terminal', transit: true),
      RaidExitIdentity(id: 'lh', name: 'Lighthouse', transit: true),
    ]);
    final result = matcher.match(
      _recognized(transits: ['Transit to Lighthouse Transit to Icebreaker']),
    );
    expect(result.state, RaidPanelState.recognized);
    expect(result.ids, {'tl', 'ti'});
  });

  test('recorded Shoreline panels match their listed exits', () {
    final fixture = jsonDecode(
      File('test/fixtures/raid_panel/shoreline_panels.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final exits = [
      for (final exit in fixture['exits'] as List)
        RaidExitIdentity(
          id: exit['id'] as String,
          name: exit['name'] as String,
          transit: exit['transit'] as bool,
        ),
    ];
    final nameOf = {for (final exit in exits) exit.id: exit.name};
    final matcher = RaidExfilMatcher(exits);
    for (final panel in fixture['panels'] as List) {
      final text = panel['text'] as String;
      final names = RaidPanelNames();
      const RaidPanelTextParser().parse(
        text,
        (panel['lines'] as List).cast<String>(),
        names,
      );
      final result = matcher.match(
        RaidPanelEvidence(
          state: RaidPanelState.recognized,
          extractNames: names.extracts,
          transitNames: names.transits,
          rawText: text,
        ),
      );
      final label = panel['label'];
      expect(result.state, RaidPanelState.recognized, reason: '$label');
      expect(
        {for (final id in result.ids) nameOf[id]},
        (panel['exits'] as List).cast<String>().toSet(),
        reason: '$label',
      );
    }
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
