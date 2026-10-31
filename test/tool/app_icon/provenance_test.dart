import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/app_icon/provenance.dart';

Map<String, Object?> candidate({
  String file = 'concepts/01-a.png',
  String? concept,
  String? prompt = 'a prompt',
}) => {
  'file': file,
  'author': 'Someone',
  'method': 'ai-assisted',
  'tools': ['ChatGPT'],
  'date': '2026-10-31',
  'prompt': prompt,
  'concept': concept,
};

Map<String, Object?> candidatesJson([List<Map<String, Object?>>? entries]) => {
  'schemaVersion': 1,
  'candidates':
      entries ??
      [
        candidate(),
        candidate(
          file: 'vector/a.svg',
          concept: 'concepts/01-a.png',
          prompt: null,
        ),
      ],
};

CandidatesParseResult parseCandidates(
  Object? json, {
  bool Function(String)? exists,
}) =>
    parseCandidatesRecord(jsonEncode(json), fileExists: exists ?? (_) => true);

List<String> candidateFailures(Object? json, {bool Function(String)? exists}) {
  final r = parseCandidates(json, exists: exists);
  expect(r, isA<CandidatesInvalid>(), reason: '$r');
  return (r as CandidatesInvalid).failures;
}

final svgBytes = Uint8List.fromList(utf8.encode('<svg/>'));
final smallBytes = Uint8List.fromList(utf8.encode('<svg small/>'));
final icoBytes = Uint8List.fromList([1, 2, 3]);

String hashOf(Uint8List b) => sha256.convert(b).toString();

Map<String, Object?> sourceJson({bool small = false}) => {
  'schemaVersion': 1,
  'author': 'Blackgrid project',
  'method': 'ai-assisted',
  'tools': ['Claude Code'],
  'date': '2026-10-31',
  'pickedCandidate': 'vector/a.svg',
  'pickDate': '2026-11-01',
  'concept': 'concepts/01-a.png',
  'sha256': <String, Object?>{
    'app_icon.svg': hashOf(svgBytes),
    if (small) 'app_icon_small.svg': hashOf(smallBytes),
    'app_icon.ico': hashOf(icoBytes),
  },
};

SourceRecord parseSource(Map<String, Object?> json) {
  final r = parseSourceRecord(jsonEncode(json));
  expect(r, isA<SourceParsed>(), reason: '$r');
  return (r as SourceParsed).record;
}

List<String> sourceFailures(String text) {
  final r = parseSourceRecord(text);
  expect(r, isA<SourceInvalid>(), reason: '$r');
  return (r as SourceInvalid).failures;
}

