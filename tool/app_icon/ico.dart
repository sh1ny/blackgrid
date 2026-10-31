// Windows icon (.ico) encoder, bounds-checked reader and validator for the
// app icon. Pure Dart (no `dart:ui`) so plain-Dart tools can import it.
//
// Layout (design D4): ICONDIR, one 16-byte ICONDIRENTRY per size in ascending
// order, then the images. Sizes below 256 px are 32-bit BGRA DIBs (40-byte
// BITMAPINFOHEADER, biHeight = 2 x size, bottom-up rows, all-zero 1-bpp AND
// mask); 256 px is a PNG.
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;

/// The square sizes, in pixels, the app icon must hold exactly once each, in
/// the ascending order [encodeIco] writes them.
const List<int> icoRequiredSizes = [16, 20, 24, 32, 40, 48, 64, 96, 128, 256];

/// SHA-256 of the `app_icon.ico` that `flutter create` generates. An icon
/// with this hash is the unmodified Flutter default.
const String flutterDefaultIcoSha256 =
    'c098d3fc85cacff98b8e69811b48e9f0d852fcee278132d794411d978869cbf8';

const _dirHeaderLength = 6;
const _dirEntryLength = 16;
const _dibHeaderLength = 40;
const _pngSignature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
const _pngRgba8ColorType = 6;

/// How an ICO image is stored.
enum IcoImageFormat {
  /// An uncompressed BITMAPINFOHEADER device-independent bitmap.
  dib,

  /// A complete PNG file.
  png,
}

/// One image of a parsed ICO.
class IcoImage {
  /// Creates an image view; use [parseIco] rather than calling this.
  IcoImage({
    required this.width,
    required this.height,
    required this.planes,
    required this.bitCount,
    required this.bytes,
  }) : format = _hasPngSignature(bytes)
           ? IcoImageFormat.png
           : IcoImageFormat.dib;

  /// Width in pixels from the directory entry (a stored 0 reads as 256).
  final int width;

  /// Height in pixels from the directory entry (a stored 0 reads as 256).
  final int height;

  /// Colour planes from the directory entry.
  final int planes;

  /// Bits per pixel from the directory entry.
  final int bitCount;

  /// Storage format, detected from the image bytes.
  final IcoImageFormat format;

  /// Exactly the bytes at the entry's offset for its size: what `rc.exe`
  /// copies into the RT_ICON resource.
  final Uint8List bytes;

  /// Planes from the DIB BITMAPINFOHEADER, or null for a PNG or short data.
  int? get dibPlanes => _dibField((d) => d.getUint16(12, Endian.little));

  /// Bits per pixel from the DIB BITMAPINFOHEADER, or null for a PNG or
  /// short data.
  int? get dibBitCount => _dibField((d) => d.getUint16(14, Endian.little));

  int? _dibField(int Function(ByteData) read) {
    if (format != IcoImageFormat.dib || bytes.length < _dibHeaderLength) {
      return null;
    }
    return read(ByteData.sublistView(bytes));
  }

  /// Decodes the image to straight (non-premultiplied) RGBA, row-major from
  /// the top, or returns null when the data is not a decodable 32-bit image
  /// of [width] x [height].
  Uint8List? decodeRgba() => switch (format) {
    IcoImageFormat.png => _decodePng(),
    IcoImageFormat.dib => _decodeDib(),
  };

  Uint8List? _decodePng() {
    try {
      final image = img.decodePng(bytes);
      if (image == null || image.width != width || image.height != height) {
        return null;
      }
      final rgba = image.convert(format: img.Format.uint8, numChannels: 4);
      return Uint8List.fromList(rgba.getBytes(order: img.ChannelOrder.rgba));
    } on Object {
      return null;
    }
  }

  Uint8List? _decodeDib() {
    final pixelBytes = width * height * 4;
    if (bytes.length < _dibHeaderLength + pixelBytes || dibBitCount != 32) {
      return null;
    }
    final out = Uint8List(pixelBytes);
    for (var y = 0; y < height; y++) {
      final src = _dibHeaderLength + (height - 1 - y) * width * 4;
      for (var x = 0; x < width; x++) {
        final s = src + x * 4;
        final o = (y * width + x) * 4;
        out[o] = bytes[s + 2];
        out[o + 1] = bytes[s + 1];
        out[o + 2] = bytes[s];
        out[o + 3] = bytes[s + 3];
      }
    }
    return out;
  }
}

/// Outcome of [parseIco].
sealed class IcoParseResult {
  const IcoParseResult();
}

/// A readable ICO directory with its images in file order.
final class IcoParsed extends IcoParseResult {
  /// Wraps [images].
  IcoParsed(List<IcoImage> images) : images = List.unmodifiable(images);

  /// The images, in directory order.
  final List<IcoImage> images;
}

/// Input that is not a readable ICO.
final class IcoUnreadable extends IcoParseResult {
  /// Creates a failure carrying [reason].
  const IcoUnreadable(this.reason);

  /// Why the bytes could not be read.
  final String reason;
}

