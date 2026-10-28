import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:blackgrid/domain/settings.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/markers/icon_set.dart';
import 'support/icon_set_fixture.dart';

void main() {
  late SetFixture fx;

  setUp(() => fx = SetFixture.create());
  tearDown(() => fx.dispose());

  group('coverage', () {
    test('coverage: release set with all 19 keys is valid', () {
      final set = expectValid(checkIconSet(fx.manifestPath));
      expect(set.icons, hasLength(19));
      expect(set.scope, IconSetScope.release);
    });

    test('coverage: missing BtrStops is named', () {
      fx.icons.removeWhere((i) => (i! as Map)['key'] == 'BtrStops');
      fx.write();
      expectFailure(
        checkIconSet(fx.manifestPath),
        rule: 'coverage',
        subject: 'BtrStops',
        contains: ['missing'],
      );
    });

    test(
      'coverage: candidate set with 6 keys passes coverage, other rules still '
      'apply',
      () {
        fx.dispose();
        fx = SetFixture.create(scope: 'candidate', keys: iconKeys.take(6));
        expect(expectValid(checkIconSet(fx.manifestPath)).icons, hasLength(6));

        fx.file('PmcExtracts').deleteSync();
        final failures = failuresOf(checkIconSet(fx.manifestPath));
        expect(failures.where((f) => f.rule == 'coverage'), isEmpty);
        expect(
          failures.any((f) => f.subject == 'pmc_extracts.svg'),
          isTrue,
          reason: 'a bad file in a candidate set still fails',
        );
      },
    );

    test('coverage: Labels and duplicate PmcExtracts are named', () {
      fx.icons.add(<String, Object?>{
        ...fx.icon('PmcExtracts'),
        'key': 'Labels',
      });
      fx.icons.add(Map<String, Object?>.of(fx.icon('PmcExtracts')));
      fx.write();
      final result = checkIconSet(fx.manifestPath);
      expectFailure(
        result,
        rule: 'coverage',
        subject: 'Labels',
        contains: ['unknown'],
      );
      expectFailure(
        result,
        rule: 'coverage',
        subject: 'PmcExtracts',
        contains: ['duplicate'],
      );
    });

    test('coverage: key list equals markerCategories minus Labels', () {
      final expected = markerCategories.where((k) => k != 'Labels').toList();
      expect(iconKeys.toSet(), expected.toSet());
      expect(iconKeys, hasLength(19));
      expect(iconKeys, expected);
    });
  });

  group('manifest', () {
    test('unknown fields are rejected at every level, naming the field', () {
      fx.manifest['extra'] = 1;
      (fx.manifest['badge']! as Map<String, Object?>)['bogus'] = 1;
      fx.icon('Transits')['nope'] = 1;
      fx.provenance('Transits')['who'] = 1;
      (fx.provenance('Transits')['concept']! as Map<String, Object?>)['x'] = 1;
      fx.write();
      final failures = failuresOf(checkIconSet(fx.manifestPath));
      for (final field in ['extra', 'bogus', 'nope', 'who', 'x']) {
        expect(
          failures.any(
            (f) => f.rule == 'manifest' && f.value.contains('"$field"'),
          ),
          isTrue,
          reason: field,
        );
      }
    });

    test('file names must be lower snake case beside the manifest', () {
      fx.icon('Transits')['file'] = 'sub/transits.svg';
      fx.icon('Switches')['file'] = 'Switches.svg';
      fx.icon('locks')['file'] = '../locks.svg';
      fx.write();
      final result = checkIconSet(fx.manifestPath);
      for (final bad in ['sub/transits.svg', 'Switches.svg', '../locks.svg']) {
        expectFailure(result, rule: 'file-name', subject: bad);
      }
    });

    test('file names must be derived from the key', () {
      fx.icon('Hazards')['file'] = 'hazard.svg';
      fx.write();
      expectFailure(
        checkIconSet(fx.manifestPath),
        rule: 'file-name',
        subject: 'hazard.svg',
      );
    });

    test('iconFileName derives lower snake case', () {
      expect(iconFileName('PmcExtracts'), 'pmc_extracts.svg');
      expect(iconFileName('lootContainers'), 'loot_containers.svg');
      expect(iconFileName('CustomPins'), 'custom_pins.svg');
      expect(iconFileName('stationaryWeapons'), 'stationary_weapons.svg');
    });

    test('failures format as one line', () {
      const failure = IconSetFailure(
        rule: 'form',
        subject: 'a.svg',
        value: 'bad\nthing',
      );
      expect(formatFailure(failure), 'form: a.svg: bad thing');
    });
  });

  group('form', () {
    const head = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"';

    IconSetResult withSvg(String svg, {IconCompiler? compile}) {
      fx.setSvg('Transits', svg);
      fx.write();
      return compile == null
          ? checkIconSet(fx.manifestPath)
          : checkIconSet(fx.manifestPath, compile: compile);
    }

    test(
      'form: path and circle glyph in tint passes and compiles non-empty',
      () {
        var compiled = 0;
        final result = withSvg(
          '$head><path d="M2 2h20v20H2z" fill="#fff"/>'
          '<circle cx="12" cy="12" r="4" fill="white"/></svg>',
          compile: (xml, name) {
            final bytes = compileIconSvg(xml, name);
            expect(bytes, isNotEmpty);
            compiled++;
            return bytes;
          },
        );
        expectValid(result);
        expect(compiled, 19);
      },
    );

    test('form: image, text and href are named', () {
      final cases = {
        'image': '$head><image width="4" height="4"/></svg>',
        'text': '$head><text fill="#fff">x</text></svg>',
        'href': '$head><path d="M0 0h1v1z" fill="#fff" href="x"/></svg>',
      };
      for (final MapEntry(:key, :value) in cases.entries) {
        expectFailure(
          withSvg(value),
          rule: 'form',
          subject: 'transits.svg',
          contains: [key],
        );
      }
    });

    test('form: onload and unlisted attributes are named', () {
      expectFailure(
        withSvg('$head onload="x()"><path d="M0 0h1v1z" fill="#fff"/></svg>'),
        rule: 'form',
        subject: 'transits.svg',
        contains: ['onload', 'svg'],
      );
      expectFailure(
        withSvg('$head><path d="M0 0h1v1z" fill="#fff" onload="x()"/></svg>'),
        rule: 'form',
        subject: 'transits.svg',
        contains: ['onload', 'path'],
      );
      expectFailure(
        withSvg(
          '$head><circle cx="1" cy="1" r="1" d="M0 0" fill="#fff"/></svg>',
        ),
        rule: 'form',
        subject: 'transits.svg',
        contains: ['"d"', 'circle'],
      );
      for (final attr in ['style="x:y"', 'id="a"', 'class="c"']) {
        expectFailure(
          withSvg('$head><path d="M0 0h1v1z" fill="#fff" $attr/></svg>'),
          rule: 'form',
          subject: 'transits.svg',
          contains: [attr.split('=').first],
        );
      }
      expectFailure(
        withSvg(
          '$head xmlns:xlink="http://www.w3.org/1999/xlink">'
          '<path d="M0 0h1v1z" fill="#fff"/></svg>',
        ),
        rule: 'form',
        subject: 'transits.svg',
        contains: ['xmlns:xlink'],
      );
    });

    test(
      'form: default black fill fails, root and g inherited tint passes',
      () {
        expectFailure(
          withSvg('$head><path d="M0 0h1v1z"/></svg>'),
          rule: 'form',
          subject: 'transits.svg',
          contains: ['path', 'fill', 'black'],
        );
        expectValid(withSvg('$head fill="#fff"><path d="M0 0h1v1z"/></svg>'));
        expectValid(
          withSvg('$head><g fill="#fff"><path d="M0 0h1v1z"/></g></svg>'),
        );
        expectValid(
          withSvg(
            '$head><path d="M0 0h1v1z" fill="none" stroke="#fff"/></svg>',
          ),
        );
      },
    );

    test('form: second colour and wrong viewBox are named', () {
      expectFailure(
        withSvg('$head><path d="M0 0h1v1z" fill="#ff0000"/></svg>'),
        rule: 'form',
        subject: 'transits.svg',
        contains: ['fill', '#ff0000'],
      );
      expectFailure(
        withSvg(
          '$head><path d="M0 0h1v1z" fill="#fff" stroke="#00ff00"/></svg>',
        ),
        rule: 'form',
        subject: 'transits.svg',
        contains: ['stroke', '#00ff00'],
      );
      expectFailure(
        withSvg(
          '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16">'
          '<path d="M0 0h1v1z" fill="#fff"/></svg>',
        ),
        rule: 'form',
        subject: 'transits.svg',
        contains: ['viewBox', '0 0 16 16'],
      );
    });

    test('form: file over 8 KiB is named with its size', () {
      final svg =
          '$head><path d="M0 0h1v1z" fill="#fff"/>'
          '<!-- ${'x' * 8300} --></svg>';
      expectFailure(
        withSvg(svg),
        rule: 'form',
        subject: 'transits.svg',
        contains: ['${svg.length} bytes', '8192'],
      );
    });

    test('form: malformed XML and compiler warning fail', () {
      expectFailure(
        withSvg('$head><path d="M0 0h1v1z" fill="#fff"></svg>'),
        rule: 'form',
        subject: 'transits.svg',
        contains: ['malformed'],
      );
      // An allow-listed element whose path data the compiler rejects.
      final warned = withSvg('$head><path d="M2 2 L foo" fill="#fff"/></svg>');
      expectFailure(
        warned,
        rule: 'form',
        subject: 'transits.svg',
        contains: ['compiler'],
      );
      expect(warned, isA<IconSetInvalid>());
      // Empty compiler output also fails.
      expectFailure(
        withSvg(validSvg, compile: (xml, name) => Uint8List(0)),
        rule: 'form',
        subject: 'transits.svg',
        contains: ['empty'],
      );
    });
  });

  group('palette', () {
    Map<String, Object?> roles() =>
        fx.manifest['roles']! as Map<String, Object?>;

    test('palette: starting D7 palette passes', () {
      expectValid(checkIconSet(fx.manifestPath));
    });

    test('palette: ScavExtracts outside exit role is named', () {
      fx.icon('ScavExtracts')['role'] = 'spawn';
      fx.write();
      expectFailure(
        checkIconSet(fx.manifestPath),
        rule: 'palette',
        subject: 'ScavExtracts',
        contains: ['exit'],
      );
    });

    test('palette: required danger and pin roles are enforced', () {
      fx.icon('Hazards')['role'] = 'loot';
      fx.icon('CustomPins')['role'] = 'loot';
      fx.write();
      final result = checkIconSet(fx.manifestPath);
      expectFailure(
        result,
        rule: 'palette',
        subject: 'Hazards',
        contains: ['danger'],
      );
      expectFailure(
        result,
        rule: 'palette',
        subject: 'CustomPins',
        contains: ['pin'],
      );
    });

    test('palette: undefined role is named', () {
      fx.icon('Switches')['role'] = 'nowhere';
      fx.write();
      expectFailure(
        checkIconSet(fx.manifestPath),
        rule: 'palette',
        subject: 'Switches',
        contains: ['nowhere'],
      );
    });

    test(
      'palette: hue 185 and contrast 2.4 are named; grey below 10% saturation '
      'passes',
      () {
        roles()['teal'] = '#00EAFF';
        roles()['dim'] = '#505050';
        fx.write();
        final result = checkIconSet(fx.manifestPath);
        expectFailure(
          result,
          rule: 'palette',
          subject: 'teal',
          contains: ['#00EAFF', 'hue 184.9'],
        );
        expectFailure(
          result,
          rule: 'palette',
          subject: 'dim',
          contains: ['#505050', 'contrast 2.4'],
        );

        roles()
          ..remove('teal')
          ..remove('dim')
          ..['mist'] = '#BEC8C8';
        fx.write();
        expectValid(checkIconSet(fx.manifestPath));
      },
    );
  });

  group('provenance', () {
    test(
      'provenance: ai-assisted record with tool and matching hash passes',
      () {
        expectValid(checkIconSet(fx.manifestPath));
      },
    );

    test('provenance: missing and stale records are named', () {
      fx.icon('Transits').remove('provenance');
      fx.file('Switches').writeAsStringSync('$validSvg ');
      fx.write();
      final result = checkIconSet(fx.manifestPath);
      expectFailure(
        result,
        rule: 'provenance',
        subject: 'transits.svg',
        contains: ['missing'],
      );
      expectFailure(
        result,
        rule: 'provenance',
        subject: 'switches.svg',
        contains: ['stale', sha(utf8.encode('$validSvg '))],
      );
    });

    test(
      'provenance: ai-assisted without tools and concept without prompt record '
      'are named',
      () {
        fx.provenance('Transits').remove('tools');
        fx.provenance('Switches')['tools'] = <Object?>[];
        fx.provenance('locks')['concept'] = {'source': 'Midjourney'};
        fx.write();
        final result = checkIconSet(fx.manifestPath);
        expectFailure(
          result,
          rule: 'provenance',
          subject: 'transits.svg',
          contains: ['tools'],
        );
        expectFailure(
          result,
          rule: 'provenance',
          subject: 'switches.svg',
          contains: ['tools'],
        );
        expectFailure(
          result,
          rule: 'provenance',
          subject: 'locks.svg',
          contains: ['promptRecord'],
        );
      },
    );

    test('provenance: prompt record must exist inside the manifest tree', () {
      File('${fx.dir.path}/prompt.md').writeAsStringSync('prompt');
      fx.provenance('locks')['concept'] = {
        'source': 'Midjourney',
        'promptRecord': 'prompt.md',
      };
      fx.provenance('Switches')['concept'] = {
        'source': 'Midjourney',
        'promptRecord': '../prompt.md',
      };
      fx.provenance('Transits')['concept'] = {
        'source': 'Midjourney',
        'promptRecord': 'absent.md',
      };
      fx.write();
      final result = checkIconSet(fx.manifestPath);
      final failures = failuresOf(result);
      expect(failures.where((f) => f.subject == 'locks.svg'), isEmpty);
      expectFailure(
        result,
        rule: 'provenance',
        subject: 'switches.svg',
        contains: ['promptRecord'],
      );
      expectFailure(
        result,
        rule: 'provenance',
        subject: 'transits.svg',
        contains: ['promptRecord'],
      );
    });

    test('provenance: required fields and date are enforced', () {
      fx.provenance('Transits').remove('author');
      fx.provenance('Switches')['date'] = '28/10/2026';
      fx.write();
      final result = checkIconSet(fx.manifestPath);
      expectFailure(
        result,
        rule: 'provenance',
        subject: 'transits.svg',
        contains: ['author'],
      );
      expectFailure(
        result,
        rule: 'provenance',
        subject: 'switches.svg',
        contains: ['date'],
      );
    });
  });

  group('origin', () {
    test('origin: hand-authored and ai-assisted project records pass', () {
      fx.provenance('Transits')
        ..['method'] = 'hand-authored'
        ..remove('tools');
      fx.write();
      expectValid(checkIconSet(fx.manifestPath));
    });

    test('origin: tarkov.dev origin and traced method are named', () {
      fx.provenance('Transits')['origin'] = 'tarkov.dev';
      fx.provenance('Switches')['method'] = 'traced';
      fx.write();
      final result = checkIconSet(fx.manifestPath);
      expectFailure(
        result,
        rule: 'origin',
        subject: 'transits.svg',
        contains: ['tarkov.dev'],
      );
      expectFailure(
        result,
        rule: 'origin',
        subject: 'switches.svg',
        contains: ['traced'],
      );
    });
  });
}
