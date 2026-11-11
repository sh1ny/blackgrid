// Generates the raw inspection FIR template from a supplied private image.
// This tool never captures a screen. Equal inputs and geometry produce equal
// output. The default geometry is the reviewed inspection-fir-v1 crop.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:blackgrid/application/output_path_guard.dart';
import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;

import 'make_marker_template.dart' show lumaOf;

/// Recipe identifier recorded in the template metadata and artwork notice.
const firRecipe = 'inspection-fir-v1';

/// Crops a 28 by 28 grayscale template without resampling.
///
/// The image must represent the complete physical client and the crop must be
/// fully inside it. Invalid geometry throws [ArgumentError].
Uint8List cropFirTemplate(
  img.Image image, {
  required int clientWidth,
  required int clientHeight,
  required int x,
  required int y,
  required int width,
  required int height,
}) {
  if (clientWidth <= 0 ||
      clientHeight <= 0 ||
      image.width != clientWidth ||
      image.height != clientHeight) {
    throw ArgumentError('client geometry does not match the source image');
  }
  if (width != 28 ||
      height != 28 ||
      x < 0 ||
      y < 0 ||
      x > image.width - width ||
      y > image.height - height) {
    throw ArgumentError('crop must be a 28x28 rectangle inside the client');
  }
  final gray = Uint8List(width * height);
  for (var row = 0; row < height; row++) {
    for (var column = 0; column < width; column++) {
      final pixel = image.getPixel(x + column, y + row);
      gray[row * width + column] = lumaOf(
        pixel.r.toInt(),
        pixel.g.toInt(),
        pixel.b.toInt(),
      );
    }
  }
  return gray;
}

/// Runs the offline generator, returning zero only after both files are written.
int run(List<String> args, {StringSink? out, StringSink? err}) {
  final output = out ?? stdout;
  final errors = err ?? stderr;
  String? source;
  var crop = '1199,732,28,28';
  var client = '3440,1440';
  var outDir = 'assets/vision/fir';
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--crop' || arg == '--client' || arg == '--out') {
      if (++i >= args.length) {
        errors.writeln('error: $arg needs a value');
        return 2;
      }
      switch (arg) {
        case '--crop':
          crop = args[i];
        case '--client':
          client = args[i];
        case '--out':
          outDir = args[i];
      }
    } else if (arg.startsWith('-') || source != null) {
      errors.writeln('error: unexpected argument $arg');
      return 2;
    } else {
      source = arg;
    }
  }
  final cropParts = crop.split(',').map(int.tryParse).toList();
  final clientParts = client.split(',').map(int.tryParse).toList();
  if (source == null ||
      cropParts.length != 4 ||
      clientParts.length != 2 ||
      cropParts.contains(null) ||
      clientParts.contains(null)) {
    errors.writeln(
      'error: supply source, --crop x,y,width,height and --client width,height',
    );
    return 2;
  }
  final File file = File(source);
  final Uint8List bytes;
  try {
    bytes = file.readAsBytesSync();
  } on FileSystemException catch (error) {
    errors.writeln('error: source unavailable: $error');
    return 1;
  }
  final img.Image? image;
  try {
    image = img.decodeImage(bytes);
  } on Object catch (error) {
    errors.writeln('error: source image is invalid: $error');
    return 1;
  }
  if (image == null) {
    errors.writeln('error: source image cannot be decoded');
    return 1;
  }
  final x = cropParts[0]!;
  final y = cropParts[1]!;
  final width = cropParts[2]!;
  final height = cropParts[3]!;
  final clientWidth = clientParts[0]!;
  final clientHeight = clientParts[1]!;
  final Uint8List gray;
  try {
    gray = cropFirTemplate(
      image,
      clientWidth: clientWidth,
      clientHeight: clientHeight,
      x: x,
      y: y,
      width: width,
      height: height,
    );
  } on ArgumentError catch (error) {
    errors.writeln('error: $error');
    return 1;
  }
  final metadata = <String, Object>{
    'format': 1,
    'width': width,
    'height': height,
    'stride': width,
    'sourceWidth': image.width,
    'sourceHeight': image.height,
    'client': {'width': clientWidth, 'height': clientHeight},
    'crop': {'x': x, 'y': y, 'width': width, 'height': height},
    'sourceSha256': sha256.convert(bytes).toString(),
    'grayscale': 'opencv-bgr2gray-fixed-point',
    'recipe': firRecipe,
  };
  final grayPath = '$outDir/inspection_fir.gray';
  final metadataPath = '$outDir/inspection_fir.json';
  for (final path in [grayPath, metadataPath]) {
    final unsafe = unsafeOutputReason(path, protectedFiles: [source]);
    if (unsafe != null) {
      errors.writeln('error: $unsafe');
      return 1;
    }
  }
  Directory(outDir).createSync(recursive: true);
  writeBytesViaTemp(grayPath, gray);
  writeViaTemp(
    metadataPath,
    '${const JsonEncoder.withIndent('  ').convert(metadata)}\n',
  );
  output.writeln('wrote 28x28 FIR template at ($x,$y) to $outDir');
  return 0;
}

void main(List<String> args) => exit(run(args));