bool _hasPngSignature(Uint8List b) {
  if (b.length < _pngSignature.length) return false;
  for (var i = 0; i < _pngSignature.length; i++) {
    if (b[i] != _pngSignature[i]) return false;
  }
  return true;
}

/// Encodes one straight-alpha RGBA raster per size in [icoRequiredSizes]
/// into an ICO. [rasters] maps size to `size * size * 4` bytes.
///
/// Throws [ArgumentError] when a size is missing or a raster has the wrong
/// length.
Uint8List encodeIco(Map<int, Uint8List> rasters) {
  final images = <Uint8List>[];
  for (final size in icoRequiredSizes) {
    final rgba = rasters[size];
    if (rgba == null) throw ArgumentError('no raster for $size px');
    if (rgba.length != size * size * 4) {
      throw ArgumentError('$size px raster must be ${size * size * 4} bytes');
    }
    images.add(size == 256 ? _encodePng(rgba, size) : _encodeDib(rgba, size));
  }
  final headerLength = _dirHeaderLength + _dirEntryLength * images.length;
  final total = images.fold<int>(headerLength, (n, i) => n + i.length);
  final out = Uint8List(total);
  final d = ByteData.sublistView(out);
  d.setUint16(2, 1, Endian.little);
  d.setUint16(4, images.length, Endian.little);
  var offset = headerLength;
  for (var i = 0; i < images.length; i++) {
    final size = icoRequiredSizes[i];
    final p = _dirHeaderLength + _dirEntryLength * i;
    out[p] = size == 256 ? 0 : size;
    out[p + 1] = size == 256 ? 0 : size;
    d.setUint16(p + 4, 1, Endian.little);
    d.setUint16(p + 6, 32, Endian.little);
    d.setUint32(p + 8, images[i].length, Endian.little);
    d.setUint32(p + 12, offset, Endian.little);
    out.setRange(offset, offset + images[i].length, images[i]);
    offset += images[i].length;
  }
  return out;
}