void main() {
  group('candidates record', () {
    test('a well-formed record parses', () {
      final r = parseCandidates(candidatesJson());
      expect(r, isA<CandidatesParsed>(), reason: '$r');
      final entries = (r as CandidatesParsed).candidates;
      expect(entries.map((e) => e.file), ['concepts/01-a.png', 'vector/a.svg']);
      expect(entries[1].concept, 'concepts/01-a.png');
    });

    test('the real record parses with 10 entries and no failures', () {
      const dir = 'docs/design/app-icon/candidates';
      final r = parseCandidatesRecord(
        File('$dir/provenance.json').readAsStringSync(),
        fileExists: (p) => File('$dir/$p').existsSync(),
      );
      expect(r, isA<CandidatesParsed>(), reason: '$r');
      expect((r as CandidatesParsed).candidates, hasLength(10));
    });

    test('invalid JSON is a failure, not an exception', () {
      final r = parseCandidatesRecord('{nope', fileExists: (_) => true);
      expect(r, isA<CandidatesInvalid>());
    });

    test('a record entry pointing at a missing file fails naming it', () {
      final failures = candidateFailures(
        candidatesJson(),
        exists: (p) => p != 'vector/a.svg',
      );
      expect(failures.single, contains('vector/a.svg'));
      expect(failures.single, contains('missing'));
    });

    test('unknown fields are rejected at both levels', () {
      final top = candidatesJson()..['extra'] = 1;
      expect(candidateFailures(top).single, contains('"extra"'));
      final entry = candidate()..['colour'] = 'red';
      expect(
        candidateFailures(candidatesJson([entry])).single,
        contains('"colour"'),
      );
    });

    test('a missing key names the field', () {
      final entry = candidate()..remove('author');
      expect(
        candidateFailures(candidatesJson([entry])).join('\n'),
        contains('author'),
      );
    });

    test('bad method, date, schemaVersion and tools name the field', () {
      final bad = candidate()
        ..['method'] = 'magic'
        ..['date'] = '2026-02-30'
        ..['tools'] = <String>[];
      final text = candidateFailures(candidatesJson([bad])).join('\n');
      expect(text, contains('method'));
      expect(text, contains('date'));
      expect(text, contains('tools'));
      final v = candidatesJson()..['schemaVersion'] = 2;
      expect(candidateFailures(v).join('\n'), contains('schemaVersion'));
    });

    test('bad paths and duplicates fail', () {
      for (final file in [
        '../x.png',
        '/x.png',
        'concepts/x.svg',
        'vector/x.png',
        'other/x.png',
        r'concepts\x.png',
      ]) {
        expect(
          candidateFailures(candidatesJson([candidate(file: file)])).join(),
          contains('file'),
          reason: file,
        );
      }
      final dup = candidatesJson([candidate(), candidate()]);
      expect(candidateFailures(dup).join(), contains('duplicate'));
    });

    test('a concept must be a recorded concept png', () {
      for (final concept in ['concepts/other.png', 'vector/a.svg']) {
        final json = candidatesJson([
          candidate(),
          candidate(file: 'vector/a.svg', concept: concept),
        ]);
        expect(candidateFailures(json).join(), contains('concept'));
      }
    });
  });

  group('source record', () {
    test('a well-formed record parses', () {
      final record = parseSource(sourceJson());
      expect(record.pickedCandidate, 'vector/a.svg');
      expect(record.concept, 'concepts/01-a.png');
      expect(record.sha256.keys, ['app_icon.svg', 'app_icon.ico']);
    });

    test('invalid JSON is a failure, not an exception', () {
      expect(sourceFailures('[').single, contains('JSON'));
    });

    test('a source record without author or pickedCandidate fails naming '
        'the field', () {
      final json = sourceJson()
        ..remove('author')
        ..remove('pickedCandidate');
      final failures = sourceFailures(jsonEncode(json));
      expect(failures.any((f) => f.contains('author')), isTrue);
      expect(failures.any((f) => f.contains('pickedCandidate')), isTrue);
    });

    test('unknown fields are rejected, also inside sha256', () {
      final top = sourceJson()..['extra'] = 1;
      expect(sourceFailures(jsonEncode(top)).single, contains('"extra"'));
      final inner = sourceJson();
      (inner['sha256']! as Map<String, Object?>)['other.svg'] = 'x';
      expect(sourceFailures(jsonEncode(inner)).join(), contains('other.svg'));
    });

    test('bad method, dates, schemaVersion, hash and picked path fail', () {
      final json = sourceJson()
        ..['method'] = 'magic'
        ..['date'] = 'yesterday'
        ..['pickDate'] = '2026-13-01'
        ..['schemaVersion'] = 2
        ..['pickedCandidate'] = 'concepts/a.png'
        ..['sha256'] = {
          'app_icon.svg': 'ABC',
          'app_icon.ico': hashOf(icoBytes),
        };
      final text = sourceFailures(jsonEncode(json)).join('\n');
      for (final field in [
        'method',
        'date',
        'pickDate',
        'schemaVersion',
        'pickedCandidate',
        'app_icon.svg',
      ]) {
        expect(text, contains(field));
      }
    });

    test('a null concept is allowed; the sha256 icon entries are required', () {
      final r = parseSource(sourceJson()..['concept'] = null);
      expect(r.concept, isNull);
      final missing = sourceJson();
      (missing['sha256']! as Map<String, Object?>).remove('app_icon.ico');
      expect(
        sourceFailures(jsonEncode(missing)).join(),
        contains('app_icon.ico'),
      );
    });
  });

  group('hash binding', () {
    test('matching bytes give no failures', () {
      final record = parseSource(sourceJson(small: true));
      expect(
        checkHashBinding(
          record,
          svg: svgBytes,
          smallSvg: smallBytes,
          ico: icoBytes,
        ),
        isEmpty,
      );
    });

    test('a source or ico hash differing from the record fails naming the '
        'rebuild command', () {
      final record = parseSource(sourceJson());
      final failures = checkHashBinding(
        record,
        svg: Uint8List.fromList([9]),
        ico: Uint8List.fromList([8]),
      );
      expect(failures, hasLength(2));
      expect(failures[0], contains('app_icon.svg'));
      expect(failures[1], contains('app_icon.ico'));
      for (final f in failures) {
        expect(f, contains('differs from the record'));
        expect(f, contains('mise run icon:build'));
      }
    });

    test('a small svg present on only one side fails naming the file', () {
      final withSmall = parseSource(sourceJson(small: true));
      final f1 = checkHashBinding(withSmall, svg: svgBytes, ico: icoBytes);
      expect(f1.single, contains('app_icon_small.svg'));
      expect(f1.single, contains('mise run icon:build'));
      final without = parseSource(sourceJson());
      final f2 = checkHashBinding(
        without,
        svg: svgBytes,
        smallSvg: smallBytes,
        ico: icoBytes,
      );
      expect(f2.single, contains('app_icon_small.svg'));
      expect(f2.single, contains('mise run icon:build'));
    });
  });

  group('rendering', () {
    test('updates hashes, keeps human fields, 2-space indent and newline', () {
      final record = parseSource(sourceJson());
      final svg = Uint8List.fromList([7]);
      final ico = Uint8List.fromList([6]);
      final text = renderSourceRecord(
        record,
        svg: svg,
        smallSvg: smallBytes,
        ico: ico,
      );
      expect(text.endsWith('}\n'), isTrue);
      expect(text, contains('\n  "author": "Blackgrid project",'));
      final round = parseSource(jsonDecode(text) as Map<String, Object?>);
      expect(round.pickedCandidate, record.pickedCandidate);
      expect(round.sha256['app_icon.svg'], hashOf(svg));
      expect(round.sha256['app_icon_small.svg'], hashOf(smallBytes));
      expect(
        checkHashBinding(round, svg: svg, smallSvg: smallBytes, ico: ico),
        isEmpty,
      );
    });
  });

  group('cross-record validation', () {
    CandidatesParsed candidates() =>
        parseCandidates(candidatesJson()) as CandidatesParsed;

    test('a picked candidate and concept that are recorded pass', () {
      expect(
        checkSourceAgainstCandidates(parseSource(sourceJson()), candidates()),
        isEmpty,
      );
    });

    test('an unrecorded pickedCandidate or concept fails naming it', () {
      final record = parseSource(
        sourceJson()
          ..['pickedCandidate'] = 'vector/zzz.svg'
          ..['concept'] = 'concepts/zzz.png',
      );
      final text = checkSourceAgainstCandidates(record, candidates()).join();
      expect(text, contains('vector/zzz.svg'));
      expect(text, contains('concepts/zzz.png'));
    });
  });
}
