import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/release/src/git.dart';
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

  group('release range', () {
    late Directory dir;
    late Git git;

    Future<String> run(List<String> args) async {
      final r = await Process.run('git', [
        '-c',
        'user.name=Test',
        '-c',
        'user.email=test@example.com',
        '-c',
        'commit.gpgsign=false',
        '-c',
        'tag.gpgsign=false',
        ...args,
      ], workingDirectory: dir.path);
      if (r.exitCode != 0) fail('git ${args.join(' ')}: ${r.stderr}');
      return (r.stdout as String).trim();
    }

    String proposal({String? why, String? notes}) =>
        '# P\n\n## Why\n${why ?? 'Because.'}\n\n${notes ?? ''}';

    String section(String body) => '## Release Notes\n\nSummary.\n\n$body\n';

    Future<void> archive(String name, String text) async {
      final file = File(
        '${dir.path}/openspec/changes/archive/2026-01-01-$name/proposal.md',
      );
      await file.create(recursive: true);
      await file.writeAsString(text);
      await run(['add', '-A']);
    }

    Future<void> squash(String name, int? pr, String text) async {
      await archive(name, text);
      await run([
        'commit',
        '-m',
        pr == null ? 'feat: $name' : 'feat: $name (#$pr)',
      ]);
    }

    Future<void> mergePr(int pr, String name, String text) async {
      await run(['checkout', '-b', 'b-$name']);
      await archive(name, text);
      await run(['commit', '-m', 'feat: $name on a branch']);
      await run(['checkout', 'main']);
      await run([
        'merge',
        '--no-ff',
        'b-$name',
        '-m',
        'Merge pull request #$pr from o/b-$name',
      ]);
    }

    Future<List<RangeChange>> changes() async =>
        (await readReleaseRange(git)).changes;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('release_notes_range_');
      git = Git(const ProcessCommandRunner(), dir);
      await run(['init', '-b', 'main']);
      await run(['commit', '--allow-empty', '-m', 'chore: initial']);
    });

    tearDown(() => dir.delete(recursive: true));

    test('items are grouped across changes in first-parent order with the '
        'PR appended', () async {
      await squash(
        'a',
        80,
        proposal(notes: section('### Added\n- Raid timer')),
      );
      await mergePr(
        81,
        'b',
        proposal(
          notes: section(
            '### Fixed\n- Map centring (#77)\n\n### Added\n- Scav cooldown',
          ),
        ),
      );
      final range = await readReleaseRange(git);
      expect(range.lastFinalTag, isNull);
      expect(
        [for (final c in range.changes) (c.name, c.pr)],
        [('a', 80), ('b', 81)],
      );
      final rendered = renderReleaseNotes('Sum.', range.changes);
      expect(
        rendered.body,
        'Sum.\n\n'
        'Added:\n- Raid timer (#80)\n- Scav cooldown (#81)\n\n'
        'Fixed:\n- Map centring (#77)',
      );
      expect(rendered.warnings, isEmpty);
    });

    test('non-ASCII proposal text is read as UTF-8', () async {
      await squash(
        'u',
        5,
        proposal(
          why: 'Scans — finally… work.',
          notes:
              '## Release Notes\n\nNaïve — café…\n\n### Added\n- Ünïcode — ok…',
        ),
      );
      final change = (await changes()).single;
      final notes = change.notes! as ReleaseNotes;
      expect(notes.summary, 'Naïve — café…');
      expect(notes.items['added']!.single.text, 'Ünïcode — ok…');
      expect(change.why, 'Scans — finally… work.');
    });

    test('the range starts at the last final tag, not a prerelease', () async {
      await squash('old', 1, proposal());
      await run(['tag', '-a', 'v0.6.0', '-m', 'v0.6.0']);
      await squash('x', 2, proposal());
      await run(['tag', '-a', 'v0.7.0-beta.1', '-m', 'beta']);
      await squash('y', 3, proposal());
      final range = await readReleaseRange(git);
      expect(range.lastFinalTag, 'v0.6.0');
      expect([for (final c in range.changes) c.name], ['x', 'y']);
    });

    test(
      'a change archived only on an unmerged branch is not listed',
      () async {
        await squash('main-one', 5, proposal());
        await run(['checkout', '-b', 'side']);
        await archive('side-one', proposal());
        await run(['commit', '-m', 'feat: side (#6)']);
        await run(['checkout', 'main']);
        expect([for (final c in await changes()) c.name], ['main-one']);
        // Merged, it is listed once, under the merge commit's PR.
        await run([
          'merge',
          '--no-ff',
          'side',
          '-m',
          'Merge pull request #7 from o/side',
        ]);
        expect(
          [for (final c in await changes()) (c.name, c.pr)],
          [('main-one', 5), ('side-one', 7)],
        );
      },
    );

    test('a proposal moved into the archive counts as added', () async {
      final active = File('${dir.path}/openspec/changes/moved/proposal.md');
      await active.create(recursive: true);
      await active.writeAsString(proposal());
      await run(['add', '-A']);
      await run(['commit', '-m', 'feat: plan moved']);
      await Directory('${dir.path}/openspec/changes/archive')
          .create(recursive: true);
      await run([
        'mv',
        'openspec/changes/moved',
        'openspec/changes/archive/2026-01-05-moved',
      ]);
      await run(['commit', '-m', 'chore: archive moved (#9)']);
      expect([for (final c in await changes()) (c.name, c.pr)], [('moved', 9)]);
    });

    test('a change without a valid section is listed under Changes with its '
        'Why sentence and warned', () async {
      await squash(
        'c',
        82,
        proposal(why: 'The map ignores floors. It should not.'),
      );
      final all = await changes();
      expect(all.single.notes, isA<NoReleaseNotes>());
      final rendered = renderReleaseNotes('Sum.', all);
      expect(
        rendered.body,
        'Sum.\n\nChanges:\n- c (#82): The map ignores floors.',
      );
      expect(rendered.warnings, hasLength(1));
      expect(rendered.warnings.single, contains('c'));
      expect(rendered.warnings.single, contains('no release notes'));
    });

    test('an invalid section is warned with its first error', () async {
      await squash(
        'd',
        3,
        proposal(notes: '## Release Notes\n### Added\n- x\n'),
      );
      final rendered = renderReleaseNotes('Sum.', await changes());
      expect(rendered.warnings.single, startsWith('d: line '));
      expect(rendered.warnings.single, contains('summary is missing'));
    });

    test(
      'with no valid section the notes are the summary and Changes only',
      () async {
        await squash('c', 82, proposal(why: 'First. Second.'));
        await squash('e', null, '# P\n');
        final rendered = renderReleaseNotes('Sum.', await changes());
        expect(rendered.body, 'Sum.\n\nChanges:\n- c (#82): First.\n- e');
        expect(rendered.warnings, hasLength(2));
      },
    );

    test('valid and plain changes mix: Changes follows the items', () async {
      await squash('ok', 1, proposal(notes: section('### Changed\n- Tweak')));
      await squash('plain', 2, proposal());
      final rendered = renderReleaseNotes('Sum.', await changes());
      expect(
        rendered.body,
        'Sum.\n\nChanged:\n- Tweak (#1)\n\nChanges:\n- plain (#2): Because.',
      );
    });

    test('a direct commit without a PR is listed as written', () async {
      await squash(
        'direct',
        null,
        proposal(why: 'Why now.', notes: section('### Added\n- Thing')),
      );
      await squash('direct2', null, proposal(why: 'Why later.'));
      final all = await changes();
      expect(all.first.pr, isNull);
      expect(
        renderReleaseNotes('Sum.', all).body,
        'Sum.\n\nAdded:\n- Thing\n\nChanges:\n- direct2: Why later.',
      );
    });

    test(
      'a proposal over 64 KB falls back to its name with a warning',
      () async {
        await squash('huge', 4, proposal(why: '${'x' * 70000}.'));
        final all = await changes();
        expect(all.single.notes, isNull);
        expect(all.single.why, isNull);
        final rendered = renderReleaseNotes('Sum.', all);
        expect(rendered.body, 'Sum.\n\nChanges:\n- huge (#4)');
        expect(rendered.warnings.single, contains('huge'));
        expect(rendered.warnings.single, contains('64 KB'));
      },
    );

    test('the proposal commits are exposed for the uncovered list', () async {
      await squash('a', 1, proposal());
      final sha = await run(['rev-parse', 'HEAD']);
      await run(['commit', '--allow-empty', '-m', 'fix: other (#2)']);
      expect((await readReleaseRange(git)).proposalShas, {sha});
    });
  });

  group('readReleaseRange limits', () {
    test('more than 1000 changes are refused naming the count', () async {
      final log = [
        for (var i = 0; i < 1001; i++)
          '\x01${'a' * 40}\x01feat: c$i (#$i)\n'
              'openspec/changes/archive/2026-01-01-c$i/proposal.md\n',
      ].join('\n');
      final git = Git(_ScriptedRunner(log), Directory.current);
      await expectLater(
        readReleaseRange(git),
        throwsA(
          isA<ReleaseException>().having(
            (e) => e.message,
            'message',
            contains('1001'),
          ),
        ),
      );
    });
  });

  group('renderReleaseNotes limits', () {
    ReleaseNotes notes(String heading, int count, [String prefix = 'i']) =>
        ReleaseNotes('s', {
          heading: [
            for (var i = 0; i < count; i++) ReleaseNoteItem('$prefix$i', i),
          ],
        });

    RangeChange change(String name, int? pr, ReleaseNotesResult? notes) =>
        RangeChange(name: name, pr: pr, sha: 'x', notes: notes, why: 'W.');

    test('at most 150 items are listed, then a count of the rest', () {
      final body = renderReleaseNotes('Sum.', [
        change('a', 1, notes('added', 100)),
        change('b', 2, notes('fixed', 60, 'f')),
      ]).body;
      expect(body, contains('- i99 (#1)'));
      expect(body, contains('- f49 (#2)'));
      expect(body, isNot(contains('- f50')));
      expect(body, endsWith('- f49 (#2)\n…and 10 more items'));
    });

    test('exactly 150 items add no count', () {
      final body = renderReleaseNotes('Sum.', [
        change('a', 1, notes('added', 150)),
      ]).body;
      expect(body, isNot(contains('more items')));
    });

    test('over 100 plain changes are listed by name, then a count', () {
      final changes = [
        for (var i = 0; i < 103; i++) change('c$i', i, const NoReleaseNotes()),
      ];
      final rendered = renderReleaseNotes('Sum.', changes);
      final lines = rendered.body.split('\n');
      expect(lines.sublist(0, 3), ['Sum.', '', 'Changes:']);
      expect(lines[3], '- c0');
      expect(lines[102], '- c99');
      expect(lines.last, '…and 3 more');
      expect(lines, hasLength(104));
      expect(rendered.warnings, hasLength(103));
    });

    test('100 plain changes keep their PR and Why', () {
      final changes = [
        for (var i = 0; i < 100; i++) change('c$i', i, const NoReleaseNotes()),
      ];
      final body = renderReleaseNotes('Sum.', changes).body;
      expect(body, contains('- c0 (#0): W.'));
      expect(body, isNot(contains('more')));
    });
  });
}

/// Answers every git call with the same scripted `git log` output.
class _ScriptedRunner implements CommandRunner {
  _ScriptedRunner(this.log);

  final String log;

  @override
  Future<CommandResult> run(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
    bool stream = false,
    Map<String, String>? environment,
    Duration? timeout,
  }) async => CommandResult(0, arguments.contains('log') ? log : '', '');
}