Uint8List _encodePng(Uint8List rgba, int size) {
  final image = img.Image.fromBytes(
    width: size,
    height: size,
    bytes: rgba.buffer,
    bytesOffset: rgba.offsetInBytes,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  return Uint8List.fromList(img.encodePng(image));
}

Uint8List _encodeDib(Uint8List rgba, int size) {
  final maskStride = ((size + 31) ~/ 32) * 4;
  final pixelBytes = size * size * 4;
  final out = Uint8List(_dibHeaderLength + pixelBytes + maskStride * size);
  final d = ByteData.sublistView(out);
  d.setUint32(0, _dibHeaderLength, Endian.little);
  d.setInt32(4, size, Endian.little);
  d.setInt32(8, size * 2, Endian.little);
  d.setUint16(12, 1, Endian.little);
  d.setUint16(14, 32, Endian.little);
  // Compression (BI_RGB) and the remaining header fields stay zero; the
  // image size field is left 0, which is valid for BI_RGB.
  for (var y = 0; y < size; y++) {
    final dst = _dibHeaderLength + (size - 1 - y) * size * 4;
    for (var x = 0; x < size; x++) {
      final s = (y * size + x) * 4;
      final o = dst + x * 4;
      out[o] = rgba[s + 2];
      out[o + 1] = rgba[s + 1];
      out[o + 2] = rgba[s];
      out[o + 3] = rgba[s + 3];
    }
  }
  return out;
}

/// Reads the ICO directory of [bytes]. Every read is bounds-checked;
/// malformed input yields [IcoUnreadable] and never throws.
IcoParseResult parseIco(Uint8List bytes) {
  if (bytes.length < _dirHeaderLength) {
    return const IcoUnreadable('shorter than the 6-byte ICO header');
  }
  final d = ByteData.sublistView(bytes);
  final reserved = d.getUint16(0, Endian.little);
  final type = d.getUint16(2, Endian.little);
  final count = d.getUint16(4, Endian.little);
  if (reserved != 0 || type != 1) {
    return IcoUnreadable('not an icon (reserved $reserved, type $type)');
  }
  if (_dirHeaderLength + _dirEntryLength * count > bytes.length) {
    return IcoUnreadable('directory of $count entries runs past the end');
  }
  final images = <IcoImage>[];
  for (var i = 0; i < count; i++) {
    final p = _dirHeaderLength + _dirEntryLength * i;
    final size = d.getUint32(p + 8, Endian.little);
    final offset = d.getUint32(p + 12, Endian.little);
    if (offset < _dirHeaderLength + _dirEntryLength * count ||
        offset + size > bytes.length) {
      return IcoUnreadable('entry $i data lies outside the file');
    }
    images.add(
      IcoImage(
        width: bytes[p] == 0 ? 256 : bytes[p],
        height: bytes[p + 1] == 0 ? 256 : bytes[p + 1],
        planes: d.getUint16(p + 4, Endian.little),
        bitCount: d.getUint16(p + 6, Endian.little),
        bytes: Uint8List.sublistView(bytes, offset, offset + size),
      ),
    );
  }
  return IcoParsed(images);
}

/// Validates [bytes] as the app icon and returns every failure; an empty
/// list means valid.
///
/// Requires exactly one square image at each of [icoRequiredSizes], all
/// 32-bit with alpha (DIB below 256 px, PNG at 256 px), none fully
/// transparent, directory planes and bit count equal to the DIB header's,
/// and not the Flutter default icon.
List<String> checkIco(Uint8List bytes) {
  final failures = <String>[];
  if (sha256.convert(bytes).toString() == flutterDefaultIcoSha256) {
    failures.add('icon is the Flutter default app_icon.ico');
  }
  final List<IcoImage> images;
  switch (parseIco(bytes)) {
    case IcoParsed(images: final parsed):
      images = parsed;
    case IcoUnreadable(:final reason):
      return [...failures, 'unreadable ICO: $reason'];
  }
  final required = icoRequiredSizes.join(', ');
  for (final size in icoRequiredSizes) {
    final n = images.where((i) => i.width == size && i.height == size).length;
    if (n == 0) {
      failures.add('missing $size px image (required sizes: $required)');
    } else if (n > 1) {
      failures.add('duplicate $size px image (required sizes: $required)');
    }
  }
  for (final image in images) {
    failures.addAll(_checkImage(image, required));
  }
  return failures;
}

List<String> _checkImage(IcoImage image, String required) {
  final w = image.width;
  final h = image.height;
  if (w != h) return ['$w x $h px image is not square'];
  if (!icoRequiredSizes.contains(w)) {
    return ['unexpected $w px image (required sizes: $required)'];
  }
  final label = '$w px';
  final failures = <String>[];
  switch (image.format) {
    case IcoImageFormat.png when w != 256:
      return ['$label image is PNG-encoded, must be an uncompressed DIB'];
    case IcoImageFormat.dib when w == 256:
      return ['$label image is a DIB, must be PNG'];
    case IcoImageFormat.png:
      failures.addAll(_checkPngHeader(image, label));
    case IcoImageFormat.dib:
      failures.addAll(_checkDibHeader(image, label));
  }
  if (failures.isNotEmpty) return failures;
  final rgba = image.decodeRgba();
  if (rgba == null) return ['$label image cannot be decoded'];
  var opaque = false;
  for (var i = 3; i < rgba.length; i += 4) {
    if (rgba[i] != 0) {
      opaque = true;
      break;
    }
  }
  if (!opaque) failures.add('$label image is fully transparent');
  return failures;
}

List<String> _checkPngHeader(IcoImage image, String label) {
  final b = image.bytes;
  // IHDR: width, height, bit depth, colour type at bytes 16..25.
  if (b.length < 26) return ['$label PNG is truncated'];
  final d = ByteData.sublistView(b);
  final failures = <String>[];
  if (d.getUint32(16) != image.width || d.getUint32(20) != image.height) {
    failures.add('$label PNG dimensions differ from the directory entry');
  }
  if (b[24] != 8 || b[25] != _pngRgba8ColorType) {
    failures.add('$label PNG must be 32-bit RGBA with alpha');
  }
  if (image.planes != 1 || image.bitCount != 32) {
    failures.add(
      '$label directory entry must be 1 plane, 32-bit '
      '(has ${image.planes} planes, ${image.bitCount}-bit)',
    );
  }
  return failures;
}

List<String> _checkDibHeader(IcoImage image, String label) {
  final b = image.bytes;
  if (b.length < _dibHeaderLength) return ['$label DIB is truncated'];
  final d = ByteData.sublistView(b);
  final w = image.width;
  final failures = <String>[];
  final headerSize = d.getUint32(0, Endian.little);
  final dibW = d.getInt32(4, Endian.little);
  final dibH = d.getInt32(8, Endian.little);
  final planes = d.getUint16(12, Endian.little);
  final bpp = d.getUint16(14, Endian.little);
  final compression = d.getUint32(16, Endian.little);
  if (headerSize != _dibHeaderLength) {
    failures.add('$label DIB header is $headerSize bytes, must be 40');
  }
  if (dibW != w || dibH != w * 2) {
    failures.add('$label DIB is $dibW x $dibH, must be $w x ${w * 2}');
  }
  if (bpp != 32) failures.add('$label image is $bpp-bit, must be 32-bit');
  if (planes != 1) failures.add('$label DIB has $planes planes, must be 1');
  if (compression != 0) {
    failures.add('$label DIB is compressed, must be uncompressed (BI_RGB)');
  }
  if (image.planes != planes) {
    failures.add(
      '$label directory planes ${image.planes} differ from DIB header '
      '$planes',
    );
  }
  if (image.bitCount != bpp) {
    failures.add(
      '$label directory bit count ${image.bitCount} differs from DIB header '
      '$bpp',
    );
  }
  final maskStride = ((w + 31) ~/ 32) * 4;
  if (b.length != _dibHeaderLength + w * w * 4 + maskStride * w) {
    failures.add('$label DIB length does not match 32-bit pixels plus mask');
  }
  return failures;
}
