import 'package:flutter_test/flutter_test.dart';
import 'package:blackgrid/domain/raid_panel_text_parser.dart';

import '../fixtures/raid_panel/header_samples.dart';

const _green = 0x3CC850; // r=60 g=200 b=80
const _dark = 0x141618;
const _white = 0xE6E6E6;

RaidPanelNames _parse(List<String> lines) {
  final names = RaidPanelNames();
  const RaidPanelTextParser().parse(lines.join('\n'), lines, names);
  return names;
}

// The 12 × 10 saved-sample grid covers the scanned part of a small ultrawide frame.
bool _detectSavedHeader(String frame) {
  final rows = savedRaidHeaderSamples[frame]!;
  final pixels = [
    for (final row in rows)
      [
        for (var i = 0; i < row.length; i += 6)
          int.parse(row.substring(i, i + 6), radix: 16),
      ],
  ];
  const width = 120, height = 28;
  final profile = RaidPanelProfile.forSize(width, height);
  return profile.detect(
    width,
    height,
    (x, y) => pixels[(y - 4) ~/ 2][(x - 69) ~/ 4],
  );
}

void main() {
  test('resolution profiles follow the reference companion tuning', () {
    final ultrawide = RaidPanelProfile.forSize(3440, 1440);
    expect(ultrawide.name, 'Ultrawide');
    expect(ultrawide.ocrScaleFactor, 1.35);
    expect(RaidPanelProfile.forSize(2560, 1440).name, '1440p');
    expect(RaidPanelProfile.forSize(2560, 1440).ocrScaleFactor, 1.15);
    expect(RaidPanelProfile.forSize(3840, 2160).name, '4K');
    final hd = RaidPanelProfile.forSize(1920, 1080);
    expect(hd.name, '1080p');
    expect(hd.ocrScaleFactor, closeTo(1440 / 1080, 1e-9));
  });

  test(
    'green header in the right panel area is detected, dark frame is not',
    () {
      const width = 3440, height = 1440;
      final profile = RaidPanelProfile.forSize(width, height);
      final panelLeft = (width * 0.64).toInt();
      int panel(int x, int y) => x >= panelLeft && y < 90 ? _green : _dark;
      expect(profile.detect(width, height, panel), isTrue);
      expect(profile.detect(width, height, (_, _) => _dark), isFalse);
      expect(profile.detect(width, height, (_, _) => _white), isFalse);
      expect(_detectSavedHeader('2026-11-25 raid time 12.10'), isTrue);
    },
  );

  test('detects an exfil header dimmed by night vision', () {
    const width = 120, height = 28;
    const reportedHeader = 0x5D8807; // #140: RGB (93, 136, 7).
    final profile = RaidPanelProfile.forSize(width, height);
    int panel(int x, int y) => x >= 84 && y < 16 ? reportedHeader : _dark;
    expect(profile.detect(width, height, panel), isTrue);
  });

  for (final time in ['12.02', '12.44']) {
    test('detects the saved Shoreline night-vision panel at $time', () {
      expect(_detectSavedHeader('2026-11-25 raid time $time'), isTrue);
    });
  }

  test('rejects night-vision scenery without an exfil header', () {
    for (final time in ['2.12', '3.90', '5.75']) {
      expect(
        _detectSavedHeader('2026-11-21 raid time $time'),
        isFalse,
        reason: 'saved night-vision scenery at $time',
      );
    }

    const width = 120, height = 28;
    final profile = RaidPanelProfile.forSize(width, height);
    const nearMisses = {
      'ordinary green tint': 0x5D8842,
      'saturated green light': 0x248802,
      'dim yellow-olive tint': 0x738F02,
    };
    for (final entry in nearMisses.entries) {
      int scenery(int x, int y) => x >= 84 && y < 16 ? entry.value : _dark;
      expect(
        profile.detect(width, height, scenery),
        isFalse,
        reason: entry.key,
      );
    }
  });

  test('dim header pixels do not extend the panel crop', () {
    const width = 2560, height = 1440;
    final profile = RaidPanelProfile.forSize(width, height);
    int panel(int x, int y) {
      if (y < 846) return _white;
      if (y >= 850 && y < 950) return 0x5D8807;
      return 0x808080;
    }

    expect(profile.panelBottom(width, height, panel), 873);
  });

  test('panel bottom follows text rows and crop is right anchored', () {
    const width = 2560, height = 1440;
    final profile = RaidPanelProfile.forSize(width, height);
    int panel(int x, int y) => y < 100 ? _green : (y < 700 ? _white : 0x808080);
    final bottom = profile.panelBottom(width, height, panel);
    // Text ends at 699; the 58% minimum panel height (835) governs.
    expect(bottom, 835);
    final crop = profile.crop(width, height, bottom);
    expect(crop.right, width);
    expect(crop.left, width - (width * 0.52).toInt());
    expect(crop.top, 0);
    expect(crop.bottom, bottom);
  });

  test('panel text colours match light, green and red glyphs only', () {
    expect(isLikelyRaidPanelText(_white), isTrue);
    expect(isLikelyRaidPanelText(_green), isTrue);
    expect(isLikelyRaidPanelText(0xD23C3C), isTrue);
    expect(isLikelyRaidPanelText(_dark), isFalse);
    expect(isLikelyRaidPanelText(0x2050C0), isFalse);
  });

  test('tagged rows yield extract and transit names without timers', () {
    final names = _parse([
      'Find an extraction point',
      'EXFIL01 Road to Customs 12:34',
      'EXFILO2 Railway Exfil ??:??:??',
      'TRANSIT01 Transit to Woods',
    ]);
    // Like the reference, a name containing "Exfil" also yields its prefix;
    // current-map matching resolves both reads to the same identity.
    expect(names.extracts, containsAll(['Road to Customs', 'Railway Exfil']));
    expect(names.transits, ['Transit to Woods']);
  });

  test('known tag misreads normalize, headers and timers are ignored', () {
    final names = _parse([
      'EX1T 03 Tunnel',
      'EXI T04 Smugglers Boat',
      '12:00',
      'Keycard required',
      'TRANSI1 01 Transit to Lighthouse',
    ]);
    expect(names.extracts, containsAll(['Tunnel', 'Smugglers Boat']));
    expect(names.transits, ['Transit to Lighthouse']);
  });

  test('untagged names before TRANSIT are extracts, after it transits', () {
    final names = _parse([
      'Pier Boat',
      'TRANSIT',
      'Transit to Streets of Tarkov',
    ]);
    expect(names.extracts, ['Pier Boat']);
    expect(names.transits, ['Transit to Streets of Tarkov']);
  });

  test('repeated reads deduplicate case-insensitively', () {
    final names = RaidPanelNames();
    const parser = RaidPanelTextParser();
    parser.parse('EXFIL01 Tunnel', ['EXFIL01 Tunnel'], names);
    parser.parse('EXFIL01 TUNNEL', ['EXFIL01 TUNNEL'], names);
    expect(names.extracts, ['Tunnel']);
  });

  test('slashed-zero row labels split rows like plain zeros', () {
    const slashed =
        'Find an extraction point EXFILØI Road to North V-Ex '
        'EXFILØ2 Road to Customs EXFILØ3 Railway Bridge '
        'EXFILØ4 Path to Lighthouse TRANSITØI Transit to Lighthouse '
        'TRANSITØ4 Transit to Icebreaker';
    const plain =
        'Find an extraction point EXFIL01 Road to North V-Ex '
        'EXFIL02 Road to Customs EXFIL03 Railway Bridge '
        'EXFIL04 Path to Lighthouse TRANSIT01 Transit to Lighthouse '
        'TRANSIT04 Transit to Icebreaker';
    final rows = [
      for (final text in [slashed, plain]) _parse([text]),
    ];
    for (final names in rows) {
      expect(
        names.extracts,
        containsAll(['Road to Customs', 'Railway Bridge']),
      );
      expect(
        names.transits,
        containsAll(['Transit to Lighthouse', 'Transit to Icebreaker']),
      );
      for (final row in [...names.extracts, ...names.transits]) {
        expect(row.toUpperCase(), isNot(contains('EXFIL')));
        expect(row.toUpperCase(), isNot(contains('TRANSIT0')));
        expect(row.toUpperCase(), isNot(contains('TRANSITØ')));
      }
    }
    expect(rows[0].extracts, rows[1].extracts);
    expect(rows[0].transits, rows[1].transits);
  });

  test('every zero and one misread in a row number is repaired', () {
    final names = _parse([
      'Find an extraction point EXFILO1 Road to North V-Ex '
          'EXFILo2 Road to Customs EXFIL Ø3 Railway Bridge '
          'EXFIL  0l Path to Lighthouse EXFIL0| Pier Boat '
          'TRANSITØI Transit to Lighthouse TRANSIT  Ø4 Transit to Icebreaker',
    ]);
    expect(
      names.extracts,
      containsAll([
        'Road to North V-Ex',
        'Road to Customs',
        'Railway Bridge',
        'Path to Lighthouse',
        'Pier Boat',
      ]),
    );
    expect(
      names.transits,
      containsAll(['Transit to Lighthouse', 'Transit to Icebreaker']),
    );
    for (final row in [...names.extracts, ...names.transits]) {
      expect(row, isNot(contains(RegExp(r'(EXFIL|TRANSIT)\s*\S\S'))));
    }
  });

  test('a row number never joins a label across a line break', () {
    // A line ending in an upper-case label word must not turn the start of
    // the next line into that label's row number.
    final names = _parse(['EXFIL01 Smugglers Path EXIT', 'Ol Boat']);
    expect(names.extracts, isNot(contains('Boat')));
  });

  test('a label followed by a word keeps the word\'s letters', () {
    final names = _parse(['EXFIL01 EXIT Old Bunker EXFIL02 TRANSIT Oil Gate']);
    expect(
      names.extracts,
      containsAll(['EXIT Old Bunker', 'TRANSIT Oil Gate']),
    );
  });

  test('an Exfil word without a row number stays in the name', () {
    final names = _parse(['EXFIL02 Saferoom Exfil EXFIL03 Railway Exfil']);
    expect(names.extracts, containsAll(['Saferoom Exfil', 'Railway Exfil']));
    expect(names.extracts.where((row) => row.contains('Railway')), [
      'Railway Exfil',
    ]);
  });

  test('merging two recognitions keeps text and unique lines', () {
    expect(mergeRaidOcrText('', 'b'), 'b');
    expect(mergeRaidOcrText('abc def', 'DEF'), 'abc def');
    expect(mergeRaidOcrText('x', 'y'), 'x\ny');
    expect(mergeRaidOcrLines([' A ', 'b'], ['a', 'c', '']), ['A', 'b', 'c']);
  });
}
