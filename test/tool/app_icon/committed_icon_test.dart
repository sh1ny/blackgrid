import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/app_icon/ico.dart';
import '../../../tool/app_icon/provenance.dart';

const _candidatesDir = 'docs/design/app-icon/candidates';
const _sourceDir = 'windows/runner/resources/app_icon';
const _icoPath = 'windows/runner/resources/app_icon.ico';
const _vecPath = 'assets/app_icon/app_icon.vec';

CandidatesParsed _candidates() => switch (parseCandidatesRecord(
  File('$_candidatesDir/provenance.json').readAsStringSync(),
  fileExists: (file) => File('$_candidatesDir/$file').existsSync(),
)) {
  CandidatesParsed parsed => parsed,
  CandidatesInvalid(:final failures) => fail(failures.join('\n')),
};

SourceRecord _source() => switch (parseSourceRecord(
  File('$_sourceDir/provenance.json').readAsStringSync(),
)) {
  SourceParsed(:final record) => record,
  SourceInvalid(:final failures) => fail(failures.join('\n')),
};

Uint8List? _bytesIfPresent(String path) {
  final file = File(path);
  return file.existsSync() ? file.readAsBytesSync() : null;
}

void main() {
  test('the committed source record names the picked candidate, the pick date, author and tools', () {
    final record = _source();
    final candidates = _candidates();

    expect(record.author, isNotEmpty);
    expect(record.tools, isNotEmpty);
    expect(record.pickDate, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
    expect(checkSourceAgainstCandidates(record, candidates), isEmpty);

    // The source is the picked candidate, and the record's concept is the
    // one that candidate redraws (null for an original design).
    final picked = candidates.candidates.singleWhere(
      (c) => c.file == record.pickedCandidate,
    );
    expect(record.concept, picked.concept);
    expect(
      File('$_sourceDir/$sourceSvgName').readAsBytesSync(),
      File('$_candidatesDir/${record.pickedCandidate}').readAsBytesSync(),
      reason: 'app_icon.svg must be the picked candidate',
    );
  });

  test('each committed concept PNG has an entry naming the user, ChatGPT and 2026-10-31', () {
    final concepts = Directory('$_candidatesDir/concepts')
        .listSync()
        .whereType<File>()
        .map((f) => 'concepts/${f.uri.pathSegments.last}')
        .where((f) => f.endsWith('.png'))
        .toList();
    expect(concepts, hasLength(4));

    final entries = {for (final c in _candidates().candidates) c.file: c};
    for (final file in concepts) {
      final entry = entries[file];
      expect(entry, isNotNull, reason: '$file has no provenance entry');
      expect(entry!.author, 'Nikolay Bochev', reason: file);
      expect(entry.tools, ['ChatGPT'], reason: file);
      expect(entry.date, '2026-10-31', reason: file);
      expect(entry.concept, isNull, reason: file);
    }
  });

  test('the committed ico holds the ten sizes, 32 bpp, DIB below 256 and PNG at 256, none fully transparent', () {
    final bytes = File(_icoPath).readAsBytesSync();
    expect(checkIco(bytes), isEmpty);

    final images = switch (parseIco(bytes)) {
      IcoParsed(:final images) => images,
      IcoUnreadable(:final reason) => fail(reason),
    };
    expect([for (final i in images) i.width], icoRequiredSizes);
    for (final image in images) {
      expect(image.bitCount, 32, reason: '${image.width} px');
      expect(
        image.format,
        image.width == 256 ? IcoImageFormat.png : IcoImageFormat.dib,
        reason: '${image.width} px',
      );
    }
  });

  test(
    'the committed sources and ico match the hashes in the source record',
    () {
      expect(
        checkHashBinding(
          _source(),
          svg: File('$_sourceDir/$sourceSvgName').readAsBytesSync(),
          smallSvg: _bytesIfPresent('$_sourceDir/$smallSvgName'),
          ico: File(_icoPath).readAsBytesSync(),
          vec: _bytesIfPresent(_vecPath),
        ),
        isEmpty,
      );
    },
  );

  test(
    'the committed vec matches its recorded hash and the compiled source',
    () {
      final vec = _bytesIfPresent(_vecPath);
      expect(
        vec,
        isNotNull,
        reason: '$_vecPath is missing; run $iconBuildCommand',
      );
      final svg = File('$_sourceDir/$sourceSvgName').readAsBytesSync();

      expect(
        checkHashBinding(
          _source(),
          svg: svg,
          smallSvg: _bytesIfPresent('$_sourceDir/$smallSvgName'),
          ico: File(_icoPath).readAsBytesSync(),
          vec: vec,
        ),
        isEmpty,
      );
      expect(checkCompiledVec(svg, vec!), isEmpty);
    },
  );
}
