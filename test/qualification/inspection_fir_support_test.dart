import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

import 'support/inspection_fir.dart';

const _abcHash =
    'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';

Map<String, Object?> _frame(int index) => {
  'file': 'frame_$index.jpg',
  'clientWidth': 10,
  'clientHeight': 10,
  'imageWidth': 6,
  'imageHeight': 5,
  'imageClientOrigin': {'x': 1, 'y': 1},
  'capturedClientRect': {'left': 3, 'top': 2, 'width': 4, 'height': 3},
  'markerX': 4,
  'markerY': 3,
  'fir': index < 6 ? 'yes' : 'no',
  'sha256': _abcHash,
};

String _manifest({void Function(List<Map<String, Object?>>)? change}) {
  final frames = List.generate(12, _frame);
  change?.call(frames);
  return jsonEncode({
    'version': 1,
    'privateInputRoot': '.qualification/found-in-raid',
    'frames': frames,
  });
}

void main() {
  test('manifest preserves the twelve frozen identities and labels', () {
    const frozen = {
      'afak_fir_yes_no_medal_3440x1440.jpg': (
        'yes',
        '0d5fbdccd97c07c5b9a82c97633059325c9142cbab27953c024c868c93e2169b',
      ),
      'afak_fir_no_no_medal_3440x1440.jpg': (
        'no',
        'ba7249f3e5e710dd9f18b5be1b1f0d4b3a7fc07d0070f560c726162c46679b5a',
      ),
      'hk416_fir_yes_with_medal_3440x1440.jpg': (
        'yes',
        'f04da3b9ad345b4edbaf2722c8caa4744207941809196485c41266356449abaa',
      ),
      'hk416_fir_no_with_medal_3440x1440.jpg': (
        'no',
        '52bfe89110d8d2b24375424a33ec363c9ba5cca5890a01ab4fd413300bed9c4f',
      ),
      'hk416_fir_no_with_medal_1920x1080.jpg': (
        'no',
        'b51d3a90752f7ff9d704f9f5ac19b12699d3f64c0388d0d1e65cf85bc79366c5',
      ),
      'hk416_fir_yes_with_medal_1920x1080.jpg': (
        'yes',
        '9a65d8618ca01b3af14950d41de7c3220db034780462d902782d695f838b7995',
      ),
      'afak_fir_yes_no_medal_1920x1080.jpg': (
        'yes',
        '7ba89f520d0c59bf8874166df79f9b31062e479f82297a58bb2ae3c942bdf66e',
      ),
      'afak_fir_no_no_medal_1920x1080.jpg': (
        'no',
        'cc4c535dbf51a5ba9525f97761e89931c3d3851e13fe1cca2c5ae2d0215722f5',
      ),
      'm4a1_fir_yes_with_medal_cascade_1920x1080.jpg': (
        'yes',
        '719dbc13307751367ec6e696819bf0bd518bb77f81b52217a58ecf65a2cf90dd',
      ),
      'ak308_fir_no_with_medal_cascade_1920x1080.jpg': (
        'no',
        '09fb40d1e5442e654a0e9c5be11bdbfa822e9d2c323c1c0cb8d8de2866db6053',
      ),
      'm4a1_fir_yes_with_medal_cascade_3440x1440.jpg': (
        'yes',
        '2ac633dbbd4ccf898b10cf892286c1c94d54233e22272134a2f12b19f5a200c1',
      ),
      'ak308_fir_no_with_medal_cascade_3440x1440.jpg': (
        'no',
        '036cde104dfdb59ce22a8152ce569a64d49ca7819c299755359e725485ea90c4',
      ),
    };
    final manifest = parseFirManifest(
      File('test/fixtures/vision/fir/manifest.json').readAsStringSync(),
    );
    expect({
      for (final frame in manifest.frames)
        frame.file: (frame.expectedFir, frame.expectedHash),
    }, frozen);
    final cropped = manifest.frames.firstWhere(
      (frame) => frame.file == 'afak_fir_no_no_medal_3440x1440.jpg',
    );
    expect((cropped.clientWidth, cropped.clientHeight), (3440, 1440));
    expect((cropped.capturedWidth, cropped.capturedHeight), (3440, 1392));
    final bordered = manifest.frames.firstWhere(
      (frame) => frame.file == 'hk416_fir_yes_with_medal_1920x1080.jpg',
    );
    expect((bordered.imageWidth, bordered.imageHeight), (1922, 1082));
    expect((bordered.imageOriginX, bordered.imageOriginY), (1, 1));
    expect((bordered.capturedLeft, bordered.capturedTop), (0, 0));
  });

  test('input identity binds twelve unique files to their expected hashes', () {
    final manifest = parseFirManifest(_manifest());
    expect(manifest.frames, hasLength(12));
    expect(manifest.frames.where((f) => f.expectedFir == 'yes'), hasLength(6));
    expect(manifest.frames.where((f) => f.expectedFir == 'no'), hasLength(6));
    final frame = manifest.frames.first;
    final verified = verifyFirSource(
      frame,
      Uint8List.fromList(utf8.encode('abc')),
    );
    expect(verified.status, FirSourceStatus.verified);
    expect(verified.actualHash, _abcHash);
    expect(
      verifyFirSource(frame, Uint8List.fromList(utf8.encode('wrong'))).status,
      FirSourceStatus.hashMismatch,
    );
    expect(
      () => parseFirManifest(
        _manifest(
          change: (frames) {
            frames[1]['file'] = frames[0]['file'];
          },
        ),
      ),
      throwsFormatException,
    );
    expect(
      () => parseFirManifest(
        _manifest(
          change: (frames) {
            frames[0]['file'] = '../other.jpg';
          },
        ),
      ),
      throwsFormatException,
    );
  });

  test('captured geometry uses explicit client size and origin', () {
    final frame = parseFirManifest(_manifest()).frames.first;
    final decoded = image.Image(width: 6, height: 5);
    decoded.setPixelRgb(1, 1, 12, 34, 56);
    decoded.setPixelRgb(4, 3, 78, 90, 123);
    final normalized = normalizeFirImage(frame, decoded);
    expect((normalized.clientWidth, normalized.clientHeight), (10, 10));
    expect((normalized.left, normalized.top), (3, 2));
    expect((normalized.image.width, normalized.image.height), (4, 3));
    expect(normalized.image.bytes.sublist(0, 4), [56, 34, 12, 255]);
    expect(normalized.image.bytes.sublist(44, 48), [123, 90, 78, 255]);
    expect(
      () => normalizeFirImage(frame, image.Image(width: 5, height: 5)),
      throwsFormatException,
    );
  });

  test('bottom crop remains smaller than the declared client', () {
    final manifest = parseFirManifest(
      _manifest(
        change: (frames) {
          frames[0]['clientWidth'] = 3440;
          frames[0]['clientHeight'] = 1440;
          frames[0]['imageWidth'] = 3440;
          frames[0]['imageHeight'] = 1392;
          frames[0]['imageClientOrigin'] = {'x': 0, 'y': 0};
          frames[0]['capturedClientRect'] = {
            'left': 0,
            'top': 0,
            'width': 3440,
            'height': 1392,
          };
        },
      ),
    );
    final frame = manifest.frames.first;
    expect((frame.clientWidth, frame.clientHeight), (3440, 1440));
    expect((frame.capturedWidth, frame.capturedHeight), (3440, 1392));
  });

  test('missing source or hash never reports a completed matrix', () {
    final bytes = Uint8List.fromList(utf8.encode('abc'));
    final complete = parseFirManifest(_manifest());
    expect(firInputsComplete(checkFirInputs(complete, (_) => bytes)), isTrue);
    final missing = checkFirInputs(
      complete,
      (frame) => frame.file == 'frame_0.jpg' ? null : bytes,
    );
    expect(missing.first.identity.status, FirSourceStatus.missingSource);
    expect(firInputsComplete(missing), isFalse);
    final noHash = parseFirManifest(
      _manifest(
        change: (frames) {
          frames[0].remove('sha256');
        },
      ),
    );
    final unchecked = checkFirInputs(noHash, (_) => bytes);
    expect(unchecked.first.identity.status, FirSourceStatus.missingHash);
    expect(firInputsComplete(unchecked), isFalse);
    final wrong = checkFirInputs(
      complete,
      (frame) => frame.file == 'frame_0.jpg'
          ? Uint8List.fromList(utf8.encode('wrong'))
          : bytes,
    );
    expect(wrong.first.identity.status, FirSourceStatus.hashMismatch);
    expect(firInputsComplete(wrong), isFalse);
  });
}
