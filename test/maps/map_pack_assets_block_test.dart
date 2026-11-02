import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../tool/maps/pack.dart';

const _begin = '    # BEGIN generated map pack assets (mise run maps:rebuild)';
const _end = '    # END generated map pack assets';

String _pubspec(String eol, {Iterable<String> block = const []}) => [
  'flutter:',
  '  assets:',
  '    - assets/app_icon/',
  _begin,
  ...block,
  _end,
  '    - assets/other/',
  '',
].join(eol);

Matcher _formatMessage(Matcher message) => throwsA(
  isA<FormatException>().having((e) => e.message, 'message', message),
);

void main() {
  group('replaceMapPackAssetBlock', () {
    test('markers are the documented lines', () {
      expect(mapPackAssetsBegin, _begin);
      expect(mapPackAssetsEnd, _end);
    });

    test('lines between one begin and one end are replaced exactly', () {
      final before = _pubspec('\n', block: ['    - old/a/', '    - old/b/']);
      final after = replaceMapPackAssetBlock(before, [
        '    - assets/maps/',
        '    - assets/maps/versions/x/',
      ]);
      expect(
        after,
        _pubspec(
          '\n',
          block: ['    - assets/maps/', '    - assets/maps/versions/x/'],
        ),
      );
    });

    test('an empty block and an empty replacement both work', () {
      expect(
        replaceMapPackAssetBlock(_pubspec('\n'), ['    - a/']),
        _pubspec('\n', block: ['    - a/']),
      );
      expect(
        replaceMapPackAssetBlock(_pubspec('\n', block: ['    - a/']), []),
        _pubspec('\n'),
      );
    });

    test('CRLF is preserved on inserted lines and kept elsewhere', () {
      final after = replaceMapPackAssetBlock(
        _pubspec('\r\n', block: ['    - old/']),
        ['    - new/a/', '    - new/b/'],
      );
      expect(after, _pubspec('\r\n', block: ['    - new/a/', '    - new/b/']));
      expect(after.replaceAll('\r\n', ''), isNot(contains('\n')));
    });

    test('LF text stays LF and a missing final newline is kept', () {
      final before = _pubspec('\n', block: ['    - old/']).trimRight();
      final after = replaceMapPackAssetBlock(before, ['    - new/']);
      expect(after, _pubspec('\n', block: ['    - new/']).trimRight());
    });

    test('missing duplicated or reversed markers fail naming the marker', () {
      const lines = ['    - x/'];
      String drop(String text, String marker) =>
          text.split('\n').where((line) => line != marker).join('\n');
      final ok = _pubspec('\n', block: ['    - old/']);

      expect(
        () => replaceMapPackAssetBlock(drop(ok, _begin), lines),
        _formatMessage(
          allOf(
            contains('BEGIN generated map pack assets'),
            contains('missing'),
          ),
        ),
      );
      expect(
        () => replaceMapPackAssetBlock(drop(ok, _end), lines),
        _formatMessage(
          allOf(contains('END generated map pack assets'), contains('missing')),
        ),
      );
      expect(
        () => replaceMapPackAssetBlock('$ok$_begin\n', lines),
        _formatMessage(
          allOf(
            contains('BEGIN generated map pack assets'),
            contains('more than once'),
          ),
        ),
      );
      expect(
        () => replaceMapPackAssetBlock('$ok$_end\n', lines),
        _formatMessage(
          allOf(
            contains('END generated map pack assets'),
            contains('more than once'),
          ),
        ),
      );
      final reversed = ok
          .replaceFirst(_begin, '@@')
          .replaceFirst(_end, _begin)
          .replaceFirst('@@', _end);
      expect(
        () => replaceMapPackAssetBlock(reversed, lines),
        _formatMessage(
          allOf(contains('END generated map pack assets'), contains('before')),
        ),
      );
    });
  });

  test('the committed pubspec block lists the active generation', () {
    final active = jsonDecode(
      File('assets/maps/active.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final version = active['version'] as String;
    final manifest = jsonDecode(
      File('assets/maps/versions/$version/manifest.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final pubspec = File('pubspec.yaml').readAsLinesSync();
    final block = pubspec
        .skipWhile((line) => line != mapPackAssetsBegin)
        .skip(1)
        .takeWhile((line) => line != mapPackAssetsEnd)
        .toList();
    expect(
      block,
      mapPackAssetLines('assets/maps', assetDirectoriesOf(version, manifest)),
      reason: 'pubspec.yaml is stale: run mise run maps:rebuild',
    );
  });

  group('mapPackAssetLines', () {
    test('indents each directory under the pack root', () {
      expect(mapPackAssetLines('assets/maps', ['', 'versions/x/']), [
        '    - assets/maps/',
        '    - assets/maps/versions/x/',
      ]);
    });
  });
}
