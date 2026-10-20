import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/qualification/build_corpus.dart';

const _id1 = 'rec-0001';
const _id2 = 'rec-0002';

Map<String, Object?> _frame(String id, {Object? image = 'IMAGE'}) => {
  'v': 1,
  'id': id,
  'image': image == 'IMAGE' ? '$id-full.png' : image,
  'client': {'width': 1920, 'height': 1080},
  'kind': id == _id1 ? 'targeted' : 'fullClient',
  if (id == _id1) 'cursor': {'x': 5, 'y': 6},
  'clipped': false,
  'outcome': 'accepted',
  'acceptedId': 'hint-must-not-be-used',
};

void main() {
  late Directory root;
  late String recording;
  late String labels;
  late String output;
  late StringBuffer out;
  late StringBuffer err;

  void writeFrames(List<Map<String, Object?>> frames, {String tail = ''}) {
    File('$recording/frames.jsonl')
        .writeAsStringSync('${frames.map(jsonEncode).join('\n')}\n$tail');
  }

  void writeLabels({
    String status = 'confirmed',
    List<(String, String)> cases = const [(_id1, 'item-a'), (_id2, 'reject')],
  }) {
    File(labels).writeAsStringSync(
      jsonEncode({
        'status': status,
        'cases': [
          for (final (id, expected) in cases) {'id': id, 'expected': expected},
        ],
      }),
    );
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('build-corpus-');
    recording = '${root.path}/recording';
    labels = '${root.path}/labels.json';
    output = '${root.path}/corpus';
    out = StringBuffer();
    err = StringBuffer();
    Directory(recording).createSync();
    for (final id in [_id1, _id2]) {
      File('$recording/$id-full.png').writeAsBytesSync([1, 2, 3, id.length]);
    }
    writeFrames([_frame(_id1), _frame(_id2)]);
    writeLabels();
  });

  tearDown(() => root.deleteSync(recursive: true));

  int run() => runBuildCorpus([recording, labels, output], out: out, err: err);

  bool outputUntouched() =>
      !Directory(output).existsSync() || Directory(output).listSync().isEmpty;

  test('builds corpus.json and copies the frames', () {
    expect(run(), 0, reason: '$err');

    final corpus = jsonDecode(
      File('$output/corpus.json').readAsStringSync(),
    ) as Map<String, Object?>;
    expect(corpus['cases'], [
      {
        'id': _id1,
        'image': '$_id1-full.png',
        'client': {'width': 1920, 'height': 1080},
        'kind': 'targeted',
        'cursor': {'x': 5, 'y': 6},
        'expected': 'item-a',
      },
      {
        'id': _id2,
        'image': '$_id2-full.png',
        'client': {'width': 1920, 'height': 1080},
        'kind': 'fullClient',
        'expected': 'reject',
      },
    ]);
    for (final id in [_id1, _id2]) {
      expect(
        File('$output/$id-full.png').readAsBytesSync(),
        File('$recording/$id-full.png').readAsBytesSync(),
      );
    }
  });

  test('accepts an empty existing output folder', () {
    Directory(output).createSync();
    expect(run(), 0, reason: '$err');
  });

  test('skips an unparseable final line but not an inner one', () {
    writeFrames([_frame(_id1), _frame(_id2)], tail: '{"v":1,"id":"rec-00');
    expect(run(), 0, reason: '$err');

    File('$recording/frames.jsonl').writeAsStringSync(
      '${jsonEncode(_frame(_id1))}\nnot json\n${jsonEncode(_frame(_id2))}\n',
    );
    Directory(output).deleteSync(recursive: true);
    expect(run(), 1);
    expect(err.toString(), contains('line 2'));
  });

  test('refuses labels that are not confirmed', () {
    writeLabels(status: 'proposed: pending user confirmation');

    expect(run(), 1);
    expect(err.toString(), contains('not confirmed'));
    expect(outputUntouched(), isTrue);
  });

  test('refuses a non-empty output folder', () {
    Directory(output).createSync();
    File('$output/keep.txt').writeAsStringSync('x');

    expect(run(), 1);
    expect(err.toString(), contains('not empty'));
    expect(Directory(output).listSync(), hasLength(1));
  });

  test('refuses a recorded line without a label', () {
    writeLabels(cases: [(_id1, 'item-a')]);

    expect(run(), 1);
    expect(err.toString(), contains(_id2));
    expect(outputUntouched(), isTrue);
  });

  test('refuses a label for an id not in the recording', () {
    writeLabels(
      cases: [(_id1, 'item-a'), (_id2, 'reject'), ('rec-0099', 'reject')],
    );

    expect(run(), 1);
    expect(err.toString(), contains('rec-0099'));
    expect(outputUntouched(), isTrue);
  });

  test('refuses a duplicate label id', () {
    writeLabels(cases: [(_id1, 'item-a'), (_id2, 'reject'), (_id2, 'item-b')]);

    expect(run(), 1);
    expect(err.toString(), contains('Duplicate'));
    expect(err.toString(), contains(_id2));
    expect(outputUntouched(), isTrue);
  });

  test('refuses a missing image and writes nothing', () {
    File('$recording/$_id2-full.png').deleteSync();

    expect(run(), 1);
    expect(err.toString(), contains(_id2));
    expect(outputUntouched(), isTrue);
  });

  test('refuses a null-image line and a clipped line', () {
    writeFrames([_frame(_id1), _frame(_id2, image: null)]);
    expect(run(), 1);
    expect(err.toString(), contains(_id2));

    writeFrames([
      _frame(_id1),
      {..._frame(_id2), 'clipped': true},
    ]);
    expect(run(), 1);
    expect(err.toString(), contains('clipped'));
    expect(outputUntouched(), isTrue);
  });

  test('a write that fails midway leaves no partial output', () {
    // An exclusive lock makes copying the second image fail after the first
    // one is written.
    final locked = File(
      '$recording/$_id2-full.png',
    ).openSync(mode: FileMode.append)..lockSync(FileLock.exclusive);
    addTearDown(locked.closeSync);

    expect(run(), 1);
    expect(err.toString(), contains('File error'));
    expect(Directory(output).existsSync(), isFalse);

    Directory(output).createSync();
    expect(run(), 1);
    expect(Directory(output).existsSync(), isTrue, reason: 'it was not ours');
    expect(Directory(output).listSync(), isEmpty);
  });

  test('a wrong argument count is a usage error', () {
    expect(runBuildCorpus([recording], out: out, err: err), 2);
  });
}
