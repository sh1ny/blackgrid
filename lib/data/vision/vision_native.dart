import 'dart:ffi';

import 'tesseract_binding.dart';
import 'vision_image.dart';
import 'vision_primitives.dart';
import 'vision_scratch.dart';

/// OCR output as a Dart string. [truncated] is set when the engine text
/// exceeded the 64 KiB cap and was cut.
final class OcrText {
  const OcrText(this.text, {required this.truncated});

  final String text;
  final bool truncated;
}

/// A library could not be opened. Thrown by a [VisionNativeOpener] after it
/// released every library it had already opened.
final class VisionLoadException implements Exception {
  const VisionLoadException(this.path, this.osError);

  final String path;
  final String osError;

  @override
  String toString() => 'VisionLoadException($path): $osError';
}

/// One OCR engine instance (Tesseract API handle). Inputs are validated by
/// the caller; implementations throw [VisionNativeError] on engine failure.
abstract interface class VisionEngine {
  /// Returns 0 on success.
  int init(String datapath, String language, int oem);

  void setPageSegMode(int psm);

  String get initLanguages;

  int get oem;

  int get pageSegMode;

  /// Always releases the engine text and clears the engine image before
  /// returning or throwing.
  OcrText recognise(VisionImage image);

  /// Ends and deletes the engine; the caller guarantees a single call.
  void dispose();
}

/// The loaded native stack: Leptonica, Tesseract and the vision library.
abstract interface class VisionNative {
  int get visionAbi;

  String get tessVersion;

  /// Null when the engine handle could not be created.
  VisionEngine? createEngine();

  VisionPrimitives get primitives;

  /// Closes every opened library in reverse open order.
  void close();
}

/// Opens the three libraries by absolute path, in dependency order.
typedef VisionNativeOpener = VisionNative Function(
  String leptonica,
  String tesseract,
  String vision,
);

/// The default opener: real `DynamicLibrary` loads.
VisionNative openVisionNative(
  String leptonica,
  String tesseract,
  String vision,
) {
  final opened = <DynamicLibrary>[];
  void closeOpened() {
    for (final library in opened.reversed) {
      library.close();
    }
  }

  DynamicLibrary load(String path) {
    try {
      final library = DynamicLibrary.open(path);
      opened.add(library);
      return library;
    } catch (error) {
      closeOpened();
      throw VisionLoadException(path, '$error');
    }
  }

  load(leptonica);
  final tesseractLibrary = load(tesseract);
  final visionLibrary = load(vision);
  final scratch = VisionScratch();
  try {
    return _FfiVisionNative(opened, tesseractLibrary, visionLibrary, scratch);
  } catch (error) {
    // A missing export means the library is not the pinned build.
    scratch.dispose();
    closeOpened();
    throw VisionLoadException(vision, '$error');
  }
}

final class _FfiVisionNative implements VisionNative, VisionScratchOwner {
  _FfiVisionNative(
    this._libraries,
    DynamicLibrary tesseractLibrary,
    DynamicLibrary visionLibrary,
    this._scratch,
  ) : _binding = TesseractBinding(tesseractLibrary, _scratch),
      primitives = FfiVisionPrimitives(visionLibrary, _scratch),
      _abi = visionLibrary.lookupFunction<Int32 Function(), int Function()>(
        'bgv_abi',
      );

  final List<DynamicLibrary> _libraries;
  final VisionScratch _scratch;
  final TesseractBinding _binding;
  final int Function() _abi;
  bool _closed = false;

  @override
  final VisionPrimitives primitives;

  @override
  int get visionAbi => _abi();

  @override
  String get tessVersion => _binding.version();

  @override
  VisionEngine? createEngine() => _binding.createEngine();

  @override
  void trimScratch() => _scratch.trim();

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _scratch.dispose();
    for (final library in _libraries.reversed) {
      library.close();
    }
  }
}
