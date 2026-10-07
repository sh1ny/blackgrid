import 'package:flutter_test/flutter_test.dart';
import 'package:blackgrid/domain/raid_panel_text_parser.dart';

const _green = 0x3CC850; // r=60 g=200 b=80
const _dark = 0x141618;
const _white = 0xE6E6E6;

RaidPanelNames _parse(List<String> lines) {
  final names = RaidPanelNames();
  const RaidPanelTextParser().parse(lines.join('\n'), lines, names);
  return names;
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
    },
  );

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

  test('merging two recognitions keeps text and unique lines', () {
    expect(mergeRaidOcrText('', 'b'), 'b');
    expect(mergeRaidOcrText('abc def', 'DEF'), 'abc def');
    expect(mergeRaidOcrText('x', 'y'), 'x\ny');
    expect(mergeRaidOcrLines([' A ', 'b'], ['a', 'c', '']), ['A', 'b', 'c']);
  });
}
