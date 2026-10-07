import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'vision_image.dart';
import 'vision_native.dart';
import 'vision_primitives.dart';

/// Largest engine text decoded; longer output is cut and flagged.
const int tesseractTextCap = 64 * 1024;

/// Opaque Tesseract API handle.
typedef TesseractHandle = Pointer<Void>;

/// The D2 Tesseract C API function set, looked up by name.
final class TesseractBinding {
  TesseractBinding(DynamicLibrary library)
    : _version = library
          .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
            'TessVersion',
          ),
      _create = library
          .lookupFunction<
            TesseractHandle Function(),
            TesseractHandle Function()
          >('TessBaseAPICreate'),
      languages = library
          .lookupFunction<
            Pointer<Utf8> Function(TesseractHandle),
            Pointer<Utf8> Function(TesseractHandle)
          >('TessBaseAPIGetInitLanguagesAsString'),
      oem = library
          .lookupFunction<
            Int32 Function(TesseractHandle),
            int Function(TesseractHandle)
          >('TessBaseAPIOem'),
      getPsm = library
          .lookupFunction<
            Int32 Function(TesseractHandle),
            int Function(TesseractHandle)
          >('TessBaseAPIGetPageSegMode'),
      init2 = library
          .lookupFunction<
            Int32 Function(
              TesseractHandle,
              Pointer<Utf8>,
              Pointer<Utf8>,
              Int32,
            ),
            int Function(TesseractHandle, Pointer<Utf8>, Pointer<Utf8>, int)
          >('TessBaseAPIInit2'),
      setPsm = library
          .lookupFunction<
            Void Function(TesseractHandle, Int32),
            void Function(TesseractHandle, int)
          >('TessBaseAPISetPageSegMode'),
      setImage = library
          .lookupFunction<
            Void Function(
              TesseractHandle,
              Pointer<Uint8>,
              Int32,
              Int32,
              Int32,
              Int32,
            ),
            void Function(TesseractHandle, Pointer<Uint8>, int, int, int, int)
          >('TessBaseAPISetImage'),
      getText = library
          .lookupFunction<
            Pointer<Utf8> Function(TesseractHandle),
            Pointer<Utf8> Function(TesseractHandle)
          >('TessBaseAPIGetUTF8Text'),
      deleteText = library
          .lookupFunction<
            Void Function(Pointer<Utf8>),
            void Function(Pointer<Utf8>)
          >('TessDeleteText'),
      clear = library
          .lookupFunction<
            Void Function(TesseractHandle),
            void Function(TesseractHandle)
          >('TessBaseAPIClear'),
      end = library
          .lookupFunction<
            Void Function(TesseractHandle),
            void Function(TesseractHandle)
          >('TessBaseAPIEnd'),
      delete = library
          .lookupFunction<
            Void Function(TesseractHandle),
            void Function(TesseractHandle)
          >('TessBaseAPIDelete');

  final Pointer<Utf8> Function() _version;
  final TesseractHandle Function() _create;
  final Pointer<Utf8> Function(TesseractHandle) languages;
  final int Function(TesseractHandle) oem;
  final int Function(TesseractHandle) getPsm;
  final int Function(TesseractHandle, Pointer<Utf8>, Pointer<Utf8>, int) init2;
  final void Function(TesseractHandle, int) setPsm;
  final void Function(TesseractHandle, Pointer<Uint8>, int, int, int, int)
  setImage;
  final Pointer<Utf8> Function(TesseractHandle) getText;
  final void Function(Pointer<Utf8>) deleteText;
  final void Function(TesseractHandle) clear;
  final void Function(TesseractHandle) end;
  final void Function(TesseractHandle) delete;

  String version() {
    final value = _version();
    return value == nullptr ? '' : value.toDartString();
  }

  /// Null when the engine could not allocate its handle.
  VisionEngine? createEngine() {
    final handle = _create();
    return handle == nullptr ? null : _FfiVisionEngine(this, handle);
  }
}

final class _FfiVisionEngine implements VisionEngine {
  _FfiVisionEngine(this._api, this._handle);

  final TesseractBinding _api;
  final TesseractHandle _handle;
  bool _disposed = false;

  @override
  int init(String datapath, String language, int oem) {
    final path = datapath.toNativeUtf8(allocator: calloc);
    final lang = language.toNativeUtf8(allocator: calloc);
    try {
      return _api.init2(_handle, path, lang, oem);
    } finally {
      calloc.free(path);
      calloc.free(lang);
    }
  }

  @override
  void setPageSegMode(int psm) => _api.setPsm(_handle, psm);

  @override
  String get initLanguages {
    final value = _api.languages(_handle);
    return value == nullptr ? '' : value.toDartString();
  }

  @override
  int get oem => _api.oem(_handle);

  @override
  int get pageSegMode => _api.getPsm(_handle);

  @override
  OcrText recognise(VisionImage image) {
    final size = image.stride * image.height;
    final buffer = calloc<Uint8>(size);
    Pointer<Utf8> text = nullptr;
    try {
      buffer
          .asTypedList(size)
          .setAll(0, Uint8List.sublistView(image.bytes, 0, size));
      _api.setImage(
        _handle,
        buffer,
        image.width,
        image.height,
        image.channels,
        image.stride,
      );
      text = _api.getText(_handle);
      if (text == nullptr) {
        throw const VisionNativeError(-5, 'OCR engine returned no text');
      }
      final bytes = text.cast<Uint8>();
      var length = 0;
      while (length < tesseractTextCap && bytes[length] != 0) {
        length++;
      }
      final truncated = length == tesseractTextCap && bytes[length] != 0;
      return OcrText(
        utf8.decode(bytes.asTypedList(length), allowMalformed: true),
        truncated: truncated,
      );
    } finally {
      if (text != nullptr) _api.deleteText(text);
      _api.clear(_handle);
      calloc.free(buffer);
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _api.end(_handle);
    _api.delete(_handle);
  }
}
