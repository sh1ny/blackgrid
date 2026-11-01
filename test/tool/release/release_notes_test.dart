import 'package:flutter_test/flutter_test.dart';

import '../../../tool/release/src/release_notes.dart';

ReleaseNotes _valid(String proposal) {
  final result = parseReleaseNotes(proposal);
  expect(result, isA<ReleaseNotes>(), reason: '$result');
  return result as ReleaseNotes;
}

List<(int, String)> _errors(String proposal) {
  final result = parseReleaseNotes(proposal);
  expect(result, isA<ReleaseNotesInvalid>(), reason: '$result');
  return [
    for (final e in (result as ReleaseNotesInvalid).errors) (e.line, e.message),
  ];
}

List<String> _texts(ReleaseNotes notes, String heading) => [
  for (final item in notes.items[heading] ?? const <ReleaseNoteItem>[])
    item.text,
];

void main() {
  group('parseReleaseNotes', () {
    test('a valid section yields its summary and items', () {
      final notes = _valid(
        '# P\n'
        '\n'
        '## Release Notes\n'
        '\n'
        'Players get faster scans.\n'
        '\n'
        '### Added\n'
        '- One\n'
        '- Two\n'
        '\n'
        '### Fixed\n'
        '- Three\n',
      );
      expect(notes.summary, 'Players get faster scans.');
      expect(notes.items.keys, ['added', 'fixed']);
      expect(_texts(notes, 'added'), ['One', 'Two']);
      expect(_texts(notes, 'fixed'), ['Three']);
      expect(notes.items['added']!.map((i) => i.line), [8, 9]);
      expect(notes.items['fixed']!.single.line, 12);
    });

    test('an indented line continues the item above with one space', () {
      final notes = _valid(
        '## Release Notes\nSum.\n### Added\n- first part\n  second part\n',
      );
      expect(_texts(notes, 'added'), ['first part second part']);
    });

    test('list markers, heading case and CRLF are accepted', () {
      final notes = _valid(
        '## release notes\r\nSum.\r\n### ADDED\r\n* a\r\n+ b\r\n',
      );
      expect(_texts(notes, 'added'), ['a', 'b']);
    });

    test('HTML comments and blank lines are ignored', () {
      final notes = _valid(
        '## Release Notes\n'
        '<!-- one -->\n'
        'Sum.\n'
        '<!--\n'
        'multi\n'
        'line\n'
        '-->\n'
        '\n'
        '### Added\n'
        '\n'
        '- x <!-- inline -->\n'
        '\n'
        '- y\n',
      );
      expect(notes.summary, 'Sum.');
      expect(_texts(notes, 'added'), ['x', 'y']);
      // Comment newlines are kept, so lines are the file's.
      expect(notes.items['added']!.map((i) => i.line), [11, 13]);
    });

    test('the section ends at the next ## heading', () {
      final notes = _valid(
        '## Release Notes\n'
        'Sum.\n'
        '### Added\n'
        '- x\n'
        '## Impact\n'
        'prose here\n'
        '### Whatever\n',
      );
      expect(_texts(notes, 'added'), ['x']);
      expect(notes.items.keys, ['added']);
    });

    test('the section runs to the end of the proposal', () {
      final notes = _valid('## Release Notes\nSum.\n### Removed\n- gone');
      expect(_texts(notes, 'removed'), ['gone']);
    });

    group('each invalid form is reported with its line and problem', () {
      test('no summary', () {
        expect(_errors('## Release Notes\n### Added\n- x\n'), [
          (1, 'the summary is missing (text before the first ### heading)'),
        ]);
      });

      test('unknown heading', () {
        expect(_errors('## Release Notes\nSum.\n### Security\n- x\n'), [
          (
            3,
            "unknown heading 'Security' "
                '(use Added, Changed, Fixed or Removed)',
          ),
        ]);
      });

      test('prose under a heading', () {
        expect(
          _errors('## Release Notes\nSum.\n### Added\nsome prose\n- x\n'),
          [
            (
              4,
              'line is neither a list item nor an indented continuation: '
                  'some prose',
            ),
          ],
        );
      });

      test('a duplicate heading', () {
        expect(
          _errors('## Release Notes\nSum.\n### Added\n- x\n### Added\n- y\n'),
          [(5, "heading 'Added' appears twice")],
        );
      });

      test('headings with no item at all', () {
        expect(_errors('# P\n\n## Release Notes\nSum.\n\n### Added\n'), [
          (3, 'no list item under Added, Changed, Fixed or Removed'),
        ]);
      });

      test('an empty heading beside one with items stays valid', () {
        // release.sh accepts this section, so the Dart parser does too.
        final notes = _valid(
          '## Release Notes\nSum.\n### Added\n\n### Fixed\n- y\n',
        );
        expect(notes.items.keys, ['fixed']);
        expect(_texts(notes, 'fixed'), ['y']);
      });

      test('a summary of 601 characters', () {
        final summary = 'a' * 601;
        expect(_errors('## Release Notes\n$summary\n### Added\n- x\n'), [
          (1, 'summary is 601 characters, over the 600 limit'),
        ]);
        expect(
          _valid('## Release Notes\n${'a' * 600}\n### Added\n- x\n').summary,
          hasLength(600),
        );
      });

      test('an item of 501 characters', () {
        expect(_errors('## Release Notes\nSum.\n### Added\n- ${'b' * 501}\n'), [
          (4, 'item is 501 characters, over the 500 limit'),
        ]);
        expect(
          _valid('## Release Notes\nSum.\n### Added\n- ${'b' * 500}\n').items,
          isNotEmpty,
        );
      });

      test('every error is collected in line order', () {
        expect(
          _errors(
            '## Release Notes\n'
            'Sum.\n'
            '### Security\n'
            '- x\n'
            '### Added\n'
            'prose\n',
          ),
          [
            (
              3,
              "unknown heading 'Security' "
                  '(use Added, Changed, Fixed or Removed)',
            ),
            (
              6,
              'line is neither a list item nor an indented continuation: '
                  'prose',
            ),
          ],
        );
      });
    });

    test('a proposal without the heading reports no release notes', () {
      expect(
        parseReleaseNotes('# P\n\n## Why\nBecause.\n'),
        isA<NoReleaseNotes>(),
      );
      expect(const NoReleaseNotes().message, contains('no release notes'));
    });
  });

  group('firstWhySentence', () {
    String? why(String body) => firstWhySentence('# P\n\n## Why\n$body');

    test('takes the first sentence of the first paragraph', () {
      expect(why('\nIt is slow. It is also odd.\n\nNext.\n'), 'It is slow.');
    });

    test('joins the lines of a wrapped paragraph', () {
      expect(why('One two\nthree four.\n'), 'One two three four.');
    });

    test('drops a leading list marker and stops at the next marker', () {
      expect(why('- First item\n  goes on\n- Second.\n'), 'First item goes on');
      expect(why('1. Numbered. More.\n'), 'Numbered.');
    });

    test('skips abbreviations and backtick code spans', () {
      expect(why('Use e.g. a flag. Then more.\n'), 'Use e.g. a flag.');
      expect(why('Run `a. b` now. After.\n'), 'Run `a. b` now.');
    });

    test('a dot inside a word does not end the sentence', () {
      expect(why('Version 1.2 is out! Next.\n'), 'Version 1.2 is out!');
    });

    test('with no sentence end the whole paragraph is returned', () {
      expect(why('no end here\n'), 'no end here');
    });

    test('over 300 characters is cut to 299 plus an ellipsis', () {
      final result = why('${'a' * 400}.\n')!;
      expect(result, '${'a' * 299}…');
      expect(result, hasLength(300));
      expect(why('${'a' * 299}.\n'), '${'a' * 299}.');
    });

    test('is null without the heading or without text', () {
      expect(firstWhySentence('# P\n\n## What\nx.\n'), isNull);
      expect(why('\n\n## Next\nx.\n'), isNull);
      expect(why(''), isNull);
    });
  });

  group('namesReference', () {
    test('an issue or PR number outside a code span is a reference', () {
      expect(namesReference('Fixes #12 here'), isTrue);
      expect(namesReference('See (#7)'), isTrue);
    });

    test('code spans, bare hashes and word-joined numbers are not', () {
      expect(namesReference('uses `#5` literal'), isFalse);
      expect(namesReference('uses ``a # #5`` literal'), isFalse);
      expect(namesReference('colour #fff and #1a'), isFalse);
      expect(namesReference('plain text'), isFalse);
    });
  });
}
