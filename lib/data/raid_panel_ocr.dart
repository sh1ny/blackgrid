import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../domain/raid_panel_text_parser.dart';

/// One independent Map-owned Windows OCR engine on a dedicated isolate. At
/// most one saved image is admitted, with no unbounded queue or Scanner
/// initialization.
class RaidPanelOcr {
  RaidPanelOcr({String? nativeLibraryPath})
    : nativeLibraryPath =
          nativeLibraryPath ??
          '${File(Platform.resolvedExecutable).parent.path}/blackgrid_panel_ocr.dll';

  final String nativeLibraryPath;
  final _responses = ReceivePort();
  final _errors = ReceivePort();
  final _exits = ReceivePort();
  final _started = Completer<void>();
  final _stopped = Completer<void>();
  SendPort? _requests;
  Future<void>? _initialization;
  Future<void>? _closing;
  Completer<RaidPanelEvidence>? _active;
  bool _closed = false;
  bool _admitting = false;
  bool _shutdownAcknowledged = false;
  String? _workerFailure;

  Future<void> _start() async {
    if (!Platform.isWindows) {
      _workerFailure =
          'Saved-panel native OCR is available only on Windows x64.';
      return;
    }
    _responses.listen((dynamic message) {
      if (message is SendPort) {
        _requests = message;
        if (!_started.isCompleted) {
          _started.complete();
        }
      } else if (message is RaidPanelEvidence) {
        final active = _active;
        _active = null;
        if (active != null && !active.isCompleted) {
          active.complete(message);
        }
      } else if (message == 'closed') {
        _shutdownAcknowledged = true;
        if (!_stopped.isCompleted) {
          _stopped.complete();
        }
      }
    });
    _errors.listen((dynamic message) {
      _workerFailure = 'Native OCR worker failed: $message';
      final active = _active;
      _active = null;
      active?.complete(
        RaidPanelEvidence(state: RaidPanelState.error, message: _workerFailure),
      );
      if (!_started.isCompleted) {
        _started.complete();
      }
    });
    _exits.listen((dynamic _) {
      if (!_shutdownAcknowledged) {
        _workerFailure ??=
            'Native OCR worker exited before releasing owned resources.';
      }
      final active = _active;
      _active = null;
      active?.complete(
        RaidPanelEvidence(state: RaidPanelState.error, message: _workerFailure),
      );
      if (!_started.isCompleted) {
        _started.complete();
      }
      if (!_stopped.isCompleted) {
        _stopped.complete();
      }
    });
    try {
      await Isolate.spawn(
        _workerMain,
        <Object>[_responses.sendPort, nativeLibraryPath],
        onError: _errors.sendPort,
        onExit: _exits.sendPort,
        errorsAreFatal: true,
      );
      await _started.future;
    } catch (error) {
      _workerFailure = 'Cannot start native OCR worker: $error';
    }
  }

  Future<RaidPanelEvidence> recognize(Uint8List imageBytes) async {
    if (_closed) {
      return RaidPanelEvidence(
        state: RaidPanelState.unavailable,
        message: 'Saved-panel OCR is closed.',
      );
    }
    if (imageBytes.isEmpty || imageBytes.length > 64 * 1024 * 1024) {
      return RaidPanelEvidence(
        state: RaidPanelState.error,
        message: 'Saved-image input is empty or exceeds 64 MiB.',
      );
    }
    if (_admitting) {
      return RaidPanelEvidence(
        state: RaidPanelState.unavailable,
        message: 'Saved-panel OCR worker is busy; no image was queued.',
      );
    }
    _admitting = true;
    try {
      await (_initialization ??= _start());
      if (_closed || _requests == null || _workerFailure != null) {
        return RaidPanelEvidence(
          state: RaidPanelState.unavailable,
          message: _workerFailure ?? 'Saved-panel OCR is closed.',
        );
      }
      final request = Completer<RaidPanelEvidence>();
      _active = request;
      _requests!.send(TransferableTypedData.fromList([imageBytes]));
      final evidence = await request.future;
      return _closed
          ? RaidPanelEvidence(
              state: RaidPanelState.unavailable,
              message: 'OCR completed after shutdown; publication invalidated.',
            )
          : evidence;
    } finally {
      _admitting = false;
    }
  }

  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    _closed = true;
    await _initialization;
    if (_requests != null && !_stopped.isCompleted) {
      // The worker processes close only after native recognition has drained.
      // Never kill an isolate or release its engine while native code uses it.
      _requests!.send('close');
      await _stopped.future;
    }
    _responses.close();
    _errors.close();
    _exits.close();
    if (_requests != null && !_shutdownAcknowledged) {
      throw StateError(
        _workerFailure ?? 'Native OCR shutdown was not acknowledged.',
      );
    }
  }
}

final class _NativeWord extends Struct {
  @Int32()
  external int left;
  @Int32()
  external int top;
  @Int32()
  external int right;
  @Int32()
  external int bottom;
  @Int32()
  external int line;
  external Pointer<Uint8> text;
}

final class _NativeEngine {
  _NativeEngine(String path) {
    if (!File(path).isAbsolute) {
      throw StateError(
        'Native OCR requires an explicit absolute app-local path.',
      );
    }
    final dll = File(path);
    final binding = File('$path.sha256');
    if (!dll.existsSync() || !binding.existsSync()) {
      throw StateError('App-local native OCR library/hash binding is missing.');
    }
    if (sha256.convert(dll.readAsBytesSync()).toString() !=
        binding.readAsStringSync().trim()) {
      throw StateError(
        'App-local native OCR library hash does not match its build binding.',
      );
    }
    final library = DynamicLibrary.open(path);
    _library = library;
    try {
      final abi = library.lookupFunction<Uint32 Function(), int Function()>(
        'bg_ocr_abi',
      );
      if (abi() != 2) {
        throw StateError('Native OCR ABI mismatch.');
      }
      alloc = library
          .lookupFunction<
            Pointer<Void> Function(Uint32),
            Pointer<Void> Function(int)
          >('bg_ocr_alloc');
      free = library
          .lookupFunction<
            Void Function(Pointer<Void>),
            void Function(Pointer<Void>)
          >('bg_ocr_free');
      destroy = library
          .lookupFunction<
            Void Function(Pointer<Void>),
            void Function(Pointer<Void>)
          >('bg_ocr_destroy');
      clear = library
          .lookupFunction<
            Void Function(Pointer<Void>),
            void Function(Pointer<Void>)
          >('bg_ocr_clear');
      decode = library
          .lookupFunction<
            Int32 Function(Pointer<Void>, Pointer<Uint8>, Uint32),
            int Function(Pointer<Void>, Pointer<Uint8>, int)
          >('bg_ocr_decode');
      recognize = library
          .lookupFunction<
            Int32 Function(
              Pointer<Void>,
              Int32,
              Int32,
              Int32,
              Int32,
              Int32,
              Int32,
            ),
            int Function(Pointer<Void>, int, int, int, int, int, int)
          >('bg_ocr_recognize');
      width = library
          .lookupFunction<
            Int32 Function(Pointer<Void>),
            int Function(Pointer<Void>)
          >('bg_ocr_width');
      height = library
          .lookupFunction<
            Int32 Function(Pointer<Void>),
            int Function(Pointer<Void>)
          >('bg_ocr_height');
      count = library
          .lookupFunction<
            Int32 Function(Pointer<Void>),
            int Function(Pointer<Void>)
          >('bg_ocr_count');
      word = library
          .lookupFunction<
            Int32 Function(Pointer<Void>, Int32, Pointer<_NativeWord>),
            int Function(Pointer<Void>, int, Pointer<_NativeWord>)
          >('bg_ocr_word');
      text = library
          .lookupFunction<
            Pointer<Uint8> Function(Pointer<Void>),
            Pointer<Uint8> Function(Pointer<Void>)
          >('bg_ocr_text');
      rgb = library
          .lookupFunction<
            Uint32 Function(Pointer<Void>, Int32, Int32),
            int Function(Pointer<Void>, int, int)
          >('bg_ocr_rgb');
      final create = library
          .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
            'bg_ocr_create',
          );
      handle = create();
      if (handle == nullptr) {
        throw StateError(
          'Windows OCR has no installed English or user-profile recognizer language.',
        );
      }
      _word = alloc(sizeOf<_NativeWord>()).cast<_NativeWord>();
      if (_word == nullptr) {
        close();
        throw StateError('OCR result allocation failed.');
      }
    } catch (_) {
      close();
      rethrow;
    }
  }
  DynamicLibrary? _library;
  late final Pointer<Void> Function(int) alloc;
  late final void Function(Pointer<Void>) free;
  late final void Function(Pointer<Void>) destroy;
  late final void Function(Pointer<Void>) clear;
  late final int Function(Pointer<Void>, Pointer<Uint8>, int) decode;
  late final int Function(Pointer<Void>, int, int, int, int, int, int)
  recognize;
  late final int Function(Pointer<Void>) width;
  late final int Function(Pointer<Void>) height;
  late final int Function(Pointer<Void>) count;
  late final int Function(Pointer<Void>, int, Pointer<_NativeWord>) word;
  late final Pointer<Uint8> Function(Pointer<Void>) text;
  late final int Function(Pointer<Void>, int, int) rgb;
  Pointer<Void> handle = nullptr;
  Pointer<_NativeWord> _word = nullptr;

  String _utf8(Pointer<Uint8> value, int limit) {
    if (value == nullptr) {
      throw StateError('Null native OCR text.');
    }
    final bytes = <int>[];
    for (var j = 0; j <= limit; j++) {
      final byte = value[j];
      if (byte == 0) return utf8.decode(bytes, allowMalformed: true);
      bytes.add(byte);
    }
    throw StateError('Unterminated native OCR text.');
  }

  /// Engine text and its recognized lines for one panel region.
  ({String text, List<String> lines}) _recognize(
    RaidPanelBox box,
    double scale, {
    required bool enhance,
  }) {
    final code = recognize(
      handle,
      box.left,
      box.top,
      box.right,
      box.bottom,
      (scale * 1000).round().clamp(250, 4000),
      enhance ? 1 : 0,
    );
    if (code == 5) {
      throw StateError('Windows OCR recognizer language is unavailable.');
    }
    if (code != 0) {
      throw StateError('Panel OCR failed (native status $code).');
    }
    final length = count(handle);
    if (length < 0 || length > 4096) {
      throw StateError('Malformed native OCR word count.');
    }
    final lines = <int, List<String>>{};
    for (var i = 0; i < length; i++) {
      if (word(handle, i, _word) != 0) {
        throw StateError('Cannot read native OCR word.');
      }
      final value = _word.ref;
      (lines[value.line] ??= []).add(_utf8(value.text, 2048));
    }
    final ordered = lines.keys.toList()..sort();
    return (
      text: _utf8(text(handle), 64 * 1024),
      lines: [for (final key in ordered) lines[key]!.join(' ')],
    );
  }

  ({String text, List<String> lines}) _pass(
    RaidPanelProfile profile,
    RaidPanelBox box,
  ) {
    final primary = _recognize(box, profile.ocrScaleFactor, enhance: false);
    final enhanced = _recognize(box, profile.ocrScaleFactor, enhance: true);
    return (
      text: mergeRaidOcrText(primary.text, enhanced.text),
      lines: mergeRaidOcrLines(primary.lines, enhanced.lines),
    );
  }

  RaidPanelEvidence read(Uint8List bytes) {
    final buffer = alloc(bytes.length).cast<Uint8>();
    if (buffer == nullptr) {
      throw StateError('Saved-image native allocation failed.');
    }
    try {
      buffer.asTypedList(bytes.length).setAll(0, bytes);
      final status = decode(handle, buffer, bytes.length);
      if (status != 0) {
        throw StateError('Image decode failed (native status $status).');
      }
      final w = width(handle), h = height(handle);
      if (w <= 0 ||
          h <= 0 ||
          w > 8192 ||
          h > 8192 ||
          w * h > 24 * 1024 * 1024) {
        throw StateError('Decoded image bounds are invalid.');
      }
      int pixel(int x, int y) => rgb(handle, x, y);
      final profile = RaidPanelProfile.forSize(w, h);
      if (!profile.detect(w, h, pixel)) {
        return RaidPanelEvidence(
          state: RaidPanelState.missing,
          message: 'No exfil panel detected (${profile.name} profile).',
        );
      }
      const parser = RaidPanelTextParser();
      final names = RaidPanelNames();
      final bottom = profile.panelBottom(w, h, pixel);
      final panel = profile.crop(w, h, bottom);
      final first = _pass(profile, panel);
      var rawText = first.text;
      parser.parse(first.text, first.lines, names);
      // A short read may have cut the panel; retry over a taller region.
      if (names.count <= 3) {
        final tallBottom = bottom > (h * 0.68).toInt()
            ? bottom
            : (h * 0.68).toInt();
        if (tallBottom > bottom + 8) {
          final tall = _pass(profile, profile.crop(w, h, tallBottom));
          rawText = mergeRaidOcrText(rawText, tall.text);
          parser.parse(tall.text, tall.lines, names);
        }
      }
      return RaidPanelEvidence(
        state: RaidPanelState.recognized,
        extractNames: names.extracts,
        transitNames: names.transits,
        rawText: rawText,
        message: 'Exfil panel read (${profile.name} profile).',
        panel: panel,
      );
    } finally {
      clear(handle);
      free(buffer.cast());
    }
  }

  void close() {
    if (handle != nullptr) {
      destroy(handle);
      handle = nullptr;
    }
    if (_word != nullptr) {
      free(_word.cast());
      _word = nullptr;
    }
    final library = _library;
    _library = null;
    library?.close();
  }
}

void _workerMain(List<Object> configuration) {
  final responses = configuration[0] as SendPort;
  final requests = ReceivePort();
  _NativeEngine? engine;
  String? unavailable;
  try {
    engine = _NativeEngine(configuration[1] as String);
  } catch (error) {
    unavailable = 'App-local saved-panel OCR unavailable: $error';
  }
  responses.send(requests.sendPort);
  requests.listen((dynamic request) {
    if (request == 'close') {
      engine?.close();
      requests.close();
      responses.send('closed');
      return;
    }
    if (request is! TransferableTypedData) {
      return;
    }
    if (engine == null) {
      responses.send(
        RaidPanelEvidence(
          state: RaidPanelState.unavailable,
          message: unavailable,
        ),
      );
      return;
    }
    try {
      responses.send(engine.read(request.materialize().asUint8List()));
    } catch (error) {
      responses.send(
        RaidPanelEvidence(
          state: RaidPanelState.error,
          message: 'Saved-image recognition failed: $error',
        ),
      );
    }
  });
}
